# First-move advantage as a winning-path windicator

**Purpose:** Hold the settled parts of the first-move-advantage work apart from the open ones, for a
later session to pick up without re-deriving either. **Scope:**
`examples/game_theory/6_oracle/first_move_advantage.py`, over the game backend in
`src/engine/python/representation/game/` and the sift in `src/engine/python/sift/`.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com> · **Date:** 2026-09-16

Numbers here are exact rationals from the game backend enumeration, reproduced by the example named
above. Where a figure is sampled it carries its trial count and seed.

## The question

Does the side that moves first have an advantage? The move-sequence tree is the wrong place to read
it: it is unbounded, and a bounded search folds a horizon into the number, which this subject refuses
(`src/engine/python/representation/game/rules.py`, the UNRESOLVED discipline). The question is put as
a magnitude instead.

## The windicator

Each player carries one number, its winning-path mass: the probability that play reaches that
player's win, an exact `fractions.Fraction` in [0, 1]. It closes to 1 as a win becomes forced and
rests at 0 when no winning path survives. A winning path bottoms out where the opponent has no legal
move, which is checkmate as the backend already reports it. The two windicators are separate state,
one per player. This is the anchor sift construction named for a game: exact rationals are the exact
measure, a move keeping only some branches-to-win is the necessary-condition sift over
`src/engine/python/sift/anchors.py`, and refusing to fold the horizon is the no-bounding rule.

## Taming the infinite movers with the field's own rule

Real tournament rules end a non-progressing line by chess's own rule, not by a depth cap the analyst
chose: threefold repetition (the rule for a draw of exactly this cyclic type), the fifty-move rule,
and insufficient material. A line that `chess.py` leaves UNRESOLVED forever coalesces to an exact
DRAW under these. That is not bounding: the rule belongs to chess, it is reported, and it is the same
for every position. The example shows the knight-shuffle line reaching its start position three
times, where the plain backend verdict is `None` (ongoing) and the tournament verdict is `draw`.

The representation that makes this tractable is expand, coalesce, collapse: the move-sequence tree is
"so many atoms" only in one dimension; in position space, transpositions and repetitions merge many
sequences into one node, and the exact solve is a retrograde pass over that coalesced graph. The
backend memo in `rules.py` already coalesces transpositions.

## First-move advantage is the anti-invariant, not the magnitude

The sum of the two windicators is invariant under swapping the players; the advantage is odd under
that swap, because giving the move to the other side flips it. A quantity odd under a symmetry is
invisible to any quantity even under it. The advantage lives in the signed difference
V(side to move) minus V(if the other side moved), never in the magnitude. This is the same fact a
reflection-invariant magnitude has about chirality (protein structure analysis, below): exact for
what the symmetry preserves, blind to what it flips.

The value of the move is positive where a tempo helps and **negative in zugzwang**, where being
forced to move loses. So first-move advantage is a property measured per position, not a constant.

## Established results

Reproduced by `examples/game_theory/6_oracle/first_move_advantage.py`:

- **Bare kings**: exact draw by insufficient material, both windicators 0, signed difference 0. The
  control that the instrument can report no advantage.
- **Threefold repetition**: the knight-shuffle line's start position occurs three times; backend
  verdict `None`, tournament verdict `draw`. The field's own rule makes the cyclic line finite and
  exact.
- **Mate in one** (depth 3 plies): W(P1) = 167071/3009600, W(P2) = 0. The opponent has no winning
  path. 19 of 20 P1 moves keep a branch-to-win; the one forcing the win outright, mass 1, is `e1e8`.
  Two routes on W(P1): enumerated 0.055513, sampled 0.057775 at 40000 trials, seed 1511, agreeing to
  within sampling error.
- **King and rook vs king** (depth 4 plies): W(P1) = 59/1083, W(P2) = 0. Only 3 of 19 moves keep a
  branch-to-win; the other 16 prune every one. The move forcing the win, mass 1, is `a1a8`.

## The value of the move, proved exactly for K+P vs K

Reproduced by `examples/game_theory/6_oracle/kpk_value_of_move.py`, which solves all 331352 legal
K+P vs K positions by the win/draw/loss retrograde fixed point (about two to three minutes) and
checks five positions against published endgame theory. All five match, and together they settle the
theorem for this class:

- **Opposition, pawn on the fifth (Ke5/Pe4/Ke7).** White's result is a win if the opponent must move
  and only a draw if White must move. The value of the move is NEGATIVE: moving first throws away
  the win. That is the exact proof that first-move advantage can be a disadvantage.
- **King on the sixth in front of the pawn, and defender far.** A win whoever moves; the value of the
  move is zero.
- **Defender in front with the attacker behind, and the rook pawn in the corner.** A draw whoever
  moves; the value of the move is zero.

The value of the move is positive, zero, or negative by position, and its sign is a table lookup, not
a constant. The retrograde solve and the agreement with published theory are the two routes.

## The exact predictor plays both sides, K+R vs K

Reproduced by `examples/game_theory/6_oracle/krk_both_sides.py` (about half a minute; the position
graph is folded by the eight board symmetries, valid because no pawn breaks them). The tablebase is
extended with distance to mate and a move rule -- the winning side takes the move of least distance to
mate, the losing side the most -- and the exact predictor then plays a whole game as both sides. K+R
vs K is the class where this closes: a forced win, no promotion, and the game stays in the class until
mate.

- From the rook's side to move the value is a win at distance 23 plies, and the predictor plays it out
  in exactly 23 plies to mate. From the bare king's side to move the value is a loss at 28 plies, and
  it plays out in exactly 28. The played length equaling the solved distance is the check: the static
  value and the played game are two routes to one number.
- The repository holds no corpus of human games. The real movesets are the predictor's own optimal
  play from a real starting position, both sides driven by the exact predictor. A win for the rook's
  side is the loss for the bare king, one decisive game read from both ends.

## Fleet cross-checks

Every domain asked reported the same discipline for taming an unbounded set, and each added a caution
that applies here.

- **Chemistry theorist**: never fold the set into one magnitude; each part and each pair is a vector
  whose magnitude is read, the set stays a point cloud, and the reported quantity is a departure from
  a size-matched null (shuffle keeping counts). The null must be drawn at the same size as the
  sample; one number off the whole tree bounds nothing about a line cut at depth d. So the windicator
  is per depth, each paired with a null at that depth.
- **Crystallography**: a norm is irrational and leaves the integers; carry squared magnitudes and
  compare squares, or read per axis and never form a norm. Names its own bounds honestly
  (EXACT_TILES, families cap, right-angle slack) as judgment-picked parameters. Open question it
  raised: whether "collapse to N dimensions" means a norm or a sum of per-axis integer counts; the
  latter stays exact.
- **Protein structure analysis**: a magnitude is exact for what its symmetry preserves and provably
  blind to what the symmetry flips. Measured on 6VXX (ref a70cbe3): 2915/2915 psi torsions hold the
  squared magnitude and flip the sign under reflection. The handedness lives in the sign, not the
  magnitude. This is the anti-invariant argument, and it is why first-move advantage must be the
  signed channel.
- **btc_miner engine**: a norm is a rank-1 readout that throws the rank away; a real higher-degree
  object read as one number vanished into the null and survived only per component (per degree). Keep
  the answer a set of refutations, draw the null by resampling, gate with a positive control.

Shared conclusion: the collapse is per-component exact, never a single norm, and the answer is a
signed per-depth quantity against a size-matched null.

## The repetition-aware tablebase

The exact windicator over a full ending is not a search; it is a table. Define a **repetition-aware
tablebase** as the exact game value V(position, side to move) in {win, draw, loss} for every position
in a material class, computed by retrograde induction from terminals and correct under the tournament
draw rules that make value depend on the path.

- **Nodes and edges.** A node is the backend state (board, side to move, castling rights, en passant
  square). Edges are legal moves from `src/engine/python/representation/game/chess.py`.
- **Terminals.** No legal move is a loss for the mover if the king is in check (checkmate) and a draw
  if not (stalemate). Insufficient material is a draw. These are the base cases of the induction.
- **Irreversible moves partition the graph.** A pawn move or a capture resets both the repetition
  count and the fifty-move counter, and it can never be undone: it leads to strictly less material or
  a further-advanced pawn. So irreversible edges form an acyclic order of **reversible blocks**, and
  the table is solved block by block, the blocks needing the most future pawn moves and captures
  first.
- **Cycles inside a block are the draw.** Within one reversible block the subgraph has cycles. Solve
  it as a fixed point: a node is a win if one move reaches a node that is a loss for the opponent (in
  this block, or in an already-solved block across an irreversible edge); a loss if every move
  reaches a win for the opponent; a draw otherwise. That draw case is exactly every cyclic,
  no-progress line: the threefold-repetition and fifty-move draw. The fifty-move rule caps a
  block at 100 plies. Each block is finite.
- **Graph-history interaction, named.** A position's value can differ by how it was reached, because
  a repetition draws. The value is well defined only relative to the last irreversible move, and that
  boundary is the state that leaves it path-independent. Solving per block keeps the table
  sound; a single position-keyed memo across blocks does not, and the plain negamax stalled and
  mismeasured for that reason.

## The questions, projected onto the table

Every open question becomes an exact lookup or filter, no search and no bound.

1. **Value of the move.** For a position P, read V(P, White to move) and V(P, Black to move). The
   value of the move is the mover's value minus what it would hold if the other side moved. Positive
   is a tempo advantage, zero is no effect, negative is zugzwang.
2. **Does the first move have an advantage, per class.** Filter the table for the sign of the value
   of the move over a whole material class, and report the counts of advantage, neutral, and
   disadvantage. The theorem's answer is that distribution, exact, not a single constant.
3. **Trebuchet.** The mutual-zugzwang position is V(P, White to move) is a White loss AND
   V(P, Black to move) is a Black loss. Both movers lose. The move is a strict disadvantage. It is
   a direct filter on the table, and it is the exact proof that first-move advantage can be negative.
4. **Windicator, saturated.** Under perfect play the windicator is the WDL value, loss 0, draw 1/2,
   win 1. Two routes must produce the same table: retrograde induction, and forward negamax with
   on-path cycle detection. Their agreement is the check.
5. **Positive control.** Bare kings and every insufficient-material class are all draws; the table
   must return V = 1/2 everywhere and value of the move 0. The example already confirms this exactly,
   so the control is in place before the table is built.

## Open problems

- **K+R vs K and K+P vs K+P.** K+P vs K is done, solved and checked above. K+R vs K is the next class
  by the same retrograde. K+P vs K+P is where a two-sided mutual zugzwang lives, and it is solved the
  same way once the promotion tables beneath it (K+Q vs K, K+R vs K) are in hand. The promotion edge
  is why the classes are solved bottom-up, with a stalemate-on-promotion kept a draw, not a win.
- **Find a trebuchet by filter, not by hand.** Once the K+P vs K+P table exists, question 3 finds the
  mutual zugzwang without hand-construction, the robust way to exhibit the negative case.
- **The README routing line.** `examples/game_theory/README.md` says the game-theory book is authored
  upstream in `theory_bucket`. The anchor sift engine is reconciling that line; `theory/` is plain
  tracked content today with no gitlink behind it. Authoring this log here is consistent with the
  current state.
