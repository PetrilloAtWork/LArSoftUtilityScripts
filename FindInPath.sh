#!/usr/bin/env bash
#
# Lists all the files whose name matches the specified pattern, in a PATH-like
# list of directories.
# 
# Usage: see FindInPath.sh --help (help() function below)
# 
# Changes:
# 20140303, petrillo@fnal.gov (version 1.0)
#   first version (from ListFCL.sh v. 1.1)
#

SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.0"

: ${FORMAT:="%f (in %h)"}

function help() {
	cat <<-EOH
	Looks for files in the search directories specified in the given variables.
	
	Usage:  ${SCRIPTNAME} [options] [--] [Pattern ...]
	
	Each pattern is similar to using a '--simple=Pattern' option, but it also
	accepts partial matches.
	If a file matches any of the patterns, the file will be printed.
	
	Options:
	--varname=VARNAME
	    specifies a variable holding a colon-separated list of search directories;
	    if none is specified, LD_LIBRARY_PATH is used by default
	--simple=PATTERN , -s PATTERN
	    prints only the files whose name matches the specified regex pattern
	    (it's a find '-name' option, see \`man 1 find\`)
	--regex=PATTERN , -r PATTERN
	    prints only the files whose name matches the specified regex pattern
	    (it's a grep '-G' pattern, see \`man 1 grep\`)
	--grep=PATTERN , -e PATTERN
	    prints only the files containing the specified pattern
	    (it's a grep '-G' pattern, see \`man 1 grep\`)
	--simplegrep=PATTERN , -F PATTERN
	    prints only the files containing the specified pattern
	    (it's a grep '-F' pattern, see \`man 1 grep\`)
	--bin , -B
	--lib , -L
	--fcl , --fhicl , -F
	    preset settings for executables, libraries and FHICL files, respectively
	
	Format options:
	--format=FORMAT
	    use the specified format; the default format is "%f (in %h)";
	    the placeholder are as documented in find (1) manual
	--name , -n
	    print the file name only
	--path , -p
	    print the full path
	
	Other options:
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

function Filter() {
	if [[ $# == 0 ]]; then
		cat
		return
	fi
	
	local -a GrepParams
	local Pattern
	for Pattern in "$@" ; do
		if [[ "${Pattern:0:1}" != '^' ]]; then
			Pattern="^[^ ]*${Pattern}"
		fi
		
		# adapt the end-of-line marker
		if [[ "${Pattern%\$}" == "$Pattern" ]]; then
			Pattern="${Pattern}[^ ]* "
		else
			Pattern="${Pattern%\$} " # our line does not end, but a space is present instead
		fi
		GrepParams=( "${GrepParams[@]}" -G "$Pattern" )
	done
	
	STDERR grep "${GrepParams[@]}"
	grep "${GrepParams[@]}"
} # Filter()


function CleanKeys() { sed -e 's/^[^ ]* \+[^ ]* \+//' ; }

function GrepText() {
	local Key File Output
	local GrepMode="${1:-'G'}"
	shift
	while read Key File Output ; do
		local Matches=1
		if [[ $# -gt 0 ]]; then
			Matches=0
			for Pattern in "$@" ; do
				grep -q -${GrepMode} -e "$Pattern" -- "$File" && Matches=1 && break
			done
		fi
		isFlagSet Matches && echo "${Key} ${File} ${Output}"
	done
	return 0
} # GrepText()


function PrintFullLDpath() {
	/sbin/ldconfig -vNX | grep -v '\t' | sed -e 's/:.*//g' | while read LibDir ; do
		[[ $((nLibDirs++)) -gt 0 ]] && echo -n ':'
		echo -n "$LibDir"
	done
	echo
} # PrintFullLDpath()


function SplitPath() {
	local VarName="$1"
	local Separators="${2:-':'}"
	
	local -a Paths
	IFS="$Separators" read -a Paths <<< "${!VarName}"
	
	local Path
	for Path in "${Paths[@]}" ; do
		echo "$Path"
	done
	return 0
} # SplitPath()


function SplitPaths() {
	local VarName
	for VarName in "$@" ; do
		SplitPath "$VarName"
	done
	return 0
} # SplitPaths()

################################################################################

declare -i NoMoreOptions=0
declare -a SimpleFilters GREPPATTERNS GrepMode Patterns GenFilters VarListNames
declare -i nSimpleFilters=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1  ;;
			( '--version' | '-V' ) DoVersion=1  ;;
			
			( '--varname='* ) VarListNames=( "${VarListNames[@]}" "${Param#--varname=}" );;
			
			### format options
			( '--name' | '-n' ) FORMAT="%f" ;;
			( '--path' | '-p' ) FORMAT="%p" ;;
			( '--format='* )    FORMAT="${Param#--*=}" ;;
			
			### selection options
			( '--grep='* )          GREPPATTERNS=( "${GREPPATTERNS[@]}" "${Param#--*=}" ) ; GrepMode='G' ;;
			( '-e' | '-G' ) let ++iParam ; GREPPATTERNS=( "${GREPPATTERNS[@]}" "${!iParam}" ) ; GrepMode='G'  ;;
			( '--simplegrep='* )    GREPPATTERNS=( "${GREPPATTERNS[@]}" "${Param#--*=}" ) ; GrepMode='F' ;;
			( '-F' ) let ++iParam ; GREPPATTERNS=( "${GREPPATTERNS[@]}" "${!iParam}" ) ; GrepMode='F'  ;;
			( '--simple='* )        SimpleFilters=( "${SimpleFilters[@]}" "${Param#--*=}" ) ;;
			( '-s' ) let ++iParam ; SimpleFilters=( "${SimpleFilters[@]}" "${!iParam}" ) ;;
			( '--regex='* )         Patterns=( "${Patterns[@]}" "${Param#--*=}" ) ;;
			( '-r' ) let ++iParam ; Patterns=( "${Patterns[@]}" "${!iParam}" ) ;;
			( '--gen='* )           GenFilters=( "${GenFilters[@]}" "${Param#--*=}" ) ;;
			( '-g' ) let ++iParam ; GenFilters=( "${GenFilters[@]}" "${!iParam}" ) ;;
			
			( '--bin' | '-B' ) # executable file mode
				VarListNames=( "${VarListNames[@]}" 'PATH' )
				;;
			( '--lib' | '-L' ) # system library mode
				FULL_LD_LIBRARY_PATH="$(PrintFullLDpath)"
				VarListNames=( "${VarListNames[@]}" 'FULL_LD_LIBRARY_PATH' )
				GenFilters=( "${GenFilters[@]}" "lib*.so*" "lib*.a" )
				;;
			( '--fhicl' | '--fcl' | '-F' ) # FHICL mode
				VarListNames=( "${VarListNames[@]}" 'FHICL_FILE_PATH' )
				GenFilters=( "${GenFilters[@]}" "*.fcl" )
				;;
			
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
		SimpleFilters[nSimpleFilters++]="*${Param}*"
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

declare -a GenNames
for GenName in "${GenFilters[@]}" ; do
	[[ -n "$GenName" ]] || continue
	[[ ${#GenNames[@]} -gt 0 ]] && GenNames=( "${GenNames[@]}" -or )
	GenNames=( "${GenNames[@]}" -name "$GenName" )
done
[[ "${#GenNames[@]}" -gt 0 ]] && GenNames=( '(' "${GenNames[@]}" ')' )

declare -a FindNames
for SimpleFilter in "${SimpleFilters[@]}" ; do
	[[ -n "$SimpleFilter" ]] || continue
	[[ ${#FindNames[@]} -gt 0 ]] && FindNames=( "${FindNames[@]}" -or )
	FindNames=( "${FindNames[@]}" -name "$SimpleFilter" )
done
[[ "${#FindNames[@]}" -gt 0 ]] && FindNames=( '(' "${FindNames[@]}" ')' )

declare -a AllFindNames
AllFindNames=( "${GenNames[@]}" )
if [[ "${#FindNames[@]}" -gt 0 ]]; then
	[[ "${#AllFindNames[@]}" -gt 0 ]] && AllFindNames=( "${AllFindNames[@]}" -and )
	AllFindNames=( "${AllFindNames[@]}" "${FindNames[@]}" )
fi

# explanation:
# - start with paths in VarNames paths
# - split by ":"
# - find in all those directories (but not in their subdirectories),
#   and in that order, all the files
# - print for each its name, full path and the string to be presented to the user as output
# - sort them by file name, preserving the relative order of files with the
#   same name from different directories
# - filter them on sort key (file name) by user's request
# - remove the sort key (file name) from the output
SplitPaths "${VarListNames[@]}" | xargs -I SEARCHPATH find SEARCHPATH -maxdepth 1 "${AllFindNames[@]}" -printf "%f %p ${FORMAT}\n" 2> /dev/null | sort -s -k1,1 -u | Filter "${Patterns[@]}" | GrepText "$GrepMode" "${GREPPATTERNS[@]}" | CleanKeys
