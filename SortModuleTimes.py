#!/usr/bin/env python2
# 
# Brief:  parses and outputs timing information from art logs
# Author: petrillo@fnal.gov
# Date:   201403??
#
# Run with '--help' argument for usage instructions.
# 
# Version:
# 1.0 (petrillo@fnal.gov)
#   first version
# 1.1 (petrillo@fnal.gov)
#   support for compressed input files; added command line interface
# 1.2 (petrillo@fnal.gov)
#   new mode to expose all the events
# 1.3 (petrillo@fnal.gov)
#   permissive option to ignore errors in the input
# 1.4 (20140618, petrillo@fnal.gov)
#   updating from optparse to argparse
# 1.5 (20140711, petrillo@fnal.gov)
#   improved parsing relying on end-of-event markers; using python 2.7
#

import sys, os
import math
import gzip
try: import bz2
except ImportError: pass
from collections import OrderedDict


Version = "%(prog)s 1.5"
__doc__ = "Prints statistics of the module timings based on the information from the Timing service."

#
# statistics collection
#
def signed_sqrt(value):
	"""Returns sign(x) * sqrt(abs(x))"""
	if value >= 0.: return math.sqrt(value)
	else: return -math.sqrt(-value)
# signed_sqrt()


class Stats:
	"""Statistics collector.
	
	This class accumulates statistics on a single variable.
	A new entry is added by add(), that allowes an optional weight.
	At any time, the following information about the sample of x is available:
	- n():       number of additions
	- weights(): total weight (matches n() unless weights are specified)
	- sum():     weighted sum of x
	- min():     minimum value of x seen so far (None if no entries yet)
	- max():     maximum value of x seen so far (None if no entries yet)
	- sumsq():   weighted sum of x^2
	- average(): weighted average of x (0 if no entries yet)
	- sqaverage(): weighted average of x^2 (0 if no entries yet)
	- rms():     the Root Mean Square (including weights)
	- rms2():    the square of the RMS (including weights)
	- stdev():   standard deviation (0 if less than two events)
	- stdevp():  an alias for rms()
	
	The construction allows to specify bFloat = false, in which case the
	accumulators are integral types (int) until a real type value or weight is
	add()ed.
	"""
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


class EventKeyClass(tuple):
	"""Event identifier: run, subrun and event numbers."""
	def run(self): return self[0]
	def subRun(self): return self[1]
	def event(self): return self[2]
	
	def __str__(self):
		return "run %d subRun %d event %d" \
		  % (self.run(), self.subRun(), self.event())
	# __str__()
# class EventKeyClass


class ModuleKeyClass(tuple):
	"""Module instance identifier: module label and instance name."""
	def name(self): return self[1]
	def instance(self): return self[0]
	
	def __str__(self): return "%s[%s]" % (self.name(), self.instance())
# class ModuleKeyClass


class EntryDataClass(object):
	"""A flexible data structure for per-event information.
	
	The object is associated to a specific, unique event.
	It can represent either the execution of the full event, or of a specific
	module on that event.
	The object gathers custom data; the standard data members:
	- time (default: None): seconds elapsed by the event
	- module (default: not defined): the module identification
	If time is None, we assume this event was never completed.
	The presence of a module data member implies that this object descrivbes a
	module execution rather than the whole event.
	"""
	def __init__(self, eventKey, **kargs):
		self.data = kargs
		self.data.setdefault('time', None)
		self.eventKey = eventKey
	# __init__()
	
	def __getattr__(self, attrName):
		# we expect this will be called only if no attrName already exists
		try: return self.data[attrName]
		except KeyError: raise AttributeError(attrName)
	# __getattr__()
	
	def time(self):
		try: return self.data['time']
		except KeyError: return None
	# time()
	
	def isModule(self):
		try: return bool(self.module)
		except AttributeError: return False
	# isEvent()
	
	def isEvent(self): return not self.isModule()
	
	def isMissing(self): return self.time() is None
	
	def SetMissing(self): self.data['time'] = None
	
	def __str__(self):
		s = str(self.eventKey)
		if self.isModule(): s += " module " + str(self.module)
		else:               s += " event"
		s += ": ";
		if self.time() is None: s += "(n/a)"
		else: s += "%g s" % self.time()
		return s
	# __str__()
	
# class EntryDataClass


class TimeModuleStatsClass(Stats):
	"""Collects statistics about execution time.
	
	This class collects statistics about execution time of a module or the whole
	event.
	The timing information is added by add() function, with as argument an
	instance of EntryDataClass.
	Optionally, the object can keep track of all the entries separately.
	The order of insertion of the events is also recorded.
	By default, this does not happen and only statistics are stored.
	
	The sample can be forcibly filled with empty entries. The idea is that one
	event is added to the sample only when the information about its timing is
	available. If we are tracking the event keys, we can check if we have all
	the events and, if some event keys are missing, we can add an empty entry for
	them so that we have the correct number of enrties in the sample.
	This is achieved by a call to complete().
	Note that to keep the order of the events the correct one one should check
	if the previous event is present or not, and complete() with it, before
	adding a new event. If the completion is performed after the new event is
	added, the previous event will be added after the new one, when complete()
	is actually called.
	"""
	def __init__(self, moduleKey, bTrackEntries = False):
		"""Constructor: specifies the module we collect information about.
		
		If the flag bTrackEntries is true, all the added events are stored singly.
		"""
		Stats.__init__(self)
		self.key = moduleKey
		self.entries = OrderedDict() if bTrackEntries else None
	# __init__()
	
	def add(self, data):
		"""Adds a time to the sample.
		
		The argument data is an instance of EntryDataClass, that includes both
		event identification and timing information.
		Its time() is used as the value of the statistic; if the entry has no time
		(None), the event information is considered to be missing.
		"""
		if self.entries is not None:
			if data.eventKey in self.entries: return False
			self.entries[data.eventKey] = data
		# if
		if not data.isMissing(): Stats.add(self, data.time())
		return True
	# add()
	
	def complete(self, eventKeys):
		"""Makes sure that an entry for each of the keys in eventKeys is present.
		
		For event keys already known, nothing happens. For new event keys, an
		empty entry is added at the end of the list, with no time information.
		Note that the events are added at the bottom of the list, in the relative
		order in eventKeys.
		
		If we are not tracking the events, nothing happens ever.
		"""
		if self.entries is None: return 0
		if (len(self.entries) > 1): eventKeys = eventKeys[-1:]
		res = 0
		for eventKey in eventKeys:
			if self.add(EntryDataClass(eventKey)): res += 1
		return res
	# complete()
	
	def getEvents(self):
		"""Returns the list of known event keys (if tracking the events)."""
		return [] if self.entries is None else self.entries.keys()
	# getEvents()
	
	def getEntries(self):
		"""Returns a list of the event statistics (if tracking the events)."""
		return [] if self.entries is None else self.entries.values()
	# getEntries()
	
	def nEntries(self):
		"""Returns the number of recorded entries (throws if not tracking)."""
		return len(self.entries)
	# nEntries()
	
	def nEvents(self):
		"""Returns the number of valid entries (events with timing)."""
		return self.n()
	# nEvents()
	
	def hasEmptyData(self):
		"""Returns whethere there are entries without timing information.
		
		Note: throws if not tracking events.
		"""
		return self.nEntries() > self.nEvents()
	# hasEmptyData()
	
	def FormatStatsAsList(self, format_ = None):
		"""Prints the collected information into a list.
		
		The list of strings includes a statistics ID (based on the key), an
		average time, a relative RMS in percent, the total time and the recorded
		the number of events with timing information and the timing extrema.
		
		The format dictionary can contain format directives, for future use (no
		format directive is currently supported).
		"""
		if isinstance(self.key, basestring): name = str(self.key)
		else: name = str(self.key)
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
		"""Prints the collected information into a list.
		
		The list of strings includes a statistics ID (based on the key), and
		a time entry for each of the events stored (with holes for the events
		with missing time).
		The format dictionary can contain format directives; the ones supported
		so far are:
		- 'max_events' (int): limit the number of events to the first max_events
		  (by default, all the available entries are printed)
		- 'format' (string, default: '%g'): the C-style formatting string for the
		  numeric timings
		"""
		if isinstance(self.key, basestring): name = str(self.key)
		else: name = str(self.key)
		
		n = min(self.nEntries(), format_.get('max_events', self.nEntries()))
		format_str = format_.get('format', '%g')
		if not self.entries: return [ name, ] + [ "n/a", ] * n
		
		output = [ name, ]
		for i, entry in enumerate(self.entries.values()):
			if i >= n: break
			if entry is None or entry.isMissing(): output.append("n/a")
			else: output.append(format_str % entry.time())
		# for
		return output
	# FormatTimesAsList()
	
# class TimeModuleStatsClass


class JobStatsClass:
	"""A class collecting timing information from different modules.
	
	This is mostly a dictionary structure, but it is sorted.
	The supported interface includes access by key (dictionary-like) or by
	position (list-like).
	"""
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
					  "Trying to overwrite stats of module %s at #%d with module %s"
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
class FormatError(RuntimeError):
	def __init__(self, msg, **kargs):
		RuntimeError.__init__(self, msg)
		self.data = kargs
	# __init__()
# class FormatError

def ParseTimeModuleLine(line):
	"""Parses a line to extract module timing information.
	
	The line must be known to contain module timing information.
	The function returns a EntryDataClass including the timing information, or
	raises a FormatError if the line has no valid format.
	
	Format 1 (20140226):
	
	TimeModule> run: 1 subRun: 0 event: 10 beziertrackercc BezierTrackerModule 0.231838
	"""
	Tokens = line.split()
	
	ModuleKey = None
	EventKey = None
	time = None
	
	# Format 1 parsing:
	try:
		EventKey = EventKeyClass((int(Tokens[2]), int(Tokens[4]), int(Tokens[6])))
		ModuleKey = ModuleKeyClass((Tokens[7], Tokens[8]))
		time=float(Tokens[9])
	except Exception, e:
		raise FormatError(
		  "TimeModule format not recognized: '%s' (%s)" % (line, str(e)),
		  type="Module", event=EventKey, module=ModuleKey
		  )
	# try ... except
	
	# validation of Format 1
	if (Tokens[0] != 'TimeModule>') \
	  or (Tokens[1] != 'run:') \
	  or (Tokens[3] != 'subRun:') \
	  or (Tokens[5] != 'event:') \
	  or (len(Tokens) != 10) \
	  :
		raise FormatError \
		  ("TimeModule format not recognized: '%s'" % line, type="Module")
	# if
	
	return EntryDataClass(EventKey, module=ModuleKey, time=time)
# ParseTimeModuleLine()


def ParseTimeEventLine(line):
	"""Parses a line to extract event timing information.
	
	The line must be known to contain event timing information.
	The function returns a EntryDataClass including the timing information, or
	raises a FormatError if the line has no valid format.
	
	Format 1 (20140226):
	
	TimeEvent> run: 1 subRun: 0 event: 10 0.231838
	"""
	Tokens = line.split()
	
	EventKey = None
	time = None
	try:
		EventKey = EventKeyClass((int(Tokens[2]), int(Tokens[4]), int(Tokens[6])))
		time = float(Tokens[7])
	except Exception, e:
		raise FormatError(
		  "TimeEvent format not recognized: '%s' (%s)" % (line, str(e)),
		  type="Event", event=EventKey
		  )
	# try ... except
	
	if (Tokens[0] != 'TimeEvent>') \
	  or (Tokens[1] != 'run:') \
	  or (Tokens[3] != 'subRun:') \
	  or (Tokens[5] != 'event:') \
	  or (len(Tokens) != 8) \
	  :
		raise FormatError("TimeEvent format not recognized: '%s'" % line,
		  type="Event", event=EventKey)
	# if
	
	return EntryDataClass(EventKey, time=time)
# ParseTimeEventLine()


def OPEN(Path, mode = 'r'):
	"""Open a file (possibly a compressed one).
	
	Support for modes other than 'r' (read-only) are questionable.
	"""
	if Path.endswith('.bz2'): return bz2.BZ2File(Path, mode)
	if Path.endswith('.gz'): return gzip.GzipFile(Path, mode)
	return open(Path, mode)
# OPEN()


def ParseInputFile(InputFilePath, AllStats, EventStats, options):
	"""Parses a log file.
	
	The art log file at InputFilePath is parsed.
	The per-module statistics are added to the existing in AllStats (an instance
	of JobStatsClass), creating new ones as needed. Similarly, per-event
	statistics are added to EventStats (a TimeModuleStatsClass instance).
	
	options class can contain the following members:
	- Permissive (default: false): do not bail out when a format error is found;
	  the entry is typically skipped. This often happens because the output line
	  of the timing information is interrupted by some other output.
	- MaxEvents (default: all events): collect statistics for at most MaxEvents
	  events (always the first ones)
	- CheckDuplicates (default: false): enables the single-event tracking, that
	  allows to check for duplicates
	
	It returns the number of errors encountered.
	"""
	def CompleteEvent(CurrentEvent, EventStats, AllStats):
		"""Make sure that CurrentEvent is known to all stats."""
		EventStats.complete(( CurrentEvent, ))
		for ModuleStats in AllStats:
			ModuleStats.complete(EventStats.getEvents())
	# CompleteEvent()
	
	
	LogFile = OPEN(InputFilePath, 'r')
	
	nErrors = 0
	LastLine = None
	CurrentEvent = None
	for iLine, line in enumerate(LogFile):
		
		line = line.strip()
		if line == LastLine: continue # duplicate line
		LastLine = line
		
		if line.startswith("TimeModule> "):
			
			try:
				TimeData = ParseTimeModuleLine(line)
			except FormatError, e:
				nErrors += 1
				msg = "Format error on '%s'@%d" % (InputFilePath, iLine + 1)
				try: msg += " (%s)" % str(e.data['type'])
				except KeyError: pass
				try: msg += ", for event " + str(e.data['event'])
				except KeyError: pass
				try: msg += ", module " + str(e.data['module'])
				except KeyError: pass
				print >>sys.stderr, msg
				if not options.Permissive: raise
				else:                      continue
			# try ... except
			
			try:
				ModuleStats = AllStats[TimeData.module]
			except KeyError:
				ModuleStats = TimeModuleStatsClass \
				  (TimeData.module, bTrackEntries=options.CheckDuplicates)
				AllStats[TimeData.module] = ModuleStats
			#
			
			ModuleStats.add(TimeData)
		elif line.startswith("TimeEvent> "):
			try:
				TimeData = ParseTimeEventLine(line)
			except FormatError, e:
				nErrors += 1
				msg = "Format error on '%s'@%d" % (InputFilePath, iLine + 1)
				try: msg += " (%s)" % str(e.data['type'])
				except KeyError: pass
				try: msg += ", for event " + str(e.data['event'])
				except KeyError: pass
				try: msg += ", module " + str(e.data['module'])
				except KeyError: pass
				print >>sys.stderr, msg
				if not options.Permissive: raise
				else:                      continue
			# try ... except
			
			EventStats.add(TimeData)
			if (options.MaxEvents >= 0) \
			  and (EventStats.n() >= options.MaxEvents):
				if CurrentEvent: CompleteEvent(CurrentEvent, EventStats, AllStats)
				raise NoMoreInput
		else:
			TimeData = None
			continue
		
		if (CurrentEvent != TimeData.eventKey):
			if TimeData and CurrentEvent:
				CompleteEvent(CurrentEvent, EventStats, AllStats)
			CurrentEvent = TimeData.eventKey
		# if
	# for line in log file
	if CurrentEvent: CompleteEvent(CurrentEvent, EventStats, AllStats)
	
	return nErrors
# ParseInputFile()


#
# output
#

class MaxItemLengthsClass:
	"""A list with the maximum length of items seen.
	
	Facilitates the correct sizing of a table in text mode.
	
	When a list of strings is add()ed, for each position in the list the length
	of the string in that position is compared to the maximum one seen so far in
	that position, and that maximum value is updated if proper.
	"""
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
	"""Returns the string s centered in a width w, padded by f on both sides."""
	leftFillerWidth = max(0, w - len(s)) / 2
	return f * leftFillerWidth + s + f * (w - leftFillerWidth)
# CenterString()

def LeftString(s, w, f = ' '):
	"""Returns the string s in a width w, padded by f on the right."""
	return s + f * max(0, w - len(s))

def RightString(s, w, f = ' '):
	"""Returns the string s in a width w, padded by f on the left."""
	return f * max(0, w - len(s)) + s

def JustifyString(s, w, f = ' '):
	"""Recomputes the spaces between the words in s so that they fill a width w.
	
	The original spacing is lost. The string is split in words by str.split().
	The character f is used to create the filling spaces between the words.
	Note that the string can result longer than w if the content is too long.
	"""
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
		If no format specification is supplied for an item, the last used format
		is applied. By default, that is a plain conversion to string.
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
			Spec = AllFormats[iRow]
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


################################################################################
### main program
###
if __name__ == "__main__": 
	import argparse
	
	###
	### parse command line arguments
	###
	Parser = argparse.ArgumentParser(description=__doc__)
	Parser.set_defaults(PresentMode="ModTable")
	
	# positional arguments
	Parser.add_argument("LogFiles", metavar="LogFile", nargs="+",
	  help="log file to be parsed")
	
	# options
	Parser.add_argument("--eventtable", dest="PresentMode", action="store_const",
	  const="EventTable", help="do not group the pages by node")
	Parser.add_argument("--allowduplicates", '-D', dest="CheckDuplicates",
	  action="store_false", help="do not check for duplicate entries")
	Parser.add_argument("--maxevents", dest="MaxEvents", type=int, default=-1,
	  help="limit the number of parsed events to this (negative: no limit)")
	Parser.add_argument("--permissive", dest="Permissive", action="store_true",
	  help="treats input errors as non-fatal [%(default)s]")
	Parser.add_argument('--version', action='version', version=Version)
	
	options = Parser.parse_args()
	
	if options.PresentMode in ( 'EventTable', ):
		options.CheckDuplicates = True
	
	###
	### parse all inputs, collect the information
	###
	
	# per-module statistics
	AllStats = JobStatsClass( )
	# per-event statistics
	EventStats = TimeModuleStatsClass \
	  ("=== events ===", bTrackEntries=options.CheckDuplicates)
	
	class NoMoreInput: pass
	
	nErrors = 0
	try:
		if options.MaxEvents == 0: raise NoMoreInput # wow, that was quick!
		for LogFilePath in options.LogFiles:
			nErrors += ParseInputFile(LogFilePath, AllStats, EventStats, options)
		
	except NoMoreInput: pass
	
	# give a bit of separation between error messages and actual output
	if nErrors > 0: print >>sys.stderr
	
	###
	### print the results
	###
	if (AllStats.MaxEvents() == 0) and (EventStats.nEntries() == 0):
		print "No time statistics found."
		sys.exit(1)
	# if
	
	OutputTable = TabularAlignmentClass()
	
	# present results
	if options.PresentMode == "ModTable":
		# fill the module stat data into the table
		OutputTable.AddData([ stats.FormatStatsAsList() for stats in AllStats ])
		# then the event data
		OutputTable.AddRow(*EventStats.FormatStatsAsList())
	elif options.PresentMode == "EventTable":
		# set some table formatting options
		OutputTable.SetRowFormats \
		  (OutputTable.LineNo(0), [ None, { 'align': 'center' }])
		# header row
		OutputTable.AddRow("Module", *range(AllStats.MaxEvents()))
		# fill the module stat data into the table
		OutputTable.AddData([ stats.FormatTimesAsList() for stats in AllStats ])
		# then the event data
		OutputTable.AddRow(*EventStats.FormatTimesAsList())
	else:
		raise RuntimeError("Presentation mode %r not known" % options.PresentMode)
	
	OutputTable.Print()
	
	###
	### say goodbye
	###
	if nErrors > 0:
		print >>sys.stderr, "%d errors were found in the input files." % nErrors
	sys.exit(nErrors)
# main
