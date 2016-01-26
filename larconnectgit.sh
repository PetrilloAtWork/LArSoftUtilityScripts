#!/usr/bin/env bash
#
# Adds the specified repository as a remote source of the local one.
# 
# Usage:  larconnectgit.sh  RepoAlias RepoLocalPath
#

SCRIPTDIR="$(dirname "$0")"
: ${BASEDIR:="$(dirname "$(readlink -f "$SCRIPTDIR")")"}

SourceDirName='srcs'

RepoAlias="$1"
if [[ -z "$RepoAlias" ]]; then
	echo "You need to specify a repository alias" >&2
	exit 1
fi

BaseRepoPath="$2"
if [[ -z "$BaseRepoPath" ]]; then
	echo "You need to specify a local repository path." >&2
	exit 1
fi
[[ "${BaseRepoPath:0:1}" != '/' ]] && BaseRepoPath="$(pwd)/${BaseRepoPath}"

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

"${SCRIPTDIR}/larcommands.sh" ${FAKE:+--dry-run} --tag="PACKAGENAME" -- git remote add "$RepoAlias" "${BaseRepoPath}/%PACKAGENAME%"
