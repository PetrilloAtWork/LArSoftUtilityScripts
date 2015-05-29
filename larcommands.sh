#!/bin/bash
#
# Distributes a command to all the GIT repositories.
#
# Changes:
# 20150304 (petrillo@fnal.gov) [v1.1]
#   started tracking versions;
#   added --version, --ifhasbranch, --ifcurrentbranch options
# 20150415 (petrillo@fnal.gov) [v1.2]
#   added --only and --skip options
# 20150415 (petrillo@fnal.gov) [v1.3]
#   added --command option
#

SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"
SCRIPTVERSION="1.3"

: ${BASEDIR:="$(dirname "$(readlink -f "$SCRIPTDIR")")"}

: ${PACKAGENAMETAG:="%PACKAGENAME%"}

function help() {
	cat <<-EOH
	Executes a command in all the GIT repositories.
	
	Usage:  ${SCRIPTNAME} [options] [--] command ...
	
	All the command words are substituted for the tags as required by the
	options. For each tag (TAGNAME), the string "%TAGNAME%" (or the one in
	TAGKEY_TAGNAME) is replaced by the value of the variable with
	name TAGVALUE_TAGNAME.
	The exit code is the number of failed commands.
	
	Special variable provided:
	- PACKAGENAME: the name of the current package
	
	Command specification options:
	--tag=TAGNAME
	--tags=TAGNAME[,TAGNAME...]
	    add a tag to the list of tags
	--git
	    adds "git" as command if it's not the first word of the command already
	
	Repository selection options:
	--ifcurrentbranch=BRANCHNAME
	    acts only on repositories whose current branch is BRANCHNAME; it can be
	    specified more than once, in which case the operation will be performed
	    if the current branch is any one of the chosen branches
	--ifhasbranch=BRANCHNAME
	    similar to '--ifcurrentbranch' above, performs the action only if the
	    repository has one of the specified branches
	--only=REGEX
	    operates only on the repositories whose name matches the specified REGEX
	--skip=REGEX
	    skips the repositories whose name matches the specified REGEX
	
	Command line parsing options:
	--command[=NARGS] command arg arg ...
	    the next NARGS (default 0) plus one arguments are added to the command
	--autodetect-command
	    interprets the arguments as part of the command, starting at the first
	    unknown option or at the first non-option argument; by default,
	    if an option is unsupported an error is printed
	
	Other options:
	--compact[=MODE]
	    do not write the git command; out the output of the command according to
	    MODE:
	    'prepend' (default): "[%PACKAGENAME%] OUTPUT"
	    'append': "OUTPUT [%PACKAGENAME%]"
	--quiet , -q
	    does not write package and command
	--fake , --dry-run , -n
	    just prints the command that would be executed
	--stop-on-error , -S
	    the execution is interrupted when a command fails (exit code non-zero);
	    the exit code is the one of the failure
	--debug[=LEVEL]
	    increase verbosity level
	--version , -V
	    prints the version of this script and exits
	--help , -h , -?
	    prints this help message
	
	EOH
} # help()


function PrintVersion() {
	local RealName="$(basename "$(readlink "$0")")"
	[[ "$RealName" == "$SCRIPTNAME" ]] && RealName=''
	echo "${SCRIPTNAME} v. ${SCRIPTVERSION}${RealName:+" (based on ${RealName})"}"
} # PrintVersion()


function isFlagSet() { local VarName="$1" ; [[ -n "${!VarName//0}" ]]; }

function STDERR() { echo "$*" >&2 ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()

function isDebugging() {
	local -i Level="${1:-1}"
	[[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge $Level ]]
} # isDebugging()

function DBGN() {
	local -i Level="$1"
	shift
	isDebugging "$Level" && STDERR "DBG[${Level}]| $*"
} # DBGN()
function DBG() { DBGN 1 "$@" ; }


function anyInList() {
	# Usage:  anyInList  Sep Key [Key...] Sep [List Items...]
	
	DBGN 4 "${FUNCNAME[0]} ${@}"
	
	# build the list of keys
	local Sep="$1"
	shift
	local -a Keys
	while [[ $# -gt 0 ]] && [[ "$1" != "$Sep" ]]; do
		Keys=( "${Keys[@]}" "$1" )
		shift
	done
	shift # the first argument was a separator
	
	DBGN 4 "Looking in ${@} for any of keys ${Keys[@]}"
	
	# now to the matching double-loop
	local Item Key
	for Item in "$@" ; do
		for Key in "${Keys[@]}" ; do
			[[ "$Item" == "$Key" ]] || continue
			DBGN 3 "Key '${Key}' found in list"
			return 0
		done
	done
	return 1
} # anyInList()


function ReplaceItem() {
	local Item="$1"
	shift
	local TagName
	while true ; do # allow for recursive substitutions
		for TagName in "$@" ; do
			local TagVarName="TAGKEYWORD_${TagName}"
			local Tag="${!TagVarName:-"%${TagName}%"}"
			local TagValueName="TAGVALUE_${TagName}"
			local NewItem="${Item//${Tag}/${!TagValueName}}"
		#	echo "${Tag} => ${TagValueName}='${!TagValueName}'" >&2
			if [[ "$NewItem" != "$Item" ]]; then
				Item="$NewItem"
				continue 2
			fi
		done
		break
	done
	echo "$Item"
} # ReplaceItem()


function PrepareHeader() {
	local Specs="$1"
	local Content="$2"
	
	case "${Specs:0:1}" in
		( '-' )
			printf "%-${Specs:1}s" "$Content"
			;;
		( '+' )
			printf "%${Specs:1}s" "$Content"
			;;
		( * )
			echo "$Content"
			;;
	esac
} # PrepareHeader()


function GetCurrentBranch() {
	# Usage:  GetCurrentBranch  [RepoDir]
	local RepoDir="$1"
	
	if [[ -n "$RepoDir" ]]; then
		pushd "$RepoDir" > /dev/null || return $?
	fi
	
	# get the short reference for current HEAD on screen;
	# that is, the current branch
	git rev-parse --abbrev-ref HEAD
	
	[[ -n "$RepoDir" ]] && popd > /dev/null
	return 0
} # GetCurrentBranch()


function GetLocalBranches() {
	# Usage:  GetLocalBranches  [RepoDir]
	local RepoDir="$1"
	
	if [[ -n "$RepoDir" ]]; then
		pushd "$RepoDir" > /dev/null || return $?
	fi
	
	# get the short reference for current HEAD on screen;
	# that is, the current branch
	git for-each-ref --format='%(refname:short)' refs/heads/
	
	[[ -n "$RepoDir" ]] && popd > /dev/null
	return 0
} # GetLocalBranches()


function isGoodRepo() {
	local Dir="$1"
	[[ -d "$Dir" ]] || return 1
	[[ -d "${Dir}/.git" ]] || return 1
	
	local RepoName="$(basename "$Dir")"
	
	DBGN 2 "Checking if repository '${RepoName}' should be processed..."
	
	local CurrentBranch
	if [[ "${#OnlyIfCurrentBranches[@]}" -gt 0 ]]; then
		[[ -z "$CurrentBranch" ]] && CurrentBranch="$(GetCurrentBranch "$Dir")"
		DBGN 2 "Current branch of ${RepoName}: '${CurrentBranch}'"
		
		anyInList -- "${OnlyIfCurrentBranches[@]}" -- "$CurrentBranch" || return 1
	fi
	
	if [[ "${#OnlyIfHasBranches[@]}" -gt 0 ]]; then
		local -a AllBranches=( $(GetLocalBranches "$Dir") )
		DBGN 2 "${#AllBranches[@]} local branches of ${RepoName}: ${AllBranches[@]}"
		
		anyInList -- "${OnlyIfHasBranches[@]}" -- "${AllBranches[@]}" || return 1
	fi
	
	if [[ "${#OnlyRepos[@]}" -gt 0 ]]; then
		DBGN 2 "Checking ${#OnlyRepos[@]} repository name patterns"
		local -i nMatches=0
		local Pattern
		for Pattern in "${OnlyRepos[@]}" ; do
			if [[ "$RepoName" =~ $Pattern ]]; then
				let ++nMatches
				DBGN 3 "Repository '${RepoName}' matches '${Pattern}'"
				break
			else
				DBGN 3 "Repository '${RepoName}' does not match '${Pattern}'"
			fi
		done
		if [[ "$nMatches" == 0 ]]; then
			DBGN 2 "Repository '${RepoName}' does not match any pattern: skipped!"
			return 1
		fi
	fi
	
	if [[ "${#SkipRepos[@]}" -gt 0 ]]; then
		DBGN 2 "Checking ${#SkipRepos[@]} repository name skip patterns"
		local Pattern
		for Pattern in "${SkipRepos[@]}" ; do
			[[ "$RepoName" =~ $Pattern ]] || continue
			DBGN 3 "Repository '${RepoName}' matches '${Pattern}': skipped!"
			return 1
		done
		DBGN 2 "Repository '${RepoName}' does not match any skip pattern."
	fi
	
	return 0
} # isGoodRepo()


################################################################################
### parameters parser
### 
declare CompactMode='normal'
declare -i NoMoreOptions=0
declare -i AutodetectCommand=0
declare -a Command
declare -a OnlyIfCurrentBranches
declare -a OnlyIfHasBranches
declare -a OnlyRepos
declare -a SkipRepos
for ((iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if isFlagSet NoMoreOptions || [[ "${Param:0:1}" != '-' ]]; then
		NoMoreOptions=1
		Command=( "${Command[@]}" "$Param" )
	else
		case "$Param" in
			( "--fake" | "--dry-run" | "-n" )
				FAKE=1
				;;
			( "--quiet" | "-q" )
				CompactMode='quiet'
				;;
			( "--git" )
				AddGit=1
				;;
			( "--command" | '--command='* )
				NArgs="${Param#--*=}"
				[[ "$NArgs" == "$Param" ]] && NArgs=1
				DBGN 2 "Adding the ${NArgs} arguments after #${iParam} to the command"
				EndArg="$((iParam + NArgs + 1))"
				while [[ $iParam < $EndArg ]] && [[ $iParam < $# ]]; do
					let ++iParam
					Command=( "${Command[@]}" "${!iParam}" )
				done
				DBGN 3 "Command is now: ${Command[@]}"
				;;
			( '--autodetect-command' )
				AutodetectCommand=1
				;;
			( '--ifcurrentbranch='* )
				OnlyIfCurrentBranches=( "${OnlyIfCurrentBranches[@]}" "${Param#--*=}" )
				;;
			( '--ifhasbranch='* )
				OnlyIfHasBranches=( "${OnlyIfHasBranches[@]}" "${Param#--*=}" )
				;;
			( '--only='* )
				OnlyRepos=( "${OnlyRepos[@]}" "${Param#--*=}" )
				;;
			( '--skip='* )
				SkipRepos=( "${SkipRepos[@]}" "${Param#--*=}" )
				;;
			( "--compact="* )
				CompactMode="${Param#--compact=}"
				;;
			( "--tag="* )
				Tags=( "${Tags[@]}" "${Param#--tag=}" )
				;;
			( "--tags="* )
				NewTags="${Param#--tags=}"
				Tags=( "${Tags[@]}" ${NewTags//,/ } )
				;;
			( '--stop-on-error' | '-S' )
				StopOnError=1
				;;
			( '--debug='* )
				DEBUG="${Param#--*=}"
				;;
			( '--debug' | '-d' )
				DEBUG=1
				;;
			( '--version' | '-V' )
				DoVersion=1
				;;
			( '--help' | '-?' | '-h' )
				DoHelp=1
				;;
			( '-' | '--' )
				NoMoreOptions=1
				;;
			( * )
				isFlagSet AutodetectCommand || FATAL 1 "Unknown option '${Param}'"
				# interpret this option and the rest of the arguments
				# as part of the command:
				# reparse this option in the newly set "command" mode
				NoMoreOptions=1
				let --iParam
		esac
	fi
done

if isFlagSet DoVersion ; then
	PrintVersion
	exit
fi

if isFlagSet DoHelp ; then
	help
	exit
fi

################################################################################
### get to the right directory
### 
if [[ ! -d "${BASEDIR}/srcs" ]]; then
	BASEDIR="$(pwd)"
	while [[ ! -d "${BASEDIR}/srcs" ]] && [[ "$BASEDIR" != '/' ]]; do
		BASEDIR="$(dirname "$BASEDIR")"
	done
fi

if [[ ! -d "${BASEDIR}/srcs" ]]; then
	: ${SRCDIR:="."}
else
	: ${SRCDIR:="${BASEDIR}/srcs"}
fi
DBGN 2 "Source directory: '${SRCDIR}'"

################################################################################
### execute the commands
###

[[ "${Command[0]}" != "git" ]] && isFlagSet AddGit && Command=( 'git' "${Command[@]}" )

DBG  "Command: ${Command[@]}"

declare -i nErrors=0
for Dir in "$SRCDIR"/* ; do
	
	isGoodRepo "$Dir" || continue
	
	PackageName="$(basename "$Dir")"
	
	pushd "$Dir" > /dev/null
	
	# replacement variables
	TAGVALUE_PACKAGENAME="$PackageName"
	
	declare -a PackageCommand
	PackageCommand=( )
	for (( iWord = 0 ; iWord < "${#Command[@]}" ; ++iWord )); do
		PackageCommand[iWord]="$(ReplaceItem "${Command[iWord]}" "${Tags[@]}" )"
	done
	
	declare Output
	if ! isFlagSet FAKE ; then
		Output="$( "${PackageCommand[@]}" 2>&1 )"
		res=$?
	else
		res=0
	fi
	
	case "$CompactMode" in
		( 'quiet' )
			[[ -n "$Output" ]] && echo "$Output"
			;;
		( 'prepend'* )
			Header="$(PrepareHeader "${CompactMode#prepend}" "[${PackageName}]")"
			echo -n "${Header} ${Output}"
			[[ $res != 0 ]] && echo -n " (exit code: ${res})"
			echo
			;;
		( 'append'* )
			Header="$(PrepareHeader "${CompactMode#append}" "[${PackageName}]")"
			echo -n "${Output} ${Header}"
			[[ $res != 0 ]] && echo -n " (exit code: ${res})"
			echo
			;;
		( * )
			echo -n "${PackageName}: ${PackageCommand[@]}"
			[[ $res != 0 ]] && echo -n " [exit code: ${res}]"
			echo
			[[ -n "$Output" ]] && echo "$Output"
	esac
	
	isFlagSet StopOnError && [[ $res != 0 ]] && exit "$res"
	
	[[ $res != 0 ]] && let ++nErrors
	popd > /dev/null
done

exit $nErrors
