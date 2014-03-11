#!/bin/bash

UserName="${1:-"Gianluca Petrillo"}"
Email="${2:-"petrillo@fnal.gov"}"

largit.sh config --local user.name "$UserName"
largit.sh config --local user.email "$Email"

git config --global user.name "$UserName"
git config --global user.email "$Email"

