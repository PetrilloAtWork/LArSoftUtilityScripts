#!/usr/bin/env bash
#
# Prints the previous or next directory in the list of GIT repositories
# in the MRB working area.
#
# Changes:
# 20160810 (petrillo@fna.gov) [v1.2]
#   using larsoft_scriptutils.sh
# 20161115 (petrillo@fna.gov) [v1.3]
#   added the possibility to directly enter subdirectories
#

hasLArSoftScriptUtils >& /dev/null || source "${LARSCRIPTDIR}/larsoft_scriptutils.sh"
mustNotBeSourced || return 1


################################################################################
SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.3"
CWD="$(pwd)"

function help() {
	cat <<-EOH
	Prints the previous or next directory in the list of GIT repositories
	in the MRB working area.
	
	Usage:  ${SCRIPTNAME}  [options] [Skip]
	
	It goes Skip repositories ahead, and prints the full path of the repository.
	If Skip is a repository name (as opposed to a number), it is entered directly.
	If the current directory is in the build area, the destination directory will
	also be in the build area; otherwise it will be in the source area.
	If Skip is a path, the first element of the path is assumed to be the
	repository name and the rest a subpath to enter inside the repository.
	
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
	--debug[=LEVEL]
	    enable debug messages
	--version
	    prints the script version and exits
	--help , -h , -?
	    prints this help message
	
	EOH
} # help()


###############################################################################

function StringLength() { echo "${#1}" ; }


###############################################################################

function StepRepository() {
	# Usage:  StepRepository  BaseDir [Step]
	# Detects which is the current repository (in the current working directory)
	# and prints the next repository by Step steps (can be negative, default: 0)
	local BaseDir="$1"
	local Step="$2"
	local -i ExitCode=0
	
	local -i iCurrentRepo
	local CurrentRepo
	# and where are we?
	CurrentRepoPath="${CWD#$BaseDir}"
	if [[ "$CurrentRepoPath" != "$CWD" ]]; then
		CurrentRepoPath="${CurrentRepoPath##/}"
		DBG "We are in '${CurrentRepoPath}' under '${BaseDir}'"
		# this is the alleged repository name
		CurrentRepo="${CurrentRepoPath%%/*}"
		if [[ -z "$CurrentRepo" ]]; then
			# this means we are exactly in the base directory
			DBG "We are in the base directory '${BaseDir}'"
		else
			# which repository is that?
			for (( iCurrentRepo = 0; iCurrentRepo < NRepositories ; ++iCurrentRepo )); do
				[[ "${Repositories[iCurrentRepo]}" == "$CurrentRepo" ]] && break
			done
			if [[ "$iCurrentRepo" == "$NRepositories" ]]; then # none of them!
				iCurrentRepo=''
				CurrentRepo=''
				DBG "No repository matching '${CurrentRepo}'."
			else
				DBG "Repository #${iCurrentRepo} ('${CurrentRepo}') matched."
			fi
		fi
	else
		DBG "Current directory '${CWD}' not matching the base dir '${BaseDir}'"
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
			iDestRepo="$((Step - 1))"
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
	local RepoNamePattern="${RepoNameHint%%/*}"
	local -a RepoMatches
	local RepoName
	for RepoName in "${Repositories[@]}" ; do
		[[ "$RepoName" =~ $RepoNamePattern ]] || continue
		if [[ "$RepoName" == "$RepoNamePattern" ]]; then
			# jackpot! perfect match, forget anything else
			RepoMatches=( "$RepoName" )
			break
		fi
		RepoMatches=( "${RepoMatches[@]}" "$RepoName" )
	done
	
	local -i NMatches="${#RepoMatches[@]}" 
	if [[ $NMatches -gt 1 ]] && isFlagUnset NoError ; then
		ERROR "${NMatches} matching repositories found: ${RepoMatches[@]}"
		return 1
	elif [[ $NMatches == 0 ]] && isFlagUnset NoError ; then
		ERROR "No repository matching: '${RepoNamePattern}'"
		return 1
	fi
	
	local SubDir="${RepoNameHint#${RepoNamePattern}}"
	echo "${RepoMatches[0]}${SubDir}"
	
	return 0
} # FindRepository()


################################################################################

# default parameters
declare -i VERBOSE=0
declare -i DoList=0

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
			( '--debug' ) DEBUG=1 ;;
			( '--debug='* ) DEBUG="${Param#--*=}" ;;
			
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

declare Mode
Mode="$(DetectMRBLocation "$(pwd)")"
LASTFATAL 1 "I can't detect in which area of MRB I am."
if [[ "$Mode" == 'TOP' ]]; then
	ERROR "We are in the main MRB working area. Jumping to source area."
	cd "$MRB_SOURCE"
	Mode='SOURCE'
fi

declare MRBVarName="MRB_${Mode}"
declare BaseDir="${!MRBVarName}"
[[ -d "$BaseDir" ]] || FATAL 3 "The detected base directory '${BaseDir}' for mode ${Mode} does not exist!"

case "$Mode" in
	( 'SOURCE' )
		TestDirFunc='isGITrepository'
		;;
	( 'BUILDDIR' )
		TestDirFunc='isCMakeBuildDir'
		;;
	( 'INSTALL' )
		TestDirFunc='isUPSpackageDir'
		;;
	( * )
		FATAL 1 "Internal error: unsupported mode '${Mode}'"
esac


# collect the GIT repositories in the base directory
declare -a Repositories
declare -i NRepositories=0
for Dir in "${BaseDir:+${BaseDir%/}/}"* ; do
	[[ -d "$Dir" ]] || continue
	"$TestDirFunc" "$Dir" || continue
	Repositories[NRepositories++]="$(basename "$Dir")"
done
DBG "Found ${NRepositories} repositories: ${Repositories[@]}"
[[ "$NRepositories" == 0 ]] && FATAL 2 "No repositories found in '${BaseDir}'"



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

