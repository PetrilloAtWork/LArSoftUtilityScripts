#!/bin/bash
#
# Prints the specified branches from all the packages
# 
# Usage:  larconnectgit.sh  RepoAlias RepoLocalPath
#

SCRIPTDIR="$(dirname "$0")"


function hasGitBranch() {
	local Package="$1"
	shift
	local -a BranchPatterns=( "$@" )
	
	local -a Items
	local -i NBranches=0
	while read -a Items ; do
		Branch="${Items[0]}"
		
		local -i Current=0
		local -i Remote=0
		
		# detect if current; if so, fix the branch name
		if [[ "$Branch" == '*' ]]; then
			Branch="${Items[1]}"
			Current=1 # we don't use this information so far
		fi
		
		# detect if remote; if so, change the branch name
		if [[ "${Branch#remotes/}" != "$Branch" ]]; then
			Branch="${Branch#remotes/}"
			Remote=1
		fi
		
		for Pattern in "${BranchPatterns[@]}" ; do
			[[ "$Branch" =~ $Pattern ]] || continue
			if [[ $NBranches == 0 ]]; then
				echo "${Package}:"
			fi
			if isFlagSet Remote ; then
				echo "  ${Branch} (remote)"
			else
				echo "  ${Branch}"
			fi
			let ++NBranches
			break
		done
		
	done < <(git branch -a)
	return 0
} # hasGitBranch()

export -f hasGitBranch
"${SCRIPTDIR}/larcommands.sh" ${FAKE:+--dry-run} --quiet --tag="PACKAGENAME" -- hasGitBranch '%PACKAGENAME%' "$@"




