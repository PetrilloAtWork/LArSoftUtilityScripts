#!/usr/bin/env bash
#
# Destroy the specified output areas (created by larrun.sh).
#


SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"
: ${BASEDIR:="$(dirname "$(grealpath "$SCRIPTDIR")")"}

: ${DOIT:="0"}

function isFlagSet() { local VarName="$1" ; [[ -n "${!VarName//0}" ]] ; }

function STDERR() { echo "$*" >&2 ; }
function ERROR() { STDERR "ERROR: $*" ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()

function DUMPVAR() { local VarName="$1" ; STDERR "${VarName}='${!VarName}'" ; }
function DUMPVARS() { local VarName ; for VarName in "$@" ; do DUMPVAR "$VarName" ; done ; }



function help() {
	cat <<-EOH
	Destroys the specified output created by larrun.sh
	
	Usage:  $(basename "$0")  [now] Area [Area...]
	
	For each specified "area", the log file and the working directory with the
	same base name are deleted.
	If "now" (nor "doit", case unsensitive) is not specified, it will just print
	the list of files which would be deleted.	
	
	Options:
	--fake , --dry-run , -n
	    just prints what would be deleted (default)
	--doit , --now, -y
	    actually performs the deletion
	--all
	    deletes all the volumes matching the specified base
	--exceptlast
	    deletes all the volumes matching the specified base, except the highest
	    volume number
	--help , -h , -?
	    prints this help message
	
	EOH
} # help()


function IsInList() {
	local ListName="$1"
	shift
	local Key
	for Key in "$@" ; do
		local ListItem
		for ListItem in "${!List[@]}" ; do
			[[ "$ListItem" == "$Key" ]] && return 0
		done
	done
	return 1
} # IsInList()


################################################################################
### parameters parser
###
declare FakeOption=''

declare -i NoMoreOptions=0
declare -a Specs
for ((iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if isFlagSet NoMoreOptions || [[ "${Param:0:1}" != '-' ]]; then
		NoMoreOptions=1
		Specs=( "${Specs[@]}" "$Param" )
	else
		case "$Param" in
			( "--fake" | "--dry-run" | "-n" )
				FakeOption="$Param"
				DOIT=0
				;;
			( "--now" | "--doit" | "-y" )
				FakeOption=''
				DOIT=1
				;;
			( '--all' )
				All=1
				AllExceptLast=0
				;;
			( '--exceptlast' )
				All=1
				AllExceptLast=1
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


declare -a Dirs
declare -i NDirs=0
for Spec in "${Specs[@]}" ; do
	[[ "${Spec%.log}" != "$Spec" ]] && Spec="${Spec%.log}"
	[[ "${Spec%_workdir}" != "$Spec" ]] && Spec="${Spec%_workdir}"
	
	SpecDir="$(dirname "$Spec")"
	SpecName="$(basename "$Spec")"
	
	if isFlagSet All ; then
		if [[ "$SpecName" =~ -[[:digit:]]+$ ]]; then
			BaseName="${SpecName%-*}"
			SpecVolumeNumber="${SpecName#"${BaseName}-"}"
		elif [[ "${SpecName%-}" != "$SpecName" ]]; then
			BaseName="${SpecName%-}"
			SpecVolumeNumber=""
		else
			BaseName="$SpecName"
			SpecVolumeNumber=""
		fi
		
		Last="$(ls -dv "${SpecDir}/${BaseName}-"* 2> /dev/null | tail -n 1)"
		
		declare LastVolumeStr="$(tr -cd '[:digit:]' <<< "${Last#"${SpecDir}/${BaseName}-"}")"
		declare -i LastVolume="$LastVolumeStr"
		
		if isFlagSet AllExceptLast ; then
			echo "${SpecDir}/${BaseName}-${LastVolumeStr} will be kept."
			let --LastVolume
		fi
		declare -i Padding="${#LastVolumeStr}"
		
		declare -i iVolume=0
		for (( iVolume = 0 ; iVolume <= LastVolume ; ++iVolume )); do
			
			for (( iPadding="$Padding" ; iPadding >= "${#iVolume}" ; --iPadding )); do
				VolumeBaseName="${SpecDir}/${BaseName}-$(printf "%0*d" "$iPadding" "$iVolume")"
				if [[ -d "${VolumeBaseName}" ]] || [[ -f "${VolumeBaseName}.log" ]]; then
					IsInList Dirs "$VolumeBaseName" || Dirs[NDirs++]="$VolumeBaseName"
					break
				fi
			done
			
		done
	else
		IsInList Dirs "$Spec" || Dirs[NDirs++]="$Spec"
	fi
done


declare RemoveOpt=""
isFlagSet DOIT && RemoveOpt="-delete"


declare -i nErrors=0
isFlagSet DOIT && echo "Deleting:"
for (( iDir = 0 ; iDir < NDirs ; ++iDir )); do
	Area="${Dirs[iDir]}"
	{ [[ $NDirs == 0 ]] && isFlagSet DOIT ; } || echo " --- ${Area} --- "
	
	for Target in "${Area}.log"* ; do
		if [[ -w "$Target" ]]; then
			if isFlagSet DOIT ; then
				rm -v "$Target"
			else
				ls "$Target"
			fi
		elif [[ -d "$Target" ]]; then
			ERROR "'${Target}' is a directory!"
			let ++nErrors
		elif [[ -e "$Target" ]]; then
			ERROR "'${Target}' can't be deleted."
			let ++nErrors
		else
			ERROR "'${Target}' does not exist."
			let ++nErrors
		fi
	done
	
	Target="$Area"
	if [[ ! -e "$Target" ]]; then
		ERROR "'${Target}' does not exist."
		let ++nErrors
	elif [[ ! -d "$Target" ]]; then
		ERROR "'${Target}' is not a directory!"
		let ++nErrors
	elif [[ ! -w "$Target" ]]; then
		ERROR "'${Target}' can't be deleted."
		let ++nErrors
	else
		find "$Target" -print $RemoveOpt
	fi
done

if ! isFlagSet DOIT ; then
	echo -e "If you like what you see, delete it with\n${0} --doit ${@/${FakeOption}}"
fi
exit $nErrors

