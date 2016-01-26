#!/usr/bin/env bash
#
# Create tar balls of the products in the specified directories.
#


SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"

: ${FAKE:="0"}

function isFlagSet() { local VarName="$1" ; [[ -n "${!VarName//0}" ]] ; }

function STDERR() { echo "$*" >&2 ; }
function ERROR() { STDERR "ERROR: $*" ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()

function LASTFATAL() { local Code="$?" ; [[ $Code != 0 ]] && FATAL "$Code" "$@" ; }


function help() {
	cat <<-EOH
	Creates tarballs with all the products in the specified product directories.
	
	Usage:  ${SCRIPTNAME} [options] [ProductsDir] [...]
	
	Product tarballs are stored in the respective product directories.
	If no product directory is specified, the one in the variable MRB_INSTALL
	is used (currently ${MRB_INSTALL:-"unset"}).
	
	Options:
	--fake , --dry-run , -n
	    just prints what would be packed
	--doit , --now, -y
	    actually produces the tarballs (default)
	--archonly
	    adds to the archive only the architecture-specific directories
	--verbose
	    be wordy
	--help , -h , -?
	    prints this help message
	
	EOH
} # help()


function CleanUp() {
	[[ -n "$FileList" ]] && [[ -w "$FileList" ]] && rm -f "$FileList"
} # CleanUp()


################################################################################
### parameters parser
### 
declare -i NoMoreOptions=0
declare -a LocalProductDirs
for ((iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if isFlagSet NoMoreOptions || [[ "${Param:0:1}" != '-' ]]; then
		NoMoreOptions=1
		LocalProductDirs=( "${LocalProductDirs[@]}" "$Param" )
	else
		case "$Param" in
			( "--fake" | "--dry-run" | "-n" )
				FAKE=1
				;;
			( "--now" | "--doit" | "-y" )
				FAKE=0
				;;
			( "--archonly" )
				DoArchOnly=1
				;;
			( '--help' | '-?' | '-h' )
				DoHelp=1
				;;
			( '--verbose' | '-v' )
				VERBOSE=1
				;;
			( '-' | '--' )
				NoMoreOptions=1
				;;
			( * )
				FATAL 1 "Unknown option '${Param}'"
		esac
	fi
done

if isFlagSet DoHelp ; then
	help
	exit
fi

FAKECMD=""
isFlagSet FAKE && FAKECMD=echo

trap CleanUp EXIT

FileList="$(readlink -f "$(mktemp "${SCRIPTNAME}-$$.tmpXXXXXX")")"

for LocalProductDir in "${LocalProductDirs[@]:-"${MRB_INSTALL:-"."}"}" ; do
	
	pushd "$LocalProductDir" > /dev/null
	[[ $? == 0 ]] || continue
	
	for PackageDir in * ; do
		[[ -d "$PackageDir" ]] || continue
		PackageName="$PackageDir"
		
		for PackageVersionDir in "${PackageDir}/"*.version ; do
			PackageVersion="$(basename "${PackageVersionDir%.version}")"
			PackageContentDir="${PackageVersionDir%.version}"
			if [[ ! -d "$PackageContentDir" ]]; then
				ERROR "Product '${PackageName}' has incomplete version ${PackageVersion}"
				continue
			fi
			
			for ArchDir in "$PackageContentDir"/*.*.* ; do
				[[ ! -d "${ArchDir}/lib" ]] && [[ ! -d "${ArchDir}/bin" ]] && continue
				
				Specs="$(basename "$ArchDir")"
				OSname="${Specs%%.*}"
				Specs="${Specs#*.}"
				Arch="${Specs%%.*}"
				Specs="${Specs#*.}"
				Qualifiers="${Specs//./:}"
				
				
				SpecsKey="${OSname}-${Arch}-${Qualifiers//:/-}"
				
				ArchiveName="${PackageName}-${PackageVersion}-${SpecsKey}.tar.bz2"
				
				echo "Packing ${PackageName} ${PackageVersion} (${OSname} ${Arch}, ${Qualifiers})"
				
				{
					# exclude the directories, or tar will insert all their content too
					
					find "${PackageDir}/${PackageVersion}/$(basename "$ArchDir")" -not -type d
					if ! isFlagSet DoArchOnly ; then
						find "${PackageDir}/$PackageVersion" -not -path "${PackageDir}/${PackageVersion}/*.*.*" -not -type d
					fi
					
					# files in the .version directory, related to our qualifiers
					find "${PackageDir}/${PackageVersion}.version" -name "*_${Qualifiers//:/_}" -not -type d
				} > "$FileList"
				
				isFlagSet VERBOSE && VERBOSEFLAG="vv"
				
				$FAKECMD tar c${VERBOSEFLAG}jf "$ArchiveName" -T "$FileList"
				
			done
			
		done
		
		
		
	done # for package 
	popd > /dev/null
done # local product dirs

