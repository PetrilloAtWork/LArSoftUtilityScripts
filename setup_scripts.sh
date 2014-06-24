#!/bin/bash
#
# Sets some environment for LArSoft scripts
#

LARSCRIPTDIR="$(dirname "$BASH_SOURCE")"

echo "Setting up LArSoft scripts in '${LARSCRIPTDIR}'"
export LARSCRIPTDIR

AddToPath PATH "$LARSCRIPTDIR"

if [[ -x "${LARSCRIPTDIR}/larswitch.sh" ]]; then
	function larswitch() { cd "$("${LARSCRIPTDIR}/larswitch.sh" "$@")" ; }
fi

if [[ -x "${LARSCRIPTDIR}/FindInPath.sh" ]]; then
	alias FindFCL="${LARSCRIPTDIR}/FindInPath.sh --fcl"
fi
