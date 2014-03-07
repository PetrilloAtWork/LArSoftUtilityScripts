#!/usr/bin/env python2
#
# Prints statistics from TimeModule out of lar log files
#

import sys, os
import math

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
		self.entries = set() if bTrackEntries else None
	# __init__()
	
	def add(self, data):
		if self.entries is not None:
			eventKey = ( data['run'], data['subRun'], data['event'], )
			if eventKey in self.entries: return False
			self.entries.add(eventKey)
		# if
		Stats.add(self, data['time'])
		return True
	# add()
	
# class TimeModuleStatsClass


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


def TabularAlignment(tabledata, specs = [ None, ]):
	"""Formats list of data in a table
	
	Each format specification applies to one item in each row.
	If no format specification is supplied for an item, the last used format is
	applied. By default, that is a plain conversion to string.
	"""
	
	# parse the format specifications
	Specs = []
	for iSpec, spec in enumerate(specs):
		SpecData = {}
		if spec is None: SpecData['format'] = str
		elif isinstance(spec, basestring): SpecData['format'] = spec
		elif isinstance(spec, dict): SpecData = spec
		else:
			raise RuntimeError("Format specification %r (#%d) not supported."
			  % (spec, iSpec))
		Specs.append(SpecData)
	# for specifications
	
	# format all the items
	ItemLengths = MaxItemLengthsClass()
	TableContent = []
	for rowdata in tabledata:
		LineContent = []
		LastSpec = None
		for iItem, itemdata in enumerate(rowdata):
			try:
				Spec = Specs[iItem]
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
	for rowdata in TableContent:
		for iItem, item in enumerate(rowdata):
			try:
				Spec = Specs[iItem]
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
# TabularAlignment()


def TableToStrings(TableContent, separator = " "):
	return [ separator.join(RowContent) for RowContent in TableContent ]
# TableToStrings()


if __name__ == "__main__": 
	
	LogFiles = sys.argv[1:]
	
	AllStats = {}
	ModulesList = []
	
	for LogFilePath in LogFiles:
		LogFile = open(LogFilePath, 'r')
		
		for iLine, line in enumerate(LogFile):
			
			line = line.strip()
			if not line.startswith("TimeModule> "): continue
			
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
				ModuleStats \
				  = TimeModuleStatsClass(TimeData['module'], bTrackEntries=True)
				ModulesList.append(TimeData['module'])
				AllStats[TimeData['module']] = ModuleStats
			#
			
			ModuleStats.add(TimeData)
			
		# for line in log file
	# for log files
	
	# present results
	TableData = []
	for ModuleKey in ModulesList:
		ModuleStats = AllStats[ModuleKey]
		if (ModuleStats.n() == 0) or (ModuleStats.sum() == 0.):
			OutputData = [ " ".join(ModuleStats.key), "n/a" ]
		else:
			RMS = ModuleStats.rms() if (ModuleStats.n() != 0) else 0.
			OutputData = [ 
				"%s[%s]" % (ModuleStats.key[1], ModuleStats.key[0]),
				"%g\"" % ModuleStats.average(),
				"(RMS %4.1f%%)" % (RMS / ModuleStats.average() * 100.),
				"total %g\"" % ModuleStats.sum(), "(%d events:" % ModuleStats.n(),
				"%g" % ModuleStats.min(), "- %g)" % ModuleStats.max(),
				]
		# if
		TableData.append(OutputData)
	# for
	
	TableContent = TabularAlignment(TableData)
	print "\n".join(TableToStrings(TableContent))
	
	sys.exit(0)
# main
