#!/bin/bash
#
# This is just a wrapper to ShowUPSsource.sh that tries to guess
# the package name from its own name.
#

SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"

# process the package name
declare PackageName="${SCRIPTNAME,,}"
PackageName="${PackageName#show}"
PackageName="${PackageName%%.*}" # remove everything after the first dot
PackageName="${PackageName%sources}"
PackageName="${PackageName%source}"

# run the original script
"${SCRIPTDIR:+"${SCRIPTDIR}/"}ShowUPSsource.sh" --package="$PackageName" "$@"

