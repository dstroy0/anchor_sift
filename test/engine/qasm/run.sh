#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds qasm_test, qasm_exact_test, qasm_self_test and qasm_bitstring into build/<stamp>_qasm_test, runs the tests,
# then the CLI on the fixtures.
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../.." && pwd)"
source "$TOP/src/engine/base/qasm/build.sh"
qasm_build qasm_test || exit 1
qasm_link "$QASM/qasm_bitstring.cu" qasm_bitstring || exit 1
CLI="$BINARY"
qasm_link "$TEST/qasm_test.cu" qasm_test || exit 1

"$BINARY" "$TEST"
STATUS=$?
echo "  qasm_test exit $STATUS"

# the exact port against the values the Python printed, then the self run against the port on the host and the device
qasm_link "$TEST/qasm_exact_test.cu" qasm_exact_test || exit 1
"$BINARY"
EXACT=$?
echo "  qasm_exact_test exit $EXACT"
[ "$EXACT" -eq 0 ] || STATUS=1
qasm_link "$TEST/qasm_self_test.cu" qasm_self_test || exit 1
"$BINARY"
SELF=$?
echo "  qasm_self_test exit $SELF"
[ "$SELF" -eq 0 ] || STATUS=1

# the CLI on the fixtures: the exit code is the verdict, 0 proved and 3 not proved
check_cli()
{
    local fixture="$1"
    local expected="$2"
    local bitstring="$3"
    local output
    local got
    output="$("$CLI" "$TEST/$fixture" 2>/dev/null)"
    got=$?
    local line
    line="$(printf '%s\n' "$output" | grep '^bitstring' | awk '{print $2}')"
    if [ "$got" -eq "$expected" ] && { [ -z "$bitstring" ] || [ "$line" = "$bitstring" ]; }; then
        echo "  ok   cli $fixture: exit $got, bitstring $line"
    else
        echo "  FAIL cli $fixture: exit $got (wanted $expected), bitstring $line (wanted $bitstring)"
        printf '%s\n' "$output"
        STATUS=1
    fi
}
check_cli bell.qasm 3 ""
check_cli bernstein_vazirani.qasm 0 101101001101

echo "  qasm tests exit $STATUS"
exit "$STATUS"
