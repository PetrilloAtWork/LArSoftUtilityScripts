#!/usr/bin/env bash
#
# Puts all the changes in the current branch in a new feature
# 
# Usage:  larnewfeature.sh  FeatureName
#

SCRIPTDIR="$(dirname "$0")"
: ${BASEDIR:="$(dirname "$(readlink -f "$SCRIPTDIR")")"}

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

function PutChangesInFeature() {
	local Package="$1"
	local FeatureName="$2"
	shift 2
	
	local -i nErrors=0
	local res=0
	
	#
	# first remove from staging everything that has not been committed yet;
	# this is also material for the new feature
	#
	git reset HEAD
	
	#
	# stash all the changes
	#
	local nStashes="$(git stash list | wc -l)"
	git stash save "PutIn${FeatureName}"
	local nNewStashes="$(git stash list | wc -l)"
	
	#
	# create the new feature
	#
	git flow feature start "$FeatureName"
	res=$?
	[[ $res != 0 ]] && let ++nErrors
	
	#
	# restore the content of the new stash in the current branch
	# (it should be the new one...)
	#
	if [[ "$nNewStashes" -gt "$nStashes" ]]; then
		git stash pop
	fi
	
	return $nErrors
} # PutChangesInFeature()

if [[ $# != 1 ]]; then
	echo "You need to specify the feature name as the first argument!" >&2
	exit 1
fi

export -f PutChangesInFeature
"${SCRIPTDIR}/larcommands.sh" ${FAKE:+--dry-run} --tag="PACKAGENAME" -- PutChangesInFeature '%PACKAGENAME%' "$@"

exit $nPatches
