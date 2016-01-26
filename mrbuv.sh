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

[[ "$#" -gt 0 ]] && { mrb uv "$@" || exit $? ; }

for ProductDepsBak in */ups/product_deps.bak ; do
	ProductDeps="${ProductDepsBak%.bak}"
	if [[ ! -r "$ProductDeps" ]]; then
		ERROR "Can't find the updated '${ProductDeps}' corresponding to the backup '${ProductDepsBak}'"
		continue
	fi
	if cmp --quiet "$ProductDeps" "$ProductDepsBak" ; then
		rm -vf "$ProductDepsBak"
	else
		echo "Keeping '${ProductDepsBak}'."
	fi
done

