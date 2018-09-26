#!/usr/bin/env bash
#
# Runs make (or equivalent) from the proper directory.
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
if isMakeDirectory "$BuildDir" ; then
	Command=( 'make' )
	declare -i NCPUs
	NCPUs=$(DetectNCPUs)
	[[ $? == 0 ]] && Command=( "${Command[@]}" "-j$((NCPUs + 1))" )
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

