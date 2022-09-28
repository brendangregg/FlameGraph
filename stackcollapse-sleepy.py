#!/usr/bin/env python3

# Parser for *.sleepy files.

# Copyright 2008-2017 Jose Fonseca
# 2022: Adapted by fredx100 for use within the FlameGraph project.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.

# You should have received a copy of the GNU Lesser General Public
# License along with this program. If not, see
# <https://www.gnu.org/licenses/>.

# See also:
#  -  http://www.codersnotes.com/sleepy/
#  -  https://github.com/jrfonseca/gprof2dot

import sys
import re
from zipfile import ZipFile

_symbol_re = re.compile(
    r'^(?P<id>\w+)' +
    r'\s+"(?P<module>[^"]*)"' +
    r'\s+"(?P<procname>[^"]*)"' +
    r'\s+"(?P<sourcefile>[^"]*)"' +
    r'\s+(?P<sourceline>\d+)$'
)

def open_entry(database, name):
    # Some versions of verysleepy use lowercase filenames
    for database_name in database.namelist():
        if name.lower() == database_name.lower():
            name = database_name
            break

    return database.open(name, 'r')

def parse_symbols():
    for line in open_entry(database, 'Symbols.txt'):
        line = line.decode('UTF-8').rstrip('\r\n')

        mo = _symbol_re.match(line)
        if mo:
            symbol_id, module, procname, sourcefile, sourceline = mo.groups()
            symbols[symbol_id] = module + ':' + procname

def parse_callstacks():
    for line in open_entry(database, 'Callstacks.txt'):
        line = line.decode('UTF-8').rstrip('\r\n')

        fields = line.split()
        samples = float(fields[0])
        callstack_list = [symbols[symbol_id] for symbol_id in fields[1:]]
        callstack_list.reverse()
        callstack = ';'.join(callstack_list)

        if callstack in callstacks:
            callstacks[callstack] += samples;
        else:
            callstacks[callstack] = samples;

def parse_stats():
    for line in open_entry(database, 'Stats.txt'):
        line = line.decode('UTF-8').rstrip('\r\n')

        prop,value = line.split(": ")
        if prop.lower() == 'duration':
            total_time = float(value)
        if prop.lower() == 'samples':
            total_samples = int(value)

    return (float(total_samples) / total_time)

if len(sys.argv) == 2:
    symbols = {}
    callstacks = {};

    database = ZipFile(sys.argv[1])

    parse_symbols()
    parse_callstacks()
    sample_time_multiplier = parse_stats()

    for callstack,sample_time in sorted(callstacks.items()):
        print(callstack + ' ' + str(int(sample_time * sample_time_multiplier)))
else:
    print("ERROR: incorrect arguments.\n")
    print("USAGE:\n\tstackcollapse-sleepy.py <filename>")
