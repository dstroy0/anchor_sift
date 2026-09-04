# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether the per symbol ratios are normally distributed, for the heavy tail posit in
# docs/research/anchor-sift-ledger.md.
#
#   Usage:  Rscript tools/dev_env/ratio_normality.R [build/ratios.csv]
#
# The posit holds that the quantities in this work are heavy tailed as a rule, and it came from two
# derived figures. This tests the measure they are derived from. Shapiro-Wilk answers whether a sample is
# normal, and the skew and excess kurtosis say in which direction it fails, so a corpus that fails through
# a long right tail can be told from one that fails through a single outlier.
#
# A logarithm is applied as well. A ratio is bounded below by zero and unbounded above, which is the shape
# that produces a right tail by construction, and a quantity that is normal in the logarithm has a mean
# that means something once taken there.

args <- commandArgs(trailingOnly = TRUE)
path <- if (length(args) > 0) args[1] else "build/ratios.csv"
data <- read.csv(path, stringsAsFactors = FALSE)

cat(sprintf("%d ratios over %d corpora\n\n", nrow(data), length(unique(data$corpus))))

cat(sprintf("  %-28s %-6s %-9s %-10s %-9s %-10s %s\n",
            "corpus", "n", "skew", "kurtosis", "W", "p", "log p"))

skewness <- function(x) {
  m <- mean(x); s <- sqrt(mean((x - m)^2))
  if (s <= 0) return(NA)
  mean(((x - m) / s)^3)
}
kurtosis <- function(x) {
  m <- mean(x); s <- sqrt(mean((x - m)^2))
  if (s <= 0) return(NA)
  mean(((x - m) / s)^4) - 3
}

failed <- 0
total <- 0
for (name in sort(unique(data$corpus))) {
  values <- data$ratio[data$corpus == name]
  if (length(values) < 12) next
  # Shapiro-Wilk takes at most 5000 observations
  sample_values <- if (length(values) > 5000) sample(values, 5000) else values
  test <- shapiro.test(sample_values)
  logged <- shapiro.test(log(sample_values[sample_values > 0]))
  total <- total + 1
  if (test$p.value < 0.01) failed <- failed + 1
  cat(sprintf("  %-28s %-6d %+-9.3f %+-10.3f %-9.4f %-10.2e %.2e\n",
              substr(name, 1, 28), length(values), skewness(values), kurtosis(values),
              test$statistic, test$p.value, logged$p.value))
}

cat(sprintf("\n  normality rejected at 1%% for %d of %d corpora\n", failed, total))
