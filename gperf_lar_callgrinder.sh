#!/usr/bin/env bash
#
# Converts all the .prof files it finds to callgrind format (assuming lar as executable)
#

: ${pprof:=pprof}

: ${lar:="$(which lar)"}

if [[ ! -x "$lar" ]]; then
	echo "Can't find the LArSoft executable (lar)!" >&2
	exit 2
fi

echo "Using LArSoft executable: '${lar}'"

find "${@:-"."}" -type f -name "*.prof" | { # this will happen in a subshell
	declare nErrors=0
	while read ProfPath ; do
		GrindPath="${ProfPath%.prof}.callgrind"
		
		if [[ "$GrindPath" -nt "$ProfPath" ]]; then
			echo "'${GrindPath}' already up to date: kept."
			continue
		fi
		
		echo "Creating '${GrindPath}'"
		$pprof --callgrind "$lar" "$ProfPath" > "$GrindPath"
		[[ $? != 0 ]] && let ++nErrors
	done
	exit $nErrors # exits the piped subshell
}

declare -i nErrors=$?
if [[ $nErrors -gt 0 ]]; then
	echo "Execution terminated with ${nErrors} errors."
fi

exit $nErrors
