#!/usr/bin/env bash
#
# Creates a new working area.
# Run without parameters for usage instructions.
#

declare local_create_area_DefaultVersion="${LARCORE_VERSION:-"develop"}"
declare local_create_area_DefaultQual="${MRB_QUAL:-"e7:debug"}"

function IsInList() {
	# IsInList Key ListItem [...]
	
	local Key="$1"
	shift
	local Item
	for Item in "$@" ; do
		[[ "$Key" == "$Item" ]] && return 0
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
	which ups >& /dev/null || {
		echo "FATAL ERROR: UPS not configured!"
		return 1
	}
	if ! declare -f setup unsetup >& /dev/null ; then
		cat <<-EOM
		ERROR: setup/unsetup not available!
		
		UPS may be correctly set up, but its setup/unsetup functions are not visible to scripts.
		A way to correct that in bash is to execute:
		
		export -f setup unsetup
		
		EOM
		echo "FATAL ERROR: UPS is not fully operative in script environment." >&2
		return 1
	fi
	return 0
} # CheckSetup()


declare local_create_area_scriptdir="$(dirname "$BASH_SOURCE")"

if [[ $# == 0 ]]; then
	cat <<-EOH
	Creates and sets up a new LArSoft working area.
	
	Usage:  source $(basename "$BASH_SOURCE") LArSoftVersion LArSoftQualifiers NewAreaPath Experiment
	
	All parameters are optional, but they need to be specified if a following one
	is also specified.
	If LArSoftVersion is not specified or empty, it defaults to '${local_create_area_DefaultVersion}'.
	If LArSoftQualifiers is not specified or empty, it defaults to '${local_create_area_DefaultQual}'.
	If NewAreaPath is not specified or empty, it defaults to LArSoftVersion/LArSoftQualifiers.
	The parameter Experiment is autodetected out of the current path if it is not
	specified or if it is "auto".
	
	EOH
	
	unset local_create_area_scriptdir local_create_area_newarea
	[[ "$BASH_SOURCE" != "$0" ]] && return
	exit
fi

###
### parameters parsing
###
declare local_create_area_setup_version="${1:-"$local_create_area_DefaultVersion"}"
declare local_create_area_setup_qual="${2:-"$local_create_area_DefaultQual"}"

declare local_create_area_newarea="$3"

declare local_create_area_experiment
case "$(tr '[:upper:]' '[:lower:]' <<< "$4")" in
	( 'auto' | 'autodetect' | '' )
		for local_create_area_dir in "$(pwd)" "$local_create_area_scriptdir" ; do
			while [[ "$local_create_area_dir" != "/" ]]; do
				
				case "$(basename "$local_create_area_dir" | tr '[:lower:]' '[:upper:]')" in
					( 'LBNE' | 'DUNE' )
						local_create_area_experiment='DUNE'
						break 2
						;;
					( 'UBOONE' | 'MICROBOONE' )
						local_create_area_experiment='MicroBooNE'
						break 2
						;;
				esac
				local_create_area_dir="$(dirname "$local_create_area_dir")"
			done
		done
		unset local_create_area_dir
		
		if [[ -z "$local_create_area_experiment" ]]; then
			if [[ -d '/dune' ]] ||  [[ -d '/lbne' ]]; then
				local_create_area_experiment="DUNE"
			elif [[ -d "/uboone" ]]; then
				local_create_area_experiment="MicroBooNE"
			fi
		fi
		;;
	( 'lbne' | 'dune' )
		local_create_area_experiment="DUNE"
		;;
	( 'uboone' | 'microboone' )
		local_create_area_experiment="MicroBooNE"
		;;
esac

local_create_area_setup_qual="$(SortUPSqualifiers "${local_create_area_setup_qual//_/:}")"
unset -f SortUPSqualifiers IsInList

if [[ -z "$local_create_area_newarea" ]] && [[ -n "$local_create_area_setup_version" ]]; then
	local_create_area_newarea="${local_create_area_setup_version}/${local_create_area_setup_qual//:/_}"
fi

if [[ "$BASH_SOURCE" == "$0" ]]; then
	cat <<-EOM
	Experiment:      ${local_create_area_experiment:-"generic"}
	LArSoft version: ${local_create_area_setup_version} (${local_create_area_setup_qual})
	Location:       '${local_create_area_newarea}'
	This script needs to be sourced:
	source $0 $@
	EOM
	CheckSetup
	[[ "$BASH_SOURCE" != "$0" ]] && return 1
	exit 1
fi

###
### Here we go: we do it!!
###

###
### environment checks
###
if [[ -z "$local_create_area_setup_version" ]]; then
	echo "You really need to specify a LArSoft version." >&2
	unset local_create_area_scriptdir local_create_area_newarea local_create_area_experiment local_create_area_setup_version local_create_area_setup_qual
	return 1
fi

# check that UPS is set up
CheckSetup || return $?

echo "Creating working area: '${local_create_area_newarea}'"


###
### set up
###
source "${local_create_area_scriptdir}/setup/setup" "base" "$local_create_area_setup_version" "$local_create_area_setup_qual"


###
### creation of the new area
###
if [[ -d "$local_create_area_newarea" ]]; then
	echo "The working area '${local_create_area_newarea}' already exists." >&2
	cd "$local_create_area_newarea"
	return 1
else
	mkdir -p "$local_create_area_newarea"
	if ! cd "$local_create_area_newarea" ; then
		echo "Error creating the new area in '${local_create_area_newarea}'." >&2
		return 1
	fi
	
	declare local_create_area_test_script="./ExecTest-$$.sh"
	cat <<-EOS > "$local_create_area_test_script"
	#!/usr/bin/env bash
	echo "success!"
	EOS
	chmod a+x "$local_create_area_test_script"
	echo -n "Testing exec... "
	"$local_create_area_test_script"
	if [[ $? != 0 ]]; then
		echo "The area '${local_create_area_newarea}' seems not suitable for compilation." >&2
		return 1
	fi
	rm "$local_create_area_test_script"
	
	echo "Creating the new working area '${local_create_area_newarea}'"
	mrb newDev -v "$local_create_area_setup_version" -q "$local_create_area_setup_qual"
	
	if [[ -r "${local_create_area_scriptdir}/setup/devel" ]]; then
		echo "Linking the developement setup script (and sourcing it!)"
		rm -f 'setup'
		ln -s "${local_create_area_scriptdir}/setup/devel" 'setup'
		source './setup'
	else
		echo "Can't find developement setup script ('${local_create_area_scriptdir}/setup/devel'): setup not linked." >&2
	fi
	
	: ${MRB_INSTALL:="${local_create_area_newarea}/localProducts_${MRB_PROJECT}_$(autodetectLArSoft.sh --localprod)"}
	
	if [[ -d "$MRB_INSTALL" ]]; then
		echo "Creating link 'localProducts' to MRB_INSTALL directory"
		rm -f 'localProducts'
		ln -s "$MRB_INSTALL" 'localProducts'
	else
		echo "Expected local products directory '${MRB_INSTALL}' not found. You'll need to complete setup on your own." >&2
		unset MRB_INSTALL
	fi
fi

mkdir -p "logs" "job"
cd "srcs"

###
### clean up
###
unset local_create_area_scriptdir local_create_area_newarea local_create_area_experiment local_create_area_setup_version local_create_area_setup_qual

###
