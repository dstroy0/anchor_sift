#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The checkers of cell_tracking/src/check shown to fire: check_test writes a good set for each checker and a broken
# copy for each fault it names, and each checker is run on every copy. The good sets must exit 0 with no fault; each
# broken copy must exit 1 with its fault counted (points_check) or printed (output_check). output_check's .divide cases
# hold the good sets' counts too: divided, and with a .divide of no divisions beside each sample; its .faces cases hold
# the faced sets' counts: both samples faced, one bare, and faced and divided. Host work, no device
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../../../examples" && pwd)"
CHECK="$TOP/cell_tracking/src/check"
source "$TOP/cell_tracking/maint/build_stamp.sh"
build_stamp check_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        SUFFIX=.exe
        MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        if [ -z "$MSVC_BIN" ]; then
            MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        fi
        if [ -z "$MSVC_BIN" ]; then
            echo "  no host compiler nvcc accepts on this platform was found."
            exit 1
        fi
        HOST_FLAGS=(-ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor)
        ;;
    *)
        SUFFIX=
        ;;
esac

for source in "$TEST/check_test.c" "$CHECK/points_check.c" "$CHECK/output_check.c"; do
    binary="$OUT/$(basename "$source" .c)$SUFFIX"
    rm -f "$binary"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2 /W4 /D_CRT_SECURE_NO_WARNINGS" -o "$binary" "$source" ;;
        *)
            cc -std=c11 -O2 -Wall -Wextra -o "$binary" "$source" ;;
    esac
    [ -f "$binary" ] || { echo "  build failed: $(basename "$source") did not build"; exit 1; }
done
if [ "${BUILD_ONLY:-0}" = "1" ]; then
    echo "  built $OUT/check_test$SUFFIX, $OUT/points_check$SUFFIX and $OUT/output_check$SUFFIX"
    exit 0
fi

# the cases are written under the build directory
SET="$OUT/check_test_set"
rm -rf "$SET"
"$OUT/check_test$SUFFIX" "$SET" || { echo "  check_test could not write its cases"; exit 1; }

CHECKS=0
FAILED=0
# held <case> <want exit> <exit> <log> <pattern>: the case's exit, and the pattern found in its output
held() {
    local name=$1 want=$2 status=$3 log=$4 pattern=$5 found=0
    CHECKS=$((CHECKS + 1))
    grep -q -- "$pattern" "$log" && found=1
    if [ "$status" -eq "$want" ] && [ "$found" -eq 1 ]; then
        echo "  $name: exit $status, fired: $pattern"
    else
        FAILED=$((FAILED + 1))
        echo "  $name: FAILED: exit $status (want $want), \"$pattern\" $([ "$found" -eq 1 ] && echo found || echo "not found")"
        sed 's/^/      /' "$log"
    fi
}

LOG="$OUT/check_test_case.log"
# points <case> <fault named, or "" for the good set> [<sample> ...]: points_check on the case's set
points() {
    local name=$1 fault=$2 status
    shift 2
    "$OUT/points_check$SUFFIX" "$SET/points_$name" "$@" > "$LOG" 2>&1
    status=$?
    if [ -z "$fault" ]; then
        held "points_$name" 0 "$status" "$LOG" "^  0 faults$"
    elif [ "$name" = "set_unread" ]; then
        held "points_$name" 1 "$status" "$LOG" "faults: $fault 1"
    else
        held "points_$name" 1 "$status" "$LOG" "[:,] $fault [1-9][0-9]*"
    fi
}

points good "" a b
points set_unread "scan.set does not read" a b
points readings_unread "a .readings does not read whole" a b
points sum_past_64 "a sum passes 64 bits" a b
points set_not_rebuilt "scan.set is not the rebuilt readings and bits" a b
points not_listed "a sample not in scan.set" a b c
points points_unread "a .points does not open or its head does not read" a b
points head_differs "a head differs from the first sample's" a b
points head_not_rebuilt "a head is not the rebuilt readings, bits and C" a b
points empty_view "a view or frame count of 0" a b
points count_past_view "a frame's count past its view" a b
points frame_short "a frame stops short" a b
points out_of_order "voxels out of order" a b
points outside "voxels outside the view" a b
points not_positive "levels not positive" a b
points zero_level "levels not positive" a b
points past_last_frame "a .points goes on past its last frame" a b
points readings_not_view "a sample's readings are not its frames times its view" a b

# output <case> <pattern, or "" for the good set>: output_check on the case's set, chain and second
output() {
    local name=$1 pattern=$2 status
    "$OUT/output_check$SUFFIX" "$SET/output_$name" "$SET/output_$name/nodes.tsv" "$SET/output_$name/submission.csv" \
        chain second > "$LOG" 2>&1
    status=$?
    if [ -z "$pattern" ]; then
        held "output_$name" 0 "$status" "$LOG" "^  0 problems$"
    else
        held "output_$name" 1 "$status" "$LOG" "$pattern"
    fi
}

output good ""
# the good set with a nodes file that is not there
"$OUT/output_check$SUFFIX" "$SET/output_good" "$SET/output_good/none.tsv" "$SET/output_good/submission.csv" \
    chain second > "$LOG" 2>&1
held "output_unopened" 1 "$?" "$LOG" "the nodes or the submission does not open"
output links_frames "chain: frame 0: the .links' frames or view are not the .points'"
output links_view "chain: frame 0: the .links' frames or view are not the .points'"
output pair_count "chain: frame 0: the pair record's sources or targets are not the frames' points"
output range "chain: frame 0: a chosen link lies past the frames' points"
output two_out "chain: frame 0: a point has two chosen links out"
output two_in "chain: frame 1: a point has two chosen links in"
output chosen "chain: frame 0: the pair's chosen links are not its record's count"
output links_trailing "chain: its .links does not open, stops short, disagrees with its .points, or goes on past"
output links_short "chain: its .links does not open, stops short, disagrees with its .points, or goes on past"
output links_missing "chain: its .links does not open, stops short, disagrees with its .points, or goes on past"
output points_trailing "chain: its .points does not open, stops short, or goes on past its last frame"
output points_short "chain: its .points does not open, stops short, or goes on past its last frame"
output points_outside "chain: frame 3: a voxel lies outside the view"
output nodes_differ "nodes.tsv: .* rows held against the rebuilt, [1-9][0-9]* differ"
output submission_differs "submission.csv: .* rows held against the rebuilt, [1-9][0-9]* differ"
output nodes_header "nodes.tsv: .* rows held against the rebuilt, [1-9][0-9]* differ"
output nodes_missing "nodes.tsv: .* [1-9][0-9]* missing"
output submission_past "submission.csv: .* [1-9][0-9]* past the rebuilt"
output carriage "nodes.tsv: [0-9]* bytes, [0-9]* LF, [1-9][0-9]* CR"

# divide <case> <want exit> <pattern>: output_check on the case's set, chain, second and fork
divide() {
    local name=$1 want=$2 pattern=$3 status
    "$OUT/output_check$SUFFIX" "$SET/divide_$name" "$SET/divide_$name/nodes.tsv" "$SET/divide_$name/submission.csv" \
        chain second fork > "$LOG" 2>&1
    status=$?
    held "divide_$name" "$want" "$status" "$LOG" "$pattern"
}

ERROR="its .divide stops short, breaks a rule above, or goes on past its last frame pair"
divide good 0 "rebuilt 3 of 3 samples: 8 frames, 16 nodes, 6 edges, 2 divisions (1 moving a link); 0 faults in the graphs"
divide none 0 "rebuilt 3 of 3 samples: 8 frames, 16 nodes, 5 edges, 0 divisions (0 moving a link); 0 faults in the graphs"
divide rows 1 "nodes.tsv: .* rows held against the rebuilt, [1-9][0-9]* differ"
divide head 1 "second: $ERROR"
divide frames 1 "second: frame 0: the .divide's frames or view are not the .points'"
divide view 1 "second: frame 0: the .divide's frames or view are not the .points'"
divide crc 1 "second: frame 0: the .divide was not made from the .links beside it: the CRC-64 differs"
divide count 1 "second: $ERROR"
divide parent 1 "second: frame 0: a division's parent lies past the frame's points or out of order"
divide order 1 "second: frame 0: a division's parent lies past the frame's points or out of order"
divide one 1 "second: frame 0: a division's daughter one is not its parent's link"
divide two 1 "second: frame 0: a division's daughter two lies past the frame's points or is daughter one"
divide two_past 1 "second: frame 0: a division's daughter two lies past the frame's points or is daughter one"
divide left 1 "second: frame 0: a division's daughter two does not come from the point it names"
divide divides 1 "fork: frame 0: a division takes daughter two from a point that divides"
divide short 1 "second: $ERROR"
divide trailing 1 "second: $ERROR"

# faces <case> <want exit> <pattern>: output_check on the case's set, chain and second
faces() {
    local name=$1 want=$2 pattern=$3 status
    "$OUT/output_check$SUFFIX" "$SET/faces_$name" "$SET/faces_$name/nodes.tsv" "$SET/faces_$name/submission.csv" \
        chain second > "$LOG" 2>&1
    status=$?
    held "faces_$name" "$want" "$status" "$LOG" "$pattern"
}

UNFACED="its .faces stops short, breaks a rule above, or goes on past its last frame"
DRIFT="its .drift does not open, stops short, disagrees with its .points, or goes on past its last frame"
SHAPE="its .shape does not open, stops short, disagrees with its .points, or goes on past its last frame"
faces good 0 "2 of them with a .faces: 2 of their 3 starts enter the view, 2 of their 4 ends leave it"
faces bare 0 "1 of them with a .faces: 2 of their 3 starts enter the view, 2 of their 4 ends leave it"
faces divided 0 "2 of them with a .faces: 1 of their 2 starts enter the view, 2 of their 5 ends leave it"
faces rows 1 "nodes.tsv: .* rows held against the rebuilt, [1-9][0-9]* differ"
faces head 1 "chain: $UNFACED"
faces frames 1 "chain: frame 0: the .faces' frames or view are not the .points'"
faces view 1 "chain: frame 0: the .faces' frames or view are not the .points'"
faces crc 1 "chain: frame 0: the .faces was not made from the .links beside it: the CRC-64 differs"
faces count 1 "chain: frame 0: the .faces' count is not the frame's points"
faces back 1 "chain: frame 1: a point's back-prediction is not the one rebuilt"
faces shape 1 "chain: frame 0: a point's flags are not the ones rebuilt"
faces verdict 1 "chain: frame 1: a point's flags are not the ones rebuilt"
faces short 1 "chain: $UNFACED"
faces trailing 1 "chain: $UNFACED"
faces outside 1 "chain: frame 0: a .links outside flag is not its prediction's"
faces past_32 1 "chain: frame 3: a point's back-prediction passes 32 bits"
faces drift_missing 1 "chain: $DRIFT"
faces drift_view 1 "chain: frame 0: the .drift's frames or view are not the .points'"
faces drift_trailing 1 "chain: $DRIFT"
faces shape_limbs 1 "chain: frame 0: the .shape's frames, view or limbs are not the .points'"
faces shape_count 1 "chain: frame 0: the .shape's count is not the frame's points"
faces shape_six 1 "chain: frame 0: a point's .shape faces are not among the six"
faces shape_short 1 "chain: $SHAPE"

rm -f "$LOG"
echo "  check test: $CHECKS checks, $FAILED failed"
[ "$FAILED" -eq 0 ]
