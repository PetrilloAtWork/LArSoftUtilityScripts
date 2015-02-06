#!/bin/bash
#
# Prints the previous or next directory in the list of GIT repositories
# in the MRB working area.
#

# guard against sourcing
[[ "$BASH_SOURCE" != "$0" ]] && echo "Don't source this script." >&2 && exit 1

################################################################################
SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.0"
CWD="$(pwd)"

function help() {
	cat <<-EOH
	Prints the previous or next directory in the list of GIT repositories
	in the MRB working area.
	
	Usage:  ${SCRIPTNAME}  [options] [Skip]
	
	It goes Skip repositories ahead, and prints the full path of the repository.
	
	Options
	--basedir=BASEDIR [${MRB_SOURCE:-.}]
	    directory where the repositories are (typically \$MRB_SOURCE),
	    or the directory with a 'srcs' subdirectory holding the repositories
	--list , -l
	    prints all the repositories in their order
	--noerror
	    in case of error, still returns the current directory
	--verbose
	    prints somehow more output
	--version
	    prints the script version and exits
	--help , -h , -?
	    prints this help message
	
	EOH
} # help()


function isFlagSet() {
	local VarName="$1"
	[[ -n "${!VarName//0}" ]]
} # isFlagSet()

function isFlagUnset() {
	local VarName="$1"
	[[ -z "${!VarName//0}" ]]
} # isFlagUnset()

function STDERR() { echo "$*" >&2 ; }
function ERROR() { STDERR "ERROR: $@" ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()
function LASTFATAL() {
	local Code="$?"
	[[ "$Code" != 0 ]] && FATAL "$Code""$@"
} # LASTFATAL()


function StringLength() { echo "${#1}" ; }


function isInteger() {
	local Value="$1"
	[[ "$Value" =~ ^[+-]*[0-9]+$ ]]
} # isInteger()


###############################################################################

function StepRepository() {
	# Usage:  StepRepository  BaseDir [Step]
	# Detects which is the current repository (in the current working directory)
	# and prints the next repository by Step steps (can be negative, default: 0)
	local BaseDir="$1"
	local Step="$2"
	declare -i ExitCode=0
	
	# and where are we?
	CurrentRepoPath="${CWD#$BaseDir}"
	if [[ "$CurrentRepoPath" != "$CWD" ]]; then
		CurrentRepoPath="${CurrentRepoPath##/}"
		# this is the alleged repository name
		CurrentRepo="${CurrentRepoPath%%/*}"
		# which repository is that?
		for (( iCurrentRepo = 0; iCurrentRepo < NRepositories ; ++iCurrentRepo )); do
			[[ "${Repositories[iCurrentRepo]}" == "$CurrentRepo" ]] && break
		done
		if [[ "$iCurrentRepo" == "$NRepositories" ]]; then # none of them!
			iCurrentRepo=''
			CurrentRepo=''
		fi
	else
		iCurrentRepo=''
		CurrentRepo=''
	fi
	
	declare -i DestRepo
	if [[ -z "$CurrentRepo" ]]; then
		STDERR "I can't understand in which repository I am now."
		ExitCode=1
		if [[ -z "$Step" ]]; then
			iDestRepo=0
		elif [[ $Step -ge 0 ]]; then
			iDestRepo="$Step"
		else
			iDestRepo="$(($NRepositories + $Step))"
		fi
	else
		[[ -z "$Step" ]] && Step=1
		iDestRepo=$((iCurrentRepo + Step))
	fi
	
	if [[ "$iDestRepo" -lt 0 ]]; then
		ERROR "We can't go before the first repository ('${Repositories[0]}')"
		ExitCode=1
		iDestRepo=0
	elif [[ "$iDestRepo" -ge $NRepositories ]]; then
		ERROR "We can't go past the last repository ('${Repositories[$NRepositories-1]}')"
		ExitCode=1
		iDestRepo=$(($NRepositories-1))
	fi

	if [[ $ExitCode == 0 ]] || isFlagSet NoError ; then
		echo "${Repositories[iDestRepo]}"
	fi
	return $ExitCode
} # StepRepository()


function FindRepository() {
	# Usage:  FindRepository  BaseDir RepoNameHint
	local BaseDir="$1"
	local RepoNameHint="$2"
	local -a RepoMatches
	local RepoName
	for RepoName in "${Repositories[@]}" ; do
		[[ "$RepoName" =~ $RepoNameHint ]] || continue
		RepoMatches=( "${RepoMatches[@]}" "$RepoName" )
	done
	
	local -i NMatches="${#RepoMatches[@]}" 
	if [[ $NMatches -gt 1 ]] && isFlagUnset NoError ; then
		ERROR "${NMatches} matching repositories found: ${RepoMatches[@]}"
		return 1
	elif [[ $NMatches == 0 ]] && isFlagUnset NoError ; then
		ERROR "No repository matching: '${RepoNameHint}'"
		return 1
	else
		echo "${RepoMatches[0]}"
	fi
	
#	FATAL 1 "Repository by name not implemented yet"
	return 0
} # FindRepository()


################################################################################

# default parameters
declare -i VERBOSE=0
declare -i DoList=0
declare BaseDir="$MRB_SOURCE"

###
### parameters parsing
###
declare -i NoMoreOptions=0
declare -a Arguments
declare -i nArguments=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1  ;;
			( '--version' | '-V' ) DoVersion=1  ;;
			( '--verbose' | '-v' ) VERBOSE=1  ;;
			
			( '--noerror' ) NoError=1 ;;
			( '--basedir='* ) BaseDir="${Param#-*=}" ;;
			( '--list' | '-l' ) DoList=1 ;;
			
			### other stuff
			( '-' | '--' )
				NoMoreOptions=1
				;;
			( * )
				isInteger "$Param" || FATAL 1 "Unrecognized script option '${Param}'"
				Arguments[nArguments++]="$Param"
				;;
		esac
	else
		NoMoreOptions=1
		Arguments[nArguments++]="$Param"
	fi
done

if isFlagSet DoHelp || [[ $nArguments -gt 1 ]]; then
	help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	exit $?
fi

if isFlagSet DoVersion ; then
	echo "${SCRIPTNAME} version ${SCRIPTVERSION}"
	exit 0
fi


# collect the GIT repositories in the base directory
declare -a Repositories
declare -i NRepositories=0
for Dir in "${BaseDir:+${BaseDir%/}/}"* ; do
	[[ -d "$Dir" ]] || continue
	[[ -d "${Dir}/.git" ]] || continue
	Repositories[NRepositories++]="$(basename "$Dir")"
done
if [[ "$NRepositories" == 0 ]] && [[ -d "${BaseDir}/srcs" ]]; then
	BaseDir="${BaseDir:+${BaseDir%/}/}srcs"
	for Dir in "${BaseDir:+${BaseDir}/}"* ; do
		[[ -d "$Dir" ]] || continue
		[[ -d "${Dir}/.git" ]] || continue
		Repositories[NRepositories++]="$(basename "$Dir")"
	done
fi

if isFlagSet DoList ; then
	isFlagSet VERBOSE && echo "I've found ${NRepositories} repositories in '${BaseDir:-the current directory}':"
	declare -i Padding="$(StringLength "$((NRepositories-1))")"
	for (( iRepo = 0 ; iRepo < $NRepositories ; ++iRepo )); do
		Repository="${Repositories[iRepo]}"
		isFlagSet VERBOSE && printf '[%*d] ' "$Padding" "$iRepo"
		echo "$Repository"
	done
	exit
fi

declare DestRepo
declare -i ExitCode=0
if [[ -n "${Arguments[0]}" ]]; then
	if isInteger "${Arguments[0]}" ; then
		DestRepo="$(StepRepository "$BaseDir" "${Arguments[0]}" )"
		ExitCode=$?
	else
		DestRepo="$(FindRepository "$BaseDir" "${Arguments[0]}" )"
		ExitCode=$?
	fi
else
	DestRepo="$(StepRepository "$BaseDir" )"
	ExitCode=$?
fi


if [[ $ExitCode == 0 ]] || isFlagSet NoError ; then
	echo "${BaseDir:+${BaseDir%/}/}${DestRepo}"
fi

exit $ExitCode
