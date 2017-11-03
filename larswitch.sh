#!/usr/bin/env bash
#
# Switches between a source directory and its corresponding build directory.
# Run without parameters for usage instructions.
# 
# Changes:
# 20160826 (petrillo@fnal.gov) [v1.0]
#   repacakged to use larsoft_scriptutils
# ???????? (petrillo@fnal.gov) [v0.1]
#   original version
#

hasLArSoftScriptUtils >& /dev/null || source "${LARSCRIPTDIR}/larsoft_scriptutils.sh"
mustNotBeSourced || return 1


SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"
SCRIPTVERSION="1.0"
CWD="$(pwd)"


################################################################################
function help() {
	cat <<-EOH
	Switches between a source directory and its corresponding build directory
	(it actually only prints where go to).
	
	Usage:  ${SCRIPTNAME}  [options]  [Directory]
	
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
	--debug[=LEVEL] , -d
	    sets the verbosity level (if no level is specified, level 1 is set)
	
	EOH
} # help()


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
      ( '--debug='* ) DEBUG="${Param#--*=}" ;;
      ( '--debug' | '-d' ) DEBUG=1 ;;
      
      ( '--tosrc' | '-s' ) Dest="SOURCE" ;;
      ( '--tobuild' | '-b' ) Dest="BUILDDIR" ;;
      ( '--toinstall' | '--tolp' | '--tolocal' | '-i' | '-l' )
        Dest="INSTALL" ;;
      
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
    Arguments[nArguments++]="$Param"
  fi
done

if isFlagSet DoHelp || [[ $nArguments -gt 1 ]]; then
  help
  # set the exit code (0 for help option, 1 for missing parameters)
  isFlagSet DoHelp
  exit $?
fi

if isFlagSet DoVersion ; then
  echo "${SCRIPTNAME} version ${SCRIPTVERSION}"
  exit 0
fi

if [[ $nArguments == 0 ]]; then
  Dir="$CWD"
else
  Dir="${Arguments[0]}"
fi

WorkingAreaType >& /dev/null || FATAL 1 "No working area is set up."

###
### autodetect where we are
###
declare SubDir='' BaseVarName=''
if [[ -z "$Src" ]]; then
  LocationName=$(DetectMRBLocation "$Dir")
  if [[ $? == 0 ]]; then
    Src="$LocationName"
    SubDir="$(SubpathTo "$Dir" "$(getWorkingAreaDir "$Src")")"
    DBGN 2 "Detected the current location to be under '<${Src}>${SubDir:+/${SubDir}}'"
  fi
fi

###
### autodetect where to go
###
if [[ -z "$Dest" ]]; then
  case "$Src" in
    ( "SOURCE" )   Dest="BUILDDIR" ;;
    ( "INSTALL" )  Dest="SOURCE" ;;
    ( "BUILDDIR" ) Dest="SOURCE" ;;
    ( "TOP" )      Dest="SOURCE" ;;
    ( "" )
      isFlagSet BeQuiet || STDERR "I have no idea where I am: heading to source directory."
      Dest="SOURCE"
      ;;
  esac
  DBGN 1 "Decided to go to ${Dest}"
fi

declare TargetDir=''
if [[ "$Dest" == "INSTALL" ]]; then
  # local products directory has a simpler structure
  
  if [[ "$BaseVarName" != 'TOP' ]] && [[ -n "$SubDir" ]]; then
    DBGN 2 "Target install directory set to: '${TargetDir}'"
    TargetDir="/${SubDir%%/*}"
      
    [[ -n "$MRB_PROJECT_VERSION" ]] && TargetDir+="/${MRB_PROJECT_VERSION}"
    DBGN 2 "Target install directory expanded to: '${TargetDir}'"
  
    FullTargetDir="$(MRBInstallDir)"
    if [[ ! -d "$FullTargetDir" ]]; then
      TargetDir="$(dirname "$TargetDir")"
      DBGN 2 "Target install directory simplified to: '${TargetDir}'"
    fi
  fi
  
else
  TargetDir="${SubDir:+/${SubDir}}"
  DBGN 2 "Target directory set to: '<${Dest}>${TargetDir}'"
fi

###
### Go!
###

[[ -z "$Dest" ]] && FATAL 1 "BUG: I am lost, I don't know where to go!"

DestDir="$(getWorkingAreaDir "$Dest")"
[[ -z "$DestDir" ]] && FATAL 1 "Destination '${Dest}' is not defined!"

DestDir+="${TargetDir}"

echo "$DestDir"

[[ -d "$DestDir" ]] || exit 3
exit 0
###
