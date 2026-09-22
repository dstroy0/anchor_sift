# Sorts src into subdirectories by what each file is.
#
# src had forty-six sources in one flat directory, of which twenty-five were benches, and finding
# the engine among them took reading the whole listing. The split is by role rather than by
# language, because the question asked of this tree is almost always "where is the engine" or
# "which bench produced that number" and never "which files are C".
#
#   engine   the hash itself and the arms that run it, host and device
#   client   the miner that talks to a pool, and what it needs
#   bench    every measurement, and the two headers they share
#   test     the correctness gate
#   scripts  the run wrappers that live with the sources
#
# git mv rather than move, so the history follows the files.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src = Join-Path $root "src"

$layout = @{
    "engine"  = @("sha256_core.c", "sha256_core.h", "cuda_miner.cu", "cuda_miner.h",
                  "anchor_sift.c", "anchor_sift.h", "anchor_sift_hw.c")
    "client"  = @("btc_miner.cpp", "json_value.h", "candidate.cpp", "harness.cpp")
    "test"    = @("kat_validation.cpp")
    "scripts" = @("cat_logs.ps1", "relaunch_miner.ps1", "run_miner.ps1")
}

foreach ($folder in $layout.Keys)
{
    New-Item -ItemType Directory -Force -Path (Join-Path $src $folder) | Out-Null
}
New-Item -ItemType Directory -Force -Path (Join-Path $src "bench") | Out-Null

Push-Location $root
try
{
    foreach ($folder in $layout.Keys)
    {
        foreach ($name in $layout[$folder])
        {
            $from = Join-Path "src" $name
            if (Test-Path $from)
            {
                & git mv $from (Join-Path (Join-Path "src" $folder) $name)
                Write-Host "  $name -> $folder" -ForegroundColor DarkGray
            }
        }
    }

    # Everything named for a bench, plus the two headers only benches include.
    $benches = @(Get-ChildItem -Path $src -Filter "bench_*" -File)
    foreach ($file in $benches)
    {
        & git mv (Join-Path "src" $file.Name) (Join-Path "src\bench" $file.Name)
        Write-Host "  $($file.Name) -> bench" -ForegroundColor DarkGray
    }
}
finally
{
    Pop-Location
}

Write-Host ""
Write-Host "[*] src now holds:" -ForegroundColor Cyan
Get-ChildItem -Path $src -Directory | ForEach-Object {
    $count = @(Get-ChildItem -Path $_.FullName -File).Count
    Write-Host ("    {0,-9} {1} files" -f $_.Name, $count)
}
$loose = @(Get-ChildItem -Path $src -File | Where-Object { $_.Extension -notin @(".exe", ".txt", ".obj") })
if ($loose.Count -gt 0)
{
    Write-Host "    still loose: $($loose.Name -join ', ')" -ForegroundColor Yellow
}
