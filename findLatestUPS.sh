#!/usr/bin/env bash
#
# Writes the UPS product with the higher version.
# Run with `-h` for help.
#

SCRIPTNAME="$(basename "$0")"

################################################################################
function Help() {
	cat <<-EOH
	
	${SCRIPTNAME}  [options] ProductName [Qualifiers ...]
	
	Returns the latest product version with at least the specified qualifiers.
	The output format is:
	    
	    <ProductName> <Version> <Qualifiers>
	    
	Options:
	--qual QUALIFIERS , -q QUALIFIERS
	    additional required qualifiers
	--all , -a
	    instead of the latest, print all the matches (latest first)
	--help, -h , -?
	    print this help
	
	EOH
} # Help()


function isFlagSet() {
  local VarName="$1"
  [[ -n "${!VarName//0}" ]]
} # isFlagSet()

function SortQualifiers() {
  local Qualifiers="$*"
  tr ': ' '\n' <<< "$Qualifiers" | sort -u
} # SortQualifiers()


function MatchProductQualifiers() {
  local ProdVersion="$1"
  local -a ProdQualifierSpec="$2"
  local -a ProdQualifiers=( $(SortQualifiers "$ProdQualifierSpec" ) )
  
  local -i iSrcQual=0
  local KeyQual
  for KeyQual in "${RequiredQualifiers[@]}" ; do
    while [[ $iSrcQual -lt ${#ProdQualifiers[@]} ]]; do
      [[ "$KeyQual" == "${ProdQualifiers[iSrcQual++]}" ]] && continue 2 # match! go to next required qualifier
    done
    return 1 # no qualifier match, this product is not good
  done
  echo "${Product} ${ProdVersion} ${ProdQualifierSpec}"
  return 0
} # MatchProductQualifiers()


################################################################################
#
# option parser
#

declare -i DoHelp=0 PrintAll=0
declare -i NoMoreOptions=0
declare -a RequiredQualifiers
declare Product

for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
  Param="${!iParam}"
  if isFlagSet NoMoreOptions || [[ "${Param:0:1}" != '-' ]]; then
    if [[ -z "$Product" ]]; then
      Product="$Param"
    else
      RequiredQualifiers+=( ${Param//:/ } )
    fi
  else
    case "$Param" in
      ( '--all' | '-a' )         PrintAll=1 ;;
      ( '--qual' | '-q' )        let ++iParam ; RequiredQualifiers+=( ${!iParam//:/ } ) ;;
      ( '--help' | '-h' | '-?' ) DoHelp=1 ;;
      ( '-' | '--' )             NoMoreOptions=1 ;;
      ( * )
        FATAL 1 "Unsupported option: '${Param}' (run \`${0} --help\` for instructions)."
    esac
  fi
done

if isFlagSet DoHelp ; then
  Help
  exit
fi
  
RequiredQualifiers=( $(SortQualifiers "${RequiredQualifiers[@]}" ) )
declare -i nRequiredQualifiers="${#RequiredQualifiers[@]}"

ups list -a -K VERSION:QUALIFIERS "$Product" | tr -d '"' | sort -r -V -u | {
  nMatches=0
  while read ProdVersion ProdQualifiers ; do
    MatchProductQualifiers "$ProdVersion" "$ProdQualifiers" || continue
    let ++nMatches
    isFlagSet PrintAll || break # one is enough
  done
  [[ $nMatches == 0 ]] && exit 1
  exit 0
}
declare -i res=$?
exit $res

