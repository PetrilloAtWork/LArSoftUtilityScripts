#!/bin/bash
#
# Runs a lar command in the background and puts the output in a log file
#
# Use with --help for usage instructions.
#
# Vesion history:
# 1.0 (petrillo@fnal.gov)
#     first published version
# 1.1 (petrillo@fnal.gov)
#     added source file specification and printing of start command
# 1.2 (petrillo@fnal.gov)
#     improved code identification
# 1.3 (petrillo@fnal.gov)
#     in sandbox mode, all the lar arguments known to be file paths are made
#     absolute; this makes the '-s' option implementation redundant
#

SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.4"

DATETAG="$(datetag)"

# this is the maximum number of logs that we allow; negative will allow any,
# but it's better to leave it to a reasonably large value to avoid infinite
# loops in case of problems or bugs
: ${MAXLOGS:="1000"}

: ${SANDBOX:=1}
: ${NOBG:=0}
: ${DUMPCONFIG:=1}

#
# Default options for the profilers here
#

# maximum number of snapshots taken; after this many are taken, every other
# snapshot is dropped before a new one is taken
: ${MASSIF_MAXSNAPSHOTS:="1000"}
# threshold below which allocations are aggregated as "below threshold",
# in percent of the total memory
: ${MASSIF_MEMTHR:="0.1"}
# rate of detailed snapshots
# (e.g. 10: 1 detailed every 10 snapshots; 1: every snapshot is detailed)
: ${MASSIF_DETAILEDFREQ:="1"}

#
# Standard packages which will be always looked for when printing the environment
#
declare -a StandardPackages
StandardPackages=(
	larcore lardata larevt larsim larreco larana
	lareventdisplay larpandora larsoft
	larexamples uboonecode lbnecode
)


function help() {
	cat <<-EOH
	Runs a lar command in the background and puts the output in a log file.
	
	Usage:  ${SCRIPTNAME} [script options] [--] ConfigFile  [Other options]
	
	The command run is:
	
	lar -c ConfigFile [OtherOptions] >& LogFile
	
	The log file path is automatically chosen and it is printed on the screen.
	By default the lar command is put into the background and abandoned to its own.
	The command is executed in a newly created directory (the "sandbox").
	
	Script options:
	--config=CONFIGFILE , -c CONFIGFILE
	    alternative way to specify a configuration file; if not specified, the
	    first non-option parameter will be taken as configuration file
	--foreground , --fg
	    does not put the command in background and waits for it to finish,
	    dumping the log on the screen in the meanwhile
	--nologdump
	    when running in foreground, don't dumb the log on screen
	--noconfigdump
	    skip the configuration dump creation
	--inline , --nosandbox
	    runs the command in the current directory rather than in a newly created
	    one
	--jobname=JOBNAME
	    the label for this job (the output directory and log file are named after
	    it)
	--printenv , -E
	    print on the screen the LARSoft UPS packages set up, and exit
	--norun , -N
	    does not actually run (use to debug ${SCRIPTNAME})
	
	 (profiling options)
	--prepend=Executable
	    prepends the specified executable to the lar command
	--prependopt=OptionString
	--prependopts=OptionString
	    if --prepend is specified, OptionString is added to the executable
	    parameters before the lar command; with --prependopts, the OptionString
	    string will be split in parameters by the usual shell rules
	    (IFS variable); with --prependopt, it will be added as a single
	    parameter; these options can be specified multiple times
	--env:VARNAME=VALUE
	    adds a variable VARNAME with the specified value to the environment
	    passed to the command
	--profile=Profiler
	    prepends a known profiler to the lar command (see options below)
	--fast[=ProfileOptionString], -F
	    equivalent to --prepend=fast or --profile=fast: uses the FAST profiler;
	    the optional ProfileOptionString string will be added in a way equivalent
	    to --prependopts=ProfileOptionString
	--oss[=ProfileOptionString]
	    equivalent to --prepend=ossProfileOptionString: uses the Open|SpeedShop
	    profiler; the optional ProfileOptionString string will be
	    added to the command line in order to get the actual profiler executable;
	    if ProfileOptionString is not specified, usertime is used; that is also
	    the profiler used when --profile=oss is specified
	--gpt , --gperftools
	    equivalent to --profile=GPerfTools: uses the GPerfTools profiler;
	    options can be added to the environment via "--env:" options
	--valgrind[=ProfileOptionString], -V
	    equivalent to --prepend=valgrind or --profile=valgrind: uses valgrind
	    memory analyser; the optional ProfileOptionString string will be added in
	    a way equivalent to --prependopts=ProfileOptionString
	--massif[=ProfileOptionString]
	    uses valgrind's massif tool for memory allocation profiling;
	    equivalent to --valgrind='--tool=massif'
	--stack
	    enables stack profiling if the tool supports it (if not, will complain)
	--mmap
	    enables more general heap profiling (mmap) if the tool supports it (if
	    not, will complain)
	--version , -V
	    prints the script version
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

function datetag() { date '+%Y%m%d' ; }

function IsInList() {
	local Key="$1"
	shift
	local Item
	for Item in "$@" ; do
		[[ "$Item" == "$Key" ]] && return 0
	done
	return 1
} # IsInList()


function FindNextFile() {
	# Prints the next available log file with the specified base name and suffix
	local BasePath="$1"
	local Suffix="$2"
	local -i IndexPadding="${3:-2}"
	local -i MaxIndex="${4:-"100"}"
	
	local BaseName="$(basename "$BasePath")"
	local Dir="$(dirname "$BasePath")"
	local -i Index=0
	local Path
	for (( Index = 0 ; Index != $MAXLOGS ; ++Index)); do
		Path="${Dir}/${BaseName}-$(printf "%0*d" "$IndexPadding" "$Index")${Suffix}"
		[[ -r "$Path" ]] && continue
		echo "$Path"
		return 0
	done
	return 1
} # FindNextFile()


function FindNextLogFile() {
	# Prints the next available log file with the specified base name
	# The log path is in the form:
	# logs/ConfigBaseName_Date-##.fcl
	local ConfigBaseName="${1%".fcl"}"
	local -i IndexPadding="${2:-2}"
	
	FindNextFile "logs/${ConfigBaseName}/${DATETAG}" '.log' "$IndexPadding" $MAXLOGS
} # FindNextLogFile()


function LowerCase() { local VarName="$1" ; tr '[:upper:]' '[:lower:]' <<< "${!VarName}" ; }


function SetupProfiler() {
	local Profiler="$1"
	
	case "$Profiler" in
		( 'fast' )
			PrependExecutable="profrun"
			PrependExecutableParameters=( "${ProfilerToolParams[@]}" )
			;;
		( 'Open|SpeedShop' )
			case $(LowerCase ProfilerTool) in
				( 'usertime' | 'ossusertime' ) PrependExecutable="ossusertime" ;;
				( '' )                         PrependExecutable="ossusertime" ;;
				( * ) FATAL 1 "Unsupported profiling tool for ${Profiler}: '${ProfilerTool}'" ;;
			esac
			PrependExecutableParameters=( "${ProfilerToolParams[@]}" )
			OneStringCommand=1
			;;
		( 'GPerfTools' )
			# the Google GPerfTools don't use an executable, but a dynamic library
			PrependExecutable=""
			PrependExecutableParameters=( )
			
			# this is the file which will be created...
			ProfileOutputFile="${JobName}-gperftools.prof"
			
			GPerfToolsLib='libprofiler.so'
			CommandEnvironment=( "${CommandEnvironment[@]}" "LD_PRELOAD=${GPerfToolsLib}" "CPUPROFILE=${ProfileOutputFile}" )
			;;
		( 'valgrind' )
			PrependExecutable="valgrind"
			
			case $(LowerCase ProfilerTool) in
				( 'memcheck' | '' )
					ToolOption="${ProfilerTool:-"memcheck"}"
					
					# these are the files which will be created...
					LogOutputFile="${JobName}-${ToolOption}.log"
					MachineOutputFile="${JobName}-${ToolOption}.xml"
					
					PrependExecutableParameters=( "${ProfilerToolParams[@]}"
						"--tool=${ToolOption}"
						"--xml=yes" "--xml-file=${MachineOutputFile}" # generate XML output and write it file
						"--log-file=${LogOutputFile}" # send the plain text output to a second file
						'--child-silent-after-fork=yes' # do not trace child (fork()'ed) processes
						'-q' # reduce the plain text output
						'--leak-check=full'
						)
					;;
				( 'massif' )
					StacksSupport=1
					ToolOption="$ProfilerTool"
					OutputFile="${JobName}-${ToolOption}.out"
					PrependExecutableParameters=( "${ProfilerToolParams[@]}"
						"--tool=${ToolOption}"
						"--massif-out-file=${OutputFile}"
						${MASSIF_MAXSNAPSHOTS:+"--max-snapshots=${MASSIF_MAXSNAPSHOTS}"}
						${MASSIF_DETAILEDFREQ:+"--detailed-freq=${MASSIF_DETAILEDFREQ}"}
						${MASSIF_MEMTHR:+"--threshold=${MASSIF_MEMTHR}"}
						)
					isFlagSet DoStackProfiling && PrependExecutableParameters=( "${PrependExecutableParameters[@]}" '--stacks=yes' )
					isFlagSet DoMMapProfiling && PrependExecutableParameters=( "${PrependExecutableParameters[@]}" '--pages-as-heap=yes' )
					;;
				( 'dhat' )
					ToolOption="exp-dhat"
					PrependExecutableParameters=( "${ProfilerToolParams[@]}"
						"--tool=${ToolOption}"
						)
					;;
				( 'callgrind' | 'cachegrind' )
					ToolOption="$ProfilerTool"
					PrependExecutableParameters=( "${ProfilerToolParams[@]}" "--tool=${ToolOption}" )
					;;
				( * ) FATAL 1 "Unsupported profiling tool for ${Profiler}: '${ProfilerTool}'" ;;
			esac
			;;
		( 'igprof' )
			PrependExecutable="igprof"
			
			case $(LowerCase ProfilerTool) in
				( 'performance' | 'memory' | '' )
					ToolOption="-${ProfilerTool:0:1}p"
					
					# these are the files which will be created...
					MachineOutputFile="${JobName}-${ProfilerTool}.gz"
					
					PrependExecutableParameters=( "${ProfilerToolParams[@]}"
						"$ToolOption"
						"-z" "--output ${MachineOutputFile}" # profiling output file
						"--debug" # a bit more output
						)
					;;
				( * ) FATAL 1 "Unsupported profiling tool for ${Profiler}: '${ProfilerTool}'" ;;
			esac
			;;
		( '' ) ;; # rely on the existing variables, no special setup
		( * ) return 1 ;;
	esac
	
	if isFlagSet DoStackProfiling && isFlagUnset StacksSupport ; then
		ERROR "Stacks profiling is not supported by ${Profiler}${ProfilerTool:+/${ProfilerTool}}"
		return 1
	fi
	
	return 0
} # SetupProfiler()


function SetupCommand() {
	local -a BaseCommand=( "$@" )
	
	isFlagSet OneStringCommand && BaseCommand=( "${BaseCommand[*]}" )
	
	# set the environment; needs to be done first
	[[ "${#CommandEnvironment[@]}" -gt 0 ]] && Command=( 'env' "${CommandEnvironment[@]}" )
	
	# add prepended commands
	[[ -n "$PrependExecutable" ]] && Command=( "${Command[@]}" "$PrependExecutable" "${PrependExecutableParameters[@]}" )
	
	Command=( "${Command[@]}" "${BaseCommand[@]}" )
	
	export Command
	return 0
} # SetupCommand()


function ExtractProductDirectoryFromSetup() {
	local PACKAGE="$(tr '[:lower:]' '[:upper:]' <<< "$1")"
	local SETUP_PACKAGE="SETUP_${PACKAGE}"
	local -a Items
	read -a Items <<< "${!SETUP_PACKAGE}"
	local iItem
	for (( iItem = 0 ; iItem < ${#Items[@]} ; ++iItem )); do
		[[ "${Items[iItem]}" == '-z' ]] && echo "${Items[iItem+1]}" && return 0
	done
	return 1
} # ExtractProductDirectoryFromSetup()


function PrintUPSsetup() {
	# PrintUPSsetup Package VarName [VarName ...]
	# 
	# Prints the selected UPS setup information extracted from SETUP_PACKAGE
	# variable; the supported variable names are:
	# - Package
	# - Version
	# - Qualifiers (-q option)
	# - Flavour (-f option)
	# - Repository (-z option)
	# 
	
	
	local PACKAGE="$(tr '[:lower:]' '[:upper:]' <<< "$1")"
	shift
	
	local SETUP_PACKAGE="SETUP_${PACKAGE}"
	local -a Items
	read -a Items <<< "${!SETUP_PACKAGE}"
	local -i iItem
	local -i NonOptionItems=0
	for (( iItem = 0 ; iItem < ${#Items[@]} ; ++iItem )); do
		local Item="${Items[iItem]}"
		case "$Item" in
			( '-z' ) Repository="${Items[++iItem]}" ;;
			( '-q' ) Qualifiers="${Items[++iItem]}" ;;
			( '-f' ) Flavour="${Items[++iItem]}" ;;
			( * )
				case $((NonOptionItems++)) in
					( 0 ) Package="$Item" ;;
					( 1 ) Version="$Item" ;;
					( * ) ERROR "Unknown item '${Item}' in UPS setup ${SETUP_PACKAGE}" ;;
				esac
				;;
		esac
	done # for items in SETUP_PACKAGE
	
	local Output
	for VarName in "$@" ; do
		[[ -z "$Output" ]] || Output+=" "
		Output+="${!VarName}"
	done
	echo "$Output"
	[[ -n "$Output" ]] # this is the return value
} # PrintUPSsetup()



function PrintLocalPackage() {
	local Package="$1"
	
	# the only (supported) way to use a package is to set it up via UPS
	local PACKAGE="$(tr '[:lower:]' '[:upper:]' <<< "$Package" )"
	local SetupVarName="SETUP_${PACKAGE}"
	[[ -z "${!SetupVarName}" ]] && return 1
	
	# get information about the UPS package
	read UPSpackage Version Qualifiers Repository <<< "$(PrintUPSsetup "$Package" Package Version Qualifiers Repository)"
	
	[[ "$Package" != "$UPSpackage" ]] && echo -n "[MISMATCH: ${Package}] "
	echo -n "${UPSpackage} ${Version} (${Qualifiers:-"no quals"})"
	
	# if that is the same as the local one, 
	if [[ "$MRB_INSTALL" == "$Repository" ]]; then
		echo -n " from local area"
		if [[ -d "${MRB_SOURCE}/${Package}" ]]; then
			pushd "${MRB_SOURCE}/${Package}" >& /dev/null
			local GITCommitHash="$(git log --pretty='%H %ci' -n 1)"
			popd >& /dev/null
			
			echo -n " => GIT commit ${GITCommitHash}"
		else
			echo -n " => source not found!"
		fi
	elif [[ -n "$Repository" ]]; then
		echo -n " from ${Repository}"
	else
		echo -n " from unknown UPS repository"
	fi
	echo
	return 0
} # PrintLocalPackage()

function PrintPackageVersions() {
	
	local -i nStandardMissing=0
	
	# first the default packages:
	local Package
	for Package in "${StandardPackages[@]}" ; do
		
		PrintLocalPackage "$Package"
		[[ $? != 0 ]] && echo "${Package}: not configured!!!"
		let ++nStandardMissing
	done
	
	# other local packages
	local UPSpackagePath
	if [[ -n "$MRB_INSTALL" ]]; then
		for UPSpackagePath in "${MRB_INSTALL}/"* ; do
			[[ -d "$UPSpackagePath" ]] || continue
			
			Package="$(basename "$UPSpackagePath")"
			
			# if is standard, we have printed it already
			IsInList "$Package" "${StandardPackages[@]}" && continue
			
			PrintLocalPackage "$Package"
			
		done
		echo "Local area: '${MRB_INSTALL}'"
	else
		echo "[no MRB local products]"
	fi
	return $nStandardMissing
} # PrintPackageVersions()



function InterruptHandler() {
	echo
	STDERR "Interruption requested."
	
	[[ -n "$LarPID" ]] && kill -INT "$LarPID"
	[[ -n "$LogPID" ]] && kill -PIPE "$LogPID"
	
	cat <<-EOM
	$(date) --- user interrupted --------------------------------------------------"
	To see the fragments of output:
	cd ${WorkDir}
	EOM
	exit 1
} # Interrupt()


################################################################################
declare JobBaseName

declare DoHelp=0 DoVersion=0 OnlyPrintEnvironment=0 NoLogDump=0

declare -i NoMoreOptions=0
declare ConfigFile
declare -a Params
declare -i nParams=0
declare -a SourceFiles
declare -a PrependExecutable
declare -a PrependExecutableParameters
declare -i PrependExecutableNParameters
declare -i OneStringCommand=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' )     DoHelp=1  ;;
			( '--version' | '-V' )         DoVersion=1  ;;
			( '--printenv' | '-E' )        OnlyPrintEnvironment=1  ;;
			( '--norun' | '-N' )           DontRun=1  ;;
			
			### behaviour options
			( '--foreground' | '--fg' )    NOBG=1    ;;
			( '--background' | '--bg' )    NOBG=0    ;;
			( '--inline' | '--nosandbox' ) SANDBOX=0 ;;
			( '--sandbox' )                SANDBOX=1 ;;
			( '--nologdump' )              NoLogDump=1 ;;
			( '--noconfigdump' )           DUMPCONFIG=0 ;;
			( '--config='* | '--cfg='* )   ConfigFile="${Param#--*=}" ;;
			( '-c' )                       let ++iParam ; ConfigFile="${!iParam}" ;;
		#	( '--source='* | '--src='* )   SourceFiles=( "${SourceFiles[@]}" "${Param#--*=}" ) ;;
		#	( '-s' )                       let ++iParam ; SourceFiles=( "${SourceFiles[@]}" "${!iParam}" ) ;;
			( '--jobname='* )              JobBaseName="${Param#--*=}" ;;
			
			### profiling options
			( '--prepend='* )
				PrependExecutable="${Param#--*=}"
				;;
			( '--prependopt='* )
				PrependExecutableParameters[PrependExecutableNParameters++]="${Param#--*=}"
				;;
			( '--prependopts='* )
				for Option in ${Param#--*=} ; do
					PrependExecutableParameters="$Option"
				done
				;;
			( '--profile='* )
				Profiler="${Param#--*=}"
				;;
			( '--env:'*=* )
				CommandEnvironment=( "${CommandEnvironment[@]}" "${Param#--env:}" )
				;;
			( '--stack' ) DoStackProfiling=1 ;;
			( '--mmap' ) DoMMapProfiling=1 ;;
			
			#
			# FAST profiler
			( '--fast='* )
				Profiler="fast"
				ProfilerToolParams=( "${Param#--*=}" )
				;;
			( '--fast' | '-F' )
				Profiler="fast"
				;;
			#
			# Open|SpeedShop profiler
			( '--oss='* )
				Profiler="Open|SpeedShop"
				ProfilerTool="oss${Param#--*=}"
				;;
			( '--oss' )
				Profiler="Open|SpeedShop"
				;;
			#
			# GPerfTools
			( '--gpt' | '--gperf' | '--gperftool' | '--gperftools' )
				Profiler="GPerfTools"
				;;
			#
			# valgrind
			( '--valgrind='* )
				Profiler="valgrind"
				ProfilerToolParams=( "${Param#--*=}" )
				;;
			( '--valgrind' | '-V' )
				Profiler="valgrind"
				;;
			(    '--massif'   | '--massif='*         \
				| '--dhat'     | '--dhat='*           \
				| '--memcheck' | '--memcheck='*       \
				| '--callgrind' | '--callgrind='*     \
				| '--cachegrind' | '--cachegrind='*   \
			)
				Profiler="valgrind"
				ProfilerTool="${Param%%=*}"
				ProfilerTool="${ProfilerTool#--}"
				[[ "$Param" =~ = ]] && ProfilerToolParams=( "${Param#--${ProfilerTool}=}" )
				;;
			
			# 
			# Ignominous Profiler
			( '--igprof' | '-I' )
				Profiler="igprof"
				ProfilerTool="performance"
				;;
			( '--igprof='* )
				Profiler="igprof"
				ProfilerTool="performance"
				ProfilerToolParams=( "${Param#--*=}" )
				;;
			( '--igprof_mem' | '--igprof_mem='* )
				Profiler="igprof"
				ProfilerTool="memory"
				ProfilerToolParams=( "${Param#--*=}" )
				[[ "$Param" =~ = ]] && ProfilerToolParams=( "${Param#--*=}" )
				;;
			
			### other stuff
			( '-' | '--' )
				NoMoreOptions=1
				;;
			( * )
				echo "Unrecognized script option #${iParam} - '${Param}'"
				exit 1
				;;
		esac
	else
		NoMoreOptions=1
		if [[ -z "$ConfigFile" ]]; then
			ConfigFile="$Param"
		else
			Params[nParams++]="$Param"
		fi
	fi
done

declare -i ExitCode
if isFlagSet OnlyPrintEnvironment ; then
	PrintPackageVersions "${StandardPackages[@]}"
	{ [[ -z "$ExitCode" ]] || [[ "$ExitCode" == 0 ]] ; } && ExitCode="$?"
fi

if isFlagSet DoVersion ; then
	echo "${SCRIPTNAME} version ${SCRIPTVERSION:-"unknown"}"
	: ${ExitCode:=0}
fi

if isFlagSet DoHelp || [[ -z "$ConfigFile" ]] ; then
	help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	{ [[ -z "$ExitCode" ]] || [[ "$ExitCode" == 0 ]] ; } && ExitCode="$?"
fi

[[ -n "$ExitCode" ]] && exit $ExitCode

# steal lar parameters and identify path parameters
declare -ai PathParams
declare -a LArParams
for (( iParam = 0; iParam < $nParams ; ++iParam )); do
	Param="${Params[iParam]}"
	case "$Param" in
		( '-s' | '-S' | '-T' | '-o' \
			| '--source' | '--source-list' | '-TFileName' | '--output' \
			)
			let ++iParam # skip the file name
			LArParams=( "${LArParams[@]}" "$Param" "${Params[iParam]}" )
			PathParams=( "${PathParams[@]}" "$((${#LArParams[@]} - 1))" )
			;;
		( '-c' | '--config' )
			let ++iParam # skip the file name
			[[ -n "$ConfigFile" ]] && [[ "$ConfigFile" != "${Params[iParam]}" ]] && FATAL 1 "Configuration file specified more than once ('${ConfigFile}', then '${Params[iParam]}')"
			ConfigFile="${Params[iParam]}"
			;;
		( * )
			LArParams=( "${LArParams[@]}" "$Param" )
			;;
	esac
done


declare ConfigName="$(basename "${ConfigFile%.fcl}")"
: ${JobBaseName:="$ConfigName"}

declare ConfigPath="$ConfigFile"
declare LogPath
LogPath="$(FindNextLogFile "$JobBaseName")"
LASTFATAL "Failed to find a suitable log file name for ${JobBaseName}!"

declare JobName="${JobBaseName}-$(basename "${LogPath%.log}")"

# make sure we can freely overwrite the log files:
set +o noclobber

#
# create the directory for the log file
#
declare LogDir="$(dirname "$LogPath")"
mkdir -p "$LogDir"
[[ -d "$LogDir" ]] || FATAL 3 "Can't create the log directory '${LogDir}'."
touch "$LogPath" || FATAL 2 "Can't create the log file '${LogPath}'."

declare AbsoluteLogPath="$(readlink -f "$LogPath")"

#
# prepare an empty sandbox
#
if isFlagSet SANDBOX ; then
# 	declare WorkDir="$(mktemp -d "workdir_${JobName}_XXXXXX" )"
	declare WorkDir="${LogPath%.log}"
	mkdir -p "$WorkDir"
	
	# we need to make the config path absolute;
	# in alternative, we could specify a command line parameter
# 	[[ -r "$ConfigFile" ]] && ConfigPath="$(readlink -f "$ConfigFile")"
	
	# we want the actual log file to be in the sandbox;
	# for convenience, it will be linked by the one outside the box
	declare RealLogPath="${WorkDir}/${JobName}.log"
	mv "$LogPath" "$RealLogPath"
	ln -s "$(basename "$WorkDir")/$(basename "$RealLogPath")" "$LogPath"
	
	# instead, we copy the configuration file in the working area;
	# this helps keeping track of what was actually used
	if [[ -r "$ConfigFile" ]]; then
		cp -a "$ConfigFile" "$WorkDir"
		ConfigPath="./$(basename "$ConfigFile")"
	fi
	
	for (( iSource = 0 ; iSource < ${#SourceFiles[@]} ; ++iSource )); do
		SourceFile="${SourceFiles[iSource]}"
		if [[ -r "$SourceFile" ]]; then
			SourceFiles[iSource]="$(readlink -f "$SourceFile")"
		fi
	done
	
	# turn all the path parameters to absolute
	for iParam in "${PathParams[@]}" ; do
		LArParams[iParam]="$(pwd)/${LArParams[iParam]}"
	done
	
	pushd "$WorkDir" > /dev/null || FATAL 3 "Can't use the working directory '${WorkDir}'"
fi

#
# expand lar parameters
#
declare -a SourceParams
for SourceFile in "${SourceFiles[@]}" ; do
	SourceParams=( "${SourceParams[@]}" '-s' "$SourceFile" )
done

#
# expand the parameters needed for the profiling (if any)
#
SetupProfiler "$Profiler"
LASTFATAL "Error setting up the profiling tool '${Profiler}'. Quitting."

#
# execute the command
#
declare -a BaseCommand
BaseCommand=( lar -c "$ConfigPath" "${SourceParams[@]}" "${LArParams[@]}" )

declare -a Command
SetupCommand "${BaseCommand[@]}"

# if user interrupts, we want to terminate our children...
trap InterruptHandler SIGINT

#
# communicate what's going on, and exit
#
echo "$(date) --- starting ---------------------------------------------------"
cat <<EOM > "$AbsoluteLogPath"
================================================================================
Job name:  '${JobName}'
Host:       $(hostname)
Directory:  $(pwd)
Executing:  ${Command[@]}
Log file:  '${LogPath}'
Date:       $(date)
Run with:   ${0} ${@}
================================================================================
$(PrintPackageVersions "${StandardPackages[@]}")
================================================================================
EOM

if isFlagSet DUMPCONFIG ; then
	if isFlagSet SANDBOX ; then
		export ART_DEBUG_CONFIG="${JobBaseName}.cfg"
	else
		export ART_DEBUG_CONFIG="${JobName}.cfg"
	fi
	echo "Configuration dump into: '${ART_DEBUG_CONFIG}'" >> "$AbsoluteLogPath"
	"${BaseCommand[@]}" > /dev/null
	echo "================================================================================" >> "$AbsoluteLogPath"
fi

unset ART_DEBUG_CONFIG
declare LarPID
if isFlagUnset DontRun ; then
	"${Command[@]}" >> "$AbsoluteLogPath" 2>&1 &
	LarPID="$!"
fi
cat <<EOM
Job name:  '${JobName}'
Directory:  $(pwd)
Executing:  ${Command[@]}
Log file:  '${LogPath}'
Process ID: ${LarPID:-(not running)}
EOM
if isFlagSet NOBG && [[ -n "$LarPID" ]]; then
	
	# bonus: print the log
	LogPID=""
	if ! isFlagSet NoLogDump ; then
		( tailf "$AbsoluteLogPath" 2> /dev/null )&
		LogPID="$!"
	fi
	
	wait "$LarPID"
	declare -i ExitCode="$?"
	
	if [[ -n "$LogPID" ]]; then
		sleep 1
		kill -PIPE "$LogPID"
	fi
	
	echo "$(date) --- finished (exit code: ${ExitCode}) ---------------------------------"
fi

# go out of the sandbox if needed
isFlagSet SANDBOX && popd > /dev/null

cat <<EOM
To see the output:
cd ${WorkDir}
EOM

exit 0
