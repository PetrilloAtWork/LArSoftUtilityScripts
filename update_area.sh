#!/usr/bin/env bash
#
# Updates the working area to allow for a new version.
# Use `update_area.sh --help` for usage instructions.
#
# Changes
# 20140326 (petrillo@fnal.gov) [v1.0]
#     original version
# 20150415 (petrillo@fnal.gov) [v1.1]
#     added the "--fake" option
# 20160701 (petrillo@fnal.gov) [v1.2]
#     unsetting the old MRB_INSTALL path from PRODUCTS
# 20170317 (petrillo@fnal.gov) [v1.3]
#     updated the list of packages not to learn current version from
# 


if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then # sourcing
	declare local_updatearea_SourceMe="$(mktemp -t update_area-XXXXXX)"
	export local_updatearea_SourceMe
fi

( # subshell, protect from sourcing

SCRIPTNAME="$(basename -- "$0")"
SCRIPTVERSION="1.3"

declare -ar SkipRepositories=( 'ubutil' 'lbneutil' 'sbndutil' 'larcoreobj' 'lardataobj' 'larsoftobj' )

function help() {
	cat <<-EOH
	Updates the working area to allow for a new version.
	
	Usage:  ${SCRIPTNAME} [options] [Version [Qualifiers]]
	
	If sourced, it will also source the local products setup.
	If the version is not specified, it will be set as the highest among the
	qualifying repositories in the source directory.
	
	Script options:
	--force
	    force the recreation of the local products area; the data there will be
	    lost!!
	--dryrun , --fake , -n
	    just prints the command that would be executed
	--debug[=LEVEL], -d
	    sets the verbosity level (0 is quietest; 1 if no level is specified)
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
	[[ "$Code" != 0 ]] && FATAL "$Code" "$@"
} # LASTFATAL()

function isDebugging() {
	local MsgLevel="${1:-1}"
	[[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge "$MagLevel" ]]
} # isDebugging()
function DBGN() {
	local Level="$1"
	shift
	isDebugging "$Level" && STDERR "DBG[${Level}]| $*"
} # DBGN()
function DBG() { DBGN 1 "$@" ; }

function DUMPVARN() {
	local Level="$1"
	shift
	local VarName
	local Output
	for VarName in "$@" ; do
		Output="${Output:+${Output} }${VarName}='${!VarName}'"
	done
	DBGN "$Level" "$Output"
} # DUMPVARN()


function isNumber() {
	local Value="$1"
	[[ -z "${Value//[0-9]}" ]]
} # isNumber()


function IsInList() {
	# Usage:  IsInList Key [Item ...]
	# Returns 0 if the key is one of the other specified items
	local Key="$1"
	shift
	local Item
	for Item in "$@" ; do
		[[ "$Item" == "$Key" ]] && return 0
	done
	return 1
} # IsInList()


function SortUPSqualifiers() {
	# Usage:  SortUPSqualifiers  Qualifiers [Separator]
	# sorts the specified qualifiers (colon separated by default)
	# The current sorting is: alphabetically, but move debug/opt/prof to the end
	local qual="$1"
	local sep="${2:-":"}"
	local item
	local -i nItems=0
	local -ar AllSpecials=( 'prof' 'opt' 'debug' )
	local -a Specials
	for item in $(tr "$sep" '\n' <<< "$qual" | sort) ; do
		if IsInList "$item" "${AllSpecials[@]}" ; then
			Specials=( "${Specials[@]}" "$item" )
			continue
		fi
		[[ "$((nItems++))" == 0 ]] || echo -n "$sep"
		echo -n "$item"
	done
	# add the special qualifiers at the end, in the original relative order
	for item in "${Specials[@]}" ; do
		[[ "$((nItems++))" == 0 ]] || echo -n "$sep"
		echo -n "$item"
	done
	echo
	return 0
} # SortUPSqualifiers()


function CheckSetup() {
	#
	# checks that everything is fine with the current settings
	#
	which ups >& /dev/null || FATAL 1 "UPS not configured!"
	[[ -n "$MRB_TOP" ]] || FATAL 1 "mrb working area not set up!"
	
	if ! declare -f setup unsetup >& /dev/null ; then
		ERROR "setup/unsetup not available!"
		cat <<-EOM
		UPS is correctly set up, but its setup/unsetup functions are not visible to scripts.
		A way to correct that in bash is to execute:
		
		export -f setup unsetup
		
		EOM
		FATAL 1 "UPS is not fully operative in script environment."
	fi
	return 0
} # CheckSetup()


function PackageList() {
	local -i nPackages=0
	for GitDir in "$MRB_SOURCE"/*/.git ; do
		PackageDir="$(dirname "$GitDir")"
		PackageName="$(basename "$PackageDir")"
		IsInList "$PackageName" "${SkipRepositories[@]}" && continue
		echo "$PackageName"
		let ++nPackages
	done
	[[ $nPackages -gt 0 ]]
} # PackageList()


function SplitVersion() {
	# assumes versions in the form v##_##_##tag_revision
	# prints a sequence of lines with: major version, all other versions,
	# a tag to the last version, and the rest of the revision
	local Version="$1"
	DBGN 2 "Splitting version string: '${Version}'"
	local -a Tokens=( ${Version//_/ } )
	local Item
	local -i NTokens="${#Tokens[@]}"
	DBGN 3 "  ${NTokens} tokens found"
	local iToken=0
	while [[ "$iToken" -lt "$NTokens" ]]; do
		DBGN 3 "  Token[${iToken}]: '${Tokens[iToken]}' (version)"
		# major version
		echo "${Tokens[iToken]#v}"
		let iToken++
		
		while [[ "$iToken" -lt "$NTokens" ]]; do
			DBGN 3 "  Token[${iToken}]: '${Tokens[iToken]}'"
			Token="${Tokens[iToken++]}"
			[[ -n "$Token" ]] || continue
			[[ "$Token" =~ ^[0-9]* ]]
			local Match="${BASH_REMATCH[0]}"
			local Rest="${Token#${Match}}"
			if [[ -z "$Match" ]]; then
				DBGN 4 "    not a number at all!"
				# the previous version was really the last
				# print an empty tag to it, and go on
				echo ""
				let --iToken
				break
			fi
			echo "$Match"
			if [[ -n "$Rest" ]]; then
				DBGN 4 "    matching a version '${Match}' and a tag '${Rest}'"
				echo "$Rest"
				break
			fi
			DBGN 4 "    plain version number"
		done
		
		# revision
		[[ "${#Tokens[@]}" -gt iToken ]] || break
		# all the rest is one token
		DBGN 3 "  Token[${iToken}]: '${Tokens[iToken]}' (first of revision)"
		echo -n "${Tokens[iToken++]}"
		while [[ $iToken -lt "${#Tokens[@]}" ]]; do
			DBGN 3 "  Token[${iToken}]: '${Tokens[iToken]}' (appended to revision)"
			echo -n "_${Tokens[iToken++]}"
		done
		echo
		
	done
} # SplitVersion()


function SortVersions() {
	local VersionTag
	local -a HighestVersion
	local HighestVersionTag
	while read VersionTag ; do
		DBGN 2 "Considering version '${VersionTag}'"
		local -a ThisVersion=( )
		local VersionToken
		while read VersionToken ; do
			ThisVersion=( "${ThisVersion[@]}" "$VersionToken" )
		done < <(SplitVersion "$VersionTag")
		local -i NThisTags="${#ThisVersion[@]}"
		DBGN 3 "  parsed as ${NThisTags} elements: ${ThisVersion[@]}"
		if [[ -n "$HighestVersion" ]]; then
			local -i iVTag=0
			while [[ $iVTag -lt $NThisTags ]]; do
				local Highest="${HighestVersion[iVTag]}"
				local This="${ThisVersion[iVTag]}"
				DBGN 4 "    comparing items #${iVTag}: '${This}' vs. '${Highest}'"
				let ++iVTag
				[[ "$Highest" == "$This" ]] && continue # so far, the same
				[[ -z "$This" ]] && continue 2 # this is not higher
				[[ -z "$Highest" ]] && break # this IS higher
				if isNumber "$This" && isNumber "$Highest" ; then
					DBGN 4 "       (both numbers)"
					[[ "${This#0}" -gt "${Highest#0}" ]] && break
					continue 2
				else
					[[ "$This" > "$Highest" ]] && break
					continue 2
				fi
			done
			
		fi
		DBGN 2 "  => version '${VersionTag}' (${ThisVersion[@]}) is the new highest"
		HighestVersion=( "${ThisVersion[@]}" )
		HighestVersionTag="$VersionTag"
	done
	echo "$HighestVersionTag"
} # SortVersions()


function DetectLatestVersion() {
	# prints the highest version among the packages matching a filter
	local Filter="$1"
	DBGN 2 "Detecting highest version among packages passing filter: '${Filter:-none}'"
	PackageList | while read PackageName ; do
		PackageDir="${MRB_SOURCE}/${PackageName}"
		if [[ -n "$Filter" ]] && [[ ! "$PackageName" =~ $Filter ]]; then
			DBGN 3 " - skip '${PackageName}' (filtered out)"
			continue
		fi
		ProductDeps="${PackageDir}/ups/product_deps"
		DBGN 3 " - check '${PackageName}' ('${ProductDeps}')"
		[[ -r "$ProductDeps" ]] && echo "$ProductDeps"
	done | xargs grep -h -e '^parent' | awk '{ print $3 ; }' | SortVersions
} # DetectLatestVersion()


function ExecCommandFilterOutput() {
	local Prepend="$1"
	shift
	local -a Command=( "$@" )
	if isFlagSet FAKE ; then
		echo "DRYRUN| ${Command[@]}"
		return 0
	else
		DBG "${Command[@]}"
		if [[ -n "$Prepend" ]]; then
			"${Command[@]}" | sed -e "s/^/${Prepend}/"
		else
			"${Command[@]}"
		fi
		return $?
	fi
} # ExecCommandFilterOutput()

function ExecCommand() { ExecCommandFilterOutput '' "$@" ; }


################################################################################
#
# parameters parser
#
declare DoHelp=0 DoVersion=0
declare Version

declare -i NoMoreOptions=0
declare -a Params
declare -i nParams=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' )       DoHelp=1  ;;
			( '--version' | '-V' )           DoVersion=1  ;;
			( '--debug' | '-d' )             DEBUG=1 ;;
			( '--debug='* )                  DEBUG="${Param#--*=}" ;;
			( '--fake' | '--dryrun' | '-n' ) FAKE=1 ;;
			
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
		Params[nParams++]="$Param"
	fi
done

unset ExitCode
declare -i ExitCode

if isFlagSet DoVersion ; then
	echo "${SCRIPTNAME} version ${SCRIPTVERSION:-"unknown"}"
	: ${ExitCode:=0}
fi

if isFlagSet DoHelp ; then
	[[ "${BASH_SOURCE[0]}" == "$0" ]] && help
	# set the exit code (0 for help option, 1 for missing parameters)
	{ [[ -z "$ExitCode" ]] || [[ "$ExitCode" == 0 ]] ; } && { isFlagSet DoHelp ; ExitCode="$?" ; }
fi

[[ -n "$ExitCode" ]] && exit $ExitCode

declare -i iParam=0
[[ -z "$Version" ]] && Version="${Params[iParam++]}"

declare QualifierSpecs="${Params[iParam++]:-"$MRB_QUALS"}"
declare Qualifiers="$(SortUPSqualifiers "$QualifierSpecs")"

#
# check that everything is fine with the current settings
#
CheckSetup || FATAL 1 "Configuration check failed."

pushd "$MRB_TOP" >& /dev/null
LASTFATAL "The working area '${MRB_TOP}' does not exist."

echo "Working area: '${MRB_TOP}'"

#
# detect the target version
#
while [[ -z "$Version" ]]; do
	if [[ ! -d "$MRB_SOURCE" ]]; then
		ERROR "No source directory available, can't autodetect the version."
		break
	fi
	
	Version="$(DetectLatestVersion '^lar')"
	DBG "Latest version among LArSoft sources: ${Version:-not found}"
	[[ -n "$Version" ]] && break

	Version="$(DetectLatestVersion)"
	DBG "Latest version among all sources: ${Version:-not found}"
	[[ -n "$Version" ]] && break
	
done
[[ -z "$Version" ]] && FATAL 1 "I don't know which version to set up!"

echo "Setting up the working area for ${MRB_PROJECT} ${Version} (${Qualifiers})"

declare LocalProductsDirName="localProducts_${MRB_PROJECT}_${Version}_${Qualifiers//:/_}"
declare LocalProductsPath="${MRB_TOP}/${LocalProductsDirName}"

if [[ -n "$local_updatearea_SourceMe" ]]; then
	cat <<-EOS > "$local_updatearea_SourceMe"
	source '${LocalProductsPath}/setup'
	[[ \$? != 0 ]] && return \$?
	if [[ "\$MRB_INSTALL" != "${MRB_INSTALL}" ]]; then
		export PRODUCTS="\$(sed -E -e "s@:${MRB_INSTALL}:@:@g" -e "s@(:|^)${MRB_INSTALL}(:|$)@@g" <<< "\${PRODUCTS}")"
	fi
	echo "PRODUCTS set to:"
	tr ':' $'\n' <<< "\$PRODUCTS"
	EOS
fi

if [[ -d "$LocalProductsPath" ]] && isFlagSet FORCE ; then
	echo "Local product directory '${LocalProductsDirName}' already exists: OVERWRITING IT!"
	ExecCommand rm -R "$LocalProductsPath"
fi
if [[ -d "$LocalProductsPath" ]]; then
	echo "Local product directory '${LocalProductsDirName}' already exists. Everything is good."
	exit
fi

declare -a Command=( mrb newDev -p -v "$Version" -q "$Qualifiers" )
echo " ==> ${Command[@]}"
ExecCommand "${Command[@]}"
ExitCode=$?
if [[ $ExitCode != 0 ]]; then
	ExecCommand rm -f "$local_updatearea_SourceMe"
	FATAL "$ExitCode" "Creation of the local products area failed!"
fi

LocalProductsLink="${MRB_TOP}/localProducts"
if [[ ! -e "$LocalProductsLink" ]] || [[ -h "$LocalProductsLink" ]]; then
	ExecCommand rm -f "$LocalProductsLink"
	ExecCommand ln -s "$LocalProductsDirName" "$LocalProductsLink" && echo "Updated 'localProducts' link."
else
	ERROR "Can't update localProduct since it does exist and it's not a link"
fi

if [[ "$(basename "$MRB_BUILDDIR")" =~ ^build ]]; then
	cat <<-EOM
	NOTA BENE: it is suggested that the working area is rebuilt anew:
	mrb zapBuild
	mrbsetenv
	mrb install
	EOM
fi

popd > /dev/null

)

declare local_updatearea_ExitCode=$?
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then # not sourcing
	exit $local_updatearea_ExitCode
else  # sourcing
	if [[ $local_updatearea_ExitCode != 0 ]]; then
		return $local_updatearea_ExitCode
	fi
	
	if [[ -n "$local_updatearea_SourceMe" ]]; then
		if [[ -s "$local_updatearea_SourceMe" ]]; then
			echo "Sourcing the local products setup for you."
			source "$local_updatearea_SourceMe"  # | sed -e 's/^/| /'
			echo "All done."
		fi
		rm -f "$local_updatearea_SourceMe"
	fi
	unset local_updatearea_SourceMe local_updatearea_ExitCode
fi

