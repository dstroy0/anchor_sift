# Simulation deployment tools

    Meant for assisting data scientists, teachers, students, researchers, the general public, anyone interested. This will aid in learning more about the anchor_sift algorithm, from a more rigorous standard than I can apply alone, for research or a genuine interest in the language. First and foremost this toolset is aimed at linguists, statisticians, mathematicians, theorists, and any category I haven't named that belongs here, my apologies this document can be amended, I don't use your tools and am not trained in them, I am strictly a polymath and am untrained formally in any of your given subjects please, critique and refine the work. I am just an adventurous C programmer experimenting outside of their small embedded world.

## clustering and N=1 using `chk_run.sh`

    Tool for running the simulations on a given set of N computers : baseline load measurement plus modulo resource assign request branch, or core pinning, or both

    Cluster type and tool aware (tool version pinning supported)

    Please let me know if you need more features, or just add them in a PR. Thanks for your valuable time.

    ***State Error Matrices***
    Exit Code State Trigger Description
    0 Execution successfully terminated with zero errors.
    11 CPU Pre-Flight Abort: Current hardware load spike violated core modulo threshold.
    12 Memory Pre-Flight Abort: Host/container contains less than 1024 MB of free space.
    21 MATLAB Script Failure: Internal code error threw an unhandled exception inside MATLAB.
    22 Octave Async Hang: GNU Octave ran, but violated the absolute TIMEOUT_LIMIT.
    23 Octave Script Failure: Fallback interpreter threw a hard code execution error.
    30 Environment Deficit: Neither software application was available on system paths.

### Examples of usage

    ***Invocation***
    ```bash
    #!/bin/bash
    ./chk_run.sh --dry-run --tag "experiment-7" simulation.m -- "/mnt/shared/data directory/" '{"alpha": 0.001, "name": "test_run"}'
    ```
    ***Output***
    ```text
    =================== SYSTEMS DRY-RUN CONFIGURATION AUDIT ===================
    Timestamp (UTC):     2026-09-04T23:00:00Z
    Job / Batch Tag:     experiment-7
    Target Script:       simulation.m
    Platform Profile:    Bare-Metal/VM
    Detected CPU Cores:  8
    Current 1-Min Load:  1.42
    Calculated Boundary: 1 (Pinning Forced: false)
    Available Memory:    16240 MB (Required Min: 1024 MB)
    ---------------------------------------------------------------------------
    Piped Arguments Isolation (Element-by-Element Analysis):
    Index: ->/mnt/shared/data directory/<-
    Index: ->{"alpha": 0.001, "name": "test_run"}<-
    ---------------------------------------------------------------------------

    Proposed MATLAB Execution String:
        timeout --kill-after=10s 45s matlab -batch "if verLessThan('matlab', '9.6'); error('Version older than %s', '9.6'); end; simulation('/mnt/shared/data directory/','{"alpha": 0.001, "name": "test_run"}');"

    Proposed GNU Octave Recovery Sequence Array:
        timeout 45s octave --cli --eval if compare_versions(version(), '6.0', '<'); error('Version older than %s', '6.0'); end; run('simulation.m'); -- [script_args...]
    ===========================================================================
    ```
