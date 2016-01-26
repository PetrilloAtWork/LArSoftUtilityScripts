#!/usr/bin/env bash
#
# Fetches from the origin repository and rebases to the feature branches.
# 
# Usage:  larfetch.sh
#
# Versions
# 20140306 petrillo@fnal.gov [v1.0]
#   original version
# 20141009 petrillo@fnal.gov [v1.1]
#   do not rebase the branches, except for develop and the current branch
#   (I noticed that I did not want to "automatically" update all my feature
#   branches, since it often yields conflicts)
# 20150415 petrillo@fnal.gov [v1.2]
#   rebase feature branches from the tracked branch, or from origin/develop
#

SCRIPTDIR="$(dirname "$0")"
VERSION="1.1"

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

function GetTrackedBranch() {
	local Branch="$1"
	
	# the format is: <branch> <HEAD commit> ["["<tracked branch>"]"] <Commit comment...>
	local TrackInfo="$(git branch -vv --contains "$Branch")"
	local Words
	read -a Words <<< "$TrackInfo"
	local -i TrackBranchIndex=2
	[[ "${Words[0]}" == '*' ]] && let ++TrackBranchIndex
	[[ "${Words[$TrackBranchIndex]}" =~ ^\[(.*)[\]:]$ ]] || return 1
	echo "${BASH_REMATCH[1]}"
	return 0
} # GetTrackedBranch()

function GetCurrentBranch() {
	local Response="$(git branch --contains HEAD)"
	local Current Branch
	read Current Branch Junk <<< "$Response"
	if [[ "$Current" != "*" ]]; then
		ERROR "Unexpected: 'git branch --contains HEAD' does not show the current branch mark"
	fi
	if [[ -n "$Junk" ]]; then
		ERROR "Unexpected: additional junk after branch name: '${Response}'"
	fi
	echo "$Branch"
} # GetCurrentBranch()

function GitFetchAndRebase() {
	local -r HIGHLIGHT="$ANSIYELLOW"
	local -r HIGHLIGHTREBASE="$ANSICYAN"
	
	local Package="$1"
	local RemoteRepo="$2"
	shift 2
	
	local Current="$(GetCurrentBranch)"
	[[ -z "$Current" ]] && FATAL 1 "Can't find current branch!?"
	DBGN 2 "Current branch: '${Current}'"
	if [[ -r '.git/rebase-apply/patch' ]]; then
		echo "Patch found => rebasing to the current branch ${Current}"
		git rebase "$@"
		[[ $? != 0 ]] && let ++nErrors
		return $nErrors
	fi
	
	
	echo -e "Fetching ${HIGHLIGHT}${Package}${ANSIRESET} from ${RemoteRepo}..."
	git fetch "$RemoteRepo" || return 1
	local Branch Empty Dummy
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
		elif [[ -n "$Empty" ]]; then
			echo "Got an error message: ${Branch} ${Empty} ${Dummy}" >&2
			let ++nErrors
			continue
		fi
		if [[ "$Branch" != "develop" ]] && [[ "${Branch#feature/}" == "$Branch" ]]; then
			DBG "Branch '${Branch}' skipped"
			continue
		fi
	#	if [[ "$Current" == "$Branch" ]]; then
	#		echo -e " - '${Branch}' (current)"
	#	else
	#		echo -e " - '${Branch}'"
	#	fi
		
		if [[ "$Branch" == 'develop' ]] || [[ "$Branch" == "$Current" ]]; then
			local RebaseBranch
			if [[ "$Branch" == "$Current" ]]; then
				RebaseBranch=""
			else
				RebaseBranch="$Branch"
			fi
			
			local TrackedBranch="$(GetTrackedBranch "$Branch")"
			DBGN 3 "Tracked branch: '${TrackedBranch}'"
			local TargetBranch="$TrackedBranch"
			if [[ -z "$TrackedBranch" ]]; then
				# if no branch is tracked, use develop
				TargetBranch='origin/develop'
				TrackedBranch="$TargetBranch"
			else
				# if tracking, git already knows and we don't interfere;
				# but if there is a target branch, then we have to specify
				# a source parameter anyway
				if [[ -z "$RebaseBranch" ]]; then
					TargetBranch=''
				fi
			fi
			
			echo -e " - rebasing '${HIGHLIGHTREBASE}${Branch}${ANSIRESET}' with ${TrackedBranch}"
			local -a RebaseCmd=( git rebase ${TargetBranch:+"$TargetBranch"} ${RebaseBranch:+"$RebaseBranch"} )
			DBGN 1 "Rebase command: ${RebaseCmd[@]}"
			"${RebaseCmd[@]}"
			if [[ $? != 0 ]]; then
				let ++nErrors
				break
			fi
			DBGN 3 "Going back to '${Current}'"
			[[ -n "$RebaseBranch" ]] && git checkout -q "$Current" # did the previous command check out develop?
		fi
	done < <(git branch)
	
	if [[ -n "$Current" ]]; then
		echo " => back to '${Current}'"
		git checkout -q "$Current"
		[[ $? == 0 ]] || let ++nErrors
	fi
	return $nErrors
} # GitFetchAndRebase()

export -f GitFetchAndRebase GetTrackedBranch
"${SCRIPTDIR}/larcommands.sh" --tag="PACKAGENAME" --command=2 GitFetchAndRebase '%PACKAGENAME%' "$RepoAlias" "$@"

nPatches=$(ls "${MRB_SOURCE}/"*"/.git/rebase-apply/patch" 2> /dev/null | wc -l)
if [[ $nPatches -gt 0 ]]; then
	echo "${nPatches} patches are left behind:"
	ls "${MRB_SOURCE}/"*"/.git/rebase-apply/patch"
fi
exit $nPatches
