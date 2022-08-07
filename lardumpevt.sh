#!/usr/bin/env bash
#
# Runs the standard event dumper on the first event of the input file
#

SCRIPTNAME="$(basename "$0")"

declare -r DumperConfigName="eventdump.fcl"

# ------------------------------------------------------------------------------
function STDERR() { echo "$*" >&2 ; }
function FATAL() {
  local Code="$1"
  shift
  STDERR "FATAL ERROR: $*"
  exit $Code
} # FATAL()

function isFlagSet() {
  local VarName="$1"
  [[ -n "${!VarName//0}" ]]
}

function Exec() {
  
  local -a Cmd=( "$@" )
  
  if isFlagSet FAKE || isFlagSet VERBOSE ; then
    STDERR "CMD> ${Cmd[@]}"
  fi
  isFlagSet FAKE || "${Cmd[@]}"
  
} # Exec()


function PrintHelp() {
  cat <<EOH
Runs the art event dumper module on the specified files.

Usage:  ${SCRIPTNAME} [options] [--] InputFile [...]

The list of files is passed to \`lar\` command line.
To pass options directly to \`lar\`, use the \`--\` option.

Options:
--events=N , --nevts=N , -n N
    processes at most N events from the input, then stops the processing;
    \`--nevts\` has the same effect as passing it directly to \`lar\`, while
    \`--events\` behaves the same (alias).
--nskip=N
    skips the first N events from the input; same effect as passing it directly
    to \`lar\`.
--fake , --dryrun
    only prints the command it would execute, then exits.
--verbose , -V
    prints the command it executes.
-- , -
    all arguments after a single or double hyphen are passed directly to \`lar\`
    command line, in the same order as specified.
--help , -h , -?
    prints this help message
  
EOH
} # PrintHelp()


# ------------------------------------------------------------------------------
# ---  parameter parsing
# ------------------------------------------------------------------------------

#
# In general, all parameters are passed directly to `lar`.
# Here we just intercept a few.
# 
declare -i NoMoreOptions=0
declare NEvents
declare FAKE=0 VERBOSE=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
  
  Param="${!iParam}"
  if isFlagSet NoMoreOptions || [[ "${Param:0:1}" != '-' ]]; then
    Arguments+=( "$Param" )
  else
    case "$Param" in
      ( '-c' | '--config' )
        FATAL 1 "Configuration file option not allowed (we'll use '${DumperConfigName}')."
        ="${!iParam}"
        ;;
      ( '-n' | '--events' | '--nevts' )
        [[ $((++iParam)) -le $# ]] || FATAL 1 "Expected number of events after option '-n'."
        NEvents="${!iParam}"
        ;;
      ( '--events='* | '--nevts='* ) NEvents="${Param#--*=}" ;;
      ( '--fake' | '--dryrun' )      FAKE=1 ;;
      ( '--verbose' | '-V' )         VERBOSE=1 ;;
      ( '--help' | '-h' | '-?' )     DoHelp=1 ;;
      ( '-' | '--' )                 NoMoreOptions=1 ;;
      ( * )
        Arguments+=( "$Param" ) ;;
    esac
  fi
  
done

if isFlagSet DoHelp ; then
  PrintHelp
  exit 0
fi

# ------------------------------------------------------------------------------
Exec lar --config "$DumperConfigName" --nevts "${NEvents:-1}" "${Arguments[@]}"

