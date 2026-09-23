# Compiles bench_sac.cu to an object only, so it can be syntax-checked while bench_sac.exe is
# locked by a running measurement. The object goes to the temp directory rather than the tree.
$ErrorActionPreference = "Stop"

$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
$envDump = cmd /c "`"$vcvars`" >nul 2>&1 && set"
foreach ($line in $envDump)
{
    if ($line -match '^([^=]+)=(.*)$')
    {
        Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2] -ErrorAction SilentlyContinue
    }
}

$out = Join-Path $env:TEMP "bench_sac_check.obj"
& nvcc -O1 -arch=sm_86 -c -o $out (Join-Path $PSScriptRoot "bench_sac.cu") -Xcompiler "/EHsc"
if ($LASTEXITCODE -ne 0)
{
    Write-Host "[!] bench_sac.cu does not compile" -ForegroundColor Red
    exit 1
}
Write-Host "[*] bench_sac.cu compiles" -ForegroundColor Green
