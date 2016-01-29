#!/usr/bin/env bash
#
# Sets some environment for LArSoft scripts
#

LARSCRIPTDIR="$(dirname "$BASH_SOURCE")"

echo "Setting up LArSoft scripts in '${LARSCRIPTDIR}'"
export LARSCRIPTDIR

AddToPath PATH "$LARSCRIPTDIR"

if ! type -t greadlink ; then
	# aliases are not expanded in non-interactive shells, so let's use a function
	function greadlink() { readlink "$@" ; }
	export -f greadlink 
fi

if [[ -x "${LARSCRIPTDIR}/larswitch.sh" ]]; then
	function larswitch() { cd "$("${LARSCRIPTDIR}/larswitch.sh" "$@")" ; }
fi

if [[ -x "${LARSCRIPTDIR}/FindInPath.sh" ]]; then
	alias FindFCL="${LARSCRIPTDIR}/FindInPath.sh --fcl"
fi

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

function goninja() {
	pushd "$MRB_BUILDDIR" > /dev/null
	ninja "$@"
	popd > /dev/null
} # goninja()

