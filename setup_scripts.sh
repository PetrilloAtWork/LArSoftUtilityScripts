#!/usr/bin/env bash
#
# Sets some environment for LArSoft scripts
#

LARSCRIPTDIR="$(dirname "$BASH_SOURCE")"

echo "Setting up LArSoft scripts in '${LARSCRIPTDIR}'"
export LARSCRIPTDIR

###############################################################################
###
###
if declare -F AddToPath >& /dev/null ; then
	AddToPath PATH "$LARSCRIPTDIR"
else
	PATH+=":${LARSCRIPTDIR}"
fi

###############################################################################
### greadlink
###
if ! type -t greadlink > /dev/null ; then
	# aliases are not expanded in non-interactive shells, so let's use a function
	function greadlink() { readlink "$@" ; }
	export -f greadlink 
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


###############################################################################
### goninja
###
function goninja() {
	pushd "$MRB_BUILDDIR" > /dev/null
	ninja "$@"
	popd > /dev/null
} # goninja()

