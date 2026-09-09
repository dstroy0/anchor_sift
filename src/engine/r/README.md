# The engine in R

**Purpose:** Test whether the assumptions the other implementations rest on actually hold, and read the measure from R.
**Scope:** `src/engine/r/measure/`, `src/engine/r/hypotheses/`

R is here for one reason the other implementations cannot cover. The Python side computes means, standard deviations, slopes, standard errors and t values, and every one of those assumes a distribution. Python's standard library carries no Shapiro-Wilk, no analysis of variance, no Wilcoxon and no Spearman, so the assumption went unchecked until these existed.

```
Rscript src/engine/r/hypotheses/ratio_normality.R build/ratios.csv
Rscript src/engine/r/hypotheses/ladder_analysis.R build/ladder.csv
Rscript src/engine/r/hypotheses/language_variance.R build/language_constant.csv
```

Each reads a CSV the Python writes. Nothing here measures a corpus.

| file | the hypothesis it tests |
|---|---|
| `hypotheses/ratio_normality.R` | are the per symbol ratios normal, and if not, which way do they fail |
| `hypotheses/ladder_analysis.R` | does the least squares fit's own assumption hold, and does anything survive without it |
| `hypotheses/language_variance.R` | is the spread within one language small next to the spread between languages |
| `measure/departure.R` | the permutation null measure, ported |

## What these found, and why they exist

**The standard errors were invalid.** The loss ratio has a skew of -4.20 and an excess kurtosis of +19.67, giving a Jarque-Bera statistic of 800.1 against a one percent point of 9.21. Normality is rejected by a factor of 87, so every `t` and every `σ` computed from those values assumed something the data denies. A claim that one corpus gave 1.600 with a standard error of 0.107, and that the interval therefore contained several named constants, was arithmetic the distribution does not support.

What survived was the part that needs no distribution: Spearman gives ρ = +0.049 at p = 0.76, so no monotone association with collision entropy exists, and Wilcoxon separates the natural corpora from the memoryless ones at p = 0.0009 with medians of 1.195 and 0.942. The quantity separates structured sources from unstructured ones and does not vary with the alphabet weight. The original four point ordering suggested the opposite.

**Normality is rejected for five of seven corpora**, and the description of how was wrong. Skew runs in both directions, from +2.98 on prime gaps to -0.37 on C source, and a logarithm does not repair it and often makes it worse, reaching 5e-12 on Greek. These are not log normal either. They are non normal in ways that differ by corpus.

**A language does carry constants, and the rare half is not one of them.** The mean distance between word boundaries separates languages at F = 13.21, and collision entropy at F = 9.02, with the between language spread exceeding the within language spread in both. The rare half against a permutation null gives F = 0.66 at p = 0.68, and its between language spread of 0.0342 is smaller than its within language spread of 0.0731.

That failure is the result and not the absence of one. A universal has to look exactly like that: carrying no information about which language it is reading. Chinese settles it, standing 66.0 within-language deviations away on collision entropy and 22.1 on the mean gap, and 0.5 away on the rare half.

## The port

`measure/departure.R` computes the same number as the Python reference, and where the two disagree the Python is the reference because every figure in the ledger came out of it. Checked on 200000 symbols over twelve seeds: a clustered sequence reads 0.4228 in Python and 0.4282 here against a floor of 0.0092, and a memoryless one reads 0.9953 and 0.9933 against a floor of 0.0044. Both gaps sit at about half a floor.

It uses a population standard deviation. R's default divides by `n-1`, and taking that one shifts every ratio by `sqrt(n/(n-1))`, which is small and is still a different number.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
