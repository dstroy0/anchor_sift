#!/bin/sh
# How many device consumers the card actually supports, measured rather than assumed.
#
# THE QUESTION. Douglas wants to size a worker pool: how many miners can run on the card. That has
# an architectural answer and a measured one, and only the measured one is worth acting on.
#
# THE ARCHITECTURAL ANSWER, stated first so the measurement can refute it. Separate CUDA PROCESSES
# on one GPU are time-sliced by the driver, not run concurrently, unless NVIDIA MPS is running. So
# N processes should each get about 1/N of the card and the aggregate should stay flat, minus
# context-switch overhead. Multiple STREAMS inside ONE process do run concurrently, which is what
# the cuda_miner survey-stream change enables.
#
# If the aggregate below scales with N, that reasoning is wrong and the driver is doing something
# better than time-slicing. If it stays flat, the worker pool should be sized at one device process
# and the parallelism belongs in streams.
#
# Usage: sh tools/hardware/device_scaling.sh [max_instances]

set -e
here=$(cd "$(dirname "$0")/../.." && pwd)
bench="$here/src/bench/bench_cuda.exe"
out="${TMPDIR:-/tmp}/device_scaling"
mkdir -p "$out"

if [ ! -x "$bench" ]; then
    echo "no bench_cuda.exe at $bench"
    exit 1
fi

top=${1:-4}

echo "  Concurrent instances of bench_cuda.exe, each reporting its own device rate."
echo "  Aggregate is the sum. Flat aggregate means the card is time-slicing."
echo ""
printf "  %10s %14s %16s %16s\n" "instances" "each (MH/s)" "aggregate" "vs 1 instance"

single=""
for count in $(seq 1 "$top"); do
    rm -f "$out"/run_*.txt
    pids=""
    at=1
    while [ "$at" -le "$count" ]; do
        "$bench" > "$out/run_$at.txt" 2>&1 &
        pids="$pids $!"
        at=$((at + 1))
    done
    for pid in $pids; do
        wait "$pid" || true
    done

    # Each instance prints one "device rate: X MH/s" line.
    rates=$(grep -h "device rate:" "$out"/run_*.txt 2>/dev/null | sed 's/.*device rate: *//; s/ MH.*//')
    got=$(echo "$rates" | grep -c . || true)
    total=$(echo "$rates" | awk '{s += $1} END {printf "%.2f", s}')
    mean=$(echo "$rates" | awk '{s += $1; n += 1} END {if (n > 0) printf "%.2f", s / n; else print "0"}')

    if [ "$count" -eq 1 ]; then
        single="$total"
    fi
    ratio=$(awk -v a="$total" -v b="$single" 'BEGIN {if (b > 0) printf "%.3f", a / b; else print "-"}')

    if [ "$got" -ne "$count" ]; then
        printf "  %10s %14s %16s %16s\n" "$count" "INCOMPLETE" "$got of $count reported" "-"
    else
        printf "  %10s %14s %16s %16s\n" "$count" "$mean" "$total" "$ratio"
    fi
done

echo ""
echo "  READ THE LAST COLUMN. A ratio near 1.0 at every row means the aggregate is flat and the"
echo "  card is time-slicing between processes: more miner processes buy nothing and cost context"
echo "  switches. A ratio rising with the instance count would mean the opposite and would refute"
echo "  the reasoning in this script's own header."
