#!/usr/bin/env bash
#
# Executes the same GIT command on all git projects:
# 
# check out ups/product_deps file from the current branch.
# 
# Run '--help' for help usage
# (and keep in mind that the --git and --tag=PACKAGENAME options are always
# applied)
#

SCRIPTDIR="$(dirname "$0")"

function help() {
  cat <<EOH

Print the message of the last entry of the GIT log.

Usage:  ${SCRIPTNAME}  [options]

EOH
  help_baseoptions
  
} # help()

#
# print the last entry of the log;
# print it on a single line;
# prepend the repository name first, aligned in 20 characters, before that line.
#
source "${SCRIPTDIR}/larcommands.sh" "$@" --git -- checkout ups/product_deps
