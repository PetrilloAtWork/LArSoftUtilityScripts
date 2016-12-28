#!/usr/bin/env bash
#
# Distributes a command to all the GIT repositories.
#
# Changes:
# 20150304 (petrillo@fnal.gov) [v1.1]
#   started tracking versions;
#   added --version, --ifhasbranch, --ifcurrentbranch options
# 20150415 (petrillo@fnal.gov) [v1.2]
#   added --only and --skip options
# 20150415 (petrillo@fnal.gov) [v1.3]
#   added --command option
# 20150914 (petrillo@fnal.gov) [v2.0]
#   rewritten argument parsing;
#   support for "miscellaneous" arguments that a caller can pass here for
#     processing;
#   new handling of help messages;
#   new option --skipnooutput;
# 20151005 (petrillo@fnal.gov) [v2.1]
#   colouring the repository name by default
# 20151023 (petrillo@fnal.gov) [v2.2]
#   long help messages are paged via $PAGER
# 20160315 (petrillo@fnal.gov) [v2.3]
#   added option to override source directory
# 20160329 (petrillo@fnal.gov)
#   bug fixed: replacement of commands with multiple tags
# 20160811 (petrillo@fnal.gov)
#   bug fixed: aligned repository name in compact output now takes the overhead
#     of the string due to highlight (if any)
# 20160830 (petrillo@fnal.gov) [v2.4]
#   added --ifhaslocalbranch option;
#   --ifhasbranch now looks also to remote branches
# 20161223 (petrillo@fnal.gov) [v2.5]
#   update for bash 4.4.5 (changed `declare -p` output on arrays)
#

BASESCRIPTNAME="$(basename "${BASH_SOURCE[0]}")"
BASESCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
BASESCRIPTVERSION="2.5"

: ${SCRIPTNAME:="$(basename "${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}")"}
: ${SCRIPTDIR:="$(dirname "${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}")"}

: ${BASEDIR:="$(dirname "$(greadlink -f "$BASESCRIPTDIR")")"}

declare -r BeginTag="%"
declare -r EndTag="%"

declare -A TagPatterns TagSources
TagPatterns['PackageName']='PACKAGENAME'
TagSources['PackageName']='TAGVALUE_PACKAGENAME'

TagPatterns['Arguments']='ARGS.*'
TagSources['Arguments']='ArgumentTag'

TagPatterns['Argument']='ARG[0-9]+'
TagSources['Argument']='ArgumentTag'

TagPatterns['NArguments']='NARGS'
TagSources['NArguments']='TAGVALUE_NArguments'


declare -ar LARSOFTCOREPACKAGES=(
	'larcore'
	'lardata'
	'larevt'
	'larsim'
	'larreco'
	'larpandora'
	'lareventdisplay'
	'larana'
	'larexamples'
	'larsoft'
) # LARSOFTCOREPACKAGES[]

declare -r ANSIRESET="\e[0m"
declare -r ANSIREVERSE="\e[7m"
declare -r ANSIUNDERLINE="\e[4m"
declare -r ANSIWHITE="\e[1;37m"
declare -r ANSIRED="\e[31m"
declare -r ANSIBLUE="\e[34m"
declare -r ANSIBROWN="\e[33m"
declare -r ANSIYELLOW="\e[1;33m"
declare -r ANSIBGRED="\e[41m"
declare -r ANSIBGBROWN="\e[43m"
declare -r ANSIBGVIOLET="\e[48;5;219m"
declare -r ANSIBGPINK="\e[48;5;225m"
declare REPONAMECOLOR="${ANSIYELLOW}${ANSIBGBROWN}"
declare HEADERCOLOR="${ANSIUNDERLINE}${ANSIBROWN}"
declare ERRORCOLOR="${ANSIBGRED}${ANSIYELLOW}"

###############################################################################
### help messages
###
function help_base() {
	cat <<-EOH
	Executes a command in all the GIT repositories.
	
	Usage:  ${SCRIPTNAME} [options] [--] command ...
	
	All the command words are substituted for the tags as required by the
	options. For each tag (TAGNAME), the string "%TAGNAME%" (or the one in
	TAGKEY_TAGNAME) is replaced by the value of the variable with
	name TAGVALUE_TAGNAME.
	The exit code is the number of failed commands.
	EOH
	echo
	help_baseoptions
	echo
	help_developtions
	
} # help_base()


function help_baseoptions() {
	cat <<-EOH
	These are some of the options supported by the base script ${SCRIPTNAME}
	relies on.
	For additional options useful to write your own commands,
	ask for '--help=developtions'.
	
	Repository selection options:
	--ifcurrentbranch=BRANCHNAME
	    acts only on repositories whose current branch is BRANCHNAME; it can be
	    specified more than once, in which case the operation will be performed
	    if the current branch is any one of the chosen branches
	--ifhasbranch=BRANCHNAME , --ifhaslocalbranch=BRANCHNAME
	    similar to '--ifcurrentbranch' above, performs the action only if the
	    repository has one of the specified branches; the first form checks all
	    branches, including the remote ones, while the second checks only local
	    ones
	--only=REGEX
	    operates only on the repositories whose name matches the specified REGEX
	--skip=REGEX
	    skips the repositories whose name matches the specified REGEX
	
	Other options:
	--source=SOURCEDIR [from MRB_SOURCES; now: '${mrb_SOURCES}']
	    use SOURCEDIR as base source directory
	--compact[=MODE]
	    do not write the git command; out the output of the command according to
	    MODE:
	    'prepend' (default): "[%PACKAGENAME%] OUTPUT"
	    'line': "[%PACKAGENAME%]\nOUTPUT"
	    'append': "OUTPUT [%PACKAGENAME%]"
	--color[=<false|always|auto>] [always]
	    uses color to write the repository name, unless the mode is "false";
	    also it instructs git to use the specified mode for the color output;
	    "no" is an alias for "false", "yes" is an alias for "always"
	--color
	    equivalent to "--usecolor=no"
	--skipnooutput
	    don't write anything for packages whose output is empty
	--keepnooutput
	    write the header line also for packages whose output is empty
	--quiet , -q
	    does not write package and command
	--fake , --dry-run , -n
	    just prints the command that would be executed
	--stop-on-error , -S
	    the execution is interrupted when a command fails (exit code non-zero);
	    the exit code is the one of the failure
	--debug[=LEVEL]
	    increase verbosity level
	--version , -V
	    prints the version of this script and exits
	--help[=TOPIC], -h , -?
	    prints an help message depending on the TOPIC:
	    'help' [also default]: prints help for the script
	    'base': prints the help for the base script
	    'baseoptions': prints this message
	    'developtions': prints options useful for writing a new script
	    'library': prints information about the library functions and variable
	               made available to the calling scripts
	
	EOH
} # help_baseoptions()


function help_developtions() {
	cat <<-EOH
	Command specification options:
	--tag=TAGNAME
	--tags=TAGNAME[,TAGNAME...]
	    add a tag to the list of tags;
	    note that currently this has no effect since if an element looks like a
	    tag, it is parsed as such anyway; the option is left as legacy
	--git
	    adds "git" as command if it's not the first word of the command already
	
	Command line parsing options:
	--command[=NARGS] command arg arg ...
	    the first argument is assigned as program name for the command;
	    the next NARGS (default 0) arguments are added as command arguments
	--commandarg arg , --commandargs[=NARGS] arg arg ...
	    the next NARGS (default 1) arguments are added as command arguments
	--autodetect-command
	    interprets the arguments as part of the command, starting at the first
	    unknown option or at the first non-option argument; by default,
	    if an option is unsupported an error is printed
	--miscarg arg , --miscargs=NARGS arg arg ...
	    the arguments are specified in a way similar to --commandarg option;
	    each argument is parsed as a script option; if it is not recognized as a
	    supported option, it is assigned to the next ARG# variable, that can be
	    used as tag in the command (see ARG tag in --help=library)
	
	EOH
} # help_developtions()


function help_library() {
	cat <<-EOH
	${BASESCRIPTNAME} provides some environment variables and some functions.
	
	Environment variables:
	PACKAGENAME
	    the name of the repository being processed (e.g. 'larcore')
	LARSOFTCOREPACKAGES [constant]
	    list of ${#LARSOFTCOREPACKAGES[@]} LArSoft core packages:
	    ${LARSOFTCOREPACKAGES[@]}
	ARG#
	    the argument number # (first argument is #1) specified with --miscarg
	NARGS
	    the number of arguments specified with --miscarg
	    (this is also the index of the last available argument)
	
	The command line automatically translates tags in the form '%TAG%':
	PACKAGENAME , ARG# , NARGS
	    substituted with the corresponding variable
	ARGS[<First>-<Last>]
	    substututed with a group of arguments, each on its own;
	    first argument is #1; supported formats are:
	    ARGS : all arguments
	    ARGS<First>- : all arguments starting from <First> included
	    ARGS-<Last> : all arguments up to <Last>, included
	    ARGS<First>-<Last> : subset of arguments between <Firts> and <Last>,
	        both included
	    if a specified argument does not exist, it is not passed
	    (e.g., 'ARGS2-6' on a command with 4 arguments will pass 3 arguments, not 5)
	
	Functions:
	isLArSoftCorePackage [PackageName]
	    returns 0 if the specified package name (\$PACKAGENAME by default)
	    is one of the ${NCorePackages} LArSoft core packages
	
	EOH
} # help_library()



function PrintVersion() {
	if [[ "$SCRIPTNAME" == "$BASESCRIPTNAME" ]]; then
		echo "${BASESCRIPTNAME} v. ${BASESCRIPTVERSION}"
	else
		echo "${SCRIPTNAME}${SCRIPTVERSION:+ v. ${SCRIPTVERSION}} (based on ${BASESCRIPTNAME} v. ${BASESCRIPTVERSION})"
	fi
} # PrintVersion()


###############################################################################
### internal functions
###

function isFlagSet() { local VarName="$1" ; [[ -n "${!VarName//0}" ]]; }
function isFlagUnset() { local VarName="$1" ; [[ -z "${!VarName//0}" ]]; }

function isFunction() { local Name="$1" ; declare -F "$Name" >& /dev/null ; }

function STDERR() { echo "$*" >&2 ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()

function LASTFATAL() {
	local -i Code="$?"
	[[ $Code != 0 ]] && FATAL "$Code" "$@"
} # LASTFATAL()


function PRINTSTACK() {
	local -i SkipTop="${1:-1}"
	local -i StackDepth="${#FUNCNAME[@]}"
	echo "${SCRIPTNAME} calling stack (${StackDepth}):"
	local -i Padding="${#StackDepth}"
	local SourceFile
	local -i iStack
	for (( iStack = $SkipTop ; iStack < $StackDepth - 1 ; ++iStack )); do
		SourceFile="${BASH_SOURCE[iStack]}"
		if [[ "$SourceFile" == "$0" ]]; then
			printf " [#%0*d] function %s  line #%d\n" $Padding $iStack "${FUNCNAME[iStack]}" "${BASH_LINENO[iStack]}"
		else
			printf " [#%0*d] function %s  line #%d (%s)\n" $Padding $iStack "${FUNCNAME[iStack]}" "${BASH_LINENO[iStack]}" "$SourceFile"
		fi
	done
} # PRINTSTACK()

function INTERNALERROR() {
	STDERR "INTERNAL ERROR: $*"
	# print the stack, skipping top 2 entries (PRINTSTACK and INTERNALERROR)
	PRINTSTACK 2
} # INTERNALERROR()

function isDebugging() {
	local -i Level="${1:-1}"
	[[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge $Level ]]
} # isDebugging()

function DBGN() {
	local -i Level="$1"
	shift
	isDebugging "$Level" && STDERR "DBG[${Level}]| $*"
} # DBGN()
function DBG() { DBGN 1 "$@" ; }

function DUMPVAR() {
	local VarName="$1"
	DBG "${VarName}='${!VarName}'"
} # DUMPVAR()

function DUMPVARS() {
	local VarName
	for VarName in "$@" ; do
		DUMPVAR "$VarName"
	done
} # DUMPVARS()


function Pager() {
	# executes the pager
	local PagerProgram="${PAGER:-less}"
	local -a PagerOptions
	if [[ "$(basename "$PagerProgram")" == 'less' ]]; then
		PagerOptions=( '-F' )
	fi
	PagerOptions=( "${PagerOptions[@]}" "$@" )
	"$PagerProgram" "${PagerOptions[@]}"
} # Pager()

function ProcessDeclareArray() {
	#
	# Transforms the output of a declare -p on an array into the declaration of
	# the content of an array, in the form:
	#
	#  [0]='value' [1]='value' ...
	#
	# (one heading and one trailing space are also output)
	#
	local DeclarePrint="$1"
	#
	# The expected pattern is something like:
	#
	#   declare [some flags] [maybe more flags] ArrayName=([0]="value" [1]="value" ... [N]="value")
	#
	# In bash (somewhere) before 4.4.5, there were single quotes before and after
	# the parentheses.
	# 
	local DeclarePattern='^declare( -[[:alnum:]]+)* [[:alnum:]_]+='\''?\((.*)\)'\''?$'
	[[ "$DeclarePrint" =~ $DeclarePattern ]]
	echo " ${BASH_REMATCH[2]} "
} # ProcessDeclareArray()


function ReturnNamedArray() {
	# Callee-side implementation for communicating arrays.
	# This function accepts an array name.
	# 
	# The procedure is that the callee produces a string that Bash can understand
	# as an array. The caller will evaluate assigning it to a local variable.
	# For example:
	# 
	# function Worker() {
	#   local -a MyArray=( "Mark Twain" "Roger Wilco" )
	#   
	#   ReturnNamedArray MyArray
	# } # Worker()
	#
	# function Caller() {
	#   local -a ResultArray
	#   
	#   eval "ResultArray=( $(Worker) )"
	#   echo "Result (${#ResultArray[@]}): ${ResultArray[*]}"
	# } # Caller()
	# 
	# Security issue: if you can confuse the substitution that transforms the
	# output of `declare -p` into its content, you can have this function run
	# arbitrary code.
	# 
	
	local -r ArrayName="$1"
	local -r Result="$(declare -p "$ArrayName")"
	# remove the "declare" part and the brackets
	local -r ArrayValue="${Result#declare* ${ArrayName}=}"
        ProcessDeclareArray "$Result"
} # ReturnNamedArray()


function ReturnArray() {
	# Callee-side implementation for communicating arrays.
	# This function accepts an array content.
	# 
	# The procedure is that the callee produces a string that Bash can understand
	# as an array. The caller will evaluate assigning it to a local variable.
	# For example:
	# 
	# function Worker() {
	#   local -a MyArray=( "Mark Twain" "Roger Wilco" )
	#   
	#   ReturnArray "${MyArray[@]}"
	# } # Worker()
	#
	# function Caller() {
	#   local -a ResultArray
	#   
	#   eval "ResultArray=( $(Worker) )"
	#   echo "Result (${#ResultArray[@]}): ${ResultArray[*]}"
	# } # Caller()
	
	local -ar Values=( "$@" )
	ReturnNamedArray Values
} # ReturnArray()


function ReturnNamedVariable() {
	# Function mirroring ReturnNamedArray for a simple variable.
	# This function accepts a variable name.
	# 
	# The procedure is that the callee produces a string that Bash can understand
	# as a variable. The caller will evaluate assigning it to a local variable.
	# For example:
	# 
	# function Worker() {
	#   local -a MyVar='"Let'"'"'s go!"' # this is "Let's go!" (quotes included)
	#   
	#   ReturnNamedVariable MyVar
	# } # Worker()
	#
	# function Caller() {
	#   local ResultVar
	#   
	#   eval "ResultVar=$(Worker)"
	#   echo "Result (${#ResultVar[@]}): ${ResultVar[*]}"
	# } # Caller()
	# 
	
	local -r VarName="$1"
	local -r Result="$(declare -p "$VarName")"
	# remove the "declare" part and the brackets
	local -r VarValue="${Result#declare* ${VarName}=}"
	echo " ${VarValue} "
	
} # ReturnNamedArray()


function ReturnVariable() {
	# Function mirroring ReturnArray for a simple variable.
	# This function accepts a variable value.
	# 
	# The procedure is that the callee produces a string that Bash can understand
	# as a variable. The caller will evaluate assigning it to a local variable.
	# For example:
	# 
	# function Worker() {
	#   local -a MyVar='"Let'"'"'s go!"' # this is "Let's go!" (quotes included)
	#   
	#   ReturnNamedVariable "$MyVar"
	# } # Worker()
	#
	# function Caller() {
	#   local ResultVar
	#   
	#   eval "ResultVar=$(Worker)"
	#   echo "Result (${#ResultVar[@]}): ${ResultVar[*]}"
	# } # Caller()
	# 
	local -r Values="$1"
	ReturnNamedVariable Values
} # ReturnVariable()


function anyInList() {
	# Usage:  anyInList  Sep Key [Key...] Sep [List Items...]
	
	DBGN 4 "${FUNCNAME[0]} ${@}"
	
	# build the list of keys
	local Sep="$1"
	shift
	local -a Keys
	while [[ $# -gt 0 ]] && [[ "$1" != "$Sep" ]]; do
		Keys=( "${Keys[@]}" "$1" )
		shift
	done
	shift # the first argument was a separator
	
	DBGN 4 "Looking in ${@} for any of keys ${Keys[@]}"
	
	# now to the matching double-loop
	local Item Key
	for Item in "$@" ; do
		for Key in "${Keys[@]}" ; do
			[[ "$Item" == "$Key" ]] || continue
			DBGN 3 "Key '${Key}' found in list"
			return 0
		done
	done
	return 1
} # anyInList()


function MatchTag() {
	#
	# Prints the key of the tag matching the provided text
	#
	
	local Text="$1"
	
	DBGN 1 "Matching tag '${Text}'"
	local TagKey
	for TagKey in "${!TagPatterns[@]}" ; do
		local TagPattern="^${TagPatterns["$TagKey"]}\$"
		DBGN 3 "  against '${TagKey}' ('${TagPattern}')"
		[[ "$Text" =~ $TagPattern ]] || continue
		DBGN 2 "  '${TagPattern}' ('${TagKey}') matched"
		echo "$TagKey"
		return 0
	done
	DBGN 2 "  no tag matched"
	return 1
} # MatchTag()


function DetectSourceDir() {
	local SourceDir="$1"
	while true ; do
		# if we have a suggestion, we indiscriminately follow it
		[[ -n "$SourceDir" ]] && break
		
		# if the detected base directory has a 'srcs' directory, that's it
		local BaseDir="$BASEDIR"
		
		SourceDir="${BaseDir}/srcs"
		[[ -d "$SourceDir" ]] && break
	
		# go through all base directory path to see if there is a 'srcs'
		# subdirectory in any of the parent directories	
		BaseDir="$(pwd)"
		while [[ ! -d "${BaseDir}/srcs" ]] && [[ "$BaseDir" != '/' ]]; do
			BaseDir="$(dirname "$BaseDir")"
		done
		SourceDir="${BaseDir}/srcs"
		[[ -d "$SourceDir" ]] && break
		
		# Bah. Stick to the current directory.
		SourceDir='.'
		break
	done
	echo "$SourceDir"
	[[ -d "$SourceDir" ]]
	return
} # DetectSourceDir()


function ReplaceTag() {
	#
	# Expands a single tag.
	# 
	# ReplaceTag Tag TagKey
	# 
	# Tag is the text included between the tag delimiters.
	# TagKey is the tag class the tag belongs to (for example, 'ARGS4-9' is a
	# tag belonging with the class with key 'Arguments').
	# 
	# Output is in the ReturnNamedArray format.
	#
	local Tag="$1"
	local TagKey="$2"
	
	local TagSource="${TagSources["$TagKey"]}"
	
	local -a NewItems
	if isFunction "$TagSource" ; then
		DBGN 2 "Expanding tag '${Tag}' ('${TagKey}') class with function '${TagSource}'"
		"$TagSource" "$Tag"
	else
		ReturnNamedVariable "$TagSource"
	fi
} # function ReplaceTag()


function ExpandTag() {
	#
	# Expands a single tag, supporting recursion.
	# 
	# ExpandTag  Tag
	#
	local Tag="$1"
	
	local TagKey
	TagKey="$(MatchTag "$Tag")"
	LASTFATAL "No tag supports '${BeginTag}${Tag}${EndTag}'."
	
	local -a ExpandedTag
	DBGN 5 "    ReplaceTag '${Tag}' '${TagKey}'"
	eval "ExpandedTag=( $( ReplaceTag "$Tag" "$TagKey" ) )"
	DBGN 6 "    => ${ExpandedTag[@]}"
	
	ExpandArguments "${ExpandedTag[@]}"
	
} # ExpandTag()


function ExpandArgument() {
	#
	# Expands all the instances of tags in a given atom.
	# 
	# It can support:
	# - simple tag: %TAGNAME%
	# - embedded tag something%TAG1%somethingelse%TAG2%end
	# 
	# If a tag expands to an array, one argument is added for each element in the
	# array.
	#
	local Argument="$1"
	
	DBGN 3 "Expanding argument '${Argument}'"
	# so far, support only the simplest model: single tag
	if [[ "$Argument" =~ ^(.*)${BeginTag}(.*)${EndTag}(.*)$ ]] ; then
		local PreTag="${BASH_REMATCH[1]}"
		local Tag="${BASH_REMATCH[2]}" # that's the stuff matched in parentheses
		local PostTag="${BASH_REMATCH[3]}"
		
		DBGN 6 "    (identified '${PreTag}' <${BeginTag}${Tag}${EndTag}> '${PostTag}'"
		
		local -a ExpandedTags
		eval "ExpandedTags=( $(ExpandTag "$Tag") )"
		
		# recursive expansion of part of the argument after the tag we deal with
		local -a ExpandedPreTags
		eval "ExpandedPreTags=( $(ExpandArgument "$PreTag") )"
		
		local -a DressedTags
		local ExpandedTag
		for ExpandedTag in "${ExpandedTags[@]}" ; do
			local ExpandedPreTag
			for ExpandedPreTag in "${ExpandedPreTags[@]}" ; do
				DressedTags=( "${DressedTags[@]}" "${ExpandedPreTag}${ExpandedTag}${PostTag}" )
			done
		done
		
		ReturnNamedArray DressedTags
	else
		# argument is just a literal; just return it
		ReturnNamedVariable Argument
	fi
} # ExpandArgument()

function ExpandArguments() {
	local -a Arguments=( "$@" )
	
	DBGN 2 "Expanding ${#Arguments[@]} arguments: '${Arguments[@]}'"
	
	local -i res
	local -a ExpandedArgs
	local Argument
	for Argument in "${Arguments[@]}" ; do
		local -a ExpandedArg
		eval "ExpandedArg=( $( ExpandArgument "$Argument" ) )"
		res=$?
		[[ $res != 0 ]] && return $res
		ExpandedArgs=( "${ExpandedArgs[@]}" "${ExpandedArg[@]}" )
	done
	
	ReturnNamedArray ExpandedArgs
} # ExpandArguments()


function ArgumentTag() {
	#
	# Processes a tag substitution with ARG category, fishing in TAGVALUE_ARGS
	#
	# ARG# => substituted with the corresponding TAGVALUE_ARGS[#]
	# ARGS[<First>-<Last>]
	#    substututed with a group of arguments, each on its own;
	#    first argument is #1; supported formats are:
	#    ARGS : all arguments
	#         ARGS<First>- : all arguments starting from <First> included
	#    ARGS-<Last> : all arguments up to <Last>, included
	#    ARGS<First>-<Last> : subset of arguments between <Firts> and <Last>,
	#        both included
	#    if a specified argument does not exist, it is not passed
	#    (e.g., 'ARGS2-6' on a command with 4 arguments will pass 3 arguments,
	#    not 5)
	# 
	
	local Tag="$1"
	
	if [[ "$Tag" =~ ^ARG([0-9]+)$ ]]; then
		local -i NArg=${BASH_REMATCH[1]}-1
		DBGN 2 "  ARG tag '${Tag}' returning argument #${NArg}"
		ReturnVariable "${TAGVALUE_ARGS[NArg]}"
	elif [[ "$Tag" == 'ARGS' ]]; then
		DBGN 2 "  ARG tag '${Tag}' returning all ${#TAGVALUE_ARGS[@]} arguments"
		ReturnArray "${TAGVALUE_ARGS[@]}"
	elif [[ "$Tag" =~ ^ARGS([0-9]*)-([0-9]*)$ ]]; then
		if [[ -z "${BASH_REMATCH[1]}" ]] && [[ -z "${BASH_REMATCH[2]}" ]]; then
			FATAL 1 "Invalid ARGS range tag specification: '${Tag}'; for all arguments, use just '${BeginTag}ARGS${EndTag}'"
		fi
		local -i FirstArg LastArg
		if [[ -n "${BASH_REMATCH[1]}" ]]; then
			FirstArg=${BASH_REMATCH[1]}-1
		else
			FirstArg=0
		fi
		if [[ -n "${BASH_REMATCH[2]}" ]]; then
			LastArg=${BASH_REMATCH[2]}-1
		else
			LastArg=${#TAGVALUE_ARGS[@]}-1
		fi
		if [[ $LastArg -lt $FirstArg ]]; then
			FATAL 1 "Invalid ARGS range tag specification: '${Tag}'"
		fi
		local -i NArgs=LastArg-FirstArg+1
		DBGN 2 "  ARG tag '${Tag}' returning arguments between ${FirstArg} and ${LastArg} included"
		ReturnArray "${TAGVALUE_ARGS[@]:FirstArg:NArgs}"
	else
		FATAL 1 "Invalid ARG tag specification: '${Tag}'"
	fi
} # ArgumentTag()


function useColorInScript() {
	[[ "$ColorMode" == "always" ]] || [[ "$ColorMode" == "auto" ]]
} # useColorInScript()

function ColorMsg() {
	local ColorCode="${1%COLOR}COLOR"
	shift
	local Msg="$*"
	if useColorInScript ; then
		echo -en "${!ColorCode}${Msg}${ANSIRESET}"
	else
		echo -n "$Msg"
	fi
} # ColorMsg()

function PrepareHeader() {
	local Specs="$1"
	local Content="$2"
	local HighlightedContent="$(ColorMsg HEADER "$2")"
  local -i HighlightOverhead=$(( ${#HighlightedContent} - ${#Content} ))
	
	local Format
	case "${Specs:0:1}" in
		( '-' )
			Format="%-$((HighlightOverhead + ${Specs:1}))s"
			;;
		( '+' )
			Format="%$((HighlightOverhead + ${Specs:1}))s"
			;;
		( * )
			Format="%s\n"
			;;
	esac
	printf "$Format" "$HighlightedContent"
} # PrepareHeader()


function GetCurrentBranch() {
	# Usage:  GetCurrentBranch  [RepoDir]
	local RepoDir="$1"
	
	if [[ -n "$RepoDir" ]]; then
		pushd "$RepoDir" > /dev/null || return $?
	fi
	
	# get the short reference for current HEAD on screen;
	# that is, the current branch
	git rev-parse --abbrev-ref HEAD
	
	[[ -n "$RepoDir" ]] && popd > /dev/null
	return 0
} # GetCurrentBranch()


function GetLocalBranches() {
	# Usage:  GetLocalBranches  [RepoDir]
	local RepoDir="$1"
	
	if [[ -n "$RepoDir" ]]; then
		pushd "$RepoDir" > /dev/null || return $?
	fi
	
	# get the short reference for current HEAD on screen;
	# that is, the current branch
	git for-each-ref --format='%(refname:short)' refs/heads/
	
	[[ -n "$RepoDir" ]] && popd > /dev/null
	return 0
} # GetLocalBranches()


function GetRemoteBranches() {
	# Usage:  GetRemoteBranches  [RepoDir]
	#
	# Each branch name is prepended by its remote repository
	#
	local RepoDir="$1"
	
	if [[ -n "$RepoDir" ]]; then
		pushd "$RepoDir" > /dev/null || return $?
	fi
	
	# list all the head references (no tags) from remote repositories;
	# the format is: <commit><tab>ref/heads/<remoteRepo>/<branch/path>
	# and the following line reports the "<remoteRepo>/<branch/path>", one per line;
	# git also prints which remote references come from into stderr, which we discard
	git ls-remote --heads 2> /dev/null | sed -E -e 's@.*[[:blank:]]+refs/heads/@@g'
	
	[[ -n "$RepoDir" ]] && popd > /dev/null
	return 0

} # GetRemoteBranches()


function isGoodRepo() {
	local Dir="$1"
	[[ -d "$Dir" ]] || return 1
	[[ -d "${Dir}/.git" ]] || return 1
	
	local RepoName="$(basename "$Dir")"
	
	DBGN 2 "Checking if repository '${RepoName}' should be processed..."
	
	local CurrentBranch
	if [[ "${#OnlyIfCurrentBranches[@]}" -gt 0 ]]; then
		[[ -z "$CurrentBranch" ]] && CurrentBranch="$(GetCurrentBranch "$Dir")"
		DBGN 2 "Current branch of ${RepoName}: '${CurrentBranch}'"
		
		anyInList -- "${OnlyIfCurrentBranches[@]}" -- "$CurrentBranch" || return 1
	fi
	
	if [[ "${#OnlyIfHasBranches[@]}" -gt 0 ]]; then
		local -a AllBranches=( $(GetLocalBranches "$Dir") )
		DBGN 2 "${#AllBranches[@]} local branches of ${RepoName}: ${AllBranches[@]}"
		isFlagSet OnlyLocalBranches || AllBranches=( "${AllBranches[@]}" $(GetRemoteBranches "$Dir") )
		DBGN 2 "${#AllBranches[@]} branches of ${RepoName}: ${AllBranches[@]}"
		
		anyInList -- "${OnlyIfHasBranches[@]}" -- "${AllBranches[@]}" || return 1
	fi
	
	if [[ "${#OnlyRepos[@]}" -gt 0 ]]; then
		DBGN 2 "Checking ${#OnlyRepos[@]} repository name patterns"
		local -i nMatches=0
		local Pattern
		for Pattern in "${OnlyRepos[@]}" ; do
			if [[ "$RepoName" =~ $Pattern ]]; then
				let ++nMatches
				DBGN 3 "Repository '${RepoName}' matches '${Pattern}'"
				break
			else
				DBGN 3 "Repository '${RepoName}' does not match '${Pattern}'"
			fi
		done
		if [[ "$nMatches" == 0 ]]; then
			DBGN 2 "Repository '${RepoName}' does not match any pattern: skipped!"
			return 1
		fi
	fi
	
	if [[ "${#SkipRepos[@]}" -gt 0 ]]; then
		DBGN 2 "Checking ${#SkipRepos[@]} repository name skip patterns"
		local Pattern
		for Pattern in "${SkipRepos[@]}" ; do
			[[ "$RepoName" =~ $Pattern ]] || continue
			DBGN 3 "Repository '${RepoName}' matches '${Pattern}': skipped!"
			return 1
		done
		DBGN 2 "Repository '${RepoName}' does not match any skip pattern."
	fi
	
	return 0
} # isGoodRepo()


function AddToCommand() {
	if [[ -z "$ProgramName" ]]; then
		ProgramName="$1"
		DBGN 1 "Program name set to '${ProgramName}'"
		shift
	fi
	DBGN 1 "Adding ${#} arguments to the command: ${@}"
	ProgramArgs=( "${ProgramArgs[@]}" "$@" )
} # AddToCommand()


function PullCommand() {
	#
	# Returns the full command. Result is in ReturnNamedArray format
	#
	ReturnArray "$ProgramName" "${ProgramArgs[@]}"
} # PullCommand()


function isGit() {
	isFlagSet AddGit || [[ "$(basename -- "$ProgramName")" == "git" ]]
} # isGit()


function AddGitOptions() {
	# if it's not a git command, don't do anything here
	isGit || return
	
	DBGN 3 "Adding 'git' to command: ${ProgramName} ${ProgramArgs[@]}"
	
	# add 'git' as a command, unless it's there already
	if [[ "$(basename -- "$ProgramName")" != "git" ]]; then
		ProgramArgs=( "$ProgramName" "${ProgramArgs[@]}" )
		ProgramName='git'
	fi
	
	# add the color option
	if [[ -n "$ColorMode" ]]; then
		ProgramArgs=( '-c' "color.ui=${ColorMode}" "${Command[@]:1}" "${ProgramArgs[@]}" )
	fi
} # AddGitOptions()


function PrintHelp() {
	#
	# Prints help according to the requested topic
	#
	local HelpTopic="$1"
	
	DBGN 1 "Help for topic: '${HelpTopic}'"
	case "$HelpTopic" in
		( 'help' ) # run a user-defined 'help' if present
			if isFunction help ; then
				help
			else
				help_base
			fi
			;;
		( '' )
			return 1 ;; # no help requested
		( * )
			local HelpFuncName="help_${HelpTopic}"
			isFunction HelpFuncName || FATAL 1 "Unknown help topic: '${HelpTopic}'"
			HelpFuncName
	esac | Pager
	exit
} # PrintHelp()


################################################################################
### Command line parser
###

function SetDefaultOptions() {
	#
	# Sets the dsefault option values before command line parsing takes place
	#
	DBGN 2 "Setting up the default options"
	# TODO waiting for bash version supporting 'declare -g' option
	CompactMode='normal'
	ColorMode='always'
	NoMoreOptions=0
	AutodetectCommand=0
	SkipEmptyOutput=0
	OnlyLocalBranches=0
	ProgramName=""
	ProgramArgs=( )
	OnlyIfCurrentBranches=( )
	OnlyIfHasBranches=( )
	OnlyRepos=( )
	SkipRepos=( )
} # SetDefaultOptions()

function StandardOptionParser() {
	#
	# Parses known options.
	# 
	# ParseOption iParam Params...
	# 
	# The iParam-th option (0-based) among Params is parsed.
	# The return value is the number of consumed options, that is usually 1.
	# A return value of 0 means that the parameter is not a supported option.
	#
	local -ir iTargetParam=$1
	shift
	local -a Params=( "$@" )
	
	# iParam points to the next unprocessed parameter
	# (it happens to be also the 1-based index of the option being processed)
	local -i iParam=$iTargetParam
	local Param="${Params[iParam++]}"
	case "$Param" in
		( "--fake" | "--dry-run" | "-n" )
			FAKE=1
			;;
		( "--quiet" | "-q" )
			CompactMode='quiet'
			;;
		( "--git" )
			AddGit=1
			;;
		( "--command" | '--command='* )
			NDefaultArgs=0
			[[ -z "$ProgramName" ]] || FATAL "command was already specified as '${ProgramName}', attempted to assign it again (argument #${iParam}: '${Param}')"
			# if no command is present yet, store the first element as such
			AddToCommand "${Params[iParam]}"
			let ++iParam
			;& # this means: execute the next block too
		( "--commandarg" | '--commandargs='* ) # note: it could follow from previous case
			[[ "$Param" =~ ^--commandarg ]] && NDefaultArgs=1
			NArgs="${Param#--*=}"
			[[ "$NArgs" == "$Param" ]] && NArgs=$NDefaultArgs
			AddToCommand "${Params[@]:iParam:NArgs}"
			DBGN 3 "Command is now: ${ProgramName} ${ProgramArgs[@]}"
			let iParam+=$NArgs
			;;
		( "--miscarg" | '--miscargs='* )
			NArgs="${Param#--*=}"
			[[ "$NArgs" == "$Param" ]] && NArgs=1
			DBGN 2 "Adding ${NArgs} mixed arguments"
			MiscArguments=( "${MiscArguments[@]}" "${Params[@]:iParam:NArgs}" )
			let iParam+=$NArgs
			DBGN 3 "Miscellaneous arguments are now: ${MiscArguments[@]}"
			;;
		( '--autodetect-command' )
			AutodetectCommand=1
			;;
		( '--source='* )
			SourceDir="${Param#--*=}"
			;;
		( '--ifcurrentbranch='* )
			OnlyIfCurrentBranches=( "${OnlyIfCurrentBranches[@]}" "${Param#--*=}" )
			;;
		( '--ifhasbranch='* )
			OnlyIfHasBranches=( "${OnlyIfHasBranches[@]}" "${Param#--*=}" )
			;;
		( '--ifhaslocalbranch='* )
			OnlyIfHasBranches=( "${OnlyIfHasBranches[@]}" "${Param#--*=}" )
			OnlyLocalBranches=1
			;;
		( '--only='* )
			OnlyRepos=( "${OnlyRepos[@]}" "${Param#--*=}" )
			;;
		( '--skip='* )
			SkipRepos=( "${SkipRepos[@]}" "${Param#--*=}" )
			;;
		( "--compact" )
			CompactMode='prepend'
			;;
		( "--compact="* )
			CompactMode="${Param#--compact=}"
			;;
		( "--color" )
			ColorMode="$(ParseColorOption "always")"
			;;
		( "--nocolor" )
			ColorMode="$(ParseColorOption "no")"
			;;
		( "--color="* )
			ColorMode="$(ParseColorOption "${Param#--*=}")"
			;;
		( '--skipnooutput' )
			SkipEmptyOutput=1
			;;
		( '--keepnooutput' )
			SkipEmptyOutput=0
			;;
		( "--tag="* )
			Tags=( "${Tags[@]}" "${Param#--tag=}" )
			;;
		( "--tags="* )
			NewTags="${Param#--tags=}"
			Tags=( "${Tags[@]}" ${NewTags//,/ } )
			;;
		( '--stop-on-error' | '-S' )
			StopOnError=1
			;;
		( '--debug='* )
			DEBUG="${Param#--*=}"
			;;
		( '--debug' | '-d' )
			DEBUG=1
			;;
		( '--version' | '-V' )
			DoVersion=1
			;;
		( '--help='* )
			HelpTopic="${Param#--*=}"
			;;
		( '--help' | '-?' | '-h' )
			HelpTopic='help'
			;;
		( '-' | '--' )
			NoMoreOptions=1
			;;
		( * )
			return 0
	esac
	return $((iParam - iTargetParam))
} # StandardOptionParser()


function ParseColorOption() {
	local Option="$1"
	local Mode="$ColorMode"
	case "${Option,,}" in
		( 'always' | 'yes' ) Mode="always" ;;
		( 'auto' )           Mode="auto" ;;
		( 'false' | 'no' )   Mode="false" ;;
		( * )                FATAL 1 "Value '${Option}' is not a supported color mode"
	esac
	echo "$Mode"
} # ParseColorOption()


################################################################################
### library functions
###
function isLArSoftCorePackage() {
	local Package="${1:-${PACKAGENAME}}"
	if [[ -z "$Package" ]]; then
		INTERNALERROR "Internal error: no Package variable provided!"
		return 2
	fi
	local CorePackage
	for CorePackage in "${LARSOFTCOREPACKAGES[@]}" ; do
		DBGN 4 "Is '${Package}' the core package '${CorePackage}'?"
		[[ "$Package" == "$CorePackage" ]] && return 0
	done
	return 1
} # isLArSoftCorePackage()

################################################################################
### parameters parser
###
SetDefaultOptions
declare -a OptionParsers # might exist already
# add StandardOptionParser to the end of the parsers, if not present already
anyInList -- 'StandardOptionParser' -- "${OptionParsers[@]}" || OptionParsers=( "${OptionParsers[@]}" 'StandardOptionParser' )

DUMPVARS ColorMode NoMoreOptions

declare -i iParam=0
declare -a Params=( "$@" )
declare -ir NParams=${#Params[@]}
DBGN 1 "Processing ${NParams} arguments: ${Params[@]}"
while [[ iParam -lt $NParams ]]; do
	Param="${Params[iParam]}"
	DBGN 2 "Parsing argument [${iParam}]: '${Param}'"
	if isFlagUnset NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		
		for OptionParser in "${OptionParsers[@]}" ; do
			DBGN 2 "  parsing options with: ${OptionParser}"
			"$OptionParser" "$iParam" "${Params[@]}"
			nProcessedParams=$?
			let iParam+=$nProcessedParams
			if [[ $nProcessedParams -gt 0 ]]; then
				DBGN 3 "    ${OptionParser} processed ${nProcessedParams} arguments"
				continue 2 # option processed, go to next
			fi
		done
		
		# if it's unknown, then it's an error
		isFlagSet AutodetectCommand || FATAL 1 "Unknown option '${Param}'"
		# interpret this option and the rest of the arguments
		# as part of the command:
	fi
	DBGN 2 "Adding all remaining arguments from [${iParam}] ('${Param}') on"
	AddToCommand "${Params[@]:iParam:$NParams}"
	break
done

declare -ir NMiscArguments="${#MiscArguments[@]}"
DBGN 1 "Processing ${NMiscArguments} miscellaneous arguments: ${MiscArguments[@]}"
iParam=0
NoMoreOptions=0
while [[ iParam -lt $NMiscArguments ]]; do
	Param="${MiscArguments[iParam]}"
	DBGN 2 "Parsing miscellaneous argument [${iParam}]: '${Param}'"
	
	for OptionParser in "${OptionParsers[@]}" ; do
		DBGN 2 "  parsing options with: ${OptionParser}"
		"$OptionParser" "$iParam" "${MiscArguments[@]}"
		nProcessedParams=$?
		let iParam+=$nProcessedParams
		if [[ $nProcessedParams -gt 0 ]]; then
			DBGN 3 "    ${OptionParser} processed ${nProcessedParams} arguments"
			continue 2 # option processed, go to next
		fi
	done
	
	DBGN 2 "  adding it as argument #${TAGVALUE_NArguments}"
	TAGVALUE_ARGS[TAGVALUE_NArguments++]="$Param"
	let ++iParam
done

AddGitOptions

if isFlagSet DoVersion ; then
	PrintVersion
	exit
fi

[[ -n "$HelpTopic" ]] && PrintHelp "$HelpTopic"


################################################################################
### get to the right directory
### 
SRCDIR="$(DetectSourceDir "$SourceDir")"
DBGN 2 "Source directory: '${SRCDIR}'"

################################################################################
### execute the commands
###

declare -a Command
eval "Command=( $(PullCommand) )"

DBG  "Command: ${Command[@]}"

declare -i nErrors=0
for Dir in "$SRCDIR"/* ; do
	
	isGoodRepo "$Dir" || continue
	
	PACKAGENAME="$(basename "$Dir")"
	
	pushd "$Dir" > /dev/null
	
	# replacement variables
	eval "${TagSources['PackageName']}=\"${PACKAGENAME}\""
	
	DBGN 1 "${PACKAGENAME}: Expanding "${#Command[@]}" arguments: ${Command[@]}"
	
	declare -a PackageCommand
	eval "PackageCommand=( $( ExpandArguments "${Command[@]}" ) )"
	
	declare Output
	if ! isFlagSet FAKE ; then
		Output="$( "${PackageCommand[@]}" 2>&1 )"
		res=$?
	else
		res=0
	fi
	
	if isFlagUnset SkipEmptyOutput || [[ -n "$Output" ]]; then
		
		case "$CompactMode" in
			( 'quiet' )
				[[ -n "$Output" ]] && echo "$Output"
				;;
			( 'prepend'* )
				Header="$(PrepareHeader "${CompactMode#prepend}" "[${PACKAGENAME}]")"
				echo -n "${Header} ${Output}"
				[[ $res != 0 ]] && echo -n " $(ColorMsg ERROR "(exit code: ${res})")"
				echo
				;;
			( 'line' )
				ColorMsg HEADER "[${PACKAGENAME}]" && echo
				[[ -n "$Output" ]] && echo "$Output"
				[[ $res != 0 ]] && echo " $(ColorMsg ERROR "(exit code: ${res})")"
				;;
			( 'append'* )
				Header="$(PrepareHeader "${CompactMode#append}" "[${PACKAGENAME}]")"
				echo -n "${Output} ${Header}"
				[[ $res != 0 ]] && echo " $(ColorMsg ERROR "(exit code: ${res})")"
				echo
				;;
			( * )
				echo -n "$(ColorMsg REPONAME $PACKAGENAME)$(ColorMsg HEADER ": ${PackageCommand[*]}")"
				[[ $res != 0 ]] && echo -n " $(ColorMsg ERROR "[exit code: ${res}]")"
				echo
				[[ -n "$Output" ]] && echo "$Output"
		esac
	fi
	
	isFlagSet StopOnError && [[ $res != 0 ]] && exit "$res"
	
	[[ $res != 0 ]] && let ++nErrors
	popd > /dev/null
done

exit $nErrors
