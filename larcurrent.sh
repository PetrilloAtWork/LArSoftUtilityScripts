#!/bin/bash
#
# Executes the same GIT command on all git projects.
# 
# Run '--help' for help usage
# (and keep in mind that the --git and --tag=PACKAGENAME options are always
# applied)
#

SCRIPTDIR="$(dirname "$0")"

function PrintPackageAndBranch() {
	local PackageName="$1"
	local CurrentBranch
	CurrentBranch="$(git rev-parse --abbrev-ref HEAD)"
	local res=$?
	echo -n "${CurrentBranch} [${PackageName}]"
	if [[ $res != 0 ]]; then
		echo -n " (error code: ${res})"
	fi
	echo
	return $res
} # PrintPackageAndBranch()

export -f PrintPackageAndBranch
"${SCRIPTDIR}/larcommands.sh" --quiet --tag=PACKAGENAME PrintPackageAndBranch '%PACKAGENAME%'
