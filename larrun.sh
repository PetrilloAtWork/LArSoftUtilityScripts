#!/usr/bin/env bash
#
# Runs a lar command in the background and puts the output in a log file
#
# Use with --help for usage instructions.
#
# Version history:
# 1.0 (petrillo@fnal.gov)
#     first published version
# 1.1 (petrillo@fnal.gov)
#     added source file specification and printing of start command
# 1.2 (petrillo@fnal.gov)
#     improved code identification
# 1.3 (petrillo@fnal.gov)
#     in sandbox mode, all the lar arguments known to be file paths are made
#     absolute; this makes the '-s' option implementation redundant
# 1.4 (petrillo@fnal.gov)
# 1.5 (petrillo@fnal.gov)
#     find the FCL find on our own, copy it into the sandbox;
#     added output of the configuration file found
# 1.6 (petrillo@fnal.gov)
#     support for random seed restore file;
#     stub for wrapped configuration file
# 1.7 (petrillo@fnal.gov)
#     automatically modify the configuration file to include seed restoration
# 1.8 (petrillo@fnal.gov)
#     support including FCL files on the fly
# 1.9 (petrillo@fnal.gov)
#     support including FCL directives on the fly
# 1.10 (petrillo@fnal.gov)
#     change the description of the GIT packages (from the commit to describe)
# 1.11 (petrillo@fnal.gov)
#     support per-event reseeding
# 1.12 (petrillo@fnal.gov)
#     support Allinea "map" profiler
# 1.13 (petrillo@fnal.gov)
#     extract random seeds from a log file
# 1.14 (petrillo@fnal.gov)
#     added the current working directory and its job subdirectory to FHiCL
#     search path for sand box jobs
# 1.15 (petrillo@fnal.gov)
#     added an option to activate debugging output for specific modules
# 1.16 (petrillo@fnal.gov)
#     added optional configuration dump for lar1ndcode and t962code
# 1.17 (petrillo@fnal.gov)
#     ".root" parameters are now interpreted as source files
# 1.18 (petrillo@fnal.gov)
#     automatically use ROOT suppression file when running with memcheck
# 1.19 (petrillo@fnal.gov)
#     revamped configuration dump options
# 1.20 (petrillo@fnal.gov)
#     added argoneutcode and lariatcode among the optional packages
# 1.21 (petrillo@fnal.gov)
#     print art-specific environment values
# 1.22 (petrillo@fnal.gov)
#     renamed 'lbnecode' optional package name into 'dunetpc'
# 1.23 (petrillo@fnal.gov)
#     added support for Ignominious profiler (igprof)
# 1.24 (petrillo@fnal.gov)
#     added support for post-processing scripts (user has to start them though)
# 1.25 (petrillo@fnal.gov)
#     added options to valgrind memcheck command
# 1.26 (petrillo@fnal.gov)
#     added `ups active` output to the log
# 1.27 (petrillo@fnal.gov)
#     added --iprofiler option;
#     removed '-V' alias for '--version' (conflicted with valgrind short option)
# 1.28 (petrillo@fnal.gov)
#     added --samplingperiod option for iprofiler
# 1.29 (petrillo@fnal.gov)
#     added --core option
# 1.30 (petrillo@fnal.gov)
#     memcheck now supports multiple options from command line;
#     XML output disabled since it consistently turns into a pain;
#     added consistency check on profiling options
# 1.31 (petrillo@fnal.gov)
#     igprof set to track only 'lar' processes
# 1.32 (petrillo@fnal.gov)
#     added `--inject-XXX` option shortcuts
# 1.33 (petrillo@slac.stanford.edu)
#     added `--no-output` option
# 1.34 (petrillo@slac.stanford.edu)
#     added detection of file lists by file name (.list, .txt, .filelist)
# 1.35 (petrillo@slac.stanford.edu)
#     added `--padding` option
# 1.36 (petrillo@slac.stanford.edu)
#     not finding the configuration file elevated from warning to fatal error;
#     added `--force` option, which currently only ignores when configuration
#     file is not found
# 1.37 (petrillo@slac.stanford.edu)
#     aborts if the executable (usually `lar`, unless some profiling is
#     requested) is not found; `--force` option overrides this feature
# 1.38 (petrillo@slac.stanford.edu)
#     prints a list of input files in the log header; `grep ^Input: ` picks them
# 1.xx (petrillo@fnal.gov)
#     added option to follow the output of the job; currently buggy
#

SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.38"
CWD="$(pwd)"

DATETAG="$(date '+%Y%m%d')"

# this is the maximum number of logs that we allow; negative will allow any,
# but it's better to leave it to a reasonably large value to avoid infinite
# loops in case of problems or bugs
: ${MAXLOGS:="1000"}

: ${SANDBOX:=1}
: ${NOBG:=0}

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


# no more than one week
: ${DefaultProfileTime:="$((7 * 24 * 3600))s"}
# period of sampling (iprofiler): 10 ms
: ${DefaultProfileSamplingPeriod:="10ms"}

declare -i NPostProcessWriters=0

# no limits to our core...
: ${DefaultCoreSize:="unlimited"}

#
# Standard packages which will be always looked for when printing the environment
#
declare -a StandardPackages
StandardPackages=(
	larcoreobj lardataobj # larsimobj
	larcorealg lardataalg # larsimobj
	larcore lardata larevt larsim larreco larana
	lareventdisplay larpandoracontent larpandora larwirecell larsoft
	larexamples
)
declare -a OptionalPackages
OptionalPackages=(
	uboonecode dunetpc sbndcode t962code argoneutcode lariatcode icaruscode
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
	--followlog , -f
	    after starting, prints the output log on the screen; <Ctrl>+<C> will
	    stop following the log, but the job will continue to the end
	--jobname=JOBNAME
	    the label for this job (the output directory and log file are named after
	    it)
	--padding=N [${PaddingDefault}]
	    use this many digits (at least) for the job counter
	--printenv , -E
	    print on the screen the LARSoft UPS packages set up, and exit
	--norun , -N
	    does not actually run (use to debug ${SCRIPTNAME})
	--force
	    ignores most errors (e.g. can't find CONFIGFILE)
	 (configuration options)
	--nowrap
	    do not use a FCL wrapper; some of the following features will not be
	    available in that case
	--seedfromevents[=RandomNumberSaverInstance]
	    restores random seeds, event-based, from the product created by a
	    RandomNumberSaver module instance in the input file; the name of the
	    instance can be specified as parameter, and it defaults to "rns"
	--seedfromfile=FILENAME[@ALIAS]
	    use FILENAME as the file to restore the random seeds, optionally changing
	    its name/location into ALIAS; currently the FCL file must have the ALIAS
	    path already in, for this to work
	--seedfromlog=LOGFILE
	    extract seeds from LOGFILE; this option is currently very stupid: it
	    ignores the generator label, it assumes that the module with the random
	    generator is producer, and that it has a "Seed" configuration option;
	    if any of these assumptions fail, the option will silently not work
	--debugmodules[=ModuleLabel,ModuleLabel,...]
	    sets the message facility to enable debugging output for the specified
	    module labels, or for all of them if none is specified; this overrides
	    the module labels selection from the configuration file
	--precfg=FILE
	--include=FILE
	    includes FILE in the FCL: the first option includes FILE before the main
	    FCL file, the second after it; multiple files can be specified by using
	    these options multiple times
	--inject=FCLdirective
	    appends the specified FCL line at the end of the FCL file (also after the
	    inclusion of the optional configuration by --include option); multiple
	    directives can be specified by using this options multiple times;
	    do not abuse it: it makes harder to rerun jobs!
	--inject-service=ServiceName:FCLdirective
	--inject-source=FCLdirective
	--inject-producer=ModuleLabel.FCLdirective
	--inject-filter=ModuleLabel.FCLdirective
	--inject-analyzer=ModuleLabel.FCLdirective
	--inject-output=ModuleLabel.FCLdirective
	    adds the specified configuration line into the configuration of the
	    specified service or module (see \`--inject\` for details).
	    Example: \`--inject-producer="generator.fluxType: parallel" is equivalent
	    to \`--inject="physics.producers.generator.fluxType: parallel"\`.
	--processname=NewProcessName
	    overrides the process name specified in the configuration
	--dropinput=Branch
	--keepinput=Branch
	    overrides the source input commands demanding the preservation or the
	    elimination of a set of branches from the input tree; format of Branch is
	    \`<data product class>_<module label>_<data product instance>_<process>\`
	    and any element can be replaced by a wildcard matching everything, \`*\`;
	    order matters, and art \`RootInput\` module will apply its rules to
	    determine the actual actions
	--dropprocess=ProcessName
	--keepprocess=ProcessName
	    overrides the source input commands demanding the preservation or the
	    elimination of all data products produced by the process with the
	    specified name; order matters, and art \`RootInput\` module will apply its
	    rules to determine the actual actions
	--no-output
	    does not run any output module (passed directly to \`art\`)
	
	 (profiling options)
	--core[=LIMIT]
	    instruct the operating system to dump core memory on abnormal termination;
	    the optional limit sets the maximum size of the core file, in kilobyte.
	    If the limit is not specified, it defaults to ${DefaultCoreSize}.
	    Note that once the limit is set, it's not possible to increase it.
	    Maximum value on this shell is ${MaximumCoreSize:-not enforced yet}.
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
	--allinea[=ProfileOptionString], -A
	    equivalent to --prepend=map or --profile=map: uses the Allines profiler;
	    the optional ProfileOptionString string will be added in a way equivalent
	    to --prependopts=ProfileOptionString
	--valgrind[=ProfileOptionString], -V
	    equivalent to --prepend=valgrind or --profile=valgrind: uses valgrind
	    analyser; the optional ProfileOptionString string will be added in
	    a way equivalent to --prependopts=ProfileOptionString
	--massif[=ProfileOptionString]
	    uses valgrind's massif tool for memory allocation profiling;
	    equivalent to --valgrind='--tool=massif'
	--igprof[=ProfileOptionString]
	    uses igprof performance profiler
	--igprof_mem[=ProfileOptionString]
	    uses igprof memory profiler
	--iprofiler[=ProfileOptionString]
	    equivalent to --prepend=iprofiler or --profile=iprofiler: uses Apple
	    iprofiler running "timeprofiler" tool; the optional ProfileOptionString
	    string will be added in a way equivalent to;
	    NOTE: OSX might ask interactively for administrator authentication
	    --prependopts=ProfileOptionString
	--profilefor=TIME [${DefaultProfileTime}]
	    time while profiling (e.g. 10s); supported only by iprofiler
	--samplingperiod=PERIOD [${DefaultProfileSamplingPeriod}]
	    sampling period for iprofiler (e.g. '10ms', '1s', '100us')
	--stack
	    enables stack profiling if the tool supports it (if not, will complain)
	--mmap
	    enables more general heap profiling (mmap) if the tool supports it (if
	    not, will complain)
	
	(other options)
	--version
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
	[[ "$Code" != 0 ]] && FATAL "$Code" "$@"
} # LASTFATAL()

function isDebugging() {
	isFlagSet DEBUG
}

function DBG() {
	isDebugging && STDERR "${DebugColor}DBG| $*${ResetColor}"
} # DBG()

function DBGN() {
	# DBGN DebugLevel Debug Message
	# Debug message is printed only if current DEBUG level is bigger or equal to
	# DebugLevel.
	local -i DebugLevel="$1"
	shift
	[[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge "$DebugLevel" ]] && DBG "$*"
} # DBGN()

function DUMPVAR() {
	local VarName="$1"
	DBG "'${VarName}'='${!VarName}'"
} # DUMPVAR()

function DUMPVARS() {
	local VarName
	for VarName in "$@" ; do
		DUMPVAR "$VarName"
	done
} # DUMPVARS()

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


function SplitBySep() {
	# Usage:  SplitBySep  Separators Arg [Arg ...]
	# 
	# Splits the arguments at the specified separators and prints them one per line
	#
	local NewIFS="$1"
	shift
	local Args="$*"
	
	local OldIFS="$IFS"
	IFS="$NewIFS"
	local -a Words
	while read -a Words ; do
		local Word
		for Word in "${Words[@]}" ; do
			echo "$Word"
		done
	done <<< "$Args"
	
	IFS="$OldIFS"
} # SplitBySep()


function ListBySep() {
	# Usage:  ListBySep  Separator [Arg Arg ...]
	# 
	# Merges all the arguments in a string, inserting a Separator between them
	#
	local Separator="$1"
	shift
	local -a Args=( "$@" )
	local iArg
	for (( iArg = 0 ; iArg < ${#Args[@]} ; ++iArg )); do
		[[ $iArg == 0 ]] || echo -n "$Separator"
		echo -n "${Args[iArg]}"
	done
	echo
} # SplitBySep()


function SplitByComma() {
	local Words="$*"
	SplitBySep ", " "$Words"
} # SplitByComma()


function ListByComma() { ListBySep ", " "$@" ; }


function isRunning() {
	# returns whether the specified process is running
	local PID="$1"
	[[ -r "/proc/${PID}" ]]
} # isRunning()

function isAbsolute() {
	local Path="$1"
	[[ "${Path:0:1}" == '/' ]]
} # isAbsolute()


function MakeAbsolute() {
	local Path="$1"
	local Cwd="${2:-"$(pwd)"}"
	[[ -n "$Path" ]] || return 0
	if isAbsolute "$Path" ; then
		echo "$Path"
	elif [[ "$Path" == "." ]]; then
		echo "${Cwd:-"."}"
	else
		echo "${Cwd:+${Cwd}/}${Path}"
	fi
	return 0
} # MakeAbsolute()


function MakePathListAbsolute() {
	# MakePathListAbsolute PathList [BaseDir] [Separator]
	local PathList="$1"
	local BaseDir="${2:-"$(pwd)"}"
	local Separator="${3:-":"}"
	
	local OldIFS="$IFS"
	local -i iPath=0
	IFS="$Separator"
	local Path NewPathsList
	# an additional separator trailing the input is needed to parse the last element
	while read -d "${Separator}" Path ; do
		local NewPath="$(MakeAbsolute "${Path#./}" "$BaseDir")"
		[[ $iPath -gt 0 ]] && NewPathsList+="$Separator"
		NewPathsList+="$NewPath"
		let ++iPath
	done <<< "${PathList}${Separator}" 
	IFS="$OldIFS"
	echo "$NewPathsList"
} # MakePathListAbsolute()


function FindNextFile() {
	# Prints the next available log file with the specified base name and suffix
	local BasePath="$1"
	local Suffix="$2"
	local -i IndexPadding="${3:-${PaddingDefault}}"
	
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
	local -i IndexPadding="${2:-${PaddingDefault}}"
	
	FindNextFile "logs/${ConfigBaseName}/${DATETAG}" '.log' "$IndexPadding" $MAXLOGS
} # FindNextLogFile()


function LowerCase() { local VarName="$1" ; tr '[:upper:]' '[:lower:]' <<< "${!VarName}" ; }


function SetCoreSize() {
  
  local -i NewSize="$1"
  
  ulimit -c "$NewSize" >& /dev/null
  LASTFATAL "Can't increase the core size from ${MaximumCoreSize} to ${NewSize} \"blocks\"."
  
} # SetCoreSize()


function PathList() {
	# Prints the paths in the specified arguments, one per line
	# (the variable is a colon-separated list of paths)
	local Paths
	for Paths in "$@" ; do
		tr ':' '\n' <<< "$Paths"
		echo
	done
} # PathList()

function PathListVar() {
	# Prints the paths in the specified variable, one per line
	# (the variable is a colon-separated list of paths)
	local VarName="$1"
	PathList "${!VarName}"	
} # PathListVar()


function AddPostProcessWriter() {
	local -i NWriter="$((NPostProcessWriters++))"
	local WriterName="PostProcessWriter${NWriter}"
	DBGN 2 "Adding post-process script part #${NWriter}: $@"
	eval "${WriterName}=( "$@" )"
} # AddPostProcessWriter()

function WritePostProcessScript() {
	local ScriptPath="$1"
	local ScriptName="$(basename "$ScriptPath")"
	local ScriptDir="$(dirname "$ScriptPath")"
	[[ "$ScriptDir" == '.' ]] && ScriptDir="$(pwd)"
	
	DBGN 1 "Post process script: ${NPostProcessWriters} parts"
	[[ $NPostProcessWriters -gt 0 ]] || return 1
	
	local -i NWriter
	cat <<-EOH > "$ScriptPath"
	#!/usr/bin/env bash
	#
	# Post-processing script '${ScriptName}'
	#
	# Run this script manually after successful completion of the job.
	#
	
	cd "\$(dirname "\$0")"
	
	EOH
	for (( NWriter = 0 ; NWriter < $NPostProcessWriters ; ++NWriter )); do
		local WriterName="PostProcessWriter${NWriter}"
		DBGN 2 "  writing part #${NWriter}: $(eval "echo \${${WriterName}[@]}")"
		{
			cat <<-EOM >> "$ScriptPath"
			###
			### part $((NWriter+1))
			###
			
			EOM
			eval "\${${WriterName}[@]}"
		} >> "$ScriptPath"
		LASTFATAL "Error writing post-processing script #${NWriter} with command: $(eval "echo \${${WriterName}[@]}")"
	done
	
	cat <<-EOT >> "$ScriptPath"
	
	###
	### clean up
	###
	[[ "\$(basename "\$0")" == '${ScriptName}' ]] && rm '${ScriptName}'
	EOT
	chmod a+x "$ScriptPath"
	DBG "Post-process script '${ScriptPath}' written."
	return 0
} # WritePostProcessScript()


function isSourceFileList() {
  local Path="$1"
  [[ ! "$Path" =~ .root$ ]]
} # isSourceFileList()


function IgProfReport() {
	local Mode="$1"
	shift
	local DataFile="$1"
	local ReportFile="$2"
	DBGN 2 "IgProfReport in ${Mode} mode"
	case "$Mode" in
		( 'performance' )
			cat <<-EOS
			#
			# Ignominious profiler report: CPU usage
			#
			echo 'Producing CPU time report...'
			igprof-analyse -d -v -g "$DataFile" >& "$ReportFile"
			EOS
			;;
		( 'memory' )
			cat <<-EOS
			#
			# Ignominious profiler report: memory usage
			#
			# TODO there is a more useful report than MEM_TOTAL...
			echo 'Producing memory usage report...'
			igprof-analyse -d -h -v -g -r MEM_TOTAL "$DataFile" > "$ReportFile"
			EOS
			;;
		( * )
			DBGN 2 "No post-processing for mode '${Mode}'"
			;;
	esac
} # IgProfReport


function CompressFile_gzip() {
	local File="$1"
	echo "gzipi -v '${File}'"
}

function CompressFile_bzip2() {
	local File="$1"
	echo "bzip2 -v '${File}'"
}


function CompressFiles() {
	local -a Files=( "$@" )

	local File
	for File in "${Files[@]}" ; do
		local Format
		local Source="$File"
		case "$File" in
			( *.gz )
				Source="${File%.gz}"
				Format='gzip'
				;;
			( *.bz2 )
				Source="${File%.bz2}"
				Format='bzip2'
				;;
			( * )
				Format=''
				;;
		esac
		[[ -n "$Format" ]] || continue
		
		"CompressFile_${Format}" "$Source"
	done
} # CompressFiles()


function SetProfiler() {
	local NewProfiler="$1"
	if [[ -z "$Profiler" ]]; then
		Profiler="$NewProfiler"
	else
		[[ "$Profiler" == "$NewProfiler" ]] || FATAL 1 "Different profilers specified: '${Profiler}' first, then '${NewProfiler}'."
	fi
} # SetProfiler()


function SetupProfiler() {
	local Profiler="$1"
	
	case "$Profiler" in
		( 'fast' )
			PrependExecutable="profrun"
			PrependExecutableParameters=( "${ProfilerToolParams[@]}" )
			;;
		( 'allinea' )
			OutputFile="${JobName}-allinea.map"
			PrependExecutable="map"
			# specify only one MPI process
			PrependExecutableParameters=(
				'-profile'
				'-output' "./${OutputFile}"
				'-log' "./${OutputFile%.map}.log.xml"
				'-n' '1' '-nompi'
				"${ProfilerToolParams[@]}"
			)
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
					# giving up XML right now, since it is a pain to parse and no good tools exist
					# valgrind (at least up to 3.12) produces XML or plain text, not both
					#	"--xml=yes" "--xml-file=${MachineOutputFile}" # generate XML output and write it file
						"--log-file=${LogOutputFile}" # send the plain text output to a second file
						'--child-silent-after-fork=yes' # do not trace child (fork()ed) processes
						'--track-origins=yes'
						'--num-callers=50' # stack trace depth (50 should be enough for lar jobs)
						'-q' # reduce the plain text output
						'--leak-check=full'
						)
					local ROOTSupp="${ROOTSYS}/etc/valgrind-root.supp"
					if [[ -r "$ROOTSupp" ]]; then
						PrependExecutableParameters=( "${PrependExecutableParameters[@]}" "--suppressions=${ROOTSupp}" )
					fi
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
					AddPostProcessWriter CompressFiles "${OutputFile}.bz2"
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
			
			: ${ProfilerTool:='performance'}
			case $(LowerCase ProfilerTool) in
				( 'performance' | 'memory' | 'energy' | 'empty-memory' )
					ToolOption="--${ProfilerTool}-profiler"
					
					# these are the files which will be created...
					MachineOutputFile="${JobName}-${ProfilerTool}.gz"
					ReportFile="${JobName}-${ProfilerTool}-report.txt"
					
					PrependExecutableParameters=( "${ProfilerToolParams[@]}"
						"$ToolOption"
						"--target" "lar" # profile only processes that contain "lar" in their name
						"--compress" "--output" "$MachineOutputFile" # profiling output file
						"--debug" # a bit more output
						)
					AddPostProcessWriter 'IgProfReport' "$ProfilerTool" "$MachineOutputFile" "$ReportFile"
					;;
				( * ) FATAL 1 "Unsupported profiling tool for ${Profiler}: '${ProfilerTool}'" ;;
			esac
			;;
		( 'iprofiler' )
			PrependExecutable='iprofiler'
			
			: ${ProfilerTool:='iprofiler'}
			: ${ProfileTime:=${DefaultProfileTime}}
			: ${ProfileSamplingPeriod:=${DefaultProfileSamplingPeriod}}
			local BaseOutputFile="${JobName}-${ProfilerTool}"
			PrependExecutableParameters=( "${ProfilerToolParams[@]}"
				"-${ProfilerTool}"
				-T "$ProfileTime" 
				-I "$ProfileSamplingPeriod"
				-o "$BaseOutputFile"
				)
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
	local UPSpackage='' Version='' Qualifiers='' Repository=''
	
	if [[ -n "${!SetupVarName}" ]]; then
		# get information about the UPS package
		read UPSpackage Version Qualifiers Repository <<< "$(PrintUPSsetup "$Package" Package Version Qualifiers Repository)"
		
		[[ "$Package" != "$UPSpackage" ]] && echo -n "[MISMATCH: ${Package}] "
		echo -n "${UPSpackage} ${Version} (${Qualifiers:-"no quals"})"
	else
		# maybe it's set up from `mrbsetenv`? look for other typical UPS variables
		local VarNameSuffix
		for VarNameSuffix in 'LIB' 'DIR' ; do
			local VarName="${PACKAGE}_${VarNameSuffix}"
			[[ -z "${!VarName}" ]] && continue
			Repository="$MRB_INSTALL"
			break
		done
		[[ -z "$Repository" ]] && return 1
		Qualifiers="$MRB_QUALS"
		local UPSproductDeps="${MRB_SOURCE}/${Package}/ups/product_deps"
		[[ -r "$UPSproductDeps" ]] && Version="$(read Dummy PackageName Version DefQual Comments < <(grep -E '^[[:blank:]]*parent[[:blank:]]+' "$UPSproductDeps") && echo "$Version")" 
		echo -n "${Package} ${Version} (${Qualifiers:-"no quals"})"
	fi
	
	# if that is the same as the local one, 
	if [[ "$MRB_INSTALL" == "$Repository" ]]; then
		echo -n " from local area"
		if [[ -d "${MRB_SOURCE}/${Package}" ]]; then
			pushd "${MRB_SOURCE}/${Package}" >& /dev/null
			local GITdescribe
			GITdescribe="$(git describe)"
			if [[ $? == 0 ]]; then
				echo -n " => GIT ${GITdescribe}"
			else
				local GITCommitHash="$(git log --pretty='%H %ci' -n 1)"
				echo -n " => GIT commit ${GITCommitHash}"
			fi
			popd >& /dev/null
			
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
	# Prints a list of the packages currently configured:
	# - standard packages, from LArSoft (prints if missing)
	# - optional packages, typically experiment code
	# - any other package installed in the local MRB working area
	# It returns the number of standard packages not configured.
	
	local -i nStandardMissing=0
	
	# first the default packages:
	local Package
	# - standard:
	for Package in "${StandardPackages[@]}" ; do
		PrintLocalPackage "$Package"
		if [[ $? != 0 ]]; then
			echo "${Package}: not configured!!!"
			let ++nStandardMissing
		fi
	done
	# - optional:
	local -a MissingOptional
	for Package in "${OptionalPackages[@]}" ; do
		PrintLocalPackage "$Package"
		[[ $? != 0 ]] && MissingOptional=( "${MissingOptional[@]}" "$Package" )
	done
	if [[ ${#MissingOptional[@]} -gt 0 ]]; then
		echo "${#MissingOptional[@]} optional packages missing: ${MissingOptional[@]}"
	fi
	
	# other local packages
	local UPSpackagePath
	if [[ -n "$MRB_INSTALL" ]]; then
		for UPSpackagePath in "${MRB_INSTALL}/"* ; do
			[[ -d "$UPSpackagePath" ]] || continue
			
			Package="$(basename "$UPSpackagePath")"
			
			# if standard or optional, we have printed it already
			IsInList "$Package" "${StandardPackages[@]}" "${OptionalPackages[@]}" && continue
			
			PrintLocalPackage "$Package"
			
		done
		echo "Local area: '${MRB_INSTALL}'"
	else
		echo "[no MRB local products]"
	fi
	return $nStandardMissing
} # PrintPackageVersions()


function FindFCLfile() {
	# Prints the full path of the FCL file which would be selected
	# (or so we think).
	# Returns 0 if the file is actually found.
	local FileName="$1"
	if [[ -r "$FileName" ]]; then
		echo "$FileName"
		return 0
	fi
	tr ':' '\n' <<< "$FHICL_FILE_PATH" | while read CandidatePath ; do
		CandidateFile="${CandidatePath:+${CandidatePath}/}${FileName}"
		[[ -r "$CandidateFile" ]] || continue
		echo "$CandidateFile"
		exit 42
	done
	[[ "${PIPE_STATUS[1]}" == 42 ]] && return 0
	return 1
} # FindFCLfile()


function ImportFileInWorkArea() {
	#
	# ImportFileInWorkArea ORIG WORKAREA [DEST]
	#
	# Copies ORIG into DEST (file or directory specification).
	# Prints the name of DEST relative to WORKAREA.
	# If WORKAREA is not specified, it's assumed to be the current directory.
	# If DEST is not specified, it's assumed to be an entity with the same name
	# as ORIG, in the WORKAREA. If it is specified as a relative path, it is
	# created under that path inside the WORKAREA
	#
	local OriginalPath="$1"
	local WorkArea="${2:-'.'}"
	local DestPath="$3"
	
	local BaseName="$(basename "$OriginalPath")"
	
	if [[ -z "$DestPath" ]]|| ! isAbsolute "$DestPath" ; then
		DestPath="${WorkArea%/}/${DestPath}"
	fi
	
	# add the name of the destination file to the destination path,
	# unless the destination path does not exist yet or is not a directory
	# (and unless the original path is actually a known directory)
	[[ -d "$DestPath" ]] && [[ -e "$OriginalPath" ]] && [[ ! -d "$OriginalPath" ]] && DestPath="${DestPath%/}/${BaseName}"
	
	if [[ ! -r "$OriginalPath" ]]; then
		echo "$OriginalPath"
		return 1
	fi
	
	if [[ -d "$OriginalPath" ]] || [[ ! -f "$DestPath" ]] || ! cmp -s "$OriginalPath" "$DestPath" ; then
		DBG "Copying '${OriginalPath}' into '${DestPath}'"
		mkdir -p "$(dirname "$DestPath")"
		cp -aH "$OriginalPath" "$DestPath"
	fi
	# if the destination is plainly in the working area,
	# print only the relative path to it; otherwise print the absolute path
	if [[ "${DestPath#${WorkArea}}" != "$DestPath" ]]; then
		local RelPath="${DestPath#${WorkArea}}"
		[[ "${RelPath:0:1}" == '/' ]] && RelPath="${RelPath:1}"
		echo "$RelPath"
		DBG "  (relative path to '${WorkArea}': '${RelPath}')"
	else
		MakeAbsolute "$DestPath"
	fi
	return 0
} # ImportFileInWorkArea()


function ImportFCLfileInWorkArea() {
	local OriginalPath="$1"
	local DestPath="$2"
	
	local ResolvedPath="$(FindFCLfile "$OriginalPath")"
	
	ImportFileInWorkArea "${ResolvedPath:-"$OriginalPath"}" "$DestPath"
} # ImportFCLfileInWorkArea()


function ScheduleInputCommands() {
  # converts drop/keep options into input commands
  
  [[ "${#InputCommands[@]}" == 0 ]] && return
  
  # start the command with removing or keeping everything
  local InputCommandLine
  if [[ "${InputCommands[0]}" =~ ^[[:blank:]]*keep ]]; then
    InputCommandLine='"drop *"'
  elif [[ "${InputCommands[0]}" =~ ^[[:blank:]]*drop ]]; then
    InputCommandLine='"keep *"'
  else
    FATAL 1 "Internal error: malformed input command '${InputCommands[0]}'"
  fi
  
  local InputCommand
  for InputCommand in "${InputCommands[@]}" ; do
    InputCommandLine+=", \"${InputCommand}\""
  done
  
  AppendConfigLines+=( "source.inputCommands: [ ${InputCommandLine[@]} ]" )
  
} # ScheduleInputCommands()


function ConfigurationReseeder() {
	#
	# The purpose of this function is to add a sequence of statements at the end
	# of a configuration file, which allows to rerun a job using the same
	# random sequences as the original one.
	#
	#
	local ConfigurationFile="$1"
	local OriginalOutputFile="$2"
	local RNSinstanceName="${3:-rns}"
	local NewProcessName="$4"
	
	local res=0
	
	#
	# determine the process name of the original job;
	# it should be in the configuration
	#
	
	local OriginalProcessName
	# look for lines starting with "process_name", use only the last one,
	# take everything after ':', remove spaces and quotes
	OriginalProcessName="$(grep -e '^[[:blank:]]*process_name[[:blank:]]*:[[:blank:]]*' "$ConfigurationFile" | tail -n 1 | sed -e 's/.*://' | tr -d "\"'[[:blank:]]")"
	res=$?
	[[ $res != 0 ]] && return $res
	
	DBG "Detected process name: '${OriginalProcessName}'"
	
	#
	# Select a new process name
	#
	: ${NewProcessName:="${OriginalProcessName}Rerun"}
	DBG "New process name: '${NewProcessName}'"
	
	#
	# detect the random state branch name
	#
	local StateProductLabel="art::RNGsnapshots"
	
	#
	# print the additional lines needed
	#
	cat <<-EOI
	
	###
	### reseeding from the input file itself
	###
	# rename the process from '${OriginalProcessName}' to '${NewProcessName}'
	process_name: "${NewProcessName}"
	# drop all the existing output branches, but keep the random state one
	source.inputCommands: [ "keep *", "drop *_*_*_${OriginalProcessName}", "keep *_${RNSinstanceName}__${OriginalProcessName}" ]
	# use the existing states for seeding
	services.RandomNumberGenerator.restoreStateLabel: "${RNSinstanceName}"
	EOI
	
	return 0
} # ConfigurationReseeder()


function RandomSeedExtractor() {
	# Extracts random generator seeds from an existing log file.
	# Outputs a set of typical FHICL instructions to use them.
	# 
	# The output assumes that the module has a "Seed" configuration parameter.
	#
	local LogFile="$1"
	[[ -r "$LogFile" ]] || return 2
	local Line Pulp InstanceName EngineLabel RandomSeed
	# using grep to skim the log file is faster than doing it with this loop
	grep 'engine' "$LogFile" | while read Line ; do
		Pulp="$(sed -e 's/.*Instantiated .* engine "\([[:alpha:]:_]*\)" with seed \([[:digit:]]\+\)\..*/\1:\2/g' <<< "$Line")"
		[[ "$Pulp" == "$Line" ]] && continue
		IFS=: read InstanceName EngineLabel RandomSeed <<< "$Pulp"
		echo "physics.producers.${InstanceName}.Seed: $RandomSeed"
	done
	return 0
} # RandomSeedExtractor()


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
} # InterruptHandler()


function TailInterruptHandler() {
	echo
	
	[[ -n "$TailPID" ]] && kill -INT "$TailPID"
	
} # TailInterruptHandler()


################################################################################
declare JobBaseName

declare -i DoHelp=0 DoVersion=0 OnlyPrintEnvironment=0 FollowLog=0 NoLogDump=0 UseConfigWrapper=1 Force=0

declare -i NoMoreOptions=0
declare ConfigFile
declare NewProcessName
declare -a Params
declare -i nParams=0
declare -a SourceFiles
declare -a PrependExecutable
declare -a PrependExecutableParameters
declare -i PrependExecutableNParameters
declare -a PrependConfigFiles
declare -a AppendConfigFiles
declare -a AppendConfigLines
declare -a InputCommands
declare -i NoOutput=0
declare -a DebugModules
declare -i OneStringCommand=0
declare -i PaddingDefault=2
declare DumpConfigMode="Yes"
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' )     DoHelp=1  ;;
			( '--version' )                DoVersion=1  ;;
			( '--debug' )                  DEBUG=1  ;;
			( '--debug='* )                DEBUG="${Param#--*=}" ;;
			( '-d' )                       let ++iParam ; DEBUG="${!iParam}" ;;
			( '--printenv' | '-E' )        OnlyPrintEnvironment=1  ;;
			( '--norun' | '-N' )           DontRun=1  ;;
			( '--force' )                  Force=1  ;;
			
			### behaviour options
			( '--foreground' | '--fg' )    NOBG=1    ;;
			( '--background' | '--bg' )    NOBG=0    ;;
			( '--inline' | '--nosandbox' ) SANDBOX=0 ;;
			( '--sandbox' )                SANDBOX=1 ;;
			( '--core' )                   CoreSize="$DefaultCoreSize" ;;
			( '--core='* )                 CoreSize="${Param#--*=}" ;;
			( '--follow' | '-f' )          FollowLog=1 ;;
			( '--nologdump' )              NoLogDump=1 ;;
			( '--noconfigdump' )           DumpConfigMode="No" ;;
			( '--onlyconfigdump' )         DumpConfigMode="Only" ;;
			( '--config='* | '--cfg='* )   ConfigFile="${Param#--*=}" ;;
			( '-c' )                       let ++iParam ; ConfigFile="${!iParam}" ;;
		#	( '--source='* | '--src='* )   SourceFiles=( "${SourceFiles[@]}" "${Param#--*=}" ) ;;
		#	( '-s' )                       let ++iParam ; SourceFiles=( "${SourceFiles[@]}" "${!iParam}" ) ;;
			( '--jobname='* )              JobBaseName="${Param#--*=}" ;;
			( '--padding='* )              PaddingDefault="${Param#--*=}" ;;
			( '--nowrap' )                 UseConfigWrapper=0 ;;
			( '--precfg='* )               PrependConfigFiles=( "${PrependConfigFiles[@]}" "${Param#--*=}" ) ;;
			( '--include='* )              AppendConfigFiles=( "${AppendConfigFiles[@]}" "${Param#--*=}" ) ;;
			( '--inject='* )               AppendConfigLines+=( "${Param#--*=}" ) ;;
			( '--inject-'*=* )             AppendConfigLines+=( ">${Param#--inject-}" ) ;;
			( '--seedfromevents' )         SeedFromEvents="rns" ;;
			( '--seedfromevents='* )       SeedFromEvents="${Param#--*=}" ;;
			( '--seedfromfile='* )
				SavedSeed="${Param#--*=}"
				if [[ "${SavedSeed/@}" != "$SavedSeed" ]]; then
					RestoreSeed="${SavedSeed#*@}"
					SavedSeed="${SavedSeed%@${RestoreSeed}}"
				else
					RestoreSeed="$(basename "$SavedSeed")"
				fi
				;;
			( '--seedfromlog='* )          SeedLogFile="${Param#--*=}" ;;
			( '--debugmodules' )           DebugModules=( "*" ) ;;
			( '--debugmodules='* )         DebugModules=( $(SplitByComma "${Param#--*=}") ) ;;
			( '--processname='* )          NewProcessName="${Param#--*=}" ;;
			( '--dropinput='* )            InputCommands+=( "drop ${Param#--*=}" ) ;;
			( '--dropprocess='* )          InputCommands+=( "drop *_*_*_${Param#--*=}" ) ;;
			( '--keepinput='* )            InputCommands+=( "keep ${Param#--*=}" ) ;;
			( '--keepprocess='* )          InputCommands+=( "keep *_*_*_${Param#--*=}" ) ;;
			( '--no-output' )              NoOutput=1 ;;
			
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
				SetProfiler "${Param#--*=}"
				;;
			( '--env:'*=* )
				CommandEnvironment=( "${CommandEnvironment[@]}" "${Param#--env:}" )
				;;
			( '--stack' ) DoStackProfiling=1 ;;
			( '--mmap' ) DoMMapProfiling=1 ;;
			
			#
			# FAST profiler
			( '--fast='* )
				SetProfiler "fast"
				ProfilerToolParams=( "${Param#--*=}" )
				;;
			( '--fast' | '-F' )
				SetProfiler "fast"
				;;
			#
			# Allinea profiler (http://www.allinea.com/products/map)
			( '--allinea='* )
				SetProfiler "allinea"
				ProfilerToolParams=( "${Param#--*=}" )
				;;
			( '--allinea' | '-A' )
				SetProfiler "allinea"
				;;
			#
			# Open|SpeedShop profiler
			( '--oss='* )
				SetProfiler "Open|SpeedShop"
				ProfilerTool="oss${Param#--*=}"
				;;
			( '--oss' )
				SetProfiler "Open|SpeedShop"
				;;
			#
			# GPerfTools
			( '--gpt' | '--gperf' | '--gperftool' | '--gperftools' )
				SetProfiler "GPerfTools"
				;;
			#
			# valgrind
			( '--valgrind='* )
				SetProfiler "valgrind"
				ProfilerToolParams=( "${Param#--*=}" )
				;;
			( '--valgrind' | '-V' )
				SetProfiler "valgrind"
				;;
			(    '--massif'   | '--massif='*         \
				| '--dhat'     | '--dhat='*           \
				| '--memcheck' | '--memcheck='*       \
				| '--callgrind' | '--callgrind='*     \
				| '--cachegrind' | '--cachegrind='*   \
			)
				SetProfiler "valgrind"
				ProfilerTool="${Param%%=*}"
				ProfilerTool="${ProfilerTool#--}"
				[[ "$Param" =~ = ]] && ProfilerToolParams+=( "${Param#--${ProfilerTool}=}" )
				;;
			
			# 
			# Ignominous Profiler
			( '--igprof' | '-I' )
				SetProfiler "igprof"
				ProfilerTool="performance"
				;;
			( '--igprof='* )
				SetProfiler "igprof"
				ProfilerTool="performance"
				ProfilerToolParams=( "${Param#--*=}" )
				;;
			( '--igprof_mem' | '--igprof_mem='* )
				SetProfiler "igprof"
				ProfilerTool="memory"
				ProfilerToolParams=( "${Param#--*=}" )
				[[ "$Param" =~ = ]] && ProfilerToolParams=( "${Param#--*=}" )
				;;
			
			#
			# Apple iprofiler
			( '--iprofiler' )
				SetProfiler "iprofiler"
				ProfilerTool="timeprofiler"
				;;
			( '--iprofiler='* )
				SetProfiler "iprofiler"
				
				: ${ProfilerTool:="timeprofiler"}
				ProfilerToolParams=( "${Param#--*=}" )
				;;
			( '--profilefor='* )
				ProfileTime="${Param#--*=}"
				;;
			( '--samplingperiod='* )
				ProfileSamplingPeriod="${Param#--*=}"
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

# maximum (current) core size;
# note that 0 /might/ mean it's impossible to change it
declare MaximumCoreSize=$(ulimit -c)
[[ $MaximumCoreSize == 0 ]] && MaximumCoreSize=''


declare -i ExitCode NeedHelp=1
if isFlagSet OnlyPrintEnvironment ; then
	NeedHelp=0
	PrintPackageVersions
	{ [[ -z "$ExitCode" ]] || [[ "$ExitCode" == 0 ]] ; } && ExitCode="$?"
fi

if isFlagSet DoVersion ; then
	NeedHelp=0
	echo "${SCRIPTNAME} version ${SCRIPTVERSION:-"unknown"}"
	: ${ExitCode:=0}
fi

if isFlagSet DoHelp || ( isFlagSet NeedHelp && [[ -z "$ConfigFile" ]] ); then
	help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	{ [[ -z "$ExitCode" ]] || [[ "$ExitCode" == 0 ]] ; } && ExitCode="$?"
fi

[[ -n "$ExitCode" ]] && exit $ExitCode


[[ -n "$CoreSize" ]] && SetCoreSize "$CoreSize"


# steal lar parameters and identify path parameters
declare -ai PathParams
declare -a LArParams
for (( iParam = 0; iParam < $nParams ; ++iParam )); do
	Param="${Params[iParam]}"
	case "$Param" in
		( '-s' | '-S' | '-T' | '-o' \
			| '--source' | '--source-list' | '--TFileName' | '--output' \
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
		( *.root | *.txt | *.list | *.filelist )
			SourceFiles=( "${SourceFiles[@]}" "$Param" )
			;;
		( * )
			LArParams+=( "$Param" )
			;;
	esac
done

declare ConfigName="$(basename "${ConfigFile%.fcl}")"
: ${JobBaseName:="$ConfigName"}

DBGN 2 "FHICL_FILE_PATH=${FHICL_FILE_PATH}"
declare UserConfigPath="$ConfigFile"
declare FullConfigPath="$(FindFCLfile "$UserConfigPath")"
if [[ -z "$FullConfigPath" ]]; then
	if isFlagSet Force ; then
		WARN "Could not find the configuration file '${UserConfigPath}'. Trying anyway."
	else
		FATAL 2 "Could not find the configuration file '${UserConfigPath}' (use \`--force\` to attempt running anyway)"
	fi
fi

declare LogPath
LogPath="$(FindNextLogFile "$JobBaseName")"
LASTFATAL "Failed to find a suitable log file name for ${JobBaseName}!"
declare JobTag="$(basename "${LogPath%.log}")"

declare JobName="${JobBaseName}-${JobTag}"

# make sure we can freely overwrite the log files:
set +o noclobber

#
# create the directory for the log file
#
declare LogDir="$(dirname "$LogPath")"
mkdir -p "$LogDir"
[[ -d "$LogDir" ]] || FATAL 3 "Can't create the log directory '${LogDir}'."
if [[ -e "$LogPath" ]]; then
	if [[ -h "$LogPath" ]]; then
		if [[ -r "$LogPath" ]]; then
			FATAL 1 "Log file '${LogPath}' already exists (as a link)."
		else
			FATAL 1 "Log file '${LogPath}' already exists (as a broken link)."
		fi
	else
		FATAL 1 "Log file '${LogPath}' already exists."
	fi
fi
touch "$LogPath" || FATAL 2 "Can't create the log file '${LogPath}'."

declare AbsoluteLogPath="$(MakeAbsolute "$LogPath")"

#
# process lar options
#
# OutputParams tracks lar arguments representing output files
declare -a OutputParams

declare DebugConfigFile=''
# configuration dump is supported in three modes, implemented with different lar options:
# - "Yes": configuration dumped into a file, then regular run
# - "Only": configuration dumped into a file, no run
case "$DumpConfigMode" in
	( 'No' )
		# "No": no configuration dump at all
		;;
	( 'Yes' | 'Only' )
		DebugConfigFile="${WorkDir:+"${WorkDir%/}/"}${JobName}.cfg"
		case "$DumpConfigMode" in
			( 'Yes' )  ConfigDumpOption='--config-out' ;;
			( 'Only' ) ConfigDumpOption='--dump-config' ;;
			( * ) FATAL 1 "Internal error: incomplete implementation, DumpConfigMode='${DumpConfigMode}'" ;;
		esac
		LArParams+=( '--config-out' "$DebugConfigFile" )
		OutputParams+=( "$((${#LArParams[@]} - 1))" )
		;;
	( * )
		FATAL 1 "Internal error: unsupported DumpConfigMode='${DumpConfigMode}'"
esac

[[ -n "$NewProcessName" ]] && LArParams+=( '--process-name' "$NewProcessName" )

isFlagSet NoOutput && LArParams+=( '--no-output' )

#
# prepare an empty sandbox
#
declare WorkDir="."
if isFlagSet SANDBOX ; then
# 	declare WorkDir="$(mktemp -d "workdir_${JobName}_XXXXXX" )"
	WorkDir="${LogPath%.log}"
	mkdir -p "$WorkDir"
	
	# we want the actual log file to be in the sandbox;
	# for convenience, it will be linked by the one outside the box
	declare RealLogPath="${WorkDir}/${JobName}.log"
	mv "$LogPath" "$RealLogPath"
	ln -s "$(basename "$WorkDir")/$(basename "$RealLogPath")" "$LogPath"
	
	for (( iSource = 0 ; iSource < ${#SourceFiles[@]} ; ++iSource )); do
		SourceFile="${SourceFiles[iSource]}"
		if [[ -r "$SourceFile" ]]; then
			SourceFiles[iSource]="$(grealpath "$SourceFile")"
		fi
	done
	
	# turn all the path parameters to absolute
	for iParam in "${PathParams[@]}" ; do
		Param="${LArParams[iParam]}"
		LArParams[iParam]="$(MakeAbsolute "$Param")"
	done

	# turn all the output path parameters to absolute and in the sandbox
	for iParam in "${OutputParams[@]}" ; do
		Param="${LArParams[iParam]}"
		isAbsolute "$Param" || Param="${WorkDir}/${Param}"
		LArParams[iParam]="$(MakeAbsolute "$Param")"
	done
	
fi

#
# copy files in the working area
#

# configuration file
# this helps keeping track of what was actually used

# ConfigPath is the configuration actually passed to lar;
# by default, we give it to lar what we found
# (it might be the wrong one, but it's well identified
# and if the user is not happy he/she can fix it)

declare ConfigPath="$(ImportFCLfileInWorkArea "${FullConfigPath:-${UserConfigPath}}" "$WorkDir" )"

# copy all the prepended and appended FCL files
declare -a PrependConfigPaths
for IncludeFile in "${PrependConfigFiles[@]}" ; do
	PrependConfigPaths=( "${PrependConfigPaths[@]}" "$(ImportFCLfileInWorkArea "$IncludeFile" "$WorkDir" )" )
done
declare -a AppendConfigPaths
for IncludeFile in "${AppendConfigFiles[@]}" ; do
	AppendConfigPaths=( "${AppendConfigPaths[@]}" "$(ImportFCLfileInWorkArea "$IncludeFile" "$WorkDir" )" )
done

# copy the file with the seeds to be restored in the final destination
RestoreSeed="$(ImportFileInWorkArea "$SavedSeed" "$WorkDir" "$RestoreSeed")"

declare SeedLogPath="$(MakeAbsolute "$SeedLogFile")"

#
# time to move into the working area (if any)
#
[[ "$WorkDir" == "." ]] || pushd "$WorkDir" > /dev/null || FATAL 3 "Can't use the working directory '${WorkDir}'"

#
# create the FCL file wrapper
#
declare WrappedConfigPath="$FullConfigPath"
declare WrappedConfigName="$(basename "$WrappedConfigPath")"
if isFlagSet UseConfigWrapper ; then
	WrappedConfigName="${JobName}-larrunwrapper.fcl"
	WrappedConfigPath="$WrappedConfigName"
	
	cat <<-EOH > "$WrappedConfigPath"
	# ******************************************************************************
	# Configuration wrapper for '${FullConfigPath}'
	#   created by ${USER} via ${SCRIPTNAME} on $(date)
	#   expected output directory: '${WorkDir}'
	# ******************************************************************************
	EOH
	
	if [[ "${#PrependConfigPaths[@]}" -gt 0 ]]; then
		cat <<-EOI >> "$WrappedConfigPath"
		
		# prepending additional configuration files:
		EOI
		for IncludeFile in "${PrependConfigPaths[@]}" ; do
			echo "#include \"${IncludeFile}\"" >> "$WrappedConfigPath"
		done
	fi
	
	cat <<-EOC >> "$WrappedConfigPath"
	
	# main FCL file:
	
	#include "${ConfigPath}"
	EOC
	
	if [[ -n "$SeedLogPath" ]]; then
		[[ -r "$SeedLogPath" ]] || FATAL 2 "Can't read log file '${SeedLogPath}' to extract seeds."
		cat <<-EOS >> "$WrappedConfigPath"
		
		# seeds extracted from "${SeedLogPath}"
		EOS
		STDERR "Extracting seeds from log '${SeedLogFile}'..."
		RandomSeedExtractor "$SeedLogPath" >> "$WrappedConfigPath"
	fi
	
	if [[ ${#DebugModules[@]} -gt 0 ]]; then
		cat <<-EOI >> "$WrappedConfigPath"
		
		# enabling debugging output only for the following modules
		services.message.debugModules: [ $(ListByComma "${DebugModules[@]}") ]
		EOI
	fi
	
	if [[ "${#AppendConfigPaths[@]}" -gt 0 ]]; then
		cat <<-EOI >> "$WrappedConfigPath"
		
		# including additional configuration files:
		EOI
		for IncludeFile in "${AppendConfigPaths[@]}" ; do
			echo "#include \"${IncludeFile}\"" >> "$WrappedConfigPath"
		done
	fi
	
	
	# process the arguments that still need processing
	ScheduleInputCommands
	
	if [[ "${#AppendConfigLines[@]}" -gt 0 ]]; then
		cat <<-EOI >> "$WrappedConfigPath"
		
		# including additional configuration from command line:
		EOI
		
		for ConfigLine in "${AppendConfigLines[@]}" ; do
			DBGN 1 "Processing injected config line: '${ConfigLine}'"
			ConfigLinePrefix=''
			if [[ "${ConfigLine:0:1}" == '>' ]]; then # check for internal marker
				ConfigLineTag="${ConfigLine%%=*}"
				ConfigLineTag="${ConfigLineTag:1}"
				ConfigLine="${ConfigLine#*=}"
				DBGN 2 " => it's special, of type '${ConfigLineTag}' (\"${ConfigLine}\")"
				case "$ConfigLineTag" in
					( 'service' ) # in `services`
						ConfigLinePrefix="${ConfigLineTag}s."
						;;
					( 'producer' | 'analyzer' | 'filter' ) # in `physics.*`
						ConfigLinePrefix="physics.${ConfigLineTag}s."
						;;
					( 'source' ) # in `source`
						ConfigLinePrefix="${ConfigLineTag}."
						;;
					( 'output' ) # in `outputs`
						ConfigLinePrefix="${ConfigLineTag}s."
						;;
					( * )
						FATAL 1 "Type '${ConfigLineTag}' of configuration line to be injected is not known."
						;;
				esac
			fi
			echo "${ConfigLinePrefix}${ConfigLine}" >> "$WrappedConfigPath"
		done
	fi
	
	echo -e "\n# additional (optional) setting override" >> "$WrappedConfigPath"
	
	if isFlagSet SANDBOX ; then
		# little hack: try to make sure that lar always look at this directory first
		# for FCL files, so that it finds immediately our wrapper *and* the FCL file
		# the wrapper includes;
		# this is not safe outside the sandbox since there could be other FCL files
		# in the current directory, which would override in an unexpected way the
		# others in case of inclusion (very unlikely, but a real nightmare to verify).
		# Also, make sure we can find the files the user could see
		FHICL_FILE_PATH=".:$(MakePathListAbsolute "$FHICL_FILE_PATH" "$CWD")"
		DBGN 2 "Expanded FHICL_FILE_PATH relative to '${CWD}':"
		DBGN 2 "FHICL_FILE_PATH=${FHICL_FILE_PATH}"
	fi
else
	[[ "${#AppendConfigLines[@]}" -eq 0 ]] || FATAL 1 "Can't inject additional configuration lines when config wrapping is disabled."
	[[ "${#AppendConfigFiles[@]}" -eq 0 ]] || FATAL 1 "Can't include additional configuration files when config wrapping is disabled."
	[[ "${#PrependConfigFiles[@]}" -eq 0 ]] || FATAL 1 "Can't prepend additional configuration files when config wrapping is disabled."
	[[ -z "$SeedLogFile" ]] || FATAL 1 "Can't use random seeds from a log file when config wrapping is disabled."
fi


if [[ -r "$RestoreSeed" ]]; then
	[[ -z "$SeedFromEvents" ]] || FATAL 1 "Seeds can be restored either from file or from events, not both."
	if isFlagSet UseConfigWrapper ; then
		cat <<-EOI >> "$WrappedConfigPath"
		
		# restore random generator seeds from a file:
		services.RandomNumberGenerator.restoreFrom: "${RestoreSeed}"
		EOI
	else
		WARN "The directive to restore random seeds from '${RestoreSeed}' must be already in the configuration file."
	fi
elif [[ -n "$SeedFromEvents" ]]; then
	ConfigurationReseeder "$ConfigPath" "${SourceFiles[0]}" "$SeedFromEvents" "" >> "$WrappedConfigPath"
	LASTFATAL "Couldn't set up the reseeding of the random generators by the event!"
fi

#
# expand lar parameters
#
declare -a SourceParams
declare -i nSources="${#SourceFiles[@]}"
for SourceEntry in "${SourceFiles[@]}" ; do
	if isSourceFileList "$SourceEntry" ]]; then
		SourceParams+=( '-s' "$SourceEntry" )
	else
		SourceParams+=( '-S' "$SourceEntry" )
  fi
done

#
# expand the parameters needed for the profiling (if any)
#
SetupProfiler "$Profiler"
LASTFATAL "Error setting up the profiling tool '${Profiler}'. Quitting."

#
# write the post-process script (if any)
#
PostProcessScriptPath="${WorkDir:+${WorkDir}/}${JobName}-postprocess.sh"
WritePostProcessScript "$(basename "$PostProcessScriptPath")" || PostProcessScriptPath=''


#
# execute the command
#
LarExecutable="$(which lar)"
declare -a BaseCommand
BaseCommand=( "${LarExecutable:-lar}" -c "$WrappedConfigPath" "${SourceParams[@]}" "${LArParams[@]}" )

declare -a Command
SetupCommand "${BaseCommand[@]}"

if ! which "${Command[0]}" >& /dev/null ; then
	if isFlagSet Force ; then
		WARN "Could not find the executable '${Command[0]}'. Trying anyway."
	else
		FATAL 2 "Could not find the executable '${Command[0]}' (use \`--force\` to attempt running anyway)"
	fi
fi

# if user interrupts, we want to terminate our children...
trap InterruptHandler SIGINT

#
# communicate what's going on, and exit
#
echo "$(date) --- starting ---------------------------------------------------"
cat <<EOM > "$AbsoluteLogPath"
================================================================================
Script:       ${SCRIPTNAME} version ${SCRIPTVERSION:-"unknown"}
Job name:    '${JobName}'
Base config: '${FullConfigPath}'
EOM
for (( iSourceEntry=0 ; iSourceEntry < $nSources ; ++iSourceEntry )); do
	SourceEntry="${SourceFiles[iSourceEntry]}"
	echo -n "Input:       "
	[[ "$nSources" -gt 1 ]] && echo -n " [$((iSourceEntry + 1))/${nSources}]"
	if isSourceFileList "$SourceEntry" ]]; then
		echo -n " file list"
	else
		echo -n " file"
	fi
	echo " '${SourceEntry}'"
done >> "$AbsoluteLogPath"
cat <<EOM >> "$AbsoluteLogPath"
Host:         $(hostname)
Directory:    $(pwd)
Executing:    ${Command[@]}
Log file:    '${LogPath}'
Date:         $(date)
Run with:     ${0} ${@}
EOM
if [[ "${#PrependConfigPaths[@]}" -gt 0 ]]; then
	let -i iFile=0
	echo "Prepended:   \"${PrependConfigPaths[iFile++]}\"" >> "$AbsoluteLogPath"
	while [[ $iFile -lt "${#PrependConfigPaths[@]}" ]]; do
		echo "             \"${PrependConfigPaths[iFile++]}\"" >> "$AbsoluteLogPath"
	done
fi
if [[ "${#AppendConfigPaths[@]}" -gt 0 ]]; then
	let -i iFile=0
	echo "Appended:    \"${AppendConfigPaths[iFile++]}\"" >> "$AbsoluteLogPath"
	while [[ $iFile -lt "${#AppendConfigPaths[@]}" ]]; do
		echo "             \"${AppendConfigPaths[iFile++]}\"" >> "$AbsoluteLogPath"
	done
fi
if [[ "${#AppendConfigPaths[@]}" -gt 0 ]]; then
	let -i iFile=0
	echo "Additional configuration:" >> "$AbsoluteLogPath"
	for ConfigLine in "${#AppendConfigLines[@]}" ; do
		echo "    ${ConfigLine}" >> "$AbsoluteLogPath"
	done
fi
if [[ -n "$NewProcessName" ]]; then
  echo "Process name overridden: '${NewProcessName}'" >> "$AbsoluteLogPath"
fi

[[ "$DumpConfigMode" != "No" ]] && echo "Configuration dump into: '${DebugConfigFile}'" >> "$AbsoluteLogPath"

# print environment variables:
{
	echo "FHiCL search path (FHICL_FILE_PATH):"
	PathListVar FHICL_FILE_PATH | sed -e 's/^/  /' 
	echo "Framework data search path (FW_SEARCH_PATH):"
	PathListVar FW_SEARCH_PATH | sed -e 's/^/  /' 
} >> "$AbsoluteLogPath"

cat <<EOM >> "$AbsoluteLogPath"
================================================================================
$(PrintPackageVersions)
================================================================================
UPS active packages:
--------------------------------------------------------------------------------
$(ups active)
================================================================================
EOM

export FHICL_FILE_PATH # be sure it is clear...

unset ART_DEBUG_CONFIG
declare LarPID
if isFlagUnset DontRun ; then
	"${Command[@]}" >> "$AbsoluteLogPath" 2>&1 &
	LarPID="$!"
fi
cat <<EOM
Job name:    '${JobName}'
Directory:    $(pwd)
Config file: '${FullConfigPath}'
Executing:    ${Command[@]}
Log file:    '${LogPath}'
Process ID:   ${LarPID:-(not running)}
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

if isFlagSet FollowLog ; then
	if [[ -r "$LogPath" ]] ; then
		cat <<-EOM
		++===========================================================================++
		||  Stop following by hitting <Ctrl>+<C>; job will not be stopped.           ||
		++===========================================================================++
		EOM
		
		# set Interrupt signal handler
		trap TailInterruptHandler SIGINT
		
		tailf "$LogPath" &
M
		TailPID="$!"
		wait "$TailPID"
		# reset to default the Interrupt signal handler
		trap - SIGINT
		
		if [[ -n "$LarPID" ]]; then
			if isRunning "$LarPID" ; then
				echo "The job will follow (PID=${LarPID}), log file: '${LogPath}'"
			else
				echo "The job seems to have terminated already (was PID=${LarPID}), log file: '${LogPath}'"
			fi
		fi
	else
		ERROR "Log file '${LogPath}' not found!"
	fi
fi

cat <<EOM
To see the output:
cd ${WorkDir}
EOM
if [[ -x "$PostProcessScriptPath" ]]; then
	cat <<-EOM
	Complete processing with: '${PostProcessScriptPath}'
	EOM
fi

exit 0
