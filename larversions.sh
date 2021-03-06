#!/usr/bin/env bash
#
# Executes the same GIT command on all git projects:
#
# print the current branch
#
# Run '--help' for help usage
# (and keep in mind that the --git and --tag=PACKAGENAME options are always
# applied)
#
# Changes:
# 20200310 (petrillo@slac.stanford.edu) [v1.1]
#   added latest tag of each repository
# 20201106 (petrillo@slac.stanford.edu) [v1.2]
#   added dependency "tree"
#

SCRIPTDIR="$(dirname "$0")"
SCRIPTVERSION="1.2"

declare -Ar MainDependencies=(
  ['sbnobj']='lardataobj'
  ['icarusalg']='larsoftobj'
  ['icaruscode']='sbncode'
  ['sbndcode']='sbncode'
)


function ExtractPackageVersion() {
  local ProductDepsFile="$1"
  local PackageName="$2"
  grep "^parent" "$UPSdeps" | awk '{ print $3 ; }'
} # ExtractPackageVersion()

function ExtractDependVersion() {
  local ProductDepsFile="$1"
  local PackageName="$2"
  grep "^${PackageName}" "$UPSdeps" | awk '{ print $2 ; }'
} # ExtractDependVersion()


function ExtractGITtag() {
  local PackageName="$1"
  DBGN 2 "Extracting GIT tag from '${PackageName}'"
  local Tag
  Tag="$(git describe --tags --abbrev=0 2> /dev/null)"
  local res=$?
  if [[ $res != 0 ]]; then
    DBGN 2 "  extraction of GIT tag failed (code: ${res})"
    Tag=""
    return 1
  fi
  echo "$Tag"
  return 0
} # ExtractGITtag()


function GetMainDependency() {
  echo "${MainDependencies["$PackageName"]:-"larsoft"}"
} # GetMainDependency()

function ExtractMainDependencyVersion() {
  local -r PackageName="$1"
  local MainDepend="${2:-"$(GetMainDependency "$PackageName")"}"
  DBG 4 "${FUNCNAME}: '${PackageName}' => '${MainDepend}' => version?"
  ExtractDependVersion "$PackageName" "$MainDepend"
} # ExtractMainDependencyVersion()


function PrintUPSversion() {
  local PackageName="$1"
  local UPSdeps="ups/product_deps"
  if [[ ! -r "$UPSdeps" ]]; then
    echo "<no UPS version>"
    return 1
  fi
  DBGN 1 "Extracting version from '${PackageName}'"
  local PackageVersion="$(ExtractPackageVersion "$UPSdeps")"

  DBGN 2 "Extracting GIT tag from '${PackageName}'"
  local -r Tag="$(ExtractGITtag "$PackageName")"

  local Msg="${PackageVersion}  [${PackageName}"

  [[ -n "$Tag" ]] && Msg+=", GIT tag '${Tag}'"

  if isLArSoftCorePackage "$PackageName" ; then
    DBGN 2 "  [core package]"
  else
    DBGN 2 "  [user package]"
    local MainDepend="$(GetMainDependency "$UPSdeps")"
    local DependVersion="$(ExtractMainDependencyVersion "$UPSdeps" "$MainDepend")"
    if [[ -n "$DependVersion" ]]; then
      Msg+=", based on ${MainDepend} ${DependVersion}"
    else
      Msg+=", main dependency not known"
    fi
  fi
  Msg+="]"
  echo "$Msg"
} # PrintUPSversion()


################################################################################
### This is quasi-boilerplate for better interface with larcommands.sh
###
function help() {
  cat <<-EOH
Prints the version of source repositories.

Usage:  ${SCRIPTNAME}  [base options]

EOH
  help_baseoptions
} # help()

################################################################################

source "${SCRIPTDIR}/larcommands.sh" --compact=quiet --tag='PACKAGENAME' --miscargs=$# "$@" -- PrintUPSversion '%PACKAGENAME%'
