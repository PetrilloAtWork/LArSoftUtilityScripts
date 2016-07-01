#!/usr/bin/env bash
#
# Convenience alias to open a art or cetbuildtools CMake macro file
#

SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"
SCRIPTVERSION="1.1"

[[ "${#DEFAULTPACKAGES[@]}" == 0 ]] && DEFAULTPACKAGES=( 'cetbuildtools' 'art' )


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
	Looks for CMake macro files in the specified UPS packages,
        shows them and finally prints their path.
	
	Usage:  ${SCRIPTNAME}  [options]  Pattern [Pattern ...]
	
	Options:
	--listonly , -L
	    do not show the files, only print their path
	--listall
	    print all the possible choices of macro files
	--package=PACKAGE [${DEFAULTPACKAGES[@]}]
	    add one UPS package at the list of package to be used
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
	
	[[ "$Pattern" =~ \. ]] || Pattern+=".cmake"
	
	DBGN 1 "Looking for '${Pattern}' in: ${Dirs[@]}"
	find "${Dirs[@]}" -name "$Pattern"
	
} # FindMatches()


function GetPackageDir() {
	local Package="$1"
	local PackageDirVar="${Package^^}_DIR"
	local PackageDir="${!PackageDirVar}"
	echo "$PackageDir"
	[[ -n "$PackageDir" ]]
} # GetPackageDir()

function FindModuleDir() {
	# detect the source directory
	local PackageName="$1"
	local PackageDir="${2:-$(GetPackageDir "$PackageName")}"
	
	local ModuleDir DirName
	for DirName in "Modules" ; do
		ModuleDir="${PackageDir}/${DirName}"
		[[ -d "$ModuleDir" ]] && echo "$ModuleDir" && return 0
	done
	return 2
} # FindModuleDir()



###############################################################################
: ${PAGER:=less}

declare -a Packages
declare -i DoHelp=0 DoVersion=0
declare -i ListOnly=0 ListAll=0
declare -i NoMoreOptions=0
declare -a Patterns
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if [[ "${Param:0:1}" == '-' ]] && isFlagUnset NoMoreOptions ; then
		case "$Param" in
			( '--package='* )          Packages=( "${Packages[@]}" "${Param#--*=}" ) ;;
			( '--pager='* )            PAGER="${Param#--*=}" ;;
			( '--debug' )              DEBUG=1 ;;
			( '--debug='* )            DEBUG="${Param#--*=}" ;;
			( '--listonly' | '-L' )    ListOnly=1 ;;
			( '--listall' )            ListAll=1 ;;
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

[[ "${#Packages[@]}" == 0 ]] && Packages=( "${DEFAULTPACKAGES[@]}" )

[[ ${#Patterns[@]} == 0 ]] && ListAll=1

# set up check
declare -a AvailablePackages
declare -a ModulesFound
declare -i nErrors=0
for PackageName in "${Packages[@]}" ; do
	declare PackageDir="$(GetPackageDir "$PackageName")"
	if [[ -z "$PackageDir" ]]; then
		ERROR "${PackageName} is not set up."
		continue
	fi
	AvailablePackages=( "${AvailablePackages[@]}" "$PackageName" )
	DBGN 1 "Package: '${PackageName}'"

	# detect the source directory
	declare PackageModuleDir
	PackageModuleDir="$(FindModuleDir "$PackageName" "$PackageDir" )"
	if [[ $? != 0 ]]; then
		DBG "Failed to find module dir (got: '${PackageModuleDir}')"
		ERROR "Could not find module directory of '${PackageName}' under '${PackageDir}'"
		let ++nErrors
		continue
	fi
	
	if isFlagSet ListAll ; then
		echo -n "All choices for '${PackageName}':"
		for CMakeFile in "$PackageModuleDir"/*.cmake ; do
			echo -n " $(basename "${CMakeFile%.cmake}")"
		done
		echo
		continue
	fi
	
	# process all the patterns one by one
	for Pattern in "${Patterns[@]}" ; do
		DBGN 2 "  Pattern: '${Pattern}'"
		
		declare -a PatternMatches=()
		
		while read Match ; do
			PatternMatches=( "${PatternMatches[@]}" "$Match" )
		done < <(FindMatches "$Pattern" "$PackageModuleDir" )
		
		if [[ "${#PatternMatches[@]}" == 0 ]]; then
			DBGN 1 "Pattern '${Pattern}' does not match any ${PackageName} CMake module."
			continue
		fi
			
		ModulesFound=( "${ModulesFound[@]}" "${PatternMatches[@]}" )
		
		isFlagUnset ListOnly && $PAGER "${PatternMatches[@]}"
	done # for patterns
	
done # for UPS products
[[ "${AvailablePackages[@]}" == 0 ]] && FATAL 1 "No relevant package set up!"

isFlagSet ListAll && exit

# print all the sources we could find
if [[ "${#ModulesFound[@]}" == 0 ]]; then
	ERROR "No items matching the specified pattern(s)!"
else
	for Module in "${ModulesFound[@]}" ; do
		echo "$Module"
	done
fi
exit $nErrors

