#!/usr/bin/env python2
#
# Author: petrillo@fnal.gov
# Date:   201403??
# 
# Version:
# 1.0 (petrillo@fnal.gov)
#   first version
# 1.1 (petrillo@fnal.gov)
#   support for compressed input files; added command line interface
# 1.2 (petrillo@fnal.gov)
#   new mode to expose all the events
#

import sys, os
import math
import gzip
try: import bz2
except ImportError: pass

import optparse

Version = "%prog 1.2"
UsageMsg = """Prints statistics of the module timings based on the information from
the Timing service.

%prog  [options] LogFile [LogFile ...]
"""

#
# statistics collection
#
def signed_sqrt(value):
	if value >= 0.: return math.sqrt(value)
	else: return -math.sqrt(-value)
# signed_sqrt()


class Stats:
	def __init__(self, bFloat = True):
		self.clear(bFloat)
	
	def clear(self, bFloat = True):
		self.e_n = 0
		if bFloat:
			self.e_w = 0.
			self.e_sum = 0.
			self.e_sumsq = 0.
		else:
			self.e_w = 0
			self.e_sum = 0
			self.e_sumsq = 0
		self.e_min = None
		self.e_max = None
	# clear()
	
	def add(self, value, weight=1):
		"""Add a new item.
		
		The addition is treated as integer only if both value and weight are
		integrals.
		"""
		self.e_n += 1
		self.e_w += weight
		self.e_sum += weight * value
		self.e_sumsq += weight * value**2
		if (self.e_min is None) or (value < self.e_min): self.e_min = value
		if (self.e_max is None) or (value > self.e_max): self.e_max = value
	# add()
	
	def n(self): return self.e_n
	def weights(self): return self.e_w
	def sum(self): return self.e_sum
	def min(self): return self.e_min
	def max(self): return self.e_max
	def sumsq(self): return self.e_sumsq
	def average(self):
		if self.e_w != 0.: return float(self.e_sum)/self.e_w
		else: return 0.
	def sqaverage(self):
		if self.e_w != 0.: return float(self.e_sumsq)/self.e_w
		else: return 0.
	def rms2(self): return self.sqaverage() - self.average()**2
	def rms(self): return signed_sqrt(self.rms2())
	def stdev(self):
		if self.e_n < 2: return 0.
		else: return self.rms() * math.sqrt(float(self.e_n)/(self.e_n-1))
	def stdevp(self): return self.rms()
# class Stats


class TimeModuleStatsClass(Stats):
	def __init__(self, moduleKey, bTrackEntries = False):
		Stats.__init__(self)
		self.key = moduleKey
		if bTrackEntries:
			self.entries = []
			self.entryKeys = set()
		else:
			self.entries = self.entryKeys = None
	# __init__()
	
	def add(self, data):
		if self.entries is not None:
			eventKey = ( data['run'], data['subRun'], data['event'], )
			if eventKey in self.entryKeys: return False
			self.entries.append(data)
			self.entryKeys.add(eventKey)
		# if
		Stats.add(self, data['time'])
		return True
	# add()
	
	def FormatStatsAsList(self, format_ = None):
		if isinstance(self.key, basestring): name = str(self.key)
		else: name = "%s[%s]" % (self.key[1], self.key[0])
		if (self.n() == 0) or (self.sum() == 0.):
			return [ name, "n/a" ]
		RMS = self.rms() if (self.n() != 0) else 0.
		return [ 
			name,
			"%g\"" % self.average(),
			"(RMS %4.1f%%)" % (RMS / self.average() * 100.),
			"total %g\"" % self.sum(), "(%d events:" % self.n(),
			"%g" % self.min(), "- %g)" % self.max(),
			]
	# FormatStatsAsList()
	
	def FormatTimesAsList(self, format_ = {}):
		if isinstance(self.key, basestring): name = str(self.key)
		else: name = "%s[%s]" % (self.key[1], self.key[0])
		
		n = min(self.n(), format_.get('max_events', self.n()))
		format_str = format_.get('format', '%g')
		if not self.entries: return [ name, ] + [ "n/a", ] * n
		
		return [ name, ] \
		  + [ format_str % entry['time'] for entry in self.entries[:n] ]
	# FormatTimesAsList()
	
# class TimeModuleStatsClass

class JobStatsClass:
	def __init__(self, jobName = None):
		self.name = jobName
		self.moduleList = []
		self.moduleStats = {}
	# __init__()
	
	def MaxEvents(self):
		if not self.moduleList: return 0
		return max(map(Stats.n, self.moduleList))
	# MaxEvents()
	
	def MinEvents(self):
		if not self.moduleList: return 0
		return min(map(Stats.n, self.moduleList))
	# MinEvents()
	
	
	# replicate some list/dictionary interface
	def __iter__(self): return iter(self.moduleList)
	def __len__(self): return len(self.moduleList)
	def __getitem__(self, key):
		if isinstance(key, int): return self.moduleList.__getitem__(key)
		else:                    return self.moduleStats.__getitem__(key)
	# __getitem__()
	def __setitem__(self, key, value):
		if isinstance(key, int):
			if key < len(self.moduleList):
				if self.moduleList[key].key != value.key:
					raise RuntimeError(
					  "Trying to overwrite stats of module %r at #%d with module %r"
					  % (self.moduleList[key].key, key, value.key)
					  )
				# if key mismatch
			else:
				self.moduleList.extend([ None ] * (key - len(self.moduleList) + 1))
			index = key
			key = value.key
		else:
			try:
				stats = self.moduleStats[key]
				index = self.moduleList.index(stats)
			except KeyError: # new stats
				index = len(self.moduleList)
				self.moduleList.append(None)
			#
		# if ... else
		self.moduleStats[key] = value
		self.moduleList[index] = value
	# __setitem__()
# class JobStatsClass

#
# format parsing
#
class FormatError(RuntimeError): pass

def ParseTimeModuleLine(line):
	#
	# Format 1 (20140226):
	# TimeModule> run: 1 subRun: 0 event: 10 beziertrackercc BezierTrackerModule 0.231838
	#
	Tokens = line.split()
	
	if (Tokens[0] != 'TimeModule>') \
	  or (Tokens[1] != 'run:') \
	  or (Tokens[3] != 'subRun:') \
	  or (Tokens[5] != 'event:') \
	  or (len(Tokens) != 10) \
	  :
		raise FormatError("TimeModule format not recognized: '%s'" % line)
	
	try:
		return {
			'run': int(Tokens[2]),
			'subRun': int(Tokens[4]),
			'event': int(Tokens[6]),
			'module': (Tokens[7], Tokens[8]),
			'time': float(Tokens[9]),
		}
	except Exception, e:
		raise FormatError \
		  ("TimeModule format not recognized: '%s' (%s)" % (line, str(e)))
	# try ... except
# ParseTimeModuleLine()

def ParseTimeEventLine(line):
	#
	# Format 1 (20140226):
	# TimeModule> run: 1 subRun: 0 event: 10 beziertrackercc BezierTrackerModule 0.231838
	#
	Tokens = line.split()
	
	if (Tokens[0] != 'TimeEvent>') \
	  or (Tokens[1] != 'run:') \
	  or (Tokens[3] != 'subRun:') \
	  or (Tokens[5] != 'event:') \
	  or (len(Tokens) != 8) \
	  :
		raise FormatError("TimeEvent format not recognized: '%s'" % line)
	
	try:
		return {
			'run': int(Tokens[2]),
			'subRun': int(Tokens[4]),
			'event': int(Tokens[6]),
			'time': float(Tokens[7]),
		}
	except Exception, e:
		raise FormatError \
		  ("TimeEvent format not recognized: '%s' (%s)" % (line, str(e)))
	# try ... except
# ParseTimeEventLine()

#
# output
#

class MaxItemLengthsClass:
	def __init__(self, n = 0):
		self.maxlength = [ None ] * n
	
	def add(self, items):
		for iItem, item in enumerate(items):
			try:
				maxlength = self.maxlength[iItem]
			except IndexError:
				self.maxlength.extend([ None ] * (iItem + 1 - len(self.maxlength)))
				maxlength = None
			#
			itemlength = len(str(item))
			if maxlength < itemlength: self.maxlength[iItem] = itemlength
		# for
	# add()
	
	def __len__(self): return len(self.maxlength)
	def __iter__(self): return iter(self.maxlength)
	def __getitem__(self, index): return self.maxlength[index]
	
# class MaxItemLengthsClass


def CenterString(s, w, f = ' '):
	leftFillerWidth = max(0, w - len(s)) / 2
	return f * leftFillerWidth + s + f * (w - leftFillerWidth)
# CenterString()

def LeftString(s, w, f = ' '): return s + f * max(0, w - len(s))

def RightString(s, w, f = ' '): return f * max(0, w - len(s)) + s

def JustifyString(s, w, f = ' '):
	assert len(f) == 1
	tokens = s.split(f)
	if len(tokens) <= 1: return CenterString(s, w, f=f)
	
	# example: 6 words, 7 spaces (in 5 spacers)
	spaceSize = max(1., float(f - sum(map(len, tokens))) / (len(tokens) - 1))
	  # = 1.4
	totalSpace = 0.
	assignedSpace = 0
	s = tokens[0]
	for token in tokens[1:]:
		totalSpace += spaceSize  # 0 => 1.4 => 2.8 => 4.2 => 5.6 => 7.0
		tokenSpace = int(totalSpace - assignedSpace) # int(1.4 1.8 2.2 1.6 2.0)
		s += f * tokenSpace + token # spaces: 1 + 1 + 2 + 1 + 2
		assignedSpace += tokenSpace # 0 => 1 => 2 => 4 => 5 => 7
	# for
	assert assignedSpace == w
	return s
# JustifyString()


class TabularAlignmentClass:
	"""Formats list of data in a table"""
	def __init__(self, specs = [ None, ]):
		"""
		Each format specification applies to one item in each row.
		If no format specification is supplied for an item, the last used format is
		applied. By default, that is a plain conversion to string.
		"""
		self.tabledata = []
		self.formats = {}
		if specs: self.SetDefaultFormats(specs)
	# __init__()
	
	class LineIdentifierClass:
		def __init__(self): pass
		def __call__(self, iLine, rawdata): return None
	# class LineIdentifierClass
	
	class CatchAllLines(LineIdentifierClass):
		def __call__(self, iLine, rawdata): return 1
	# class CatchAllLines
	
	class LineNo(LineIdentifierClass):
		def __init__(self, lineno, success_factor = 5.):
			TabularAlignmentClass.LineIdentifierClass.__init__(self)
			if isinstance(lineno, int): self.lineno = [ lineno ]
			else:                       self.lineno = lineno
			self.success_factor = success_factor
		# __init__()
		
		def matchLine(self, lineno, iLine, rawdata):
			if lineno < 0: lineno = len(rawdata) + lineno
			return iLine == lineno
		# matchLine
		
		def __call__(self, iLine, rawdata):
			success = 0.
			for lineno in self.lineno:
				if self.matchLine(lineno, iLine, rawdata): success += 1.
			if success == 0: return None
			if self.success_factor == 0.: return 1.
			else:                         return success * self.success_factor
		# __call__()
	# class LineNo
	
	class FormatNotSupported(Exception): pass
	
	def ParseFormatSpec(self, spec):
		SpecData = {}
		if spec is None: SpecData['format'] = str
		elif isinstance(spec, basestring): SpecData['format'] = spec
		elif isinstance(spec, dict):
			SpecData = spec
			SpecData.setdefault('format', str)
		else: raise TabularAlignmentClass.FormatNotSupported(spec)
		return SpecData
	# ParseFormatSpec()
	
	def SetRowFormats(self, rowSelector, specs):
		# parse the format specifications
		formats = []
		for iSpec, spec in enumerate(specs):
			try:
				formats.append(self.ParseFormatSpec(spec))
			except TabularAlignmentClass.FormatNotSupported, e:
				raise RuntimeError("Format specification %r (#%d) not supported."
				  % (str(e), iSpec))
		# for specifications
		self.formats[rowSelector] = formats
	# SetRowFormats()
	
	def SetDefaultFormats(self, specs):
		self.SetRowFormats(TabularAlignmentClass.CatchAllLines(), specs)
	
	def AddData(self, data): self.tabledata.extend(data)
	def AddRow(self, *row_data): self.tabledata.append(row_data)
	
	
	def SelectFormat(self, iLine):
		rowdata = self.tabledata[iLine]
		success = None
		bestFormat = None
		for lineMatcher, format_ in self.formats.items():
			match_success = lineMatcher(iLine, self.tabledata)
			if match_success <= success: continue
			bestFormat = format_
			success = match_success
		# for
		return bestFormat
	# SelectFormat()
	
	
	def FormatTable(self):
		# select the formats for all lines
		AllFormats \
		  = [ self.SelectFormat(iRow) for iRow in xrange(len(self.tabledata)) ]
		
		# format all the items
		ItemLengths = MaxItemLengthsClass()
		TableContent = []
		for iRow, rowdata in enumerate(self.tabledata):
			RowFormats = AllFormats[iRow]
			LineContent = []
			LastSpec = None
			for iItem, itemdata in enumerate(rowdata):
				try:
					Spec = RowFormats[iItem]
					LastSpec = Spec
				except IndexError: Spec = LastSpec
				
				Formatter = Spec['format']
				if isinstance(Formatter, basestring):
					ItemContent = Formatter % itemdata
				elif callable(Formatter):
					ItemContent = Formatter(itemdata)
				else:
					raise RuntimeError("Formatter %r (#%d) not supported."
					% (Formatter, iItem))
				# if ... else
				LineContent.append(ItemContent)
			# for items
			ItemLengths.add(LineContent)
			TableContent.append(LineContent)
		# for rows
		
		# pad the objects
		for iRow, rowdata in enumerate(TableContent):
			RowFormats = AllFormats[iRow]
			Spec = AllFormats[iItem]
			for iItem, item in enumerate(rowdata):
				try:
					Spec = RowFormats[iItem]
					LastSpec = Spec
				except IndexError: Spec = LastSpec
				
				fieldWidth = ItemLengths[iItem]
				alignment = Spec.get('align', 'left')
				if alignment == 'right':
					alignedItem = RightString(item, fieldWidth)
				elif alignment == 'justified':
					alignedItem = JustifyString(item, fieldWidth)
				elif alignment == 'center':
					alignedItem = CenterString(item, fieldWidth)
				else: # if alignment == 'left':
					alignedItem = LeftString(item, fieldWidth)
				if Spec.get('truncate', True): alignedItem = alignedItem[:fieldWidth]
				
				rowdata[iItem] = alignedItem
			# for items
		# for rows
		return TableContent
	# FormatTable()
	
	def ToStrings(self, separator = " "):
		return [ separator.join(RowContent) for RowContent in self.FormatTable() ]
	
	def Print(self, stream = sys.stdout):
		print "\n".join(self.ToStrings())
	
# class TabularAlignmentClass




def OPEN(Path, mode = 'r'):
	if Path.endswith('.bz2'): return bz2.BZ2File(Path, mode)
	if Path.endswith('.gz'): return gzip.GzipFile(Path, mode)
	return open(Path, mode)
# OPEN()


if __name__ == "__main__": 
	
	Parser = optparse.OptionParser(usage=UsageMsg, version=Version)
	Parser.set_defaults(PresentMode="ModTable")
	
	Parser.add_option("--eventtable", dest="PresentMode", action="store_const",
	  const="EventTable", help="do not group the pages by node" )
	
	(options, LogFiles) = Parser.parse_args()
	
	bTrackEntries = options.PresentMode in ( 'EventTable', )
	AllStats = JobStatsClass( )
	EventStats \
	  = TimeModuleStatsClass("=== events ===", bTrackEntries=bTrackEntries)
	
	for LogFilePath in LogFiles:
		LogFile = OPEN(LogFilePath, 'r')
		
		LastLine = None
		for iLine, line in enumerate(LogFile):
			
			line = line.strip()
			if line == LastLine: continue # duplicate line
			LastLine = line
			
			if line.startswith("TimeModule> "):
				
				try:
					TimeData = ParseTimeModuleLine(line)
				except FormatError, e:
					print >>sys.stderr, \
					  "Format error on '%s'@%d:" % (LogFilePath, iLine)
					raise
				# try ... except
				
				try:
					ModuleStats = AllStats[TimeData['module']]
				except KeyError:
					ModuleStats = TimeModuleStatsClass \
					  (TimeData['module'], bTrackEntries=bTrackEntries)
					AllStats[TimeData['module']] = ModuleStats
				#
				
				ModuleStats.add(TimeData)
			elif line.startswith("TimeEvent> "):
				try:
					TimeData = ParseTimeEventLine(line)
				except FormatError, e:
					print >>sys.stderr, \
					  "Format error on '%s'@%d:" % (LogFilePath, iLine)
					raise
				# try ... except
				
				EventStats.add(TimeData)
			else: continue
			
		# for line in log file
	# for log files
	
	OutputTable = TabularAlignmentClass()
	
	# present results
	if options.PresentMode == "ModTable":
		OutputTable.AddData([ stats.FormatStatsAsList() for stats in AllStats ])
		OutputTable.AddRow(*EventStats.FormatStatsAsList())
	elif options.PresentMode == "EventTable":
		OutputTable.SetRowFormats \
		  (OutputTable.LineNo(0), [ None, { 'align': 'center' }])
		OutputTable.AddRow("Module", *range(AllStats.MaxEvents()))
		OutputTable.AddData([ stats.FormatTimesAsList() for stats in AllStats ])
		OutputTable.AddRow(*EventStats.FormatTimesAsList())
	else:
		raise RuntimeError("Presentation mode %r not known" % options.PresentMode)
	
	OutputTable.Print()
	
	sys.exit(0)
# main
