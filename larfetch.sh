#!/bin/bash
#
# Fetches from the origin repository and rebases to the festure branches.
# 
# Usage:  larconnectgit.sh  RepoAlias RepoLocalPath
#

SCRIPTDIR="$(dirname "$0")"
: ${BASEDIR:="$(dirname "$(readlink -f "$SCRIPTDIR")")"}

: ${RepoAlias:="origin"}

SourceDirName='srcs'

# go down to the srcs directory
if [[ ! -d "${BASEDIR}/${SourceDirName}" ]]; then
	BASEDIR="$(pwd)"
	while [[ ! -d "${BASEDIR}/${SourceDirName}" ]] && [[ "$BASEDIR" != '/' ]]; do
		BASEDIR="$(dirname "$BASEDIR")"
	done
fi

if [[ ! -d "${BASEDIR}/${SourceDirName}" ]]; then
	: ${SRCDIR:="."}
else
	: ${SRCDIR:="${BASEDIR}/${SourceDirName}"}
fi

function GitFetchAndRebase() {
	local Package="$1"
	local RemoteRepo="$2"
	shift 2
	
	if [[ -r '.git/rebase-apply/patch' ]]; then
		local Current="$(git branch | grep -F ' * ' | cut -b 4-)"
		echo "Patch found => rebasing to the current branch ${Current}"
		git rebase "$@"
		[[ $? != 0 ]] && let ++nErrors
		return $nErrors
	fi
	
	
	echo "Fetching ${Package} from ${RemoteRepo}..."
	git fetch "$RemoteRepo" || return 1
	local Branch Empty Dummy Current=''
	local -i nErrors=0
	while read Branch Empty Dummy ; do
		if [[ "$Branch" == '*' ]]; then
			if [[ -n "$Dummy" ]]; then
				echo "Got an error message: ${Empty} ${Dummy}" >&2
				let ++nErrors
				continue
			fi
			Branch="$Empty"
			Empty=''
			Current="$Branch"
		elif [[ -n "$Empty" ]]; then
			echo "Got an error message: ${Branch} ${Empty} ${Dummy}" >&2
			let ++nErrors
			continue
		fi
		if [[ "$Branch" != "develop" ]] && [[ "${Branch#feature/}" == "$Branch" ]]; then
			echo "  ('${Branch}' skipped)"
			continue
		fi
		if [[ "$Current" == "$Branch" ]]; then
			echo " - '${Branch}' (current)"
		else
			echo " - '${Branch}'"
		fi
		
		git rebase "$@" "${RemoteRepo}/develop" "$Branch"
		if [[ $? != 0 ]]; then
			let ++nErrors
			break
		fi
		
	done < <(git branch)
	
	if [[ -n "$Current" ]]; then
		echo " => back to '${Current}'"
		git checkout "$Current"
		[[ $? == 0 ]] || let ++nErrors
	fi
	return $nErrors
} # GitFetchAndRebase()

export -f GitFetchAndRebase
"${SCRIPTDIR}/larcommands.sh" ${FAKE:+--dry-run} --tag="PACKAGENAME" -- GitFetchAndRebase '%PACKAGENAME%' "$RepoAlias" "$@"

nPatches=$(ls "${MRB_SOURCE}/"*"/.git/rebase-apply/patch" 2> /dev/null | wc -l)
if [[ $nPatches -gt 0 ]]; then
	echo "${nPatches} patches are left behind:"
	ls "${MRB_SOURCE}/"*"/.git/rebase-apply/patch"
fi
exit $nPatches
