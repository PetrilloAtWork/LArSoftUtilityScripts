#!/usr/bin/env bash

function _BashCompletion_larrun() {
  
  [[ -n "$BASHCOMPLETION_DEBUG" ]] && set -x
  
  local LArRun="$1"
  local CompleteMe="$2"
  local Previous="$3"
  
  local Mode
  #
  # determine the type of completion needed from the context
  #
  local GotConfig=0
  local GotSource=0
  
  # first test if the completing word explains what we need to do
  case "$CompleteMe" in
    ( '--config='* )
      Mode='FHiCL'
      ;;
    ( '--source='* )
      Mode='source'
      ;;
    ( * )
      Mode=''
      ;;
  esac
  
  # then parse argument by argument, until just before the one being completed
  if [[ -z "$Mode" ]]; then
    local iWord
    # should we care of what follows the completing word?
    for (( iWord = 1 ; iWord < $COMP_CWORD; ++iWord )); do
      local Word="${COMP_WORDS[iWord]}"
      case "$Mode" in
        ( 'FHiCL' )
          # we entered FHiCL mode with previous argument, now it is over
          GotConfig=1
          Mode=''
          continue
          ;;
        ( 'source' )
          # we entered this mode with previous argument, now it is over
          GotSource=1
          Mode=''
          continue
          ;;
        ( '' )
          # open mode (might be FHiCL)
          case "$Word" in
            ( '-c' )
              Mode='FHiCL'
              ;;
            ( '-s' )
              Mode='source'
              ;;
            ( '--config='* ) # known single-argument option
              GotConfig=1
              Mode=''
              ;;
            ( '--source='* ) # known single-argument option
              GotSource=1
              Mode=''
              ;;
            ( '--' | '-' ) # no more options, no more completion, sorry
              break
              ;;
            ( '--'* | '-'* ) # some unknown option: skip it, assume no arguments
              Mode=''
              ;;
            ( * ) # non-option arguments
              if [[ "$GotConfig" == 0 ]]; then
                GotConfig=1
              elif [[ "$GotSource" == 0 ]]; then
                GotSource=1
              fi
              Mode=''
          esac
          ;;
      esac
    done
  fi
  
  # still no clue? complete with the first positional argument type not yet in
  if [[ -z "$Mode" ]]; then
    if [[ "$GotConfig" == 0 ]]; then
      Mode='FHiCL'
    elif [[ "$GotSource" == 0 ]]; then
      Mode='source'
    fi
  fi
  
  [[ -n "$BASHCOMPLETION_DEBUG" ]] && set +x
  
  #
  # supposedly we know what to do now
  #
  case "$Mode" in
    ( 'FHiCL' )
      
      COMPREPLY=( $(FindInPath.py --fcl --name --regex="^${CompleteMe#--config=}" 2> /dev/null | sort -u) )
      
      # add back `--config=` if needed
      if [[ "${CompleteMe#--config=}" != "$CompleteMe" ]]; then
        local i
        for (( i = 0; i < "${#COMPREPLY[@]}" ; ++i )); do
          COMPREPLY[i]="--config=${COMPREPLY[i]}"
        done
      fi
      return 0
      ;;
    ( 'source' )
      COMPREPLY=( $( compgen -o plusdirs -A file -X '!*.root' "$CompleteMe" ) )
      return 0
      ;;
    ( * )
      COMPREPLY=( $( compgen -o default "$CompleteMe" ) )
      return 0
      ;;
  esac
  return 1
  
} # _BashCompletion_larrun()


function _BashCompletion_larrun_test() {
  declare -a COMP_WORDS=( "$@" )
  declare -i COMP_WORD=$(( ${#COMP_WORDS[@]} - 1 ))
  set -x
  _BashCompletion_larrun "${COMP_WORDS[0]}" "${COMP_WORDS[COMP_WORD]}" "${COMP_WORDS[COMP_WORD-1]}"
  set +x
  declare -p COMPREPLY
} # _BashCompletion_larrun_test()


# completion setup
complete -r larrun.sh >& /dev/null
complete -F _BashCompletion_larrun larrun.sh
