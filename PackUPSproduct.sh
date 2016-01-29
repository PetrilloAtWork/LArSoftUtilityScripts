#!/usr/bin/env bash
#
# Usage:  PackUPSproduct.sh product[@version] [...]
#
#

# /grid/fermiapp/products/uboone

###############################################################################
function STDERR() { echo "$*" >&2 ; }
function ERROR() { echo "ERROR: $*" ; }

function isDebugging() {
	local -i MessageLevel="${1:-1}"
	[[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge "$MessageLevel" ]]
} # isDebugging()

function DBGN() {
	local -i Level="$1"
	shift
	isDebugging "$Level" && STDERR "DBG[${Level}]| $*"
} # DBGN()

function DBG() { DBGN 1 "$@" ; }
	

###############################################################################
function FindProduct() {
	
	local ProductName="$1"
	local ProductVersion="$2"
	
	###
	### Find the target
	###
	
	local TargetName="$ProductName${ProductVersion:+"/${ProductVersion}.version"}"
	DBGN 4 "Looking for '${TargetName}' in the UPS repositories"
	local ProductRepo ProductDir TargetDir
	while read ProductRepo ; do
		[[ -n "$ProductRepo" ]] || continue
		DBGN 2 "Looking in '${ProductRepo}'"
		[[ -d "${ProductRepo}/${ProductName}" ]] || continue
		
		DBGN 3 "Product '${ProductName}' found in repository '${ProductRepo}'"
		TargetDir="${ProductRepo}/${TargetName}"
		
		[[ -d "$TargetDir" ]] && break
	done < <(tr ':' '\n' <<< "$PRODUCTS")
	
	if [[ ! -d "$TargetDir" ]]; then
		STDERR "Product '${ProductName}' (${ProductVersion:-"any versions"}) not found!"
		return 2
	fi
	
	echo "$ProductRepo"
        return 0
} # FindProduct()


function MakeTarball() {
	
	local ProductRepo="$1"
	local ProductName="$2"
	local ProductVersion="$3"
	
	###
	### pack
	###
	local OutputFile="${ProductName}${ProductVersion:+"-${ProductVersion}"}.tar.bz2"
	
	local TargetName="${ProductName}${ProductVersion:+"/${ProductVersion}.version"}"
	local -a TargetDirs
	if [[ -n "$ProductVersion" ]]; then
		TargetDirs=( "$TargetName" "${TargetName%.version}" )
	else
		TargetDirs=( "$TargetName" )
	fi
	local res
	echo "  (taken from '${ProductRepo}')"
	local -a Cmd=( tar cjf "$OutputFile" -C "$ProductRepo" "${TargetDirs[@]}" )
	DBG "${Cmd[@]}"
	"${Cmd[@]}"
	res=$?
	if [[ $res == 0 ]]; then
		echo "  '$(pwd)/${OutputFile}'"
	fi
	
	###
	### done
	###
        return $res
} # MakeTarball()


function PackProduct() {
	
	local -i res=0
	
	local ProductName="$1"
	local ProductVersion="${ProductName#*@}"
	
	###
	### parse the product specification
	###
	if [[ "$ProductName" == "$ProductVersion" ]]; then
		ProductVersion=""
	else
		ProductName="${ProductName%"@${ProductVersion}"}"
	fi
	
	echo "Packing '${ProductName}' (${ProductVersion:-"all available versions"})"	

	###
	### Find the target
	###
	local RepositoryPath
	RepositoryPath="$(FindProduct "$ProductName" "$ProductVersion" )"
	res=$?
	DBG "Repository: '${RepositoryPath}' (error code: ${res})"
	[[ $res != 0 ]] && return $res
	
	###
	### pack
	###
	MakeTarball "$RepositoryPath" "$ProductName" "$ProductVersion"
	res=$?
	
	###
	### done
	###
        return $res
} # PackProduct()


###############################################################################
declare -i nErrors=0
for ProductSpec in "$@" ; do
	PackProduct "$ProductSpec" || let ++nErrors
done

[[ $nErrors -gt 0 ]] && echo "${nErrors} errors were encountered."
exit $nErrors

