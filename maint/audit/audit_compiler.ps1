# Audits every bench for compiler-dependent results.
#
# The concern is exact: a compiler is free to fold, reassociate, contract and hoist arithmetic, and
# where it folds a measurement into an immediate the bench prints a compile-time answer while
# appearing to compute one. bench_engines already caught a whole engine that was a constant
# function; nothing structural stops the same thing happening to a statistic.
#
# The test that settles it is differential rather than inspective. Each bench is built three ways
# and run three times:
#
#   O0    no optimisation at all, so nothing is folded, hoisted or contracted
#   O2    the flags the tree was built with
#   NOFMA O2 with fused multiply-add contraction disabled, which is on by default in GCC
#
# A bench whose three outputs are byte-identical computed its numbers rather than inheriting them.
# A bench whose outputs differ had a result the compiler participated in, and that result has to be
# re-derived before it is quoted. This is a whole-tree check: it does not require guessing which
# statistic might be fragile.
#
# Benches seeded from a fixed constant are deterministic by construction, so any difference between
# the three is the compiler and nothing else.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src = Join-Path $root "src"
$engine = Join-Path $src "engine"
# Not $bench: the loop below binds that name to each source in turn, and a directory sharing it
# would be silently replaced part way through.
$benchDirectory = Join-Path $src "bench"
$format = Join-Path $src "format"
$testDirectory = Join-Path $src "test"
$work = Join-Path $root "audit"
$compiler = "g++"

New-Item -ItemType Directory -Force -Path $work | Out-Null

# Each arm is a name and the flags that define it. The core is rebuilt per arm so that the
# compression function itself is subject to the same treatment as the statistics that read it.
# The O0 arm carries no -mavx2, and the reason is a compiler defect rather than a preference.
# MinGW-w64 GCC mishandles over-aligned locals at -O0 on this ABI: it hand-aligns a pointer for one
# __m256i local and then places another at a fixed offset from a frame pointer it never realigned,
# so it emits vmovdqa - the *aligned* 256-bit move - against an address that is 16 mod 32, and the
# process takes a general protection fault. The faulting instruction is
#
#   vmovdqa %ymm0,-0x20(%rbp)     with rbp = 0x5fe0b0, so the target is 0x5fe090, 16 mod 32
#
# and -mstackrealign changes the prologue not at all. Nothing in this tree causes it and no source
# change here avoids it.
#
# sha256_core.c gates its vector arm on __AVX2__ and its else arm defers to the scalar reference, so
# without -mavx2 the O0 build is the reference arm compiled unoptimised. That is the arm a fold
# audit wants anyway: it is the one whose arithmetic the statistics read.
#
# What this costs, stated rather than buried: for the two benches that exercise the vector arm, the
# O0 column tests different code from the other two columns, so an agreement there is evidence about
# the reference arm and not about the vector arm. The vector arm is covered instead by
# kat_validation, which asserts it equal to the reference on the FIPS vectors, the genesis block,
# block 125552 and 1000 consecutive real headers.
$arms = @(
    @{ Name = "O0";    Flags = @("-O0") },
    @{ Name = "O2";    Flags = @("-O2", "-mavx2") },
    @{ Name = "NOFMA"; Flags = @("-O2", "-mavx2", "-ffp-contract=off") }
)

# kat_validation is included deliberately. It is the correctness gate every other result rests on,
# so a compiler-dependent answer there would be the most expensive one to miss.
$benches = @(Get-ChildItem -Path $benchDirectory -Filter "bench_*.cpp" |
    Where-Object { $_.Name -notin @("bench_cuda.cpp", "bench_keyhole.cpp") }) +
    @(Get-ChildItem -Path $testDirectory -Filter "kat_validation.cpp")
$benches = $benches | Sort-Object Name

Write-Host "[*] auditing $($benches.Count) benches over $($arms.Count) arms" -ForegroundColor Cyan

foreach ($arm in $arms)
{
    $armDirectory = Join-Path $work $arm.Name
    New-Item -ItemType Directory -Force -Path $armDirectory | Out-Null

    $coreObject = Join-Path $armDirectory "sha256_core.o"
    Write-Host "[*] arm $($arm.Name): building core" -ForegroundColor DarkCyan
    & $compiler -c (Join-Path $engine "sha256_core.c") -o $coreObject @($arm.Flags) -std=c11
    if ($LASTEXITCODE -ne 0) { Write-Error "core failed on arm $($arm.Name)"; exit 1 }

    foreach ($bench in $benches)
    {
        $exe = Join-Path $armDirectory ($bench.BaseName + ".exe")
        & $compiler $bench.FullName $coreObject -o $exe @($arm.Flags) -std=c++17 `
            -I $engine -I $benchDirectory -I $format 2>&1 |
            Out-Null
        if ($LASTEXITCODE -ne 0)
        {
            Write-Host "    [skip] $($bench.BaseName) did not build on $($arm.Name)" -ForegroundColor DarkYellow
        }
    }
    Write-Host "[*] arm $($arm.Name): built" -ForegroundColor DarkCyan
}

# Running is the slow part and the benches are independent, so run them concurrently. One core is
# left for the machine, which is the standing rule for this tree.
$parallel = [Math]::Max(1, [int]$env:NUMBER_OF_PROCESSORS - 1)
Write-Host "[*] running, $parallel at a time" -ForegroundColor Cyan

$jobs = @()
foreach ($arm in $arms)
{
    foreach ($bench in $benches)
    {
        $exe = Join-Path (Join-Path $work $arm.Name) ($bench.BaseName + ".exe")
        if (-not (Test-Path $exe)) { continue }
        $jobs += [pscustomobject]@{ Arm = $arm.Name; Bench = $bench.BaseName; Exe = $exe }
    }
}

$jobs | ForEach-Object -ThrottleLimit $parallel -Parallel {
    $out = Join-Path (Split-Path -Parent $_.Exe) ($_.Bench + ".out")
    # Benches that read a data file resolve it relative to the tree root, so run from there rather
    # than from wherever the arm's binaries happen to live.
    Set-Location $using:root
    try
    {
        & $_.Exe *> $out
    }
    catch
    {
        Set-Content -Path $out -Value "RUN FAILED: $_"
    }
}

Write-Host "[*] comparing arms" -ForegroundColor Cyan

$report = @()
foreach ($bench in $benches)
{
    $hashes = @{}
    foreach ($arm in $arms)
    {
        $out = Join-Path (Join-Path $work $arm.Name) ($bench.BaseName + ".out")
        if (Test-Path $out)
        {
            $hashes[$arm.Name] = (Get-FileHash -Algorithm SHA256 -Path $out).Hash
        }
        else
        {
            $hashes[$arm.Name] = "ABSENT"
        }
    }

    $distinct = ($hashes.Values | Sort-Object -Unique)
    $verdict = if ($distinct.Count -eq 1) { "identical" } else { "DIFFERS" }

    $report += [pscustomobject]@{
        Bench   = $bench.BaseName
        Verdict = $verdict
        O0      = $hashes["O0"].Substring(0, 8)
        O2      = $hashes["O2"].Substring(0, 8)
        NOFMA   = $hashes["NOFMA"].Substring(0, 8)
    }
}

$report | Format-Table -AutoSize

$differing = @($report | Where-Object { $_.Verdict -ne "identical" })
Write-Host ""
Write-Host "[*] $($differing.Count) of $($report.Count) benches are compiler-dependent" -ForegroundColor `
    $(if ($differing.Count -eq 0) { "Green" } else { "Yellow" })
foreach ($row in $differing)
{
    Write-Host "    $($row.Bench)" -ForegroundColor Yellow
}

$report | Export-Csv -NoTypeInformation -Path (Join-Path $work "audit.csv")
Write-Host "[*] wrote $(Join-Path $work 'audit.csv')" -ForegroundColor Cyan
