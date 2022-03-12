#!/usr/bin/env bash
#
# Reruns a command run with larrun.sh version 1.1 or newer.
#

SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.0"


function help() {
	cat <<-EOH
	Reruns a larrun.sh command session.
	
	Usage:  ${SCRIPTNAME} [script options] [--] LogFile [LogFile ...]
	
	Script options:
	--version , -V
	    prints the script version
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


################################################################################

declare DoHelp=0 DoVersion=0

declare -i NoMoreOptions=0
declare -a LogFiles
declare -i nLogFiles=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' )     DoHelp=1  ;;
			( '--version' | '-V' )         DoVersion=1  ;;
			
			### other stuff
			( '-' | '--' )
				NoMoreOptions=1
				;;
			( * )
				echo "Unrecognized script option #${iParam} - '${Param}'"
				exit 1
				;;
		esac
	else
		NoMoreOptions=1
		LogFiles[nLogFiles++]="$Param"
	fi
done

declare -i ExitCode

if isFlagSet DoVersion ; then
	echo "${SCRIPTNAME} version ${SCRIPTVERSION:-"unknown"}"
	: ${ExitCode:=0}
fi

if isFlagSet DoHelp ; then
	help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	{ [[ -z "$ExitCode" ]] || [[ "$ExitCode" == 0 ]] ; } && ExitCode="$?"
fi

[[ -n "$ExitCode" ]] && exit $ExitCode

declare -i nErrors=0
for LogFile in "${LogFiles[@]}" ; do
	
	# by convention a log file is present with the same name as the output directory;
	# if `LogFile` is actually the output directory, this will point to that log file.
	[[ -d "$LogFile" ]] && LogFile+=".log"
	if [[ ! -r "$LogFile" ]]; then
		ERROR "Log file '${LogFile}' not found!"
		let ++nErrors
		continue
	fi
	
	declare RunDir=''
	declare RunLogFile=''
	declare -a Command=( )
	
	while read Line ; do
		[[ -n "$RunDir" ]] && [[ "${#Command[@]}" -gt 0 ]] && [[ -n "$RunLogFile" ]] && break
		
		if [[ "${Line#Directory: }" != "$Line" ]]; then
			RunDir="$(sed -e 's/^Directory:[[:blank:]]*//g' <<< "$Line")"
			continue
		fi
		
		if [[ "${Line#Run with: }" != "$Line" ]]; then
			Command=( $(sed -e 's/^Run with:[[:blank:]]*//g' <<< "$Line") )
			continue
		fi
		
		if [[ "${Line#Log file: }" != "$Line" ]]; then
			RunLogFile="$(sed -e "s/^Log file:[[:blank:]]*'\(.*\)'.*$/\1/g" <<< "$Line")"
			continue
		fi
		
	done < "$LogFile"
	
	if [[ -z "$RunDir" ]]; then
		ERROR "Could not find the run directory in the log file!"
		let ++nErrors
		continue
	fi
	if [[ "${#Command[@]}" == 0 ]]; then
		ERROR "Could not find the command in the log file! (could be from larrun.sh 1.0?)"
		let ++nErrors
		continue
	fi
	if [[ -z "$RunLogFile" ]]; then
		ERROR "Could not find the name of the job log file!"
		let ++nErrors
		continue
	fi
	if [[ ! -d "$RunDir" ]]; then
		ERROR "Run directory '${RunDir}' is not accessible any more."
		let ++nErrors
		continue
	fi
	
	cat <<-EOM
	Rerunning from '${LogFile}':
	
	${Command[@]}
	
	EOM
	
	${Command[@]}
done

if [[ $nErrors -gt 0 ]]; then
	ERROR "Run with ${nErrors} error(s)."
fi
exit $nErrors
