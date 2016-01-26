#!/usr/bin/env bash
#
# Fetches all the packages from their "origin" remote repository.
#

SCRIPTDIR="$(dirname "$0")"
: ${BASEDIR:="$(dirname "$(readlink -f "$SCRIPTDIR")")"}
: ${SRCDIR:="${BASEDIR}/srcs"}

for Dir in "$SRCDIR"/* ; do
	[[ -d "$Dir" ]] || continue
	[[ -d "${Dir}/.git" ]] || continue
	
	PackageName="$(basename "$Dir")"
	(
		cd "$Dir"
		echo "${PackageName}:"
		git fetch origin
		git merge origin
	)
done
