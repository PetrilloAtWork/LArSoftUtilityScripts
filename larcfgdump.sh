#!/usr/bin/env bash
#
# Creates a config dump for each configuration file specified.
#

for FHICLfile in "$@" ; do
	if [[ "${FHICLfile//\/}" == "$FHICLfile" ]]; then
		OldIFS="$IFS"
		declare -a ConfigDirs
		read -a ConfigDirs <<< "$FHICL_FILE_PATH"
		for CfgDir in "${ConfigDirs[@]}" ; do
			[[ -r "${CfgDir}/${FHICLfile}" ]] && FullFHICLfile="${CfgDir}/${FHICLfile}" && break
		done
	else
		FullFHICLfile="$FHICLfile"
	fi
	
	export ART_DEBUG_CONFIG="$(basename "${FHICLfile%.fcl}").cfg"
	lar -c "$FHICLfile" >& /dev/null
	echo "${FullFHICLfile} => '${ART_DEBUG_CONFIG}'"	
done

