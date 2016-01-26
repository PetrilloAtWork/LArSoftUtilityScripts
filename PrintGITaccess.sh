#!/usr/bin/env bash
#
# Prints the access mode for all the GIT repositories under the specified
# directory.
#

function PrintAccess() {
	local Dir="$1"
	
	pushd "$Dir" > /dev/null || return 3
	PackageName="$(basename "$Dir")"
	
	git remote -v | while read Source URL Mode ; do
		[[ "$Mode" == "(push)" ]] || continue
		Protocol="${URL%%://*}"
		[[ "$Protocol" == "$URL" ]] && Protofol="file"
		
		if [[ "$Source" != 'origin' ]]; then
			echo -n "${PackageName} (source: '${Source}'): "
		else
			echo -ne "${PackageName}: \t"
		fi
		case "$Protocol" in
			( 'ssh' ) echo -n "full access" ;;
			( 'file' | 'git' | 'http' | 'https' ) echo -n "read only (${Protocol})" ;;
			( * ) echo -n "? (protocol: ${Protocol})" ;;
		esac
		echo
	done
	
	popd > /dev/null
	
	return 0
} # PrintAccess()

################################################################################

SourceDir="${1:-"${MRB_SOURCE:-"."}"}"
declare -a Sources
if [[ -d "${SourceDir}/.git" ]]; then
	Sources=( "$SourceDir" )
else
	for Dir in "$SourceDir"/* ; do
		[[ -d "${Dir}/.git" ]] && Sources=( "${Sources[@]}" "$Dir" )
	done
fi

declare -i nPackages=0
for Dir in "${Sources[@]}" ; do
	PrintAccess "$Dir"
	[[ $? == 0 ]] && let ++nPackages
done

if [[ $nPackages == 0 ]]; then
	echo "No GIT repositories found in '${SourceDir}'!" >&2
	exit 1
fi
exit 0
