#!/bin/sh
# The prose gate for the theory repository, run by .git/hooks/pre-commit.
#
# Doug, 2026-09-25: "theory/ workbooks/ and thought_experiments/ from our repo have a zero tolerance
# gate, other repo files are ignored. only our concerns are flagged".
#
# prose_ratchet.tsv holds its header and no file. Every staged file under the three roots has a
# ceiling of 0 prose findings. A breaking finding anywhere under the roots stops the commit.
# Exit codes are docs_check's: 1 breaking, 2 read nothing, 3 a staged file carries prose, 4 no
# ratchet. printed_check reads the .py under the roots; none are there today, and its 2 says so.
cd "$(git rev-parse --show-toplevel)" || exit 1
export PYTHONIOENCODING=utf-8

python maint/prose/docs_check.py --ratchet=maint/prose/prose_ratchet.tsv --staged
status=$?
if [ "$status" -ne 0 ]; then
    echo "prose gate: docs_check exited $status, commit stopped"
    exit "$status"
fi

python maint/prose/printed_check.py theory workbooks thought_experiments
status=$?
if [ "$status" -eq 2 ]; then
    echo "prose gate: no Python under the roots, so printed_check checked nothing"
elif [ "$status" -ne 0 ]; then
    echo "prose gate: printed_check exited $status, commit stopped"
    exit "$status"
fi
exit 0
