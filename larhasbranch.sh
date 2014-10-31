#!/bin/bash
#
# Prints the specified branches from all the packages
# 
# Usage:  larconnectgit.sh  RepoAlias RepoLocalPath
#

SCRIPTDIR="$(dirname "$0")"


function hasGitBranch() {
	local Package="$1"
	shift 1
	local -a Branches=( "$@" )
	
	git branch -a | while read -a Items ; do
		Branch="${Items[0]}"
		[[ "$Branch" == '*' ]] && Branch="${Items[1]}"
		
		Remote=0
		if [[ "${Branch#remotes/}" != "$Branch" ]]; then
			Branch="${Branch#remotes/}"
			Remote=1
		fi
		
		for TargetBranch in "${Branches[@]}" ; do
			[[ "$Branch" == "$TargetBranch" ]] || continue
			if isFlagSet Remote ; then
				echo "  ${TargetBranch} (remote)"
			else
				echo "  ${TargetBranch}"
			fi
		done
		
	done
	return 0
} # hasGitBranch()

export -f hasGitBranch
"${SCRIPTDIR}/larcommands.sh" ${FAKE:+--dry-run} --tag="PACKAGENAME" -- hasGitBranch '%PACKAGENAME%' "$@"

exit 0
