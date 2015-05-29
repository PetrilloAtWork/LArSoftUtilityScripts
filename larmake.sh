#!/bin/bash
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

function isDirUnder() {
	# Usage:  isDirUnder Dir ParentDir
	# returns success if Dir is a subdirectory of ParentDir
	local Dir="$1"
	local ParentDir="$2"
	[[ -z "$ParentDir" ]] && return 1
	
	local FullDir="$(readlink -f "$Dir")"
	[[ -z "$FullDir" ]] && return 1
	while [[ ! "$FullDir" -ef "$ParentDir" ]]; do
		[[ "$FullDir" == '/' ]] && return 1
		FullDir="$(dirname "$FullDir")"
	done
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


###############################################################################


BuildDir="$CWD"
if ! isBuildArea "$BuildDir" ; then
	if isSourceArea "$BuildDir" ; then
		BuildDir="$($SwitchScript)"
		[[ $? == 0 ]] || BuildDir="$CWD"
	fi
fi

[[ -d "$BuildDir" ]] || FATAL 3 "Can't find the build directory (thought it was: '${BuildDir}')"

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

