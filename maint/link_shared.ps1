# Points the files shared with anchor_sift at anchor_sift, so one edit reaches both.
#
#   Run elevated:  Start-Process pwsh -Verb RunAs -ArgumentList "-File","tools\link_shared.ps1"
#
# Windows refuses symlink creation to an unelevated process unless Developer Mode is on, which is
# why this is a separate script and not a line in a build.
#
# THE TARGETS ARE SEARCHED FOR, NOT SPELLED OUT
#
# anchor_sift is being reorganized: tools/ became maint/ and the links broke silently, so the next
# commit here was refused by a hook whose checker had no file behind it. A path written down here
# would break again on the next move. Each target is found by name instead, and a name that matches
# more than one file is reported and skipped rather than guessed at.
#
# WHY build_theory.sh IS SAFE TO LINK
#
# It derives its root with cd "$(dirname "$0")/../..". A shell sets $0 to the path as invoked and
# does not resolve it through the link, so running it from this repository as
# tools/book/build_theory.sh gives dirname tools/book, a real directory here, and ../.. lands back
# at this repository instead of at anchor_sift. The invocation carries the location.
#
# WHAT THIS COSTS
#
# Git stores these as symlinks. A clone on a machine without core.symlinks and Developer Mode gets a
# short text file holding a path instead of the file, and the book build fails oddly. That is
# acceptable while both trees are local, and it is the thing to remember if this is ever cloned
# fresh.

$ErrorActionPreference = "Stop"

$broken = 0
$here = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# ELEVATION IS CHECKED BEFORE ANYTHING IS REMOVED, NOT WHEN THE FIRST LINK IS WRITTEN.
#
# The loop below removes the existing link or file and then creates the replacement. Windows refuses
# symlink creation to an unelevated process, so run without elevation the remove succeeded and the
# create failed, and tools\book\build_theory.sh went from a stale link to no file at all - a script
# meant to repair links deleted one. The header has said "Run elevated" since it was written, which
# is exactly the kind of instruction that does not survive being ignored once.
#
# Refusing up front costs one API call and makes the failure mode "nothing happened".
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Host "  This script creates symlinks, which Windows allows only to an elevated process." -ForegroundColor Red
    Write-Host "  Nothing has been changed. Re-run it as:" -ForegroundColor Red
    Write-Host ""
    Write-Host '    Start-Process pwsh -Verb RunAs -ArgumentList "-File","maint\link_shared.ps1"'
    Write-Host ""
    exit 1
}
$trees = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
$anchor = Join-Path $trees "anchor_sift"
$repotools = Join-Path $trees "repo_tools"

if (-not (Test-Path $anchor))
{
    Write-Error "anchor_sift not found at $anchor"
    exit 1
}
if (-not (Test-Path $repotools))
{
    Write-Error "repo_tools not found at $repotools"
    exit 1
}

# Where the file lives here, the name to find it by, and WHICH TREE to find it in.
#
# THE TOOLS COME FROM repo_tools, NOT FROM ANOTHER CAPTAIN'S REPOSITORY. docs_check.py pointed into
# anchor_sift, so this tree's prose gate was whatever that repository last saved - and on 2026-09-11
# eight patterns arrived here without anyone on this side asking for them or knowing. That is not a
# shared file, it is one repository silently setting another's standard. Doug's rule is that every
# captain takes tools from repo_tools, so the source moves and the theory files, which really are
# shared subject matter rather than tooling, stay where they are.
$shared = @(
    @{ mine = "theory\preamble.tex";            name = "preamble.tex";    root = $anchor },
    @{ mine = "theory\macros.tex";              name = "macros.tex";      root = $anchor; under = "theory" },
    @{ mine = "theory\cryptography\macros.tex"; name = "macros.tex";      root = $anchor; under = "cryptography" },
    @{ mine = "tools\book\build_theory.sh";     name = "build_theory.sh"; root = $anchor },
    @{ mine = "tools\prose\docs_check.py";      name = "docs_check.py";   root = $repotools }
)

foreach ($one in $shared)
{
    # The tree this entry is sourced from. NOT named $anchor: it is anchor_sift for the theory files
    # and repo_tools for the tooling, and a name that says otherwise would be wrong half the time.
    $root = $one.root
    $rootName = Split-Path -Leaf $root
    $mine = Join-Path $here $one.mine

    $found = @(Get-ChildItem -Path $root -Filter $one.name -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "\\\.git\\" -and $_.FullName -notmatch "\\build\\" })

    # A hint narrows a name that legitimately appears more than once, such as the two macros files.
    if ($one.under)
    {
        $narrowed = @($found | Where-Object { $_.DirectoryName -match [regex]::Escape($one.under) })
        if ($one.under -eq "theory")
        {
            # The top-level one, not the subject copy beneath it.
            $narrowed = @($found | Where-Object { $_.DirectoryName -eq (Join-Path $root "theory") })
        }
        $found = $narrowed
    }

    if ($found.Count -eq 0)
    {
        Write-Host ("  skip  {0}  (no {1} in {2})" -f $one.mine, $one.name, $rootName) -ForegroundColor Yellow
        continue
    }
    if ($found.Count -gt 1)
    {
        Write-Host ("  STOP  {0}  matches {1} files in anchor_sift:" -f $one.name, $found.Count) -ForegroundColor Red
        $found | ForEach-Object { Write-Host ("          {0}" -f $_.FullName) }
        continue
    }

    $theirs = $found[0].FullName
    $item = Get-Item $mine -Force -ErrorAction SilentlyContinue

    if ($item -and $item.LinkType -eq "SymbolicLink")
    {
        if ($item.Target -eq $theirs)
        {
            Write-Host ("  ok    {0}" -f $one.mine) -ForegroundColor DarkGray
            continue
        }
        Write-Host ("  move  {0}  ->  {1}" -f $one.mine, $theirs) -ForegroundColor Cyan
        Remove-Item $mine -Force
    }
    elseif ($item)
    {
        # Refuse to replace a real file that has diverged. Linking would discard the local version
        # with no record of it, and a silent loss is worse than a stopped script.
        if ((Get-FileHash $mine -Algorithm SHA256).Hash -ne (Get-FileHash $theirs -Algorithm SHA256).Hash)
        {
            Write-Host ("  STOP  {0}  differs from anchor_sift; reconcile it first" -f $one.mine) -ForegroundColor Red
            continue
        }
        Remove-Item $mine -Force
    }

    $parent = Split-Path -Parent $mine
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    New-Item -ItemType SymbolicLink -Path $mine -Target $theirs | Out-Null

    # VERIFY IT RESOLVES, RATHER THAN REPORTING THAT IT WAS CREATED. A symlink to a path that does
    # not exist is created without complaint by Windows and by every other system, so "link" printed
    # in green has never meant the file is reachable - only that a link object now sits there.
    #
    # That gap is not hypothetical here. anchor_sift renamed maint\book to maint\tex_book and
    # tools\book\build_theory.sh dangled for a day, while REPRODUCE.md went on telling a reader to
    # run it. Nothing noticed until a scanner crashed opening it. The search above is what makes the
    # link survive a rename, but only once someone re-runs this; until then a stale link is the one
    # state this script cannot see and a reader hits first.
    if (-not (Test-Path -LiteralPath $mine))
    {
        Write-Host ("  BROKEN {0}  ->  {1}  (link created but does not resolve)" -f $one.mine, $theirs) -ForegroundColor Red
        $broken += 1
        continue
    }
    Write-Host ("  link  {0}  ->  {1}" -f $one.mine, $theirs) -ForegroundColor Green
}

# A dangling link found on the way IN is reported too, because the common case is that nothing here
# changed and this script simply has not been run since the other tree moved.
Write-Host ""
$dangling = 0
foreach ($one in $shared)
{
    $mine = Join-Path $here $one.mine
    $item = Get-Item $mine -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq "SymbolicLink" -and -not (Test-Path -LiteralPath $mine))
    {
        Write-Host ("  DANGLING  {0}  ->  {1}" -f $one.mine, $item.Target) -ForegroundColor Red
        $dangling += 1
    }
}

if ($broken -gt 0 -or $dangling -gt 0)
{
    Write-Host ("  {0} link(s) do not resolve." -f ($broken + $dangling)) -ForegroundColor Red
    exit 1
}
Write-Host "  every shared link resolves" -ForegroundColor Green

Write-Host ""
Write-Host "  done. Verify with: git -C `"$here`" status --short"
