#!/usr/bin/env bash
#
# Sets some environment for LArSoft scripts
#

LARSCRIPTDIR="$(dirname "$BASH_SOURCE")"

echo "Setting up LArSoft scripts in '${LARSCRIPTDIR}'"
export LARSCRIPTDIR


###############################################################################
### set up
###
if declare -F AddToPath >& /dev/null ; then
	AddToPath PATH "$LARSCRIPTDIR"
else
	PATH+=":${LARSCRIPTDIR}"
fi

###############################################################################
### grealpath
###
if ! type -t grealpath > /dev/null ; then
	# aliases are not expanded in non-interactive shells, so let's use a function
	if type -t realpath > /dev/null ; then
		function grealpath() { realpath "$@" ; }
	elif type -t greadlink > /dev/null ; then
		function grealpath() { greadlink -f "$@" ; }
	else
		function grealpath() { readlink -f "$@" ; }
	fi
	export -f grealpath 
fi

###############################################################################
### larswitch, lartestswitch
###
if [[ -x "${LARSCRIPTDIR}/larswitch.sh" ]]; then
	function larswitch() { cd "$("${LARSCRIPTDIR}/larswitch.sh" "$@")" ; }
fi
if [[ -x "${LARSCRIPTDIR}/lartestswitch.sh" ]]; then
	function lartestswitch() { cd "$("${LARSCRIPTDIR}/lartestswitch.sh" "$@")" ; }
fi

###############################################################################
### FindFCL
###
if [[ -x "${LARSCRIPTDIR}/FindInPath.py" ]]; then
	alias FindFCL="${LARSCRIPTDIR}/FindInPath.py --fcl"
fi


###############################################################################
### gotorepo , nextrepo , prevrepo
###
if [[ -x "${LARSCRIPTDIR}/largotorepo.sh" ]]; then
	function gotorepo() {
		local DirName
		DirName="$("${LARSCRIPTDIR}/largotorepo.sh" --noerror "$@" )"
		local -i res="$?"
		if [[ -n "$DirName" ]]; then
			[[ $res != 0 ]] && echo "  (jumping anyway)" >&2
			cd "$DirName" && return $res
		else
			return $res
		fi
	}
	function nextrepo() { gotorepo ${1:-+1} ; }
	function prevrepo() { gotorepo -${1:-1} ; }
fi


###############################################################################
### setupLatest
###

function setupLatest() {
  
  local Option
  local DoHelp=0 Quiet=0 Fake=0
  local -a RequiredQualifiers
  OPTIND=1
  while getopts ":q:Qnh-" Option ; do
    case "$Option" in
      ( 'q' ) RequiredQualifiers+=( ${OPTARG//:/ } ) ;;
      ( 'Q' ) Quiet=1 ;;
      ( 'n' ) Fake=1 ;;
      ( 'h' ) DoHelp=1 ;;
      ( '-' ) break ;;
      ( * )
        if [[ "$Option" == '?' ]] && [[ "$OPTARG" == '?' ]]; then
          DoHelp=1
        else
          CRITICAL "$OPTERR" "${FUNCNAME}: option '${OPTARG}' not supported."
          return
        fi
        ;;
    esac
  done
  shift $((OPTIND - 1))
  
  if isFlagSet DoHelp ; then
		cat <<-EOH
			
			${FUNCNAME}  [options] ProductName [Qualifiers]
			
			Sets the Returns the latest product version with at least the specified qualifiers.
			The output format is:
			    
			    <ProductName> <Version> <Qualifiers>
			    
			Options:
			-q QUALIFIERS
			    additional required qualifiers
			-Q
			    do not print the setup command being issued
			-n
			    do not actually issue the setup command (dry run)
			-h , -?
			    print this help
		
		EOH
    return 
  fi
  
  local Product="$1"
  local RequiredQualifiers="$2"
  
  local -a LatestProduct
  LatestProduct=( $( "${LARSCRIPTDIR}/findLatestUPS.sh" "$Product" "$RequiredQualifiers" ) )
  local res=$?
  if [[ $res != 0 ]]; then
    CRITICAL $res "No product '${Product}' found${RequiredQualifiers:+" compatible with all qualifiers '${RequiredQualifiers}'"}" >&2
    return $res
  fi
  local -a Cmd=( setup "${LatestProduct[0]}" "${LatestProduct[1]}" ${LatestProduct[2]:+ -q "${LatestProduct[2]}"} )
  isFlagUnset Quiet && echo "${Cmd[@]}"
  isFlagUnset Fake && source "$(ups "${Cmd[@]}" )"
  
} # setupLatest()


###############################################################################
### setup_LArSoft , setup_as_LArSoft, setup_as
###
if [[ -r "${LARSCRIPTDIR}/setup" ]]; then
	function setup_LArSoft() {
		local Target="${1:-base}"
		local SetupScript="${LARSCRIPTDIR}/setup/${Target}"
		if [[ ! -r "$SetupScript" ]]; then
			echo "ERROR: no LArSoft setup for '${Target}'" >&2
			return 2
		fi
		source "$SetupScript"
	} # setup_LArSoft()
fi

function setup_as_LArSoft() { setup_as 'larsoft' "$@" ; }


function setup_as() {
	
	local ReferenceProduct="$1"
	shift
	
	local -a Products=( "$@" )
	if [[ "${#Products[@]}" == 0 ]]; then
		echo "Set up the specified packages with the same version and qualifiers as the currently set up '${ReferenceProduct}'." >&2
		return 1
	fi

	local SetupVarName="SETUP_$(tr '[[:lower:]]' '[[:upper:]]' <<< "$ReferenceProduct")"
	if [[ -z "${!SetupVarName}" ]]; then
		echo "UPS product '${ReferenceProduct}' not set up." >&2
		return 1
	fi
	
	local -a ProductSetup=( ${!SetupVarName} )
	
	local Version="${ProductSetup[1]}"
	local Qualifiers=''
	
	local -i iWord
	local -ir nWords="${#ProductSetup[@]}"
	for (( iWord = 0 ; iWord < $nWords ; ++iWord )); do
		local Word="${ProductSetup[iWord]}"
		if [[ "$Word" == '-q' ]]; then
			Qualifiers="${ProductSetup[++iWord]}"
		fi
	done
		
	
	if [[ -z "$Version" ]] || [[ -z "$Qualifiers" ]]; then
		echo "UPS package '${ReferenceProduct}' is not correctly set up." >&2
		return 1
	fi
	
	local Product
	local -i nErrors=0
	for Product in "${Products[@]}" ; do
		local -a Cmd=( setup "$Product" "$Version" -q "$Qualifiers" )
		echo "${Cmd[@]}"
		"${Cmd[@]}" || let ++nErrors
	done
	return $nErrors
} # setup_as()

################################################################################
### bash completion
###
function LArScript_setup_completions() {
  
  local CompletionScriptDir="${LARSCRIPTDIR}/completion"
  local CompletionScript
  for CompletionScript in "$CompletionScriptDir"/* ; do
    [[ -r "$CompletionScript" ]] || continue
    source "$CompletionScript"
  done
  
  unset LArScript_setup_completions
} # LArScript_setup_completions

LArScript_setup_completions



