#!/usr/bin/env bash
#
# Runs a sequence of mrb gitCheckout
#

SCRIPTNAME="$(basename "$0")"


function STDERR() { echo "$*" >&2; }
function ERROR() { STDERR "ERROR: $*" ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL (${Code}): $*"
	exit $Code
} # FATAL()


function help() {
	cat <<-EOH
	Executes a sequence of mrb gitCheckout (setting the repositories to develop branch).
	
	Usage:  ${SCRIPTNAME} Repository [Repository ...]
	
	EOH
} # help()


#
# preliminary checks
#
[[ -n "$MRB_SOURCE" ]] || FATAL 1 "MRB not correctly set up: no 'MRB_SOURCE' variable defined."


#
# argument parsing
#

declare -a Repositories=( "$@" )
declare -i NRepositories="${#Repositories[@]}"
if [[ $NRepositories -le 0 ]]; then
	help
	exit
fi

#
# operations
#
declare -a FailedRepos
declare -i NFailedRepos
declare -i res=0
declare -i nErrors=0
for Repository in "${Repositories[@]}" ; do
	cat <<-EOH
	******************************************************************************
	  Checking out: '${Repository}'"
	******************************************************************************
	EOH
	mrb gitCheckout "$Repository"
	res=$?
	if [[ $res != 0 ]]; then
		ERROR "  FAILED!! checkout of '${Repository}' failed with exit code ${res}"
		FailedRepos[NFailedRepos++]="$Repository"
	fi
done

#
# report
#
if [[ $NFailedRepos -gt 0 ]]; then
	echo "******************************************************************************"
	FATAL "$NFailedRepos" "Failed checkout of ${NFailedRepos}/${NRepositories} repositories: ${FailedRepos[@]}"
fi


