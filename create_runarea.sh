#!/usr/bin/env bash
#
# Creates a new run area.
# Run without parameters for usage instructions.
#

function _doSource() {
	# Reminder: `source` will pass all the "current" command line arguments ($*)
	# to the sourcing script if no additional command line argument is specified.
	# This wrapper gives control to the caller on which the current arguments are.
	# Also, `source "$@"` would incur into the same issue, where in case of no
	# additional argument `source "$1"` would still add as arguments of the
	# sourced script the arguments of the function, that is the name of the very
	# script to be sourced, effectively resulting in `source "$1" "$1"`.
	local ScriptName="$1"
	shift
	source "$ScriptName" "$@"
} # _doSource()


function _CanonizePath() {
	local Path="$1"
	local BasePath="${2:-$(pwd)}"
	
	local CanonicalPath="$Path"
	[[ "${CanonicalPath:0:1}" != "/" ]] && CanonicalPath="${BasePath%/}/${Path}"
	if declare -F canonical_path >& /dev/null ; then
		# if we have the canonical_path utility, use it: makes it easier to read
		canonical_path "$CanonicalPath"
	else
		echo "$CanonicalPath"
	fi
} # _CanonizePath()


function _DetectRunAreaPath() {
	#
	# Builds the run area path, based on the development area (first argument).
	# 
	# The idea is to create a subpath similar to the one in the development area;
	# for example: with development area
	# /...develbase.../LArSoft/development/debug
	# the run area should be /...runbase.../LArSoft/development/debug
	# and this script should be able to return that result if the current
	# directory is any of:
	# /...runbase.../LArSoft/development/debug
	# /...runbase.../LArSoft/development
	# /...runbase.../LArSoft
	# 
	# In practise, the name of the current directory is searched for in the
	# develop path, and whatever follows it is appended to the current directory
	# to make the final run area path.
	#
	
	local DevelopArea="$1"
	
	local Cwd="$(pwd)"
	local -r ThisDirName="$(basename "$Cwd")"
	
	# look for the deepest subdirectory in the development area that has the same
	# name as the current directory; that will be the common base line
	local RelativePath SearchPath="$DevelopArea"
	while true ; do
		if [[ -z "$SearchPath" ]] || [[ "$SearchPath" == '/' ]]; then
			return 1
		fi
		local DirName="$(basename "$SearchPath")"
		if [[ "$DirName" == "$ThisDirName" ]]; then
			break
		fi
		# chip away the directory name
		SearchPath="${SearchPath%/${DirName}}"
		RelativePath="${DirName}${RelativePath:+/${RelativePath}}"
	done
	echo "${Cwd%/}${RelativePath:+/${RelativePath}}"
	return 0
} # _DetectRunAreaPath()


function create_runarea() {
	local scriptdir="$(dirname "${BASH_SOURCE[0]}")"
	local scriptname="$(basename "${BASH_SOURCE[0]}")"
	
	OPTIND=1
	local Option
	local -i DoHelp=0
	while getopts 'h?' Option ; do
		case "$Option" in
			( 'h' | '?' ) DoHelp=1 ;;
			( '-' ) let ++OPTIND ; break ;;
		esac
	done
	shift $((OPTIND-1))
	
	if [[ $# == 0 ]] || [[ $DoHelp != 0 ]]; then
		cat <<-EOH
		Creates and sets up a new LArSoft run area mirroring an existing development one.
		
		Usage:  source ${scriptname}  [options] DevelopArea [NewPath]
		
		DevelopArea is a path which must contain a localProduct directory (usually
		a link to a MRB_INSTALL directory).
		If NewPath is specified, the area will be set up in it. Otherwise, the
		directory tree in DevelopArea will replicated down to the first directory
		which has the same name as the current one, or is not writable by the user,
		or is user's home directory.
		
		Options:
		    -h , -?
		        prints this help message
		
		EOH
		[[ $DoHelp != 0 ]]
		return
	fi
	
	###
	### parameters parsing
	###
	local develop="$(_CanonizePath "$1")"
	local runarea="$2" # optional
	
	if [[ -z "$runarea" ]]; then
		runarea="$(_DetectRunAreaPath "$develop")"
		if [[ $? != 0 ]]; then
			echo "Could not find where to create the area, sorry." >&2
			runarea=''
		fi
	fi
	
	if [[ "$BASH_SOURCE" == "$0" ]]; then
		cat <<-EOM
		Developement area: ${develop}
		Running area:      ${runarea}
		This script needs to be sourced:
		source $0 $@
		EOM
		return
	fi
	
	if [[ -z "$runarea" ]]; then
		echo "You really need to specify where to create the area." >&2
		return 1
	fi
	
	
	###
	### creation of the new area
	###
	if [[ -d "$runarea" ]]; then
		echo "The working area '${runarea}' already exists." >&2
		cd "$runarea"
		return 17
	fi
	
	mkdir -p "$runarea"
	cd "$runarea"
	local res=$?
	if [[ $res != 0 ]] ; then
		echo "Error creating the new area in '${runarea}'." >&2
		return $res
	fi
	
	echo "Linking the products directory..."
	ln -s "${develop}/localProducts" "localProducts"
	
	local setup_path="${scriptdir}/setup/runtime"
	if [[ -r "$setup_path" ]]; then
		echo "Linking the runtime setup script (and sourcing it!)"
		rm -f 'setup'
		ln -s "$setup_path" 'setup'
		_doSource './setup'
	else
		echo "Can't find runtime setup script ('${setup_path}'): setup not linked." >&2
	fi
	
	mkdir -p "logs" "job" "input"
	[[ -d "$runarea" ]] && cd "$runarea"
} # create_runarea()

function create_runarea_wrapper() {
	create_runarea "$@"
	local -i res=$?
	unset -f _doSource _CanonizePath _DetectRunAreaPath create_runarea create_runarea_wrapper
	return $res
} # create_runarea_wrapper()

create_runarea_wrapper "$@"
