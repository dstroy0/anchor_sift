# Builds the surface packer for the device.
#
# nvcc on Windows drives cl.exe as its host compiler and will not find it on a bare PATH. The
# Visual Studio build tools put it somewhere only their own environment script knows about, so that
# script is imported here and its variables are carried into this session before nvcc is called.
# Without it nvcc stops with "Cannot find compiler 'cl.exe' in PATH", which reads as a missing CUDA
# install and is a missing environment.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
    $vcvars = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
}
if (-not (Test-Path $vcvars)) {
    Write-Error "vcvars64.bat not found. Install the VC++ build tools workload."
    exit 1
}

$dump = cmd /c "`"$vcvars`" >nul 2>&1 && set"
foreach ($line in $dump) {
    if ($line -match "^([^=]+)=(.*)$") {
        Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2]
    }
}

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if (-not $cl) { Write-Error "cl.exe still not on PATH after vcvars"; exit 1 }

# sm_86 is the part this was written against. A different card wants its own arch and nvcc says so
# plainly, so this is left explicit instead of guessed at from the device present.
$source = Join-Path $here "pack_shapes.cu"
$out = Join-Path $here "pack_shapes.exe"
& nvcc -O3 -arch=sm_86 -o $out $source
if ($LASTEXITCODE -ne 0) { Write-Error "nvcc failed"; exit $LASTEXITCODE }

Write-Output $out
