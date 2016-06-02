#!/usr/bin/env bash
#
# Runs `mrb uv` and deletes the backup files of the files that were not changed.
#

function STDERR() { echo "$*" >&2 ; }
function ERROR() { STDERR "ERROR: $*" ; }

if [[ -z "$MRB_SOURCE" ]]; then
	ERROR "no MRB working area set up."
	exit 1
fi

cd "$MRB_SOURCE" || exit $?

declare -r TempSuffix=".mrbuvsh"

#
# move existing backups out of the way
#
for ProductDepsBak in */ups/product_deps.bak ; do
	RepoName="${ProductDepsBak%%/*}"
	ProductDepsTempBackup="${ProductDepsBak}${TempSuffix}"
	
	echo "Moving away backup in ${RepoName}"
	mv "$ProductDepsBak" "$ProductDepsTempBackup"
done


#
# run `mrb uv`
#
[[ "$#" -gt 0 ]] && { mrb uv "$@" || exit $? ; }

#
# remove unnecessary backups
#
for ProductDepsBak in */ups/product_deps.bak ; do
	RepoName="${ProductDepsBak%%/*}"
	ProductDeps="${ProductDepsBak%.bak}"
	ProductDepsTempBackup="${ProductDepsBak}${TempSuffix}"
	if [[ ! -r "$ProductDeps" ]]; then
		ERROR "Can't find the updated '${ProductDeps}' corresponding to the backup '${ProductDepsBak}'"
		continue
	fi
	if cmp --quiet "$ProductDeps" "$ProductDepsBak" ; then
		# no difference, restore the backup(s)
		mv "$ProductDepsBak" "$ProductDeps"
		echo "No change in ${RepoName}."
		[[ -r "$ProductDepsTempBackup" ]] && mv "$ProductDepsTempBackup" "$ProductDepsBak"
	else
		# file is changed...
		if [[ -r "$ProductDepsTempBackup" ]]; then
			# ... and we have two backups.
			# What do we do? the previous backup might be too outdated;
			# or it might be the real one.
			# We decide we keep the old one
			mv "$ProductDepsTempBackup" "$ProductDepsBak"
			echo "Changed ${RepoName} (keeping the existing backup)."
		else
			echo "Changed ${RepoName}."
		fi
	fi
done

