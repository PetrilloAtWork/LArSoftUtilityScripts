#!/usr/bin/env bash
#
# Creates a workikng area based on a production release (no MRB).
# 
# Changes:
# 1.0 (20140219, petrillo@fnal.gov)
#     first version
# 1.1 (20140925, petrillo@fnal.gov)
#     updated default qualifiers (e5 -> e6)
# 1.2 (20171016, petrillo@fnal.gov)
#     updated default qualifiers (e10 -> e14);
#     restored magic 'job' directory name
# 1.3 (20180315, petrillo@fnal.gov)
#     updated default qualifiers (e14 -> e15);
# 1.4 (20181002, petrillo@slac.stanford.edu)
#     updated default qualifiers (e15 -> e17);
# 1.5 (20200323, petrillo@slac.stanford.edu)
#     updated default qualifiers (e17 -> e19);
#

SCRIPTNAME="$(basename "$0")"
VERSION="1.5"

: ${BASEDIR:="."}

declare -a StandardQualifiers
StandardQualifiers=(       'e19:debug'  'e19:prof'   )
StandardQualifierAliases=( 'debug' 'prof' )

function help() {
	cat <<-EOH
	Creates a working area based on a production release (no MRB).
	
	Usage:  ${SCRIPTNAME} [options] Version[@qualifiers] [...]
	
	If no qualifiers set is specified, all the standard ones will be created:
	${StandardQualifiers[@]}.
	
	Options [defaults in brackets]:
	--current , -C
	    make the first specified version the current one (just creates a "current"
	    link to the version directory)
	--basedir=BASEDIR [${BASEDIR}]
	    create the area on top of BASEDIR directory
	
	EOH
} # help()


function isFlagSet() {
	local VarName="$1"
	[[ -n "${!VarName//0}" ]]
} # isFlagSet()

function isFlagUnset() {
	local VarName="$1"
	[[ -z "${!VarName//0}" ]]
} # isFlagUnset()

function STDERR() { echo "$*" >&2 ; }
function WARN() { STDERR "WARNING: $@" ; }
function ERROR() { STDERR "ERROR: $@" ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()
function LASTFATAL() {
	local Code="$?"
	[[ "$Code" != 0 ]] && FATAL "$Code""$@"
} # LASTFATAL()


function IsInList() {
	# Usage:  IsInList Key [Item ...]
	# Returns 0 if the key is one of the other specified items
	local Key="$1"
	shift
	local Item
	for Item in "$@" ; do
		[[ "$Item" == "$Key" ]] && return 0
	done
	return 1
} # IsInList()


function SortUPSqualifiers() {
	# Usage:  SortUPSqualifiers  Qualifiers [Separator]
	# sorts the specified qualifiers (colon separated by default)
	# The current sorting is: alphabetically, but move debug/opt/prof to the end
	local qual="$1"
	local sep="${2:-":"}"
	local item
	local -i nItems=0
	local -ar AllSpecials=( 'prof' 'opt' 'debug' )
	local -a Specials
	for item in $(tr "$sep" '\n' <<< "$qual" | sort) ; do
		if IsInList "$item" "${AllSpecials[@]}" ; then
			Specials=( "${Specials[@]}" "$item" )
			continue
		fi
		[[ "$((nItems++))" == 0 ]] || echo -n "$sep"
		echo -n "$item"
	done
	# add the special qualifiers at the end, in the original relative order
	for item in "${Specials[@]}" ; do
		[[ "$((nItems++))" == 0 ]] || echo -n "$sep"
		echo -n "$item"
	done
	echo
	return 0
} # SortUPSqualifiers()


function ReplaceLink() {
	local BaseDir="$1"
	local Target="$2"
	local LinkName="$3"
	
	local FullTarget="${BaseDir:+"${BaseDir%/}/"}${Target}"
	if [[ ! -e "$FullTarget" ]]; then
		ERROR "Target '${Target}' not available from '${BaseDir:-"."}'"
		return 2
	fi
	
	local Link="${BaseDir:+"${BaseDir%/}/"}${LinkName}"
	
	local -i isDir=0
	[[ -d "$FullTarget" ]] && isDir=1
	
	if [[ -e "$Link" ]]; then
		if [[ ! -h "$Link" ]]; then
			ERROR "${Link} already exists and it's not a symbolic link!"
			return 1
		fi
		
		if isFlagSet isDir && [[ ! -d "$Link" ]]; then
			ERROR "${Link} already exists and it's not a directory!"
			return 1
		elif isFlagUnset isDir && [[ -d "$Link" ]]; then
			ERROR "${Link} already exists and it's a directory!"
			return 1
		fi
		
		rm -f "$Link"
	fi
	
	ln -s "$Target" "$Link"
	return $?
} # ReplaceLink()


function CreateProductionArea() {
	local BaseDir="${1:+"${1%/}/"}"
	local Version="$2"
	local Quals="$3"
	local QualsAlias="$4"
	
	local QualsDir="${Quals//:/_}"
	
	local AreaDir="${BaseDir}${Version}/${QualsDir}"
	
	local -i nErrors=0
	
	# create the directory
	if [[ -d "$AreaDir" ]]; then
		WARN "Reusing area '${AreaDir}'"
	else
		if ! mkdir -p "$AreaDir" ; then
			let ++nErrors
			return $nErrors
		fi
	fi
	
	# create a little structure in the area;
	# the directory name 'job' is chosen because most experiments
	# set that name up as part of the local FHiCL search path
	mkdir -p "${AreaDir}/logs" "${AreaDir}/job"
	
	local SetupLink="${AreaDir}/setup"
	
	ReplaceLink "$AreaDir" '../../setup' "setup"
	case $? in
		( 0 ) ;;
		( 2 ) WARN "Link to setup skipped, no '${BaseDir}setup' found." ;;
		( * )
			let ++nErrors
			return $nErrors
	esac
	
	# create the qualifiers alias
	if [[ -n "$QualsAlias" ]]; then
		if ! ReplaceLink "$(dirname "$AreaDir")" "$QualsDir" "$QualsAlias" ; then
			let ++nErrors
			return $nErrors
		fi
	fi
	
	echo "Area '${AreaDir}' for version ${Version} (${Quals}) created."
	
	return $nErrors
} # CreateProductionArea()


function CreateProductionAreas() {
	local BaseDir="${1:+"${1%/}/"}"
	local VersionSpec="$2"
	local MakeItCurrent="$3"
	
	local Version="${VersionSpec%%@*}"
	local -a Qualifiers
	local -a QualifierAliases
	
	if [[ "$Version" == "$VersionSpec" ]]; then
		Qualifiers=( "${StandardQualifiers[@]}" )
		QualifierAliases=( "${StandardQualifierAliases[@]}" )
	else
		Qualifiers=( "$(SortUPSqualifiers "${VersionSpec#"${Version}@"}")" )
		QualifierAliases=( "" )
	fi
	
	local -i nErrors=0
	local iQualifier
	for (( iQual = 0 ; iQual < ${#Qualifiers[@]} ; ++iQual )); do
		local Quals="${Qualifiers[iQual]}"
		local QualsAlias="${QualifierAliases[iQual]}"
		
		CreateProductionArea "$BaseDir" "$Version" "$Quals" "$QualsAlias" "$MakeItCurrent" || let ++nErrors
	done
	
	# make it the current one
	if isFlagSet MakeItCurrent ; then
		ReplaceLink "$BaseDir" "$Version" 'current'
		case $? in
			( 0 )
				echo "  => version ${Version} made current"
				;;
			( * )
				ERROR "Unable to make ${Version} current"
				let ++nErrors
				;;
		esac
	fi
	
	return $nErrors
} # CreateProductionAreas()


################################################################################

declare -i NoMoreOptions=0
declare -a Versions
declare -i nVersions=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1  ;;
			
			( '--current' | '-C' ) MakeItCurrent=1 ;;
			( '--basedir='* )      BASEDIR=${Param#"--basedir="} ;;
			
			### other stuff
			( '-' | '--' )
				NoMoreOptions=1
				;;
			( * )
				FATAL 1 "Unrecognized script option #${iParam} - '${Param}'"
				;;
		esac
	else
		NoMoreOptions=1
		Versions[nVersions++]="$Param"
	fi
done

if isFlagSet DoHelp || [[ $nVersions == 0 ]] ; then
	help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	exit $?
fi

declare -i nErrors=0
for VersionSpec in "${Versions[@]}" ; do
	CreateProductionAreas "$BASEDIR" "$VersionSpec" $MakeItCurrent || let ++nErrors
	# only the first version is made current
	MakeItCurrent=0
done

exit $nErrors
