#!/bin/bash
proc_id=$(uuidgen)

name=""
pid="none"
fre="99"
dur="10"

show_help() {
cat << EOF
Usage: ${0##*/} [-h|--help]
    -n|--name       进程名
    -p|--pid        进程pid
    -f|--frequency  采样频率
    -d|--duration   采样时长
EOF
}

while [[ $# -gt 0 ]]
do
k="$1"
case $k in
    -h|--help)
    show_help
    exit 0
    ;;
    -n|--name)
    name=${2}
    shift
    shift
    ;;
    -p|--pid)
    pid=${2}
    shift
    shift
    ;;
    -f|--frequency)
    fre=${2}
    shift
    shift
    ;;
    -d|--duration)
    dur=${2}
    shift
    shift
    ;;
    *)
    show_help >&2
    exit 1
    ;;
esac
done

if [[ "${pid}" == "none" && "${name}" != "" ]]; then
    pid=$(pidof ${name})
fi

exist=$(ps aux | awk '{print $2}' | grep -w ${pid})
if [[ ! $exist ]] ; then
echo "PID not exist!"
exit 1
fi

sudo perf record -F ${fre} -p ${pid} -g -o /tmp/${proc_id}.data -- sleep ${dur}
if [[ 0 -gt $? ]] ; then
echo "step 1 error"
exit 1
fi
sudo perf script -i /tmp/${proc_id}.data > /tmp/${proc_id}.perf
if [[ 0 -gt $? ]] ; then
echo "step 2 error"
exit 1
fi
stackcollapse-perf.pl /tmp/${proc_id}.perf > /tmp/${proc_id}.folded
if [[ 0 -gt $? ]] ; then
echo "step 3 error"
exit 1
fi
flamegraph.pl /tmp/${proc_id}.folded > ./${proc_id}.svg