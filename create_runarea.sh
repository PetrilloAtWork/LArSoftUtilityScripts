#!/usr/bin/env bash
#
# Creates a new run area.
# Run without parameters for usage instructions.
#

declare local_create_runarea_scriptdir="$(dirname "$BASH_SOURCE")"

if [[ $# == 0 ]]; then
	cat <<-EOH
	Creates and sets up a new LArSoft run area mirroring an existing development one.
	
	Usage:  source $(basename "$BASH_SOURCE") DevelopArea [NewPath]
	
	DevelopArea is a path which must contain a localProduct directory (usually
	a link to a MRB_INSTALL directory).
	If NewPath is specified, the area will be set up in it. Otherwise, the
	directory tree in DevelopArea will replicated down to the first directory
	which has the same name as the current one, or is not writable by the user,
	or is user's home directory.
	EOH
	
	unset local_create_runarea_scriptdir
	[[ "$BASH_SOURCE" != "$0" ]] && return
	exit
fi


function CanonizePath() {
	local Path="$1"
	local BasePath="${2:-$(pwd)}"
	
	local CanonicalPath="$Path"
	[[ "${CanonicalPath:0:1}" != "/" ]] && CanonicalPath="${BasePath%/}/${Path}"
	echo "$CanonicalPath"
} # CanonizePath()


function local_create_runarea_DetectRunAreaPath() {
	local DevelopArea="$(CanonizePath "$1")"
	
	local Cwd="$(pwd)"
	local HomeDir="$HOME"
	local ThisDirName="$(basename "$Cwd")"
	
	local RelativePath SearchPath="$DevelopArea"
	while true ; do
		[[ "$SearchPath" == '/' ]] && break
		
		if [[ "$(basename "$SearchPath")" == "$ThisDirName" ]]; then
			RelativePath="$SearchPath"
			break
		fi
		SearchPath="$(dirname "$SearchPath")"
	done
	[[ -z "$RelativePath" ]] && return 1
	echo "${Cwd%/}/${DevelopArea#"${RelativePath}/"}"
	return 0
} # local_create_runarea_DetectRunAreaPath()


###
### parameters parsing
###
declare local_create_runarea_develop="$1"
declare local_create_runarea_runarea="$2"

if [[ -z "$local_create_runarea_runarea" ]]; then
	local_create_runarea_runarea="$(local_create_runarea_DetectRunAreaPath "$local_create_runarea_develop")"
	if [[ $? != 0 ]]; then
		echo "Could not find where to create the area, sorry." >&2
		local_create_runarea_runarea=''
	fi
fi

unset -f local_create_runarea_DetectRunAreaPath


if [[ "$BASH_SOURCE" == "$0" ]]; then
	cat <<-EOM
	Developement area: ${local_create_runarea_develop}
	Running area:      ${local_create_runarea_runarea}
	This script needs to be sourced:
	source $0 $@
	EOM
	[[ "$BASH_SOURCE" != "$0" ]] && return 1
	exit 1
fi

if [[ -z "$local_create_runarea_runarea" ]]; then
	echo "You really need to specify where to create the area." >&2
	unset local_create_runarea_scriptdir local_create_runarea_develop local_create_runarea_runarea
	return 1
fi


###
### creation of the new area
###
if [[ -d "$local_create_runarea_runarea" ]]; then
	echo "The working area '${local_create_runarea_runarea}' already exists." >&2
	cd "$local_create_runarea_runarea"
	return 1
else
	mkdir -p "$local_create_runarea_runarea"
	if ! cd "$local_create_runarea_runarea" ; then
		echo "Error creating the new area in '${local_create_runarea_runarea}'." >&2
		return 1
	fi
	
	echo "Linking the products directory..."
	ln -s "${local_create_runarea_develop}/localProducts" "localProducts"
	
	if [[ -r "${local_create_runarea_scriptdir}/setup/runtime" ]]; then
		echo "Linking the runtime setup script (and sourcing it!)"
		rm -f 'setup'
		ln -s "${local_create_runarea_scriptdir}/setup/runtime" 'setup'
		source './setup'
	else
		echo "Can't find runtime setup script ('${local_create_runarea_scriptdir}/setup/runtime'): setup not linked." >&2
	fi
	
fi

mkdir -p "logs" "job" "input"
[[ -d "$MRB_TOP" ]] && cd "$MRB_TOP"

###
### clean up
###
unset local_create_runarea_develop local_create_runarea_runarea

###
