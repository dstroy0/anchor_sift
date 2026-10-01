#!/usr/bin/env python3
# PQC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Whether a segwit payout address is well formed: checksum, witness version and program length.

    python tools/chain/address_check.py --check              the controls, each able to fail
    python tools/chain/address_check.py bc1q... [bc1q...]    exit 0 when every address verifies

WHY VALIDITY AND NOT EQUALITY. The payout wallet is hierarchical, a new receive address is the
expected case and comparing against a stored one flags nothing but rotation. What a typo breaks is the
checksum, and that is what this reads.

TWO CONSTANTS. Witness version 0 is checksummed as bech32, constant 1. Version 1 and above use
bech32m, constant 0x2bc830a3. Checking against the wrong constant for the version accepts an address
no wallet would pay, so the constant is chosen from the version the address itself carries.

This reads the string only. It does not ask the network whether the address has been paid, and a
well formed address can still belong to somebody else.
"""

import sys

CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
GENERATOR = (0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)
BECH32 = 1
BECH32M = 0x2BC830A3
NETWORKS = {"bc": "mainnet", "tb": "testnet"}


def polymod(values):
    """The BCH checksum register over five bit groups."""
    register = 1
    for value in values:
        top = register >> 25
        register = ((register & 0x1FFFFFF) << 5) ^ value
        for index in range(5):
            if (top >> index) & 1:
                register ^= GENERATOR[index]
    return register


def expand_prefix(prefix):
    return [ord(letter) >> 5 for letter in prefix] + [0] + [ord(letter) & 31 for letter in prefix]


def regroup(groups):
    """Five bit groups to bytes, refusing padding that is too long or not zero."""
    accumulator = 0
    bits = 0
    out = []
    for group in groups:
        accumulator = (accumulator << 5) | group
        bits += 5
        while bits >= 8:
            bits -= 8
            out.append((accumulator >> bits) & 0xFF)
    if bits >= 5 or (accumulator & ((1 << bits) - 1)):
        return None
    return bytes(out)


def read_address(address):
    """(network, witness version, program bytes, encoding name), or (None, reason)."""
    if address != address.lower() and address != address.upper():
        return None, "mixed case"
    if len(address) > 90:
        return None, "longer than 90 characters"
    text = address.lower()
    split = text.rfind("1")
    if split < 1 or split + 7 > len(text):
        return None, "no separator, or fewer than six checksum characters after it"
    prefix = text[:split]
    if prefix not in NETWORKS:
        return None, "prefix %r is not a Bitcoin network" % prefix
    if any(letter not in CHARSET for letter in text[split + 1:]):
        return None, "a character outside the bech32 alphabet"
    groups = [CHARSET.find(letter) for letter in text[split + 1:]]
    version = groups[0]
    if version > 16:
        return None, "witness version %d is above 16" % version
    constant = BECH32 if version == 0 else BECH32M
    if polymod(expand_prefix(prefix) + groups) != constant:
        return None, "checksum does not verify as %s" % ("bech32" if version == 0 else "bech32m")
    program = regroup(groups[1:-6])
    if program is None:
        return None, "program padding is malformed"
    if not 2 <= len(program) <= 40:
        return None, "program of %d bytes is outside 2 to 40" % len(program)
    if version == 0 and len(program) not in (20, 32):
        return None, "version 0 program of %d bytes is neither 20 nor 32" % len(program)
    return (NETWORKS[prefix], version, program, "bech32" if version == 0 else "bech32m"), None


def kind(version, program):
    if version == 0:
        return "P2WPKH" if len(program) == 20 else "P2WSH"
    if version == 1 and len(program) == 32:
        return "P2TR"
    return "witness v%d" % version


def corrupted(address, at):
    """The address with one checksummed character replaced by the next letter of the alphabet."""
    letter = address[at].lower()
    swapped = CHARSET[(CHARSET.find(letter) + 1) % len(CHARSET)]
    return address[:at] + swapped + address[at + 1:]


def _check():
    failed = 0
    # Published vectors, one for each constant: BIP-173 for version 0, BIP-350 for version 1.
    accepted = ("BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4",
                "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0")
    for address in accepted:
        found, reason = read_address(address)
        print("  published vector %s: %s" % (address, "verifies" if found else "REFUSED, " + reason))
        if found is None:
            failed += 1
            continue
        # A checker that has never refused anything has not been shown to refuse. Every data
        # character, one at a time, moved to another letter: a BCH code of this length detects every
        # single substitution, so every one of these must be refused.
        split = address.lower().rfind("1")
        slipped = [at for at in range(split + 1, len(address)) if read_address(corrupted(address, at))[0]]
        total = len(address) - split - 1
        print("    %d single character substitutions, %d wrongly accepted" % (total, len(slipped)))
        if slipped:
            failed += 1
    # The wrong constant for the version: a version 1 address re-checksummed as bech32 must fail.
    text = accepted[1]
    split = text.rfind("1")
    groups = [CHARSET.find(letter) for letter in text[split + 1:-6]]
    register = polymod(expand_prefix("bc") + groups + [0] * 6) ^ BECH32
    tail = "".join(CHARSET[(register >> 5 * (5 - index)) & 31] for index in range(6))
    wrong = text[:-6] + tail
    refused = read_address(wrong)[0] is None
    print("  version 1 address carrying a bech32 checksum instead of bech32m: %s"
          % ("refused" if refused else "WRONGLY ACCEPTED"))
    if not refused:
        failed += 1
    print("")
    print("%d check(s) failed" % failed)
    return failed


def main(argv):
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 0
    if "--check" in argv:
        return 1 if _check() else 0
    addresses = [argument for argument in argv if not argument.startswith("-")]
    if not addresses:
        sys.stderr.write("name at least one address, or --check\n")
        return 2
    bad = 0
    for address in addresses:
        found, reason = read_address(address)
        if found is None:
            print("%s  REFUSED: %s" % (address, reason))
            bad += 1
            continue
        network, version, program, encoding = found
        print("%s  verifies: %s, %s, witness v%d, %d byte program, %s"
              % (address, network, kind(version, program), version, len(program), encoding))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
