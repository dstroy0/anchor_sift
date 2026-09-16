# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Builds the engine on Windows and runs the graders. One command, no arguments.
#
#     maint\engine\build_engine.ps1
#     maint\engine\build_engine.ps1 -BuildOnly
#
# THIS IS THE WINDOWS ENTRY POINT AND IT GETS THE GPU. A machine with a card renders on it without
# anyone asking, and three things have to line up for that which a bare configure does not do.
#
#   nvcc drives a host compiler. On Windows that is MSVC and it reaches PATH through vcvars, which
#   Git Bash does not run, so maint/engine/build_engine.sh finds nvcc unusable and skips CUDA. This
#   script imports that environment first.
#
#   The Visual Studio generator compiles .cu only where the toolkit installed its MSBuild
#   integration, which a normal install often skips, and CMake stops with "No CUDA toolset found".
#   Ninja needs no integration and is used where it is present.
#
#   nvcc is frequently not on PATH even where the toolkit is installed. The standard locations are
#   searched and the newest is put on PATH for the configure.
#
# Where any of that is missing the build still succeeds with the host arms and says what was
# skipped. A skipped device is reported, never silent.

param(
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$src = Join-Path $root "src\engine\c"
$build = Join-Path $root "build\engine_c"

if (-not (Get-Command cmake -ErrorAction SilentlyContinue))
{
    Write-Error "cmake is not on PATH."
    exit 1
}

$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if (Test-Path $vcvars)
{
    Write-Host "[*] importing MSVC environment"
    $envDump = cmd /c "`"$vcvars`" >nul 2>&1 && set"
    foreach ($line in $envDump)
    {
        if ($line -match '^([^=]+)=(.*)$')
        {
            Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2] -ErrorAction SilentlyContinue
        }
    }
}
else
{
    Write-Host "[!] vcvars64.bat not found. Without it nvcc has no host compiler and CUDA is skipped."
}

if (-not (Get-Command nvcc -ErrorAction SilentlyContinue))
{
    $toolkits = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*\bin\nvcc.exe" -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending
    if ($toolkits)
    {
        $env:PATH = (Split-Path $toolkits[0].FullName) + ";" + $env:PATH
        Write-Host "[*] nvcc found off PATH at $($toolkits[0].FullName)"
    }
}

$generator = @()
if (Get-Command ninja -ErrorAction SilentlyContinue)
{
    $generator = @("-G", "Ninja")
}
else
{
    $bundled = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
    if (Test-Path (Join-Path $bundled "ninja.exe"))
    {
        $env:PATH = $bundled + ";" + $env:PATH
        $generator = @("-G", "Ninja")
        Write-Host "[*] using the ninja bundled with the build tools"
    }
}

$haveCuda = [bool](Get-Command nvcc -ErrorAction SilentlyContinue) -and
            [bool](Get-Command cl.exe -ErrorAction SilentlyContinue)
if ($haveCuda)
{
    Write-Host "[*] nvcc and cl.exe both present, the device arm will be compiled in" -ForegroundColor Cyan
}
else
{
    Write-Host "[!] device arm skipped, host arms only" -ForegroundColor Yellow
}

Write-Host "[*] configuring"
$configure = @("-S", $src, "-B", $build) + $generator + @("-DCMAKE_BUILD_TYPE=Release")
if (-not $haveCuda)
{
    $configure += "-DANCHOR_SKIP_CUDA=ON"
}
& cmake @configure | Out-Null
if ($LASTEXITCODE -ne 0)
{
    Write-Error "configure failed"
    exit 1
}

# NAMED TARGETS AND NOT THE DEFAULT ALL. Two benches in this directory do not compile with MSVC and
# a bare build therefore fails on Windows with the engine itself built fine. Measured 2026-09-16
# against MSVC 14.44: bench_dispatch.c:105 uses CLOCK_MONOTONIC, which is POSIX and absent, and
# bench_lattice.c:500 onward does not parse. Both predate this script.
$targets = @("anchor_sift_kernel", "anchor_steer", "anchor_steer_arms", "anchor_raster",
             "anchor_exact_portable", "test_steer", "bench_steer_arms", "bench_raster",
             "bench_exact_arms", "bench_exact")
Write-Host "[*] building"
foreach ($target in $targets)
{
    & cmake --build $build --target $target | Out-Null
    if ($LASTEXITCODE -ne 0)
    {
        Write-Error "target $target did not build"
        exit 1
    }
}
Write-Host "[+] built into $build" -ForegroundColor Green

if ($BuildOnly)
{
    exit 0
}

$failed = 0
foreach ($grader in @("test_steer", "bench_steer_arms", "bench_raster", "bench_exact_arms"))
{
    $exe = Join-Path $build "$grader.exe"
    if (-not (Test-Path $exe))
    {
        Write-Host "[!] $grader was not built" -ForegroundColor Red
        $failed += 1
        continue
    }

    Write-Host ""
    Write-Host "[*] $grader" -ForegroundColor Cyan
    Push-Location $build
    try
    {
        & $exe
        if ($LASTEXITCODE -ne 0)
        {
            Write-Host "[!] $grader reported a failure" -ForegroundColor Red
            $failed += 1
        }
    }
    finally
    {
        Pop-Location
    }
}

Write-Host ""
if ($failed -ne 0)
{
    Write-Error "$failed grader(s) failed"
    exit 1
}
Write-Host "[+] all graders passed" -ForegroundColor Green
