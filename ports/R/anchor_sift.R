# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The permutation null measure, in R.
#
# This is a port of tools/dev_env/proof_conservation.py and it computes the same number. Where the
# two disagree the Python is the reference, because every figure in the ledger came out of it.
#
#   source("ports/R/anchor_sift.R")
#   anchor_sift_departure(utf8ToInt("some long text..."))
#
# What it measures: how far a sequence sits from a shuffle of itself, read through the gaps between
# repeated symbols. A memoryless source returns about 1.00. Natural language returns 0.48 to 0.76.
# Below 1 means the live sequence is more dispersed than its own shuffle, which is clustering.

# Symbols occurring fewer times than this carry no usable gap statistic and are dropped.
ANCHOR_SIFT_MIN_OCCURRENCES <- 32L

# How many reseeds anchor_sift_floor averages over when measuring the null's own spread.
ANCHOR_SIFT_SEEDS <- 12L

#' Population standard deviation, which is what the reference implementation uses.
#'
#' R's sd() divides by n-1. Python's statistics.pstdev divides by n. Using the wrong one shifts
#' every ratio by sqrt(n/(n-1)), which is small and is still a different number.
anchor_sift_pstdev <- function(values) {
  count <- length(values)
  if (count < 1L) return(NA_real_)
  centered <- values - mean(values)
  sqrt(sum(centered * centered) / count)
}

#' Coefficient of variation of the gaps between occurrences, one value per symbol.
#'
#' @param seats integer vector of symbols.
#' @param min_occurrences symbols seen fewer times than this are dropped.
#' @return named numeric vector, names being the symbols as characters.
anchor_sift_dispersion <- function(seats, min_occurrences = ANCHOR_SIFT_MIN_OCCURRENCES) {
  spots <- split(seq_along(seats), seats)
  out <- numeric(0)
  for (value in names(spots)) {
    where <- spots[[value]]
    if (length(where) < min_occurrences) next
    gaps <- diff(where)
    middle <- mean(gaps)
    if (middle > 0) out[value] <- anchor_sift_pstdev(gaps) / middle
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
anchor_sift_departure <- function(seats, seed = 0L,
                                  min_occurrences = ANCHOR_SIFT_MIN_OCCURRENCES) {
  counts <- table(seats)
  live <- anchor_sift_dispersion(seats, min_occurrences)
  if (length(live) < 1L) return(NA_real_)

  set.seed(seed)
  dead <- anchor_sift_dispersion(sample(seats), min_occurrences)

  shared <- intersect(names(live), names(dead))
  shared <- shared[live[shared] > 0]
  if (length(shared) < 4L) return(NA_real_)

  ratios <- dead[shared] / live[shared]
  # Sorted by how often each symbol occurs, most frequent first, then the back half taken. That
  # back half is the rare half and it is the only part quoted anywhere in this work.
  order_by_count <- order(as.numeric(counts[shared]), decreasing = TRUE)
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
anchor_sift_floor <- function(seats, seeds = ANCHOR_SIFT_SEEDS) {
  taken <- vapply(seq_len(seeds) - 1L,
                  function(one) anchor_sift_departure(seats, seed = one),
                  numeric(1))
  taken <- taken[!is.na(taken)]
  list(mean = mean(taken), sd = stats::sd(taken), n = length(taken))
}

#' Convenience: read a text file as bytes and measure it.
#'
#' @param path file to read.
#' @return the departure for that file's bytes.
anchor_sift_file <- function(path) {
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  anchor_sift_departure(as.integer(raw_bytes))
}
