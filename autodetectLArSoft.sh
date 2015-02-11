#!/bin/bash
#
# Autodetects and print LArSoft version, qualifiers and experiment.
# Do not source this script.
# 
# Use:  autodetectLArSoft.sh  [options] [DefaultVersion [DefaultQualifiers [DefaultExperiment]]]
# 
# Each specified parameter is used as default if the respective value is not
# discovered.
#

declare SCRIPTNAME="$(basename "$0")"

################################################################################
###  Format tags
# all these have to start with the item tag ('%');
                 ItemTag='%'
           VersionFormat="${ItemTag}V"
        QualifiersFormat="${ItemTag}Q"
  QualifiersInPathFormat="${ItemTag}q"
        ExperimentFormat="${ItemTag}E"
    LeadingPackageFormat="${ItemTag}L"
    PackageVersionFormat="${ItemTag}p"
RealPackageVersionFormat="${ItemTag}P"

: ${DefaultFormat:="${VersionFormat}\n${QualifiersFormat}\n${ExperimentFormat}\n"}

      UPSformat="${LeadingPackageFormat} ${PackageVersionFormat} -q ${QualifiersFormat}"
LArSoftUPSformat="larsoft ${VersionFormat} -q ${QualifiersFormat}"
  LocalProdFormat="${PackageVersionFormat}_${QualifiersInPathFormat}"
        AllFormat="$(cat <<EOM
Experiment:              ${ExperimentFormat}
LArSoft version:         ${VersionFormat}
LArSoft qualifiers:      ${QualifiersFormat}
Leading package:         ${LeadingPackageFormat}
Leading package version: ${RealPackageVersionFormat}\n
EOM
)"

################################################################################
function help() {
	cat <<-EOH
	Detects and prints parameters of the current LArSoft working area and
	environment.
	
	Usage:  ${SCRIPTNAME} [options] [version [qualifiers [experiment]]]
	
	The three arguments specify a default value if autodetection fails.
	
	Options [defaults in brackets]:
	--version , -v
	    prints LArSoft (environment) version [${VersionFormat}]
	--qualifiers , -q
	    prints the qualifiers (colon-separated) [${QualifiersFormat}]
	--experiment , -e
	    prints the experiment [${ExperimentFormat}]
	--package , -p
	    prints the version of the leading source package for the experiment,
	    or the version as in '--version' if no such source package is present [${PackageVersionFormat}]
	-P
	    prints the version of the leading source package for the experiment,
	    or an empty string if no such source package is present [${RealPackageVersionFormat}]
	--leadingpackage , -L
	    prints the name of the leading source package for the experiment [${LeadingPackageFormat}]
	-Q
	    prints the qualifiers (underscore-separated) [${QualifiersInPathFormat}]
	--ups , --upssetup , -u
	    prints leading package version and qualifiers in UPS setup format
	-U
	    prints LArSoft version and qualifiers in UPS setup format
	--localprod , -l
	    prints version and qualifiers in localProducts directory format
	--all
	    prints all the information in a human-friendly way
	--format=FORMAT , -f FORMAT
	    use FORMAT directly as format string; the string is printed by the bash
	    \`printf\` function; the codes for each option are reported in brackets
	    in the option description; the default format is '${DefaultFormat}'
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

function isDebugging() {
	local -i Level="${1:-1}"
	[[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge "$Level" ]]
} # isDebugging()

function DBGN() {
	local -i Level="$1"
	shift
	isDebugging "$Level" && STDERR "DBG[${Level}]| $*"
} # DBGN()
function DBG() { DBGN 1 "$@" ; }


function ParseLocalProductsDir() {
	local LPDir="$1"
	while [[ -h "$LPDir" ]] ; do
		LPDir="$(readlink "$LPDir")"
	done
	LPDir="$(basename "${LPDir:-$1}")"
	
	local -a VersionQuals
	local OldIFS="$IFS"
	IFS='_'
	VersionQuals=( ${LPDir} )
	IFS="$OldIFS"
	
	[[ "${VersionQuals[0]}" == "localProducts" ]] || return 1
	
	[[ -n "$MRB_PROJECT" ]] && [[ "$MRB_PROJECT" != "${VersionQuals[1]}" ]] && return 1
	local Project="${VersionQuals[1]}"
	
	local Version Quals
	case "${VersionQuals[2]}" in
		( 'nightly' )
			Version="${VersionQuals[2]}"
			;;
		( 'v'* )
			Version="${VersionQuals[2]}${VersionQuals[3]:+_${VersionQuals[3]}${VersionQuals[4]:+_${VersionQuals[4]}}}"
			;;
		( * ) # ??
			Version="${VersionQuals[2]}"
			;;
	esac
	local Quals="${LPDir#"localProducts_${VersionQuals[1]}_${Version}"}"
	Quals="${Quals#_}"
	DBGN 2 "  information from setup script '${SetupFile}': project '${Project}' version '${Version}' qualifiers '${Quals}'"
	echo "$Version"
	echo "$Quals"
	return 0
} # ParseLocalProductsDir()

function ParseLocalSetup() {
	local SetupFile="$1"
	[[ -r "$SetupFile" ]] || return 2
	
	local Project Version Quals
	
	local -a Line
	while read -a Line ; do
		[[ "${Line[0]}" == 'setenv' ]] || continue
		local Value="${Line[2]//\"}"
		case "${Line[1]}" in
			( 'MRB_PROJECT' )         Project="$Value" ;;
			( 'MRB_PROJECT_VERSION' ) Version="$Value" ;;
			( 'MRB_QUALS' )           Quals="$Value" ;;
		esac
	done < "$SetupFile"
	
	DBGN 2 "  information from setup script '${SetupFile}': project '${Project}' version '${Version}' qualifiers '${Quals}'"
	if [[ -z "$Project" ]] || [[ -z "$Version" ]] || [[ -z "$Quals" ]]; then
		DBGN 2 "    => information from setup script is not enough!"
		return 1
	fi
	echo "$Version"
	echo "$Quals"
	return 0
} # ParseLocalSetup()

function FindLocalProductsDir() {
	local BaseDir="${MRB_TOP:-"."}"
	[[ -d "$BaseDir" ]] || return 1
	for Pattern in "localProducts_${MRB_PROJECT}_" "localProducts_" "localProducts" "localProd" ; do
		local LocalProductsDir
		while read LocalProductsDir ; do
			DBGN 2 "  testing directory '${LocalProductsDir}'"
			local SetupFile="${LocalProductsDir}/setup"
			[[ -r "$SetupFile" ]] || continue
			
			local res=0
			VersionQuals="$(ParseLocalSetup "$SetupFile")"
			res=$?
			if [[ $res != 0 ]]; then
				VersionQuals="$(ParseLocalProductsDir "$LocalProductsDir")"
				res=$?
			fi
			
			[[ $res == 0 ]] || continue
			
			DBGN 2 "Local product directory is valid: '${LocalProductsDir}'"
			echo "$LocalProductsDir"
			return 0
		done < <( ls -drv "$Pattern"* 2> /dev/null )
	done
	return 1
} # FindLocalProductsDir()

function ExtractLocalProductsDirParams() {
	local LocalProductsDir
	LocalProductsDir="$(FindLocalProductsDir)"
	local res=$?
	[[ $res != 0 ]] && return $res
	ParseLocalSetup "${LocalProductsDir}/setup" && return 0
	ParseLocalProductsDir "$LocalProductsDir"
} # ExtractLocalProductsDirParams()


function FindLocalProduct() {
	local PackageName="$1"
	local PackageVersion="$2"
	local LocalProductDir="${3:-$(FindLocalProductsDir)}"
	
	local UPSpackageDir="${LocalProductDir}/${PackageName}"
	[[ -d "$UPSpackageDir" ]] || return 2
	
	[[ -d "${UPSpackageDir}/${PackageVersion}" ]]
} # FindLocalProduct()


function FindHighestLocalProductVersion() {
	local PackageName="$1"
	local LocalProductDir="${2:-$(FindLocalProductsDir)}"
	
	local UPSpackageDir="${LocalProductDir}/${PackageName}"
	[[ -d "$UPSpackageDir" ]] || return 2
	
	basename "$(ls -rvd "${UPSpackageDir}/"*.version | head -n 1)" | sed -e 's/.version$//'
} # FindHighestLocalProductVersion()


function FindPreviousLocalProductVersion() {
	local PackageName="$1"
	local PackageVersion="$2"
	local LocalProductsDir="${3:-$(FindLocalProductsDir)}"
	
	local UPSpackageDir="${LocalProductsDir}/${PackageName}"
	[[ -d "$UPSpackageDir" ]] || return 2
	
	local ReferenceKey="${UPSpackageDir}/${PackageVersion}.version"
	local TargetDir="$({ ls -d "${UPSpackageDir}/"*.version ; echo "$ReferenceKey" ; } | sort | grep -B1 "$ReferenceKey" | tail -n 2 | head -n 1)"
	[[ -n "$TargetDir" ]] && basename "${TargetDir%.version}"
} # FindPreviousLocalProductVersion()


function FindSourceDir() {
	local SourceDir="$MRB_SOURCE"
	[[ -z "$SourceDir" ]] && SourceDir="${MRB_TOP:-"."}/srcs"
	[[ -f "${SourceDir}/setEnv" ]] && echo "$SourceDir"
} # FindSourceDir()


function PackageSourceVersion() {
	local PackageName="$1"
	local SourceDir="${2:-$(FindSourceDir)}"
	[[ -z "$SourceDir" ]] && return 1
	
	local PackageDir="${SourceDir}/${PackageName}"
	[[ -d "$PackageDir" ]] || return 2
	local UPSdeps="${PackageDir}/ups/product_deps"
	[[ -f "$UPSdeps" ]] || return 3
	
	grep "^ *parent ${PackageName}" "$UPSdeps" | head -n 1 | awk '{ print $3 ; }'
	return $PIPESTATUS # grep return code
} # PackageSourceVersion()


function FindPackageVersion() {
	local PackageName="$1"
	local PackageVersion="$2"
	
	# look in the source directory for the current version ofthe specified package
	local DetectedPackageVersion="$(PackageSourceVersion "$PackageName")"
	
	if [[ -z "$DetectedPackageVersion" ]]; then # if we can't find any version...
		# look in the local products directory and get the most recent installed
		# version of this package up to the version we are setting up
		DetectedPackageVersion="$(FindPreviousLocalProductVersion "$PackageName" "$PackageVersion")"
	fi
	
	# if no version could be found don't print aything
	echo "$DetectedPackageVersion"
} # FindPackageVersion()


function DetectPackageVersion() {
	local PackageName="$1"
	local PackageVersion="$2"
	
	local DetectedPackageVersion="$(FindPackageVersion "$PackageName" "$PackageVersion")"
	
	# if no version could be found, just stick to the given version
	# (we hope it's somewhere in UPS)
	echo "${DetectedPackageVersion:-${PackageVersion}}"
} # DetectPackageVersion()


################################################################################
declare -i NoMoreOptions=0
declare -a Versions
declare -i nVersions=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1  ;;
			
			( '--version' | '-v' )    Format="${Format:+"${Format}\\n"}${VersionFormat}" ;;
			( '--package' | '-p' )    Format="${Format:+"${Format}\\n"}${RealPackageVersionFormat}" ;;
			( '-P' )                  Format="${Format:+"${Format}\\n"}${PackageVersionFormat}" ;;
			( '--qualifiers' | '-q' ) Format="${Format:+"${Format}\\n"}${QualifiersFormat}" ;;
			( '-Q' )                  Format="${Format:+"${Format}\\n"}${QualifiersInPathFormat}" ;;
			( '--experiment' | '-e' ) Format="${Format:+"${Format}\\n"}${ExperimentFormat}" ;;
			( '--leadingpackage' | '-L' ) Format="${Format:+"${Format}\\n"}${LeadingPackageFormat}" ;;
			( '--ups' | '--upssetup' | '-u' ) Format="${Format:+"${Format}\\n"}${UPSformat}" ;;
			( '-U' )                  Format="${Format:+"${Format}\\n"}${LArSoftUPSformat}" ;;
			( '--localprod' | '-l' )  Format="${Format:+"${Format}\\n"}${LocalProdFormat}" ;;
			( '--all' | '-a' )        Format="${Format:+"${Format}\\n"}${AllFormat}" ;;
			
			( '--format=' )           Format="${Param#--format=}" ;;
			( '--format' | '-f' )     let ++iParam; Format="${!iParam}" ;;
			
			### other stuff
			( '--debug' )             DEBUG=1 ;;
			( '--debug='* )           DEBUG="${Param#--debug=}" ;;
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

: ${DefaultLArSoftVersion:="${Versions[0]:-"default"}"}
: ${DefaultLArSoftQualifiers:="${Versions[1]:-"default"}"}
: ${DefaultExperiment:="${Versions[2]:-"LArSoft"}"}

: ${Format:="$DefaultFormat"}

if isFlagSet DoHelp ; then
	help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	exit $?
fi


declare LArSoftVersion=""
declare LArSoftQualifiers=""
declare Experiment=""

declare SetupDir="$(dirname "$0")"
[[ "${SetupDir:0:2}" == './' ]] && SetupDir="$(pwd)/${SetupDir:2}"
DBGN 2 "Setup directory: '${SetupDir}'"

###
### parse the current path, looking for experiment, LArSoft version and qualifiers
###
for LocalDir in "$(pwd)" "$SetupDir" ; do
	DBGN 1 "Extracting information from path: '${LocalDir}'"
	declare ExperimentTry=""
	declare LArSoftVersionTry=""
	declare LArSoftQualifiersTry=""
	while [[ "$LocalDir" != "/" ]]; do
		declare DirName="$(basename "$LocalDir")"
		declare DirRealName="$(basename "$(readlink "$LocalDir")")"
		
		DBGN 2 "  '${DirName}'${DirRealName:+" ( => '${DirRealName}'")}..."
		
		# experiment?
		if [[ -z "$ExperimentTry" ]]; then
			for TestName in "$DirName" "$DirRealName" ; do
				case "${TestName^^}" in
					( 'LBNE' )
						ExperimentTry='LBNE'
						DBGN 1 "  => experiment might be: '${ExperimentTry}'"
						continue 2
						;;
					( 'UBOONE' | 'MICROBOONE' )
						ExperimentTry='MicroBooNE'
						DBGN 1 "  => experiment might be: '${ExperimentTry}'"
						continue 2
						;;
				esac
			done
		fi
		
		# version?
		if [[ -z "$LArSoftVersionTry" ]]; then
			for TestName in "$DirName" "$DirRealName" ; do
				# branch names
				case "$TestName" in
					( 'develop' | 'master' | 'nightly' )
						LArSoftVersionTry="$TestName"
						DBGN 1 "  => LArSoft version might be: '${LArSoftVersionTry}'"
						continue 2
						;;
				esac
				# version pattern
				if [[ "$TestName" =~ v[[:digit:]]+_[[:digit:]]+(_[[:digit:]]+)?$ ]]; then
					LArSoftVersionTry="$TestName"
					DBGN 1 "  => LArSoft version might be: '${LArSoftVersionTry}' (matches pattern)"
					continue 2
				fi
			done
		fi
		
		# qualifiers?
		if [[ -z "$LArSoftQualifiersTry" ]]; then
			for TestName in "$DirName" "$DirRealName" ; do
				if tr ':_' '\n' <<< "$TestName" | grep -q -w -e 'debug' -e 'prof' -e 'opt' ; then
					LArSoftQualifiersTry="${TestName//_/:}"
					DBGN 1 "  => qualifiers might be: '${LArSoftQualifiersTry}' (matches pattern)"
					continue 2
				fi
			done
		fi
		
		LocalDir="$(dirname "$LocalDir")"
	done
	unset TestName DirRealName
	
	if [[ -n "$ExperimentTry" ]] && [[ -n "$LArSoftVersionTry" ]] && [[ -n "$LArSoftQualifiersTry" ]]; then
		break
	fi
done
# if the experiment hasn't been found, never mind
if [[ -n "$LArSoftVersionTry" ]] && [[ -n "$LArSoftQualifiersTry" ]]; then
	: ${Experiment:="$ExperimentTry"}
	: ${LArSoftVersion:="$LArSoftVersionTry"}
	: ${LArSoftQualifiers:="$LArSoftQualifiersTry"}
fi
unset ExperimentTry LArSoftVersionTry LArSoftQualifiersTry

# still nothing, try to autodetect from the mounted directories
if [[ -z "$Experiment" ]]; then
	if [[ -d "/lbne" ]]; then
		Experiment="LBNE"
	elif [[ -d "/uboone" ]]; then
		Experiment="MicroBooNE"
	else
		Experiment="LArSoft"
	fi
	DBGN 1 "Experiment forcibly set to: '${Experiment}'"
fi

LocalProductsDirInfo=( $(ExtractLocalProductsDirParams "$MRB_TOP" ) )
if [[ $? == 0 ]]; then
	LArSoftVersion="${LocalProductsDirInfo[0]}"
	LArSoftQualifiers="${LocalProductsDirInfo[1]}"
	DBGN 1 "Information from local product directory: version '${LArSoftVersion}' qualifiers '${LArSoftQualifiers}'"
fi

: ${LArSoftVersion:="$DefaultLArSoftVersion"}
: ${LArSoftQualifiers:="$DefaultLArSoftQualifiers"}
: ${Experiment:="$DefaultExperiment"}

case "${Experiment,,}" in
	( 'auto' | 'autodetect' | '' )
		;;
	( 'lbne' )
		Experiment="LBNE"
		LeadingPackage="lbnecode"
		;;
	( 'uboone' | 'microboone' )
		Experiment="MicroBooNE"
		LeadingPackage="uboonecode"
		;;
	( 'larsoft' )
		Experiment="LArSoft"
		LeadingPackage="larsoft"
		;;
esac

# look in the source directory for the current version ofthe specified package
declare RealLeadingPackageVersion="$(FindPackageVersion "$LeadingPackage" "$LArSoftVersion")"
declare LeadingPackageVersion=${RealLeadingPackageVersion:-${LArSoftVersion}}

declare Output="$Format"
Output="$(sed -e "s/\(^\|[^${ItemTag}]\)${VersionFormat}/\1${LArSoftVersion}/g" <<< "$Output")"
Output="$(sed -e "s/\(^\|[^${ItemTag}]\)${QualifiersFormat}/\1${LArSoftQualifiers//_/:}/g" <<< "$Output")"
Output="$(sed -e "s/\(^\|[^${ItemTag}]\)${QualifiersInPathFormat}/\1${LArSoftQualifiers//:/_}/g" <<< "$Output")"
Output="$(sed -e "s/\(^\|[^${ItemTag}]\)${ExperimentFormat}/\1${Experiment}/g" <<< "$Output")"
Output="$(sed -e "s/\(^\|[^${ItemTag}]\)${RealPackageVersionFormat}/\1${RealLeadingPackageVersion}/g" <<< "$Output")"
Output="$(sed -e "s/\(^\|[^${ItemTag}]\)${PackageVersionFormat}/\1${LeadingPackageVersion}/g" <<< "$Output")"
Output="$(sed -e "s/\(^\|[^${ItemTag}]\)${LeadingPackageFormat}/\1${LeadingPackage}/g" <<< "$Output")"
Output="$(sed -e "s/${ItemTag}${ItemTag}/${ItemTag}/g" <<< "$Output")"
printf "$Output"

