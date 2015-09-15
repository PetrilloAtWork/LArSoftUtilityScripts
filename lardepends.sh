#!/bin/bash
#
# Executes the same GIT command on all git projects:
# 
# print the versions each package depends on
# 
# Run '--help' for help usage.
#

SCRIPTDIR="$(dirname "$0")"
SCRIPTVERSION="1.0"

function ExtractDependVersion() {
	local ProductDepsFile="$1"
	local PackageName="$2"
	grep "^${PackageName}" "$UPSdeps" | awk '{ print $2 ; }'
	return ${PIPESTATUS[0]}
} # ExtractDependVersion()

function ExtractLArSoftVersion() { ExtractDependVersion "$1" 'larsoft' ; }


function PrintDependentUPSversion() {
	local PackageName="$1"
	local UPSdeps="ups/product_deps"
	if [[ ! -r "$UPSdeps" ]]; then
		echo "<no UPS version>"
		return 1
	fi
	
	shift
	local -a Products=( "$@" )
	
	local Product ProductVersion
	for Product in "${Products[@]}" ; do
		DBGN 1 "Extracting version of '${Product}' that '${PackageName}' depends on"
		ProductVersion="$(ExtractDependVersion "$UPSdeps" "$Product" )"
		if [[ $? != 0 ]]; then
			DBGN 2 "  -> none"
			continue
		fi
		echo "  ${Product} ${ProductVersion}"
	done
} # PrintDependentUPSversion()

################################################################################
### This is quasi-boilerplate for better interface with larcommands.sh
###
function help() {
	cat <<-EOH
	Prints the version of dependencies of source repositories.
	
	Usage:  ${SCRIPTNAME}  [base options] Product [Product ...]
	
	For each package, prints the version of dependency on each of the specified
	products, if any.
	
	EOH
	help_baseoptions
} # help()

################################################################################

source "${SCRIPTDIR}/larcommands.sh" --compact=line --skipnooutput --tag='PACKAGENAME' --tag='ARGS' --miscargs=$# "$@" -- PrintDependentUPSversion '%PACKAGENAME%' '%ARGS%'
