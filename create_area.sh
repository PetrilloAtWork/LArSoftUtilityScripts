#!/usr/bin/env bash
#
# Creates a new working area.
# Run without parameters for usage instructions.
#

function IsInList() {
	# IsInList Key ListItem [...]
	
	local Key="$1"
	shift
	local Item
	for Item in "$@" ; do
		[[ "$Key" == "$Item" ]] && return 0
	done
	return 1
} # IsInList()


function SortUPSqualifiers() {
	# Usage:  SortUPSqualifiers  Qualifiers [Separator]
	# sorts the specified qualifiers (colon separated by default)
	# The current sorting is: alphabetically, but move debug/opt/prof to the end
	local qual="$1"
	local sep="${2:-":"}"
	local item
	local -i nItems=0
	local -ar AllSpecials=( 'prof' 'opt' 'debug' )
	local -a Specials
	for item in $(tr "$sep" '\n' <<< "$qual" | sort) ; do
		if IsInList "$item" "${AllSpecials[@]}" ; then
			Specials=( "${Specials[@]}" "$item" )
			continue
		fi
		[[ "$((nItems++))" == 0 ]] || echo -n "$sep"
		echo -n "$item"
	done
	# add the special qualifiers at the end, in the original relative order
	for item in "${Specials[@]}" ; do
		[[ "$((nItems++))" == 0 ]] || echo -n "$sep"
		echo -n "$item"
	done
	echo
	return 0
} # SortUPSqualifiers()


function CheckSetup() {
	#
	# checks that everything is fine with the current settings
	#
	which ups >& /dev/null || {
		echo "FATAL ERROR: UPS not configured!"
		return 1
	}
	if ! declare -f setup unsetup >& /dev/null ; then
		cat <<-EOM
		ERROR: setup/unsetup not available!
		
		UPS may be correctly set up, but its setup/unsetup functions are not visible to scripts.
		A way to correct that in bash is to execute:
		
		export -f setup unsetup
		
		EOM
		echo "FATAL ERROR: UPS is not fully operative in script environment." >&2
		return 1
	fi
	return 0
} # CheckSetup()


# ------------------------------------------------------------------------------
function DoCreateArea() {

  local SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
  
  local DefaultVersion="${LARSOFT_VERSION:-develop}"

  local Version Qualifiers NewAreaPath Experiment
  
  # autodetection picks default values from `${SCRIPTDIR}/setup/defaults`;
  # it should really really work
  local autodetection_script="$(which 'autodetectLArSoft.sh' 2> /dev/null)"
  [[ -r "$autodetection_script" ]] || autodetection_script="${SCRIPTDIR}/autodetectLArSoft.sh"
  if [[ -r "$autodetection_script" ]] ; then
    local -a autodetection=( $("$SHELL" "$autodetection_script" --defaults --loose -v -q -e -L -p "$DefaultVersion" ) )
    Version="${autodetection[0]}"
    Qualifiers="${autodetection[1]}"
    Experiment="${autodetection[2]}"
  else
    Version="$DefaultVersion"
    Qualifiers="${MRB_QUALS:-e20:prof}"
    Experiment="LArSoft"
  fi
  NewAreaPath="${Version}/${Qualifiers//:/_}"
  
  if [[ $# == 0 ]]; then
    cat <<-EOH
Creates and sets up a new LArSoft working area.

Usage:  source $(basename "$BASH_SOURCE") LArSoftVersion LArSoftQualifiers NewAreaPath Experiment

All parameters are optional, but they need to be specified if a following one
is also specified.
If LArSoftVersion is not specified or empty, it is autodetected (now: '${Version}').
If LArSoftQualifiers is not specified or empty, it is autodetected (now: '${Qualifiers}'.
If NewAreaPath is not specified or empty, it defaults to LArSoftVersion/LArSoftQualifiers.
The parameter Experiment is autodetected out of the current path if it is not
specified or if it is "auto".

EOH
    
    return
  fi

  ###
  ### parameters parsing
  ###
  [[ -n "$1" ]] && Version="$1"
  [[ -n "$2" ]] && Qualifiers="$2"
  [[ -n "$3" ]] && NewAreaPath="$3"
  [[ -n "$4" ]] && Experiment="$4"

  Qualifiers="$(SortUPSqualifiers "${Qualifiers//_/:}")"
  unset -f SortUPSqualifiers IsInList

  if [[ -z "$NewAreaPath" ]] && [[ -n "$Version" ]]; then
    NewAreaPath="${Version}/${Qualifiers//:/_}"
  fi

  if [[ "$BASH_SOURCE" == "$0" ]]; then
    cat <<-EOM
Experiment:      ${Experiment:-"generic"}
LArSoft version: ${Version} (${Qualifiers})
Location:       '${NewAreaPath}'
This script needs to be sourced:
source $0 $@
EOM
    CheckSetup
    return 1
  fi

  ###
  ### Here we go: we do it!!
  ###

  ###
  ### environment checks
  ###
  if [[ -z "$Version" ]]; then
    echo "You really need to specify a LArSoft version." >&2
    unset SCRIPTDIR NewAreaPath Experiment Version Qualifiers
    return 1
  fi

  # check that UPS is set up
  CheckSetup || return $?

  echo "Creating working area: '${NewAreaPath}'"


  ###
  ### set up
  ###
  source "${SCRIPTDIR}/setup/setup" "base" "$Version" "$Qualifiers"


  ###
  ### creation of the new area
  ###
  if [[ -d "$NewAreaPath" ]]; then
    echo "The working area '${NewAreaPath}' already exists." >&2
    cd "$NewAreaPath"
    return 1
  else
    mkdir -p "$NewAreaPath"
    if ! cd "$NewAreaPath" ; then
      echo "Error creating the new area in '${NewAreaPath}'." >&2
      return 1
    fi
    
    local TestScript="./ExecTest-$$.sh"
    cat <<-EOS > "$TestScript"
#!/usr/bin/env bash
echo "success!"
EOS
    chmod a+x "$TestScript"
    echo -n "Testing exec... "
    "$TestScript"
    if [[ $? != 0 ]]; then
      echo "The area '${NewAreaPath}' seems not suitable for compilation." >&2
      return 1
    fi
    rm "$TestScript"
    
    echo "Creating the new working area '${NewAreaPath}'"
    mrb newDev -v "$Version" -q "$Qualifiers"
    
    if [[ -r "${SCRIPTDIR}/setup/devel" ]]; then
      echo "Linking the developement setup script (and sourcing it!)"
      rm -f 'setup'
      ln -s "${SCRIPTDIR}/setup/devel" 'setup'
      source './setup'
    else
      echo "Can't find developement setup script ('${SCRIPTDIR}/setup/devel'): setup not linked." >&2
    fi
    
    : ${MRB_INSTALL:="${NewAreaPath}/localProducts_${MRB_PROJECT}_$(autodetectLArSoft.sh --localprod)"}
    
    if [[ -d "$MRB_INSTALL" ]]; then
      echo "Creating link 'localProducts' to MRB_INSTALL directory"
      rm -f 'localProducts'
      ln -s "$MRB_INSTALL" 'localProducts'
    else
      echo "Expected local products directory '${MRB_INSTALL}' not found. You'll need to complete setup on your own." >&2
      unset MRB_INSTALL
    fi
  fi
  
  # for some reasons `cetpkgsupport` always interferes with a following `mrbsetenv`
  unsetup cetpkgsupport

  mkdir -p "logs" "job"
  cd "srcs"

  ###
} # DoCreateArea()


function CreateAreaWrapper() {
  
  DoCreateArea "$@"
  local res=$?
  
  unset CreateAreaWrapper DoCreateArea
  
  return $res
} # CreateAreaWrapper()


CreateAreaWrapper "$@"
