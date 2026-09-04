# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test the halving ladder's loss ratio against collision entropy, for the ledger entry in
# docs/research/anchor-sift-ledger.md.
#
#   Usage:  Rscript tools/dev_env/ladder_analysis.R [build/ladder.csv]
#
# The Python side computes slopes, standard errors and t values, and all of those assume a normal
# distribution which this data rejects with a Jarque-Bera statistic of 800 against a one percent point
# of 9.21. The tests below either check that assumption directly or avoid needing it: Shapiro-Wilk on
# the values themselves and on the residuals, and Spearman's rank correlation, which tests monotone
# association without assuming any distribution.

args <- commandArgs(trailingOnly = TRUE)
path <- if (length(args) > 0) args[1] else "build/ladder.csv"
data <- read.csv(path, stringsAsFactors = FALSE)

cat(sprintf("%d corpora from %s\n\n", nrow(data), path))

cat("distribution of the loss ratio\n")
cat(sprintf("  min %.4f  median %.4f  mean %.4f  max %.4f  sd %.4f\n",
            min(data$ratio), median(data$ratio), mean(data$ratio),
            max(data$ratio), sd(data$ratio)))

shapiro <- shapiro.test(data$ratio)
cat(sprintf("  Shapiro-Wilk W %.4f  p %.3e  %s\n\n", shapiro$statistic, shapiro$p.value,
            if (shapiro$p.value < 0.01) "normality rejected at 1%" else "normality not rejected"))

cat("least squares, which needs the residuals to be normal\n")
fit <- lm(ratio ~ h2, data = data)
coefs <- summary(fit)$coefficients
cat(sprintf("  slope %+.4f  stderr %.4f  t %+.2f  p %.4f  r2 %.4f\n",
            coefs[2, 1], coefs[2, 2], coefs[2, 3], coefs[2, 4], summary(fit)$r.squared))
residual_test <- shapiro.test(residuals(fit))
cat(sprintf("  Shapiro-Wilk on residuals W %.4f  p %.3e  %s\n\n",
            residual_test$statistic, residual_test$p.value,
            if (residual_test$p.value < 0.01) "the fit's own assumption fails"
            else "residuals pass"))

cat("Spearman rank correlation, which assumes no distribution at all\n")
spearman <- suppressWarnings(cor.test(data$h2, data$ratio, method = "spearman"))
cat(sprintf("  rho %+.4f  S %.1f  p %.4f  %s\n\n", spearman$estimate, spearman$statistic,
            spearman$p.value,
            if (spearman$p.value < 0.05) "monotone association" else "no monotone association"))

cat("by family, with a distribution free comparison of the two independent groups\n")
for (name in sort(unique(data$family))) {
  rows <- data[data$family == name, ]
  cat(sprintf("  %-12s n %-4d median %+.4f  IQR %.4f  range %+.4f to %+.4f\n",
              name, nrow(rows), median(rows$ratio), IQR(rows$ratio),
              min(rows$ratio), max(rows$ratio)))
}

natural <- data$ratio[data$family == "natural"]
memoryless <- data$ratio[data$family == "memoryless"]
if (length(natural) > 2 && length(memoryless) > 2) {
  wilcox <- suppressWarnings(wilcox.test(natural, memoryless))
  cat(sprintf("\n  natural against memoryless, Wilcoxon rank sum W %.1f  p %.4f  %s\n",
              wilcox$statistic, wilcox$p.value,
              if (wilcox$p.value < 0.05) "they differ" else "no difference established"))
}
