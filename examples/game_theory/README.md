# Game theory

**Purpose:** Measure how much of a game's result is still open after a move is chosen, on four games
that carry their own answer key, and show what pruning the opponent's replies does to that number.
**Scope:** `examples/game_theory/`, over `src/engine/python/representation/game/`,
`src/engine/python/measure/outcome_entropy.py` and `src/engine/python/measure/periodicity.py`

| stage         | script                                     | what it answers                                                            |
| ------------- | ------------------------------------------ | -------------------------------------------------------------------------- |
| `1_represent` | `four_games_one_protocol.py`               | what a position keeps, and what six calls a game has to answer             |
| `1_represent` | `reversi_positions.py`                     | a played board and the same pieces drawn, side by side                     |
| `2_partition` | `what_the_branching_costs.py`              | how fast a position subdivides, and where enumeration stops being possible |
| `2_partition` | `board_width.py`                           | Reversi returns 8; a grid with two axes of structure returns one of them   |
| `3_reference` | `what_random_play_reaches.py`              | what the same position returns when nobody is trying                       |
| `3_reference` | `position_null.py`                         | the departure is the flip rule, not the board                              |
| `4_measure`   | `entropy_of_the_outcome_given_the_move.py` | H(Y\|X), and how many bits the choice of move is worth                     |
| `4_measure`   | `grundy_period.py`                         | 383 of 383 readable subtraction games return their exact Grundy period     |
| `4_measure`   | `rules_and_play.py`                        | the departure reads the rules and does not order the players               |
| `5_sift`      | `survivorship_changes_the_question.py`     | what pruning the opponent's branches does to the quantity being reported   |
| `6_oracle`    | `against_published_values.py`              | whether any of it matches what somebody else published                     |
| `6_oracle`    | `bouton_and_wythoff.py`                    | Bouton 1901 and Wythoff 1907, off grids built without either               |
| `6_oracle`    | `sturmian_convergents.py`                  | what the period detector returns on a sequence with no period              |

## Why a game

Every other subject in this tree measures something whose right answer is either unknown or was
produced here. A game is different: a terminal position is win, loss or draw by the rules. The
outcome distribution under a move is a quantity with a true value, and for a game small enough to
enumerate that value can be computed outright. An estimator that disagrees with
it is wrong in a way no amount of sampling can argue with.

The four games are the four corners of the two properties that decide whether the true value is
reachable -- whether chance deals, and whether the opponent chooses.

|                  | opponent chooses | opponent has no choice |
| ---------------- | ---------------- | ---------------------- |
| **chance deals** | poker            | blackjack              |
| **no chance**    | checkers, chess  | --                     |

Blackjack, checkers endgames and small-deck poker give a solved arm. Chess does not, and that is why
it is here. A chess position after four plies has more continuations than the other three games have
positions. The chess number has to be estimated and nothing local can catch it being wrong. The
only thing standing behind it is whether the same estimator reproduced the games that could be
solved. This subject exists to make that boundary visible.

## What the stages found

**Pruning the opponent's replies turns a lost checkers ending into a certain win.** Same position,
same budget, same code. Three conditionings are computed side by side and each carries the sentence
saying which quantity it is:

| conditioning | what it measures                                  | win          | loss     | unresolved |
| ------------ | ------------------------------------------------- | ------------ | -------- | ---------- |
| null         | P(outcome \| move), both sides uniform            | 0.089039     | 0.032665 | 0.878296   |
| survivor     | P(outcome \| move, both sides play into our line) | **1.000000** | 0.000000 | 0.000000   |
| adversary    | P(outcome \| move, opponent plays its best reply) | **0.000000** | 0.039802 | 0.960198   |

That is the finding this subject was built for, and the cost of pruning is not that the number gets
bigger. The cost is that it stops being the number it is named after. `P(outcome | move)` and
`P(outcome | move, the opponent plays into our line)` are different quantities about different
things, and the second is not an estimate of the first. Reporting the second under the first's name
is the way this work would be quietly wrong.

**In poker the pruning changes the recommendation, not just the probability.** On a pair of sevens
over a twelve card deck the survivorship reading wins 0.833333 and the adversary reading 0.361111, a
gap of 0.472222 -- and they do not agree on what to do. Unpruned, the best move is to discard `2s 7s`.
Pruned, it is to keep the hand. A probability that is wrong can be caveated. A recommendation that is
wrong gets acted on.

**Blackjack is the control that makes those two numbers evidence.** Its
dealer has exactly one legal move at every turn. There is nothing to prune, and the pruned and
unpruned readings must come out identical. They do, to the digit: gap `0.000000`. Without that, three
different numbers from three conditionings could just be three different bugs. The same holds on a
forced back rank mate in chess, where the gap is also exactly zero, and for the same structural
reason -- a mate survives any opponent. Pruning removes nothing that mattered.

**A shallow budget can drive the information gain to zero on a position that is entirely decided.**
On a back rank mate in one at two plies, read over the resolved outcomes alone, `I(X;Y)` is
`0.0000` -- because nineteen of the twenty moves resolved nothing and were dropped from the sum,
leaving only the mate, and a single certain outcome has no entropy to lose. The reading is computed
over `1/20` of the move set and says so. Read over all four categories the same position reports
`I(X;Y) = 0.2864`, because whether the game ends here is itself one of the things knowing the move
tells you. That is why both readings are printed with the covered share beside them, and why neither
is offered as the number.

**Every published value checked, and the negative control rejects.** Stage six runs 13 checks against
numbers that existed before this code did, and one deliberately broken generator that has to fail.

| check                                                              | measured              | published             |
| ------------------------------------------------------------------ | --------------------- | --------------------- |
| chess perft(1..4) from the opening                                 | 20, 400, 8902, 197281 | 20, 400, 8902, 197281 |
| chess perft(1..2) from Kiwipete                                    | 48, 2039              | 48, 2039              |
| checkers legal moves from the opening                              | 7                     | 7                     |
| blackjack dealer bust rate, ten showing                            | 0.2099                | 0.2120 ± 0.010        |
| blackjack: standing on 16 can never draw                           | 0.0                   | 0.0                   |
| blackjack basic strategy, 16 against a ten                         | hit                   | hit                   |
| poker: all nine hand categories in order                           | yes                   | yes                   |
| poker: ace low straight is a straight                              | yes                   | yes                   |
| **negative control** -- perft(1) with the pawn double step removed | 12                    | not 20                |

Kiwipete is in there for a specific reason: the opening position does not exercise castling, en
passant or promotion. A generator can be wrong in three ways and still pass perft from the start.

The blackjack dealer bust rate is a windowed check, and the window is stated in the call
rather than chosen until the result passed. The published figure is quoted for an infinite deck and
this is one deck with three cards already removed. The two differ by composition. Standing on 16
wins only where the dealer busts, that single number checks the whole dealer rule.

## Played boards and impartial games

Seven of the scripts read two more kinds of object, through `representation/game/board.py` and
`representation/game/combinatorial.py`, and they are not the same kind of evidence as each other.

A **played board** is a position: a square is a point and the piece on it is its value. The null is
the same pieces on the same squares in a drawn order. A board is the only corpus in this work where
the two ingredients of an object can be varied separately, because the rules are fixed and public
and the play is a choice.

An **impartial game** is a position index carrying a Grundy value. This is the subject that closes a
hole the workbook names in its own words: every reach claim here is quantified over a set nobody has
enumerated, and closing one needs a controlled series inside a domain with an outside answer on every
row. Subtraction games give that for the price of the arithmetic, and the answers are theorems.

None of the seven fetches anything. Every corpus they read is generated by the arithmetic that
defines the game, so a row costs a second and the count of rows is a choice rather than a budget.

The one to read first is `6_oracle/sturmian_convergents.py`. It is the only script here that corrects
something outside its own subject. Handed an aperiodic word, `sequence_period` returns a number, that
number clears its own shuffle floor by 3 to 29 times, and it is still not a period: it is the
denominator of a continued fraction convergent of the word's slope, and it grows as the window
widens. The word "period" on that output is wrong and the margin does not catch it.

The diagnostic that does catch it needs no oracle. A real period is the same number at every window.
115 of 115 subtraction games with a true period give one answer across five windows; 0 of 9 aperiodic
words give one answer across seven. `measure.periodicity.stable_period` runs that test.

## What is not folded in, and why the numbers look worse for it

A bounded search has to do something with the positions it never resolved. The usual answer is an
evaluation function: score the unresolved position and fold that score into the result. That converts
a bound on the search into a number that looks like an outcome, and nothing downstream can tell the
two apart afterwards.

This does not do that. Unresolved mass is carried as its own outcome and never redistributed over
win, loss and draw. That is why the checkers table above reads 0.96 unresolved under an adversary
and why the chess opening at four plies resolves almost
nothing and says so. The standing discipline in this tree is that bounding is not allowed -- no
judgment-picked tolerances or parameters -- and a search depth is a bound. It is allowed here only
because it is a declared input, reported beside every result and visible in the distribution it
produced.

This is the same failure crystallography records, in a different domain. A 0.25 angstrom grid applied
on the way in silently became the answer, and every number downstream carried the grid instead of the
deposit. An evaluation function is that grid.

Entropy is reported twice for the same reason: `H_res` over the resolved outcomes renormalized, which
is the position's uncertainty, and `H_all` over all four categories, which includes the search's own
ignorance. Neither is right on its own. Reporting only `H_res` hides how little was resolved;
reporting only `H_all` lets a bigger budget look like a more certain position.

## Where the one float is

Everything upstream of the logarithm is exact. Outcome distributions are `fractions.Fraction`, built
from exact integer weights over deck counts and uniform move priors. Two distributions computed by
different routes are compared with `==` and not with a tolerance. `log2` of a rational is irrational
except at powers of two. The entropy is a float and carries sixteen digits and no more.

That boundary is drawn as late as possible and every probability printed beside an entropy is the
exact rational. A reader who distrusts the entropy can recompute it.
The quantity compared between conditionings is the distribution; the entropy is a summary of it.

No banned library is used anywhere in this subject -- no numpy, scipy, sympy, mpmath, pandas, torch,
jax, cupy, numba or sklearn. Python's own integers and `fractions.Fraction` carry all of it.

## Two routes or it does not ship

Stage three computes the null twice: once by enumerating every continuation exactly, once by playing
seeded games out and counting. They answer the same question by different routes and have to agree
where both can run. The sampled arm converges to the enumerated one and does not equal it; that gap
is sampling error and shrinks with the trial count. A gap that does not shrink would mean one of the
two routes is wrong, and it would be printed.

The seed is an input of the measurement in the same way the budget is, and it is reported with the
result. A sampled number nobody can reproduce is not a measurement.

## Running one

```
python examples/game_theory/6_oracle/against_published_values.py
python examples/game_theory/5_sift/survivorship_changes_the_question.py
python examples/game_theory/2_partition/what_the_branching_costs.py 5
python examples/game_theory/3_reference/what_random_play_reaches.py 20000
```

Stage six is the positive control, it takes a few seconds, and nothing
else in the subject means anything if it fails. Stage two is the slow one: its chess arm is a perft
and the node count is exponential. Passing a larger ply count costs what the game charges.

## What is not here

The write-up of what these measurements mean is the book at `theory/game_theory`. This directory is
the implementation and the measurements.

Betting is not modeled in poker and doubling, splitting, insurance and surrender are not modeled in
blackjack. All of those change what a hand pays, and this subject measures which of win, loss and
draw is reached. The fifty move rule, threefold repetition and
insufficient material are not modeled in chess, because each turns a long game into a draw and this
subject reports a game the budget did not finish as unresolved.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
