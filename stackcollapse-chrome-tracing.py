#!/usr/bin/python
#
# stackcolllapse-chrome-tracing.py	collapse Trace Event Format [1]
#             callstack events into single lines.
#
# [1] https://github.com/catapult-project/catapult/wiki/Trace-Event-Format
#
# USAGE: ./stackcollapse-chrome-tracing.py input_json [input_json...] > outfile
#
# Example input:
#
# {"traceEvents":[
#     {"pid":1,"tid":2,"ts":0,"ph":"X","name":"Foo","dur":50},
#     {"pid":1,"tid":2,"ts":10,"ph":"X","name":"Bar","dur":30}
# ]}
#
# Example output:
#
#  Foo 20.0
#  Foo;Bar 30.0
#
# Input may contain many stack trace events from many processes/threads.
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at docs/cddl1.txt or
# http://opensource.org/licenses/CDDL-1.0.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at docs/cddl1.txt.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
# 4-Jan-2018	Marcin Kolny	Created this.
import argparse
import json

stack_identifiers = {}


class Event:
    def __init__(self, label, timestamp, dur):
        self.label = label
        self.timestamp = timestamp
        self.duration = dur
        self.total_duration = dur

    def get_stop_timestamp(self):
        return self.timestamp + self.duration


def cantor_pairing(a, b):
    s = a + b
    return s * (s + 1) / 2 + b


def get_trace_events(trace_file, events_dict):
    json_data = json.load(trace_file)

    for entry in json_data['traceEvents']:
        if entry['ph'] == 'X':
            cantor_val = cantor_pairing(int(entry['tid']), int(entry['pid']))
            if 'dur' not in entry:
                continue
            if cantor_val not in events_dict:
                events_dict[cantor_val] = []
            events_dict[cantor_val].append(Event(entry['name'], float(entry['ts']), float(entry['dur'])))


def load_events(trace_files):
    events = {}

    for trace_file in trace_files:
        get_trace_events(trace_file, events)

    for key in events:
        events[key].sort(key=lambda x: x.timestamp)

    return events


def save_stack(stack):
    first = True
    event = None
    identifier = ''

    for event in stack:
        if first:
            first = False
        else:
            identifier += ';'
        identifier += event.label

    if not event:
        return

    if identifier in stack_identifiers:
        stack_identifiers[identifier] += event.total_duration
    else:
        stack_identifiers[identifier] = event.total_duration


def load_stack_identifiers(events):
    event_stack = []

    for e in events:
        if not event_stack:
            event_stack.append(e)
        else:
            while event_stack and event_stack[-1].get_stop_timestamp() <= e.timestamp:
                save_stack(event_stack)
                event_stack.pop()

            if event_stack:
                event_stack[-1].total_duration -= e.duration

            event_stack.append(e)

    while event_stack:
        save_stack(event_stack)
        event_stack.pop()


parser = argparse.ArgumentParser()
parser.add_argument('input_file', nargs='+',
                    type=argparse.FileType('r'),
                    help='Chrome Tracing input files')
args = parser.parse_args()

all_events = load_events(args.input_file)
for tid_pid in all_events:
    load_stack_identifiers(all_events[tid_pid])

for identifiers, duration in stack_identifiers.items():
    print(identifiers + ' ' + str(duration))
