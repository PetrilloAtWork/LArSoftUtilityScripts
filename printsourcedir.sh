#!/bin/bash
#
# Prints the source directory matching the current directory
# (stays here if it's in sourec tree, make,
# uses larswitch if it's in build tree)
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

function isGITrepository() {
	# Usage:  isGITrepository Dir 
	# returns success if Dir is contained in a GIT repository
	local Dir="${1:-"$(pwd)"}"
	
	local FullDir="$(readlink -f "$Dir")"
	[[ -z "$FullDir" ]] && return 1
	while [[ ! -d "${FullDir}/.git" ]]; do
		[[ "$FullDir" == '/' ]] && return 1
		FullDir="$(dirname "$FullDir")"
	done
	return 0
} # isGITrepository()

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


SourceDir="$CWD"
if ! isSourceArea "$SourceDir" ; then
	if isBuildArea "$SourceDir" ; then
		SourceDir="$($SwitchScript)"
		[[ $? == 0 ]] || SourceDir="$CWD"
	fi
fi

[[ -d "$SourceDir" ]] || FATAL 3 "Can't find the source directory (thought it was: '${SourceDir}')"

isGITrepository "$SourceDir" || FATAL 1 "Can't find the source directory (thought it '${SourceDir}', but it's not GIT)"

# execute
echo "$SourceDir"

