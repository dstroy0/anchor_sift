# Experiments: reproducing Duraiswami's matched core

The goal is to show that our system and Duraiswami's matched core (arXiv 2609.17642, Section 7) are the same
solution. Our forms converge onto his printed numbers, or to within the places he printed them with, as the series
order and the blend's terms grow:

All of his runs here take h = 0.01, c = 0.2, X_a = 1 and X_b = 2.

The exterior tail of S, c^2 X_b^(-2h) / (4h), is 0.99. It needs no fit.

The 8-parameter optimum: F_0 and U_0 in span(T_0, T_1, T_2) of eta, and the annulus return flow
(b_0 + b_1 eta) psi(X):

| quantity               | his value                     |
|------------------------|-------------------------------|
| F_0                    | 0.244 + 0.034 eta - 0.058 T_2 |
| U_0                    | 0.450 + 0.004 eta - 0.034 T_2 |
| b_0                    | -2.01                         |
| b_1                    | not printed                   |
| root-mean-square       | 0.077                         |
| with 13 parameters     | 0.039                         |

The 32-parameter matched core: F_0 and U_0 to T_4 (10), annulus axial content 2 x 6 (12) and annulus swirl content
2 x 5 (10):

| quantity                 | his value | where            |
|--------------------------|-----------|------------------|
| F_0 at eta = 0           | 0.336     | X = 0            |
| U_0 at eta = 0           | 0.452     | X = 0            |
| F_0 at eta = 1           | 0.214     | X = 0            |
| return flow              | -2.06     | the annulus      |
| largest abs U            | 0.60 / 1.9 | core / annulus  |
| root-mean-square         | 1.2e-3    | the six functions |
| worst                    | 3.7e-3    | the six functions |
| pressure datum           | 5e-13     | consistency      |

His family, as his code writes it:

- F_0 and U_0 are Chebyshev sums in eta.
- The annulus axial content is psi_b(X; X_a, X_v) times sum over j, k of U_jk T_j(s_v) T_k(eta), with
  s_v = 2 (X - X_a) / (X_v - X_a) - 1. The swirl content is psi_b(X; X_a, X_b) times sum over j, k of F_jk T_j(s_b)
  T_k(eta). psi_b = e^(4 - 1/(s (1 - s))) on 0 < s < 1, which is ode_series_bump.
- The six matching functions of eta are the net torque X tau_theta(X_b), the net force sqrt(X) tau_z(X_b), M(inf),
  J(inf), S(inf) with the exterior tail taken off, and int_0^inf (H - H_pow) dX.

## Rules for every experiment

- Every value is an exact form: rational coefficients times rational powers of one held e times held atoms.
- The atoms (E1, w(z_c) and w'(z_c), rho, the tail integral) are never evaluated. Where a form meets one of his
  decimals, his decimals define the atoms: the atom values his printed numbers imply are solved for exactly, and
  his other printed numbers are the check. They agree, or the disagreement is recorded.
- A subject is measured by 8 witnesses at the corners of a cube around it. The 8 corner forms give the 8 components:
  the value, 3 edge differences, 3 face differences and 1 body difference, each a whole form.
- For each term, the number of the 8 components it needs is recorded as its character and is not interpreted.
- A check passes or fails only where the answer is exact: a residual is 0 or it is not. Everything else is recorded.
- Every whole form, all 8 corners, is written to `records/`, tracked and committed with the work.

## 0. Ground work

- 0a. Dense magnitude arrays. A form is one array of exact integers over a shared index, the power of e and then
  the atom powers, with one denominator per form. Check: join_datum, join_series and axis_heat give the same forms
  term for term as the map. Recorded: entries and bits per entry.
- 0b. Module objects built once per width and linked into each driver, each rebuilt only where its source or a
  header it reads is newer.
- 0c. The witness cube module: a subject of 3 rational parameters, a center and a half-edge from the cfg, the 8
  corner forms, the 8 components, and each term's count. The record writer writes every form whole.

## 1. The cube on subjects already known

e^(-1/s), psi, the Kummer w, x^h, and A K and A J from axis_heat. Check: the 8 components equal the matching
combinations of the Taylor coefficients already held, exactly.

## 2. The axis core

The subject is F, U and Pi over (X, eta, h), the cubes centered at X = 0, eta = 0 and eta = 1. Recorded: the
difference of the forms at order K and K + 1 for K = 40, 60, 80, and the ratio and root estimates at each order,
beside his radius of 3.9 to 4.0.

## 3. The datum against the join's own choices

The subject is the right side of Pi_0 over (X_a, X_b, eta). The answer depends on eta; the X_a and X_b components
measure how much the join's placement puts into it. A sweep over blend terms, orders and cuts records the
difference forms.

## 4. The annulus family and the six identities

Both sides of each identity as exact forms, the difference reduced in the atoms. Every term left in the difference is
recorded: those are the terms the identity drops.

## 5. The fits

His parameters enter the series polynomially and the Jacobian is exact. Exact Gauss-Newton on the six functions,
the atoms defined by his decimals.

- 5a. The exterior tail, c^2 X_b^(-2h) / (4h) at his values, against 0.99.
- 5b. The 8-parameter optimum. His printed F_0, U_0 and b_0 are put in exactly and b_1 is solved for. Check: the
  root-mean-square converges onto 0.077, and a fit over all 8 lands on his printed coefficients within his places.
- 5c. The 32-parameter matched core. Check: the forms converge onto every value in the 32-parameter table.

## 6. The Pi_0 fixed point

Y = G(p) - p and DG(p) at the polynomial p as exact forms on the Chebyshev basis. Z waits on the ellipse space in
the workbook.

## 7. The axis heat with every term

The dissipation with the axial shear and the radial strain, integrated on the full core. The difference from
Proposition 20's swirl-only result is recorded term by term. Cubes over (q, h, Pr) centered on his run's values
and on water at 20 C.

## Order

0, then 1, then 2 and 3, then 4, then 5 and 6, then 7.
