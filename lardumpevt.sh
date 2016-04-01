#!/usr/bin/env bash
#
# Runs the standard event dumper on the first event of the input file
#

: ${EVENTS:=1}

declare InputFile="$1"
shift

lar -c "eventdump.fcl" -s "$InputFile" -n "$EVENTS" "$@"

