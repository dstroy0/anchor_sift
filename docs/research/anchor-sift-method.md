# The anchor-sift detector

**Purpose:** Run the byte-pair distribution pipeline: squash text to a flat distribution, measure distance, establish validity by split-half, correct for support, cluster, and control for family.
**Scope:** `tools/dev_env/byte_signature.py`, `tools/dev_env/salish_purity.py`, `tools/dev_env/corpus_gate.py`, `tools/dev_env/case_or_splitting.py`, `tools/dev_env/cluster_profiles.py`, `tools/dev_env/evidential_pressure.py`

## 1. Squash

Text $T$, whitespace stripped, encoded UTF-8 to bytes $b_0 \dots b_{m-1}$. Every adjacent pair maps to one index:

$$k_i \;=\; 256\,b_i + b_{i+1}, \qquad k_i \in [0,\,65536)$$

This is the squash. A variable-length sequence over a $256$-symbol alphabet becomes a fixed flat array of $2^{16}$ cells, with no character-level decision taken anywhere in it. The map is injective on pairs, so no two distinct pairs collide.

$$P_T(k) \;=\; \frac{c_T(k)}{\sum_{j} c_T(j)}, \qquad c_T(k) = \bigl|\{\, i : k_i = k \,\}\bigr|$$

$P_T$ is a probability distribution over $2^{16}$ outcomes (`tools/dev_env/byte_signature.py:85-93`).

## 2. Distance

$$D(P,Q) \;=\; \tfrac{1}{2} \sum_{k=0}^{65535} \bigl| P(k) - Q(k) \bigr| \;\in\; [0,1]$$

Total variation. $D=0$ when the distributions agree everywhere, $D=1$ when their supports are disjoint (`tools/dev_env/byte_signature.py:96-99`).

## 3. Validity by split-half

$D(P_A,P_B)$ between two corpora means nothing until you know the resolution of the estimator at that sample size. Split each corpus at its midpoint and measure it against itself:

$$D_{\text{self}}(T) \;=\; D\bigl(P_{T[0:m/2]},\; P_{T[m/2:m]}\bigr)$$

A between-corpus reading is interpretable when

$$D_{\text{self}}(T) \;\ll\; D(P_T, P_{T'}) \quad \forall\, T' \neq T$$

and is uninterpretable when $D_{\text{self}}(T) > \max_{T'} D_{\text{self}}(T')$, which says the corpus is too small to distinguish from noise (`tools/dev_env/byte_signature.py:162-196`).

Measured on 20 corpora cut to 6707 bytes each: $D_{\text{self}}$ ranged $0.1118$ to $0.3192$, mean $0.2361$.

## 4. Support correction

$D_{\text{self}}$ falls as the distribution concentrates, independently of the language. Report support and entropy alongside it:

$$\mathrm{supp}(P) = \bigl|\{\,k : P(k) > 0\,\}\bigr|, \qquad H(P) = -\sum_{k} P(k)\log_2 P(k)$$

Across those 20 corpora, $\mathrm{supp}$ ran $193$ to $970$ and tracked $D_{\text{self}}$ almost monotonically. A corpus in a low-support encoding looks internally consistent for arithmetic reasons. Any ranking of $D_{\text{self}}$ across different writing systems is a ranking of $\mathrm{supp}$ until shown otherwise (`tools/dev_env/byte_signature.py:157-175`).

## 5. Corruption against a reference inventory

Given the character sets $S = \{s_1 \dots s_q\}$ that carry the distinctive parts of a writing system:

$$\mathrm{sets}(T) = \sum_{s \in S} \mathbf{1}\bigl[\,\exists\, c \in T,\ c \in s\,\bigr], \qquad \mu(T) = \frac{10^3}{|T_\alpha|}\bigl|\{\,c \in T : \mathrm{comb}(c)\,\}\bigr|$$

where $T_\alpha$ is the alphabetic subsequence and $\mathrm{comb}$ marks combining characters. Extraction loss drops combining marks first, so $\mu \to 0$ with $\mathrm{sets} \ll q$ identifies a corrupted file whose surviving text is still well-formed (`tools/dev_env/salish_purity.py:57-71`).

Run on 60 extracted papers with $q=7$: one file scored $\mathrm{sets} \ge 5$ with $\mu > 0$. The rest lost the marks entirely.

## 6. Null by permutation

To separate a real partition from the arithmetic of splitting a key space, permute the labels within each pre-split group, holding cell counts fixed:

$$\pi^{\ast} \sim \mathrm{Unif}\bigl(\mathcal{S}(\text{labels within group})\bigr), \qquad \Delta = \mathrm{E}\bigl[\,r(\pi^{\ast})\,\bigr] - r(\pi_{\text{obs}})$$

$\Delta \le 0$ means the observed split bought nothing a random split of identical shape would not (`tools/dev_env/case_or_splitting.py:110-131`). Over 19 corpora capped to 60000 tokens, $\Delta$ ranged $+0.0056$ to $+0.0901$, with null scatter $\le 0.0133$ over 5 draws.

## 7. Clustering and cophenetic check

Average-linkage agglomeration over $D$. A tree can be built from any matrix, so report the correlation between the cophenetic height $h(i,j)$ at which $i$ and $j$ first join and the measured distance:

$$\rho_c \;=\; \mathrm{corr}\bigl(\,D(i,j),\; h(i,j)\,\bigr)_{i \lt j}$$

Low $\rho_c$ means the tree imposes structure the distances do not carry, and the output is an ordering with no groups in it (`tools/dev_env/cluster_profiles.py`). Measured $\rho_c = 0.8406$ over $171$ pairs on 19 languages.

## 8. Family control

Languages are not independent draws. Sampling one per family defeats the shared-history term:

$$\hat{\pi} \;=\; \frac{1}{d}\sum_{t=1}^{d} \frac{1}{|F|}\sum_{f \in F} \mathbf{1}\bigl[\,h(x_{f,t})\,\bigr], \qquad x_{f,t} \sim \mathrm{Unif}(f)$$

over $d$ draws and family set $F$. Report $\hat{\pi}$ with its across-draw standard deviation (`tools/dev_env/evidential_pressure.py:65-78`). Run on 418 languages across 121 families, $d=300$: area rates $0.089$ to $0.716$ with scatter $0.029$ to $0.069$.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-03
