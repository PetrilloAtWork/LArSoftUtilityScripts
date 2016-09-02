    #!/usr/bin/env bash
#
# Brief:  Utility library for LArSoft scripts.
# Author: Gianluca Petrillo (petrillo@fnal.gov)
# 
# 
# Requires bash 4 or OSX 10.10 (with bash 3 because Apple sucks).
# This file can be safely sourced multiple time.
# 
# This library should be sourced in a script.
# Scripts should be preambled by:
#     
#     hasLArSoftScriptUtils >& /dev/null || source "${LARSCRIPTDIR}/larsoft_scriptutils.sh"
#     
# (or you might want to do something to autodetect LARSCRIPTDIR location).
# 
# Changes:
# 20160810 (petrillo@fnal.gov) [v1.0]
#   first version: collecting my code from elsewhere
#


################################################################################

function hasLArSoftScriptUtils() {
  #
  # Usage example:
  #     
  #     hasLArSoftScriptUtils >& /dev/null || source "${LARSCRIPTDIR}/larsoft_scriptutils.sh"
  #     
  # (rely on the fact that if the utilities are not loaded, hasLArSoftScriptUtils
  # is undefined and the command will cause a "command not found" error)
  #
  [[ -n "$LARSOFTSCRIPTUTILS_VERSION" ]] # just because
} # hasLArSoftScriptUtils()



################################################################################
###  Basic bash programming utilities
################################################################################

function isNameSet() {
  #
  # isNameSet Name
  # 
  # Returns whether Name is declared in bash
  #
  local Name="$1"
  declare -p "$Name" >& /dev/null
} # isNameSet()


function isFunctionSet() {
  #
  # isFunctionSet Name
  # 
  # Returns whether Name is declared as a bash function 
  #
  local FunctionName="$1"
  declare -F "$FunctionName" >& /dev/null
} # isFunctionSet()


function isVariableSet() {
  #
  # isVariableSet Name
  # 
  # Returns whether Name is declared in bash as a variable (not a function)
  #
  local Name="$1"
  isNameSet "$Name" && ! isFunctionSet "$Name"
} # isVariableSet()



function isFlagSet() {
  #
  # isFlagSet VarName
  # 
  # Returns whether VarName is a variable set to a non-zero value
  #
  local VarName="$1"
  [[ -n "${!VarName//0}" ]]
} # isFlagSet()


function isFlagUnset() {
  #
  # isFlagUnset VarName
  # 
  # Returns whether VarName is not set or set to a variable with a zero value
  #
  local VarName="$1"
  [[ -z "${!VarName//0}" ]]
} # isFlagUnset()


function anyFlagSet() {
  #
  # anyFlagSet  VarName [VarName ...]
  #
  # Returns whether at least one of the specified flags VarName is set
  #
  local FlagName
  for FlagName in "$@" ; do
    isFlagSet "$FlagName" && return 0
  done
  return 1
} # anyFlagSet()



function StringLength() {
  #
  # Usage:  StringLength "String"
  # 
  # Prints the length of the specified string. Example:
  #     
  #     declare -i Padding="$(StringLength $(( NItems - 1 )) )"
  #     
  #
  local String="$1"
  echo "${#String}"
} # StringLength()


#-------------------------------------------------------------------------------
#---  Numeric parsing
#---

function isNonNegativeInteger() {
  local Number="$1"
  [[ "$Number" =~ ^\+*[0-9]+$ ]]
} # isNonNegativeInteger()

function isInteger() {
  local Number="$1"
  [[ "$Number" =~ ^[+-]*[0-9]+$ ]]
} # isInteger()

function isNonNegativeRealNumber() {
  local Number="$1"
  Number="${Number/.}" # we can accept one decimal point
  isInteger "$Number"
} # isNonNegativeRealNumber()

function isRealNumber() {
  local Number="$1"
  Number="${Number#-}" # may have a sign
  isNonNegativeRealNumber "$Number"
} # isRealNumber()

function isPositiveInteger() {
  local Number="$1"
  isInteger "$Number" && [[ "$Number" -gt 0 ]]
} # isPositiveInteger()


function Max() {
  #
  # Max  Number [Number ...]
  # 
  # Prints the largest among the specified integral values.
  # If a value is not an integer (see isInteger) it is skipped, and the return
  # value will be 1 (that is, an error).
  # If no value is specified, the return value is also an error.
  # If there is no good value, nothing is printed; otherwise, the largest among
  # the valid numbers is printed.
  #
  [[ $# == 0 ]] && return 1
  local -i errors=0
  local -i good=0
  local -i max
  local -i elem
  for elem in "$@" ; do
    isInteger "$elem" || continue
    if [[ $good == 0 ]]; then
      max=$elem
    else
      [[ $elem -gt $max ]] && max="$elem"
    fi
    let ++good
  done
  [[ $good -gt 0 ]] && echo "$max"
  [[ $good == $# ]] # return value: all elements were good integers
} # Max()



################################################################################
###  Console output
################################################################################

# some ANSI terminal color codes
declare -rx \
  ANSIRESET="\e[0m" \
  ANSIRED="\e[1;31m" \
  ANSIGREEN="\e[0;32m" \
  ANSIYELLOW="\e[1;33m" \
  ANSICYAN="\e[36m" \
  ANSIGRAY="\e[1;30m" \
  ANSIWHITE="\e[1;37m"


function ApplyMessageColor() {
  #
  # Wraps the message in the specified colour
  # 
  # Usage:  ApplyMessageColor  ColorVarName Message...
  # 
  # ColorVarName is the name of a variable whose value is the ANSI sequence
  # enabling a colour. If the variable name is empty, no colour will be applied,
  # but the colour will still be reset at the end of the message.
  # 
  # Some conditional colour names are declared in SetColors().
  #
  local ColorName="$1"
  shift
  echo -e "${ColorName:+${!ColorName}}${*}${ResetColor}"
} # ApplyMessageColor()



# functions are always redefined
function STDERR() {
  #
  # Usage:  STDERR string [string ...]
  # 
  # Prints a string on standard error.
  #
  echo -e "$*" >&2
} # STDERR()

function STDERRCOLOR() {
  #
  # Usage:  STDERR string [string ...]
  # 
  # Prints a string on standard error.
  #
  local ColorName="$1"
  shift
  echo -e "$(ApplyMessageColor '$ColorName' "$@")" >&2
} # STDERRCOLOR()

function INFO() {
  #
  # Usage:  INFO  message
  # 
  # Prints a message on standard error (highlighted).
  #
  STDERRCOLOR InfoColor "$*"
} # INFO()

function WARN() {
  #
  # Usage:  WARN  message
  # 
  # Prints an warning message on standard error.
  #
  STDERRCOLOR WarnColor "Warning: $*"
} # WARN()

function ERROR() {
  #
  # Usage:  ERROR  message
  # 
  # Prints an error message on standard error.
  #
  STDERRCOLOR ErrorColor "Error: $*"
} # ERROR()

function FATAL() {
  #
  # Usage:  FATAL  ExitCode Message
  #
  # Exits with the specified code printing the specified error message.
  # Note that if the script is being sourced, FATAL will not terminate it.
  # To have the script exit while executing a instruction not in a function,
  # you can still do something like:
  #     
  #     [[ -n "$Var" ]] || FATAL 1 "Variable not set!" && return 1
  #     
  # If within a function, there is no way to terminate the script being sourced
  # without terminating the shell itself (not that I know of, at least).
  # Or else this function would be doing exactly that!
  # 
  local Code="$1"
  shift
  STDERRCOLOR FatalColor "Fatal error (${Code}): $*"
  if isSourcing ; then
    return $Code
  else
    exit $Code
  fi
} # FATAL()

function LASTFATAL() {
  #
  # Usage:  LASTFATAL Message
  #
  # Exits with the specified error message if the previous command returned a
  # non-zero exit code (exit code is propagated).
  #
  local Code="$?"
  [[ "$Code" != 0 ]] && FATAL $Code $*
} # LASTFATAL()


function SetColors() {
  # call this after you know if you want colours or not
  local UseColors="${1:-${USECOLORS:-1}}"
  if isFlagSet UseColors ; then
    DBGN 10 "Setting output colors..."
    ErrorColor="$ANSIRED"
    FatalColor="$ANSIRED"
    WarnColor="$ANSIYELLOW"
    DebugColor="$ANSIGREEN"
    InfoColor="$ANSICYAN"
    ResetColor="$ANSIRESET"
  else
    DBGN 10 "Unsetting output colors..."
    ErrorColor=
    FatalColor=
    WarnColor=
    DebugColor=
    InfoColor=
    ResetColor=
  fi
} # SetColors()



#-------------------------------------------------------------------------------
#--- debug messages
#--- 

function isDebugging() {
  #
  # Usage:  isDebugging  [Level]
  # 
  # Returns whether debug messages of the specified level (default: 1) or lower
  # should be printed.
  #
  
  local -i DebugLevel="${1:-1}"
  [[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge "$DebugLevel" ]]  
  
} # isDebugging()


function DBG() {
  #
  # Usage:  DBG  Message
  # 
  # Prints a debugging message.
  #
  isDebugging && STDERR "${DebugColor}DBG| $*${ResetColor}"
} # DBG()

function DBGN() {
  #
  # Usage:  DBGN  Level Message
  # 
  # Prints a debugging message with the specified level.
  # Debug message is displayed if the debug verbosity level is not lower
  # than the message level.
  # 
  local -i DebugLevel="$1"
  shift
  [[ -n "$DEBUG" ]] && [[ "$DEBUG" -ge "$DebugLevel" ]] && DBG "$*"
} # DBGN()


function DUMPVAR() {
  #
  # Usage:  DUMPVAR  VarName
  #
  # Prints the value of the specified variable as debug message.
  #
  local VarName="$1"
  DBG "'${VarName}'='${!VarName}'"
} # DUMPVAR()

function DUMPVARS() {
  #
  # Usage:  DUMPVARS  VarName [VarName ...]
  #
  # Prints the value of all the specified variables as debug message.
  #
  local VarName
  for VarName in "$@" ; do
    DUMPVAR "$VarName"
  done
} # DUMPVARS()


function PrintBashCallStack() {
  #
  # PrintBashCallStack [Levels]
  #
  # Prints a list of the callers of the current function (this one excluded).
  # Prints at most Levels callers, or all of them if not specified or non-positive.
  # It always prints at least one caller (if available).
  #
  local -i Limit=${1:-"0"}
  local -i StackFrameNo=0
  while caller $((++StackFrameNo)) ; do [[ $StackFrameNo == $Limit ]] && break ; done
  return 0
} # PrintBashCallStack()



################################################################################
###  Sourcing utilities
################################################################################

function isSourcing() {
  # returns whether the current script is being sourced
  [[ "$0" == 'bash' ]] && [[ "$BASH_SOURCE" != "$0" ]]
} # isSourcing()


function isNotSourcing() {
  # returns whether the current script is not being sourced
  ! isSourcing 
} # isNotSourcing()


function mustBeSourced() {
  # Exits (with the specified error message) if the script is not being sourced
  local Msg="${1:-"The script $(basename "$0") needs to be sourced."}"
  
  isSourcing || LASTFATAL "$Msg"
  
} # mustBeSourced()


function mustNotBeSourced() {
  # Prints an error and returns an error code of script is being sourced.
  # 
  # We can't exit the script, so the usage should be:
  #     
  #     mustNotBeSourced || return 1
  #     
  local Msg="${1:-"The script $(basename "$0") must not be sourced."}"
  
  isNotSourcing && return
  
  FATAL 1 "$Msg"
} # mustNotBeSourced()



################################################################################
###  Paths
################################################################################

#-------------------------------------------------------------------------------
#---  Path manipulation
#---

function isAbsolutePath() {
  #
  # Usage:  isAbsolutePath  Path
  #
  # Returns whether specified path is absolute.
  #
  
  local Path="$1"
  [[ "${Path:0:1}" == '/' ]]
  
} # isAbsolutePath()


function MakeAbsolutePath() {
  #
  # Usage:  MakeAbsolutePath  Path [BaseDir]
  #
  # Prints an absolute path. If Path is already absolute, it is directly
  # printed. Otherwise, BaseDir (default: current directory) is prepended to
  # Path and the joint path is printed.
  #
  
  local Path="$1"
  local BaseDir="$2"
  if isAbsolutePath "$Path" ; then
    echo "$Path"
  else
    JoinPaths "${BaseDir:-$(pwd)}" "$Path"
  fi
  
} # MakeAbsolutePath()


function AppendSlash() {
  #
  # Usage:  AppendSlash  Path
  # 
  # Prints Path, with a '/' added at the end if Path does not have one already.
  #
  local DirName="$1"
  if [[ -n "$DirName" ]]; then
    echo "${DirName%%/}/"
  else
    echo
  fi
} # AppendSlash()


function RemoveSlash() {
  #
  # Usage:  RemoveSlash  Path
  # 
  # Prints Path, without any trailing '/' (unless the path is '/')
  #
  local DirName="$1"
  if [[ -z "$DirName" ]]; then
    echo
  elif [[ -z "${DirName%%/}" ]]; then
    echo '/'
  else
    echo "${DirName%%/}"
  fi
} # RemoveSlash()


function RemoveMultipleSlashes() {
  #
  # Usage:  RemoveMultipleSlashes  Path
  # 
  # Prints Path, with at most one trailing '/'
  #
  local DirName="$1"
  if [[ "${DirName: -1}" != '/' ]]; then
    echo "$DirName"
  else
    echo "${DirName%%/}/"
  fi
} # RemoveMultipleSlashes()


function JoinPaths() {
  #
  # Usage:  JoinPaths  Path [Path ...]
  #
  # Concatenates the specified paths into one.
  #
  
  local -a Paths=( "$@" )
  local -i NPaths="${#Paths[@]}"
  
  local JointPath
  local -i iPath
  for (( iPath = 0 ; iPath < NPaths ; ++iPath )); do
    JointPath="$( AppendSlash "$JointPath" )${Paths[iPath]}"
  done
  echo "$JointPath"
  
} # JoinPaths()


function InsertPath() {
  #
  # InsertPath [options] VarName Path [Path ...]
  #
  # Insert paths to a list of paths separated by a separator in VarName.
  # The resulting list is printed out.
  #
  # Options:
  # -s SEP     specify the separation string (default: ':')
  # -1 (number!) don't allow for duplicate items (existing and added)
  # -m         allow for duplicate items (default)
  # -a         append (default)
  # -p         prepend
  # -e         add only if existing
  # -d         add only if existing directory
  #
  local Option Separator=':' Prepend=0 AllowDuplicates=1 Move=0
  local -a Checks
  OPTIND=1
  while getopts "ed1Dmaps:-" Option ; do
    case "$Option" in
      ( 'e' | 'd' ) Checks=( "${Checks[@]}" "-${Option}" ) ;;
      ( '1' ) AllowDuplicates=0 ;;
      ( 'D' ) AllowDuplicates=1 ;;
      ( 'm' ) Move=1 ;;
      ( 'a' ) Prepend=0 ;;
      ( 'p' ) Prepend=1 ;;
      ( 's' ) Separator="$OPTARG" ;;
      ( '-' ) break ;;
    esac
  done
  shift $((OPTIND - 1))
  
  local VarName="$1"
  shift
  
  local -a KnownItems WrittenItems
  local OldIFS="$IFS"
  IFS="$Separator"
  read -a KnownItems <<< "${!VarName}"
  IFS="$OldIFS"
  
  if isFlagSet Prepend ; then
    
    local Check
    
    # first write the new items
    for Item in "$@" ; do
      
      for Check in "${Checks[@]}" ; do
        test "$Check" "$Item" || continue 2
      done
      
      if isFlagUnset AllowDuplicates ; then
        local WrittenItem
        for WrittenItem in "${WrittenItems[@]}" ; do
          [[ "$Item" == "$WrittenItem" ]] && continue 2 # go to the next item
        done
      fi
      
      local isKnown=0
      local KnownItem
      for KnownItem in "${KnownItems[@]}" ; do
        [[ "$Item" == "$KnownItem" ]] && isKnown=1 && break
      done
      
      isFlagSet isKnown && isFlagUnset Move && continue
      
      [[ "${#WrittenItems[@]}" == 0 ]] || printf '%s' "$Separator"
      printf '%s' "$Item"
      WrittenItems=( "${WrittenItems[@]}" "$Item" )
    done # items
    local -i nAddedItems=${#WrittenItems[@]}
    
    # now write the items which were there already
    for KnownItem in "${KnownItems[@]}" ; do
      
      local -i nDupCheck=0
      isFlagSet Move && nDupCheck=$nAddedItems
      isFlagUnset AllowDuplicates && nDupCheck=${#WrittenItems[@]}
      
      local iWrittenItem
      for (( iWrittenItem = 0; iWrittenItem < $nDupCheck ; ++iWrittenItem )); do
        [[ "${WrittenItems[iWrittenItem]}" == "$KnownItem" ]] && continue 2
      done
      
      [[ "${#WrittenItems[@]}" == 0 ]] || printf '%s' "$Separator"
      printf '%s' "$KnownItem"
      WrittenItems=( "${WrittenItems[@]}" "$KnownItem" )
    done
  else # append
    
    # first write the items which are there already
    for KnownItem in "${KnownItems[@]}" ; do
      if isFlagUnset AllowDuplicates ; then
        local WrittenItem
        for WrittenItem in "${WrittenItems[@]}" ; do
          [[ "$WrittenItem" == "$KnownItem" ]] && continue 2
        done
      fi
      
      if isFlagSet Move ; then
        # check if it will be written later
        local Item
        for Item in "$@" ; do
          [[ "$Item" == "$KnownItem" ]] && continue 2
        done
      fi
      
      [[ "${#WrittenItems[@]}" == 0 ]] || printf '%s' "$Separator"
      printf '%s' "$KnownItem"
      WrittenItems=( "${WrittenItems[@]}" "$KnownItem" )
    done
    
    # then the new ones
    local Item
    for Item in "$@" ; do
      for Check in "${Checks[@]}" ; do
        test "$Check" "$Item" || continue 2
      done
      
      if isFlagUnset AllowDuplicates ; then
        local WrittenItem
        for WrittenItem in "${WrittenItems[@]}" ; do
          [[ "$WrittenItem" == "$Item" ]] && continue 2
        done
      fi
      
      if isFlagUnset Move ; then
        local KnownItem
        for KnownItem in "${KnownItems[@]}" ; do
          [[ "$Item" == "$KnownItem" ]] && continue 2
        done
      fi
      
      [[ "${#WrittenItems[@]}" == 0 ]] || printf '%s' "$Separator"
      printf '%s' "$Item"
      WrittenItems=( "${WrittenItems[@]}" "$Item" )
    done
  fi # prepend/append
  
  printf "\n"
  return 0
} # InsertPath()


function AddToPath() {
  #
  # AddToPath [options] VarName Path [Path ...]
  #
  # Adds paths to a colon-separated list of paths stored in VarName, which is
  # updated with the new value.
  # Options: as for InsertPath
  #
  local Option
  OPTIND=1
  while getopts "ed1Dmaps:-" Option ; do
    [[ "$Option" == "-" ]] && break
  done
  
  local VarName="${!OPTIND}"
  eval "export ${VarName}=\"$(InsertPath "$@" )\""
} # AddToPath()


function DeletePath() {
  #
  # DeletePath [options] VarName Path [Path ...]
  #
  # Removes paths from a list of paths separated by Separator in VarName.
  # The purged list is printed out.
  #
  # Options:
  # -s SEP     specify the separation string (default: ':')
  #
  local Option Separator=':'
  OPTIND=1
  while getopts "s:-" Option ; do
    case "$Option" in
      ( 's' ) Separator="$OPTARG" ;;
      ( '-' ) break ;;
    esac
  done
  shift $((OPTIND - 1))
  
  local VarName="$1"
  shift
  
  tr "$Separator" "\n" <<< "${!VarName}" | while read ExistingItem ; do
    
  #	# this code commented out would remove duplicate entries
  #	for KnownItem in "${KnownItems[@]}" ; do
  #		[[ "$Item" == "$KnownItem" ]] && continue 2 # go to the next item
  #	done
    
    # check if we have met this item before
    for Item in "$@" ; do
      [[ "$ExistingItem" == "$Item" ]] && continue 2 # gotcha! skip this
    done
    
    # use a separator if this is not the very first item we have
    [[ "${#KnownItems[@]}" == 0 ]] || printf '%s' "$Separator"
    
    printf '%s' "$ExistingItem"
    
    KnownItems=( "${KnownItems[@]}" "$ExistingItem" )
  done # ( while )
  printf "\n"
  return 0
} # DeletePath()


function PurgeFromPath() {
  #
  # PurgeFromPath [options] VarName Path [Path ...]
  #
  # Removes paths from a list of paths separated by Separator in VarName,
  # which is updated with the new value.
  # Options: the same as DeletePath()
  #
  local Option
  OPTIND=1
  while getopts "s:-" Option ; do
    [[ "$Option" == "-" ]] && break
  done
  
  local VarName="${!OPTIND}"
  eval "export ${VarName}=\"$(DeletePath "$@" )\""
} # PurgeFromPath()


function RemoveDuplicatesFromPath() {
  #
  # RemoveDuplicatesFromPathSep VarName [Separator]
  #
  # Removes duplicate paths from a list of paths separated by Separator in
  # VarName. The purged list is printed out.
  #
  local VarName="$1"
  local Separator="${2:-":"}"
  
  tr "$Separator" "\n" <<< "${!VarName}" | while read Item ; do
    
    for KnownItem in "${KnownItems[@]}" ; do
      [[ "$Item" == "$KnownItem" ]] && continue 2 # go to the next item
    done
    
    # use a separator if this is not the very first item we have
    [[ "${#KnownItems[@]}" == 0 ]] || printf '%s' "$Separator"
    
    printf '%s' "$Item"
    
    KnownItems=( "${KnownItems[@]}" "$Item" )
  done # ( while )
  printf "\n"
  return 0
} # RemoveDuplicatesFromPath()


function PurgeDuplicatesFromPath() {
  #
  # PurgeDuplicatesFromPath VarName [Separator]
  #
  # Removes duplicate paths from a list of paths separated by colons in
  # VarName, which is updated with the new value.
  #
  local VarName="$1"
  eval "export ${VarName}=\"$(RemoveDuplicatesFromPath "$@" )\""
} # PurgeDuplicatesFromPath()



#-------------------------------------------------------------------------------
#---  path queries
#---

function isDirUnder() {
  # 
  # Usage:  isDirUnder Dir ParentDir
  # 
  # returns success if Dir is a subdirectory of ParentDir
  # 
  local Dir="$1"
  local ParentDir="$2"
  [[ -z "$ParentDir" ]] && return 1
  
  DBGN 2 "Is '${Dir}' under '${ParentDir}'?"
  local FullDir="$(MakeAbsolutePath "$Dir")"
  while [[ ! "$FullDir" -ef "$ParentDir" ]]; do
    [[ "$FullDir" == '/' ]] && return 1
    FullDir="$(dirname "$FullDir")"
    DBGN 3 "  - now check: '${FullDir}'"
  done
  DBGN 2 "  => YES!"
  return 0
} # isDirUnder()


function SubpathTo() {
  # 
  # Usage:  SubpathTo Dir ParentDir 
  # 
  # returns success if Dir is a subdirectory of ParentDir, like isDirUnder;
  # in addition to isDirUnder, on success it prints the relative path from
  # ParentDir to Dir
  # 
  local Dir="$1"
  local ParentDir="$2"
  [[ -z "$ParentDir" ]] && return 1
  
  local RelPath
  DBGN 2 "Is '${Dir}' under '${ParentDir}'?"
  local FullDir="$(MakeAbsolutePath "$Dir")"
  while [[ ! "$FullDir" -ef "$ParentDir" ]]; do
    [[ "$FullDir" == '/' ]] && return 1
    RelPath="$(basename "$FullDir")${RelPath:+"/${RelPath}"}"
    FullDir="$(dirname "$FullDir")"
    DBGN 3 "  - now check: '${FullDir}'"
  done
  DBGN 2 "  => YES!"
  echo "$RelPath"
  return 0
} # SubpathTo()



################################################################################
###  LArSoft-specific utilities
################################################################################

#-------------------------------------------------------------------------------
#---  building
#---

function DetectNCPUs() {
  #
  # Usage:  DetectNCPUs
  #
  # Prints on screen the maximum number of hardware threads available.
  #
  if [[ -r '/proc/cpuinfo' ]]; then
    grep -c 'processor' '/proc/cpuinfo'
    return 0
  else
    sysctl -n 'hw.ncpu' 2> /dev/null
    return
  fi
  return 1
} # DetectNCPUs()


function isMakeDirectory() {
  #
  # Usage:  isMakeDirectory Directory
  #
  # Returns whether the specified directory contains GNU makefile infrastructure
  # from cmake or otherwise.
  #
  
  local -r Dir="$1"
  [[ -d "$Dir" ]] || return 3
  local MakefileName
  for MakefileName in 'Makefile' 'GNUmakefile' ; do
    [[ -r "${Dir}/${MakefileName}" ]] && return 0
  done
  return 1
  
} # isMakeDirectory()


function isNinjaDirectory() {
  #
  # Usage:  isNinjaDirectory  Directory
  #
  # Returns whether the specified directory contains Google ninja infrastructure
  # from cmake.
  #
  
  local Dir="$1"
  
  # a ninja directory is under the build area:
  isMRBBuildArea "$Dir" || return 1
  
  # the top build directory has a build.ninja file
  [[ -r "${MRB_BUILDDIR}/build.ninja" ]] || return 1
  
  # that's it, we are in business
  return 0
  
} # isNinjaDirectory()

function isCompilableDirectory() {
  #
  # Usage:  isCompilableDirectory  Directory
  #
  # Returns whether the specified directory is a build directory with any of
  # the known build systems that can compile it singularly (e.g. not ninja).
  #
  local Dir="$1"
  isMakeDirectory "$1"
  
} # isCompilableDirectory()

function isBuildDirectory() {
  #
  # Usage:  isBuildDirectory  Directory
  #
  # Returns whether the specified directory is a build directory with any of
  # the known build systems.
  #
  local Dir="$1"
  isMakeDirectory "$1" || isNinjaDirectory "$1"
  
} # isBuildDirectory()


function isCMakeBuildDir() {
  #
  # Usage:  isCMakeBuildDir  [Directory]
  #
  # Returns whether the specified directory is a build directory with cmake
  # infrastructure in.
  #
  
  local TestDir="${1:-.}"
  DBGN 2 "   test if '${TestDir}' is a CMake build directory"
  [[ -d "$(JoinPaths "$TestDir" 'CMakeFiles')" ]]
  
} # isCMakeBuildDir()


function isGITrepository() {
  #
  # Usage:  isGITrepository  [Directory]
  #
  # Returns whether the specified directory contains a GIT repository.
  #
  
  local TestDir="${1:-.}"
  DBGN 2 "   test if '${TestDir}' is a GIT repository"
  [[ -d "$(JoinPaths "$TestDir" '.git')" ]]
  
} # isGITrepository()



#-------------------------------------------------------------------------------
#---  MRB environment
#---

function isMRBSourceArea() {
  #
  # Usage:  isMRBSourceArea  [Directory]
  # 
  # Returns whether the specified directory (default: current one) is under
  # the MRB source area.
  # This requires MRB to be set up.
  #
  
  local Dir="${1:-.}"
  if [[ -n "$MRB_SOURCE" ]]; then
    isDirUnder "$Dir" "$MRB_SOURCE"
  else
    DBGN 2 "Attempt to determine if '${Dir}' is a MRB source area, without MRB"
    Dir="$(MakeAbsolutePath "$Dir")"
    while [[ "$Dir" != '/' ]]; do
      [[ -r "${Dir}/.mrbversion" ]] && [[ -r "${Dir}/.cmake_add_subdir" ]] && return 0
      Dir="$(basename "$Dir")"
    done
    return 1
  fi
  
} # isMRBSourceArea()


function isMRBBuildArea() {
  #
  # Usage:  isMRBBuildArea  [Directory]
  # 
  # Returns whether the specified directory (default: current one) is under
  # the MRB build area.
  # This requires MRB to be set up.
  #
  
  local Dir="$1"
  if [[ -n "$MRB_BUILDDIR" ]]; then
    isDirUnder "$Dir" "$MRB_BUILDDIR"
  else
    DBGN 2 "Attempt to determine if '${Dir}' is a MRB build area, without MRB"
    Dir="$(MakeAbsolutePath "$Dir")"
    while [[ "$Dir" != '/' ]]; do
      [[ -r "${Dir}/cetpkg_variable_report" ]] && return 0
      Dir="$(basename "$Dir")"
    done
    return 1
  fi
  
} # isMRBBuildArea()


function isMRBInstallArea() {
  #
  # Usage:  isMRBInstallArea  [Directory]
  # 
  # Returns whether the specified directory (default: current one) is anywhere
  # under the MRB instll area.
  # This may give wrong answer if MRB is not set up.
  #
  
  local Dir="$1"
  if [[ -n "$MRB_INSTALL" ]]; then
    isDirUnder "$Dir" "MRB_INSTALL"
    return
  else
    DBGN 2 "Attempt to determine if '${Dir}' is a MRB install area, without MRB"
    Dir="$(MakeAbsolutePath "$Dir")"
    while [[ "$Dir" != '/' ]]; do
      [[ -r "${Dir}/.mrbversion" ]] && [[ -d "${Dir}/.upsfiles" ]] && return 0
      Dir="$(basename "$Dir")"
    done
    return 1
  fi
  
} # isMRBInstallArea()


function isMRBWorkingArea() {
  #
  # Usage:  isMRBWorkingArea  [Directory]
  # 
  # Returns whether the specified directory (default: current one) is anywhere
  # under the MRB working area.
  # This requires MRB to be set up.
  #
  
  local Dir="$1"
  if [[ -n "$MRB_TOP" ]]; then
    isDirUnder "$Dir" "$MRB_TOP"
  else
    DBGN 2 "Attempt to determine if '${Dir}' is a MRB area, without MRB"
    
    # do we have:
    local -i hasSourceArea=0 hasInstallAreas=0 hasBuildAreas=0
    
    isMRBSourceArea "${Dir}/srcs" && hasSourceArea=1
    
    local SubDir
    for SubDir in "$(JoinPaths "$Dir" 'localProducts')"* ; do
      isMRBInstallArea "$SubDir" && let ++hasInstallAreas
    done
    
    for SubDir in "$(JoinPaths "$Dir" 'build')"* ; do
      isMRBBuildArea "$SubDir" && let ++hasBuildAreas
    done
    
    # let be generous; an MRB area can have any number of any category...
    
    isFlagSet hasSourceArea || [[ $hasBuildAreas -ge 1 ]] || [[ $hasInstallAreas -ge 1 ]]
    return
  fi
  
} # isMRBWorkingArea()


function DetectMRBLocation() {
  #
  # Usage:  DetectMRBLocation  [Dir]
  #
  # Prints the MRB location where we are: 'SOURCE' 'BUILDDIR' 'INSTALL' or
  # 'TOP'. Returns with exit code 1 if we are not in any of them.
  # 
  
  local Dir="${1:-"$(pwd)"}"
  
  isMRBSourceArea  "$Dir" && echo "SOURCE"   && return 0
  isMRBBuildArea   "$Dir" && echo "BUILDDIR" && return 0
  isMRBInstallArea "$Dir" && echo "INSTALL"  && return 0
  isMRBWorkingArea "$Dir" && echo "TOP"      && return 0
  return 1
  
} # DetectMRBLocation()




function isUPSpackageDir() {
  #
  # Usage:  isUPSpackageDir  [Dir]
  # 
  # Returns whether the specified directory (default: current one) is a UPS
  # product directory. This means the directory contains one or more versions
  # of the UPS product.
  # This currently works only if the directory has *.version files.
  #
  local TestDir="${1:+"${1%/}/"}"
  DBGN 2 "   test if '${TestDir}' is a UPS package"
  ls "${TestDir}/"*.version >& /dev/null
} # isUPSpackage()



################################################################################
### If the script was not sourced, assume we want to execute a command in the
### utilities-aware environment:
###

# setting USECOLORS=0 before this call will disable colours, only the first time
hasLArSoftScriptUtils || SetColors 

declare LARSOFTSCRIPTUTILS_VERSION="1.0"

