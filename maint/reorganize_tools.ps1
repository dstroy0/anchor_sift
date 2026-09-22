# Sorts tools into subdirectories by what each file does.
#
#   pwsh -File tools\maint\reorganize_tools.ps1 [-DryRun]
#
# The same job reorganize_src.ps1 did for src, and for the same reason: forty loose files in one
# directory is a list to read, not a structure to navigate.
#
# NAMES DO NOT CHANGE, ONLY PATHS
#
# check_slant.py becomes check\check_slant.py and keeps its name. The repetition is deliberate.
# Every document, every printf inside a bench, and every usage line in a docstring names these files,
# so a rename means finding all of those and being right every time. Inserting one directory level
# means the filename is still the search key. A previous mechanical rewrite in this tree corrupted a
# filename by matching a fragment of it; matching on the whole name cannot do that.
#
# WHAT DOES NOT MOVE
#
# book and prose already exist and hold symlinks into anchor_sift. book\build_theory.sh derives the
# repository root with dirname "$0"/../.., which is only correct at exactly that depth, so moving it
# deeper would break it silently. Both stay where they are.

param([switch]$DryRun)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root "tools"

# What each file is, which is the only thing that decides where it goes.
$sorting = @{
    "view" = @(
        "build_shadow_view.py", "build_sources_view.py", "build_step_view.py",
        "build_voxel_view.py", "make_shadow_figure.py",
        "shadow_view_template.html", "sources_view_template.html",
        "step_view_template.html", "voxel_view_template.html",
        # The generated pages travel with their generators, which write beside themselves. Left
        # behind they would be stale copies of a file that now appears somewhere else.
        "shadow_view.html", "sources_view.html", "step_view.html", "voxel_view.html"
    )
    "check" = @(
        "check_monotone.py", "check_ridge_common_mode.py", "check_rotation_residues.py",
        "check_slant.py", "check_tilt.py", "check_two_sources.py",
        "check_word_collapse.py", "check_word_pairs.py", "language_of_nature.py"
    )
    "radar" = @("radar_assay.py", "radar_receive.py", "sei_round_constants.py")
    "audit" = @(
        "audit_compiler.ps1", "audit_constants.py", "audit_diff.py", "audit_seeds.ps1",
        "audit_seeds.py", "conserve_headers.py", "sweep_phase.ps1", "sweep_phase.py",
        "verify_renyi.py"
    )
    "hardware" = @("batch_invariant.py", "compressor_test.py")
    "chain" = @("fetch_blocks.py", "blocks.json")
    "book" = @("build_bibliography.py")
    "maint" = @("link_shared.ps1", "link_viz.ps1", "reorganize_src.ps1")
}

Push-Location $root
try
{
    foreach ($bucket in ($sorting.Keys | Sort-Object))
    {
        $into = Join-Path $tools $bucket
        if (-not (Test-Path $into))
        {
            if ($DryRun) { Write-Host "would create tools\$bucket" }
            else { New-Item -ItemType Directory -Path $into | Out-Null }
        }

        foreach ($name in $sorting[$bucket])
        {
            $from = Join-Path $tools $name
            if (-not (Test-Path $from))
            {
                # Already moved, or never existed. Either way there is nothing to do and saying so
                # is more useful than failing on a second run.
                Write-Host "  skip    $name (not in tools root)"
                continue
            }

            $to = Join-Path $into $name
            if ($DryRun)
            {
                Write-Host "  would move $name -> $bucket\"
                continue
            }

            # git mv keeps the file's history attached. An ignored file such as blocks.json is not
            # tracked, so git refuses it and a plain move is correct there.
            git ls-files --error-unmatch $from 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0)
            {
                git mv $from $to
                Write-Host "  git mv  $name -> $bucket\"
            }
            else
            {
                Move-Item $from $to
                Write-Host "  move    $name -> $bucket\  (untracked)"
            }
        }
    }
}
finally
{
    Pop-Location
}

$left = @(Get-ChildItem -Path $tools -File | Where-Object { $_.Name -ne "README.md" })
if ($left.Count -gt 0)
{
    Write-Host ""
    Write-Host "still loose in tools root:"
    foreach ($one in $left) { Write-Host "  $($one.Name)" }
}
