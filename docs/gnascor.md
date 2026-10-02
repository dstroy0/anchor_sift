# The language: gnascor

**Purpose:** Say what gnascor is, what the query protocol asks, and where the transpiler keeps each piece.
**Scope:** `src/c/transpiler/`, `src/cu/transpiler/`

The objective is to compile a program written in gnascor to any language, including one nobody has met, and prove it is the same program everywhere. Where the language is unknown, the engine derives it by asking. [gnascor.md](https://github.com/dstroy0/orior/blob/main/src/c/transpiler/gnascor.md) holds the language part by part, and [engine_plan.md](https://github.com/dstroy0/orior/blob/main/src/engine_plan.md) the open work.

**gnascor** is the internal language, `.g` high order and `.gsm` its assembly. It is designed and it is what a program is written in. It is not derived and its vocabulary does not move. **`L*`** is the map from gnascor to a target's spellings, and it is the derived part.

**Information is coherence.** A description at its Kolmogorov complexity holds no redundancy, every bit of it carries, and no part predicts another. A system at coherence has that property from the other side: its parts agree and the friction between them is at its floor. Compression and coherence are one measurement from two directions.

What is known before meeting anything is relations. `1,1 -> 2` is a relation and is not an addition, because addition is a spelling. Every system that computes agrees about the relation and each spells it its own way.

## The query protocol

The query protocol is the form every ask takes, and it is what derivation is made of:

    [ ADDRESS ] -> ( QUALIFIER ) -> [ MEASURED COST ] -> BINARY RESULT (1 or 0)

The address names the target: a memory address, a URI, an API endpoint, an LLM context key, a register. The qualifier is a binary question asked at it, phrased to demand a state validation and never a data payload. The cost bound is the most the target may spend to answer, and no hand writes that field. An ask carrying no bound returns the cost instead of a bit. The spread of those costs is the baseline, and every bound after that is expressed against it.

**Gate, then rank. Never one score.** A relation holds or it does not, and that answer carries no noise. A cost is measured and every cost carries noise. The gate decides which candidates are admissible and the rank orders whatever survives, and the two are never added together. [query_protocol_table.md](https://github.com/dstroy0/orior/blob/main/theory/workbooks/engine/query_protocol_table.md) holds the protocol step by step.

Two branches resolve to a pair, and the pair to a four-letter mnemonic:

| left branch | right branch | pair state | mnemonic | meaning                                                     |
| ----------- | ------------ | ---------- | -------- | ----------------------------------------------------------- |
| LEAD (1)    | VOID (0)     | 1, 0       | CORE     | The primary intent persists; the secondary path dissolved.  |
| RITE (0)    | LEAD (1)     | 0, 1       | SHIFT    | Focus has migrated from the left domain to the right.       |
| DUAL (2)    | VOID (0)     | 2, 0       | ECHO     | An amplified state is sustained without new external input. |
| DUAL (2)    | DUAL (2)     | 2, 2       | NEXUS    | Maximum systemic coherence; both major systems are aligned. |

## The transpiler

The transpiler is the record machine's programs written for a part, and the asks that learn the part. `keymath` imprints record programs, `key_schedule` lays them out, and `cycle` runs them on the device with a host reference. The code generator writes each program's lane from a ruleset, one `.krs` a language, and every lane the device writes is held word for word against the host's.

| directory                                                                                                  | what it holds                                                                                                                                                       |
| ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`src/c/transpiler/bootstrap/`](https://github.com/dstroy0/orior/tree/main/src/c/transpiler/bootstrap)     | the query protocol on the host: one ask (`query_ask`), every arrangement of primitives that produces a relation (`chain_build`), and the order of asks (`ask_order`) |
| [`src/cu/transpiler/codegen/`](https://github.com/dstroy0/orior/tree/main/src/cu/transpiler/codegen)       | the code generator's kernels, and its rulesets: `c.krs`, `ptx.krs`, `sass.krs`, `vhdl.krs` and `yosys.krs`                                                          |
| [`src/c/transpiler/cubin/`](https://github.com/dstroy0/orior/tree/main/src/c/transpiler/cubin)             | one line of SASS turned into the sixteen bytes the part runs, and a cubin written from a kernel's machine code; `machines/sm_86.kdm` and `sm_86.ksc`                  |
| [`src/c/transpiler/emit/`](https://github.com/dstroy0/orior/tree/main/src/c/transpiler/emit)               | one emitter, every container: it reads a layout file and writes what that layout describes                                                                          |
| [`src/c/transpiler/interface/`](https://github.com/dstroy0/orior/tree/main/src/c/transpiler/interface)     | the cell, a probe runner: a probe asks the target one question in a child process the cell can lose                                                                 |
| [`src/c/transpiler/qasm/`](https://github.com/dstroy0/orior/tree/main/src/c/transpiler/qasm)               | exact qubit states, read from OpenQASM                                                                                                                              |

The method is to write C source, read the SASS it compiles to, and hold it against what NVIDIA's compiler writes for the same program (Q17). Every slot a `.krs` writes by hand is asked of the part the way `loop_back` is asked of sm_86 (Q16).

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
