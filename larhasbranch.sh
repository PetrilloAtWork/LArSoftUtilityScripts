#!/usr/bin/env bash
#
# Prints the specified branches from all the packages
# 
# Usage:  larconnectgit.sh  RepoAlias RepoLocalPath
#

SCRIPTDIR="$(dirname "$0")"

function isFlagSet() { local VarName="$1" ; [[ -n "${!VarName//0}" ]] ; }

declare BranchOptionName='ifhasbranch'

declare -a GenOptions
declare -a BranchOptions
declare -i NoMoreOptions=0
declare Param

for Param in "$@" ; do
	if [[ "${Param:0:1}" == '-' ]] && ! isFlagSet NoMoreOptions; then
		case "$Param" in
			( '--current' ) BranchOptionName='ifcurrentbranch' ;;
			( '-' | '--' ) NoMoreOptions=1 ;;
			( * ) GenOptions=( "${GenOptions[@]}" "$Param" ) ;;
		esac
	else
		BranchName="$Param"
		BranchOptions=( "${BranchOptions[@]}" "--ifhasbranch=${BranchName}" )
	fi
done

"${SCRIPTDIR}/larcommands.sh" ${FAKE:+--dry-run} --quiet --tag="PACKAGENAME" "${BranchOptions[@]}" "${GenOptions[@]}" -- echo '%PACKAGENAME%'
