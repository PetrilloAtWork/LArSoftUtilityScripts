#!/usr/bin/env python2
#
# Lists all the files whose name matches the specified pattern, in a PATH-like
# list of directories.
# 
# Usage: see FindInPath.py --help
# 
# Changes:
# 20150105 (petrillo@fnal.gov) [v1.0]
#   first version (from a bash version)
# 20160602 (petrillo@fnal.gov) [v1.1]
#   add a --full option and make partial match the default
# 20160718 (petrillo2fnal.gov) [v1.2]
#   bug fix: default output should print directory, not full path
#

__version__ = "1.2"
__doc__ = """
Looks for files in the search directories specified in the given variables.
"""

import sys, os
import logging
import re
import fnmatch

#function PrintFullLDpath() {
	#/sbin/ldconfig -vNX | grep -v '\t' | sed -e 's/:.*//g' | while read LibDir ; do
		#[[ $((nLibDirs++)) -gt 0 ]] && echo -n ':'
		#echo -n "$LibDir"
	#done
	#echo
#} # PrintFullLDpath()


def MatchesPatterns(ItemRecord, Patterns, options = None):
	# no requirement means we accept it
	if not Patterns: return True
	
	for regex in Patterns:
		if regex.match(ItemRecord['FileName']): return True
	
	return False
# MatchesPatterns()



def EndsWith(s, suffixes):
	for suffix in suffixes:
		if s.endswith(suffix): return True
	return False
# EndsWith()


def FindInDir(SearchDir, Patterns, options):
	if not os.path.isdir(SearchDir):
		logging.debug("Search directory '%s' does not exist", SearchDir)
		return []
	# if no dir
	
	FileRecords = []
	for DirItem in os.listdir(SearchDir):
		if options.Suffixes and not EndsWith(DirItem, options.Suffixes): continue
		
		record = {
		  'Dir': SearchDir,
		  'FileName': DirItem,
		  'Path': os.path.join(SearchDir, DirItem),
		  }
		
		if not MatchesPatterns(record, Patterns, options): continue
		
		FileRecords.append(record)
		
	# for
	
	return FileRecords
# FindInDir()

def WrapString(s, left, right):
	if left and not s.startswith(left): s = left + s
	if right and not s.endswith(right): s += right
	return s
# WrapString()


def Find(SearchDirs, options):
	"""Finds the patterns specified in options
	"""
	
	# prepare the patterns
	RegexPatterns = []
	for pattern in options.RegexFilters:
		if options.FullMatch: pattern = WrapString(pattern, '^', '$')
		logging.debug("Adding regex pattern: '%s'", pattern)
		RegexPatterns.append(re.compile(pattern))
	# for regex patterns
	
	for simple_pattern in options.SimpleFilters:
		if not options.FullMatch:
			simple_pattern = WrapString(simple_pattern, '*', '*')
		pattern = fnmatch.translate(simple_pattern)
		logging.debug("Adding simple pattern: '%s' (regex: '%s')", 
		  simple_pattern, pattern)
		RegexPatterns.append(re.compile(pattern))
	# for simple patterns
	
	FileRecords = []
	for SearchDir in SearchDirs:
		FileRecords.extend(FindInDir(SearchDir, RegexPatterns, options))
	return FileRecords
# Find()


def FormatRecord(Record, Format, options = None):
	return Format % Record
# FormatRecord()


def FormatRecords(Records, options):
	FormattedRecords = []
	for record in Records:
		FormattedRecords.append(FormatRecord(record, options.OutputFormat, options))
	return FormattedRecords
# FormatRecords()


################################################################################


if __name__ == "__main__":
	
	import argparse
	
	logging.getLogger().setLevel(logging.INFO)
	
	Parser = argparse.ArgumentParser(description=__doc__)
	
	Parser.set_defaults(
	  OutputFormat = "%(FileName)s (in %(Dir)s)",
	  SimpleFilters = [],
	  RegexFilters = [],
	  )
	
	# positional parameters: filters
	Parser.add_argument('SimpleFilters', nargs='*',
	  help="list of simple filters (equivalent to the --simple option)")
	
	PatternOptions = Parser.add_argument_group('Pattern options')
	PatternOptions.add_argument('--simple', '-s', dest="SimpleFilters",
	  action="append",
	  help="prints only files whose name matches the specified simple pattern"
	    " (as in python's fnmatch module)"
	  )
	PatternOptions.add_argument('--regex', '-r', dest="RegexFilters",
	  action="append",
	  help="prints only files whose name matches the specified regular expression"
	    " (as in python's re module)"
	  )
	PatternOptions.add_argument('--full', '-f', dest="FullMatch",
	  action="store_true",
	  help="the pattern must match the entire file name"
	  )
	
	InputOptions = Parser.add_argument_group('Input options')
	InputOptions.add_argument('--varname', dest="VarNames",
	  action="append",
	  help="environment variable holding the list of search directories"
	  )
	InputOptions.add_argument('--bin', '-B', dest="VarNames",
	  action="append_const", const='PATH',
	  help="uses PATH as variable (equivalent to '--varname=PATH', and default)"
	  )
	InputOptions.add_argument('--lib', '-L', dest="VarNames",
	  action="append_const", const='LD_LIBRARY_PATH',
	  help="uses LD_LIBRARY_PATH as variable (equivalent to '--varname=LD_LIBRARY_PATH')"
	  )
	InputOptions.add_argument('--fcl', '--fhicl', '-F', dest="VarNames",
	  action="append_const", const='FHICL_FILE_PATH',
	  help="uses FHICL_FILE_PATH as variable (equivalent to '--varname=FHICL_FILE_PATH')"
	  )
	InputOptions.add_argument('--suffix', dest="Suffixes", action="append",
	  help="only prints entries with this suffix (can be specified multiple times)"
	  )
	InputOptions.add_argument('--separator', dest="Separator",
	  type=str, default=':',
	  help="interpret this character as directory separator [%(default)r])"
	  )
	
	OutputOptions = Parser.add_argument_group('Output options')
	OutputOptions.add_argument('--name', '-n', dest="OutputFormat",
	  action="store_const", const="%(FileName)s",
	  help="print the file name only"
	  )
	OutputOptions.add_argument('--path', '-p', dest="OutputFormat",
	  action="store_const", const="%(Path)s",
	  help="print the full path"
	  )
	OutputOptions.add_argument('--dir', '-d', dest="OutputFormat",
	  action="store_const", const="%(Dir)s",
	  help="print the directory where the match is"
	  )
	OutputOptions.add_argument('--format', dest="OutputFormat",
	  type=str, help="print using this format [%(default)s]"
	  )
	OutputOptions.add_argument('--reverse', '-R', dest="ReverseOrder",
	  type=str, help="looks for the latest directories in paths first"
	  )
	
	# generic program options
	Parser.add_argument('--debug', dest="Debug", action="store_true",
	  help="increases verbosity level")
	Parser.add_argument('--version', '-V', action="version",
	  version="%(prog)s " + __version__)
	
	args = Parser.parse_args()
	
	if args.Debug: logging.getLogger().setLevel(logging.DEBUG)
	
	# fill the list of directories
	SearchDirs = []
	for VarName in args.VarNames:
		try:
			VarValue = os.environ[VarName]
		except KeyError:
			logging.error("Variable '%s' is not set", VarName)
			continue
		# if
		
		# merge the directory list, skip duplicates, but preserve order
		for DirPath in VarValue.split(args.Separator):
			if DirPath not in SearchDirs: SearchDirs.append(DirPath)
		
	# for
	
	if args.ReverseOrder: SearchDirs.reverse()
	
	logging.debug("Search directories: '%s'", "', '".join(SearchDirs))
	
	FileRecords = Find(SearchDirs, args)
	if len(FileRecords) == 0:
		logging.error("No matches.")
		sys.exit(2)
	# if
	
	# format the entries
	Output = FormatRecords(FileRecords, args)
	
	# print the result on screen
	for entry in Output: print entry
	
# explanation:
# - start with paths in VarNames paths
# - split by ":"
# - find in all those directories (but not in their subdirectories),
#   and in that order, all the files
# - print for each its name, full path and the string to be presented to the user as output
# - sort them by file name, preserving the relative order of files with the
#   same name from different directories
# - filter them on sort key (file name) by user's request
# - remove the sort key (file name) from the output
# SplitPaths "${VarListNames[@]}" | xargs -I SEARCHPATH find SEARCHPATH -maxdepth 1 "${AllFindNames[@]}" -printf "%f %p ${FORMAT}\n" 2> # /dev/null | sort -s -k1,1 -u | Filter "${Patterns[@]}" | GrepText "$GrepMode" "${GREPPATTERNS[@]}" | CleanKeys
	sys.exit(0)
# main
