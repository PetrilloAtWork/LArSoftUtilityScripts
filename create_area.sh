#!/bin/bash
#
# Creates a new working area.
# Run without parameters for usage instructions.
#

declare local_DefaultVersion="${LARCORE_VERSION:-"nightly"}"
declare local_DefaultQual="${MRB_QUAL:-"debug:e4"}"

function SortUPSqualifiers() {
	# Usage:  SortUPSqualifiers  Qualifiers [Separator]
	# sorts the specified qualifiers (colon separated by default)
	local qual="$1"
	local sep="${2:-":"}"
	local item
	local -i nItems=0
	for item in $(tr "$sep" '\n' <<< "$qual" | sort) ; do
		[[ "$((nItems++))" == 0 ]] || echo -n "$sep"
		echo -n "$item"
	done
	echo
	return 0
} # SortUPSqualifiers()


declare local_scriptdir="$(dirname "$BASH_SOURCE")"

if [[ $# == 0 ]]; then
	cat <<-EOH
	Creates and sets up a new LArSoft working area.
	
	Usage:  source $(basename "$BASH_SOURCE") LArSoftVersion LArSoftQualifiers NewAreaPath Experiment
	
	All parameters are optional, but they need to be specified if a following one
	is also specified.
	If LArSoftVersion is not specified or empty, it defaults to '${local_DefaultVersion}'.
	If LArSoftQualifiers is not specified or empty, it defaults to '${local_DefaultQual}'.
	If NewAreaPath is not specified or empty, it defaults to LArSoftVersion/LArSoftQualifiers.
	The parameter Experiment is autodetected out of the current path if it is not
	specified or if it is "auto".
	
	EOH
	
	unset local_scriptdir local_newarea
	[[ "$BASH_SOURCE" != "$0" ]] && return
	exit
fi

###
### parameters parsing
###
declare local_setup_version="${1:-"$local_DefaultVersion"}"
declare local_setup_qual="${2:-"$local_DefaultQual"}"

declare local_newarea="$3"

declare local_experiment
case "$(tr '[:upper:]' '[:lower:]' <<< "$4")" in
	( 'auto' | 'autodetect' | '' )
		for local_dir in "$(pwd)" "$local_scriptdir" ; do
			while [[ "$local_dir" != "/" ]]; do
				
				case "$(basename "$local_dir" | tr '[:lower:]' '[:upper:]')" in
					( 'LBNE' )
						local_experiment='LBNE'
						break 2
						;;
					( 'UBOONE' | 'MICROBOONE' )
						local_experiment='MicroBooNE'
						break 2
						;;
				esac
				local_dir="$(dirname "$local_dir")"
			done
		done
		unset local_dir
		
		if [[ -z "$local_experiment" ]]; then
			if [[ -d "/lbne" ]]; then
				local_experiment="LBNE"
			elif [[ -d "/uboone" ]]; then
				local_experiment="MicroBooNE"
			fi
		fi
		;;
	( 'lbne' )
		local_experiment="LBNE"
		;;
	( 'uboone' | 'microboone' )
		local_experiment="MicroBooNE"
		;;
esac

local_setup_qual="$(SortUPSqualifiers "${local_setup_qual//_/:}")"
unset -f SortUPSqualifiers

if [[ "$BASH_SOURCE" == "$0" ]]; then
	cat <<-EOM
	Experiment:      ${local_experiment:-"generic"}
	LArSoft version: ${local_setup_version} (${local_setup_qual})
	This script needs to be sourced:
	source $0 $@
	EOM
	[[ "$BASH_SOURCE" != "$0" ]] && return 1
	exit 1
fi

if [[ -z "$local_setup_version" ]]; then
	echo "You really need to specify a LArSoft version." >&2
	unset local_scriptdir local_newarea local_experiment local_setup_version local_setup_qual
	return 1
fi

if [[ -z "$local_newarea" ]] && [[ -n "$local_setup_version" ]]; then
	local_newarea="${local_setup_version}/${local_setup_qual//:/_}"
	echo "Creating a default working area: '${local_newarea}'"
fi


###
### set up
###
source "${local_scriptdir}/setup/base" "$local_setup_version" "$local_setup_qual"


###
### creation of the new area
###
if [[ -d "$local_newarea" ]]; then
	echo "The working area '${local_newarea}' already exists." >&2
	cd "$local_newarea"
	return 1
else
	mkdir -p "$local_newarea"
	if ! cd "$local_newarea" ; then
		echo "Error creating the new area in '${local_newarea}'." >&2
		return 1
	fi
	
	declare local_test_script="ExecTest-$$.sh"
	cat <<-EOS > "$local_test_script"
	#!/bin/bash
	echo "success!"
	EOS
	chmod a+x "$local_test_script"
	echo -n "Testing exec... "
	"$local_test_script"
	if [[ $? != 0 ]]; then
		echo "The area '${local_newarea}' seems not suitable for compilation." >&2
		return 1
	fi
	rm "$local_test_script"
	
	echo "Creating the new working area '${local_newarea}'"
	mrb newDev 
fi

mkdir -p "logs"
cd "srcs"

###
### clean up
###
unset local_scriptdir local_newarea local_experiment local_setup_version local_setup_qual

###
