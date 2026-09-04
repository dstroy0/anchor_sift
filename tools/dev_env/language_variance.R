# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Decide whether a language carries a constant, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  Rscript tools/dev_env/language_variance.R [build/language_constant.csv]
#
# The claim is that a language has an idiom of its own and that it is constant. Stated that way it is a
# variance question: if it holds, the spread of a quantity within one language is small against the
# spread between languages, and the ratio of the two is what an analysis of variance reports.
#
# Three quantities are tested and they are not expected to behave alike. The mean distance between word
# boundaries should belong to a language, since word length does. Collision entropy should belong to it
# partly, through the size and shape of its character inventory. The rare half against a permutation null
# was found in earlier work to hold across every language measured, so if it is a universal it should
# fail to separate them, and that failure is the result and not the absence of one.
#
# Chinese is held out of the main test and reported separately. It is logographic, carries 3164 distinct
# symbols against 87 to 98 for the others, and would dominate any variance it entered.

args <- commandArgs(trailingOnly = TRUE)
path <- if (length(args) > 0) args[1] else "build/language_constant.csv"
data <- read.csv(path, stringsAsFactors = FALSE)

alphabetic <- data[data$language != "chinese", ]
cat(sprintf("%d texts over %d alphabetic languages, plus %d Chinese\n\n",
            nrow(alphabetic), length(unique(alphabetic$language)),
            sum(data$language == "chinese")))

cat(sprintf("  %-10s %-10s %-10s %-9s %-10s %s\n",
            "quantity", "within sd", "between sd", "ratio", "F", "p"))

for (name in c("h2", "gap", "tail")) {
  values <- alphabetic[[name]]
  groups <- factor(alphabetic$language)

  # Spread inside a language, pooled, against the spread of the language means
  within <- sqrt(mean(tapply(values, groups, function(x) mean((x - mean(x))^2))))
  between <- sd(tapply(values, groups, mean))

  fit <- summary(aov(values ~ groups))[[1]]
  cat(sprintf("  %-10s %-10.4f %-10.4f %-9.2f %-10.2f %.2e\n",
              name, within, between, between / within, fit[["F value"]][1], fit[["Pr(>F)"]][1]))
}

cat("\n  Chinese against the alphabetic languages, in within-language standard deviations\n")
for (name in c("h2", "gap", "tail")) {
  values <- alphabetic[[name]]
  groups <- factor(alphabetic$language)
  within <- sqrt(mean(tapply(values, groups, function(x) mean((x - mean(x))^2))))
  middle <- mean(values)
  chinese <- mean(data[data$language == "chinese", ][[name]])
  cat(sprintf("  %-10s alphabetic %.3f, chinese %.3f, distance %.1f\n",
              name, middle, chinese, abs(chinese - middle) / within))
}
