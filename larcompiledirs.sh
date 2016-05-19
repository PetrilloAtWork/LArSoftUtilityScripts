#!/usr/bin/env bash
#
# Tries to make all the subdirectories of the current directory.
# Run with '--help' for usage instructions.
#
# Change log:
# 20150615 (petrillo@fnal.gov)
#   original version (not numbered)
# 20160519 (petrillo@fnal.gov) [v1.1] 
#   added ability to descend, debug message infrastructure, and a version number
#
#

declare -r SCRIPTNAME="$(basename "$0")"
declare -r SCRIPTVERSION="1.1"

declare -r ANSICYAN="\e[1;36m"
declare -r ANSIYELLOW="\e[1;33m"
declare -r ANSIRED="\e[1;31m"
declare -r ANSIGREEN="\e[32m"
declare -r ANSIRESET="\e[0m"

declare -r DEBUGCOLOR="$ANSIGREEN"
declare -r WARNCOLOR="$ANSIYELLOW"
declare -r ERRORCOLOR="$ANSIRED"
declare -r FATALCOLOR="$ANSIRED"

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
	--deep, -r
	    on failure, descend into the failing directory and attempt a subdirectory
	    by subdirectory compilation
	--makeopt=OPTION
	    passes an option to the make program
	-- , -
	    the following arguments are all to be passed to \`make\`
	--version , -V
	    prints a version number and exits
	--help , -h , -?
	    prints this help
	
	EOH
} # Help()

###############################################################################
function STDERR() { echo "$*" >&2 ; }

function ApplyColor() {
	local ColorName="$1"
	shift
	if [[ -n "$ColorName" ]]; then
		echo -e "${!ColorName}${*}${ANSIRESET}"
	else
		echo "$*"
	fi
} # ApplyColor()

function STDERRCOLOR() { STDERR "$(ApplyColor "$@")" ; }

function ERROR() { STDERRCOLOR ERRORCOLOR "ERROR: $*" ; }

function FATAL() {
	local Code="$1"
	shift
	STDERRCOLOR FATALCOLOR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()

function LASTFATAL() {
	local -i Code="$?"
	[[ $Code == 0 ]] || FATAL "$Code" "$@"
} # LASTFATAL()

function isDebugging() {
	local -i Level="${1:-1}"
	[[ -n "$DEBUG" ]] && [[ $DEBUG -ge $Level ]]
} # isDebugging()

function DBGN() {
	local Level="$1"
	shift
	isDebugging "$Level" && STDERRCOLOR DEBUGCOLOR "DBG[${Level}]| $*"
} # DBGN()

function DBG() { DBGN 1 "$@" ; }

function isFlagSet() {
	local VarName="$1"
	[[ -n "${!VarName//0}" ]]
} # isFlagSet()

function isFlagUnset() {
	local VarName="$1"
	[[ -z "${!VarName//0}" ]]
} # isFlagUnset()

function anyFlagSet() {
	local FlagName
	for FlagName in "$@" ; do
		isFlagSet "$FlagName" && return 0
	done
	return 1
} # anyFlagSet()

function Max() {
	[[ $# == 0 ]] && return 1
	local -i max="$1"
	local -i elem
	for elem in "$@" ; do
		[[ $elem -gt $max ]] && max="$elem"
	done
	echo "$max"
	return 0
} # Max()

###############################################################################


function PrintHeader() {
	# Prints a header with the specified color
	# Usage: PrintHeader ColorVarName Message [FieldWidth]
	local -r ColorVarName="$1"
	shift
	local -r Message="$1"
	shift
	local -r Level="$1"
	shift
	local -ir FieldWidth="${1:-${COLUMNS:-80}}"
	
	local HighlightColor="${!ColorVarName}"
	local ResetColor="$ANSIRESET"
	[[ -z "$HighlightColor" ]] && ResetColor=""
	
	local -r LeftPad="- * "
	local -r RightPad=" * -"
	
	local Content
	if isFlagSet Level ; then
		Content+="["
		local i
		for (( i = 0 ; i < Level ; ++i )); do
			Content+=">"
		done
		Content+="]  $Message"
	else
		Content="$Message"
	fi
	
	
	local -ir ContentLength="${#Content}"
	local -i HalfField=$(((FieldWidth - ContentLength) / 2))
	
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
	
	echo -e "${HighlightColor}${PaddingLeft}  ${Content}  ${PaddingRight}${ResetColor}"
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


function CanBeCompiled() {
	local DirPath="${1:-.}"
	HasMakefile "$DirPath" || return 1
	return 0
} # CanBeCompiled()

function CanCompileDirectory() {
	local DirPath="${1:-.}"
	CanBeCompiled "$DirPath" || return 1
	HasMakefile "$DirPath" || return 1
	return 0
} # CanCompileDirectory()


function CompileSingleDir() {
	# Compiles in the specified directory
	local DirPath="${1:-.}"
	shift
	local -a Targets=( "$@" )
	
	(
		cd "$DirPath"
		make "${MakeOpts[@]}" -- "${Targets[@]}"
	)
	local -i res=$?
	
	return $res
} # CompileSingleDir()


function CompileAllDirs() {
	# Compiles in the specified directory, optionally descending into subdirectories
	# If there is no makefile in the directory or if it's not a directory at all,
	# nothing happens and a "success" exit code is returned.
	# Otherwise, the compilation is attempted with `make`
	# and the return code is the one from make.
	local -i Level="$1"
	local Dir="$2"
	
	if ! CanCompileDirectory "$Dir" ; then
		ERROR "Make system in use does not support per-directory make${Dir:+" under '${Dir}'"}: skipped (treated as failure!)"
		PrintHeader ERRORCOLOR "Compilation${Dir:+" in '${Dir}'"} skipped" "$Level"
		Failures[${#Failures[@]}]="${Dir:-.}"
		let ++NFailures[Level]
		return 1
	fi

	PrintHeader ANSICYAN "${Dir:-"current direcrory"}"
	CompileSingleDir "$Dir" "${MakeTargets[@]}"
	local -i res=$?
	
	if [[ $res == 0 ]]; then
		Successes[${#Successes[@]}]="${Dir:-.}"
		let ++NSuccesses[Level]
		return 0
	fi
	
	# we failed!
	Failures[${#Failures[@]}]="${Dir:-.}"
	let ++NFailures[Level]
	PrintHeader ERRORCOLOR "Compilation${Dir:+" in '${Dir}'"} failed (code: ${res})" "$Level"
	if isFlagUnset DescendOnFailure ; then
		return 1
	fi
	
	# let's descend and see...
	local -a SubDirs
	local -i NSubDirs=0
	local SubDir
	while read SubDir ; do
		local SubPath="${Dir:+${Dir%/}/}${SubDir}"
		DBGN 4 "Considering: '${SubPath}'"
		[[ -d "$SubPath" ]] || continue
		CanBeCompiled "$SubPath" || continue
		SubDirs[NSubDirs++]="$SubPath"
	done < <( ls "${Dir:-.}" )
	
	if [[ $NSubDirs == 0 ]]; then
		DBG "No suitable subdirectories found: no descent."
		return 1
	fi
	
	PrintHeader WARNCOLOR "descending${Dir:+" into '${Dir}'"} (${NSubDirs} subdirectories)" "$Level"
	local -i NLocalFailures=0
	for SubDir in "${SubDirs[@]}" ; do
		CompileAllDirs $((Level + 1)) "$SubDir"
		res=$?
		let NLocalFailures+=$res
	done
	return $((NLocalFailures + 1))
} # CompileAllDirs()


###############################################################################

###
### parameter parsing
###

declare -a MakeTargets
declare -i NMakeTargets=0
declare -a BaseDirs
declare -a MakeOpts=( ${MAKEOPTS} )
declare -i NBaseDirs=0
declare -i NoMoreOptions=0
declare -a WrongParameters

for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	
	if isFlagUnset NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '-h' | '--help' | '-?' ) DoHelp=1 ;;
			( '--version' | '-V' ) DoVersion=1 ;;
			( '--basedir='* ) BaseDirs[NBaseDirs++]="${Param#--*=}" ;;
			( '--keepgoing' | '--keep-going' | '-k' ) KeepGoing=1 ;;
			( '--deep' | '-r' ) DescendOnFailure=1 ;;
			( '--makeopt='* ) MakeOpts=( "${MakeOpts[@]}" "${Param#--*=}" ) ;;
			( '--debug='* ) DEBUG="${Param#--*=}" ;;
			( '--debug' | '-d' ) DEBUG=1 ;;
			( '-' | '--' )   NoMoreOptions=1 ;;
			( * )
				WrongParameters=( "${WrongParameters[@]}" "$iParam" )
		esac
	else
		MakeTargets[NMakeTargets++]="$Param"
	fi
	
done

isFlagSet DoVersion && echo "${SCRIPTNAME} version ${SCRIPTVERSION}"
isFlagSet DoHelp && Help

anyFlagSet DoHelp DoVersion && exit

if [[ "${#WrongParameters[@]}" -gt 0 ]]; then
	for iParam in "${WrongParameters[@]}" ; do
		ERROR "Unrecognised option #${iParam}: '${!iParam}'"
	done
	exit 1
fi

if isFlagSet DescendOnFailure && isFlagUnset KeepGoing ; then
	FATAL 1 "When descending into subdirectory on failure ('--deep' option), keep-going option ('--keep-koing') must be explicitly set."
fi

[[ $NBaseDirs == 0 ]] && BaseDirs=( "" )

###
### execute!
###
declare -i res
declare -a Successes
declare -ia NSuccesses=( 0 )
declare -a Failures
declare -ia NFailures=( 0 )

for BaseDir in "${BaseDirs[@]}" ; do
	CompileAllDirs 0 "$BaseDir"
	res=$?
	[[ $res != 0 ]] && isFlagUnset KeepGoing && break
done

declare -i NLevels="$(Max ${#NFailures[@]} ${#NSuccesses[@]} )"

declare -i NDirs=$((NSuccesses + NFailures))
if [[ $NFailures == 0 ]]; then
	echo "All ${NDirs} directories successfully compiled."
else
	if [[ "$NLevels" == 1 ]]; then
		echo "${NSuccesses}/${NDirs} directories successfully compiled, ${NFailures} compilations failed:"
	else
		echo "Descended down to ${NLevels} levenls because of failures:"
		for (( iLevel = 0 ; iLevel < $NLevels ; ++iLevel )); do
			echo "  - level $((iLevel+1)): ${NSuccesses[iLevel]:-0} succeeded, ${NFailures[iLevel]:-0} failed"
		done
		echo "Failures reported in:"
	fi
	for Failure in "${Failures[@]}" ; do
		echo "$Failure"
	done
fi
if isFlagSet KeepGoing ; then
	exit ${#Failures[@]}
else
	exit $res
fi


