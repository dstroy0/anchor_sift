# Sweeps the seed on the benches carrying live claims, and reports how far each number moves.
#
# Failure mode fourteen in docs/failure-modes.md. A statistic that appears at one draw and not at
# others is a draw. Thirty-two of the fixed seeds in this tree are the same constant, so nothing
# measured here has ever been asked whether it survives a different one.
#
# The three-arm compiler audit already showed these benches are deterministic: one seed gives one
# answer under three different builds. That is not the same property. Determinism says the program
# computes a function of its seed; stability says the answer is a property of SHA-256 rather than
# of the seed. Only the second one makes a number quotable.
#
# Output goes to maint/audit/audit_seeds.py, which lines the runs up and reports min, max and spread for
# every number that appears in the same place across seeds.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$src = Join-Path $root "src"
$engine = Join-Path $src "engine" "c" "sha256" "core"
# Not $bench: the loops below bind that name to each source in turn.
$benchDirectory = Join-Path $src "engine" "c" "sha256" "bench"
$format = Join-Path $src "engine" "c" "sha256" "format"
$work = Join-Path $root "build" "audit" "seeds"
$compiler = "g++"

# The benches whose numbers the workbook quotes and which draw from a generator. Benches that
# enumerate rather than sample have no seed to sweep and are not here.
$benches = @(
    "bench_deltanull",
    "bench_closeness",
    "bench_canary",
    "bench_orbit",
    "bench_sweep",
    "bench_tail",
    "bench_dimension"
)

# Seeds chosen to have nothing in common with each other or with the written one. A sweep over
# neighboring integers would share generator state structure and would not be a sweep.
$seeds = @(20260908, 1, 424242, 999983, 2147483647, 70368744177643)

New-Item -ItemType Directory -Force -Path $work | Out-Null

$object = Join-Path $work "sha256_core.o"
Write-Host "[*] building core" -ForegroundColor Cyan
& $compiler -c (Join-Path $engine "sha256_core.c") -o $object -O2 -mavx2
if ($LASTEXITCODE -ne 0) { Write-Error "core build failed"; exit 1 }

foreach ($bench in $benches)
{
    $exe = Join-Path $work ($bench + ".exe")
    Write-Host "[*] building $bench" -ForegroundColor DarkCyan
    & $compiler (Join-Path $benchDirectory ($bench + ".cpp")) $object -o $exe -O2 -mavx2 `
        -std=c++17 -ffp-contract=off -I $engine -I $benchDirectory -I $format
    if ($LASTEXITCODE -ne 0) { Write-Error "$bench build failed"; exit 1 }
}

$parallel = [Math]::Max(1, [int]$env:NUMBER_OF_PROCESSORS - 1)
Write-Host "[*] running $($benches.Count) benches at $($seeds.Count) seeds, $parallel at a time" `
    -ForegroundColor Cyan

$jobs = @()
foreach ($bench in $benches)
{
    foreach ($seed in $seeds)
    {
        $jobs += [pscustomobject]@{
            Bench = $bench
            Seed  = $seed
            Exe   = Join-Path $work ($bench + ".exe")
            Out   = Join-Path $work ("{0}.{1}.out" -f $bench, $seed)
        }
    }
}

$jobs | ForEach-Object -ThrottleLimit $parallel -Parallel {
    Set-Location $using:root
    $env:BENCH_SEED = $_.Seed
    try
    {
        & $_.Exe *> $_.Out
    }
    catch
    {
        Set-Content -Path $_.Out -Value "RUN FAILED: $_"
    }
}

Write-Host "[*] done, comparing" -ForegroundColor Cyan
& python (Join-Path $root "maint" "audit" "audit_seeds.py") $work
