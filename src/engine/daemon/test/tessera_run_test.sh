#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# tessera_run against the host's daemon: the command's exit code handed on, the processors and the priority set on it,
# its processors measured, a job that does not fit waiting for the one before it, two that fit running at once, the
# refusals, and a command watched by a child tessera_run (as a WSL command always is): its pid confirmed against the
# parent's record, and a parent killed or stopped found so by the child, which ends the command and logs it. Takes
# tessera_run, tessera_burn and a scratch directory, and reads $TESSERA_STATE, where the records are kept.
set -u

RUN="$1"
BURN="$2"
SCRATCH="$3"
mkdir -p "$SCRATCH"
CHECKS=0
FAILED=0
STATE="$(cygpath -u "${TESSERA_STATE:-}" 2> /dev/null || echo "${TESSERA_STATE:-}")"
CHILDREN="$STATE/00000000000000000000000000000000/children"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;;
    *) WINDOWS=0 ;;
esac

# ends a background tessera_run at once, as a crash would, with no chance to clean up
kill_hard()
{
    if [ "$WINDOWS" -eq 1 ]; then
        taskkill //F //PID "$(cat "/proc/$1/winpid")" > /dev/null
    else
        kill -9 "$1"
    fi
}

# 0 once the child's log holds the text, within the seconds given
log_holds()
{
    local waited=0
    while [ "$waited" -lt "$2" ]; do
        grep -qs "$1" "$CHILDREN"/*.log && return 0
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# 0 where no tessera_burn of the given milliseconds still runs
burn_ended()
{
    if [ "$WINDOWS" -eq 1 ]; then
        ! tasklist //FI "IMAGENAME eq tessera_burn.exe" //NH 2> /dev/null | grep -q tessera_burn
    else
        ! pgrep -f "tessera_burn 1 $1 " > /dev/null
    fi
}

# the description, then the status of the condition already tested: 0 when it held
check()
{
    CHECKS=$((CHECKS + 1))
    if [ "$2" -eq 0 ]; then
        echo "  held: $1"
    else
        echo "  FAILED: $1"
        FAILED=$((FAILED + 1))
    fi
}

# a decimal with three places, as tessera_run prints them, in thousandths; -1 when the line is not there
thousandths()
{
    local text
    text="$(sed -n "s/.*$1 \([0-9]*\)\.\([0-9][0-9][0-9]\) $2.*/\1\2/p" "$3" | head -1)"
    if [ -n "$text" ]; then
        echo $((10#$text))
    else
        echo -1
    fi
}

# 1: two threads for 1.5 s, exit 7
"$RUN" --processors 2 --name burn_two -- "$BURN" 2 1500 7 > "$SCRATCH/two.out" 2> "$SCRATCH/two.err"
STATUS=$?
cat "$SCRATCH/two.err" "$SCRATCH/two.out"
MASK="$(sed -n 's/.*on processors \(0x[0-9a-f]*\) .*/\1/p' "$SCRATCH/two.err")"
GIVEN="$(sed -n 's/.* of \([0-9]*\) processors reserved.*/\1/p' "$SCRATCH/two.err")"
GIVEN="${GIVEN:-0}"
BURNED="$(sed -n 's/.*tessera_burn: processors \(0x[0-9a-f]*\),.*/\1/p' "$SCRATCH/two.out")"
PEAK="$(thousandths peak processors "$SCRATCH/two.err")"
[ "$STATUS" -eq 7 ]
check "the command's exit code, 7, is tessera_run's ($STATUS)" $?
[ -n "$MASK" ] && [ "$BURNED" = "$MASK" ]
check "the command ran on the processors the job was given ($BURNED against $MASK)" $?
grep -q "below normal 1" "$SCRATCH/two.out"
check "the command ran below normal priority" $?
[ "$PEAK" -ge 1000 ] && [ "$PEAK" -le 2100 ]
check "two threads peaked between 1.000 and 2.100 processors ($PEAK thousandths)" $?

# 2: a job that asks every processor, then one more that waits for it
"$RUN" --processors "$GIVEN" --name burn_all -- "$BURN" 1 2500 0 > "$SCRATCH/all.out" 2> "$SCRATCH/all.err" &
ALL=$!
sleep 0.5
"$RUN" --processors 1 --name burn_after -- "$BURN" 1 100 0 > "$SCRATCH/after.out" 2> "$SCRATCH/after.err"
wait "$ALL"
cat "$SCRATCH/all.err" "$SCRATCH/after.err"
WAITED="$(thousandths "admitted after" s "$SCRATCH/after.err")"
[ "$GIVEN" -gt 0 ] && [ "$WAITED" -ge 1000 ]
check "a job of 1 processor waited for one holding all $GIVEN ($WAITED ms)" $?

# 3: two jobs of 2 processors each, together
"$RUN" --processors 2 --name burn_pair_first -- "$BURN" 1 2000 0 > "$SCRATCH/first.out" 2> "$SCRATCH/first.err" &
FIRST=$!
sleep 0.5
"$RUN" --processors 2 --name burn_pair_second -- "$BURN" 1 100 0 > "$SCRATCH/second.out" 2> "$SCRATCH/second.err"
wait "$FIRST"
cat "$SCRATCH/first.err" "$SCRATCH/second.err"
WAITED="$(thousandths "admitted after" s "$SCRATCH/second.err")"
[ "$WAITED" -ge 0 ] && [ "$WAITED" -lt 500 ]
check "two jobs that fit ran at once (the second waited $WAITED ms)" $?

# 4: refusals
"$RUN" --processors 999 -- "$BURN" 1 10 0 2> "$SCRATCH/many.err"
STATUS=$?
[ "$STATUS" -eq 125 ] && grep -q "asks 999 processors" "$SCRATCH/many.err"
check "999 processors is refused with 125 ($STATUS)" $?
"$RUN" --processors 1 "$BURN" 1 10 0 2> "$SCRATCH/usage.err"
STATUS=$?
[ "$STATUS" -eq 125 ]
check "a command line with no -- is refused with 125 ($STATUS)" $?
"$RUN" --processors 1 -- tessera_no_such_command 2> "$SCRATCH/absent.err"
STATUS=$?
cat "$SCRATCH/absent.err"
[ "$STATUS" -eq 127 ] && grep -q "released after" "$SCRATCH/absent.err"
check "a command that does not start exits 127 ($STATUS), and its job is released" $?

# 5: a command watched by a child tessera_run: the child confirmed, the exit handed on, the tree measured, and the
# records gone after a clean end
rm -rf "$CHILDREN"
"$RUN" --processors 2 --name burn_child --child -- "$BURN" 2 1500 5 > "$SCRATCH/child.out" 2> "$SCRATCH/child.err"
STATUS=$?
cat "$SCRATCH/child.err" "$SCRATCH/child.out"
PEAK="$(thousandths peak processors "$SCRATCH/child.err")"
[ "$STATUS" -eq 5 ] && grep -q "says it lives; its pid is recorded" "$SCRATCH/child.err" \
    && grep -q "its pid confirmed against the parent's record" "$SCRATCH/child.err"
check "a watched command's child said it lives, was recorded and confirmed, and exit 5 was handed on ($STATUS)" $?
[ "$PEAK" -ge 1000 ] && [ "$PEAK" -le 2100 ]
check "a watched command's two threads peaked between 1.000 and 2.100 processors ($PEAK thousandths)" $?
[ -z "$(ls -A "$CHILDREN" 2> /dev/null)" ]
check "a clean end left no records ($(ls -A "$CHILDREN" 2> /dev/null | wc -l) left)" $?

# 6: the parent killed: its child finds its record let go, ends the command and logs it
rm -rf "$CHILDREN"
"$RUN" --processors 1 --name burn_orphan --child -- "$BURN" 1 60000 0 > "$SCRATCH/orphan.out" 2> "$SCRATCH/orphan.err" &
PARENT=$!
sleep 3
kill_hard "$PARENT"
wait "$PARENT" 2> /dev/null
log_holds "was asked to end" 40
FOUND=$?
cat "$SCRATCH/orphan.err"
cat "$CHILDREN"/*.log 2> /dev/null
[ "$FOUND" -eq 0 ] && grep -qs "its parent is gone" "$CHILDREN"/*.log && grep -qs "^orphaned " "$CHILDREN"/*.child \
    && burn_ended 60000
check "the child of a killed parent found it gone, ended the command, logged it, and its records are kept" $?

# 7: the parent stopped (Linux): it holds its record but keeps no keepalive, and its child ends the command once the
# unresponsive time passes; the stopped parent, let go again, hands on the child's exit
if [ "$WINDOWS" -eq 0 ]; then
    rm -rf "$CHILDREN"
    TESSERA_RUN_SILENT_MS=1000 TESSERA_RUN_UNRESPONSIVE_MS=3000 \
        "$RUN" --processors 1 --name burn_stopped --child -- "$BURN" 1 60001 0 > "$SCRATCH/stopped.out" \
        2> "$SCRATCH/stopped.err" &
    PARENT=$!
    sleep 2
    kill -STOP "$PARENT"
    log_holds "was asked to end" 30
    FOUND=$?
    kill -CONT "$PARENT"
    wait "$PARENT"
    STATUS=$?
    cat "$SCRATCH/stopped.err"
    [ "$FOUND" -eq 0 ] && grep -qs "the parent still holds its record" "$CHILDREN"/*.log \
        && grep -qs "holds its record but is not responding" "$CHILDREN"/*.log && [ "$STATUS" -eq 124 ] \
        && burn_ended 60001
    check "the child of a stopped parent waited out the unresponsive time, ended the command, and 124 was handed on ($STATUS)" $?
fi

# 8: a child with no launch record runs nothing
rm -rf "$SCRATCH/unlaunched"
mkdir -p "$SCRATCH/unlaunched"
"$RUN" --parent "$SCRATCH/unlaunched/none" -- "$BURN" 1 10 0 > "$SCRATCH/unlaunched.out" 2> "$SCRATCH/unlaunched.err"
STATUS=$?
cat "$SCRATCH/unlaunched.err"
[ "$STATUS" -eq 125 ] && grep -q "no launch record" "$SCRATCH/unlaunched.err" && ! grep -q tessera_burn "$SCRATCH/unlaunched.out"
check "a child with no launch record ran nothing and exited 125 ($STATUS)" $?

echo "  tessera_run test: $CHECKS checks, $FAILED failed"
[ "$FAILED" -eq 0 ]
