# Sweeps the window phase, which no measurement in this tree has ever varied.
#
# From the symbol width posit in anchor_sift: a detector is not told where the units begin, and a
# slice of the right width at the wrong offset splits every unit across two symbols. Every window
# bench_renyi reads is byte aligned, so seven of the eight possible alignments have never been
# looked at, at any width. Structure sitting at an offset of one to seven bits would be split at
# every window in every run recorded so far and would be invisible to all of them.
#
# The sweep is affordable at a reduced domain because the resolution of a deficit ratio depends on
# the bin count and not on the domain size: the chi-square statistic behind it has variance twice
# its degrees of freedom, so one window resolves its deficit to sqrt(2/(r-1)) whatever the domain.
# A 2^28 run is therefore exactly as sensitive to a phase difference as a 2^32 run and costs a
# sixteenth as much, and eight of them together cost half of one full run.
#
# The splitmix control runs at every phase as well. A pseudorandom function has no preferred
# alignment, so its spread across phases is the floor below which a difference between phases on
# the real function means nothing.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$work = Join-Path $root "audit" "phase"
# Prefers the device build where it exists: the sweep is eight full runs and the host is shared.
$exe = Join-Path $root "src" "bench" "bench_renyi_gpu.exe"
$onDevice = 1
if (-not (Test-Path $exe))
{
    $exe = Join-Path $root "src" "bench" "bench_renyi.exe"
    $onDevice = 0
}

New-Item -ItemType Directory -Force -Path $work | Out-Null

if (-not (Test-Path $exe))
{
    Write-Error "bench_renyi.exe not built"
    exit 1
}

$domain = 28
Write-Host "[*] sweeping eight phases at domain 2^$domain" -ForegroundColor Cyan

foreach ($phase in 0..7)
{
    $out = Join-Path $work ("phase{0}.out" -f $phase)
    Write-Host "    phase $phase" -ForegroundColor DarkCyan
    # Holes off: the 32-bit window costs four gigabytes and answers a question about the
    # arrangement, not about alignment. Control four is the pseudorandom one and is the null here.
    # Zero threads means the polite default, which matters because this machine is in use.
    & $exe $domain 0 4 $phase 0 $onDevice *> $out
}

Write-Host "[*] comparing" -ForegroundColor Cyan
& python (Join-Path $root "tools" "sweep_phase.py") $work
