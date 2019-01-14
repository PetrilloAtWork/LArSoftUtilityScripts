#!/usr/bin/env bash
#
# Runs ctest from the proper directory.
#

hasLArSoftScriptUtils >& /dev/null || source "${LARSCRIPTDIR}/larsoft_scriptutils.sh"
mustNotBeSourced || return 1

SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"
CWD="$(pwd)"

SwitchScript="${SCRIPTDIR}/larswitch.sh"


###############################################################################

[[ -n "$SETUP_CMAKE" ]] || FATAL 1 "It appears compilation environment is not set up."

BuildDir="$CWD"
if ! isMRBBuildArea "$BuildDir" ; then
	DBGN 2 "Current directory is not a building area."
	if isMRBSourceArea "$BuildDir" ; then
		DBGN 2 "Current directory is in source area: switching."
		BuildDir="$($SwitchScript --tobuild ${DEBUG:+--debug="$DEBUG"})"
		[[ $? == 0 ]] || BuildDir="$CWD"
	elif isMRBWorkingArea "$BuildDir" ; then
		DBGN 2 "Current directory is in a working area."
		BuildDir="$($SwitchScript --tobuild ${DEBUG:+--debug="$DEBUG"})"
		[[ $? == 0 ]] || BuildDir="$CWD"
	fi
fi

[[ -d "$BuildDir" ]] || FATAL 3 "Can't find the build directory (thought it was: '${BuildDir}')"

DBG "Detected build directory: '${BuildDir}'"
declare -a Command
Command=( 'ctest' )
declare -i NCPUs
NCPUs=$(DetectNCPUs)
[[ $? == 0 ]] && Command=( "${Command[@]}" "-j$((NCPUs + 1))" )

# execute
cd "$BuildDir" && "${Command[@]}" "$@"
res=$?

echo "  (tested from '$(pwd)')"
[[ $res == 0 ]] || hline "TEST ERROR(S)!!!  (exit code: ${res})"
exit $res

