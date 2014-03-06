#!/bin/bash
#
# Preprocess a FHICL file with the C preprocessor
# 
# Usage: see PreprocessFCL.sh --help (help() function below)
# 
# Changes:
# 20140224, petrillo@fnal.gov (version 1.0)
#   first version
#

SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.0"

function help() {
	cat <<-EOH
	Preprocesses a FHICL file with the C preprocessor.
	
	Usage:  ${SCRIPTNAME} [options] [--] FCLfile [FCLfile ...]
	
	Options:
	--header , -H [default: only if more than one file is specified]
	    prints a header before each preprocessed file
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


################################################################################

declare -i NoMoreOptions=0
declare -a FCLfiles
declare -i nFCLfiles=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1  ;;
			( '--version' | '-V' ) DoVersion=1  ;;
			
			### format options
			( '--header' | '-H' ) Header=1 ;;
			
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
		FCLfiles[nFCLfiles++]="$Param"
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

if [[ -z "$Header" ]]; then
	if [[ $nFCLfiles -gt 1 ]]; then
		Header=1
	else
		Header=0
	fi
fi

declare -a IncludeDirs
declare OldIFS="$IFS"
IFS=':'
IncludeDirs=( $FHICL_FILE_PATH )
IFS="$OldIFS"

declare -a CPPParams
for IncludeDir in "${IncludeDirs[@]}" ; do
	CPPParams=( "${CPPParams[@]}" "-I${IncludeDir}" )
done

for FCLfile in "${FCLfiles[@]}" ; do
	if isFlagSet Header ; then
		cat <<-EOH
		#############################################################################
		###  ${FCLfile}
		###  (this four-line header does not belong to the FCL file)
		#############################################################################
		EOH
	fi
	cpp "${CPPParams[@]}" "$FCLfile" 2> /dev/null
	
done
