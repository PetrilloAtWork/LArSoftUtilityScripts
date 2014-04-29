#!/bin/bash
#
# Lists all the modules matching a simple pattern.
# 
# Usage: see FindModule.sh --help (help() function below)
# 
# Changes:
# 20140421, petrillo@fnal.gov (version 1.2)
#   bug fix to regex search; added '--debug' option
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
	Lists all the modules matching any of the specified patterns.
	
	Usage:  ${SCRIPTNAME} [options] [--] Pattern [Pattern ...]
	
	Options:
	--regex , -e
	    pattern is a regular expression (like the ones in egrep);
	    by default, pattern is a simple file-matching pattern
	--case , -C
	    name the search case-sensitive (by default, it is not)
	--sources , --src , -S
	    searches in the LArSoft source directories (default if MRB_SOURCE is
	    defined)
	--libraries , --lib , -L
	    searches in the current library paths (default if MRB_SOURCE is not
	    defined)
	--debug
	    print additional debug information
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

function isDebugging() { isFlagSet DEBUG ; }
function DBG() { isDebugging && STDERR "DBG| $*" ; }


################################################################################

REGEX=""

declare -i NoMoreOptions=0
declare -a Patterns
declare -i nPatterns=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1 ;;
			( '--version' | '-V' ) DoVersion=1 ;;
			( '--debug' ) DEBUG=1 ;;
			
			( '--sources' | '--src' | '-S' ) FromSources=1 ;;
			( '--libraries' | '--lib' | '-L' ) FromLibraries=1 ;;
			
			### format options
			( '--regex' | '-e' ) REGEX="posix-egrep" ;;
			( '--case' | '-C' ) CaseSensitive=1 ;;
			
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

declare ProgressiveFind=0
if ! isFlagSet FromSources && ! isFlagSet FromLibraries ; then
	[[ -n "$MRB_SOURCE" ]] && FromSources=1
	FromLibraries=1
fi

case "$REGEX" in
	( "" )
		if isFlagSet CaseSensitive ; then
			FindCommand='name'
		else
			FindCommand='iname'
		fi
		DefaultPattern="*"
		;;
	( "posix-egrep" )
		if isFlagSet CaseSensitive ; then
			FindCommand='regex'
		else
			FindCommand='iregex'
		fi
		DefaultPattern=".*"
		;;
esac

declare -i Found=0

# from sources
if isFlagSet FromSources ; then
	
	declare -a SourceFindCommands
	for Pattern in "${Patterns[@]:-"$DefaultPattern"}" ; do
		SourceFindCommands=( "${SourceFindCommands[@]}" "-${FindCommand}" "${Pattern}_module.cc" )
	done
	
	if [[ -d "$MRB_SOURCE" ]]; then
		declare -a Command=( find "$MRB_SOURCE" ${REGEX:+-regextype "$REGEX"} "${SourceFindCommands[@]}" )
		DBG "${Command[@]}"
		"${Command[@]}"
	elif [[ -z "$MRB_SOURCE" ]]; then
		ERROR "Source directory (MRB_SOURCE) not defined."
	else
		ERROR "Source directory ('${MRB_SOURCE}') not not exist."
	fi
fi

# from libraries
if isFlagSet FromLibraries ; then
	declare -a LibraryFindCommands
	for Pattern in "${Patterns[@]:-"$DefaultPattern"}" ; do
		LibraryFindCommands=( "${LibraryFindCommands[@]}" "-${FindCommand}" ".*/lib${Pattern}_module.so" )
	done
	
	if [[ -n "$LD_LIBRARY_PATH" ]]; then
		declare -a AllLibPaths LibPaths
		declare OldIFS="$IFS"
		IFS=":"
		AllLibPaths=( ${LD_LIBRARY_PATH} )
		IFS="$OldIFS"
		for LibPath in "${AllLibPaths[@]}" ; do
			[[ -d "$LibPath" ]] && LibPaths=( "${LibPaths[@]}" "$LibPath" )
		done
		declare -a Command=( find "${LibPaths[@]}" ${REGEX:+-regextype "$REGEX"} "${LibraryFindCommands[@]}" )
		DBG "${Command[@]}"
		"${Command[@]}"
		[[ $? == 0 ]] && Found=1
	else
		ERROR "No library path configured (LD_LIBRARY_PATH)."
	fi
fi

exit 0
