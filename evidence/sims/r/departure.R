# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The permutation null measure, in R.
#
# This is a port of the rare half in src/engine/python/measure/dispersion.py, the tail that
# evidence/proofs/posits/proof_conservation.py computes too. It computes the same measure and not the same
# number: the null is a shuffle, R draws it from its own generator, and a value agrees with the Python's
# only as far as the reseeding floor allows. Where the two disagree past that the Python is the
# reference, because every figure in the ledger came out of it.
#
#   source("evidence/sims/r/departure.R")
#   orior_file("corpus.sym")
#
# A symbol is a byte, because the reference reads its corpus with open(path, "rb"). Do not hand this
# the output of utf8ToInt: that is one symbol per codepoint where the reference takes one per UTF-8
# byte, and on any text that is not ASCII the two measure different sequences.
#
# What it measures: how far a sequence sits from a shuffle of itself, read through the gaps between
# repeated symbols. In the Python reference's recorded figures a memoryless source returns about 1.00
# and natural language 0.48 to 0.76; no run of this port prints them. Below 1 means the live sequence
# is more dispersed than its own shuffle, which is clustering.

# Symbols occurring fewer times than this carry no usable gap statistic and are dropped.
ORIOR_MIN_OCCURRENCES <- 32L

# How many reseeds orior_floor averages over when measuring the null's own spread.
ORIOR_SEEDS <- 12L

#' Population standard deviation, which is what the reference implementation uses.
#'
#' R's sd() divides by n-1. Python's statistics.pstdev divides by n, and a symbol's spread is the
#' reference's only with it. The departure would not show the wrong one: the live sequence and its
#' shuffle hold the same count of each symbol, so the same number of gaps, and the factor cancels in
#' every ratio. The floor's sd over seeds is where it would not cancel.
orior_pstdev <- function(values) {
  count <- length(values)
  if (count < 1L) {
    return(NA_real_)
  }
  centered <- values - mean(values)
  sqrt(sum(centered * centered) / count)
}

#' Coefficient of variation of the gaps between occurrences, one value per symbol.
#'
#' @param seats integer vector of symbols.
#' @param min_occurrences symbols seen fewer times than this are dropped.
#' @return named numeric vector, names being the symbols as characters.
orior_dispersion <- function(seats, min_occurrences = ORIOR_MIN_OCCURRENCES) {
  spots <- split(seq_along(seats), seats)
  out <- numeric(0)
  for (value in names(spots)) {
    where <- spots[[value]]
    if (length(where) < min_occurrences) next
    gaps <- diff(where)
    middle <- mean(gaps)
    if (middle > 0) out[value] <- orior_pstdev(gaps) / middle
  }
  out
}

#' Departure from a permutation null, averaged over the rare half of the alphabet.
#'
#' The rare half is the half of the qualifying symbols with the lower counts. It is where the
#' reading lives: the frequent half tracks corpus length and is not comparable between corpora of
#' different sizes.
#'
#' @param seats integer vector of symbols.
#' @param seed integer seed for the shuffle that builds the null.
#' @param min_occurrences symbols seen fewer times than this are dropped.
#' @return one number, or NA where fewer than four symbols qualify.
orior_departure <- function(seats, seed = 0L,
                                  min_occurrences = ORIOR_MIN_OCCURRENCES) {
  counts <- table(seats)
  live <- orior_dispersion(seats, min_occurrences)
  if (length(live) < 1L) {
    return(NA_real_)
  }

  set.seed(seed)
  dead <- orior_dispersion(sample(seats), min_occurrences)

  shared <- intersect(names(live), names(dead))
  shared <- shared[live[shared] > 0]
  if (length(shared) < 4L) {
    return(NA_real_)
  }

  ratios <- dead[shared] / live[shared]
  # Sorted by how often each symbol occurs, most frequent first, then the back half taken. That
  # back half is the rare half and it is the only part quoted anywhere in this work. Ties on count
  # fall by ratio, descending, because the reference sorts (count, ratio) pairs. A tie straddling
  # the midpoint would otherwise seat a different symbol in the rare half than the reference does.
  order_by_count <- order(as.numeric(counts[shared]), ratios, decreasing = TRUE)
  ranked <- ratios[order_by_count]
  mean(ranked[(floor(length(ranked) / 2) + 1L):length(ranked)])
}

#' The floor below which a difference between two sequences means nothing.
#'
#' The measure divides a live quantity by one taken from a shuffle, and the shuffle carries its own
#' randomness. Reseeding it says how much the answer moves for no reason at all. Any separation
#' worth reporting has to be several times this.
#'
#' @param seats integer vector of symbols.
#' @param seeds how many reseeds to average over.
#' @return list with mean and sd of the departure across seeds.
orior_floor <- function(seats, seeds = ORIOR_SEEDS) {
  taken <- vapply(
    seq_len(seeds) - 1L,
    function(one) orior_departure(seats, seed = one),
    numeric(1)
  )
  taken <- taken[!is.na(taken)]
  # Population sd, matching the reference's statistics.pstdev. stats::sd divides by n-1 and
  # inflates the floor by sqrt(n/(n-1)), and the floor is what every other number is read against.
  list(mean = mean(taken), sd = orior_pstdev(taken), n = length(taken))
}

#' Convenience: read a text file as bytes and measure it.
#'
#' @param path file to read.
#' @return the departure for that file's bytes.
orior_file <- function(path) {
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  orior_departure(as.integer(raw_bytes))
}
