#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Draw poker: chance, hidden information, and a ranking nobody here invented.
#
#   Usage:  from representation.game import poker
#           game = poker.Poker(ranks=6, suits=2, hand=3)   # small enough to solve
#           game = poker.Poker(ranks=13, suits=4, hand=5)  # the real deck, sampled only
#
# The deck size is a parameter and that is the whole design. The same rules, the same evaluator and
# the same discard decision run on a twelve card deck that can be enumerated outright and on a fifty
# two card deck that cannot. That gives the two arms something to agree about: the solved arm runs on
# the small deck, the sampled arm runs on both, and where they overlap they have to match. An
# estimator that is right only where it cannot be checked is not a measurement.
#
# The hand ranking is the external answer key. Nothing in this tree decides that a flush beats a
# straight; that ordering came from outside and predates the instrument, the same property
# that makes the Crystallography Open Database a positive control and not a second opinion.
#
# WHAT A MOVE IS
#
# Each player is dealt a hand, PLAYER_ONE discards a subset of it and draws replacements, PLAYER_TWO
# does the same, and the better hand wins. The move is the discard subset. The move set is every
# subset of the hand and the decision is a real one with a computable best answer. Betting is not
# modeled: a bet changes what a pot pays and this subject measures which of win, loss and draw is
# reached. Hidden information is modeled, because PLAYER_TWO chooses its discard without seeing
# PLAYER_ONE's hand, and that is the property blackjack does not have.

import itertools

from representation.game import rules

# Hand categories, low to high. The names are the usual ones and the order is the usual order.
HIGH_CARD = 0
PAIR = 1
TWO_PAIR = 2
TRIPS = 3
STRAIGHT = 4
FLUSH = 5
FULL_HOUSE = 6
QUADS = 7
STRAIGHT_FLUSH = 8

CATEGORY_NAMES = {
    HIGH_CARD: "high card",
    PAIR: "pair",
    TWO_PAIR: "two pair",
    TRIPS: "three of a kind",
    STRAIGHT: "straight",
    FLUSH: "flush",
    FULL_HOUSE: "full house",
    QUADS: "four of a kind",
    STRAIGHT_FLUSH: "straight flush",
}

DEAL_ONE = "deal_one"
DEAL_TWO = "deal_two"
DISCARD_ONE = "discard_one"
DRAW_ONE = "draw_one"
DISCARD_TWO = "discard_two"
DRAW_TWO = "draw_two"
SHOWDOWN = "showdown"


def card(rank, suit):
    """One card as a single integer. A hand sorts and hashes without a class."""
    return rank * 16 + suit


def rank_of(value):
    return value // 16


def suit_of(value):
    return value % 16


def evaluate(hand):
    """The strength of a hand, as a tuple that compares correctly against another hand's.

    The leading element is the category and the rest are the tie breakers in the order they are
    read: the rank of the group that made the category first, then the kickers descending. Comparing
    two of these with `<` gives the same answer as the rules of poker.

    Straights and flushes are computed from the ranks and suits actually present. A short deck
    still has them and a two suit deck simply makes flushes common. That is deliberate. The small
    deck is not a toy version of poker with the interesting parts removed, it is the same game on
    fewer cards, and the categories have to keep working for the solved arm to mean anything.
    """
    ranks = sorted((rank_of(value) for value in hand), reverse=True)
    suits = [suit_of(value) for value in hand]

    counts = {}
    for rank in ranks:
        counts[rank] = counts.get(rank, 0) + 1

    # Groups ordered by size first and by rank second, which is exactly the tie break order.
    groups = sorted(counts.items(), key=lambda item: (item[1], item[0]), reverse=True)
    shape = tuple(size for _, size in groups)
    ordered = tuple(rank for rank, _ in groups)

    flush = len(set(suits)) == 1
    distinct = sorted(set(ranks), reverse=True)
    straight_high = None
    if len(distinct) == len(hand):
        if distinct[0] - distinct[-1] == len(hand) - 1:
            straight_high = distinct[0]
        elif distinct[0] == max(rank_of(value) for value in hand) and _wheel(distinct):
            # The ace low straight, where the highest rank plays as one below the lowest.
            straight_high = distinct[1]

    if straight_high is not None and flush:
        return (STRAIGHT_FLUSH, straight_high)
    if shape[0] == 4:
        return (QUADS,) + ordered
    if shape[:2] == (3, 2):
        return (FULL_HOUSE,) + ordered
    if flush:
        return (FLUSH,) + tuple(ranks)
    if straight_high is not None:
        return (STRAIGHT, straight_high)
    if shape[0] == 3:
        return (TRIPS,) + ordered
    if shape[:2] == (2, 2):
        return (TWO_PAIR,) + ordered
    if shape[0] == 2:
        return (PAIR,) + ordered
    return (HIGH_CARD,) + tuple(ranks)


def _wheel(distinct):
    """Whether these distinct ranks are a straight with the top rank playing low."""
    body = distinct[1:]
    if not body:
        return False
    if body[0] - body[-1] != len(body) - 1:
        return False
    return body[-1] == 0


class Poker(object):
    """The draw poker backend over a deck of `ranks` ranks and `suits` suits, `hand` cards each."""

    name = "poker"

    def __init__(self, ranks=6, suits=2, hand=3):
        self.ranks = ranks
        self.suits = suits
        self.hand = hand
        self.deck = tuple(
            card(rank, suit) for rank in range(ranks) for suit in range(suits)
        )

    def initial(self):
        return (DEAL_ONE, (), (), self.deck, ())

    def to_move(self, state):
        phase = state[0]
        if phase in (DEAL_ONE, DEAL_TWO, DRAW_ONE, DRAW_TWO):
            return rules.CHANCE
        if phase == DISCARD_ONE:
            return rules.PLAYER_ONE
        return rules.PLAYER_TWO

    def moves(self, state):
        phase, one, two, deck, pending = state

        if phase == SHOWDOWN:
            return []
        if phase == DISCARD_ONE:
            return _subsets(one)
        if phase == DISCARD_TWO:
            return _subsets(two)
        return list(deck)

    def weights(self, state):
        """Every remaining card is one card. Distinct cards. The weights are all one."""
        return [1] * len(state[3])

    def apply(self, state, move):
        phase, one, two, deck, pending = state

        if phase == DISCARD_ONE:
            kept = tuple(value for value in one if value not in move)
            return (DRAW_ONE, kept, two, deck, (len(move),))
        if phase == DISCARD_TWO:
            kept = tuple(value for value in two if value not in move)
            return (DRAW_TWO, one, kept, deck, (len(move),))

        drawn = move
        deck = tuple(value for value in deck if value != drawn)

        if phase == DEAL_ONE:
            one = tuple(sorted(one + (drawn,)))
            nxt = DEAL_ONE if len(one) < self.hand else DEAL_TWO
            return (nxt, one, two, deck, ())
        if phase == DEAL_TWO:
            two = tuple(sorted(two + (drawn,)))
            nxt = DEAL_TWO if len(two) < self.hand else DISCARD_ONE
            return (nxt, one, two, deck, ())
        if phase == DRAW_ONE:
            one = tuple(sorted(one + (drawn,)))
            remaining = pending[0] - 1
            if remaining > 0:
                return (DRAW_ONE, one, two, deck, (remaining,))
            return (DISCARD_TWO, one, two, deck, ())

        two = tuple(sorted(two + (drawn,)))
        remaining = pending[0] - 1
        if remaining > 0:
            return (DRAW_TWO, one, two, deck, (remaining,))
        return (SHOWDOWN, one, two, deck, ())

    def verdict(self, state):
        phase, one, two, _, _ = state
        if phase != SHOWDOWN:
            return None

        left = evaluate(one)
        right = evaluate(two)
        if left > right:
            return rules.WIN
        if left < right:
            return rules.LOSS
        return rules.DRAW

    def describe(self, state):
        phase, one, two, deck, _ = state
        return "%s  one=%s  two=%s  deck=%d" % (
            phase,
            show(one),
            show(two) if phase == SHOWDOWN else "hidden",
            len(deck),
        )

    def deal(self, one_cards, two_cards):
        """A named position with both hands already dealt, for measuring one discard decision."""
        one = tuple(sorted(one_cards))
        two = tuple(sorted(two_cards))
        deck = tuple(
            value for value in self.deck if value not in one and value not in two
        )
        return (DISCARD_ONE, one, two, deck, ())


def _subsets(hand):
    """Every subset of a hand, smallest first, as the discard choices available."""
    found = []
    for size in range(len(hand) + 1):
        for combination in itertools.combinations(hand, size):
            found.append(combination)
    return found


def show(hand):
    """A hand as readable text, for an example printing what it measured."""
    letters = "23456789TJQKA"
    suited = "shdc"
    parts = []
    for value in hand:
        rank = rank_of(value)
        parts.append(
            "%s%s"
            % (
                letters[rank] if rank < len(letters) else str(rank),
                (
                    suited[suit_of(value)]
                    if suit_of(value) < len(suited)
                    else str(suit_of(value))
                ),
            )
        )
    return " ".join(parts)
