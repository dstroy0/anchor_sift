# scriptura's blocks

**Purpose:** The one rule on what scriptura's SWAR memory scans may be handed, and why it settles the over-read question.
**Scope:** `scriptura_compare`, `scriptura_length`, `scriptura_find`, `scriptura_copy`, `scriptura_fill` (M17 of [engine_table.md](engine_table.md)).

Ruled by Doug, 23 September: "never pass unaligned memory to this, ever"; "the solution is to always nul term memory blocks you hand it".

- Every block handed to the scriptura word scans is 8-byte aligned and NUL-terminated. A string literal is not guaranteed aligned: copy it into an aligned block first.
- Used this way, `scriptura_compare(a, b, length of b + 1)` returns strcmp's sign. The bytes read past a short block's NUL never change the result (the first differing lane decides it, bitwise). An aligned word never crosses a page.
- The over-read question is settled by this rule and is not reopened.
