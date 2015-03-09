#!/bin/bash
#
# Looks for art source matching exactly the suggested patterns,
# shows them and finally prints their path.
#
# See `ShowSource.sh --help` for usage instructions.
#

SCRIPTNAME="$(basename "$0")"

SCRIPTVERSION="1.0"

: ${DEFAULTPACKAGE:="art"}

###############################################################################
function STDERR() { echo -- "$*" >&2 ; }
function WARN()   { STDERR "WARNING: $*" ; }
function ERROR()  { STDERR "ERROR: $*" ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (code: ${Code}): $*"
	exit $Code
} # FATAL()

function isDebugging() {
	local Level="${1:-1}"
	[[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge "$Level" ]]
} # isDebugging()
function DBGN() {
	local Level="$1"
	shift
	isDebugging "$Level" && STDERR "DBG[${Level}]| $*"
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

function help() {
	cat <<-EOH
	Looks for source files matching exactly the suggested patterns
	in the specified UPS package, shows them and finally prints their path.
	
	Usage:  ${SCRIPTNAME}  [options]  Pattern [Pattern ...]
	
	Options:
	--listonly , -L
	    do not show the files, only print their path
	--package=PACKAGE [${DEFAULTPACKAGE}]
	    the UPS package to be used
	--pager=PAGER [${PAGER}]
	    the command to be used to show the files
	--debug[=LEVEL]
	    increase the verbosity level
	--version , -V
	    prints the script version and exits
	--help , -h , -?
	    prints this help message and exits
	EOH
} # help()

###############################################################################
function FindMatches() {
	local Pattern="$1"
	shift
	local -a Dirs=( "$@" )
	
	find "${Dirs[@]}" -name "$Pattern"
	
} # FindMatches()


function GetPackageDir() {
	local Package="$1"
	local PackageDirVar="${Package^^}_DIR"
	local PackageDir="${!PackageDirVar}"
	echo "$PackageDir"
	[[ -n "$PackageDir" ]]
} # GetPackageDir()

function FindSourceDir() {
	# detect the source directory
	local PackageName="$1"
	local PackageDir="${2:-$(GetPackageDir "$PackageName")}"
	
	local SourceDir DirName
	for DirName in "source/${PackageName,,}" "src/${PackageName,,}" "source" "src" ; do
		SourceDir="${PackageDir}/${DirName}"
		[[ -d "$SourceDir" ]] && echo "$SourceDir" && return 0
	done
	return 2
} # FindSourceDir()


function FindIncludeDir() {
	# detect the include directory
	local PackageName="$1"
	local PackageDir="${2:-$(GetPackageDir "$PackageName")}"
	DBGN 2 "Directory for package '${PackageName}' is '${PackageDir}'"
	
	local IncDir
	
	# ask UPS first
	local IncDirVarName
	for IncDirVarName in "${PackageName^^}_INC" ; do
		IncDir="${!IncDirVarName}"
		DBGN 2 "Include dir: ${IncDirVarName}='${IncDir}'"
		[[ -n "$IncDir" ]] && [[ -d "$IncDir" ]] && echo "$IncDir" && return 0
	done
	
	# nope... try to figure out
	local UPSflavor
	local -a UPSflavors
	local -i iFlavor
	for (( iFlavor = 0 ; iFlavor <= 7 ; ++iFlavor )); do
		UPSflavor="$(ups flavor -${iFlavor} 2> /dev/null)"
		[[ $? == 0 ]] || continue
		UPSflavors=( "$UPSflavor" "${UPSflavors[@]}" ) # higher takes priority
	done
	
	DBGN 2 "Trying to find include dir by building it with UPS flavours: ${UPSflavors[@]}"
	local IncDir DirName
	for DirName in "include/${PackageName,,}" "inc/${PackageName,,}" "include" "inc" ; do
		DBGN 3 "  - trying '${DirName}'"
		for FlavorDir in '' "${UPSflavors[@]}" ; do
			IncDir="${PackageDir}/${FlavorDir:+${FlavorDir}/}${DirName}"
			DBGN 4 "    -> '${IncDir}'"
			[[ -d "$IncDir" ]] && echo "$IncDir" && return 0
		done # for flavors
	done # for directory pattern
	DBG "No include directory found for '${PackageName}'"
	return 2
} # FindIncludeDir()


###############################################################################
: ${PAGER:=less}

declare PackageName
declare -i DoHelp=0 DoVersion=0
declare -i ListOnly=0
declare -i NoMoreOptions=0
declare -a Patterns
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if [[ "${Param:0:1}" == '-' ]] && isFlagUnset NoMoreOptions ; then
		case "$Param" in
			( '--package='* )          PackageName="${Param#--*=}" ;;
			( '--pager='* )            PAGER="${Param#--*=}" ;;
			( '--debug' )              DEBUG=1 ;;
			( '--debug='* )            DEBUG="${Param#--*=}" ;;
			( '--listonly' | '-L' )    ListOnly=1 ;;
			( '--version' | '-V' )     DoVersion=1 ;;
			( '--help' | '-h' | '-?' ) DoHelp=1 ;;
			( '-' | '--' ) NoMoreOptions=1 ;;
			( * )
				FATAL 1 "Option '${Param}' not recognized."
		esac
	else
		Patterns=( "${Patterns[@]}" "$Param" )
	fi
done

if isFlagSet DoHelp ; then
	help
	exit
fi
if isFlagSet DoVersion ; then
	echo "${SCRIPTNAME} version ${SCRIPTVERSION}"
	exit
fi

: ${PackageName:="$DEFAULTPACKAGE"}

# set up check
declare PackageDir="$(GetPackageDir "$PackageName")"
if [[ -z "$PackageDir" ]]; then
	ERROR "${PackageName} is not set up."
	exit 1
fi
# detect the source directory
declare PackageSourceDir
PackageSourceDir="$(FindSourceDir "$PackageName" "$PackageDir" )"
if [[ $? != 0 ]]; then
	DBG "Failed to find source dir (got: '${PackageSourceDir}')"
	PackageSourceDir="$(FindIncludeDir "$PackageName" "$PackageDir" )"
	if [[ $? == 0 ]]; then
		WARN "Could not find the source directory of '${PackageName}' under '${PackageDir}'; using include dir '${PackageSourceDir}'."
	else
		DBG "Failed to find source dir (got: '${PackageSourceDir}')"
		ERROR "Could not find source nor include directory of '${PackageName}' under '${PackageDir}'"
		exit 2
	fi
fi

# process all the patterns one by one
declare -a SourcesFound
declare -i nErrors=0

for Pattern in "${Patterns[@]}" ; do
	
	declare -a PatternMatches
	
	while read Match ; do
		PatternMatches=( "${PatternMatches[@]}" "$Match" )
	done < <(FindMatches "$Pattern" "$PackageSourceDir" )
	
	if [[ "${#PatternMatches[@]}" == 0 ]]; then
		let ++nErrors
		ERROR "Pattern '${Pattern}' does not match any ${PackageName} source."
		continue
	fi
		
	SourcesFound=( "${SourcesFound[@]}" "${PatternMatches[@]}" )
	
	isFlagUnset ListOnly && $PAGER "${PatternMatches[@]}"
done

# print all the sources we could find
for Source in "${SourcesFound}" ; do
	echo "$Source"
done

exit $nErrors

