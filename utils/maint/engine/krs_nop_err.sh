#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Every form a ruleset left blank turned into the nop or the err it meant, once, when the reader stopped taking a
# blank form. A form named on the err list becomes `err <name> <parameters>` and every other blank one becomes
# `nop <name> <parameters>`; a form with text is not touched
#
#     utils/maint/engine/krs_nop_err.sh <ruleset> [form that is an error] ...
set -u

KRS="$1"
shift
ERRS=" $* "

# each blank form's line rewritten in place: the head without its equals, under the keyword its name earns. IFS is
# cleared to keep the leading tabs a form's text is written with
while IFS= read -r line; do
    case "$line" in
        form\ *)
            head="${line%%=*}"
            text="${line#*=}"
            ;;
        *)
            printf '%s\n' "$line"
            continue
            ;;
    esac
    # a form with anything after its equals is written, and stays a form
    if [ -n "${text// /}" ] || [ "$head" = "$line" ]; then
        printf '%s\n' "$line"
        continue
    fi
    head="${head% }"
    name="$(printf '%s' "$head" | awk '{print $2}')"
    case "$ERRS" in
        *" $name "*) printf 'err %s\n' "${head#form }" ;;
        *) printf 'nop %s\n' "${head#form }" ;;
    esac
done <"$KRS" >"$KRS.turned"
mv "$KRS.turned" "$KRS"
echo "$KRS: $(grep -c '^nop ' "$KRS") nop, $(grep -c '^err ' "$KRS") err, $(grep -c '^form ' "$KRS") written"
