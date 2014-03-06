#!/bin/bash

UserName="${1:-'petrillo'}"
Email="${2:-"${UserName}@fnal.gov"}"

largit.sh config --local user.name "$UserName"
largit.sh config --local user.email "$Email"

git config --global user.name "$UserName"
git config --global user.email "$Email"

