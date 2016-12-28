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
# 20160826 (petrillo@fnal.gov) [v1.2] 
#   updated to use larsoft_scriptutils
#
#


hasLArSoftScriptUtils >& /dev/null || source "${LARSCRIPTDIR}/larsoft_scriptutils.sh"
mustNotBeSourced || return 1


SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"
CWD="$(pwd)"

declare -r SCRIPTVERSION="1.2"


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
	
	echo -e "$(ApplyMessageColor "$ColorVarName" "${PaddingLeft}  ${Content}  ${PaddingRight}")"
} # PrintHeader()


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
	
	if ! isCompilableDirectory "$Dir" ; then
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
		isCompilableDirectory "$SubPath" || continue
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
  
  # try to jump to build area
  if ! isCompilableDirectory "$BaseDir" && ! isMRBBuildArea "$BaseDir" ; then
  DBGN 1 "'${BaseDir}': not a compilable directory, and not under MRB_BUILDDIR"
    if isMRBSourceArea "$BaseDir" ; then
      DBGN 2 "'${BaseDir}': source area! try to jump to build area"
      RelPath="$(SubpathTo "$BaseDir" "$MRB_SOURCE")"
      if [[ $? == 0 ]]; then
        BaseDir="${MRB_BUILDDIR}${RelPath:+/${RelPath}}"
        DBGN 1 "jumping => '${BaseDir}'"
      else
        DBGN 2 "Failed. Let's go on and crash."
      fi
    fi
  fi
  
  
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
