#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
FLAGS=$1
shift
DRIVERS=()
while [[ $# -gt 0 && $1 != "--" ]]; do
    DRIVERS+=("$1")
    shift
done
shift
for driver in "${DRIVERS[@]}"; do
    echo "== $driver $FLAGS"
    start=$(date +%s%N)
    "./build/$driver.exe" $FLAGS --source /d/kaggle_project_data/biohub_cell_tracking_data/train \
        /d/kaggle_project_data/biohub_cell_tracking_set/train "$@"
    stop=$(date +%s%N)
    echo "   wall $(((stop - start) / 1000000)) ms"
done
