#!/bin/bash
#
# Executes the same GIT command on all git projects:
# 
# print the current branch
# 
# Run '--help' for help usage
# (and keep in mind that the --git and --tag=PACKAGENAME options are always
# applied)
#

SCRIPTDIR="$(dirname "$0")"
SCRIPTVERSION="1.0"

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

function ExtractLArSoftVersion() { ExtractDependVersion "$1" 'larsoft' ; }


function PrintUPSversion() {
	local PackageName="$1"
	local UPSdeps="ups/product_deps"
	if [[ ! -r "$UPSdeps" ]]; then
		echo "<no UPS version>"
		return 1
	fi
	DBGN 1 "Extracting version from '${PackageName}'"
	local PackageVersion="$(ExtractPackageVersion "$UPSdeps")"
	if isLArSoftCorePackage "$PackageName" ; then
		DBGN 2 "  [core package]"
		echo "${PackageVersion}  [${PackageName}]"
	else
		DBGN 2 "  [user package]"
		local LArSoftVersion="$(ExtractLArSoftVersion "$UPSdeps")"
		if [[ -n "$LArSoftVersion" ]]; then
			echo "${PackageVersion}  [${PackageName}, based on LArSoft ${LArSoftVersion}]"
		else
			echo "${PackageVersion}  [${PackageName}, not directly based on LArSoft]"
		fi
	fi
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
