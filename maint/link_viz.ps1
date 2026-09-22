# Points anchor_sift's examples/00_blob_viz_tools at this repository's view tools.
#
#   Run elevated:  Start-Process pwsh -Verb RunAs -ArgumentList "-File","tools\maint\link_viz.ps1"
#
# Windows refuses symlink creation to an unelevated process unless Developer Mode is on, which is
# why this is a separate script and not a line in a build. It is the same reason link_shared.ps1
# stands on its own.
#
# THE TARGET IS tools\view AND NOTHING ABOVE IT
#
# The first version of this linked the whole tools directory, which put the compiler audits, the
# chain fetcher, the radar chain and the maintenance scripts inside a directory named for
# visualization in another repository. Only the viewers belong over there. A link one level too high
# is not a tidiness problem, it is fifty unrelated files appearing somewhere nobody asked for them.
#
# WHICH WAY THE LINK POINTS
#
# link_shared.ps1 runs the other direction: shared book and prose files live in anchor_sift and are
# linked into here. This one is the reverse, because the viewers were written here and anchor_sift
# is the consumer. One directory link rather than a file each, so a viewer added to view later
# appears over there without anyone re-running this.
#
# WHY THE TARGET IS RELATIVE
#
# An absolute target would bake this machine's home directory, and the private repository's name and
# location, into a file inside a public tree. The relative form carries only the two repositories'
# positions with respect to each other. It survives moving git_project and it names no owner.
#
# WHAT THIS COSTS
#
# The link resolves only where both trees are checked out side by side under git_project. Anywhere
# else it dangles. That is the intended compartmentalization: the tools stay in the private
# repository and the public one holds a pointer that resolves for someone who already has both.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root "tools"
$anchor = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $root))) "anchor_sift"

if (-not (Test-Path $anchor))
{
    Write-Error "anchor_sift not found at $anchor"
    exit 1
}

$holder = Join-Path $anchor "examples\00_blob_viz_tools"
if (-not (Test-Path $holder))
{
    New-Item -ItemType Directory -Path $holder | Out-Null
    Write-Host "created $holder"
}

# The earlier link was named for the whole tools directory. Remove it by name so an upgrade from
# that version does not leave the over-broad link in place beside the correct one.
$stale = Join-Path $holder "tools"
if (Test-Path $stale)
{
    $was = Get-Item $stale -Force
    if ($was.LinkType)
    {
        Remove-Item $stale -Force
        Write-Host "removed the previous link to the whole tools directory"
    }
    else
    {
        Write-Error "$stale is a real directory, not a link. Move it aside first."
        exit 1
    }
}

$link = Join-Path $holder "view"

# Replace a link, never a directory. A real directory here means someone put something at this name
# on purpose, and deleting it to make room is not this script's decision to make.
if (Test-Path $link)
{
    $existing = Get-Item $link -Force
    if (-not $existing.LinkType)
    {
        Write-Error "$link is a real directory, not a link. Move it aside first."
        exit 1
    }
    Remove-Item $link -Force
    Write-Host "replaced the existing link"
}

# New-Item resolves a relative target against the working directory rather than against the link, so
# the working directory has to be the link's own folder for the stored path to mean what it reads.
Push-Location $holder
try
{
    $relative = Resolve-Path -Relative (Join-Path $tools "view")
    New-Item -ItemType SymbolicLink -Path "view" -Target $relative | Out-Null
    Write-Host "linked view -> $relative"
}
finally
{
    Pop-Location
}

$check = Join-Path $link "build_step_view.py"
if (Test-Path $check)
{
    Write-Host "resolves: build_step_view.py is readable through the link"
}
else
{
    Write-Error "the link was created but does not resolve"
    exit 1
}
