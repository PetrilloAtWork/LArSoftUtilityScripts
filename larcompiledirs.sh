#!/bin/bash
#
# Tries to make all the subdirectories of the current directory.
# Stops at the first failure.
#
# Usage:  larcompiledirs.sh  [Targets]
#

declare SCRIPTNAME="$(basename "$0")"

declare -r ANSICYAN="\e[1;36m"
declare -r ANSIRED="\e[1;31m"
declare -r ANSIRESET="\e[0m"

###############################################################################
function Help() {
	cat <<-EOH
	Runs \`make\` on all the subdirectories of the specified directory.
	
	Usage:  ${SCRIPTNAME}  [options] [-|--] [MakeTargets ...]
	
	All the "MakeTargets" arguments are passed to \`make\` (whether they are
	actual targets or make options).
	
	Options:
	--basedir=BASEDIR
	    uses this as a base directory (default is current one; can be specified
	    multiple times)
	--keep-going, -k
	    instead of stopping at the first failure, it tries all the directories
	    and reports the list of failing directories; the exit code is the
	    number of failures
	    Note that this is not the '-k' option of \`make\`; to pass that one,
	    write it after the options escape '--'
	-- , -
	    the following arguments are all to be passed to \`make\`
	--help , -h , -?
	    prints this help
	
	EOH
} # Help()

###############################################################################
function STDERR() { echo "$*" >&2 ; }

function ERROR() { STDERR "ERROR: $*" ; }

function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()

function LASTFATAL() {
	local -i Code="$?"
	[[ $Code == 0 ]] || FATAL "$Code" "$@"
} # LASTFATAL()

function isFlagSet() {
	local VarName="$1"
	[[ -n "${!VarName//0}" ]]
} # isFlagSet()

function isFlagUnset() {
	local VarName="$1"
	[[ -z "${!VarName//0}" ]]
} # isFlagUnset()

###############################################################################


function PrintHeader() {
	# Prints a header with the specified color
	# Usage: PrintHeader ColorVarName Message [FieldWidth]
	local -r ColorVarName="$1"
	local -r Message="$2"
	local -ir FieldWidth="${3:-${COLUMNS:-80}}"
	
	local HighlightColor="${!ColorVarName}"
	local ResetColor="$ANSIRESET"
	[[ -z "$HighlightColor" ]] && ResetColor=""
	
	local -r LeftPad="- * "
	local -r RightPad=" * -"
	
	local -ir MessageLength="${#Message}"
	local -i HalfField=$(((FieldWidth - MessageLength) / 2))
	
	[[ $HalfField -lt 0 ]] && HalfField=0
	
	local -i iPad
	local PaddingLeft
	for (( iPad = $(( HalfField / ${#LeftPad} )) ; iPad > 0 ; --iPad )); do
		PaddingLeft+="$LeftPad"
	done
	
	local PaddingRight
	for (( iPad = $(( HalfField / ${#RightPad} )) ; iPad > 0 ; --iPad )); do
		PaddingRight+="$RightPad"
	done
	
	echo -e "${HighlightColor}${PaddingLeft}  ${Message}  ${PaddingRight}${ResetColor}"
} # PrintHeader()


function HasMakefile() {
	local -r Dir="$1"
	[[ -d "$Dir" ]] || return 3
	local MakefileName
	for MakefileName in Makefile GNUmakefile ; do
		[[ -r "${Dir}/${MakefileName}" ]] && return 0
	done
	return 1
} # HasMakefile()


function CompileDir() {
	# Compiles in the specified directory
	# If there is no makefile in the directory or if it's not a directory at all,
	# nothing happens and a "success" exit code is returned.
	# Otherwise, the compilation is attempted with `make`
	# and the return code is the one from make.
	local DirPath="$1"
	shift
	local -a Targets=( "$@" )
	
	HasMakefile "$DirPath" || return 0
	
	local DirName="$(basename "$DirPath")"
	
	PrintHeader ANSICYAN "$DirName"
	
	(
		cd "$DirPath"
		make "${Targets[@]}"
	)
	local -i res=$?
	
	[[ $res == 0 ]] || PrintHeader ANSIRED "Compilation in '${DirName}' failed (code: ${res})"
	
	return $res
} # CompileDir()


###############################################################################

###
### parameter parsing
###

declare -a MakeTargets
declare -i NMakeTargets=0
declare -a BaseDirs
declare -i NBaseDirs=0
declare -i NoMoreOptions=0
declare -a WrongParameters

for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	
	if isFlagUnset NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '-h' | '--help' | '-?' ) DoHelp=1 ;;
			( '--basedir='* ) BaseDirs[NBaseDirs++]="${Param#--*=}" ;;
			( '--keepgoing' | '--keep-going' | '-k' ) KeepGoing=1 ;;
			( '-' | '--' )   NoMoreOptions=1 ;;
			( * )
				WrongParameters=( "${WrongParameters[@]}" "$iParam" )
		esac
	else
		MakeTargets[NMakeTargets++]="$Param"
	fi
	
done

if isFlagSet DoHelp ; then
	Help
	exit
fi

if [[ "${#WrongParameters[@]}" -gt 0 ]]; then
	for iParam in "${WrongParameters[@]}" ; do
		ERROR "Unrecognised option #${iParam}: '${!iParam}'"
	done
	exit 1
fi

[[ $NBaseDirs == 0 ]] && BaseDirs=( "" )

###
### execute!
###
declare -i res
declare -i NDirs=0
declare -a Successes
declare -i NSuccesses=0
declare -a Failures
declare -i NFailures=0
for BaseDir in "${BaseDirs[@]}" ; do
	TargetDirs=( "${BaseDir:+${BaseDir%/}/}"* )
	declare -i NTargetDirs=${#TargetDirs[@]}
	
	[[ -n "$BaseDir" ]] && PrintHeader ANSIGREEN "Compiling ${NTargetDirs} directories under '${BaseDir}'"
	for (( iDir = 0; iDir < $NTargetDirs ; ++iDir )); do
		Dir="${TargetDirs[iDir]}"
		
		CompileDir "$Dir" "${MakeTargets[@]}"
		res=$?
		
		if [[ $res == 0 ]]; then
			Successes[NSuccesses++]="$Dir"
		else
			Failures[NFailures++]="$Dir"
			ERROR "Compilation of directory '${Dir}' [$((iDir+1))/${NTargetDirs}] failed [code=${res}]"
			isFlagUnset KeepGoing && break 2
		fi
	done
done
declare -i NDirs=$((NSuccesses + NFailures))
if [[ $NFailures == 0 ]]; then
	echo "All ${NDirs} directories successfully compiled."
else
	echo "${NSuccesses}/${NDirs} directories successfully compiled, ${NFailures} compilations failed:"
	for Failure in "${Failures[@]}" ; do
		echo "$Failure"
	done
fi
if isFlagSet KeepGoing ; then
	exit ${#Failures[@]}
else
	exit $res
fi


