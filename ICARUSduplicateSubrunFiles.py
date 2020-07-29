#!/usr/bin/env python3

import os, sys
import re
import datetime

class OutputFilePathParser:
    """
    
    Reference path:
    
    root://fndca1.fnal.gov:1094/pnfs/fnal.gov/usr/icarus/archive/sam_managed_users/icaruspro/data/mc/reco2/root/Production2020/poms_icarus_prod_nu_numioffaxis/MCC/v08_48_00/1.1/simulation_numi_20200419T072758_2-0021_gen_20200419T204556_filter_20200420T100017_g4_20200421T193723_detsim_20200421T234309_reco1_20200422T040114_reco2.root
    
    """
    
    StagePattern = re.compile(r'_(\d{8})T(\d{6})_([A-Za-z0-9]+)$')
    FirstStagePattern = re.compile(r'_(\d{8})T(\d{6})_(\d+)-(\d+)_([A-Za-z0-9]+)$')
    
    def __init__(self, path): self.parse(path)
    
    def parse(self, path):
        if "://" in path:
            self.protocol, path = path.split("://", 1)
        else: self.protocol = None
        dirPath, fileName = os.path.split(path)
        self.fileBaseName, self.fileSuffix = os.path.splitext(fileName)
        self._parseBaseName(self.fileBaseName)
        self.dirs = dirPath.split(os.path.sep)
        if self.protocol:
            self.hostname = self.dirs[0]
            self.dirs[0] = ''
        else: self.hostname = None
        if self.hostname and ':' in self.hostname:
            try:
                self.hostname, protocolPort = self.hostname.rsplit(':', 1)
                self.protocolPort = int(protocolPort)
            except TypeError: self.protocolPort = None
        # if
        return self
    # parse()
    
    
    def fileName(self): return self.fileBaseName + self.fileSuffix
    def dirPath(self): return os.path.sep.join(self.dirs)
    def filePath(self):
        return os.path.sep.join([ self.dirPath(), self.fileName() ])
    def hasRun(self):
        return self.stages and self.stages[0].hasRun()
    def runAndSubRun(self):
        return self.stages[0].runAndSubRun() if self.hasRun() else None
    def run(self):
        return self.stages[0].run if self.hasRun() else None
    def subRun(self):
        return self.stages[0].subRun if self.hasRun() else None
    
    def dump(self):
        msg = []
        if self.protocol: msg.append("Protocol:  '{}'".format(self.protocol))
        if self.hostname: msg.append("Host name: '{}'".format(self.hostname))
        if self.protocolPort:
            msg.append("     port:  {}".format(self.protocolPort))
        msg.append("File path: '{}'".format(self.filePath()))
        msg.append("Directory: '{}'".format(self.dirPath()))
        msg.append("Dir. list: {}".format(self.dirs))
        msg.append("File name: '{}'".format(self.fileName()))
        msg.append("Base name: '{}'".format(self.fileBaseName))
        msg.append("Config   : '{}'".format(self.configurationName))
        msg.append("Stages ({:d}):".format(len(self.stages)))
        for iStage, stage in enumerate(self.stages):
            msg.append("  [{:d}] {}".format(iStage+1, stage.dump()))
        msg.append("Suffix   : '{}'".format(self.fileSuffix))
        return "\n".join(msg)
    # dump()
    
    def __str__(self):
        s = ""
        if self.protocol: s += self.protocol + "://"
        if self.hostname:
            s += self.hostname
            if self.protocolPort: s += ":" + str(self.protocolPort)
        s += self.filePath()
        return s
    # __str__()
    
    
    class JobStageClass:
        
        def __init__(self, tag, date, time, process, run=None, subRun=None):
            self.tag = tag
            self.date = self.parseDateTime(date, time)
            self.process = process
            self.run = None if run is None else int(run)
            self.subRun = None if subRun is None else int(subRun)
        # __init__()
        @staticmethod
        def parseDate(date):
            date = int(date)
            l = []
            l.insert(0, date % 100)
            date //= 100
            l.insert(0, date % 100)
            date //= 100
            l.insert(0, date % 10000)
            return l
        # parseDate()
        @staticmethod
        def parseTime(time):
            realtime = float(time)
            time = int(time)
            d = {}
            d['microsecond'] = int(realtime * 1e6) - time * 1000000
            d['second'] = time % 100
            time //= 100
            d['minute'] = time % 100
            time //= 100
            d['hour'] = time % 100
            return d
        # parseDate()
        @staticmethod
        def parseDateTime(date, time):
            return datetime.datetime(
              *OutputFilePathParser.JobStageClass.parseDate(int(date)),
              **OutputFilePathParser.JobStageClass.parseTime(float(time))
              )
        # parseDateTime()
        def hasRun(self): return self.run is not None or self.subRun is not None
        def runAndSubRun(self):
            return ( self.run, self.subRun ) if self.hasRun() else None
        def __str__(self): return self.tag
        def dump(self):
            s = self.process
            if self.hasRun():
                elements = []
                if self.run is not None:
                    elements.append("run {}".format(self.run))
                if self.subRun is not None:
                    elements.append("subrun {}".format(self.subRun))
                s += " (" + " ".join(elements) + ")";
            # if
            if self.date is not None: s += " on " + str(self.date)
            return s
    # class JobStageClass
    
    def _parseBaseName(self, baseName):
        
        
        parseMe = baseName
        self.stages = []
        while True:
            match = self.StagePattern.search(parseMe)
            if not match: break
            parseMe = parseMe[:match.start()]
            self.stages.insert(0, 
              OutputFilePathParser.JobStageClass(
                tag=match.group(0),
                date=match.group(1), time=match.group(2),
                process=match.group(3),
              ))
        # while
        match = self.FirstStagePattern.search(parseMe)
        if match:
            parseMe = parseMe[:match.start()]
            self.stages.insert(0, 
              OutputFilePathParser.JobStageClass(
                tag=match.group(0),
                date=match.group(1), time=match.group(2),
                run=int(match.group(3)), subRun=int(match.group(4)),
                process=match.group(5),
              ))
        # if
        self.configurationName = parseMe
    # _parseBaseName()
    
# class OutputFilePathParser


if __name__ == "__main__":
    
    __doc__ = """
Parses the specified file lists and reports duplicate subruns.
Subruns are detected parsing the file name, for which a specific pattern is expected.
    """
    
    import sys
    import argparse
    import logging
    
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger()
    
    argParser = argparse.ArgumentParser(description=__doc__)
    
    argParser.set_defaults(PrintUnique=True, PrintDuplicate=False)
    
    argParser.add_argument("sources", nargs='*', default=[],
      help="source files (if none, reads from standard input)")
    
    argParser.add_argument("--print-unique", "-u", dest="PrintUnique",
      action="store_true", help="print file names with unique subruns")
    argParser.add_argument("--skip-unique", "-U", dest="PrintUnique",
      action="store_false", help="do not print file names with unique subruns")
    
    argParser.add_argument("--print-duplicate", "-d", dest="PrintDuplicate",
      action="store_true", help="print file names with duplicate subruns")
    argParser.add_argument("--skip-duplicate", "-D", dest="PrintDuplicate",
      action="store_false", help="do not print file names with duplicate subruns")
    
    argParser.add_argument("--summary", "-s", dest="PrintSummary",
      action="store_true", help="print a summary of unique and duplicate files")
    
    args = argParser.parse_args()
    
    sourceFiles = args.sources[:] if args.sources else [ sys.stdin ]
    manySources = len(sourceFiles) > 1
    
    nErrors = 0
    nFiles = 0
    nDuplicates = 0
    met = {}
    formatProvenance \
      = (lambda name, line: "'{}' line {:d}".format(name, line)) if manySources \
        else (lambda name, line: "line {:d}".format(line))
    for source in sourceFiles:
        try:
            sourceFile = source if hasattr(source, 'readlines') else open(source, 'r')
        except IOError:
            logger.error("Can't open input file '%s': skipped.", source)
            nErrors += 1
            continue
        # try ... except
        sourceName = sourceFile.name
        for iLine, arg in enumerate(sourceFile.readlines()):
            path = arg.strip()
            if not path or path[0] == '#': continue
            nFiles += 1
            parsed = OutputFilePathParser(path)
            #print(parsed.dump())
            key = parsed.runAndSubRun() if parsed.hasRun() else None
            if key not in met:
                if args.PrintUnique: print(arg, end='')
                if key is not None: met[key] = ( path, [ ( sourceName, iLine ), ])
            else:
                previouslyMet = met[key]
                if len(previouslyMet[1]) == 1: nDuplicates += 1
                previouslyMet[1].append(( sourceName, iLine ))
                if args.PrintDuplicate:
                    print("# {} (R:{} S:{}) duplicate of {} ('{}')".format(
                      path, parsed.run(), parsed.subRun(),
                      formatProvenance(*(previouslyMet[1][0])), previouslyMet[0]
                      ), file=sys.stderr, 
                      )
                # if
                
            # if ... else
        # for line in source file
    # for source files
    
    # global summary
    if args.PrintSummary:
        msg = "%d file names read" % nFiles
        if manySources: msg += " from %d file lists" % len(sourceFiles)
        if len(met) == nFiles:
            msg += ", all unique."
        else:
            msg += ", %d unique files found, %d have" % ( len(met), nDuplicates)
            maxDuplicates = max( len(l[1]) for l in met.values() )
            if maxDuplicates > 1: msg += " up to %d duplicates" % (maxDuplicates - 1)
            else:                 msg += " one duplicate"
        msg += "."
        logging.info(msg)
    # if global summary
    
    sys.exit(1 if nErrors else 0)
# main
