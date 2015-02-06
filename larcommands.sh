#!/bin/bash
#
# Distributes a command to all the GIT repositories.
#

SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"
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
	
	Options:
	--tag=TAGNAME
	--tags=TAGNAME[,TAGNAME...]
	    add a tag to the list of tags
	--git
	    adds "git" as command if it's not the first word of the command already
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
	--help , -h , -?
	    prints this help message
	
	EOH
} # help()


function isFlagSet() { local VarName="$1" ; [[ -n "${!VarName//0}" ]]; }

function STDERR() { echo "$*" >&2 ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()


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

################################################################################
### parameters parser
### 
declare CompactMode='normal'
declare -i NoMoreOptions=0
declare -a Command
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
			( '--help' | '-?' | '-h' )
				DoHelp=1
				;;
			( '-' | '--' )
				NoMoreOptions=1
				;;
			( * )
				FATAL 1 "Unknown option '${Param}'"
		esac
	fi
done

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

################################################################################
### execute the commands
###

[[ "${Command[0]}" != "git" ]] && isFlagSet AddGit && Command=( 'git' "${Command[@]}" )

declare -i nErrors=0
for Dir in "$SRCDIR"/* ; do
	[[ -d "$Dir" ]] || continue
	[[ -d "${Dir}/.git" ]] || continue
	
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
