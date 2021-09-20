#!/usr/bin/env bash
#
# Switches between a test directory and its tested code directory.
# Run without parameters for usage instructions.
#
# Changes
# 20161021 (petrillo@fnal.gov) [v1.1]
#   added support for dunetpc-like and lariatsoft-like repositories
#   to go test => source (the other direction is probably still
#   broken for lariatsoft-like repositories)
#

# guard against sourcing
[[ "$BASH_SOURCE" != "$0" ]] && echo "Don't source this script." >&2 && exit 1

################################################################################
SCRIPTNAME="$(basename "$0")"
SCRIPTVERSION="1.1"
CWD="$(pwd)"

function help() {
	cat <<-EOH
	Switches between a test directory and its tested code directory
	(it actually only prints where go to).
	
	Usage:  ${SCRIPTNAME}  [options]
	
	Options
	--quiet , -q
	    don't print any error message
	--debug[=LEVEL] , -d
	    sets the verbosity level (if no level is specified, level 1 is set)
	
	EOH
} # help()


function isFlagSet() {
	local VarName="$1"
	[[ -n "${!VarName//0}" ]]
} # isFlagSet()

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

function isDebugging() {
	local -i Level="${1:-1}"
	[[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge "$Level" ]]
} # isDebugging()

function DBGN() {
	local -i Level="$1"
	shift
	isDebugging && STDERR "DBG[${Level}] $*"
} # DBGN()
function DBG() { DBGN 1 "$@" ; }


function isInPath() {
	# isInPath  Path BasePath
	# succeeds if Path is under BasePath, in which case also prints
	# the part of Path that exceeds BasePath
	local Path="$1"
	local BasePath="$2"
	local CWD="$(pwd)"
	
	[[ -z "$Path" ]] && return 1
	[[ -z "$BasePath" ]] && return 1
	[[ "${Path:0:1}" == '/' ]] || Path="${CWD%/}/${Path}"
	[[ "${BasePath:0:1}" == '/' ]] || BasePath="${CWD%/}/${Path}"
	
	local StartPath="$Path"
	DBGN 3 "Does '${Path}' live under '${BasePath}'?"
	while [[ "$Path" != '/' ]]; do
		DBGN 4 "  - testing: '${Path}'"
		if [[ "$Path" -ef "$BasePath" ]]; then
			local Left="${StartPath#${Path}}"
			DBGN 3 "  => YES! '${Path}' matches the base path, plus '${Left#/}'"
			echo "$Left"
			return 0
		fi
		Path="$(dirname "$Path")"
	done
	DBGN 3 "  => NO!"
	return 1
} # isInPath()


function DetectCodeBaseDir() {
	local PackageName="$1"
	local BaseDir="$2"
	local Mode="$3"
	local SubDir="$4"
	
	# this is the expected solution if the code is inside a subdirectory
	# with the same name as the package:
	local SimpleCodeDir="${BaseDir}/${PackageName}${SubDir:+"/${SubDir}"}"
	if [[ -d "$SimpleCodeDir" ]]; then
		DBGN 2 "Simple pattern found => '${PackageName}'"
		echo "$PackageName"
		return 0
	fi
	
	# there are some euristics we can use only if we have a subdir directory
	# (and even then...)
	if [[ -n "$SubDir" ]]; then
		# maybe there is no special directory for the code, lariatsoft-like:
		if [[ -d "${BaseDir}/${SubDir}" ]]; then
			DBGN 2 "No base code subdirectory => ''"
			echo ""
			return 0
		fi
		
		# or maybe it has a name different than the package name
		local CodeBaseDir CodeBaseDirCandidate=''
		for CodeBaseDir in "$BaseDir"/* ; do
			[[ -d "$CodeBaseDir" ]] || continue
			[[ -d "${CodeBaseDir}/${SubDir}" ]] || continue
			local DirName="$(basename "$CodeBaseDir")"
			# ignore known directories
			case "$DirName" in
				( 'test' | 'ups' ) continue ;;
			esac
			DBGN 3 "Subdirectory '${CodeBaseDir}' has a '${SubDir}'"
			if [[ -n "$CodeBaseDirCandidate" ]]; then
				DBGN 2 "Too many subdirectories of '${BaseDir}' contain '${SubDir}' ('${CodeBaseDirCandidate}', '${DirName}')"
				return 1
			fi
			CodeBaseDirCandidate="$DirName"
		done
		if [[ -n "$CodeBaseDirCandidate" ]]; then
			DBGN 2 "Found '${SubDir}' in non-package-named directory => '${CodeBaseDirCandidate}'"
			echo "$CodeBaseDirCandidate"
			return 0
		fi
	else
		# with no subdir offered, we can just try our luck
		DBGN 2 "No subdir provided, no '${PackageName}'; assuming no base code subdirectory => ''"
		echo ""
		return 0
	fi
	
	DBGN 2 "Failed to detect code base directory; returning '${PackageName}'"
	echo "$PackageName"
	return 1
} # DetectCodeBaseDir()


################################################################################

# default parameters
declare -i BeQuiet=0

###
### parameters parsing
###
declare -i NoMoreOptions=0
declare -a Arguments
declare -i nArguments=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' ) DoHelp=1  ;;
			( '--version' | '-V' ) DoVersion=1  ;;
			( '--debug='* ) DEBUG="${Param#--*=}" ;;
			( '--debug' | '-d' ) DEBUG=1 ;;
			
			( '--quiet' | '-q' ) BeQuiet=1 ;;
			
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
		Arguments[nArguments++]="*${Param}*"
	fi
done

if isFlagSet DoHelp || [[ $nArguments -gt 0 ]]; then
	help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	exit $?
fi

if isFlagSet DoVersion ; then
	echo "${SCRIPTNAME} version ${SCRIPTVERSION}"
	exit 0
fi

[[ -d "$MRB_TOP" ]] || FATAL 1 "No MRB working area is set up."

###
### autodetect where we are
###

# first, the base directory
declare SubDir=''
for TestVar in MRB_BUILDDIR MRB_SOURCE MRB_INSTALL MRB_TOP ; do
	Dir="${!TestVar}"
	[[ -n "$Dir" ]] || continue
	
	SubDir="$(isInPath "$CWD" "$Dir")" || continue
	
	Src="$TestVar"
	break
done


DBG "Source directory is ${Src} (${!Src}), subdir: '${SubDir}'"
# we expect SubDir to be in the form: <PackageName>/<PackageName|test>/<MoreDir>
# we want:
#   BaseDir=${!Src}/<PackageName>
#   Mode=<PackageName|test>
#   SubDir=<MoreDir>
#
BaseDir="${!Src}"
SubDir="${SubDir#/}"

# extract <PackageName>
PackageName="${SubDir%%/*}"
[[ -z "$PackageName" ]] && FATAL 1 "It seems we are not in any repository!"
BaseDir+="/${PackageName}"
SubDir="${SubDir#${PackageName}}"
SubDir="${SubDir#/}"

# extract Mode
Mode="${SubDir%%/*}"
SubDir="${SubDir#${Mode}}"
SubDir="${SubDir#/}"

DBG "Package: '${PackageName}', base dir: '${BaseDir}', mode: '${Mode}', subdir: '${SubDir}'"


###
### autodetect where to go
###
case "$Mode" in
	( 'test' )
		Dest="$(DetectCodeBaseDir "$PackageName" "$BaseDir" "$Mode" "$SubDir")"
		LASTFATAL 1 "Can't find where the code is."
		;;
	( 'ups' | 'releaseDB' )
		FATAL 1 "We are neither in the repository source nor in the test directory."
		;;
	( * )      Dest="test" ;;
esac

###
### Go!
###

[[ -z "$Dest" ]] && FATAL 1 "BUG: I am lost, I don't know where to go!"

DestDir="${BaseDir}/${Dest}/${SubDir}"

echo "$DestDir"

[[ -d "$DestDir" ]] || exit 3
exit 0
###
