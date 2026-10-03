# Simulating a quantum circuit classically

## The cost

An OpenQASM program, in the language [Cross et al.](#src:OpenQASM-3) define, describes a circuit of gates and measurements on $n$ qubits. A classical simulator holds the state as $2^n$ complex amplitudes. A gate on one or two qubits updates every amplitude, in pairs or in groups of four, and costs $O(2^n)$ operations. A measurement returns an outcome with probability equal to the squared magnitude of its amplitude, and a simulator samples it with a random draw.

The exponential cost has exceptions. Circuits of Clifford gates are simulated in polynomial time in the stabilizer formalism, by the method of [Aaronson and Gottesman](#src:Aaronson-Gottesman-2004). States of little entanglement are held as matrix product states whose bond dimension is bounded by the entanglement across each cut, as [Vidal](#src:Vidal-2003) showed. Neither reaches a general circuit.

## A deterministic interpretation leaves the cost where it is

In the de Broglie–Bohm theory a measurement's outcome is fixed by the wave function and the initial positions of the particles, and no random draw is needed, in the theory as [Bohm](#src:Bohm-1952) set it out. The wave function that guides the particles is the same object of $2^n$ amplitudes, and computing it costs what the simulation above costs. In quantum equilibrium the initial positions are distributed as the squared magnitude of the wave function, and no observer can know them more finely, as [Dürr, Goldstein and Zanghì](#src:Durr-Goldstein-Zanghi-1992) showed. Outcomes are then predictable to exactly the probabilities a sampling simulator uses. In the many-worlds interpretation every outcome occurs on some branch, and there is no single bit string to return.

A deterministic interpretation changes the account of measurement. It does not change the cost of computing the amplitudes, or the statistics a run of the circuit produces.

## Status

The engine holds qubit states with every amplitude exact, in the field $\mathbb{Q}(\sqrt{2})[i]$, which contains the entries of the Clifford gates and the T gate. It holds them in two forms: the dense state of $2^n$ amplitudes, and a matrix product state whose bonds are cut to their exact rank, as the [engine workbook](#src:Quigg-engine-workbook) records. The test of such a simulator is agreement: with an independent floating-point simulator to that simulator's precision, and with a stabilizer simulator exactly on Clifford circuits.
