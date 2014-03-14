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

: ${DefaultFormat:="%V\n%Q\n%E\n"}

function help() {
	cat <<-EOH
	Creates a workikng area based on a production release (no MRB).
	
	Usage:  ${SCRIPTNAME} [options] [version [qualifiers [experiment]]]
	
	The three arguments specify a default value if autodetection fails.
	
	Options [defaults in brackets]:
	--version , -v
	    prints the version
	--qualifiers , -q
	    prints the qualifiers (colon-separated)
	--experiment , -e
	    prints the experiment
	-Q
	    prints the qualifiers (underscore-separated)
	--ups , --upssetup , -u
	    prints version and qualifiers in UPS setup format
	--localprod , -l
	    prints version and qualifiers in localProducts directory format
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
	echo "$Version"
	echo "$Quals"
	return 0
} # ParseLocalProductsDir()

function FindLocalProductsDir() {
	local BaseDir="${MRB_TOP:-"."}"
	[[ -d "$BaseDir" ]] || return 1
	for Pattern in "localProducts_${MRB_PROJECT}_" "localProducts_" "localProducts" "localProd" ; do
		local LocalProductsDir
		ls -drv "$Pattern"* 2> /dev/null | while read LocalProductsDir ; do
			[[ -r "${LocalProductsDir}/setup" ]] || continue
			
			VersionQuals="$(ParseLocalProductsDir "$LocalProductsDir")"
			[[ $? == 0 ]] || continue
			
			echo "$VersionQuals"
			exit 42
		done
		[[ $? == 42 ]] && return 0
	done
	return 1
} # FindLocalProductsDir()


################################################################################
declare -i NoMoreOptions=0
declare -a Versions
declare -i nVersions=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1  ;;
			
			( '--version' | '-v' )    Format="${Format:+"${Format}\n"}%V" ;;
			( '--qualifiers' | '-q' ) Format="${Format:+"${Format}\n"}%Q" ;;
			( '-Q' ) Format="${Format:+"${Format}\n"}%q" ;;
			( '--experiment' | '-e' ) Format="${Format:+"${Format}\n"}%E" ;;
			( '--ups' | '--upssetup' | '-u' ) Format="${Format:+"${Format}\n"}%V -q %Q" ;;
			( '--localprod' | '-l' ) Format="${Format:+"${Format}\n"}%V_%q" ;;
			
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
[[ "$SetupDir" != '/' ]] && SetupDir="$(pwd)/${SetupDir}"


###
### parse the current path, looking for experiment, LArSoft version and qualifiers
###
for LocalDir in "$(pwd)" "$SetupDir" ; do
	declare ExperimentTry=""
	declare LArSoftVersionTry=""
	declare LArSoftQualifiersTry=""
	while [[ "$LocalDir" != "/" ]]; do
		declare DirName="$(basename "$LocalDir")"
		declare DirRealName="$(basename "$(readlink "$LocalDir")")"
		
		# experiment?
		if [[ -z "$ExperimentTry" ]]; then
			for TestName in "$DirName" "$DirRealName" ; do
				case "$(tr '[:lower:]' '[:upper:]' <<< "$TestName")" in
					( 'LBNE' )
						ExperimentTry='LBNE'
						continue 2
						;;
					( 'UBOONE' | 'MICROBOONE' )
						ExperimentTry='MicroBooNE'
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
						continue 2
						;;
				esac
				# version pattern
				if [[ "$TestName" =~ v[[:digit:]]+_[[:digit:]]+(_[[:digit:]]+)?$ ]]; then
					LArSoftVersionTry="$TestName"
					continue 2
				fi
			done
		fi
		
		# qualifiers?
		if [[ -z "$LArSoftQualifiersTry" ]]; then
			for TestName in "$DirName" "$DirRealName" ; do
				if tr ':_' '\n' <<< "$TestName" | grep -q -w -e 'debug' -e 'prof' -e 'opt' ; then
					LArSoftQualifiersTry="${TestName//_/:}"
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
fi

LocalProductsDirInfo=( $(FindLocalProductsDir "$MRB_TOP" ) )
if [[ $? == 0 ]]; then
	LArSoftVersion="${LocalProductsDirInfo[0]}"
	LArSoftQualifiers="${LocalProductsDirInfo[1]}"
fi

: ${LArSoftVersion:="$DefaultLArSoftVersion"}
: ${LArSoftQualifiers:="$DefaultLArSoftQualifiers"}
: ${Experiment:="$DefaultExperiment"}

case "$(tr '[:upper:]' '[:lower:]' <<< "$Experiment")" in
	( 'auto' | 'autodetect' | '' )
		;;
	( 'lbne' )
		Experiment="LBNE"
		;;
	( 'uboone' | 'microboone' )
		Experiment="MicroBooNE"
		;;
	( 'larsoft' )
		Experiment="LArSoft"
		;;
esac

declare Output="$Format"
Output="$(sed -e "s/\(^\|[^%]\)%V/\1${LArSoftVersion}/g" <<< "$Output")"
Output="$(sed -e "s/\(^\|[^%]\)%Q/\1${LArSoftQualifiers//_/:}/g" <<< "$Output")"
Output="$(sed -e "s/\(^\|[^%]\)%q/\1${LArSoftQualifiers//:/_}/g" <<< "$Output")"
Output="$(sed -e "s/\(^\|[^%]\)%E/\1${Experiment}/g" <<< "$Output")"
Output="$(sed -e "s/%%/%/g" <<< "$Output")"
printf "$Output"
