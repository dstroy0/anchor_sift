# Self-reproduction, and a compiler that compiles itself

## Von Neumann's construction

The self-reproducing automaton of [von Neumann](#src:von-Neumann-1966) has three parts and a description. Given a description $\varphi(X)$ of any automaton $X$, a universal constructor $A$ builds $X$. A copier $B$ makes a copy of any description. A control $C$ has $B$ copy the description, has $A$ build from it, and ties the copy to what was built. With $X = A + B + C$, the automaton $(A + B + C) + \varphi(A + B + C)$ produces itself. The definition is not circular, because $A$ and $B$ are fixed before $X$ is chosen and $C$ is defined for any $X$. With an arbitrary part $D$ added to the description, each generation also builds $D$, and a change in the description of $D$ is inherited.

The description is copied in place of the machine because a description is passive. Copying a working automaton would mean examining it while it runs, and the examination would disturb it.

Burks completed the cellular form. Each cell of a square lattice holds one of 29 states: 16 transmission states, 4 confluent states, the unexcitable state and 8 sensitized states. Its next state is a function of its own state and its four nearest neighbors' states. Every signal is a single pulse, present or absent, and a cell's state carries $\log_2 29 \approx 4.86$ bits. With these pulses alone the structure can compute anything a Turing machine can, and its constructor can build any configuration of unexcited cells that its tape describes.

## A compiler that compiles itself

A compiler that compiles its own source to byte-identical output is a fixed point of a constructor applied to its own description. On a computer, copying a description is a memory copy, and the step with content is $A$, the compile.

The fixed point does not show that the source accounts for all of the compiler's behavior. A compiler that compiles itself can carry behavior that appears in no source, passed from one binary to the next, as [Thompson](#src:Thompson-1984) showed. Diverse double-compiling checks a compiler with a second, independent one. The independent compiler compiles the first compiler's source, the result compiles the same source again, and the output is compared bit for bit with the first compiler's own binary. If the source accounts for the binary, the two are identical, as [Wheeler](#src:Wheeler-2005) shows.

## Status

The engine's bootstrap test compiles its emitter, written as a record program, with the emitter itself, and compares the output byte for byte. It is not built, as the [engine workbook](#src:Quigg-engine-workbook) records. Passing it would show the fixed point, and a diverse double-compile would be needed to show the source accounts for the emitter.
