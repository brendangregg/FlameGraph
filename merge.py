#!/usr/bin/python
#
# merge multiple .col files
#
# USAGE: python combine.py file1.col file2.col
#
# 8-Aug-2023    Daniel Hill Created this.

import sys

stacks = {}

for file in sys.argv[1:]:
    with open(file, "r") as f:
        for line in f.readlines():
            if line.startswith("#"):  # skip metadata lines
                continue
            parts = line.rsplit(" ", 1)
            if parts[0] not in stacks:
                stacks[parts[0]] = 0
            stacks[parts[0]] += int(parts[1])

with open("combined.col", "w") as f:
    for stack in stacks:
        f.write(stack + " " + str(stacks[stack]) + "\n")