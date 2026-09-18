# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Builds the direct renderer with BOTH arms and grades them against each other.
#
#     maint/engine/build_gpu_raster.ps1 [-Arch sm_86]
#
# nvcc drives a host compiler and on Windows that host compiler is MSVC. The CMake build uses a
# different one, and objects from the two do not link. The device arm gets its own build exactly
# as the exact arm does in build_gpu_arm.sh. Everything this binary needs is compiled here by the one
# compiler nvcc is driving, which is what keeps the ABI consistent inside it.
#
# The result is bench_raster with the device arm compiled in. Without this script the CMake build
# still produces bench_raster, linking the stub arms in anchor_raster.c, and it reports the device as
# absent and grades the host alone. That is a skip and never a pass.

param(
    [string]$Arch = ""
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$src = Join-Path $root "src\engine\c"
$render = Join-Path $src "render"
$out = Join-Path $root "build\engine_gpu"

if (-not (Get-Command nvcc -ErrorAction SilentlyContinue))
{
    Write-Error "nvcc is not on PATH. Install the CUDA toolkit, or build the host arm alone with maint/engine/build_engine.sh."
    exit 1
}

if ($Arch -eq "")
{
    $capability = (nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>$null | Select-Object -First 1)
    if ($capability)
    {
        $Arch = "sm_" + ($capability.Trim() -replace '\.', '')
    }
    else
    {
        # No device to ask. Compiling for a default still checks that the code compiles and that the
        # assembler accepts it, and the grader will report the device as absent at run time.
        $Arch = "sm_86"
    }
}
Write-Host "[*] architecture $Arch"

$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars))
{
    Write-Error "vcvars64.bat not found. nvcc needs an MSVC host compiler on Windows."
    exit 1
}

Write-Host "[*] importing MSVC environment"
$envDump = cmd /c "`"$vcvars`" >nul 2>&1 && set"
foreach ($line in $envDump)
{
    if ($line -match '^([^=]+)=(.*)$')
    {
        Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2] -ErrorAction SilentlyContinue
    }
}

New-Item -ItemType Directory -Force $out | Out-Null

# ANCHOR_RASTER_HAVE_CUDA is what suppresses the stub arms in anchor_raster.c. Defined on this build
# and undefined on the CMake one. Exactly one definition of each device symbol ever exists.
$defines = "-DANCHOR_RASTER_HAVE_CUDA=1"
$includes = "-I`"$src\portable`" -I`"$src\no_rounding`" -I`"$render`""

# TWO STEPS, AND THE SPLIT IS FORCED. The C sources use _Static_assert, which is
# C11. Handing them to nvcc compiles them through the C++ front end, where that keyword does not
# exist, and MSVC's default C mode does not carry it either. So the C files are compiled first by cl
# at /std:c11, and nvcc compiles the device file and links the objects. Passing -x cu over the whole
# set fails at exact_integer.h:77 and passing them to nvcc by extension fails the same way.
$clIncludes = @(
    "/I" + (Join-Path $src "portable"),
    "/I" + (Join-Path $src "no_rounding"),
    "/I" + $render
)

Push-Location $out
try
{
    Write-Host "[*] cl /std:c11 -> objects"
    $units = @(
        (Join-Path $render "anchor_raster.c"),
        (Join-Path $src "no_rounding\exact_integer.c"),
        (Join-Path $src "portable\anchor_sift.c"),
        (Join-Path $src "bench\bench_raster.c")
    )
    foreach ($unit in $units)
    {
        & cl /nologo /std:c11 /O2 /DANCHOR_RASTER_HAVE_CUDA=1 $clIncludes /c $unit | Out-Null
        if ($LASTEXITCODE -ne 0)
        {
            Write-Error "cl failed on $unit"
            exit 1
        }
    }

    Write-Host "[*] nvcc -> bench_raster.exe"
    & nvcc -O3 "-arch=$Arch" -DANCHOR_RASTER_HAVE_CUDA=1 ("-I" + $render) `
        (Join-Path $render "raster_cuda.cu") `
        anchor_raster.obj exact_integer.obj anchor_sift.obj bench_raster.obj `
        -o bench_raster.exe
    if ($LASTEXITCODE -ne 0)
    {
        Write-Error "nvcc failed linking the renderer"
        exit 1
    }
}
finally
{
    Pop-Location
}

Write-Host "[+] built $out\bench_raster.exe" -ForegroundColor Green
Write-Host "[*] grading host against device"

Push-Location $out
try
{
    & (Join-Path $out "bench_raster.exe")
    $code = $LASTEXITCODE
}
finally
{
    Pop-Location
}

if ($code -ne 0)
{
    Write-Error "the renderer grader reported a failure"
    exit 1
}
Write-Host "[+] host and device agree on every configuration" -ForegroundColor Green
