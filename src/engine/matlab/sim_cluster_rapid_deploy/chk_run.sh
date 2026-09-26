#!/bin/bash

# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational

# --- CONFIGURATION BOUNDARIES ---
MIN_MATLAB="9.6"
MIN_OCTAVE="6.0"
TIMEOUT_LIMIT="45s"
MIN_FREE_MEM_MB=1024

# --- INITIAL STATE MANAGEMENT ---
DRY_RUN=false
ALLOW_PINNING="${PINNED:-false}"
FILE_PATH=""
BATCH_TAG=""
declare -a SCRIPT_ARGS=()

# -------------------------------------------------------------
# ARGUMENT PARSING LOOP (Traps Bash Options vs -- Pipes)
# -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --tag)
            if [[ -n "$2" && "$2" != -* ]]; then
                BATCH_TAG="$2"
                shift 2
            else
                echo "Error: --tag requires a non-empty string argument." >&2
                exit 1
            fi
            ;;
        --)
            # Stop parsing Bash parameters; shift past '--' and grab everything else
            shift
            SCRIPT_ARGS=("$@")
            break
            ;;
        *)
            if [ -z "$FILE_PATH" ]; then
                FILE_PATH="$1"
            else
                echo "Error: Unexpected loose argument detected: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    echo "Error: Valid path to a *.m file required." >&2
    echo "Usage: [PINNED=true] $0 [--dry-run] [--tag <name>] <filename.m> [-- <script_args>...]" >&2
    exit 1
fi

if [ -z "$BATCH_TAG" ]; then
    BATCH_TAG="job-$(date +%s)-$$-$((RANDOM % 100))"
fi

FILE_DIR=$(dirname "$FILE_PATH")
FILE_NAME=$(basename "$FILE_PATH")
SCRIPT_NAME="${FILE_NAME%.*}"

# -------------------------------------------------------------
# TRANSLATE BASH ARRAYS TO INTERPRETER-SPECIFIC SYNTAX
# -------------------------------------------------------------
MATLAB_ARGS_STR=""

if [ ${#SCRIPT_ARGS[@]} -gt 0 ]; then
    # Safely serialize arguments for MATLAB's inline functional statement
    for arg in "${SCRIPT_ARGS[@]}"; do
        # Escape single quotes by doubling them to preserve literal boundaries inside MATLAB
        escaped_arg="${arg//\'/\'\'}"
        MATLAB_ARGS_STR="${MATLAB_ARGS_STR}'${escaped_arg}',"
    done
    MATLAB_ARGS_STR="${MATLAB_ARGS_STR%,}" # Strip trailing comma
fi

# -------------------------------------------------------------
# PLATFORM BRANCHING: CORE & ENVIRONMENT DISCOVERY
# -------------------------------------------------------------
PLATFORM="Bare-Metal/VM"

if [ -f "/sys/fs/cgroup/cpu.max" ]; then
    CGROUP_READS=$(cat /sys/fs/cgroup/cpu.max)
    QUOTA=$(echo "$CGROUP_READS" | awk '{print $1}')
    PERIOD=$(echo "$CGROUP_READS" | awk '{print $2}')
    
    if [ "$QUOTA" != "max" ] && [ -n "$PERIOD" ]; then
        PLATFORM="Docker/Cgroup Container"
        CORES=$(awk -v q="$QUOTA" -v p="$PERIOD" 'BEGIN { c = q / p; print (c < 1) ? 1 : int(c) }')
    fi
fi

if [ -z "$CORES" ]; then
    CORES=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
fi

CURRENT_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | awk -F',' '{ print $1 }' | xargs)

DYNAMIC_THRESHOLD=$(awk -v load="$CURRENT_LOAD" -v cores="$CORES" -v pin="$ALLOW_PINNING" '
    BEGIN {
        mod = load % cores;
        final_val = int(mod);
        if (pin != "true" && final_val < 1) {
            final_val = 1;
        }
        print final_val;
    }
')

AVAILABLE_MEM=$(free -m | awk '/^Mem:/ {print $7}')

# --- STATEFUL ERROR THROTTLES ---
LOAD_EXCEEDED=$(awk -v cur="$CURRENT_LOAD" -v max="$DYNAMIC_THRESHOLD" 'BEGIN {print (cur > max) ? 1 : 0}')
if [ "$LOAD_EXCEEDED" -eq 1 ]; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] STATE_ERR: High load spikes ($CURRENT_LOAD > $DYNAMIC_THRESHOLD)." >&2
    exit 11
fi

if [ -n "$AVAILABLE_MEM" ] && [ "$AVAILABLE_MEM" -lt "$MIN_FREE_MEM_MB" ]; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] STATE_ERR: Memory starvation threshold hit (${AVAILABLE_MEM}MB available)." >&2
    exit 12
fi

# -------------------------------------------------------------
# CORE AFFINITY (TASKSET) PREPARATION
# -------------------------------------------------------------
TASKSET_CMD=""
if [ "$ALLOW_PINNING" = "true" ] && command -v taskset &>/dev/null; then
    if command -v mpstat &>/dev/null; then
        TARGET_CORE=$(mpstat -P ALL 1 1 | awk '/^[0-9]/ && $3 !~ /all/ {print $3, $NF}' | sort -nk2 | tail -n1 | awk '{print $1}')
    fi
    if [ -z "$TARGET_CORE" ]; then
        TARGET_CORE=$(( $$ % CORES ))
    fi
    TASKSET_CMD="taskset -c $TARGET_CORE"
fi

# -------------------------------------------------------------
# GENERATE DETAILED LAUNCH PATTERNS
# -------------------------------------------------------------
MATLAB_STATEMENT="$SCRIPT_NAME"
[ -n "$MATLAB_ARGS_STR" ] && MATLAB_STATEMENT="${SCRIPT_NAME}(${MATLAB_ARGS_STR})"

MATLAB_EXEC="$TASKSET_CMD timeout --kill-after=10s $TIMEOUT_LIMIT matlab -batch \"if verLessThan('matlab', '$MIN_MATLAB'); error('Version older than %s', '$MIN_MATLAB'); end; ${MATLAB_STATEMENT};\""

# Store base execution tokens in an array to avoid destructive shell word splitting
OCTAVE_EXEC_ARRAY=()
[ -n "$TASKSET_CMD" ] && OCTAVE_EXEC_ARRAY+=($TASKSET_CMD)
OCTAVE_EXEC_ARRAY+=(timeout "$TIMEOUT_LIMIT" octave --cli --eval "if compare_versions(version(), '$MIN_OCTAVE', '<'); error('Version older than %s', '$MIN_OCTAVE'); end; run('$FILE_NAME');" --)

# -------------------------------------------------------------
# EVALUATE TIMESTAMPED DRY RUN AUDIT
# -------------------------------------------------------------
if [ "$DRY_RUN" = "true" ]; then
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "=================== SYSTEMS DRY-RUN CONFIGURATION AUDIT ==================="
    echo "Timestamp (UTC):     $TS"
    echo "Job / Batch Tag:     $BATCH_TAG"
    echo "Target Script:       $FILE_PATH"
    echo "Platform Profile:    $PLATFORM"
    echo "Detected CPU Cores:  $CORES"
    echo "Current 1-Min Load:  $CURRENT_LOAD"
    echo "Calculated Boundary: $DYNAMIC_THRESHOLD (Pinning Forced: $ALLOW_PINNING)"
    echo "Available Memory:    ${AVAILABLE_MEM} MB (Required Min: ${MIN_FREE_MEM_MB} MB)"
    echo "---------------------------------------------------------------------------"
    echo "Piped Arguments Isolation (Element-by-Element Analysis):"
    if [ ${#SCRIPT_ARGS[@]} -eq 0 ]; then
        echo "  [No arguments passed]"
    else
        for i in "${!SCRIPT_ARGS[@]}"; do
            printf "  Index [%d]: ->%s<-\n" "$i" "${SCRIPT_ARGS[$i]}"
        done
    fi
    echo "---------------------------------------------------------------------------"
    echo "Proposed MATLAB Execution String:"
    echo "  $MATLAB_EXEC"
    echo ""
    echo "Proposed GNU Octave Recovery Sequence Array:"
    echo "  ${OCTAVE_EXEC_ARRAY[*]} [script_args...]"
    echo "==========================================================================="
    exit 0
fi

# -------------------------------------------------------------
# ACTUAL PROCESS PIPELINE DEPLOYMENT
# -------------------------------------------------------------
cd "$FILE_DIR" || exit 1

# Path 1: MATLAB TARGET INTERPRETER
if command -v matlab &> /dev/null && command -v timeout &> /dev/null; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] Deploying MATLAB pipeline..."
    eval "$MATLAB_EXEC"
    exit_code=$?

    case $exit_code in
        0)   echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] Status: Success."; exit 0 ;;
        124|137) echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] STATE_ERR: MATLAB worker hit async deadlock or OOM (Exit: $exit_code). Attempting Fallback..." >&2 ;;
        *)   echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] STATE_ERR: MATLAB script failure (Exit: $exit_code)." >&2; exit 21 ;;
    esac
fi

# Path 2: GNU OCTAVE RECOVERY FALLBACK
if command -v octave &> /dev/null; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] Deploying GNU Octave fallback stream..."
    
    # Safe array expansion preserves spaces and inner structural characters perfectly
    "${OCTAVE_EXEC_ARRAY[@]}" "${SCRIPT_ARGS[@]}"
    octave_code=$?

    if [ $octave_code -eq 124 ]; then
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] STATE_ERR: GNU Octave worker hit real-time async timeout allocation." >&2
        exit 22
    elif [ $octave_code -eq 0 ]; then
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] Status: Fallback Success."
        exit 0
    else
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] STATE_ERR: GNU Octave worker calculation failure (Exit: $octave_code)." >&2
        exit 23
    fi
fi

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")][TAG:$BATCH_TAG] STATE_ERR: No viable runtime targets found on system path." >&2
exit 30
