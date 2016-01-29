#!/usr/bin/env bash
#
# Lists all the FCL files whose name matches the specified pattern.
# 
# Usage: see ListFCL.sh --help (help() function below)
# 
# Changes:
# 20140218, petrillo@fnal.gov (version 1.1)
#   adding version number and grepping abilities
# 201402??, petrillo@fnal.gov (version 1.0)
#   first version
#

SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.1"

: ${FORMAT:="%f (in %h)"}

function help() {
	cat <<-EOH
	Looks for FHICL files in the ART FHICL search directories.
	
	Usage:  ${SCRIPTNAME} [options] [--] [Pattern]
	
	Options:
	--format=FORMAT
	    use the specified format; the default format is "%f (in %h)";
	    the placeholder are as documented in find (1) manual
	--name , -n
	    print the file name only
	--path , -p
	    print the full path
	--grep=PATTERN , -e PATTERN
	    prints only the FHICL file containing the specified pattern
	    (it's a grep '-G' pattern, see \`man 1 grep\`))
	--version , -V
	    print the version number and exit
	--help , -h , -?
	    print these usage instructions
	
	EOH
} # help()


function isFlagSet() {
	local VarName="$1"
	[[ -n "${!VarName//0}" ]]
} # isFlagSet()

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

function Filter() {
	local Pattern="$1"
	if [[ -n "$Pattern" ]]; then
		grep -e "$Pattern"
	else
		cat
	fi
} # Filter()

function CleanKeys() { sed -e 's/^[^ ]* \+[^ ]* \+//' ; }

function GrepText() {
	local Key File Output
	while read Key File Output ; do
		local Matches=1
		if [[ $# -gt 0 ]]; then
			Matches=0
			for Pattern in "$@" ; do
				grep -q -G -e "$Pattern" -- "$File" && Matches=1 && break
			done
		fi
		isFlagSet Matches && echo "${Key} ${File} ${Output}"
	done
	return 0
} # GrepText()

################################################################################

declare -i NoMoreOptions=0
declare -a Patterns
declare -i nPatterns=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1  ;;
			( '--version' | '-V' ) DoVersion=1  ;;
			
			### format options
			( '--name' | '-n' ) FORMAT="%f" ;;
			( '--path' | '-p' ) FORMAT="%p" ;;
			( '--format='* )    FORMAT="${Param#--*=}" ;;
			( '--grep='* )      GREPPATTERNS=( "${GREPPATTERNS[@]}" "${Param#--*=}" ) ;;
			( '-e' ) let ++iParam ; GREPPATTERNS=( "${GREPPATTERNS[@]}" "${!iParam}" ) ;;
			
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
		Patterns[nPatterns++]="$Param"
	fi
done

if isFlagSet DoHelp ; then
	help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	exit $?
fi

if isFlagSet DoVersion ; then
	echo "${SCRIPTNAME} version ${SCRIPTVERSION}"
	exit 0
fi

# explanation:
# - start with paths in FHICL_FILE_PATH
# - split by ":"
# - find in all those directories (but not in their subdirectories),
#   and in that order, all the FCL files
# - print for each its name and the string to be presented to the user as output
# - soft them by FCL file name, preserving the relative order of files with the
#   same name from different directories
# - filter them on sort key (file name) by user's request
# - remove the sort key (file name) from the output
tr ':' "\n" <<< "$FHICL_FILE_PATH" | xargs -I SEARCHPATH find SEARCHPATH -maxdepth 1 -name "*.fcl" -printf "%f %p ${FORMAT}\n" 2> /dev/null | sort -s -k1,1 -u | Filter "^[^ ]*${Patterns[0]}[^ ]* " | GrepText "${GREPPATTERNS[@]}" | CleanKeys
