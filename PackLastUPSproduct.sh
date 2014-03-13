#!/bin/bash

: ${DESTDIR:=""}

declare -i nErrors
for Package in "$@" ; do
	PACKAGE="$(tr '[:lower:]' '[:upper:]' <<< "$Package")"
	PackageDirVarName="${PACKAGE}_DIR"
	PackageBaseDir="$(dirname "${!PackageDirVarName}")"
	if [[ ! -d "$PackageBaseDir" ]]; then
		if [[ -z "$PackageBaseDir" ]]; then
			echo "Can't extract base dir of package '${Package}' (invalid ${PackageDirVarName})... have you set it up?" >&2
		else
			echo "Base dir of package '${Package}' not valid: '${PackageBaseDir}'" >&2
		fi
		let ++nErrors
		continue
	fi

	LatestVersionDir="$(ls -1vrd "${PackageBaseDir}"/*.version | head -n 1)"
	LatestDir="${LatestVersionDir%.version}"
	LatestVersion="$(basename "$LatestDir")"
	DestFile="${DESTDIR:+"${DESTDIR}/"}${Package}-${LatestVersion}.tar.bz2"
	CurrentChain="${PackageBaseDir}/current.chain"
	[[ -d "$CurrentChain" ]] || CurrentChain=''
	RelativeBase="$(basename "$PackageBaseDir")"
	echo "Packing ${Package} ${LatestVersion:-"(no version)"} into '${DestFile}'..."
	tar cjf "$DestFile" -C "$(dirname "$PackageBaseDir")" "${RelativeBase}/${LatestVersion}" "${RelativeBase}/${LatestVersion}.version" ${CurrentChain:+"${RelativeBase}/$(basename "$CurrentChain")"}
	[[ $? == 0 ]] || let ++nErrors
done
exit $nErrors
