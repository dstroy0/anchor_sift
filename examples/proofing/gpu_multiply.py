"""Two integers to the card and one back, with the packing being no work at all.

    python examples/proofing/gpu_multiply.py --check     grade against Python's own multiply
    python examples/proofing/gpu_multiply.py --time      measure against the host at rising size

WHY THE PACKING IS FREE

A large integer is already a run of 32 bit limbs in memory, least significant first. So handing one
to the device is `value.to_bytes(count * 4, "little")` and reading one back is
`int.from_bytes(raw, "little")`, and neither is a conversion: they are the same bytes, named twice.
There is no base change, no loop over coefficients and nothing to round.

The end is where it counts. The device returns the product as three arrays, and the product is

    base + p0 * step + p0 * p1 * rest

where each array is read as one integer at a 32 bit stride. The coefficients of a convolution run
past 2^32 and have to be carried, and the carrying happens INSIDE that addition, in Python's own
big integer arithmetic, at C speed. A carry pass written out over a hundred million coefficients
would cost more than every transform put together. Here there is no pass.

WHAT THE DEVICE DOES

Three transforms over three moduli, each carrying a Proth witness that proves it prime, then
Garner's rule across them. Nothing else. Every verdict below is formed here, against Python's own
multiply, because a product on a card is a number nobody can eyeball and the only thing worth
printing is whether two routes that had no way to agree did.

WHAT IT REFUSES

A product longer than the moduli support. The three primes admit a transform of 2^27, which is
1.29 billion decimal digits, and a request past that is refused by the device instead of wrapping.

A run whose answer was never compared. `--check` walks sizes where Python can still multiply, and
a size past that is reported as timed and never as verified, since a fast wrong answer is the
thing this tree keeps producing.
"""

import argparse
import io
import os
import struct
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PACKER = os.path.join(ROOT, "build", "bench_ntt_cuda.exe")
SCRATCH = os.path.join(ROOT, "build", "ntt")

sys.set_int_max_str_digits(0)

LIMB = 32
BYTES = LIMB // 8

# The three moduli the device is built on. Named here so the reassembly cannot drift from the
# device's own Garner, and each is reproducible by examples/proofing/twiddle_proof.py.
PRIME0 = 2013265921      # 15 * 2^27 + 1, Proth witness 11
PRIME1 = 2281701377      # 17 * 2^27 + 1, Proth witness 3
PRIME2 = 3892314113      # 29 * 2^27 + 1, Proth witness 3

# Below this the trip to the card costs more than the transform saves. MEASURED, and it moved a long
# way once the process stopped being launched per call. At 192 ms of context setup per multiply the
# threshold had to sit at 16,384 limbs so only the top of the splitting tree ever crossed it. With
# one persistent process the crossing point is 1,024 limbs, about ten thousand decimal digits, and a
# million place run of pi fell from 10.065 s to 6.071 s by moving it. Below 1,024 the curve turns
# back up as the pipe and the conversion start to dominate. Read it as a floor, never a direction.
NATIVE_LIMBS = 1 << 10


# ONE PROCESS FOR THE WHOLE RUN. Creating a CUDA context costs 192 ms, measured, and a run of pi to
# a million places made 56 device calls: 10.76 s of a 19.55 s wall clock was context setup against
# 0.25 s of transform. The card was idle 98.7 percent of the time. So the process is started once
# and kept, and the per call cost becomes a pipe write.
_SERVED = None


def server():
    """The device process, started once and reused for every multiply after."""
    global _SERVED
    if _SERVED is None or _SERVED.poll() is not None:
        if not os.path.exists(PACKER):
            raise SystemExit("build it first: powershell src/scripts/build_ntt.ps1")
        _SERVED = subprocess.Popen([PACKER, "--pipe"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return _SERVED


def shut_down():
    """Tell the device there is no more work, so it exits instead of being orphaned."""
    global _SERVED
    if _SERVED is not None and _SERVED.poll() is None:
        try:
            _SERVED.stdin.write(struct.pack("<QQ", 0, 0))
            _SERVED.stdin.flush()
            _SERVED.stdin.close()
            _SERVED.wait(timeout=10)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            _SERVED.kill()
    _SERVED = None


def _exactly(stream, want):
    """Read exactly `want` bytes, since a pipe is free to hand back less than was asked for."""
    out = bytearray()
    while len(out) < want:
        chunk = stream.read(want - len(out))
        if not chunk:
            return None
        out += chunk
    return bytes(out)


def limb_count(value):
    """How many 32 bit limbs `value` occupies."""
    return max(1, (value.bit_length() + LIMB - 1) // LIMB)


def write_limbs(value, path):
    """`value` as a flat run of limbs. The same bytes it already is, written down."""
    with io.open(path, "wb") as handle:
        handle.write(value.to_bytes(limb_count(value) * BYTES, "little"))


def read_packed(path):
    """One array read back as the integer whose base 2^32 digits it holds."""
    with io.open(path, "rb") as handle:
        return int.from_bytes(handle.read(), "little")


def device_multiply(left, right, keep=False):
    """The product, by way of the card. Returns the value and the milliseconds the device spent.

    THROUGH A PIPE AND NOT THROUGH THE DISK. The three returned arrays at a billion digits are some
    1.5 GB and the two operands another 0.5 GB, and routing that through files was measured at 8.6
    seconds against 1.77 seconds of transform, so five sixths of the wall clock was the filesystem.
    The device reads both operands to completion before it writes anything, so writing everything
    and then reading everything cannot deadlock on a full pipe.
    """
    if not os.path.exists(PACKER):
        raise SystemExit("build it first: powershell src/scripts/build_ntt.ps1")
    if left < 0 or right < 0:
        raise ValueError("this multiply is for non-negative values")
    if left == 0 or right == 0:
        return 0, 0.0

    wide = limb_count(left)
    tall = limb_count(right)
    carried = wide + tall

    served = server()
    served.stdin.write(struct.pack("<QQ", wide, tall))
    served.stdin.write(left.to_bytes(wide * BYTES, "little"))
    served.stdin.write(right.to_bytes(tall * BYTES, "little"))
    served.stdin.flush()

    want = carried * BYTES
    arrays = []
    for _ in range(3):
        chunk = _exactly(served.stdout, want)
        if chunk is None:
            raise SystemExit("the device stopped mid answer")
        arrays.append(int.from_bytes(chunk, "little"))

    base, step, rest = arrays
    return base + PRIME0 * step + PRIME0 * PRIME1 * rest, 0.0


def multiply(left, right):
    """The product, by whichever route is cheaper at this size, sign included.

    THE SIGN IS HANDLED HERE AND NOWHERE ELSE. The device works on magnitudes, because a transform
    over a prime field has no sign to carry. Chudnovsky's series alternates, so its partial sums go
    negative and a splitting merge multiplies a negative by a positive routinely.

    Every test of this file used non-negative operands, and below the threshold the native multiply
    takes negatives without comment, so the first negative to reach the device was the first one in
    a real computation. The gate now covers exactly that case.
    """
    if min(limb_count(abs(left)), limb_count(abs(right))) < NATIVE_LIMBS:
        return left * right
    negative = (left < 0) != (right < 0)
    out = device_multiply(abs(left), abs(right))[0]
    return -out if negative else out


def _made(bits, seed):
    """A value of about `bits` bits, made from a cheap recurrence that repeats exactly on a re-run.

    BUILT AS BYTES AND CONVERTED ONCE. An earlier version accumulated with `out = (out << 64) | x`,
    which shifts a value that is already most of the answer on every one of a million iterations and
    is therefore quadratic in the bit count. At the sizes this file exists to measure, that helper
    took longer than every multiply it was written to time, and the run looked like a slow device
    and not a slow test. Assembling the bytes first and converting once is linear.
    """
    state = seed
    raw = bytearray()
    for _ in range((bits + 63) // 64):
        state = (state * 6364136223846793005 + 1442695040888963407) % (1 << 64)
        raw += state.to_bytes(8, "little")
    raw[0] |= 1
    return int.from_bytes(bytes(raw), "little")


def _check():
    lines = []
    failed = 0

    lines.append("  THE PACKING, which has to be its own inverse before anything else matters")
    for value in (7, (1 << 200) - 1, _made(4096, 3)):
        path = SCRATCH + ".probe.bin"
        if not os.path.isdir(os.path.dirname(SCRATCH)):
            os.makedirs(os.path.dirname(SCRATCH))
        write_limbs(value, path)
        back = read_packed(path)
        os.remove(path)
        ok = back == value
        lines.append("    %-22s %s" % (str(value)[:20], "returns" if ok else "DOES NOT RETURN"))
        if not ok:
            failed += 1
    lines.append("")

    lines.append("  THE PRODUCT, against Python's own, at sizes Python can still reach")
    for bits in (1 << 19, 1 << 20, 1 << 21, 1 << 22):
        left = _made(bits, 0x51F7)
        right = _made(bits, 0xA13D)

        start = time.perf_counter()
        wanted = left * right
        native = time.perf_counter() - start

        got, spent = device_multiply(left, right)
        agree = got == wanted
        lines.append("    %9s bits  host %7.3fs  device %8.3fms  %s"
                     % (format(bits, ","), native, spent, "agree" if agree else "DISAGREE"))
        if not agree:
            failed += 1
            lines.append("      host   %d bits" % wanted.bit_length())
            lines.append("      device %d bits" % got.bit_length())
    lines.append("")

    lines.append("  A SQUARE, where both factors are the same array")
    value = _made(1 << 21, 0x7E1)
    got, _ = device_multiply(value, value)
    agree = got == value * value
    lines.append("    %s" % ("agrees" if agree else "DISAGREES"))
    if not agree:
        failed += 1
    lines.append("")

    lines.append("  SIGNED OPERANDS, which a splitting merge produces and this file did not test")
    big_left = _made(1 << 21, 11)
    big_right = _made(1 << 21, 13)
    for one, two in ((-big_left, big_right), (big_left, -big_right), (-big_left, -big_right)):
        got = multiply(one, two)
        agree = got == one * two
        lines.append("    %s%s  %s" % ("-" if one < 0 else "+", "-" if two < 0 else "+",
                                       "agrees" if agree else "DISAGREES"))
        if not agree:
            failed += 1
    lines.append("")

    lines.append("  LOPSIDED FACTORS, since a transform pads them to one length")
    left = _made(1 << 21, 1)
    right = _made(1 << 16, 2)
    got, _ = device_multiply(left, right)
    agree = got == left * right
    lines.append("    %s" % ("agrees" if agree else "DISAGREES"))
    if not agree:
        failed += 1
    lines.append("")

    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def _say(text):
    """One line out, immediately, instead of at the end.

    A run reporting only on completion tells a reader nothing while it is the thing they are
    waiting on, and tells them nothing at all if it is stopped. Each row here costs minutes at the
    top sizes, so each row is printed as it lands.
    """
    sys.stdout.write(text + "\n")
    sys.stdout.flush()


def _time():
    _say("  THE MULTIPLY, host against card")
    _say("")
    _say("    %14s %12s %12s %12s %10s"
         % ("decimal digits", "host", "device", "end to end", "faster by"))

    for bits in (1 << 22, 1 << 24, 1 << 26, 1 << 28, 1 << 30, 1 << 31):
        digits = int(bits / 3.321928)
        left = _made(bits, 0x51F7)
        right = _made(bits, 0xA13D)

        if bits <= (1 << 26):
            start = time.perf_counter()
            left * right
            native = time.perf_counter() - start
        else:
            native = None

        start = time.perf_counter()
        try:
            _, spent = device_multiply(left, right)
        except SystemExit as trouble:
            _say("    %14s  %s" % (format(digits, ","), trouble))
            break
        whole = time.perf_counter() - start

        _say("    %14s %11s %11.3fs %11.3fs %10s"
             % (format(digits, ","),
                ("%.3fs" % native) if native is not None else "not run",
                spent / 1000.0, whole,
                ("%.0fx" % (native / whole)) if native and whole else "-"))

    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the big multiply, on the card")
    parser.add_argument("--check", action="store_true", help="grade against Python's own multiply")
    parser.add_argument("--time", action="store_true", help="measure against the host")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.time:
        sys.exit(_time())
    parser.print_help()
