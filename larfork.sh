#!/usr/bin/env bash
#
# For each repository forks creating an upstream and a new origin.
# 
# print the versions each package depends on
# 
# Run '--help' for help usage.
#

SCRIPTDIR="$(dirname "$0")"
SCRIPTVERSION="1.0"

ORIGINNAME='origin'
UPSTREAMNAME='upstream'
GITHUBURL='git@github.com:'

function AutodetectForkURL() {
	
	local GitHubUser
	GitHubUser="$(git config 'user.github' 2> /dev/null)"
	if [[ -n "$GitHubUser" ]]; then
		echo "${GITHUBURL%:}:${GitHubUser}"
		return 0
	fi
	
	return 1
} # AutodetectForkURL()


function AddUpstreamRepository() {
	local PackageName="$1"
	local ForkURL="$2"
	
	: ${ForkURL:="$(AutodetectForkURL "$PackageName")"}
	
	# currenly there is no autodetection system, so that failure is no surprise...
	[[ -n "$ForkURL" ]] || FATAL 1 "Fork URL not specified and could not be autodetected."
	
	local res
	local ExpectedUpstreamURL="${ForkURL%/}/${PackageName}.git"
	local UpstreamURL OriginURL NewURL
	local Msg
	
	#
	# detect which remote repositories are registered
	#
	local -a Remotes
	Remotes=( $(git remote) )
	LASTFATAL "Error running 'git remote' on '${PackageName}'!"
	
	local -i HasOrigin=0
	local -i HasUpstream=0
	local Remote
	for Remote in "${Remotes[@]}" ; do
		case "$Remote" in
			( "$ORIGINNAME" ) HasOrigin=1 ;;
			( "$UPSTREAMNAME" ) HasUpstream=1 ;;
		esac
	done
	
	if [[ $HasUpstream == 1 ]]; then
		UpstreamURL="$(git remote get-url origin 2> /dev/null)" || Msg="couldn't find its URL though"
		[[ "$UpstreamURL" == "$ExpectedUpstreamURL" ]] || Msg="but points to '${UpstreamURL}', not '${ExpectedUpstreamURL}'"
		echo "  already has '${UPSTREAMNAME}' repository${Msg:+" (${Msg})"}"
		return
	fi
	if [[ $HasOrigin == 2 ]]; then
		echo "  has no '${ORIGINNAME}'!!!"
		return 1
	fi
	
	OriginURL="$(git remote get-url "$ORIGINNAME")"
	LASTFATAL "Can't get '${ORIGINNAME}' remote URL for '${PackageName}'!"
	
	#
	# rename the old origin to upstream
	#
	local OriginPackageName="${OriginURL##*/}"
	[[ "$OriginPackageName" != "${PackageName}.git" ]] && Msg="package name '${OriginPackageName%.git}', not '${PackageName}'"
	git remote rename "$ORIGINNAME" "$UPSTREAMNAME"
	res=$?
	if [[ $res != 0 ]]; then
		ERROR "Failed to rename ${ORIGINNAME} remote repository!"
		return $?
	fi
	NewURL="${ForkURL%/}/${OriginPackageName}" # prefer the original package name in any case
	
	#
	# create the new origin
	#
	git remote add "$ORIGINNAME" "$NewURL"
	res=$?
	if [[ $res != 0 ]]; then
		ERROR "Failed to add ${ORIGINNAME} remote repository!"
		return $?
	fi
	
	#
	# fetch everything
	#
	git fetch --multiple "$ORIGINNAME" "$UPSTREAM" >&2
	res=$?
	[[ $res != 0 ]] && Msg="${Msg:+"${Msg}; fetching returned error code ${res}"}"
	
	echo "origin set to '${NewURL}'${Msg:+" (${Msg})"}"
	
} # AddUpstreamRepository()

################################################################################
### This is quasi-boilerplate for better interface with larcommands.sh
###
function help() {
	cat <<-EOH
	Sets up for a fork or the \`${ORIGINNAME}\` repository.
	
	Usage:  ${SCRIPTNAME}  [base options]  ForkURL
	
	For each package, if \`${UPSTREAMNAME}\` name is not present, it is created from
	\`${ORIGINNAME}\` (move), and the new \`${ORIGINNAME}\` is set to the same package
	name in the specified ForkURL.
	A fetch of both the repositories is performed on success.
	
	ForkURL must point to the Git repository parent (for example, the one of
	SBN upstream is \`git@github.com:SBNSoftware\`). It defaults to GitHub if
	the GitHub user is available (GIT \`user.github\` configuration key).
	
	EOH
	help_baseoptions
} # help()

################################################################################

source "${SCRIPTDIR}/larcommands.sh" --compact=line --skipnooutput --tag='PACKAGENAME' --tag='ARGS' --miscargs=$# "$@" -- AddUpstreamRepository '%PACKAGENAME%' '%ARGS%'
