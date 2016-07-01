#!/usr/bin/env bash
#
# Runs make (or equivalent) from the proper directory.
#

SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"
CWD="$(pwd)"

SwitchScript="${SCRIPTDIR}/larswitch.sh"

function STDERR() { echo "$*" >&2 ; }
function ERROR() { STDERR "ERROR: $*" ; }
function FATAL() {
	local -i Code="$1"
	shift
	STDERR "FATAL (${Code}): $*"
	exit $Code
} # FATAL()

function isDebugging() {
	local Level="${1:-1}"
	[[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge "$Level" ]]
} # isDebugging()

function DBGN() {
	local -i Level="$1"
	isDebugging "$Level" || return
	shift
	STDERR "DBG[${Level}] $*"
} # DBGN()
function DBG() { DBGN 1 "$@" ; }


function isDirUnder() {
	# Usage:  isDirUnder Dir ParentDir
	# returns success if Dir is a subdirectory of ParentDir
	local Dir="$1"
	local ParentDir="$2"
	[[ -z "$ParentDir" ]] && return 1
	
	DBGN 2 "Is '${Dir}' under '${ParentDir}'?"
	local FullDir="$Dir"
	[[ "${FullDir:0:1}" != '/' ]] && FullDir="${CWD}${Dir:+/${Dir}}"
	while [[ ! "$FullDir" -ef "$ParentDir" ]]; do
		[[ "$FullDir" == '/' ]] && return 1
		FullDir="$(dirname "$FullDir")"
		DBGN 3 "  - now check: '${FullDir}'"
	done
	DBGN 2 "  => YES!"
	return 0
} # isDirUnder()

function isMakeDirectory() {
	local Dir="$1"
	[[ -r "${Dir}/Makefile" ]] || [[ -r "${Dir}/GNUmakefile" ]]
} # isMakeDirectory()

function isNinjaDirectory() {
	local Dir="$1"
	# a ninja directory is under the build area:
	isBuildArea "$Dir" || return 1
	# the top build directory has a build.ninja file
	[[ -r "${MRB_BUILDDIR}/build.ninja" ]] || return 1
	# that's it, we are in business
	return 0
} # isNinjaDirectory()


function isBuildDirectory() {
	local Dir="$1"
	isMakeDirectory "$1" || isNinjaDirectory "$1"
} # isBuildDirectory()

function isSourceArea() {
	local Dir="$1"
	[[ -n "$MRB_SOURCE" ]] && isDirUnder "$Dir" "$MRB_SOURCE"
} # isSourceArea()

function isBuildArea() {
	local Dir="$1"
	[[ -n "$MRB_BUILDDIR" ]] && isDirUnder "$Dir" "$MRB_BUILDDIR"
} # isBuildArea()

function isWorkingArea() {
	local Dir="$1"
	[[ -n "$MRB_TOP" ]] && isDirUnder "$Dir" "$MRB_TOP"
} # isWorkingArea()


###############################################################################


BuildDir="$CWD"
if ! isBuildArea "$BuildDir" ; then
	DBGN 2 "Current directory is not a building area."
	if isSourceArea "$BuildDir" ; then
		DBGN 2 "Current directory is in source area: switching."
		BuildDir="$($SwitchScript --tobuild ${DEBUG:+--debug="$DEBUG"})"
		[[ $? == 0 ]] || BuildDir="$CWD"
	elif isWorkingArea "$BuildDir" ; then
		DBGN 2 "Current directory is in a working area."
		BuildDir="$($SwitchScript --tobuild ${DEBUG:+--debug="$DEBUG"})"
		[[ $? == 0 ]] || BuildDir="$CWD"
	fi
fi

[[ -d "$BuildDir" ]] || FATAL 3 "Can't find the build directory (thought it was: '${BuildDir}')"

DBG "Detected build directory: '${BuildDir}'"
declare -a Command
if isMakeDirectory "$BuildDir" ; then
	Command=( 'make' )
elif isNinjaDirectory "$BuildDir" ; then
	Command=( 'ninja' )
	BuildDir="$MRB_BUILDDIR"
else
	Command=( )
fi

[[ "${#Command[@]}" == 0 ]] && FATAL 1 "Can't understand which build system is under '${BuildDir}'"

# execute
echo "Building from directory '${BuildDir}'"
cd "$BuildDir"
"${Command[@]}" "$@"

