# Constants

**Purpose:** Get a natural constant to any precision you ask for, computed on the spot and checked by two independent routes, with nothing stored.
**Scope:** `src/engine/python/representation/constants/`

A natural constant is not an oracle. The engine's oracle boundary holds the answers a sample cannot supply on its own, published cell edges and bond lengths and language trees, facts from outside. Pi is not one of those. It is derivable from within to any depth, and it is derived here and not tabled. Storing a thousand digits of pi and comparing against them is the oracle move on a value that needs no oracle, and it caps the constant at the length someone pasted. This module computes instead.

## The two-route rule

Every public function computes its constant by two independent routes and returns the value only when they agree at the requested precision. That agreement is the positive control, run on every call. A route with a bug, or a series stopped one term too early, disagrees with the other and raises instead of handing back a wrong digit. The matching check is the two derivations meeting, and never a pasted expansion.

| constant     | function       | route one                                  | route two                                        |
| ------------ | -------------- | ------------------------------------------ | ------------------------------------------------ |
| pi           | `pi`           | Machin, `16 arctan(1/5) - 4 arctan(1/239)` | Euler, `4 (arctan(1/2) + arctan(1/3))`           |
| e            | `euler_e`      | the Taylor series of `1/k!`                | the continued fraction `[2; 1, 2, 1, 1, 4, ...]` |
| sqrt(2)      | `root_two`     | integer Newton square root                 | the continued fraction `[1; 2, 2, 2, ...]`       |
| ln(2)        | `ln_two`       | the series `sum 1/(k 2^k)`                 | `2 artanh(1/3)`                                  |
| golden ratio | `golden_ratio` | `(1 + sqrt 5)/2`                           | the ratio of consecutive Fibonacci numbers       |

The drawn null is in `evidence/proofs/posits/proof_constants_two_routes.py` (PRF-x-015): a Machin identity with one coefficient wrong is fed in, and the two-route check raises on it. That posit aladds a third route where an algebraic identity supplies one, `sqrt(2)^2` bracketing 2 and `phi^2 = phi + 1`, both independent of the series.

## The integer form, and the precision knob

Each function takes the number of decimal places `n` and returns `floor(C * 10**n)` as an exact Python integer. No float ever appears. There is no ceiling on `n`: the series and the recurrences run to whatever scale is asked, and the caller pins the constant as far as it cares to wait. Twenty guard digits are computed past `n` and dropped, keeping the last returned digit clear of a truncation artifact.

```python
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.constants.naturals import pi, root_two

pi(50)          # 314159265358979323846264338327950288419716939937510, i.e. floor(pi * 10**50)
root_two(1000)  # sqrt(2) to a thousand places, as one integer
```

A display at a fixed width is the caller's boundary, taken from this integer. A camera turn table scaled to a power of two, for instance, computes each angle's sine to high precision here and takes the integer at the scale it renders at. That quantization is the display step and stores nothing.

## The command line

`python src/engine/python/representation/constants/naturals.py --places <n> [name ...]` prints the named constants to `n` places, or all five when none is named.

```
python src/engine/python/representation/constants/naturals.py --places 200 pi e
```

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-17
