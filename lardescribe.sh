#!/bin/bash
#
# Executes the same GIT command on all git projects:
# 
# print the current branch
# 
# Run '--help' for help usage
# (and keep in mind that the --git and --tag=PACKAGENAME options are always
# applied)
#

SCRIPTDIR="$(dirname "$0")"

"${SCRIPTDIR}/larcommands.sh" --compact=prepend+20 --git describe