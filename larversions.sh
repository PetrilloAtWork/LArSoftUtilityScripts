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
# 20220311 (petrillo@slac.stanford.edu) [v1.3]
#   version extraction updated to follow new LArSoft CMake paradigm
#

SCRIPTDIR="$(dirname "$0")"
SCRIPTVERSION="1.3"

declare -r VersionAtom='([0-9]{1,2})'
declare -r SepAtom='(\.|_)'
# Ugh... VERSION 09.06.03.00pwhatever98bis
#  [1] 09.06.03.00pwhatever98bis
#  [2] 09
#  [4] 06
#  [7] 03
# [10] 00
# [11] pwhatever98bis
declare -r VersionPattern="(v?${VersionAtom}${SepAtom}${VersionAtom}(${SepAtom}${VersionAtom}(${SepAtom}${VersionAtom}([-_a-zA-Z][-_.0-9a-zA-Z]*)?)?)?)"

declare -Ar MainDependencies=(
  ['sbnobj']='lardataobj'
  ['sbnalg']='sbnobj'
  ['sbncode']='sbnalg'
  ['icarusalg']='sbnalg'
  ['icaruscode']='sbncode'
  ['sbndcode']='sbncode'
)


function ExtractUPSPackageVersion() {
  local ProductDepsFile="$1"
  local PackageName="$2"
  local Version="$(grep "^parent" "$UPSdeps" | awk '{ print $3 ; }')"
  [[ -z "$Version" ]] && return 1
  echo "$Version"
} # ExtractUPSPackageVersion()


function ExtractPackageVersionFromCMake() {
  local CMakeListsFile="${1:-"CMakeLists.txt"}"
  local PackageName="$2" # unused
  local ProjectLine="$(grep -E '\bproject *\(' "$CMakeListsFile" | tail -n 1)"
  
  [[ "$ProjectLine" =~ VERSION\ +${VersionPattern} ]] || return 1
  
  echo "${BASH_REMATCH[1]}"
} # ExtractPackageVersionFromCMake()


function ExtractDependVersion() {
  local ProductDepsFile="$1"
  local PackageName="$2"
  grep "^${PackageName}" "$ProductDepsFile" | awk '{ print $2 ; }'
} # ExtractDependVersion()

function ExtractPackageVersion() {
  local UPSdeps="ups/product_deps"
  [[ -r "$UPSdeps" ]] && ExtractUPSPackageVersion "$UPSdeps" "$PackageName" && return
  
  CMakeListsFile='CMakeLists.txt'
  [[ -r "$CMakeListsFile" ]] && ExtractPackageVersionFromCMake "$CMakeListsFile" "$PackageName" && return
  
  return 1
} # ExtractPackageVersion()


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
  local UPSdeps="ups/product_deps"
  if [[ ! -r "$UPSdeps" ]]; then
    echo "<no UPS version>"
    return 1
  fi
  DBG 4 "${FUNCNAME}: '${PackageName}' => '${MainDepend}' => version?"
  ExtractDependVersion "$UPSdeps" "$MainDepend"
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
  local PackageVersion="$(ExtractPackageVersion "$UPSdeps")"

  DBGN 2 "Extracting GIT tag from '${PackageName}'"
  local -r Tag="$(ExtractGITtag "$PackageName")"

  local Msg="${PackageVersion:-"<unknown version>"}  [${PackageName}"

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



function PrintPackageVersion() {
  local PackageName="$1"
  DBGN 1 "Extracting version from '${PackageName}'"
  local PackageVersion="$(ExtractPackageVersion)"

  DBGN 2 "Extracting GIT tag from '${PackageName}'"
  local -r Tag="$(ExtractGITtag "$PackageName")"

  local Msg="${PackageVersion:-"<unknown>"}  [${PackageName}"

  [[ -n "$Tag" ]] && Msg+=", GIT tag '${Tag}'"

  if isLArSoftCorePackage "$PackageName" ; then
    DBGN 2 "  [core package]"
  else
    DBGN 2 "  [user package]"
    local MainDepend="$(GetMainDependency "$PackageName")"
    local DependVersion="$(ExtractMainDependencyVersion "$PackageName" "$MainDepend")"
    if [[ -n "$DependVersion" ]]; then
      Msg+=", based on ${MainDepend} ${DependVersion}"
    else
      Msg+=", main dependency not known"
    fi
  fi
  Msg+="]"
  echo "$Msg"
} # PrintPackageVersion()



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

source "${SCRIPTDIR}/larcommands.sh" --compact=quiet --tag='PACKAGENAME' --miscargs=$# "$@" -- PrintPackageVersion '%PACKAGENAME%'
