#!/usr/bin/env bash
#
# Goes to the source directory of the specified package.
# Run without parameters for usage instructions.
#

# guard against sourcing
[[ "$BASH_SOURCE" != "$0" ]] && echo "Don't source this script." >&2 && exit 1

################################################################################
SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.0"
CWD="$(pwd)"

function help() {
	cat <<-EOH
	Goes to the source directory of the specified package
	(it actually only prints where go to).
	
	Usage:  ${SCRIPTNAME}  PackageName[/SubPath]
	
	Options
	--tosrc , -s
	--tobuild , -b
	--toinstall , --tolocal, --tolp, -i, -l
	    selects which directory to print; by default, print source directory
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
		Arguments[nArguments++]="${Param}"
	fi
done

if isFlagSet DoHelp || [[ $nArguments != 1 ]]; then
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

PackageName="${Arguments[0]}"
SubDir="${PackageName#*/}"
[[ -n "$SubDir" ]] && PackageName="${PackageName%/${SubDir}}"

: ${Dest:="MRB_SOURCE"}

###
### Go!
###

[[ -z "$Dest" ]] && FATAL 1 "BUG: I am lost, I don't know where to go!"

DestBaseDir="${!Dest}"
[[ -z "$DestBaseDir" ]] && FATAL 1 "Destination '${Dest}' is not defined!"

if [[ "$Dest" == "MRB_INSTALL" ]]; then
	# local products directory has a simpler structure
	if [[ -n "$MRB_PROJECT_VERSION" ]]; then
		SubDir="${MRB_PROJECT_VERSION}/${SubDir}"
	fi
fi

for DirName in "$PackageName" "lar${PackageName}" "${PackageName}code" "$PackageName" ; do
	DestDir="${DestBaseDir}/${DirName}"
	[[ -d "$DestDir" ]] || continue
	[[ -n "$SubDir" ]] && DestDir+="/${SubDir}"
	break;
done

echo "$DestDir"

[[ -d "$DestDir" ]] || exit 3
exit 0
###
