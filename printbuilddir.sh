#!/usr/bin/env bash
#
# Prints the build directory matching the current directory
# (stays here if it's make, goes to BUILD_DIR if it's ninja,
# uses larswitch if it's in source tree)
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
	# TODO
	return 1
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
	true
elif isNinjaDirectory "$BuildDir" ; then
	BuildDir="$MRB_BUILDDIR"
else
	FATAL 1 "Can't understand which build system is under '${BuildDir}'"
fi

# execute
echo "$BuildDir"

