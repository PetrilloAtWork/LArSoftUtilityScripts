#!/bin/bash
#
# Switches between a source directory and its corresponding build directory.
# Run without parameters for usage instructions.
#

# guard against sourcing
[[ "$BASH_SOURCE" != "$0" ]] && echo "Don't source this script." >&2 && exit 1

################################################################################
SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="0.1"
CWD="$(pwd)"

function help() {
	cat <<-EOH
	Switches between a source directory and its corresponding build directory
	(it actually only prints where go to).
	
	Usage:  ${SCRIPTNAME}  [options]
	
	Options
	--tosrc , -s
	--tobuild , -b
	--toinstall , --tolocal, --tolp, -i, -l
	    selects which directory to print; by default, depending on where we
	    currently are:
	    * build directory: print source directory
	    * source directory: print build directory
	    * top or install directory: print source directory
	    * otherwise: prints an error message, then source directory
	--quiet , -q
	    don't print any error message
	
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

# default parameters
declare -i BeQuiet=0
declare Src='' Dest=''

###
### parameters parsing
###
declare -i NoMoreOptions=0
declare -a Arguments
declare -i nArguments=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1  ;;
			( '--version' | '-V' ) DoVersion=1  ;;
			
			( '--tosrc' | '-s' ) Dest="MRB_SOURCE" ;;
			( '--tobuild' | '-b' ) Dest="MRB_BUILDDIR" ;;
			( '--toinstall' | '--tolp' | '--tolocal' | '-i' | '-l' )
				Dest="MRB_INSTALL" ;;
			
			( '--quiet' | '-q' ) BeQuiet=1 ;;
			
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
		Arguments[nArguments++]="*${Param}*"
	fi
done

if isFlagSet DoHelp || [[ $nArguments -gt 0 ]]; then
	help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	exit $?
fi

if isFlagSet DoVersion ; then
	echo "${SCRIPTNAME} version ${SCRIPTVERSION}"
	exit 0
fi

[[ -d "$MRB_TOP" ]] || FATAL 1 "No MRB working area is set up."

###
### autodetect where we are
###
declare SubDir=''
if [[ -z "$Src" ]]; then
	for TestVar in MRB_BUILDDIR MRB_SOURCE MRB_INSTALL MRB_TOP ; do
		Dir="${!TestVar}"
		[[ -n "$Dir" ]] || continue
		
		[[ "${CWD#$Dir}" == "$CWD" ]] && continue
		
		SubDir="${CWD#${Dir}}"
		# is it a coincidence? ('build.x86_64' matches 'build'...)
		[[ -n "$SubDir" ]] && [[ "${SubDir:0:1}" != '/' ]] && continue
		
		Src="$TestVar"
		break
	done
fi

###
### autodetect where to go
###
if [[ -z "$Dest" ]]; then
	case "$Src" in
		( "MRB_SOURCE" )   Dest="MRB_BUILDDIR" ;;
		( "MRB_INSTALL" )  Dest="MRB_SOURCE" ;;
		( "MRB_BUILDDIR" ) Dest="MRB_SOURCE" ;;
		( "MRB_TOP" )      Dest="MRB_SOURCE" ;;
		( "" )
			isFlagSet BeQuiet || STDERR "I have no idea where I am: heading to source directory."
			Dest="MRB_SOURCE"
			;;
	esac
fi

if [[ "$Dest" == "MRB_INSTALL" ]]; then
	# local products directory has a simpler structure
	SubDir="${SubDir:1}"
	SubDir="/${SubDir%%/*}"
	if [[ -n "$MRB_PROJECT_VERSION" ]]; then
		SubDir+="/${MRB_PROJECT_VERSION}"
		[[ -d "${MRB_INSTALL}/${SubDir}" ]] || SubDir="$(dirname "$SubDir")"
	fi
fi

###
### Go!
###

[[ -z "$Dest" ]] && FATAL 1 "BUG: I am lost, I don't know where to go!"

DestDir="${!Dest}"
[[ -z "$DestDir" ]] && FATAL 1 "Destination '${Dest}' is not defined!"

DestDir+="$SubDir"

echo "$DestDir"

[[ -d "$DestDir" ]] || exit 3
exit 0
###
