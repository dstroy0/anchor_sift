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
#   Git Bash does not run. Maint/engine/build_engine.sh finds nvcc unusable and skips CUDA. This
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
$src = Join-Path $root "src\engine"
$build = Join-Path $root "build\engine_c"

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Error "cmake is not on PATH."
    exit 1
}

$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if (Test-Path $vcvars) {
    Write-Host "[*] importing MSVC environment"
    $envDump = cmd /c "`"$vcvars`" >nul 2>&1 && set"
    foreach ($line in $envDump) {
        if ($line -match '^([^=]+)=(.*)$') {
            Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2] -ErrorAction SilentlyContinue
        }
    }
}
else {
    Write-Host "[!] vcvars64.bat not found. Without it nvcc has no host compiler and CUDA is skipped."
}

if (-not (Get-Command nvcc -ErrorAction SilentlyContinue)) {
    $toolkits = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*\bin\nvcc.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending
    if ($toolkits) {
        $env:PATH = (Split-Path $toolkits[0].FullName) + ";" + $env:PATH
        Write-Host "[*] nvcc found off PATH at $($toolkits[0].FullName)"
    }
}

$generator = @()
if (Get-Command ninja -ErrorAction SilentlyContinue) {
    $generator = @("-G", "Ninja")
}
else {
    $bundled = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
    if (Test-Path (Join-Path $bundled "ninja.exe")) {
        $env:PATH = $bundled + ";" + $env:PATH
        $generator = @("-G", "Ninja")
        Write-Host "[*] using the ninja bundled with the build tools"
    }
}

$haveCuda = [bool](Get-Command nvcc -ErrorAction SilentlyContinue) -and
[bool](Get-Command cl.exe -ErrorAction SilentlyContinue)
if ($haveCuda) {
    Write-Host "[*] nvcc and cl.exe both present, the device arm will be compiled in" -ForegroundColor Cyan
}
else {
    Write-Host "[!] device arm skipped, host arms only" -ForegroundColor Yellow
}

# A CACHE LEFT BY ANOTHER RUN OUTRANKS EVERY MESSAGE PRINTED ABOVE. ANCHOR_SKIP_CUDA is an
# option() and CMAKE_C_COMPILER is cached. A build tree configured once by build_engine.sh under
# gcc with CUDA skipped keeps both settings through every later configure here. This script then
# announced "importing MSVC environment" and "the device arm will be compiled in" and produced a gcc
# build with no CUDA in it. All three statements were false and nothing reported a conflict.
#
# This is the stale device failure one layer up: the announcement describes the intent and the cache
# decides the build, and agreement between them is never checked. The two decisive variables are
# passed explicitly on every configure now, and a cache naming a different C compiler is removed
# and not argued with, because CMake refuses a compiler change outright.
$cache = Join-Path $build "CMakeCache.txt"
if (Test-Path $cache) {
    $cachedCompiler = Select-String -Path $cache -Pattern "^CMAKE_C_COMPILER:" -ErrorAction SilentlyContinue
    if ($cachedCompiler -and ($cachedCompiler.Line -notmatch "cl\.exe")) {
        Write-Host "[*] cached toolchain is not MSVC, reconfiguring from scratch" -ForegroundColor Yellow
        Remove-Item -Force $cache
        Remove-Item -Recurse -Force (Join-Path $build "CMakeFiles") -ErrorAction SilentlyContinue
    }
}

Write-Host "[*] configuring"
$configure = @("-S", $src, "-B", $build) + $generator + @("-DCMAKE_BUILD_TYPE=Release")
if ($haveCuda) {
    $configure += "-DANCHOR_SKIP_CUDA=OFF"
}
else {
    $configure += "-DANCHOR_SKIP_CUDA=ON"
}
& cmake @configure | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "configure failed"
    exit 1
}

# THE ANNOUNCEMENT IS CHECKED AGAINST THE CACHE. The defect above was a script stating an intent
# while the build did something else, and nothing compared the two. Where the device arm was
# announced and the configure carries no CUDA compiler, that is a failure here and not a
# discovery twenty minutes later in a raster row reading "host only".
if ($haveCuda) {
    $cudaLine = Select-String -Path $cache -Pattern "^CMAKE_CUDA_COMPILER:" -ErrorAction SilentlyContinue
    if ((-not $cudaLine) -or ($cudaLine.Line -match "NOTFOUND")) {
        Write-Error "the device arm was announced but the configure carries no CUDA compiler"
        exit 1
    }
    Write-Host "[+] device arm confirmed in the configure" -ForegroundColor Green
}

# NAMED TARGETS AND NOT THE DEFAULT ALL. Two benches in this directory do not compile with MSVC and
# a bare build therefore fails on Windows with the engine itself built fine. Measured 2026-09-16
# against MSVC 14.44: bench_lattice.c:500 onward needs C99 _Complex arithmetic, and MSVC supplies
# the types without the operators. It predates this script.
#
# bench_dispatch used to sit beside it and no longer does. Its cycle counter gate tested __x86_64__
# alone, a GCC and Clang predefine MSVC never sets. Every MSVC build fell through to a POSIX
# clock_gettime that MSVC does not ship. The gate now carries the MSVC definition.
#
# anchor_steer and anchor_steer_arms used to be on this list and no longer exist. Both folded into
# anchor_sift_kernel, the whole engine in one translation unit.
$targets = @("anchor_sift_kernel", "anchor_sift_kernel_counted", "anchor_raster", "anchor_render",
    "anchor_exact_portable", "test_steer", "test_adversarial", "test_arm_agreement",
    "test_o2_spawn",
    "bench_steer_arms", "bench_raster", "bench_exact_arms", "bench_exact",
    "bench_dispatch", "bench_coherence", "bench_scaling_reads", "bench_scaling_cycles")
Write-Host "[*] building"
foreach ($target in $targets) {
    & cmake --build $build --target $target | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "target $target did not build"
        exit 1
    }
}
Write-Host "[+] built into $build" -ForegroundColor Green

if ($BuildOnly) {
    exit 0
}

$failed = 0
foreach ($grader in @("test_steer", "test_adversarial", "test_arm_agreement", "test_o2_spawn", "bench_steer_arms", "bench_raster", "bench_exact_arms")) {
    $exe = Join-Path $build "$grader.exe"
    if (-not (Test-Path $exe)) {
        Write-Host "[!] $grader was not built" -ForegroundColor Red
        $failed += 1
        continue
    }

    Write-Host ""
    Write-Host "[*] $grader" -ForegroundColor Cyan
    Push-Location $build
    try {
        & $exe
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] $grader reported a failure" -ForegroundColor Red
            $failed += 1
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host ""
if ($failed -ne 0) {
    Write-Error "$failed grader(s) failed"
    exit 1
}
Write-Host "[+] all graders passed" -ForegroundColor Green
