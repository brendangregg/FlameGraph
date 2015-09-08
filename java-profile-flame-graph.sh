#!/bin/bash

# author: https://github.com/yaojuncn

# this is a script combining the jstack profiling and generating the flamegraph for JVM applications

# the work is based on Brendan Gregg's flame graph work on https://github.com/brendangregg/FlameGraph
# and also based on mik01aj's useful script https://gist.github.com/mik01aj/1811bb1ccf7dd5f716ce
# mostly I'm only providing one single script inside the FlameGraph project
# however it will be much more convenient for for java developer's usage

# the script will only do the cpu flame graph for java code only; it will not include the system flame graph; 
# however, for most cases this is quite enough for developers to tune the jvm app's performance

set -e

me=`basename "$0"`

if [[ $# == 0 ]]; then
	echo "Usage ./${me} pid"
	echo "Usage ./${me} pid -i 0.01  -n 120 -o /tmp -c y "
	echo "-i specifies sleep interval of profiling in seconds, default to 0.01 seconds"
	echo "-n specifies total count of profiling, default to 120 count"
	echo "-o specifies the output path for the svg file and temporary stack files; default to current dir"
	echo "-c specifies whether do clean up for temporary stack files in the middle, y or n, default to y"
	echo "the output will be \$pid_flamegraph.svg"
	exit 
fi

pid=$1
interval=0.01 # sleep interval in seconds of profiling, default to 0.01 seconds
count=120   # count of profiles, default to 120
cleanup=y  # whether to clean up for temporary stack files 
outputpath=$PWD  # output path, default to current dir

while [[ $# > 1 ]]
do
key="$1"

case $key in
    -i)
    interval="$2"
    shift # past argument
    ;;
    -n)
    count="$2"
    shift # past argument
    ;;
    -c)
    cleanup="$2"
    shift # past argument
    ;;
    -o)
    outputpath="$2"
    shift # past argument
    ;;
    --default)
    DEFAULT=YES
    ;;
    *)
    # unknown option
    ;;
esac
shift # past argument or value
done


cleanup=`echo "${cleanup}" | tr '[:upper:]' '[:lower:]'`
if [[ "$outputpath" != */ ]]
then
    outputpath="${outputpath}/"
fi

echo "pid=${pid}"
echo "interval=${interval}"
echo "count=${count}"
echo "outputpath=${outputpath}"
echo "cleanup=${cleanup}"

file_stacklog="${outputpath}${pid}.stack.log"

rm -f "$file_stacklog"

echo "now to profile process id of $pid with interval of ${interval}, count=${count}, the stacklog is $file_stacklog"

index=1
while [ $index -lt $count ]
do
  jstack "$pid" >> "$file_stacklog" 
  sleep ${interval} 
  index=`expr $index + 1`
done

file_tmpstack="${outputpath}${pid}.stack.tmp.log"
file_outsvg="${outputpath}${pid}_flamegraph.svg"

./stackcollapse-jstack.pl "$file_stacklog" > "$file_tmpstack"
./flamegraph.pl --cp "$file_tmpstack" > "${file_outsvg}"

if [[ "$cleanup" == "y" ]]; then
	rm -f "${file_stacklog}"
	rm -f "${file_tmpstack}"
fi

echo "flamegraph for pid=${pid} generated as ${file_outsvg}"







