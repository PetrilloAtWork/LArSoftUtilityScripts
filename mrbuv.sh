#!/usr/bin/env bash
#
# Runs `mrb uv` and deletes the backup files of the files that were not changed.
#
# If version is not specified, an attempt is made to detect it from the current
# working area.
#

# ------------------------------------------------------------------------------
function STDERR() { echo "$*" >&2 ; }
function ERROR() { STDERR "ERROR: $*" ; }

function ExtractPackageVersion() {
	local ProductDepsFile="$1"
	local PackageName="$2"
	grep "^parent" "$UPSdeps" | awk '{ print $3 ; }'
} # ExtractPackageVersion()

function DetectPackageVersion() {
  local PackageName="$1"
  declare UPSdeps="${MRB_SOURCE:-.}/${PackageName}/ups/product_deps"
  if [[ ! -r "$UPSdeps" ]]; then
    ERROR "Could not find the product_deps file of '${PackageName}' ('${UPSdeps}')."
    return 2
  fi
  ExtractPackageVersion "$UPSdeps" "$PackageName"
} # DetectPackageVersion()


function Exec() {
  local -a Cmd=( "$@" )
  echo "CMD> ${Cmd[@]}"
  "${Cmd[@]}"
} # Exec()


# ------------------------------------------------------------------------------
if [[ -z "$MRB_SOURCE" ]]; then
	ERROR "no MRB working area set up."
	exit 1
fi

cd "$MRB_SOURCE" || exit $?

declare -r TempSuffix=".mrbuvsh"

#
# figure out which version
#
declare -a Arguments=( "$@" )
declare -ai ArgumentIndices
for (( iArg = 0 ; iArg < "${#Arguments[@]}" ; ++iArg )); do
  Arg="${Arguments[iArg]}"
  [[ "${Arg:0:1}" == "-" ]] || ArgumentIndices+=( "$iArg" )
done

declare Package="${Arguments[${ArgumentIndices[0]}]}"
declare Version="${Arguments[${ArgumentIndices[1]}]}"
if [[ "${#ArgumentIndices[@]}" == 0 ]] || [[ -z "$Package" ]]; then
  declare -i PackageIndex="${ArgumentIndices[0]:-${#Arguments[@]}}"
  Package='larsoft'
  Arguments[PackageIndex]="$Package"
fi
if [[ "${#ArgumentIndices[@]}" == 1 ]] || [[ -z "$Version" ]]; then
  #
  # attempt autodetection of the version
  #
  declare -i VersionIndex="${ArgumentIndices[1]:-${#Arguments[@]}}"
  Version="$(DetectPackageVersion "$Package")"
  if [[ $? == 0 ]]; then
    echo "Autodetected the version of '${Package}' in the working area as: '${Version}'"
    Arguments[VersionIndex]="$Version"
  else
    ERROR "Attempt to discover the version of '${Package}' failed."
  fi
fi

#
# move existing backups out of the way
#
for ProductDepsBak in */ups/product_deps.bak ; do
  [[ -e "$ProductDepsBak" ]] || continue # e.g. in case there is no backup
  RepoName="${ProductDepsBak%%/*}"
  ProductDepsTempBackup="${ProductDepsBak}${TempSuffix}"

  echo "Moving away backup in ${RepoName}"
  mv "$ProductDepsBak" "$ProductDepsTempBackup"
done


#
# run `mrb uv`
#
[[ "${#Arguments[@]}" -gt 0 ]] && { Exec mrb uv "${Arguments[@]}" || exit $? ; }

#
# remove unnecessary backups
#
for ProductDepsBak in */ups/product_deps.bak ; do
  [[ -e "$ProductDepsBak" ]] || continue # e.g. in case there is no backup
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

