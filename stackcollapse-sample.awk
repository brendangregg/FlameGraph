#!/usr/bin/awk -f
#
# Uses MacOS' /usr/bin/sample to generate a flamegraph of a process
#
# Usage:
#
# sudo sample [pid] -file /dev/stdout | stackcollapse-sample.awk | flamegraph.pl
#
# Options:
#
# The output will show the name of the library/framework at the call-site
# with the form AppKit`NSApplication or libsystem`start_wqthread.
#
# If showing the framework or library name is not required, pass
# MODULES=0 as an argument of the sample program.
#
# The generated SVG will be written to the output stream, and can be piped
# into flamegraph.pl directly, or written to a file for conversion later.
#
# ---
#
# Copyright (c) 2017, Apple Inc.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

BEGIN {

  # Command line options
  MODULES = 1       # Allows the user to enable/disable printing of modules.

  # Internal variables
  _FOUND_STACK = 0  # Found the stack traces in the output.
  _LEVEL = -1       # The current level of indentation we are running.

  # The set of symbols to ignore for 'waiting' threads, for ease of use.
  # This will hide waiting threads from the view, making it easier to
  # see what is actually running in the sample. These may be adjusted
  # as necessary or appended to if other symbols need to be filtered out.

  _IGNORE["libsystem_kernel`__psynch_cvwait"] = 1
  _IGNORE["libsystem_kernel`__select"] = 1
  _IGNORE["libsystem_kernel`__semwait_signal"] = 1
  _IGNORE["libsystem_kernel`__ulock_wait"] = 1
  _IGNORE["libsystem_kernel`__wait4"] = 1
  _IGNORE["libsystem_kernel`__workq_kernreturn"] = 1
  _IGNORE["libsystem_kernel`kevent"] = 1
  _IGNORE["libsystem_kernel`mach_msg_trap"] = 1
  _IGNORE["libsystem_kernel`read"] = 1
  _IGNORE["libsystem_kernel`semaphore_wait_trap"] = 1

  # The same set of symbols as above, without the module name.
  _IGNORE["__psynch_cvwait"] = 1
  _IGNORE["__select"] = 1
  _IGNORE["__semwait_signal"] = 1
  _IGNORE["__ulock_wait"] = 1
  _IGNORE["__wait4"] = 1
  _IGNORE["__workq_kernreturn"] = 1
  _IGNORE["kevent"] = 1
  _IGNORE["mach_msg_trap"] = 1
  _IGNORE["read"] = 1
  _IGNORE["semaphore_wait_trap"] = 1

}

# This is the first line in the /usr/bin/sample output that indicates the
# samples follow subsequently. Until we see this line, the rest is ignored.

/^Call graph/ {
  _FOUND_STACK = 1
}

# This is found when we have reached the end of the stack output.
# Identified by the string "Total number in stack (...)".

/^Total number/ {
  _FOUND_STACK = 0
  printStack(_NEST,0)
}

# Prints the stack from FROM to TO (where FROM > TO)
# Called when indenting back from a previous level, or at the end
# of processing to flush the last recorded sample

function printStack(FROM,TO) {

  # We ignore certain blocking wait states, in the absence of being
  # able to filter these threads from collection, otherwise
  # we'll end up with many threads of equal length that represent
  # the total time the sample was collected.
  #
  # Note that we need to collect the information to ensure that the
  # timekeeping for the parental functions is appropriately adjusted
  # so we just avoid printing it out when that occurs.
  _PRINT_IT = !_IGNORE[_NAMES[FROM]]

  # We run through all the names, from the root to the leaf, so that
  # we generate a line that flamegraph.pl will like, of the form:
  # Thread1234;example`main;example`otherFn 1234

  for(l = FROM; l>=TO; l--) {
    if (_PRINT_IT) {
      printf("%s", _NAMES[0])
      for(i=1; i<=l; i++) {
        printf(";%s", _NAMES[i])
      }
      print " " _TIMES[l]
    }

    # We clean up our current state to avoid bugs.
    delete _NAMES[l]
    delete _TIMES[l]
  }
}

# This is where we process each line, of the form:
#  5130 Thread_8749954
#    + 5130 start_wqthread  (in libsystem_pthread.dylib) ...
#    +   4282 _pthread_wqthread  (in libsystem_pthread.dylib) ...
#    +   ! 4282 __doworkq_kernreturn  (in libsystem_kernel.dylib) ...
#    +   848 _pthread_wqthread  (in libsystem_pthread.dylib) ...
#    +     848 __doworkq_kernreturn  (in libsystem_kernel.dylib) ...

_FOUND_STACK && match($0,/^    [^0-9]*[0-9]/) {

  # We maintain two counters:
  #   _LEVEL: the high water mark of the indentation level we have seen.
  #   _NEST:  the current indentation level.
  #
  # We keep track of these two levels such that when the nesting level
  # decreases, we print out the current state of where we are.

  _NEST=(RLENGTH-5)/2
  sub(/^[^0-9]*/,"") # Normalise the leading content so we start with time.
  _TIME=$1           # The time recorded by 'sample', first integer value.

  # The function name is in one or two parts, depending on what kind of
  # function it is.
  #
  # If it is a standard C or C++ function, it will be of the form:
  #  exampleFunction
  #  Example::Function
  #
  # If it is an Objective-C funtion, it will be of the form:
  #  -[NSExample function]
  #  +[NSExample staticFunction]
  #  -[NSExample function:withParameter]
  #  +[NSExample staticFunction:withParameter:andAnother]

  _FN1 = $2
  _FN2 = $3

  # If it is a standard C or C++ function then the following word will
  # either be blank, or the text '(in', so we jut use the first one:

  if (_FN2 == "(in" || _FN2 == "") {
    _FN =_FN1
  } else {
    # Otherwise we concatenate the first two parts with .
    _FN = _FN1 "." _FN2
  }

  # Modules are shown with '(in libfoo.dylib)' or '(in AppKit)'

  _MODULE = ""
  match($0, /\(in [^)]*\)/)

  if (RSTART > 0 && MODULES) {

    # Strip off the '(in ' (4 chars) and the final ')' char (1 char)
    _MODULE = substr($0, RSTART+4, RLENGTH-5)

    # Remove the .dylib function, since it adds no value.
    gsub(/\.dylib/, "", _MODULE)

    # The function name is 'module`functionName'
    _FN = _MODULE "`" _FN
  }

  # Now we have set up the variables, we can decide how to apply it
  # If we are descending in the nesting, we don't print anything out:
  # a
  # ab
  # abc
  #
  # We only print out something when we go back a level, or hit the end:
  # abcd
  # abe < prints out the stack up until this point, i.e. abcd

  # We store a pair of arrays, indexed by the nesting level:
  #
  #  _TIMES - a list of the time reported to that function
  #  _NAMES - a list of the function names for each current stack trace

  # If we are backtracking, we need to flush the current output.
  if (_NEST <= _LEVEL) {
    printStack(_LEVEL,_NEST)
  }

  # Record the name and time of the function where we are.
  _NAMES[_NEST] = _FN
  _TIMES[_NEST] = _TIME

  # We subtract the time we took from our parent so we don't double count.
  if (_NEST > 0) {
    _TIMES[_NEST-1] -= _TIME
  }

  # Raise the high water mark of the level we have reached.
  _LEVEL = _NEST
}
