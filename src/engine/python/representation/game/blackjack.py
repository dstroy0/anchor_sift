#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Blackjack: one player against a dealer who has no choices, over a deck that runs down.
#
#   Usage:  from representation.game import blackjack
#           game = blackjack.Blackjack(decks=1)
#
# This is the cheapest solved arm in the set. The tree is small enough to enumerate outright. The
# outcome distribution under a move is not estimated here, it is computed. That makes it the control:
# an estimator that cannot reproduce blackjack exactly has nothing to say about chess.
#
# WHAT IS MODELED AND WHAT IS NOT
#
# The dealer has a fixed rule and therefore never chooses; it is given PLAYER_TWO with exactly one
# legal move at every turn, which states the absence of choice in the protocol. For
# the distribution over win, loss and draw that is the same game -- the hole card is unknown to the
# player either way and is drawn from the same deck -- and it keeps hidden information out of a
# backend that is not about hidden information. Poker is the backend that is.
#
# Doubling, splitting, insurance and surrender are not here. They change what a hand pays, and this
# subject measures which of win, loss and draw is reached, not how much is won. A natural 21 needs no
# special case for the same reason: it wins by comparison like any other 21, and two naturals push,
# which the comparison already returns as DRAW.

from representation.game import rules

# Ranks are indexed 1..10 where 1 is an ace and 10 covers ten, jack, queen and king. A rank's value
# in pips is its index, with the ace's second value handled by `best_total`.
RANKS = tuple(range(1, 11))

# Cards of each rank in one deck. Four of everything, sixteen tens because four ranks share it.
PER_DECK = {1: 4, 2: 4, 3: 4, 4: 4, 5: 4, 6: 4, 7: 4, 8: 4, 9: 4, 10: 16}

# The dealer's rule, stated once. Hitting to 17 and standing on every 17 including a soft one is the
# common house rule and it is an input of this measurement, not a choice made inside the search.
DEALER_STANDS_ON = 17

HIT = "hit"
STAND = "stand"
DRAW_CARD = "draw"
DEALER_MOVE = "dealer"

# Phases of a hand. They are part of the state because the state has to say what happens next
# without the search remembering anything.
DEAL_PLAYER_ONE = "deal_player_one"
DEAL_PLAYER_TWO = "deal_player_two"
DEAL_DEALER = "deal_dealer"
PLAYER_CHOICE = "player_choice"
PLAYER_DRAW = "player_draw"
DEALER_TURN = "dealer_turn"
DEALER_DRAW = "dealer_draw"
SETTLED = "settled"

BUST = 22


def best_total(pips, aces):
    """The hand's value, counting one ace as eleven where that does not bust.

    Only one ace can ever be worth eleven, since two would be twenty two before anything else is
    counted. `pips` already counts every ace as one.
    """
    if aces > 0 and pips + 10 <= 21:
        return pips + 10
    return pips


class Blackjack(object):
    """The blackjack backend. `decks` sets the shoe size and is an input of every result from it."""

    name = "blackjack"

    def __init__(self, decks=1):
        self.decks = decks

    def initial(self):
        shoe = tuple(PER_DECK[rank] * self.decks for rank in RANKS)
        return (DEAL_PLAYER_ONE, 0, 0, 0, 0, shoe)

    def to_move(self, state):
        phase = state[0]
        if phase in (
            DEAL_PLAYER_ONE,
            DEAL_PLAYER_TWO,
            DEAL_DEALER,
            PLAYER_DRAW,
            DEALER_DRAW,
        ):
            return rules.CHANCE
        if phase == PLAYER_CHOICE:
            return rules.PLAYER_ONE
        return rules.PLAYER_TWO

    def moves(self, state):
        phase = state[0]
        if phase == PLAYER_CHOICE:
            return [HIT, STAND]
        if phase == DEALER_TURN:
            return [DEALER_MOVE]
        if phase == SETTLED:
            return []
        return [rank for rank, count in zip(RANKS, state[5]) if count > 0]

    def weights(self, state):
        """How many cards of each drawable rank remain. Exact integers. The mix is exact."""
        return [count for count in state[5] if count > 0]

    def apply(self, state, move):
        phase, player_pips, player_aces, dealer_pips, dealer_aces, shoe = state

        if phase == PLAYER_CHOICE:
            if move == HIT:
                return (
                    PLAYER_DRAW,
                    player_pips,
                    player_aces,
                    dealer_pips,
                    dealer_aces,
                    shoe,
                )
            return (
                DEALER_TURN,
                player_pips,
                player_aces,
                dealer_pips,
                dealer_aces,
                shoe,
            )

        if phase == DEALER_TURN:
            if best_total(dealer_pips, dealer_aces) < DEALER_STANDS_ON:
                return (
                    DEALER_DRAW,
                    player_pips,
                    player_aces,
                    dealer_pips,
                    dealer_aces,
                    shoe,
                )
            return (SETTLED, player_pips, player_aces, dealer_pips, dealer_aces, shoe)

        drawn = move
        shoe = _remove(shoe, drawn)

        if phase in (DEAL_PLAYER_ONE, DEAL_PLAYER_TWO, PLAYER_DRAW):
            player_pips += drawn
            player_aces += 1 if drawn == 1 else 0
            if phase == DEAL_PLAYER_ONE:
                return (
                    DEAL_PLAYER_TWO,
                    player_pips,
                    player_aces,
                    dealer_pips,
                    dealer_aces,
                    shoe,
                )
            if phase == DEAL_PLAYER_TWO:
                return (
                    DEAL_DEALER,
                    player_pips,
                    player_aces,
                    dealer_pips,
                    dealer_aces,
                    shoe,
                )
            nxt = SETTLED if player_pips > 21 else PLAYER_CHOICE
            return (nxt, player_pips, player_aces, dealer_pips, dealer_aces, shoe)

        dealer_pips += drawn
        dealer_aces += 1 if drawn == 1 else 0
        if phase == DEAL_DEALER:
            return (
                PLAYER_CHOICE,
                player_pips,
                player_aces,
                dealer_pips,
                dealer_aces,
                shoe,
            )

        nxt = SETTLED if dealer_pips > 21 else DEALER_TURN
        return (nxt, player_pips, player_aces, dealer_pips, dealer_aces, shoe)

    def verdict(self, state):
        if state[0] != SETTLED:
            return None

        player = best_total(state[1], state[2])
        dealer = best_total(state[3], state[4])

        if player > 21:
            return rules.LOSS
        if dealer > 21:
            return rules.WIN
        if player > dealer:
            return rules.WIN
        if player < dealer:
            return rules.LOSS
        return rules.DRAW

    def describe(self, state):
        """The position in one line, for an example that wants to print what it measured."""
        player = best_total(state[1], state[2])
        dealer = best_total(state[3], state[4])
        soft = " soft" if state[2] > 0 and state[1] + 10 <= 21 else ""
        return "player %d%s, dealer showing %d, %d cards left" % (
            player,
            soft,
            dealer,
            sum(state[5]),
        )


def _remove(shoe, rank):
    """One card of `rank` gone from the shoe."""
    counts = list(shoe)
    counts[rank - 1] -= 1
    return tuple(counts)


def position(decks, player_cards, dealer_card):
    """A named position to measure, built by dealing the given cards out of a fresh shoe.

    This exists, an example can ask about a specific decision -- sixteen against a dealer ten, the
    hand every basic strategy table is remembered for --.
    """
    shoe = list(PER_DECK[rank] * decks for rank in RANKS)
    player_pips = 0
    player_aces = 0
    for card in player_cards:
        shoe[card - 1] -= 1
        player_pips += card
        player_aces += 1 if card == 1 else 0
    shoe[dealer_card - 1] -= 1

    return (
        PLAYER_CHOICE,
        player_pips,
        player_aces,
        dealer_card,
        1 if dealer_card == 1 else 0,
        tuple(shoe),
    )
