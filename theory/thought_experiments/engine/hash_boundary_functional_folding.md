# The boundary functional of a hash keyspace, and folding

## The question

What would the boundary functional be for a given hash, with at most a 30 digit 0-9a-fA-F keyspace?

## 1. The scale of a 30 digit hex keyspace

A 30 digit string using characters 0-9 and a-f (or A-F) operates in base 16. Each hex digit represents 4 bits of information.

- **Cardinality:** a 30 digit hex string yields a keyspace of $16^{30} = (2^4)^{30} = 2^{120}$ possible values.
- **Comparison:** smaller than SHA-256's native output ($2^{256}$), a $2^{120}$ keyspace is still vast, roughly $1.32 \times 10^{36}$ combinations. Even at trillions of evaluations per second, the space remains physically bounded.

## 2. The boundary functional Φ

The boundary functional is the characteristic function that defines the exact edge between a failed search and a hit (the "floor"). It maps a hash output $x$ in the $2^{120}$ space to a binary decision or a distance. With $T$ the target threshold:

$$\Phi(x) = \begin{cases} 1 & \text{if } x < T \\ 0 & \text{if } x \ge T \end{cases}$$

Or, as a measure of how close a search came to the boundary:

$$\Phi(x) = |x - T|$$

## 3. The boundary functional in a single cycle sweep

- **Simultaneous evaluation:** the grid computes the hash for every nonce in the array concurrently, producing a vector of outputs $[x_1, x_2, \ldots, x_N]$.
- **Parallel functional application:** $\Phi$ is applied to every element at once.
- **The latch (the floor):** a reduction tree, or a recursive fold, scans the resulting binary vector; the first 1 trips the latch and locks that index as the floor of the search.

Within a 30 digit hex keyspace ($2^{120}$ states) the boundary functional is the threshold condition, $\Phi(x) = 1$ when $x < T$, whether it is evaluated sequentially through a tower recursion or across a spatial array at once.

## 4. Folding: even with a leading 80 required, there is no dimensional restriction

Folding schemes (Nova, SuperNova, HyperNova) remove the growth that recursion otherwise causes in verifiable computation.

- **Deferred verification:** instead of proving the inner logic recursively at every step, a folding scheme defers the expensive final check.
- **Instance compression:** two constraint satisfaction instances (step $i$ and step $i+1$) fold into one instance of the same size.
- **Constant circuit size:** whether 10 nonces or $10^{10}$ are folded, the verification circuit stays the same size.

With a severe boundary condition, such as a long required prefix:

- **The stream:** the nonces are processed as a continuous stream.
- **The accumulator:** the folding scheme compresses the running state into a compact vector.
- **The final argument:** one succinct argument at the end proves that the accumulated trace satisfied the boundary functional.
