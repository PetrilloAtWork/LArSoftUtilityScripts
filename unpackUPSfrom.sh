#!/usr/bin/env bash
#
# Usage:  unpackUPSpackage.sh fetch_script TarballPath [TarballPath ...]
#

SCRIPTNAME="$(basename "$0")"

: ${TempDir:="."}

function STDERR() { echo "$*" >&2 ; }
function ERROR() { STDERR "ERROR: $*" ; }
function CODEDERROR() {
	local Code="$1"
	shift
	STDERR "ERROR [${Code}]: $*"
} # CODEDERROR()
function LASTERROR() {
	local Code=$?
	[[ $Code != 0 ]] && CODEDERROR "$Code" "$@"
	return $Code
} # LASTERROR()

function Fetch() {
	local Source="$1"
	local Dest="$2"
	"$FetchScript" read "$Source" "$Dest"
} # Fetch()

function Unpack() {
	local Tarball="$1"
	local Dest="${2:-"."}"
	
	if [[ ! -r "$Tarball" ]]; then
		ERROR "Can't read local tarball: '${Tarball}'"
		return 2
	fi
	
	tar xf "$Tarball" -C "$Dest"
	LASTERROR "Error unpacking '${Tarball}'"
	
} # Unpack()

function FetchAndInstall() {
	local TarballSource="$1"
	local TarballName="$(basename "$1")"
	local TarballPath="${TempDir%/}/${TarballName}"
	
	Fetch "$TarballSource" "$TarballPath"
	LASTERROR "Error while reading '${TarballSource}'" || return $?
	
	Unpack "$TarballPath"
	LASTERROR "Error while unpacking '${TarballSource}'; tarball left at '${TarballPath}'"
} # FetchAndInstall()

###############################################################################
declare FetchScript

if [[ "$SCRIPTNAME" =~ unpack_from_(.*) ]]; then
	FetchScript="${BASH_REMATCH[1]}"
else
	FetchScript="$1"
	shift
fi

echo "Reading from '${FetchScript}':"

declare -i nPackages=0 nErrors=0
for Tarball in "$@" ; do
	let ++nPackages
	FetchAndInstall "$Tarball" || let ++nErrors
done

if [[ $nPackages -gt 0 ]]; then
	if [[ $nErrors == 0 ]]; then
		echo "${nPackages} packages successfully retrieved and unpacked."
	else
		echo "$((nPackages - nErrors))/${nPackages} packages successfully retrieved and unpacked, ${nErrors} errors."
	fi
else
	echo "No packages processed."
fi
exit $nErrors

