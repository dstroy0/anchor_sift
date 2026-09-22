# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The two commands that need a person. Everything else in this directory is keyless.
#
#     powershell -File maint\signing\sign.ps1
#
# WHAT THIS DOES AND WHAT IT REFUSES TO DO
#
# It signs one small file and anchors the signature. It never touches the passphrase: that goes to
# the gpg agent's own prompt and never through a file, an argument, an environment variable or a log.
# docs/provenance.md section 5 records three proposals for unattended signing and why each fails, and
# the short form is that a library able to decrypt its own key unattended ships whatever unlocks it.
#
# WHY BOTH COMMANDS, AND IN THIS ORDER
#
# The signature answers WHO and cannot answer WHEN, because its date field is written by the signer's
# own clock. The anchor answers WHEN and cannot answer WHO, because it needs no key and anyone can
# make one. Running one without the other leaves half the claim, and the order matters only in that
# the anchor is taken over the signature, so the signature has to exist first.
#
# THE ANCHOR DISCLOSES NOTHING. It is taken over a digest, which is the same size for a sentence or a
# corpus and names no file. Held work can be anchored today and revealed whenever. Waiting for
# publication to anchor is the expensive mistake, because every unanchored day is a day a competing
# claim can predate.

$ErrorActionPreference = "Stop"

$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifest = Join-Path $here "manifest.tsv"
$key      = "E603975E472D00FE"

if (-not (Test-Path $manifest))
{
    Write-Output "  no manifest at $manifest"
    Write-Output "  build one first:  python maint\signing\build_manifest.py"
    exit 1
}

# Refuse to sign a manifest that no longer describes the tree. A signature over a stale list is worse
# than no signature: it is a deliberate attestation to bytes that have since moved.
Write-Output "  checking the manifest still describes this tree"
$repo = Resolve-Path (Join-Path $here "..\..")
python (Join-Path $here "verify.py") --manifest $manifest --root $repo
$integrity = $LASTEXITCODE

# verify.py counts an absent signature and an absent anchor as findings, and on a first run both are
# absent by definition. Two findings with no CHANGED or MISSING lines above is the expected state
# here, so this asks rather than refusing outright.
if ($integrity -gt 2)
{
    Write-Output ""
    Write-Output "  the manifest does not match the tree. Rebuild it before signing:"
    Write-Output "      python maint\signing\build_manifest.py"
    exit 1
}

Write-Output ""
Write-Output "  signing $manifest with $key"
Write-Output "  gpg will prompt for the passphrase. Nothing here handles it."
gpg --detach-sign --armor --local-user $key $manifest

if ($LASTEXITCODE -ne 0)
{
    Write-Output "  gpg refused. Nothing was signed and nothing was anchored."
    exit 1
}

Write-Output "  signed: $manifest.asc"
Write-Output ""

$ots = Get-Command ots -ErrorAction SilentlyContinue
if (-not $ots)
{
    Write-Output "  ots is not installed, so the signature is NOT anchored and priority is not"
    Write-Output "  established. Authorship is. Install and run:"
    Write-Output "      pip install opentimestamps-client"
    Write-Output "      ots stamp $manifest.asc"
    exit 1
}

Write-Output "  anchoring the signature"
ots stamp "$manifest.asc"

if ($LASTEXITCODE -ne 0)
{
    Write-Output "  ots refused. The signature stands and the anchor does not."
    exit 1
}

Write-Output ""
Write-Output "  done. Three files now carry the claim:"
Write-Output "      manifest.tsv        the digests, keep private while the work is held"
Write-Output "      manifest.tsv.asc    who, verifiable against the published public key"
Write-Output "      manifest.tsv.asc.ots  when, verifiable against any full node"
Write-Output ""
Write-Output "  The proof needs a confirmation before it verifies, which takes a few hours."
Write-Output "  Upgrade it later with:  ots upgrade $manifest.asc.ots"
