# Notes on the sources the millennium workbook names

Each source has a section. A note gives the page or section of the source, what it says there, and
which entry of the workbook or the research paper it bears on. A note quotes only what the page
shows. Text taken from a PDF loses some mathematics, and a note that depends on a formula says
whether the formula was checked on the rendered page.

## Lienstromberg, Schiffer and Schubert, arXiv:2312.03546v2

Read from the LaTeX source arXiv gives for v2, sections 1 to 9, with the macros of `1main.tex`.

- Section 1, system (1.1). The paper works on the torus $\mathbb{T}_d$, "which might be seen as the
  cube with periodic boundary conditions", and says this is "assumed for technical reasons" and
  that most results "should still hold true for Lipschitz domains". The paper that the workbook
  cites for putting a magnitude in place of a constant keeps the box. Bears on Proposition 6 and
  on the entry "Never put the fluid in a box".
- Section 1, after (1.3). "Although many liquids and gases, such as water and air, may reasonably
  be considered Newtonian, many real fluids are in fact non-Newtonian." The paper holds water to
  be Newtonian and does not test it. Bears on the open entry "Friction is not linear, anywhere":
  the source does not support it for water.
- Section 1, the power law $\mu(|\varepsilon|) = \mu_0|\varepsilon|^{p-2}$, $p > 1$; $1<p<2$ is
  shear thinning, $p>2$ shear thickening, $p=2$ Newtonian. The Ellis law (their (1.4)) is named
  as a better model for shear-thinning fluids, Newtonian at low and high shear.
- Section 1, the functional $I_\eta$. It carries a stabilizing term $\tfrac{C_4}{4}|\nabla u|^4$
  that the authors call "quite unphysical and only used for the mathematical analysis", and say
  is necessary for small $p$, "even for the Newtonian case $p=2$ in three dimensions".
- Theorem A (their Theorem 2.7): for $p > 2d/(d+2)$, minimizers converge weakly to a Leray--Hopf
  solution. Theorem B (their Theorem 5.2): for $p > (3d+2)/(d+2)$, which is $11/5$ when $d=3$,
  and $W$ strictly convex, the convergence is strong and the limit obeys the energy equality.
  This matches what the research paper states.
- Section 1, closing paragraph. Existence of solutions obeying an energy equality for $p >
  (3d+2)/(d+2)$ "can be traced back to Ladyshenskaya", cited as Lady1, Lady2, Lady3, and "Even in
  the Newtonian case, it is still unclear whether there exists a solution obeying an energy
  equality even for very regular initial data." This matches the research paper.
- Section 2.1, the potential $W$. The stress is $\sigma = -\pi\,\mathrm{id} + DW(\varepsilon) =
  -\pi\,\mathrm{id} + 2\mu(|\varepsilon|)\varepsilon$, called "generalized Newtonian". The
  viscosity depends on $|\varepsilon|$ alone. No temperature and no bulk viscosity enter, and
  $\mathrm{div}\,u = 0$ is kept. The paper keeps one dropped dependence and leaves the others of
  the table of terms to put back out.
- Section 2.1, notation. $(u\cdot\nabla)u$ and $\mathrm{div}(u\otimes u)$ are used as one term
  "due to the incompressibility condition".
- Section 2.1, the potential for the Ellis law (their (1.4)) has $p = (\alpha+1)/\alpha$, and
  $\mu(s) \sim \mu_0\min\{1, (\mu_0 s/\tau_{1/2})^{(1-\alpha)/\alpha}\}$. The Ellis law is
  Newtonian at low shear and a power law at high shear, with $p < 2$ there.
- Section 2.2, Proposition 2.4. For $p > (3d+2)/(d+2)$ every Leray--Hopf solution is an energy
  solution. In $d = 3$ the threshold is $11/5$; in $d = 2$ it is $2$.
- Section 2.3, the initial value is taken with zero mean, "without loss of generality since other
  averages can also be considered, e.g. by a change of coordinates". A Galilean change removes a
  uniform drift on the torus.
- Sections 2.4 to 3.2: interpolation, minimizers, Euler--Lagrange equations, a priori bounds. The
  bounds are uniform in $\eta$ and hold on the torus. Nothing here bears on a workbook entry.
- Section 3.3, opening. A proof under an extra $L_\infty$ bound on $\nabla u_\eta$ is given "for
  the purpose of exposition", and the authors say "such a bound is not true in reality". The step
  that identifies the limit of the viscous term "is clear if $DW$ is a linear function, meaning
  that the fluid is Newtonian". The term that is linear for a constant viscosity is the term that
  needs the hard part of the paper once the viscosity varies.
- Section 3.3, Lemma 3.6 (their label `lukaspodolski`). Weak convergence on a bounded domain fails
  through oscillations or concentrations. The authors state that their identity (claim
  `baumgart`) "fails for $p < (3d+2)/(d+2)$ if the additional $L_\infty$ bound is dropped".
- Section 4, the general proof by solenoidal Lipschitz truncation. It is technical and has no
  physical content. Nothing here bears on a workbook entry.
- Section 5, opening. Oscillations "will likely destroy" weak convergence of the viscous term for
  a non-Newtonian fluid. Concentrations do not. Existence results trace to Ladyzhenskaya and
  Lions; non-uniqueness to Buckmaster and Vicol (their BV19, BMS).
- Section 5, after Lemma 5.1. A convex potential with $W(\varepsilon) = 0$ for $|\varepsilon| < R$
  gives zero shear stress at low rates of strain, and the equation is then the incompressible
  Euler equation there, which "allows for oscillations" (their DL09). Strict convexity is assumed
  to exclude this.
- Section 5, before Theorem 5.3. For $2d/(d+2) < p < (3d+2)/(d+2)$ the energy equality "is not
  automatically satisfied, as the flow might develop anomalous dissipation". The Newtonian case
  $p = 2$ in three dimensions lies in this range. Bears on Proposition 5 of the research paper and
  on the entry "An unbounded value is a sign that an assumption has left the fluid": the source
  names the same gap in its own terms and does not say it is a sign of anything.
- Section 5, Remark 5.4. The stabilizing term can be dropped for $p \ge 4$. Uniqueness of
  Leray--Hopf solutions for $p < (3d+2)/(d+2)$ "is still an open problem" (their BV19). For
  Newtonian fluids the weak convergence of $DW$ is "trivial" because it is linear.
- Appendix, the truncation. Maximal functions, Whitney cubes, a partition of unity, and a potential
  $\mathrm{curl}^*$ to keep the divergence zero. It is technical and has no physical content.
- Bibliography (`1main.bbl`). Ladyzhenskaya: Trudy Mat. Inst. Steklov. 102 (1967) 85--104; Zap.
  Nauchn. Sem. LOMI 7 (1968) 126--154; *The mathematical theory of viscous incompressible flow*,
  Gordon and Breach (1969). Buckmaster and Vicol, Ann. of Math. 189 (2019) 101--144.

What changes. The research paper and the workbook hold that this paper keeps a magnitude where
equation (1) keeps a constant, and that it proves the energy equality for $p > 11/5$. Both stand.
Three things the workbook does not say and should: the paper keeps the periodic box "for technical
reasons"; it treats water as Newtonian; and for the range that contains $p = 2$ in three
dimensions it says the flow "might develop anomalous dissipation".

## Barber, Hiller, Löfstedt, Putterman and Weninger, Physics Reports 281 (1997)

Read from the text layer of the scanned PDF, which is an optical reading of the page. The
equations do not survive it; a note that rests on an equation says so.

- Section 1. In sonoluminescence "the resulting fluid mechanical motion sets up a transformation
  of the sound energy into degrees of freedom, visible photons, which are not describable by the
  original equations of fluid mechanics." The acoustic energy density is concentrated by twelve
  orders of magnitude. Bears on I11 and on the thesis of the research paper chapters: the source
  says, in its own words, that the motion leaves what the continuum equations describe.
- Section 1, Fig. 1. The flash is under 50 ps; the outgoing acoustic spike under 20 ns; the
  maximum radius about 45 µm; drive about 1.2 atm; about $2\times10^5$ photons per flash for air
  in water.
- Section 1. Light intensity rises a hundredfold from 40 °C to 0 °C. Matches the workbook row.
- Section 2. "A magnetic stirrer accelerates the degassing by creating turbulent voids which
  increase the area of the fluid/gas interface." Stirring opens voids in the liquid. Bears on I7
  and I8, on stirring and the bottom of a column.
- Section 2. The sealed cylindrical resonator removes the free surface; a NiCr wire boils the
  liquid locally to seed a bubble.
- Section 3. The bubble wall collapses at about Mach 4 relative to the ambient speed of sound in
  the gas, and the acceleration that stops it exceeds $10^{11}\,g$, checked on the rendered page, p. 78.
  Fig. 10 there gives $R_c/R_0 \le 1/8$. The flash comes within 500 ps of
  the minimum radius. The minimum radius is limited by the van der Waals hard core of the gas.
- Section 4. Except for about 200 ns near the minimum radius, the wall speed is under a tenth of
  the gas sound speed, and for 99.5 percent of the cycle low-Mach hydrodynamics describes the
  motion. The Rayleigh--Plesset equation (their (5)) is used. Fits take an effective damping of
  0.04 g/(cm s), four times the tabulated viscosity of pure water, "due to impurities in the
  water", and surface tension 50 dyne/cm.
- Section 4. Near the minimum radius the timescale is about a hundred picoseconds, "outside of the
  validity of the hydrodynamic approximations which led to the derivation of the RP equation";
  "while the RP is rich in mathematical implications at these parameters, it misses the physics
  essential to SL." Later: once the wall reaches a speed comparable to the speed of sound, "more
  complete equations of state (or microscopic theories) and nonlinear dynamics must be employed."
  Bears on the entry "An unbounded value is a sign that an assumption has left the fluid": this
  source names a fluid equation leaving its own validity at the moment of collapse.
- Section 4, Fig. 17. The outgoing acoustic pulse is about 3 atm at 1 mm, and over 6000 atm at
  the point of emission after correcting for spreading. Only 0.01 percent of the acoustic drive
  input leaves as light.
- Section 4. The asymmetry between slow expansion and fast collapse "sets the arrow of time for the
  SL process". The empirical criterion for light: the collapse reaches Mach 1 relative to the
  sound speed in air at the ambient radius, which gives $R_{\max}/R_0 \approx 10$. Fig. 19: the
  expansion ratio rises from 3.5 to 9 across the threshold. Bears on I1, on alignment: the
  threshold here is set by an expansion ratio, and phase alignment is not named as the cause.
- Section 4. Surface tension is small in the bubble dynamics except for small bubbles, where it
  can suppress the onset of light because the critical expansion ratio is not reached.
- Section 5. A small percentage of noble gas is essential; pure N$_2$, pure O$_2$ and 80:20 give
  no stable signal; air is 1 percent argon. The doping effect in oxygen "indicates that we are
  here dealing with the physics of atoms and plasmas as opposed to, say, effects of chemical
  reactions". Bears on I12: the source places the light in the physics of atoms and plasmas.
- Section 6. Diffusion of gas sets the ambient radius of a bouncing bubble. For air in water the
  SL bubble violates the diffusion prediction by about a factor of 50, which points to "an as yet
  undetermined mass flow process".
- Section 6, Figs. 26 to 37. At higher partial pressures noble-gas bubbles grow each cycle and then
  "somehow become unstable and split off microbubbles", seen as glitches in the phase of the
  flash. The authors' "logical, but unproven, deduction" is an unknown non-diffusive mass flow;
  candidates are gas carried off by the outgoing shock, or a macroscopic mass convection cell that
  breaks the spherical symmetry. They suggest the extra flux comes with the outgoing acoustic
  spike, and that the mechanism "lies outside chemistry". Bears on I2 and on the chain to
  microcavitation: a light-emitting bubble sheds microbubbles, and the source names that as a
  mass flow it cannot yet explain.
- Section 6, Fig. 32. In a bouncing bubble that emits no light the maximum temperature at
  collapse is about 1000 K.
- Section 6. A quiescent 5 µm air bubble dissolves in about a third of a second (Epstein and
  Plesset); an SL bubble decays in about a tenth of a second after the sound stops.
- Section 7. In non-aqueous fluids light is weaker and the bubble jitters a few mm. Light rises as
  temperature falls in every fluid tried: from 40 °C to −6 °C for air in water by over a factor of
  100, correlated with a higher drive level the bubble survives. "It seems to be fortunate
  happenstance for the discovery of SL that room temperature is not 20 °C hotter." Static pressure
  of one atmosphere gives the most stable SL; at a quarter atmosphere the focusing would be an
  order of magnitude greater than the Section 1 estimate; SL has been seen down to a third of an
  atmosphere. At 4 to 5 atm tap water gives stable SL. Bears on I6 and I9 (pressure as the second
  shared variable) and on the row that says nine of thirteen rows carry temperature.
- Section 7. Solubility "does not appear to be of crucial importance"; the fluid's vapor
  pressure and dielectric constant may matter. Helium in liquid argon is proposed as a simple
  test system, "if it were attempted".
- Section 8. The spectrum is broadband with no spectral lines at 10 nm resolution, and it rises
  into the ultraviolet down to 190 nm, almost 6.5 eV, where water cuts it off. Water does not
  become transparent again until the X-ray range. Swan lines of excited carbon are absent. If the
  spectra are windows on one shape, helium at 20 °C would peak above 150 eV, and "the existence
  of such energetic photons cannot be ruled out experimentally at this time". Bears on I11: the
  light is broadband, with no line set to name a source.
- Section 9. The flash is shorter than 50 ps; the jitter between flashes is under 50 ps, better
  than a part per million of the acoustic period, while the resonator's quality factor is about
  1000. The brightest signal has over $10^7$ photons per flash, a peak power over 100 mW.
  Transient SL from clouds of cavitating bubbles (Frenzel and Schultes 1934) shows spectral lines,
  and whether it is the same physics as a single trapped bubble "remains to be seen". Bears on I1
  and on the seiche analogy: the source names the clockwork regularity as "surely remarkable" and
  does not attribute it to alignment.
- Section 10. Neon SL shows none of the lines of a neon discharge. "The absence of lines in SL
  strongly suggests that the SL bubble is very hot and/or very stressed so that the comparison with
  other luminescence phenomena may be misleading. One can wonder if in fact SL is a thermal
  phenomenon and if its correct name would have been 'sonoincandescence'." Candidate mechanisms:
  blackbody radiation, bremsstrahlung from unbound electrons in a gas hot enough to be ionized but
  rarefied enough to be transparent, and chemiluminescence. Adiabatic heating gives 5000 to
  10000 K and "does not focus energy sufficiently" to explain the ultraviolet spectrum. Bears on
  I11 and I12 directly: heat and light together, and ionization of the gas named as a candidate.
- Section 10, the shock model. The supersonic inward wall launches a shock into the gas; the
  Guderley similarity solution of the Euler equations, with viscosity neglected, has the shock's
  Mach number go to infinity as it reaches the origin. Behind it $T/T_0 \approx M^2$, and on the
  rebound the gas is heated again, to roughly $M^4$. The similarity solution "is invalidated when
  ionization effects become important". Bears on the research paper's thesis: a fluid equation
  with a term dropped (viscosity) produces an infinite value at a point, and the source says the
  physics leaves the equation before the infinity is reached.
- Section 10, scaling estimates. For $M = 4.3$ and $R_0 = 4.5$ µm: $T \approx 10^5$ K, shock radius
  0.15 µm, about 100 ps. For $M = 24$: radius 30 Å, 0.3 ps, $T \approx 10^8$ K, "hot enough for
  fusion if it happened in a deuterium bubble"; whether the shock holds itself together down to
  such radii "remains to be seen", and "the shock surface has not yet been experimentally
  detected". The exponents and equations (53) to (58) were checked on the rendered page, p. 127.
- Section 10, bremsstrahlung. "The temperatures reached by the shock heating suggest that the gas
  in the bubble forms a dense ionized region. The free electrons released by the heating will
  accelerate and radiate light as they collide with the ions." With $M = 4$ and ionization near
  unity, the model gives about $10^7$ eV per flash, "in rather good agreement with experiment".
  Corrections for "a dense cold plasma" should be considered. Bears on I12: the source states the
  gas in the bubble as ionized, a plasma, and the light as radiation from its free electrons.
  This is the model the source calls "the most complete candidate", and it says the model "is,
  however, far from satisfactory".
- Section 10. "Since the light emission occurs as a (mathematical) singularity is forming, any
  transport process which a theorist chooses to incorporate in this model can affect the result."
  Bears on the research paper's thesis: the source says, of a forming singularity in a real
  fluid, that the terms kept or dropped decide the answer.
- Section 10. SL is relatively unaffected by a 20 T magnetic field. Whether Planck's constant
  enters is open; Schwinger's zero-point proposal, Unruh radiation (powers too small by many
  orders), discharge from charge separation (compared to ball lightning), and fracto- or
  triboluminescence from a cracking gas shell are listed.
- Section 11. The flash is uniform over a spherical shell from a region smaller than its own
  wavelength. A 7 percent dipole in the angular correlation is explained by a 20 percent
  ellipticity of the bubble; the dipole has a memory as long as the free decay of the sound field.
  Upper bound on ellipticity in the narrow state about 3 percent.
- Section 11. Shape perturbations are expanded in spherical harmonics $a_\ell(t)$ (their (64)).
  Collapse is Rayleigh--Taylor stable, with growth at most a factor of 3, and viscosity damps the
  harmonics between flashes in under 1 µs. "Therefore, there no usable energy is stored inside the
  bubble during a cycle." Bears on the spherical-harmonics entry of the first observation and on
  I1: the source reads the shape of the collapse from spherical harmonics, and finds that no shape
  energy is carried from one cycle to the next.
- Section 11. The upper threshold of SL is due "either to some other hydrodynamic instability or to
  an event occurring at the moment of collapse which is not describable by the hydrodynamics".
  Jets, pinch-off, anomalous diffusion and resonator imperfections are left open.
- Section 12. "We do not yet know the complete set of experimental parameters that must be
  controlled so as to render experiments on SL reproducible from lab to lab." Of four quartz
  spheres alike to one percent, one gives a poor resonance and unstable light. Pure water's
  resistance drops within minutes in air, and damping and surface tension change with it.
  Hydrogen and deuterium spectra in heavy water fit a black body at 6000 K and may be impurity.
  "Pending the ascendancy of a falsifiable theory, the next set of SL discoveries might instead be
  driven by engineering improvements." Bears on I9 and on transitivity: a phenomenon reproducible
  in one laboratory is not yet reproducible from laboratory to laboratory, and the source says
  why.
- References. Frenzel and Schultes, Z. phys. Chem. B27 (1934) 421; Guderley, Luftfahrtforschung 19
  (1942) 302; Rayleigh, Phil. Mag. 34 (1917) 94; Plesset, J. Appl. Mech. 16 (1949) 277;
  Prosperetti, Quart. Appl. Math. 34 (1977) 339; Schwinger, PNAS 90 (1993) 2105, 7285.

What changes. I11 was scored on the abstract and section 1 and stands. I12 gains a source held and
read: section 10 states the gas forms "a dense ionized region" whose free electrons radiate the
light, and names this the most complete candidate while calling it far from satisfactory. That is
a statement of the claim by the source, short of a measurement; I12 is to be scored on it, and the
Flannigan and Suslick measurement is still wanted. Section 10 also gives the research paper a
second instance, beside Proposition 5, of a fluid equation that reaches an infinity at a point
where the source says the physics has left the equation.

## Duraiswami, arXiv:2609.17642v1 (15 September 2026)

*Self-similar swirl between contracting porous walls: the GD1998 exact Navier--Stokes solution
revisited in the similarity variables of the OpenAI 2026 forced blow-up construction.* Located
while searching for the 0.7 nanometer report, and read in full from the text layer, 31 pages.

- Abstract. The study asks whether the forced construction is computable and whether it can be
  related to an experiment. "The blow-up is energetically free, the anomalous factor $\theta^{-h}$
  is 1.4 at $\theta = 10^{-15}$, and the first continuum assumption to fail is cavitation in a
  liquid and compressibility in a gas, both while $\theta^{-h}$ is within 12% of unity."
- Section 1. "A real fluid leaves the equations' description long before the singularity; and
  nothing here bears on the unforced equations that engineering practice solves."
- Section 2. "The proof was produced by an automated system and is accompanied by a Lean 4
  formalization; as of 12 September 2026 there was no refereed independent verification."
- Section 7. Imposing the moment identities of the construction shows the core "cannot be met by a
  core symmetric about the dividing plane": the core is an axial through-flow. The cone condition
  of the construction is Rayleigh's centrifugal criterion with axial shear, and it places the
  annulus at similarity radii of order $10^{20}$: "a statement about the asymptotic regime of the
  proof, not about a flow one could compute or build."
- Section 7, axis pressure deficit. The deficit $\Pi(0,0) - \Pi(\infty,0)$ is $0.34$ to $0.61$
  times $u_{\max}^2$ for the computed profiles.
- Section 8, Table 7. In the core: peak swirl velocity $\sim \tau^{-1/2-h}$; core radius
  $\sim\tau^{1/2}$; kinetic energy $\sim\tau^{1/2-3h}$, vanishing; dissipation rate
  $\sim\tau^{-1/2-3h}$, with finite time integral. "The blow-up is energetically free." These
  match the research paper's Proposition 5.
- Section 8, which continuum assumption fails first. "In a liquid it is cavitation, at a core
  radius near a millimeter for laboratory scales; in a gas it is compressibility, near thirty
  micrometers; molecular scales are never reached." For water with an initial swirl of 1 m/s at a
  radius of 1 cm, the axis deficit reaches one atmosphere at $u \approx 10$ m/s (12.8 to 17.1 m/s
  on the computed profiles), a core radius of 0.6 to 1 mm. "Viscous heating is negligible there":
  the temperature rise over the remaining collapse time is "of order 50 J/kg / 4×10³ J/(kg K) ≈
  0.01 K". "Molecular scales (0.3 nm) lie eight decades below the initial radius and seven below
  the inception radius." In air, the Knudsen number based on a mean free path of 68 nm reaches
  $10^{-2}$ at 7 µm and $10^{-1}$ at 0.7 µm. "Physically realized, the forced blow-up is a
  cavitating vortex in a liquid and a shocking one in a gas."
- Section 8, the experiment. A swirl chamber with porous walls driven toward collapse, with axis
  cavitation inception and loss of the steady state at the fold as observables.
- Section 9. "Nothing found suggests that the mechanism is reachable in a flow one computes or
  builds, and the forced theorem says nothing about the unforced equations of engineering
  practice."

What changes.

1. The 0.7 nanometer report. This source is the nearest found, and it does not say it. It puts
   the first failure in water at cavitation near a millimeter, gives 0.3 nm as the molecular
   scale, and gives 68 nm and 0.7 µm only for the mean free path and Knudsen number in air. The
   report's "0.7 nanometers" and "70 nanometers" read as these two air figures with their units
   changed. The entry stays "by report" with its source still not located; this source is to be
   recorded beside it as one that bears on it and does not support it.
2. The scaling estimate of the first workbook chapter. The estimate puts the dropped viscosity
   term on a par with the kept one above $U^* \approx 110$ m/s at 20 °C. This source puts
   cavitation in water at 10 to 17 m/s and the temperature rise of viscous heating at 0.01 K. On
   this source's numbers the fluid cavitates well below $U^*$. Cavitation, not the dropped
   temperature term, is the first assumption to fail in water. The estimate stays theory; this is
   to be entered beside it.
3. Transitivity and I9. This source proposes the laboratory realization the author asked about,
   and predicts that it shows axis cavitation, a known phenomenon, and not a blowup. That is
   consistent with the author's claim that the breakdown is not seen in vessels, and gives the
   reason in the source's terms: the fluid leaves the equation first.
4. Microcavitation as the culmination of the chain. The source names cavitation as what a real
   liquid does with the forced singularity. This bears on the chain in the terms-to-put-back
   chapter and on I2.

## Flannigan and Suslick, Nature 434 (2005) 52--55

*Plasma formation and temperature measurement during single-bubble cavitation*, the published
pages from the Zenodo record 895438, read from the text layer, 4 pages. The two-column layout
interleaves the neighboring letters on the same pages; only this letter is noted.

- Opening. Single-bubble sonoluminescence "results from extreme temperatures and pressures achieved
  during bubble compression; calculations have predicted the existence of a hot, optically opaque
  plasma core with consequent bremsstrahlung radiation. However, there has been previously no
  strong experimental evidence for the existence of a plasma during single- or multi-bubble
  sonoluminescence."
- The measurement. In 85 wt% sulphuric acid under argon the flash is 2,700 times as intense as in
  water under argon; the acid has very low vapor pressure and is transparent down to 200 nm.
  Argon atom emission lines give temperatures of 8,000 ± 1,000 K at 2.3 bar, 10,700 ± 1,300 K at
  2.5 bar, and 15,200 ± 1,900 K at 2.8 bar.
- The finding. The argon excited states are about 13 eV above the ground state and "cannot be
  thermally populated at the measured Ar emission temperatures (4,000--15,000 K)"; the ionization
  energy of O$_2$ is more than twice its bond dissociation energy. O$_2^+$ "likewise cannot be
  thermally produced. We therefore conclude that these emitting species must originate from
  collisions with high-energy electrons, ions or particles from a hot plasma core." O$_2^+$
  emission needs over 18 eV; "to our knowledge, this is the first example of emission from any ion
  in any sonoluminescence spectrum under any conditions."
- Thermal conductivity. Mixtures of Ar and Ne move the temperature from about 15,000 K down to
  1,500 K: "bubble collapse is only approximately adiabatic, and in SBSL, thermal conductivity of
  the dissolved gases is a critical experimental parameter." Bears on the table of terms to put
  back: the heat conducted out of the gas decides the temperature reached. The conduction term
  sets the outcome at collapse.
- Shock heating. "The limiting emission temperature of an intense shockwave in air is only
  ~17,000 K," and shock-heated argon plasmas have line temperatures below about 20,000 K.
- The continuum. The ultraviolet continuum "may be partially blackbody radiation from the emitting
  shell surrounding an optically opaque core, and partially bremsstrahlung due to ionization. It
  could also be due to ion–electron recombination, which is likely to be present in a dense
  plasma."

What changes. I12 now has a measurement held and read. The light is emitted by species that only
a plasma can excite, and the source concludes there is a hot plasma core. That is the author's
claim, measured: I12 is to be scored a hit on this source. It also bears on I11: light and heat
come together, the plasma at 15,000 K in a liquid held at room temperature.

## Leray, Acta Mathematica 63 (1934) 193--248, in Terrell's translation, arXiv:1604.02484

The translation sets each page of the French beside its English. Read in the English, with the
French consulted where the text layer breaks a formula.

- Introduction I. "The theory of viscosity leads one to allow that motions of a viscous liquid are
  governed by Navier's equations. It is necessary to justify this hypothesis a posteriori by
  establishing the following existence theorem." Leray treats the equation as a hypothesis about
  the liquid, to be justified, not as given. Bears on the research paper's thesis.
- Introduction I. "I have indicated a reason which makes me believe there are motions which become
  irregular in a finite time. Unfortunately I have not succeeded in creating an example of such a
  singularity." Leray expected blowup.
- Introduction I. "In fact it is not paradoxical to suppose that the thing which regularizes the
  motion, dissipation of energy, does not suffice to keep the second derivatives of the velocity
  components bounded and continuous. Navier's theory assumes the second derivatives bounded and
  continuous. Oseen himself had already emphasised that this was not a natural hypothesis." A
  solution that may lack those derivatives Leray calls "a turbulent solution".
- Introduction I, footnote quoting Oseen. Two kinds of motion: regular, without singularity, and
  irregular, with singularity; "one is tempted from now on to presume that laminar motions
  furnished by experiment are identical to theoretical regular motions, and that experimental
  turbulent motions are identified with irregular theoretical motion. Does this presumption
  correspond with reality? Only further research will be able to decide." Bears on the research
  paper: the identification of a mathematical singularity with a physical event is, in the source,
  a presumption to be tested.
- Introduction I. Each turbulent solution satisfies Navier's equations except at times of
  irregularity, which form a closed set of measure zero.
- Introduction II. The work treats unbounded liquids; the conclusions are "extremely analogous"
  to those for a liquid within fixed convex walls. "The absence of walls indeed introduces some
  complications concerning the unknown behavior of functions at infinity but greatly simplifies
  the exposition and brings the essential difficulties more to light." Bears on the entry "Never
  put the fluid in a box": Leray works without a box and says this brings out the essential
  difficulties.
- Section 10. Leray names $u_i(x,t)$ "the speed of the molecules of the liquid" ("la vitesse des
  molécules du liquide"). The velocity field of the equation is, in the source's words, a velocity
  of molecules. Bears on Proposition 8 (field and molecules) and the averaged-fluid chapter.
- Chapters I and II. Strong and weak convergence in mean, quasi-derivatives (weak derivatives),
  mollification, and the linearized equations solved by the heat kernel and Oseen's tensor, with
  the energy relation (2.21). Analysis with no physical content beyond the above.
- Section 15. "Motions of viscous liquids are governed by Navier's equations (3.1)", with $\nu$ and
  $\rho$ "constants". A solution is regular on an interval when $u$, $p$ and the derivatives in the
  equation are continuous and $W(t) = \int u\cdot u$ and $V(t) = \max|u|$ are bounded by continuous
  functions. A regular solution has derivatives of all orders.
- Section 17, (3.4). The energy dissipation relation $\nu\int_{t_0}^t J^2\,dt + \tfrac12 W(t) =
  \tfrac12 W(t_0)$, with $J^2 = \int u_{i,k}u_{i,k}$. With (3.5) and (3.6) these are the
  "fundamental inequalities".
- Section 18, (3.7). Two regular solutions with the same initial state agree: uniqueness of
  regular solutions. This is the uniqueness the research paper's continuation argument uses.
- Section 19. Existence for a regular initial state on $0 < t < \tau$ with $\tau = A\nu^3 V^{-2}(0)$
  (3.8), by successive approximation. Then: "a solution of Navier's equations, regular in an
  interval $(\theta, T)$, becomes irregular at time $T$ when $T$ is finite and it is impossible to
  extend the regular solution to any larger interval. Formula (3.8) reveals a first
  characterization of irregularities: If a solution of Navier's equations becomes irregular at
  time $T$, then $V(t)$ becomes arbitrarily large as $t$ tends to $T$, and more precisely $V(t) >
  A\sqrt{\nu/(T-t)}$" (3.9). Checked against the French: the exponent is $1/2$, of $\nu/(T-t)$.
  This is the statement the research paper's continuation paragraph cites as Leray's: a solution
  continues while $V$ is bounded. It now rests on a source read.
- Section 20. "It will be important to know whether there are solutions which become irregular."
  If they cannot be found, the regular solution exists for all time. Leray proposes self-similar
  solutions $u(x,t) = [2\alpha(T-t)]^{-1/2}U[(2\alpha(T-t))^{-1/2}x]$ (3.12), solving (3.11), and
  writes: "Unfortunately I have not made a successful study of system (3.11). We therefore leave in
  suspense the matter of knowing whether irregularities occur or not." The forced construction's
  core is self-similar with a different, anisotropic scaling.
- Section 21. Second characterization: $J(t) > A\nu^{3/4}(T-t)^{-1/4}$ at an irregularity. Two
  cases of regularity: a solution never becomes irregular if $\nu^{-3}W V^2$, or $\nu^{-4}WJ^2$, is
  below a constant at some time.
- Section 22. $L^p$ forms, $p > 3$: $\int|u|^p \ge A(1-3/p)^{\ldots}\nu^{\ldots}(T-t)^{-(p-3)/2}$
  and the matching case of regularity. "These cases of regularity show how a solution always
  remains regular if its initial velocity state is sufficiently near rest."
- Sections 23 to 25. Semi-regular solutions: $\int_0 V^2\,dt$ finite and strong convergence in mean
  to the initial state; uniqueness and existence for initial data with square-summable
  quasi-derivatives, or bounded, or in $L^p$, $p > 3$.
- Section 26. "We have not succeeded in proving that the corresponding regular solution to
  Navier's equations is defined for all values of $t$." Leray mollifies the convective velocity
  over a length $\varepsilon$, system (5.1), "very near Navier's equations when the length
  $\varepsilon$ is very short", and shows its solution is regular for all time. Bears on the
  research paper's thesis: the existence theory of the equation is reached by changing the
  equation, and the changed equation is called near Navier's only in the limit.
- Section 27, (5.7). Kinetic energy "remains localized at finite distance": the energy outside a
  sphere is bounded by the initial energy outside a smaller sphere plus a term in $t$.
- Sections 28 to 31. As $\varepsilon \to 0$ a subsequence converges weakly; the limit is a
  "turbulent solution": square-summable, divergence-free, satisfying the weak equation (5.15) and
  $\int_0^t \nu J^2 + \tfrac12 W(t) \le \tfrac12 W(0)$ (an inequality, not an equality), for all
  $t$ outside a set of measure zero. Existence theorem: every square-summable divergence-free
  initial state has at least one turbulent solution defined for all $t > 0$.
- Section 32, footnote. "I have not been able to establish a uniqueness theorem stating that to a
  given initial state, there corresponds a unique turbulent solution." Bears on the
  Lienstromberg note: uniqueness of Leray--Hopf solutions is still open.
- Section 33, structure theorem. A turbulent solution is regular on open intervals whose union
  differs from the half-line by a set of measure zero; the kinetic energy decreases on that set
  and at $t = 0$. "We have had to give up regularity of the solution at a set of times of measure
  zero. At these times the solution is only subject to a very weak continuity condition (c) and to
  condition (b) expressing the nonincrease of kinetic energy." If (3.11) had a nonzero solution,
  $U[(2\alpha(T-t))^{-1/2}x]$ scaled would give a turbulent solution with one irregular time.
- Section 34, (6.4). All singular times precede $\nu^{-5}W^2(0)/(16A_1^4)$: "A motion which is
  regular up to time $\theta$ never becomes irregular" past that bound, and (6.5) bounds the sum of
  the lengths of the irregular gaps to a power. For large $t$, $J(t) < A\sqrt{W(0)}(\nu t)^{-1}$ and
  $V(t) < A\sqrt{W(0)}(\nu t)^{-3/4}$. "I am ignoring the case in which $W(t)$ necessarily tends to 0
  as $t$ becomes indefinitely large."

What changes. The research paper says Leray's 1934 paper "was not read for this chapter". It is
now read, in Terrell's translation with the French beside it, and the continuation paragraph
rests on Section 19: a solution becomes irregular at $T$ only if $\max|u| > A\sqrt{\nu/(T-t)}$.
The sentence is to be changed to cite the paper as read. Three of Leray's sentences bear on the
thesis and belong in the research paper with citation: the equation as a hypothesis to be
justified a posteriori; Oseen's presumption, that experimental turbulence is mathematical
irregularity, as something "only further research will be able to decide"; and the absence of
walls as what "brings the essential difficulties more to light". The last bears directly on the
entry "Never put the fluid in a box".

## Ladyzhenskaya, Trudy Mat. Inst. Steklov. 102 (1967) 85--104

*О новых уравнениях для описания движений вязких несжимаемых жидкостей и разрешимости в целом
для них краевых задач* (On new equations for describing the motions of viscous incompressible
fluids and the solvability in the large of their boundary value problems), from the MathNet.ru
scan `tm2939`. The text layer of the scan is unreadable. Its 20 pages were rendered as images
and read in the Russian; the notes translate.

- Opening. "In my report at the Congress of Mathematicians of 1966 I proposed to describe the
  motions of viscous incompressible fluids by one of the following systems": (0.1) with stress
  $(\nu_0 + \nu_1 v_x^2)v_{x_k}$; (0.2) with $\nu_0 + \nu_1\,\mathrm{rot}^2v$ acting on $\mathrm{rot}\,v$;
  and (0.3) with $\nu(v_x) = \nu_0 + \nu_1\int_\Omega v_x^2\,dx$, a viscosity set by the total
  rate of deformation of the whole flow. $\nu_0, \nu_1 > 0$. System (0.4) uses the symmetric
  deformation tensor and "has the advantage over (0.1) that the deformation tensor in it is
  symmetric."
- Opening. "I shall not discuss here the arguments of a physical character in favour of these
  systems, but shall prove that the boundary value problems for them are uniquely solvable 'in the
  large' and stable over any finite interval of time." The paper proves; it does not argue that
  any fluid obeys these laws.
- §1, (1.1). $A(v_x) = \nu_0 + \nu_1|v_x|^{2\mu}$, in a domain $\Omega \times [0,T]$ with $v = 0$ on
  the boundary; "for inessential simplifications we shall take $\Omega$ to be a bounded domain".
  In the notation of Lienstromberg, Schiffer and Schubert this is $p - 2 = 2\mu$.
- Energy estimates (1.3), (1.4), and a third from multiplying by $v_t$ (1.5). For $\mu \ge 1/5$
  Sobolev's embedding bounds the convective term (1.6), and Gronwall's lemma (Lemma 1.1) closes
  (1.17).
- Galerkin approximations, with the limit in the nonlinear viscous term taken by "the idea of
  Minty and Browder" on monotone operators (1.27): $[A^k(v'_x) - A^k(v''_x)](v'_{x_k} -
  v''_{x_k}) \ge \nu_0(v' - v'')^2_x$.
- Theorem 1.1. Problem (1.1) has at least one generalized solution for every $f \in L_2(Q_T)$
  and initial value in the right space, if $\mu \ge 1/5$. Theorem 1.2: at most one, if $\mu \ge
  1/4$. In the exponent $p$, existence for $p \ge 12/5$ and uniqueness for $p \ge 5/2$.
- Theorem 1.3. The same for (0.2). Theorem 1.4. With $\int_0^\infty\|f\|\,dt < \infty$, solutions
  exist on the whole half-line.
- §2, Theorem 2.1. System (0.3), with $\nu$ depending on $\int v_x^2$, has a unique solution in a
  class with $\max\|v\| + \|v_{tx}\|$ finite. Theorem 2.3: under smoothness of $f$ and $S$ it is
  classical. A change of time variable $\tau = \int_0^t\varphi(\xi)\,d\xi$ turns it into the
  Navier--Stokes system with a time-dependent rescaling (2.16).
- §3, stability. "Solutions found in §§1 and 2 are stable on any finite interval of time. If the
  forces $f(x,t)$ decay with time fast enough, the solutions tend to zero as $t \to \infty$" (3.4).
  Solutions with nearby forces and initial data attract each other when $\nu_0$ exceeds a bound
  set by the solution (3.8).
- §4, stationary problems. Solvable in an arbitrary domain for arbitrary $f$; the flow past a body
  with a constant velocity at infinity (4.18), (4.19). "For the Navier--Stokes equations the
  solvability of stationary boundary problems was proved under the condition that the flux of the
  vector $a$ through each closed boundary surface is zero. For the problems considered here this
  assumption is removed."
- References include Ladyzhenskaya's *Mathematical questions of the dynamics of a viscous
  incompressible fluid* (1961), Minty (1962, 1963), Browder (1965), Leray and Lions (1965).

What changes. The research paper says Ladyzhenskaya's papers were not read; the first of the three
that Lienstromberg, Schiffer and Schubert cite is now read. It bears on the section on keeping a
magnitude in two ways. Ladyzhenskaya replaced the constant viscosity with one that grows with
the rate of deformation, and proved existence, uniqueness and stability in the large for every
time; for equation (1) it is open. She also wrote that she would not argue for the
systems on physical grounds. The proved regularity is bought by a stress law that is chosen, not
measured. The 1968 LOMI paper and the 1969 book are not held.

## Ladyzhenskaya, *The Mathematical Theory of Viscous Incompressible Flow*, second English edition

Gordon and Breach, translated by Richard A. Silverman and John Chu; preface dated Leningrad,
autumn 1968; the file held is a later printing. A scan with no text layer, rendered and read four
pages to a sheet. This is the third of the sources Lienstromberg, Schiffer and Schubert cite.

- Dedication: to her father, to V. I. Smirnov, "and Jean Leray".
- Preface to the second English edition. "The basic problem of the unique solvability in the large
  of the general three-dimensional nonstationary problem is still open." "Up to the present time,
  essentially only two cases of unique solvability of the general nonstationary problem have been
  proved": for any time but small Reynolds number and potential forces, and for any data but only
  small time. "In a supplement, I propose alternate fundamental equations for fluid mechanics,
  whose mathematical character is advantageous relative to the Navier--Stokes equations, and which
  appear to me to be potentially useful in describing viscous fluid flows. For these equations,
  the initial-boundary-value problems are uniquely solvable in the large."
- Preface to the first English edition. For flow with sources in an unbounded plane domain the
  problem "can have infinitely many solutions", and she gives the family $u_r = c/r$, $u_\phi =
  c_1(1/r - r^{(c/\nu)+1})$ for $c < -2\nu$.
- Introduction. Two questions: whether the equations have a unique solution, and "how satisfactory
  is the description of real flows given by the solutions of these equations?" The Navier--Stokes
  model "had to serve as a scapegoat, answering for all the accumulated absurdities of the theory
  of ideal fluids". Two paradoxes: Poiseuille flow is the only symmetric solution in a pipe for
  every Reynolds number, but is observed only below a critical value; Couette flow likewise. "In
  both cases, it is not known whether the Navier--Stokes equations have solutions for large $R$
  which correspond to the observed flows."
- Introduction, footnote. "The inadequacy of this explanation of the paradoxes cited above may be
  seen by noting that the size of the critical value of $R$ depends on the conditions of the
  experiment, and can be considerably increased by performing the experiment very carefully."
- Introduction. "If a large force $f$ acts on the fluid for an extended interval of time, then the
  quantities $D^m_x v_k$ ... can become so large that the assumption that they are comparatively
  small, made in deriving the Navier--Stokes equations from the statistical Maxwell--Boltzmann
  equations, will no longer be satisfied, just as other assumptions of the Stokes theory, i.e.
  the assumption that the kinematic viscosity and the thermal regime are constant, will be far
  from valid. Because of this, it is hardly possible to explain the transition from laminar to
  turbulent flows within the framework of the classical Navier--Stokes theory." Bears directly on
  the research paper's thesis and on the forced construction: Ladyzhenskaya names the constant
  viscosity and the constant thermal regime as assumptions that fail when a large force acts for a
  long time, the forced construction's situation.
- Introduction. "We call the reader's attention to the following three problems": unique
  solvability in the large in three dimensions; stationary problems in multiply connected regions;
  and whether solutions tend to those of an ideal fluid as $\nu \to 0$.
- Chapter 1. Function spaces; Lemmas 1 to 3 (Ladyzhenskaya's inequalities, among them
  $\int u^4 \le 4(\int u^2)^{1/2}(\int|\nabla u|^2)^{3/2}$ in three dimensions); the constants do not
  depend on the size of the domain. §2: $L_2(\Omega) = G(\Omega) \oplus \mathring J(\Omega)$,
  gradients and solenoidal fields. §3: Riesz and the Leray--Schauder principle.
- Chapter 2, opening. "In all cases considered here, the only important assumption is that a
  system of coordinates can be chosen in which the domain $\Omega$ filled by the fluid does not
  change"; "we set the density of the fluid equal to 1, and we assume that the kinematic viscosity
  $\nu$ is constant." The wall condition is "the adhesion condition".
- Chapter 2, §§1 to 4. The linear Stokes problem: generalized solutions by Riesz's theorem, unique,
  with second derivatives where $f$ allows; exterior problems; plane flows and the Stokes paradox
  (no solution of the plane problem past an obstacle vanishing at the body and tending to a given
  velocity at infinity); the operator $\tilde\Delta$ is self-adjoint, negative-definite, with
  discrete spectrum in a bounded domain.
- Chapter 2, §5, "The Positivity of the Pressure". The system "determines the pressure $p(x)$ to
  within an arbitrary additive constant." The pressure need be neither bounded nor of one sign: for
  $f \in L_2$, $p + \mathrm{const}$ "will in fact neither be bounded in absolute value nor have
  constant sign". "It is reasonable to relinquish the requirement that $p(x)$ (or, more exactly,
  $p(x) + \mathrm{const}$) be positive at every point; instead, we replace the physical
  requirement that the pressure be non-negative by the requirement that the integrals $\int_\Sigma
  |p|\,dS$ be bounded over two-dimensional surfaces $\Sigma$." "Actually, the integrals $\int_\Sigma
  p\,dS$ only have physical meaning for areas $\Sigma$ whose sizes are not less than a certain
  positive number (stipulated by the limits of accuracy of measurement and by the discreteness of
  the liquid medium)." Bears on Proposition 13 (the pressure has no level) and on the averaged-fluid
  chapter: the source says the pressure of the equation has meaning only as an average over an area
  above a size set by measurement and by the molecules.
- Chapter 3. Hydrodynamical potentials (Odqvist, Lichtenstein): the fundamental solution of the
  Stokes system by Fourier transform, volume and layer potentials, integral equations, Green's
  function, estimates in $W^2_2$.
- Chapter 4. The linear nonstationary problem: generalized solutions, uniqueness, energy
  inequality, smoothness, behavior as $t \to \infty$ (Theorem 7: decay in a bounded domain when
  $\int\|f\|$ converges), Fourier series, the vanishing viscosity limit for the linear problem
  (Theorem 9), and the Cauchy problem (Theorem 10). In §2, (27): the Green's tensor of the linear
  Cauchy problem has pressure $p^k(x,t) = -\partial_{x_k}(1/4\pi|x|)\,\delta(t)$, a pressure
  concentrated at the instant of the force and spread over all of space at once. Bears on
  Proposition 12 of the research paper: the source writes down the instantaneous pressure.
- Chapter 5, opening. Stationary problems "have at least one laminar solution for arbitrary
  Reynolds numbers" when the flux through each boundary component vanishes. "In the small",
  uniqueness for bounded domains is due to Lichtenstein and Odqvist, for unbounded to Leray and
  Finn. Method: Riesz's theorem and the Leray--Schauder principle; Theorem 1 of §1 for bounded
  domains with zero boundary data.
- Chapter 5, §§1 to 6. Existence of a generalized solution for any force (Theorem 1); uniqueness
  only when $2\sqrt3\,\mu_1^{-1/4}\nu^{-2}|f| < 1$, a small Reynolds number (Theorem 2); unbounded
  domains (Theorem 3); nonzero boundary data with zero flux through each boundary component
  (Theorem 4); flow past obstacles (Theorem 5); smoothness of the generalized solutions has "the
  same local character as for Laplace's operator" (Theorems 6, 7); uniform convergence to the
  velocity at infinity (Theorem 8). "It is not clear whether the nonlinear boundary value problem is
  solvable 'in the large'" when only the total flux vanishes.
- Chapter 6, §1. "If all the data of the problem are independent of one of the coordinates ...
  then the problem has a unique solution 'in the large', i.e. at all instants of time, with no
  restrictions whatsoever on the smallness of $f$, $a$ or the domain. The same is true in the
  three-dimensional problem if there is axial symmetry and the axis of symmetry does not belong to
  the domain occupied by the fluid. In the general three-dimensional case, it has been shown that
  the problem has a unique solution for all $t \ge 0$ under the condition that the forces $f$ are
  derivable from a potential and that the 'generalized Reynolds number' is less than 1 at the
  initial instant of time. However, if these conditions are not met, then it has been proved only
  that the problem has a unique solution for a certain time interval." Hopf's weak solutions exist
  for all time, "but Hopf did not give the proof of uniqueness of these solutions and thereby did
  not justify such extension of the notion of solution."
- Chapter 6, §1. The statement "it has been proved that the problem has a unique solution" "can
  have very different meanings depending on the function space in which one looks for the
  solution"; "for every problem there are infinitely many 'generalized solutions', but they
  coincide with the classical solution, if the latter exists." Bears on the workbook's status
  table: what "proved" means depends on the space named.
- Chapter 6, §1, Theorem 1. At most one generalized solution in her class (with $\int v^4\,dx$
  bounded). §2, Lemmas 1 to 6: a priori estimates; Lemma 3 bounds solutions when the initial data
  and forces are small against $\nu^3/\beta^2$; Lemma 4 gives a time $T_1$ set by the data for
  large data; Lemma 5 gives estimates for all time in plane flows; Lemma 6 the same for axially
  symmetric flows whose axis lies outside the domain.
- Chapter 6, §3, Theorems 2 to 6. Existence by Galerkin: plane flows for all $t \ge 0$ (Theorem 2);
  potential forces with small initial data for all $t$ (Theorem 3, condition (42) $\|v_x(x,0)\|
  \cdot\|v_t(x,0)\| < \nu^3/\beta^2$); general data on an interval $0 \le t \le T_1$ (Theorem 5);
  axial symmetry with the domain at a positive distance $\delta$ from the axis, for all $t$
  (Theorem 6). Bears on the forced construction: her axisymmetric theorem needs the axis kept out
  of the fluid; the forced construction's core sits on the axis.
- Chapter 6, §§4 to 6. Generalized solutions are classical when $f$ is Hölder (Theorem 7);
  Golovkin and Solonnikov's sharper results (Theorems 8, 9); stability for plane flows (Theorems 10
  to 12). Hopf's weak solutions exist for all time (Theorem 13); footnote: "We have constructed an
  example of nonuniqueness in this class of weak solutions for the Navier--Stokes equations for the
  boundary conditions when on the boundary two components of $v$ and one component of $\mathrm{curl}
  \,v$ are fixed", which "shows that the description of the class of uniqueness ... is precise".
  Theorem 15: uniqueness among weak solutions in $L_{q,r}$ with $1/r + n/2q \le 1/2$ (the
  Serrin--Prodi--Ladyzhenskaya class).
- Chapter 6, §7. Vanishing viscosity: solved for plane flows; "for the initial-boundary-value
  problem (1), the question is open even for plane flows."
- Chapter 6, §8, Theorem 18. The Cauchy problem on all of space has, for all $t \ge 0$ and any
  force in $L_{5/4} \cap L_2$, at least one weak solution with $v_t, v_{x_ix_j}, p_x$ in
  $L_{5/4}$, "no restrictions concerning the smallness of $f$". Uniqueness is not claimed.
- Supplement, "New Equations for the Description of the Motion of Viscous Incompressible Fluids".
  Systems (1) to (3): the viscosity $\nu(v_x) = \nu_0 + \nu_1\int v_x^2$, or a stress $T_{ik}$ with
  $|T| \le c(1 + |\hat v|^{2\mu})|\hat v|$, $\mu \ge 1/4$, or its special case $(\nu_2 + \nu_3|\hat
  v|^2)v_{ik}$. "Many advantages suggest the use of one of the following systems." "The motion of
  continuous media is described by" $\rho\,dv/dt = \mathrm{div}\,T + \rho f$, with Stokes's
  postulates giving $T = -pE + \beta D + \gamma D^2$ (citing Serrin, Handbuch der Physik VIII/1).
  "The analysis of Maxwell--Boltzmann statistical equations yields further indications about the
  form and properties of the $T_{ik}$ functions and corroborates that the conditions (1)--(3) for
  many collision models are natural." Theorem 1: unique generalized solutions for any data,
  classical when $f$ is Hölder and $S$ smooth. Theorem 2: unique and stable on any finite interval.
  Stationary problems are solvable "in the large", and the zero flux across each boundary
  component is not needed, only across the whole boundary. "The proofs largely repeat the
  arguments used in chapter 6. But there is one essential difference in them which is connected
  with the nonlinear principal parts": the energy norm of the new system is stronger than that of
  Navier--Stokes, so the quantity $T$ in (11) "is arbitrary, and need not be small".
- Comments, chapter 5. Leray's 1933 a priori estimates "essentially solved the problem of the
  existence of laminar flows for any Reynolds number", but Leray "did not state this explicitly in
  his later publications", and "it was thought until very recently (at least in the USSR) that the
  problem of the existence of laminar flows for any Reynolds number was still open", and "[m]any
  of the hydrodynamicists and mathematicians concerned with this problem were convinced that
  laminar flows did not exist for arbitrary Reynolds numbers. This conviction was based on numerous
  experiments, which always showed that the flow was turbulent for large Reynolds numbers.
  However, it follows from the results of chapter 5 that the cause of this effect is not that the
  solution does not exist, but ... that it is unstable, and possibly non-unique." Bears on the
  research paper's thesis and on transitivity (I9): the observed flow is the stable solution of the
  equation, not the only one it has.
- Additional comments. "As before, this problem remains open": unique solvability in the large of
  the general nonstationary problem. Yudovich proved periodic solutions exist for periodic forces;
  Prodi and Lions defined weak solutions with $\int v^4$ bounded in three dimensions; Finn proved
  unique stationary flow past a body for small data. On the limit of the viscosity $\nu$ tending to zero: "one
  does not find any ... mathematical solution even for two-dimensional problems if
  boundaries are present." References run to 132 items and include Leray's three 1933--1934
  papers, Hopf (1950--51), Odqvist (1930) and Serrin's Handbuch article (1963).
- Comments, chapter 4. The works of Dolidze on the nonstationary problem "are ... in
  error", taking the linear operator to behave as the heat operator.

What changes. The research paper's sentence that "Ladyzhenskaya's papers were not read for this
chapter" no longer holds: the 1967 Trudy paper, the 1968 LOMI paper on modifications and the book
are read, and the 1968 LOMI paper on axial symmetry as well. Three findings for the research paper.
First, the introduction of the book states the thesis of the chapter on dropped terms in its own
words: when a large force acts for a long time, the derivatives grow until the assumptions of the
Maxwell--Boltzmann derivation fail, "just as other assumptions of the Stokes theory, i.e. the
assumption that the kinematic viscosity and the thermal regime are constant, will be far from
valid." Second, the 1968 modifications paper derives the regularizing viscosity from the dropped
temperature coupling, which is Propositions 3 and 4 run forward to a regular equation. Third, the
book's §5 of chapter 2 holds that the pressure has physical meaning only as an average over an
area above a size set by measurement and the discreteness of the liquid, which belongs beside
Proposition 13 and the averaged-fluid chapter.

## Ladyzhenskaya, Zap. Nauchn. Sem. LOMI 7 (1968) 126--154

*О модификациях уравнений Навье--Стокса для больших градиентов скоростей* (On modifications of
the Navier--Stokes equations for large gradients of the velocities), MathNet.ru `znsl2239`. Read in
the Russian from rendered page images, two pages to a sheet, 29 pages. This is the second of the
three papers Lienstromberg, Schiffer and Schubert cite for the energy equality at large exponents.

- Opening. "In this article I continue the discussion of replacing the Navier--Stokes equations by
  others, somewhat more complicated, but having definite advantages", referring to her reports at
  the 1966 Congress and the 1968 All-Union Congress of Mechanics in Moscow.
- (1) to (3). A continuous medium obeys $\rho\,dv/dt = \mathrm{div}\,\mathcal{P} + \rho f$. "If one
  accepts Stokes's postulates on the character of the dependence of $\mathcal{P}$ on the tensor of
  rates of deformation $\mathcal{D}$", the stress is $\mathcal{P} = \alpha E + \beta\mathcal{D} +
  \gamma\mathcal{D}^2$ with $\alpha, \beta, \gamma$ scalar functions of the invariants. For an
  incompressible fluid, $\mathcal{P} = -pE + \beta(\hat v^2, \det\mathcal{D})\mathcal{D} + \gamma
  (\hat v^2, \det\mathcal{D})\mathcal{D}^2$. The function $p$ "is most often called the pressure
  (by the analogy by which this pressure is connected with the pressure given by measuring
  instruments)." Bears on Proposition 13: the pressure of the incompressible equations is named a
  pressure by analogy with the measured one.
- Conditions 1) to 3) on the stress $T_{ik}$: continuity, growth $|T| \le c(1 + |\hat v|^{2\mu})
  |\hat v|$ with $\mu \ge 1/4$, coercivity, and monotonicity (3). Example (5): $T_{ik} = \beta(\hat
  v^2)v_{ik}$, with "viscosity coefficient" $\beta(\tau)$ positive, increasing and between $C_1
  \tau^\mu$ and $C_2\tau^\mu$ for large $\tau$.
- The physical argument, (6) to (12). "Existing derivations of the equations of motion from the
  statistical Boltzmann equation give some indications for the choice of the function $\beta(\tau)$
  for different models of collisions of gas molecules." These derivations give, for velocity and
  temperature $T$, the system (6), (7): $v_t + v_kv_{x_k} - \partial_{x_k}(\mu v_{ik}) = -p_{x_i} +
  f_i$ and $T_t + v_kT_{x_k} - \partial_{x_k}(\kappa T_{x_k}) - c\mu\hat v^2 = 0$, with $\mu$ and
  $\kappa$ "the coefficients of viscosity and heat conduction, which depend in a definite way on $T$
  (the form of this dependence is determined by the model of interaction between the molecules)";
  "in most cases they increase monotonically as $T \to \infty$". With $\theta(T) = \int dT/\mu(T)$,
  (8) $\theta_t + v_k\theta_{x_k} - c_1\mu\Delta\theta - 2c_1\mu'\mu\theta_x^2 - c\hat v^2 = 0$. On all
  of space, (9): $\min\theta(x,0) + ct_1\min\hat v^2 \le \theta(x,t_1) \le \max\theta(x,0) +
  ct_1\max\hat v^2$; in a bounded domain, (10), with boundary values. "These strictly derived
  inequalities give some ground to accept that the dependence of $\theta$ on $\hat v^2$ has the
  form" (11) $\theta = \nu_1(1 + \varepsilon\hat v^2)$, $\varepsilon \ll 1$. For hard spheres and
  the quasi-Maxwellian model $\mu(T) = c_2\sqrt T$; $\mu = \tfrac{c_2^2}{2}\theta = \nu_0(1 +
  \varepsilon\hat v^2)$. "Thus in these cases it seems natural to take the tensor $T_{ik}$ in the
  form" (12) $T_{ik} = \nu_0(1 + \varepsilon\hat v^2)v_{ik}$.
- After (12). This tensor is "the simplest among all possible dependences (2) of $\mathcal{P}$ on
  $\mathcal{D}$ (if one does not count the linear dependence of $\mathcal{P}$ on $\mathcal{D}$
  leading to the Navier--Stokes equations) for which the dissipation function $\Phi =
  (\beta\mathcal{D}:\mathcal{D} + \gamma\mathcal{D}^2:\mathcal{D}) > 0$". The system (13)
  "differs from the Navier--Stokes system only by the term containing the small $\varepsilon$. For
  it, unlike the Navier--Stokes system, one succeeds in proving unique solvability of
  initial-boundary problems (and solvability of stationary boundary problems) for any Reynolds
  numbers. The term containing $\varepsilon$ can be regarded as a kind of 'regularizer' of the
  Navier--Stokes system, 'correcting' it when $|\hat v|$ becomes very large." Footnote: "One may
  even take in (12) $\varepsilon = \varepsilon_1 t$, $\varepsilon_1 = \mathrm{const} > 0$."
- Molecular repulsion as $1/r^\nu$ with $\nu = 12$ gives $\mu = c_3T^\lambda$, $\lambda = \tfrac12
  + \tfrac{2}{11} = \tfrac{15}{22}$, and with (11) a tensor satisfying conditions 1) to 3).
  "Other models known to me, together with (11), also lead to tensors $T$ satisfying conditions
  1)--3)."
- §1, Theorem I. Under 1) to 3), for initial data in $\mathring J(\Omega)$ and $f \in L_{2,1}(Q_T)$,
  problem (4), (17) has a unique generalized solution, continuous in time in $L_2$. Bounded or
  unbounded $\Omega$. Proof by Galerkin and monotonicity, as in the 1967 paper.
- §1, end. For $f = f(x)$ in a bounded domain, $\|v(x,t)\| \le \|v(x,0)\|e^{-\nu t/c_\Omega} +
  \tfrac{c_\Omega}{\nu}\|f\|(1 - e^{-\nu t/c_\Omega})$, "true for $\varepsilon \ge 0$ and $\mu \ge
  0$, i.e. also for the Navier--Stokes equations".
- §2, Theorem 2.1. Stationary problems are solvable in bounded and unbounded domains with any
  positive $\nu, \varepsilon, \mu$.
- References: Serrin, *Mathematical foundations of classical fluid mechanics* (1963); Chapman and
  Cowling, *The mathematical theory of non-uniform gases* (1960); Huang, *Statistical mechanics*
  (1966); Uhlenbeck and Ford, *Lectures in statistical mechanics* (1965).

What changes. This paper is the source the research paper's thesis has been missing. Ladyzhenskaya
derives her modified viscosity from the coupling equation (1) drops: kinetic theory makes the
viscosity rise with temperature, $\mu = c_2\sqrt T$ for hard spheres; the energy balance (7) with
shear heating $c\mu\hat v^2$ makes the temperature rise with the rate of deformation, (9) proved
on all of space; and together they give $\mu = \nu_0(1 + \varepsilon\hat v^2)$, the viscosity that
grows with $|D|^2$. With that term kept, she proves unique solvability for every Reynolds number;
for equation (1) it is open. The research paper's Propositions 3 and 4 (the dropped
term $2\mu'(T)D\nabla T$ and the energy balance) and its section on keeping a magnitude are, in
this source, one argument: put the temperature back and the equation is regular. Two cautions
stand beside it. For a gas $\mu$ rises with $T$; for water it falls, $(\ln\mu)' = -0.0245$ per
kelvin at 20 °C (IAPWS R12-08), and her derivation then gives the opposite sign of $\varepsilon$,
where her theorem does not apply. And she says the inequalities give "some ground" for (11), not a
derivation of it.

## Ladyzhenskaya, Zap. Nauchn. Sem. LOMI 7 (1968) 155--177

*Об однозначной разрешимости в целом трёхмерной задачи Коши для уравнений Навье--Стокса при
наличии осевой симметрии* (On the unique solvability in the large of the three-dimensional Cauchy
problem for the Navier--Stokes equations in the presence of axial symmetry), MathNet.ru
`znsl2240`. Read in the Russian from rendered page images, 23 pages. This is not the paper of the
same volume that Lienstromberg, Schiffer and Schubert cite, *Modifications of the Navier--Stokes
equations for large gradients of the velocities*, pages 126--154; that one is still not held.

- Opening. At the 1966 Moscow Congress she announced unique solvability in the large of the Cauchy
  problem and one initial-boundary problem for Navier--Stokes "in the case of axial symmetry (in
  the narrow sense)" and gave the relation (17) from which the new a priori estimates follow. In
  the narrow sense: the initial velocity and the force do not depend on the angle, and have no
  swirl, $v_0^\varphi = f^\varphi = 0$.
- (1) to (5). Cylindrical equations with $\omega = v^r_z - v^z_r$ "the only nonzero angular
  component of the vorticity"; a stream function $\psi$ with $v^r = \psi_z/r$, $v^z = -\psi_r/r$;
  the problem is posed on $\Pi_{\varepsilon R} = \{\varepsilon \le r \le R, |z| \le R\}$ and then
  $\varepsilon \to 0$, $R \to \infty$.
- (13). The energy relation. (17), (18): multiplying by $\Phi(\omega/r)$ gives
  $\tfrac12\frac{d}{dt}\int(\omega/r)^2 r\,dr\,dz + \nu\int(\nabla(\omega/r))^2 r\,dr\,dz = \int
  \mathcal{F}\,\omega/r\,dr\,dz$. The quantity $\omega/r$ is carried by the flow and diffused; it
  has no stretching term. (23) to (25) are the new estimates that make the problem solvable in the
  large.
- Theorem 1. The problem in $\Pi_{\varepsilon R}$ is uniquely solvable with bounds independent of
  $\varepsilon$ and $R$. Theorem 2: the Cauchy problem on all of space is uniquely solvable for every
  $T$ under (45), (46). Theorem 3: with Hölder forces the solution is classical.
- Closing. With (22), the estimates (23), (24) do not depend on $\nu$, and taking $\Phi = r^{2k-1}$
  with $k \to \infty$ bounds $\max|\omega/r|$ independently of $\nu$; this opens the limit $\nu \to 0$
  to the Euler equations.

What it bears on. Without swirl the axisymmetric Navier--Stokes problem is regular for all time,
on all of space, with no box. The forced construction is axisymmetric with swirl, $u_\theta$, and
its blowup is carried by the swirl: the swirl is what this theorem excludes. Bears on I7 and I8:
the turning is what removes the guarantee.

## Heaviside step function, Wikipedia

The article at en.wikipedia.org/wiki/Heaviside_step_function, read through. A tertiary source:
it states the definitions and names Heaviside's operational calculus as the origin; it is not
Heaviside's own text, which is still not held.

- Definition. $H(x) = 1$ for $x \ge 0$ and $0$ for $x < 0$; the value at zero is a convention, $1$
  (right-continuous), $0$ (left-continuous) or $\tfrac12$ (so that $H(x) = \tfrac12(1 + \mathrm{sgn}
  \,x)$). In optimization $H(0)$ may be the whole interval $[0,1]$.
- The Dirac delta is the weak derivative of $H$, $\delta = dH/dx$; $H$ is the integral of $\delta$.
- Smooth approximations: $\tfrac12 + \tfrac12\tanh kx = 1/(1 + e^{-2kx})$; $\tfrac12 +
  \tfrac1\pi\arctan kx$; $\tfrac12 + \tfrac12\mathrm{erf}\,kx$; each tends to $H$ as $k \to \infty$.
- Heaviside used it in operational calculus "to represent switching phenomena", in telegraphic
  communications.

What it bears on.

1. The box. A box is a product of step functions, $\prod_i H(x_i)H(1 - x_i)$; putting the fluid in
   a box multiplies it by an indicator whose derivative is a delta on the walls. Proposition 6's
   loss is the transform of that product: the walls are where the step sits.
2. The forced construction's cutoffs. Every cutoff $\chi_X$, $\chi_t$, $\chi(c_nq)$ of Sections 3.5,
   5 and 10 is a smooth step: one inside, zero outside, smooth between. The force is the residual
   of fields multiplied by smooth steps, and its support is where the steps switch.
3. The pressure at an instant. Ladyzhenskaya's Green's tensor (book, chapter 4, (27)) has pressure
   $p^k = -\partial_{x_k}(1/4\pi|x|)\,\delta(t)$: a force switched on as a step in time gives a
   pressure that is a delta in time over all of space. That is Proposition 12 in Heaviside's terms.
4. Fluid tension and switching. The analytic approximations make a step from a steepness $k$; a
   cavitation threshold read as a step in pressure is the $k \to \infty$ limit of a smooth
   transition whose width the continuum equation does not carry.

## Ożański and Pooley, arXiv:1708.09787v1, a modern review of Leray's paper

Held as a guide to Leray's paper, and read at its abstract, introduction and Section 1.

- Introduction. Leray studied the equations on the whole space $\mathbb{R}^3$ with explicit kernels;
  later authors adopted Faedo--Galerkin methods. Hopf (1951) treated bounded domains;
  Ladyzhenskaya (1959) proved global existence and uniqueness of strong solutions in bounded
  two-dimensional domains. Serrin, Prodi and Ladyzhenskaya (1967) gave the $L^r_tL^s_x$ condition
  $2/r + 3/s \le 1$; the endpoint $s = 3$ is Escauriaza, Seregin and Šverák (2003). Scheffer (1977)
  and Caffarelli, Kohn and Nirenberg (1982): the one-dimensional Hausdorff measure of the singular
  set is zero.
- Introduction. Weak solutions "can be thought of as weak continuations of the strong solution
  beyond the blow-up time, a revolutionary idea at the time." The set of singular times has
  box-counting dimension at most $1/2$.
- Section 1.1. The rescaling $u_\nu(x,t) = \nu u(x, \nu t)$, $p_\nu = \nu^2 p(x, \nu t)$ takes a
  solution at viscosity one to one at viscosity $\nu$. This is a different rescaling from the
  forced construction's (10.22), which fixes time and scales space; both remove $\nu$, and neither
  changes the equation's form.

## Navier, Mémoires de l'Académie royale des sciences 6 (1827) 389--440

*Mémoire sur les lois du mouvement des fluides*, read 18 March 1822, from the validated Wikisource
transcription of the volume (djvu pages 577 to 628), with its formulas in TeX. Read in the French;
the notes translate.

- §I, opening. The equations of the geometers "suppose that the molecules of the fluid can take any
  motions whatever relative to one another without opposing any resistance, and slide without
  effort on the walls of the vessels in which the fluid is contained. But the considerable, or
  total, differences that some natural effects present with the results of the known theories show
  the necessity of having recourse to new notions, and of taking account of certain molecular
  actions which show themselves principally in the phenomena of motion." Water through a long pipe
  of small diameter flows far slower than the calculation gives, "and subject to different laws".
- §I, the fluid. "We represent this body as an assemblage of material points, or molecules, placed
  at very small distances from one another." In repose the molecules sit at distances fixed by
  repulsion and pressure, "which has determined the size of the volume occupied by the body, by
  reason of the temperature and the exterior pressure". Navier's fluid is molecules, its volume set
  by temperature and pressure. Bears on Proposition 8 and on the density rows.
- §I, the principle. "In a fluid in motion, two molecules that approach one another repel more
  strongly, and two molecules that separate repel less strongly, than they would if their present
  distance did not change; and we take for principle that by the effect of the motion of a fluid,
  the repulsive actions of the molecules are increased or diminished by a quantity proportional to
  the speed with which the molecules approach or separate." Linear friction is taken as a principle.
  Bears on the open entry "Friction is not linear, anywhere": the linearity is Navier's stated
  starting point, not a result.
- §II. The repulsive force between two molecules is $f(\rho)$, decreasing "very rapidly" with
  distance $\rho$; summed over a sphere about a molecule it gives the pressure $p =
  \tfrac{4\pi}{3}\int_0^\infty \rho^3 f(\rho)\,d\rho$, "and which measures the resistance opposed to
  the pressure". The continuum pressure is a sum of molecular forces.
- §III. With $F(\rho)$ the motional part, $\varepsilon = \tfrac{8\pi}{30}\int_0^\infty \rho^4F(\rho)\,
  d\rho$; the sum over all molecules is replaced by a volume integral, "since all the points in an
  infinitely small rectangular element" have values that differ by an infinitely small amount.
  The equations: $P - dp/dx = \rho(du/dt + u\,du/dx + v\,du/dy + w\,du/dz) - \varepsilon(d^2u/dx^2 +
  d^2u/dy^2 + d^2u/dz^2)$, with $du/dx + dv/dy + dw/dz = 0$. This is equation (1) with $\nu =
  \varepsilon/\rho$. The fluid is "incompressible" from the start, so no bulk term appears, and
  $\varepsilon$ is one constant for the fluid with no dependence on temperature.
- §III, the wall. A second constant $E$, from the action of the wall's molecules on the fluid's,
  gives the slip condition $E u + \varepsilon\,du/dz = 0$ at a wall normal to $z$. "The value of the
  constant $E$ must vary according to the nature of the bodies with which the fluid is in contact."
  Navier's wall slips; the no-slip condition in Fefferman's statement on a bounded domain is a
  different choice.
- §IV, pipes. Rectangular and circular pipes solved by series; the motion "approaches continually"
  a steady state independent of the initial state. For very small pipes $U = \tfrac{\rho g\zeta}{E\alpha}
  \tfrac{R}{2}$: the mean velocity "is then sensibly independent of the mutual action of the parts of
  the fluid, that is to say of what one ordinarily calls the cohesion or the viscosity of the fluid";
  it depends almost only on the adherence to the wall. Agreement with Girard's capillary
  experiments is claimed.
- §IV, temperature. From Girard's copper tubes at about 12 °C, $E/\rho \approx 0.0023$ (metre,
  second). "The experiments show that the action of the wall on the fluid generally diminishes as
  the temperature rises." Water with nitrate of potash runs slower than pure water in glass below
  250 degrees and faster above; "one conceives in fact that the rise of temperature can determine,
  in certain cases, a beginning of chemical action". Navier records from experiment that the
  constants change with temperature, and keeps them constant in his equations. Bears on Proposition
  3 and the viscosity row.
- §IV. Mercury in glass, which does not wet it, stops flowing at a certain head; "the resistance
  arising from sliding on the wall ... is dependent, like the friction of solid bodies, on the
  intensity of the pressure". Bears on the row for viscosity with pressure.
- §IV, canals. The ratio of mean to surface velocity runs from $4/\pi^2 = 0.405$ to $2/\pi = 0.637$
  with the shape; Du Buat's $0.8$ is not reached. "It results from the new theory exposed in this
  Memoir that the supposition of a linear motion is not proper to represent completely the
  phenomena of this motion, except in the cases where the diameter of the pipes is very small."
  Navier says, in the paper that introduces the viscous term, that his equations with linear motion
  do not represent flow in pipes and canals of ordinary size.

What changes. The research paper's sentence that "the papers of Navier and of Stokes ... were not
read" no longer holds for either. Navier's own text supplies three things the research paper and
the workbook can cite: the fluid is molecules and the continuum is a sum over them; linear friction
is a principle taken, "we take for principle"; and the constants of friction and adherence change
with temperature in the experiments he cites, while his equations hold them fixed. The first texts
of vector analysis remain.

## Gibbs, *Elements of Vector Analysis* (New Haven, 1881--1884)

"Arranged for the use of students in physics", marked "not published", from the archive.org scan
`elementsvectora00gibb`, read from its optical text layer, 88 pages. The symbols of the scan do not
survive; the words do, and the notes follow them.

- Preface. The analysis is "such as are familiar under a slightly different form to students of
  quaternions"; Gibbs does not need "the conception of the quaternion", only "a suitable notation
  for those relations between vectors, or between vectors and scalars, which seem most important".
- Chapter I, Nos. 1 to 41. Vectors, the direct product (the scalar product) and the skew product
  (the cross product), triple products, reciprocal systems of vectors, linear equations in a
  vector.
- Chapter II, Nos. 50 to 54. The derivative $\nabla u$ of a scalar function of position, with the
  direction of most rapid increase; for a vector function $\omega$, $\nabla\cdot\omega$ is its
  divergence and $\nabla\times\omega$ its curl. No. 55: the divergence is "the rate of decrease of
  the density" of a substance whose flux is $\omega$, per unit volume, independent of the axes.
- Nos. 57 to 61. The surface integral of a vector over a closed surface equals the volume integral
  of its divergence; the line integral around a closed line equals the surface integral of its
  curl. These are the identities the research paper's Proposition 1 uses, here as Gibbs states
  them.
- Nos. 70 to 72. $\nabla\cdot\nabla$, the Laplacian. "$-\nabla\cdot\nabla u$, where $a$ is any
  infinitesimal scalar, evidently represents the excess of the value of the scalar function $u$ at
  the point considered above the average of its values at six points at the following vector
  distances". "Maxwell has called $-\nabla\cdot\nabla u$ the concentration of $u$ ... which is
  proportioned to the excess of the average value of the function in an infinitesimal spherical
  surface above the value at the center." Bears on the averaged-fluid chapter: the viscous term
  $\nu\Delta u$ is, in the words of the text that named it, the excess of the average of the
  velocity on a small sphere over its value at the center. The term the equation keeps is itself
  an average.
- Nos. 73 to 77. Integration by parts; Green's theorem and its generalization "due to Thomson".
- Nos. 78 to 90. Uniqueness theorems: if $\nabla u = 0$ in a continuous space, $u$ is constant;
  conditions at bounding surfaces and at infinite distances fix a function from its divergence and
  curl. The minimum theorems of Thomson.
- Nos. 91 to 104. Potentials, Newtonians, Laplacians and Maxwellians as operators; No. 98 splits
  any vector function with a definite potential uniquely into a solenoidal and an irrotational
  part: "there is only one way in which a vector function of position in space having a definite
  potential can be thus divided". This is the decomposition the Leray projector and the research
  paper's Proposition 12 rest on. "In space" means all of space; Gibbs needs the potential to be
  "definite", that is, the function to decay at infinite distances.
- No. 100. Infinite values confined to surfaces, lines or points can contribute finite amounts to
  a volume integral; "such cases are easily treated by substituting for the surface, line, or point,
  a very thin shell, or filament, or a solid very small in all dimensions, within which the
  function may be supposed to have a very large value."
- Chapter III, Nos. 105 to 121. Linear vector functions and dyadics: "any linear vector function
  may be expressed by means of a dyadic". The rate of strain $D$ and the stress $\sigma$ of the
  research paper are dyadics in this sense.
- Nos. 135 to 158. Every self-conjugate dyadic is $ai i + bjj + ckk$ on three perpendicular axes;
  every dyadic splits into a self-conjugate part and a rotation part (No. 137). "Rotations and
  Strains": a pure strain is a right tensor; every homogeneous strain is a pure strain and a
  rotation (No. 150). This is the split of $\nabla u$ into the rate of strain $D$ and the spin
  that Stokes made in his Art. 2, in Gibbs's notation.
- Chapter IV, No. 159. $\nabla\omega$ for a vector function is a dyadic, "the nine differential
  coefficients of the three components". Nos. 164 and 165 extend the integral theorems to dyadics.
- Chapter V. Exponential, sine and cosine of a dyadic; No. 185: "a flux which is a linear function
  of the position-vector is called a homogeneous-strain-flux".
- Note on bivector analysis. Complex vectors; "a circular bivector" satisfies $r\cdot r = 0$ with
  $r \ne 0$, "as in the analysis of real vectors" this cannot be concluded.

What changes. The research paper says the first texts of vector analysis were not read. Gibbs's
*Elements* is now read; Heaviside is not held. Two things bear on the research paper: the
Laplacian of the viscous term is, in Gibbs's words, an excess over an average on a small sphere;
and the split into solenoidal and irrotational parts is unique only on all of space, with decay at
infinity: the setting without a box.

## Stokes, Trans. Camb. Phil. Soc. 8 (1845) 287--319

*On the theories of the internal friction of fluids in motion, and of the equilibrium and motion of
elastic solids*, read 14 April 1845, in the reprint of *Mathematical and Physical Papers*, vol. I
(Cambridge, 1880), pp. 75--129, from the archive.org scan `mathphyspapers01stokrich`. Read from the
optical text layer. Words survive it; the equations do not, and are taken from the words around
them.

- Opening. The common equations rest on "the fundamental hypothesis that the mutual action of two
  adjacent elements of the fluid is normal to the surface which separates them". "There is a whole
  class of motions of which the common theory takes no cognizance whatever, namely, those which
  depend on the tangential action." A ball pendulum in water: the common theory gives a constant
  arc; observation shows it diminishes.
- Opening, footnote. "The same equations have also been obtained by Navier in the case of an
  incompressible fluid (Mém. de l'Académie, t. vi. p. 389), but his principles differ from mine
  still more than do Poisson's." Stokes reached the equations independently of Navier and by a
  different route.
- Introduction. Cauchy's equations for elastic solids are the same as Stokes's, "except that he has
  not considered the effect of the heat developed by sudden compression."
- Art. 1. "If we suppose a fluid to be made up of ultimate molecules, it is easy to see that these
  molecules must, in general, move among one another in an irregular manner, through spaces
  comparable with the distances between them, when the fluid is in motion. But since there is no
  doubt that the distance between two adjacent molecules is quite insensible, we may neglect the
  irregular part of the velocity, compared with the common velocity with which all the molecules in
  the neighborhood of the one considered are moving. Or, we may consider the mean velocity of the
  molecules in the neighborhood of the one considered, apart from the velocity due to the
  irregular motion. It is this regular velocity which I shall understand by the velocity of a fluid
  at any point." Bears directly on the averaged-fluid chapter and Proposition 8: the velocity of the
  equation is defined by its author as a mean over molecules, with the irregular part neglected.
- Art. 1. The molecular forces are "sensible only at
  insensible distances"; a state of "relative equilibrium". The principle: the excess of pressure
  over the equilibrium pressure depends only on the relative motion near the point.
- Art. 2. The instantaneous motion of an element is translation, rotation, uniform dilatation and
  two motions of shifting (the axes of extension, roots $e', e'', e'''$ of a cubic).
- Art. 3. "The change of density and temperature about the point P is to be neglected" in finding
  the form of the pressure. Linearity in the rates of strain is reached by the "hypothesis of
  starts": impulsive molecular displacements replaced by continuous forces, with time $\tau$ "so
  short that all summations with respect to such intervals of time may be replaced without sensible
  error by integrations". That the effects of shifting and of dilatation "are superimposed" is
  stated: "it must be taken as an additional assumption, and not a matter of absolute
  demonstration". Bears on the research paper's thesis: the linear stress law is an assumption,
  named as such by its author.
- Art. 3, the bulk term $\kappa$. "We may at once put $K = 0$ if we assume that in the case of a
  uniform motion of dilatation the pressure at any instant depends only on the actual density and
  temperature at that instant, and not on the rate at which the former changes with the time. In
  most cases to which it would be interesting to apply the theory of the friction of fluids the
  density of the fluid is either constant, or may without sensible error be regarded as constant,
  or else changes slowly with the time." And: "if theory and experiment should in such cases
  agree, the experiments must not be regarded as confirming that part of the theory which relates
  to supposing K to be equal to zero." Bears on the bulk viscosity row (Holmes, Parker and Povey):
  Stokes dropped the bulk viscosity by an assumption he says agreement with experiment does not
  test.
- Art. 5. "As it is quite useless to consider cases of the utmost degree of generality, I shall
  suppose the fluid to be homogeneous, and of a uniform temperature throughout, except in so far
  as the temperature may be raised by sudden compression in the case of small vibrations. Hence in
  equations (10) $\mu$ may be supposed to be constant as far as regards the temperature; for, in the
  case of small vibrations, the terms introduced by supposing it to vary with the temperature would
  involve the square of the velocity, which is supposed to be neglected." Bears directly on
  Proposition 3 of the research paper: the term $2\mu'(T)D\nabla T$ is the term Stokes names here,
  and he drops it as quadratic in the velocity, for small vibrations. The research paper's thesis,
  that the term was dropped and is not zero, now has its source: the bound that justified dropping
  it is small velocity, and the forced construction's velocity is unbounded.
- Art. 5. "If we suppose $\mu$ to be independent of the pressure also": Du Buat's experiments on
  pipes and canals show the total retardation "is not increased by increasing the pressure", so
  "I shall therefore suppose that for water, and by analogy for other incompressible fluids, $\mu$
  is independent of the pressure." Bears on the row for viscosity with pressure: Stokes dropped it
  on Du Buat's evidence, by analogy for other fluids.
- Art. 5. The equations are "applicable to the determination of the motion of water in pipes and
  canals, to the calculation of the effect of friction on the motions of tides and waves, and
  such questions". For very small motion the square of the velocity is neglected.
- Art. 6. Free surface conditions (15); capillary attraction is neglected and its term given.
- Art. 6, the solid wall. Stokes first assumed no slip; his pipe formulae "did not at all agree"
  with Bossut and Du Buat. Poisson's conditions did no better. At the wall "the tangential force
  varies nearly as the square of the velocity with which the fluid flows past the surface of a
  solid, at least when the velocity is not very small"; he supposes "that the total friction
  varies as the first power of the velocity" for small velocities. Du Buat found the water at the
  wall of a pipe at rest when the mean velocity is under about an inch a second. Bears on the open
  entry "Friction is not linear, anywhere": Stokes reports from experiment that friction at a wall
  varies as the square of the velocity except at small speeds, and attributes it to roughness and,
  in a later note, to eddies.
- Art. 6, the later note (1880). "By friction that the eddies die away, and the kinetic energy of the
  mass is converted into molecular kinetic energy, that is, heat." Bears on Proposition 4 and the
  energy balance: Stokes names the dissipated energy as heat, the term equation (1) does not carry.
- Art. 6. "The most interesting questions connected with this subject require for their solution a
  knowledge of the conditions which must be satisfied at the surface of a solid in contact with the
  fluid, which, except perhaps in case of very small motions, are unknown."
- Art. 7, sound. Plane waves with the temperature changes of compression kept through the ratio of
  specific heats (20); "the effect of the tangential force is to make the intensity of the sound
  diminish as the time increases, and to render the velocity of propagation less than what it
  would otherwise be." Neither can yet be tested "as we do not possess any means of measuring the
  intensity of sound".
- Art. 8. Fluid between two coaxial cylinders turning at constant rates, the velocity $q = Ar +
  C/r$ (23); Newton's Principia, Lib. II, Prop. 51, gets the wrong law because he balanced force,
  not moment. A sphere turning in an infinite fluid cannot drive a motion in annuli alone:
  "from the excess of centrifugal force in the neighborhood of the equator of the revolving
  sphere the particles in that part will recede from the sphere, and approach it again in the
  neighborhood of the poles, and this circulating motion will be combined with a motion about the
  axis." Bears on I7 and I8: a turning body throws the fluid outward at its equator, the source's
  statement of the author's "imparts mass outward".
- Art. 8, the proposed experiment. Two cylinders turned in opposite directions; "if the inner were
  made to revolve too fast, the fluid near it would have a tendency to fly outwards in
  consequence of the centrifugal force, and eddies would be produced." The instability later
  named for Taylor and Couette is stated here.
- Art. 9. Pipe and canal flow; for a round pipe the profile is parabolic once the wall velocity
  $U$ is given.
- Section II, Arts. 10 to 12. Lagrange's proof that a velocity potential persists is inadmissible
  because $u, v, w$ need not expand in powers of $t$; Cauchy's proof is sound; Stokes gives a new
  one by a lemma on differential inequalities. "It appears to me to be sometimes assumed as a
  principle that two variables, functions of another, $t$, are proved to be equal for all values
  of $t$ when it is shewn that they are equal for a certain value of $t$, and that whenever they
  are equal for the same value of $t$ their increments for the same increment of $t$ are ultimately
  equal ... a conclusion manifestly false." Bears on the research paper's thesis about rules
  carried over without proof: Stokes names a principle of his own time as false.
- Art. 14. A small element "suddenly solidified" moves with translation alone, or with rotation
  as well, as $u\,dx + v\,dy + w\,dz$ is or is not an exact differential.
- Section III, Art. 15. Elastic solids by the same method; two constants $A$, $B$. Cauchy's
  equations agree "except that he has not considered the effect of the heat developed by sudden
  compression"; Stokes keeps it through $m$, the ratio of specific heats, for rapid vibration.
- Section IV, Art. 17. Poisson supposes ultimate molecules acting along lines between centres, and
  neglects "the irregular part of the force exerted by a hemisphere of the medium on a molecule in
  the centre of its base"; that gives one constant ($A = 5B$) for solids. Stokes calls this
  "very questionable" for solids.
- Art. 18. Poisson's fluid is displaced as a solid for a short time $\tau$ and then rearranges; as
  $\tau \to 0$ his equations reduce to Stokes's (12) when $K = 0$. "Poisson himself has not made
  this reduction of his equations."
- Art. 19. For India rubber the cubical compressibility by the one-constant theory "would turn out
  comparable with that of a gas". Oersted's direct experiments give compressibilities for solids
  20 or 30 times smaller than Poisson's theory. Bears on the thesis: a theory with one constant
  where the material has two gives answers off by an order of magnitude.
- Art. 21. Two kinds of elasticity: of volume and of form. "There seems no line of demarcation
  between a solid and a viscous fluid", and the distinction depends on gravity compared with the
  cohesive forces: "what on the Earth is a soft solid might, if carried to the Sun, and retained at
  the same temperature, be a viscous fluid". "Some experiments which have been made on the sudden
  conversion of water and ether into vapor, when enclosed in strong vessels and exposed to high
  temperatures, go towards breaking down the distinction between liquids and gases." Bears on I9:
  water in a strong vessel at high temperature is the gem-growing vessel, and the source names it
  as the place where liquid and gas stop being distinct.
- Art. 21. "According to the law of continuity, then, we should expect the property of elasticity
  to run through the whole series ... it may become insensible, or else may be masked by some other
  more conspicuous property." A fluid "admits of a finite, but exceedingly small amount of
  constraint before it will be relieved from its state of tension by its molecules assuming new
  positions of equilibrium". "Should it be otherwise, equations (8) and (12) will not be true, or
  only approximately true." Bears on the fluid-tension analogy: Stokes holds that a fluid carries a
  small tension of form before its molecules rearrange, and that his equations hold only where
  that tension is insensible.

What changes. Three sentences of this source answer the research paper's "no account is given of
who dropped which term". They are not an account of who; they are the reasons stated by the author
of the equation, and belong beside the propositions they bear on. Proposition 3: Stokes holds
$\mu$ constant in temperature because the terms "would involve the square of the velocity, which
is supposed to be neglected", for small vibrations. The row for viscosity with pressure: Stokes
holds $\mu$ independent of pressure on Du Buat's pipe experiments, "and by analogy for other
incompressible fluids". The row for bulk viscosity: $K = 0$ is assumed, and agreement with
experiment "must not be regarded as confirming" it. Art. 1 defines the velocity of the equation as
the mean velocity of the molecules, the irregular part neglected; Proposition 8 and the
averaged-fluid chapter rest on that. The research paper's sentence that the papers of Stokes were
not read is to change for Stokes; Navier remains.

Read from the text layer of the PDF, 166 pages, extracted with its layout kept and blank lines
dropped. Symbols survive; fractions and superscripts break across lines. A note that rests on an
exponent says whether it was checked on the rendered page.

- Abstract and Theorem 1.1. For every $\nu > 0$ there are a force $f \in C_c^\infty(\mathbb{R}^3
  \times (0,\infty))$, a compact $K$, and smooth $u, p$ on $\mathbb{R}^3 \times [0,1)$ with zero
  initial velocity, support in $K$, bounded kinetic energy and $\limsup \|u\|_{L^\infty} = \infty$
  as $t \uparrow 1$. This establishes alternative (C) of Fefferman's statement, and by compact
  support (D) on $\mathbb{T}^3$ (Corollary 10.6).
- Section 1.1. Leray (1934) built global finite-energy weak solutions with an energy inequality.
  Prior work cited: Tao's averaged equation; Buckmaster and Vicol; Albritton, Brué and Colombo
  (forced, non-unique Leray--Hopf solutions, with a force in $L^1_tL^2_x$ singular at the initial
  time); Córdoba and Martínez-Zoroa (forced Euler and hypodissipative blowup).
- Section 2. "For any incompressible flow $u$ and pressure $p$, we can always define the external
  force $f$ to be the residual in (1.1). The Navier--Stokes equations then hold by construction.
  The challenge is to choose a flow that blows up while this residual remains smooth." Bears on
  the research paper's statement that the force is a residual: the source says so in these words.
- Section 2.1. Self-similar core, radius $\ell_r \asymp \tau^{1/2}$, height $\ell_z \asymp
  \tau^{1/2-h}$, $0 < h < 1/100$, volume of order $\tau^{3/2-h}$; $|u_\theta|, |u_z| \asymp
  \tau^{-1/2-h}$, $|u_r| = O(\tau^{-1/2})$. Kinetic energy of the core of order $\tau^{1/2-3h}$.
  $\mathrm{Re}_\theta \asymp \tau^{-h} \to \infty$; $\mathrm{Re}_r = O(1)$. These match the
  research paper's figures.
- Section 2.1. "In the actual core, viscosity transports angular momentum outwards." Inflow
  carries angular momentum inward and spins the core up; axial outflow carries it away. Bears on
  I7 and I8, on stirring and angular momentum: the source's core is a stirred column whose spin
  is pushed outward by viscosity.
- Section 2.2. The background's residual "becomes unbounded as $t \uparrow 1$, so it cannot serve
  as the smooth external force". Oscillatory pulses on rings are added so that "the fluid's own
  motion supplies the missing momentum transport"; "these internal forces redistribute momentum
  within the fluid". "An exponentially small external force seeds each pulse; the background
  shear supplies its subsequent growth." Pulses grow from the shear and then decay by viscosity.
  Bears on I1 and the seiche analogy: the construction aligns two families of waves so that their
  averaged fluxes supply a stress, which is energy aligned by design.
- Section 2.3. Outside the annulus the flow is purely azimuthal and solves the radial heat
  equation exactly, "the heat exterior"; it is cut off smoothly at a fixed radius.
- Section 3, the rescaling $u_\nu(x,t) = \sqrt\nu\, u(x/\sqrt\nu, t)$, $p_\nu = \nu p(x/\sqrt\nu,
  t)$, $f_\nu = \sqrt\nu f(x/\sqrt\nu, t)$; "the singular time is unchanged" (verified in
  (10.22)--(10.23)). As the research paper states.
- Section 3.1. Similarity coordinates $\tau = q(1-\eta^2)$, $z = q^D\eta$, $X = r^2/(2q)$ with
  $A = (1+h)/2$, $D = 1-h$. The core is "a time-dependent region in space; its boundary is
  determined by fixed similarity coordinates."
- Section 3.2. The annular stress $T$ is required "to be nonzero precisely in the annulus" and must
  lie in the interior of a cone generated by two covariance vectors $v_1, v_2$; this "admissible
  stress cone condition" is enforced by a radial oscillation of phase $N\log X$ (Proposition C.2).
- Section 3.3. Pulse amplitude $A_{\rm wave} \asymp q^{-1/2-h/2}$, wavelength $\ell_{\rm wave}
  \asymp q^{1/2+h/2}$. The amplitudes, phases and cutoffs are chosen; pulses are separated by
  supports in an auxiliary torus variable $Y$.
- Section 3.4. Stage decay $\sigma_j = 1/5 + j/10 \to \infty$; a residual is "flat" as $q \downarrow 0$
  if every derivative is $O(q^N)$ for every $N$. The construction removes the residual stage by
  stage until the residual is flat at the singular point.
- Theorem 3.1. There are constants $0 < h < 1/100$, $q_* > 0$, $0 < X_a < X_{\rm ext} < \infty$
  and smooth fields on $\{0 < q < q_*\}$ with: $u = \mathrm{curl}\,A + Be_\theta$; every derivative
  bounded on compact subsets with $q \ge c$; every derivative of the residual $O(q^N)$ for each
  $N$ as $q \downarrow 0$ (3.4); the residual zero for $X \ge X_{\rm ext}$, where the field is the
  heat exterior $K = r^{-1-2h}H_{\rm ext}(\tau/r^2)$ (3.5); and the growth $u_\theta = \tau^{-A}(
  \varepsilon_\theta + O(\tau^{2h}))$ at a fixed similarity point (3.6). The constants are stated
  to exist and are not given numerically, as the research paper says.
- Section 3.5. The fields are multiplied by cutoffs $\chi_X\chi_t$ with compact support, curled,
  and extended by zero. For $t < 1$, $f := R(u,p)$, the residual. Near $(0,1)$ the cutoffs equal
  one and $f$ is the local residual, flat there. The core has volume of order $\tau^{3/2-h}$,
  $E_{\rm core} \asymp \tau^{1/2-3h}$ and $D_{\rm core} \asymp \tau^{-1/2-3h}$; since $h < 1/6$,
  $\int_0^{\tau_0} \tau^{-1/2-3h}\,d\tau < \infty$. These match Proposition 5 of the research paper.
- Section 3.5, last step. Lemma 10.5: any smooth solution with the same force and zero initial
  datum whose kinetic energy is bounded must agree with $u$ on $[0,T]$, $T < 1$; it cannot exist
  past $t = 1$. This is the uniqueness step the research paper's Leray paragraph rests on.
- Section 3.6. "All profile choices are fixed before $q \downarrow 0$. Constants may depend on
  those choices and on the stated derivative order, but are independent of the concentration
  scale."
- Table 1 and Section 4 opening. A guide to about 80 symbols. Section 4 builds the profiles $E, U,
  \Pi$ in similarity variables so that the leading tangential residual is minus the cylindrical
  divergence of a stress $T_0$ that vanishes near the axis and in the exterior.
- Section 4.1. The profiles are chosen; incompressibility and the radial balance then fix $V_0$
  and $\Pi$ (4.7). "The remaining radial terms, and axial viscosity relative to radial viscosity in
  the tangential equations, carry an additional factor at least $q^{2h}$"; they go to the residual.
- Section 4.2, Lemma 4.4. Five cumulative radial integrals $(M, I, J, S, C_p)$; two profiles that
  agree beyond a joining radius and share these integrals give the same pressure, radial velocity
  and stress there.
- Section 4.3, Lemma 4.5. The admissible stress cone: with $t_s = -b_s/a$, $v_s = a(1+t_s^2)$,
  the conditions are $a > 0$, $v_s > 2$, $P_c > v_s$, $(v_s-2)J_c^2 < 2(P_c-v_s)^2$.
- Theorem 4.6. Fixed $h \in (0, 1/100)$, $\lambda > 0$, $C > 1$, $0 < X_a < X_b$ and profiles with:
  smoothness and analyticity near the axis; the pressure normalized to vanish at radial infinity,
  $\Pi(X,\eta) = -\int_X^\infty E^2/(2x)\,dx$; $T_0$ zero for $X \le X_a$ and $X \ge X_b$ and
  nonzero inside; the cone condition with margin $\kappa < 2$; edge bounds $|T_0| \ge c\zeta$; the
  four moments $M = J = S = 0$ at infinity; and the exterior $E = c_\infty X^{-A}H(2d/X)$, "the
  exact radial heat solution". "All constants in the theorem depend only on the fixed profile
  choices and, for the derivative bounds, on the derivative order. They are independent of
  physical $q$."
- Section 4.4 to 4.6, Lemmas 4.7 to 4.11, Proposition 4.10. Moment matrices are inverted (Rolle's
  theorem gives the determinant a fixed sign); the exterior is prepared with $T_d = e^{M_d} + 10$,
  $P_* > e^{T_d}$, $X_R = 110(CP_*)^{10}$; the inner profile is joined; a periodic radial shear of
  phase $N\log X$ restores the cone where it fails, with errors $O(1/N)$. The choices run from
  large to small in a fixed order, and every constant is a fixed number chosen once. This is
  bookkeeping with no physical content beyond what the outline says.
- Section 5, opening. Axial viscosity and the remaining radial terms are corrected in powers of
  $q^{2h}$. "The resulting coefficient sequence is the formal expansion (5.1): convergence of the
  unmodified infinite series is not asserted." Lemma 5.4 sums it with cutoffs instead. The
  construction does not claim the expansion converges, and does not need it to.
- Section 5.1, Lemma 5.1. Each order is a linear system near the axis, solved by Picard iteration
  with analytic dependence on $\eta$; "the radial interval is independent of the coefficient norms
  at later orders".
- Section 5.2, Lemma 5.2. At each order five bump coefficients are solved so that five moments
  vanish and the stress stays inside $[X_-, X_+]$ or $[X_-, X_b]$. The axial-velocity
  perturbation must sit beyond the leading one "for the pressure support".
- Section 5.2, Step 5, (5.22). Near the outer edge $|T_1| \le Ce^{-4/\delta_b}\delta_b^{-3}$; the
  stress is flat at both edges of the annulus.
- Proposition 5.3. Each finite truncation $U[N]$ has residual $O(q^{h(N+1)-K_m})$ after $m$
  derivatives, with the loss $K_m$ independent of $N$.
- Lemma 5.4. The $n$-th term is multiplied by $\chi(c_n q)$ with $c_n \to \infty$; cutoffs act on
  vector potentials before the curl. The sum stays divergence-free. On any compact set with $q$
  bounded below only finitely many terms remain. The residual is $O(q^N)$ for every $N$ (5.36).
- Proposition 5.5. The background $(u_B, p_B)$ is smooth for $q > 0$, divergence-free, and its
  residual is $-(\partial_r + 2/r)T_{\rm phys,\theta}e_\theta - (\partial_r + 1/r)T_{\rm phys,z}e_z
  + E_B$, with $E_B$ flat; the exterior is the exact heat field (5.44).
- Section 6. The waves are localized by a periodic variable $Y \in \mathbb{T}^2$ evaluated at
  $Y = v_r r + v_t t$, so that "distinct waves do not produce additional quadratic interactions".
  Dyadic charts at $Q = 2^{-\ell}$, $\varepsilon = Q^h$. Lattice directions with $|v\cdot n| \ge
  c/(1+|n|)$ for integer $n \ne 0$ (6.7). A squared partition of unity on each band, with
  rectangles of mesh $S^{-3}$.
- Lemmas 6.1 to 6.3, Proposition 6.6. Centers on the auxiliary torus are chosen by a greedy
  coloring so that enlarged rectangles of interacting labels are disjoint; cross products of
  distinct labels vanish identically after evaluation. Coefficient classes $M_\alpha$, $W_\alpha$,
  $S_\alpha$ are closed under products, sums and the normalized derivatives.
- Section 7, opening. "Their principal linearized evolution must also agree with the background
  shear and viscous diffusion." A linear amplitude equation set by the background shear and
  viscosity: "the homogeneous solution grows and then decays". Its Gaussian bound makes the
  solution exponentially small near both ends of the interval.
- Section 7.1. Carrier wave number $k = \varepsilon^{-1/2}$ (checked on the rendered page: $k =
  \lceil\varepsilon^{-1/2}\rceil$; $\varepsilon k^2$ is of order one and "viscosity remains in the
  leading amplitude equation"). The pulse phase is rotated by the shear $g$ along the pulse
  coordinate $v \in [0, L_s]$, $L_s = 2r_0 S$.
- Lemma 7.1, (7.10). Reference growth and decay rates $\pm\lambda$ with $\lambda(v) =
  \lambda_0\sqrt{1+s(v)^2}$; damping $d = \varepsilon k^2|n_\Phi|^2$.
- Section 7.2, (7.12). The envelope $P(v) = \exp\int_{L_s/2}^v (\lambda(w) - d_{\rm ref}(w))\,dw$;
  growth exceeds damping before the midpoint and is exceeded after it, (7.16):
  $e^{-C(v-L_s/2)^2/L_s} \le P(v) \le e^{-c(v-L_s/2)^2/L_s}$.
- Lemma 7.4, (7.22). The energy identity $\tfrac12\frac{d}{dv}|t|^2 = -g\cdot(\Pi_{\rm tr}
  (t_\theta, t_z)) - \varepsilon k^2|n_\Phi|^2|t|^2$: "The first term gives energy exchange with the
  base shear; the second gives viscous dissipation." Bears on I1, energy aligned, and on the
  research paper's Proposition 5: in this construction the viscous dissipation is the same
  constant-viscosity term, and the shear supplies the energy that it dissipates. Nothing in the
  construction lets heat or a variable viscosity enter this balance.
- Proposition 7.5. The squared amplitudes are $y = H^{-1}T_{0,\star}$, positive because of the cone
  condition; the covariance of the two pulse families is $C(W_0) = \varepsilon T_{0,\star}$ (7.26).
  Two waves, each with zero angular mean, produce together the required stress.
- Proposition 7.6. A linear right inverse of the covariance prescribes signed stress increments.
- Section 7.4, Lemma 7.7. The curl of a vector potential gives the wave exactly divergence-free;
  the remainder $r_m$ is one power smaller.
- (7.40). The temporal cutoff $\psi$ leaves a remainder carrying a factor $S^{C}e^{-cS}$, which in
  physical variables is $O(q^N)$ for every $N$: the cutoff tails are flat.
- Corollary 7.8. When a wave increment is added to a field that already holds earlier corrections,
  the covariance changes by the prescribed $\Sigma$ plus three remainders, each smaller by a power
  of $\varepsilon$; "without any positivity condition on an accumulated stress".
- Section 8. The angular mean of the residual is corrected by pressure, tangential stresses and
  divergence-free mean velocities supported in the active shell. Two radial integrals must vanish
  (8.2): the angular-momentum moment and the axial flux. Lemma 8.2 gives a compactly supported
  radial primitive whose cutoff remainder is flat when a weighted mean vanishes. Proposition 8.3:
  pressure and axial velocity corrections. Proposition 8.4, Corollary 8.5: three integral defects
  $P$, $J_\theta$, $J_z$ are canceled by bump stresses. Lemma 8.6: the fast auxiliary-time
  derivative is inverted on zero-mean fields by a Fourier multiplier with the Diophantine bound
  (6.7).
- Lemma 8.7. Five fixed bump profiles solve the five moment constraints by inverting two
  Vandermonde matrices; "the inverse may deteriorate as $\lambda \downarrow 0$; no uniformity in
  that limit is required."
- Section 9 opening. "Each correction introduces new nonlinear errors, so we need a decay
  improvement after a complete cycle of corrections." $\kappa_s = 10^{-5}$.
- Proposition 9.1, (9.2). The gains of each linear term are tabulated; viscous amplitude
  derivatives gain $1 - 2\kappa_s$, the viscous angular connection $1/2$. The viscous terms are
  the constant-viscosity Laplacian throughout.
- Proposition 9.3, (9.3). At every stage the residual splits as $R = G[j] + F[j]$: supported
  oscillatory sources $G$ and a flat remainder $F$ with $|F[j]|_m \le C_{j,m,N}q^N$ for every $N$.
- Definition 9.4, (9.8) to (9.10). Stage $j$ bounds: $G_\gamma \in W_{B_j}$, mean residuals in
  $M_{C_j}$, defects in $S_{C_j}$, with $\sigma_j = 1/5 + j/10$, $B_j = 1/2+\sigma_j$, $C_j = 1 +
  \sigma_j$; the two angular-momentum and axial-flux integrals vanish exactly. Proposition 9.5:
  the initial state has $B_0 = 0.7$, $C_0 = 1.2$.
- Proposition 9.6. One cycle of four corrections (amplitude, stress, temporal mean, five-equation
  moments) raises every order by $1/10$; the inequalities close with margins of $0.1$ or more,
  using $B \ge 0.7$ and $\kappa_s = 10^{-5}$.
- Lemma 9.7. One domain $0 < q < q_{\rm big}$ serves every stage; derivative counts are tracked on
  a directed acyclic graph of the finite construction. Lemma 9.8: the stage-$j$ increment is
  $O(q^{hj/10 - \ell_m})$ with $\ell_m = 2A + (m+1)(1 + 3h/2)$ independent of $j$.
- Proposition 9.9. Summing with cutoffs gives $u_{\rm loc} = \mathrm{curl}\,A + Be_\theta$, smooth,
  divergence-free, with residual $O(q^N)$ for every $N$ (9.20). Outside a fixed $X_{\rm ext}$ the
  field is the exterior heat field $K = r^{-1-2h}H_{\rm ext}(\tau/r^2)$ and the residual is zero.
  Step 5 confirms the growth $u_\theta(\sqrt{2X_{\rm in}\tau}, 0, 0, 1-\tau) = \tau^{-A}(\varepsilon_0 +
  O(\tau^{2h}))$. This closes Theorem 3.1.
- Section 10 opening. "We must give it zero initial datum and compact spatial support, while
  keeping its momentum residual the restriction of a force in $C_c^\infty$." Rescaling gives
  arbitrary positive viscosity and the periodic construction (Corollary 10.6).
- Proposition 10.1, (10.5). $u = \mathrm{curl}(cA) + cB e_\theta$, $p = c\,p_{\rm loc}$ with a
  spatial cutoff $\chi_X$ and a temporal cutoff $\chi_t$ that is zero for $t$ near $0$. "For $0 \le
  t < 1$ we define $f = R(u,p) = \partial_t u + (u\cdot\nabla)u - \Delta u + \nabla p$." Taking its
  divergence, $-\Delta p = \sum\partial_i\partial_j(u_iu_j) - \mathrm{div}\,f$: "the force may have
  nonzero divergence." Bears on Proposition 12 of the research paper (the pressure Poisson
  equation): the source states it with the force term included.
- Lemma 10.2, (10.9). Near $(0,1)$, $|\partial_x^\alpha\partial_t^j f(x,t)| \le C(\tau + |z|^{1/D})^N$
  for every $N$; all derivatives of $f$ have limits $F_j$ as $t \uparrow 1$, and they vanish at the
  origin. This is the statement the research paper reads from Figure 6: the force vanishes to every
  order at the singular point.
- Lemma 10.3, (10.11). The force is continued past $t = 1$ by a Borel-type sum $\sum_j
  \chi_0(b_j\sigma)\sigma^jF_j(x)/j!$, supported in $K \times [0,2]$. The force after $t = 1$ is
  chosen; it is not determined by any fluid.
- Lemma 10.4, (10.13). $\|u(t)\|_2^2 + 2\int_0^t\|\nabla u\|_2^2 \le F(t)^2$ with $F(t) =
  \int_0^t\|f\|_2$: bounded kinetic energy and finite total dissipation on $[0,1)$.
- Lemma 10.5. Uniqueness among smooth solutions with bounded kinetic energy and unrestricted
  pressure growth, by a Riesz-transform identification of the pressure and a localized energy
  estimate.
- Proof of Theorem 1.1, (10.21) to (10.23). $u_\theta(x_\tau, 1-\tau) = \tau^{-A}(\varepsilon_0 +
  O(\tau^{2h})) \to \infty$ along $x_\tau = (\sqrt{2X_{\rm in}\tau}, 0, 0)$. Under the rescaling,
  $\|u_\nu(t)\|_2^2 = \nu^{5/2}\|u(t)\|_2^2$ and $\nu\int\|\nabla u_\nu\|_2^2 = \nu^{5/2}\int\|\nabla
  u\|_2^2$. The research paper's statement that time is unchanged is confirmed here. The energy
  factor $\nu^{5/2}$ is new to the notes: for water, $\nu \approx 10^{-6}$, the energy of the
  rescaled flow is $10^{-15}$ times that of the flow at viscosity one, and its support is
  $\sqrt\nu = 10^{-3}$ times as wide. Bears on I9: the construction at the viscosity of water is a
  thousandth the size of the one at viscosity one, in whatever units the one at viscosity one is
  measured.
- Corollary 10.6. The periodic construction places rescaled copies $\lambda u(\lambda x,
  \lambda^2(t-t_0))$ at every lattice point of $\mathbb{R}^3/\mathbb{Z}^3$, with disjoint
  supports. The periodic box holds the whole-space solution as translates and adds nothing to it.
  Bears on Proposition 6 of the research paper: in this construction, as there, the box loses
  nothing because the fluid already fits in one cell.
- Appendix A. The outer profile: Vandermonde-type moment matrices (Lemma A.1), a contraction for
  quadratic moment equations (Lemma A.2), a schedule of radial intervals fixed in the order (A.6),
  an axial pulse with amplitude found as the root of (A.19) on $[0.9, 1.2]$, the pressure datum
  (Lemma A.5) and the cone inequalities on the outer interval (A.24) to (A.31).
- Lemma A.6, (A.32) to (A.37). The exterior is the exact radial swirl heat flow $K(r,t) =
  c_\infty s^{-A}H(2t/s)$, $s = r^2/2$, with $H(Z) = \Gamma(a_K)^{-1}\int_0^\infty
  e^{-v}v^{a_K-1}(1+Zv)^{-h}\,dv$; $K$ solves $\partial_tK = (\partial_{rr} + r^{-1}\partial_r -
  r^{-2})K$ exactly and $K_r < 0$. The heat equation here is that of the velocity, not of the
  temperature: "heat" in the source names the diffusion of the swirl by viscosity.
- Proposition A.10, (A.48) to (A.51). At the outer edge of the annulus the stress vanishes like
  $e^{-4/\delta^2}\delta^{-3}$ and its direction tends to $(1, 0)$, purely angular.
- Appendix B. The inner profile near the axis is analytic, built by contraction in a weighted
  coefficient space $B_\rho$ (B.4); the comparison function $f_0(z) = \sum(-z/2)^\alpha/(\alpha!
  (\alpha+1))$ with $f_0(z) \ge 0.265$ on $[0, 4.1]$ (B.11). Proposition B.2: an analytic axis
  profile with zero leading residual stress on $0 \le Y \le 4.1$.
- Appendix C. A periodic loop of shears with prescribed mean, inserted at high radial frequency
  $N\log X$, restores the strict cone; the profile changes by $O(N^{-1})$ and five bumps restore
  the moments exactly (Proposition C.2). Proposition C.3 closes Theorem 4.6.
- References. The paper cites Navier, *Mémoire sur les lois du mouvement des fluides*, Mém. Acad.
  Sci. Inst. France 6 (1827) 389--440, presented 18 March 1822, Gallica ark:/12148/bd6t54644559x;
  Stokes, *On the theories of the internal friction of fluids in motion*, Trans. Camb. Phil. Soc. 8
  (1845) 287--319, doi:10.1017/CBO9780511702242.005; Leray, Acta Math. 63 (1934) 193--248,
  doi:10.1007/BF02547354; Euler, *Principes généraux du mouvement des fluides* (1757); Caffarelli,
  Kohn and Nirenberg (1982); Escauriaza, Seregin and Šverák (2003); Tao (2016).

What changes. The research paper's figures for the construction all stand: the force is the
residual, it is flat at the singular point, the constants are existential, the rescaling keeps
the singular time, and the core quantities scale as stated. The proof of Theorem 1.1 has now been
read through, at the level of its statements, its order of choices and its closing estimates; the
technical bounds of Sections 6 to 9 and the appendices were followed and not checked line by line.
Nothing read bears against the proof. Three things are new and bear on the workbook:

1. The construction is a stirred column. Inflow spins the core up, viscosity carries the angular
   momentum outward, and axial outflow carries it away. I7 and I8 describe the same transport.
2. The construction aligns two families of oscillating pulses, each grown from the shear and then
   damped by viscosity, so that their averaged fluxes supply the stress the core needs; energy is
   taken from the shear and dissipated by the constant-viscosity term (7.22). This is energy
   aligned by design, which bears on I1 and the seiche.
3. At the viscosity of water the construction is $\sqrt\nu \approx 10^{-3}$ times the size of the
   one at viscosity one, and holds $\nu^{5/2} \approx 10^{-15}$ times its energy. Whether a gem
   vessel can supply it depends on the size of the one at viscosity one, which the paper fixes
   only through existential constants. This bears on I9 and leaves it open.

## Gruntfest and Becker, *Mechanics of Deformation and Fracture*, NASA contract NASw-708 (1964)

Final report, General Electric Re-entry Systems Department, July 1964, NTRS 19650001075. Read
from page images of the scan for report pages 5 to 22 and the bibliography, and from the text
layer for the abstract and introduction.

- Abstract. "Instabilities due to regenerative thermal feedback are shown to severely limit the
  range of shear rates or shear stresses for which steady flows are possible. A new instability
  mode for the flow with constant average velocity gradient is described which may be connected
  with the effectiveness of lubricants. Possible relationships of the heating effect to the
  stability of laminar flows and cavitation in liquids are mentioned."
- Introduction. "The laws of thermodynamics teach that the flow of fluids is never exactly
  isothermal." On cavitation: "The connection with cavitation might be related to the strong
  dependence of vapor pressures on temperature."
- The model. Plane Couette flow of a Newtonian liquid whose viscosity falls exponentially with
  temperature, $\eta = \eta_0 e^{-a(T - T_0)}$, with $a$ near $E_A/RT_0^2$. In the reduced
  temperature $\varphi = a(T - T_0)$ and the reduced stress $\Psi = a\sigma_0^2\ell^2/(k\eta_0)$, the
  energy balance with shear heating is $\Psi(\sigma/\sigma_0)^2 e^\varphi = \partial\varphi/\partial
  \tau - \partial^2\varphi/\partial\xi^2$.
- Constant stress, adiabatic: the temperature becomes unbounded at the reduced time $1/\Psi$.
  Constant stress between isothermal walls: no steady flow when the reduced temperature on the
  center plane exceeds 1.187; the largest $\Psi$ for steady flow is 3.52.
- Constant boundary velocity between isothermal walls. The steady solution gives
  $(a\eta_0/k)(V^2/8) = e^{\varphi_c} - 1$. With $\varphi_c \le 1.187$ this bounds the velocity for
  steady flow, $V_m = 4.27\,(k/(a\eta_0))^{1/2}$, and the bound does not depend on the gap. For
  organic liquids at one poise and $a = 0.08$ per kelvin they give about 600 cm/s. Near $V_m$ the
  apparent viscosity differs from $\eta_0$ by a factor of 2.27.
- The instability with no steady state: "the velocity gradient tends to rise in the center and
  fall near the walls", which "could account for the low drag on lubricated bearings". The
  center temperature rises when the walls are cooled. For gases, which become more viscous when
  heated, the same argument puts the gradient at the boundaries.
- Concluding remarks: "in the case of air and water, the temperature gradients necessary for the
  onset of convection may be lower than those required for the development of discernible changes
  in viscosity."
- Reference 2 is Gruntfest, *Thermal feedback in liquid flow*, Trans. Soc. Rheology 7 (1963)
  195--207.

Water, evaluated with the IAPWS values at $20\,^\circ$C and atmospheric pressure ($k = 0.5980$
W/(m K), $\mu = 1.0016$ mPa s, $a = 0.0245$ per kelvin):

- $V_m = 666$ m/s. The center plane then stands at $48.5$ K above the walls, near $68\,^\circ$C,
  where the vapor pressure is $0.029$ MPa. $V_m$ is $6.04\,U^*$, with $U^*$ the 110 m/s of the
  scaling estimate of the first workbook chapter, since $V_m^2 = 8(e^{1.187} - 1)k/(a\mu)$ and
  $U^{*2} = k/(2a\mu)$.
- The steady center rise is 0.06 K at 17 m/s, 2.5 K at 110 m/s and 44 K at 618 m/s.
- The exponential law overstates the fall in water: at $68\,^\circ$C it gives $0.31$ mPa s, and
  IAPWS gives $0.41$.
- The limit $\varphi_c \le 1.187$ is carried over from the constant-stress case. With the walls
  moving at a fixed speed the steady problem has one solution at every speed, with
  $V^2 = 8\int_{T_0}^{T_c} k/\mu\,dT$ for any $\mu(T)$ and $k(T)$, independent of the gap; 1.187 is
  where the wall stress peaks, and above it the stress falls as $V$ rises. With the IAPWS $\mu(T)$
  and $k(T)$ at atmospheric pressure the middle of the layer is at $20.06\,^\circ$C at 17 m/s,
  $68.5\,^\circ$C at 643 m/s and $99.9\,^\circ$C at 956 m/s.

What changes.

1. I13, first half. The runaway is in this source for a fixed stress: above the peak stress
   there is no steady flow, and the shear gathers in the center. For walls moving at a fixed speed
   the steady layer exists at every speed, and 666 m/s is where its wall stress peaks. The vapor is
   not in this source.
2. The scaling estimate of the first workbook chapter. $U^*$ is where the dropped term is on a par
   with the kept one; the wall stress peaks at six times $U^*$. Both are far above the 10 to 17 m/s
   at which the forced construction in water cavitates (Duraiswami).
3. Navier's slip. Gruntfest's lowered wall gradient is the same effect as the slip at a wall that
   equation (1) sets to zero, reached here by heating instead of by a vapor layer.

## Berry, Vakarelski, Chan and Thoroddsen, arXiv:1612.08335v2

*Navier slip model of drag reduction by Leidenfrost vapor layers.* Read in full from the text
layer, with Figure 1 read from the page image.

- Abstract. "Recent experiments found that a hot solid sphere that is able to sustain a stable
  Leidenfrost vapor layer in a liquid exhibits significant drag reduction during free fall."
  "Measurements based on liquids of different viscosities show that onset of the drag crisis
  depends on the viscosity ratio of the vapor to the liquid."
- Introduction. For a no-slip sphere at Reynolds numbers $10^3$ to $4\times10^5$ the drag
  coefficient is near 0.4, and near $5\times10^5$ it drops to near 0.1, the drag crisis. A
  free-slip sphere follows $C_D \approx (48/\mathrm{Re})(1 - 2.2/\sqrt{\mathrm{Re}})$ and does not
  separate; such a sphere "has yet to be realised".
- The vapor layer is of order hundreds of micrometers on a sphere of a centimeter, "estimated to
  be in the range of 50 - 200 µm", and $150 \pm 50$ µm in the experiments they compare with.
- Figure 1, measured. Hot spheres above the Leidenfrost temperature in free fall, against spheres
  at room temperature in the same liquids. In water at $95\,^\circ$C ($\mu_L = 0.3$ mPa s) the
  drag coefficient read from the figure is near 0.25 at $\mathrm{Re} \approx 10^5$ and near 0.15
  at $2$ to $3\times10^5$, against 0.4 to 0.5 without the vapor layer. In the fluorocarbon PP3 it
  falls to near 0.07. The vapor viscosity is "$\sim 1.2\times10^{-2}$ mPa s for all liquids
  presented."
- The model is Navier's slip condition at the sphere with slip length $s$. At low Reynolds number
  the literature gives $s \approx (\mu_L/\mu_V)\,\delta_V$, with $\delta_V$ the thickness of the
  vapor layer.
- Conclusion. "The presence of a finite tangential velocity on the surface of the sphere enables
  the flow to resist the adverse pressure gradient for longer, delaying flow separation." At
  moderate to high Reynolds number the slip length depends on $\mu_L/\mu_V$ "but does not follow
  the form suggested by low Re flow analysis."

What changes.

1. I13, second half. A vapor layer between water and a moving sphere lowers the measured drag
   coefficient to between a half and a third of its value without the layer. The vapor is made by
   the heat of the sphere, and the body on it is a solid. The author's claim is water riding water
   on steam made by the shear between them, and this source does not test it.
2. Navier's slip. The condition Navier wrote at a wall, a tangential velocity proportional to the
   wall stress, is the model these authors use for the vapor layer. Equation (1) with the no-slip
   condition sets that velocity to zero. The vapor layer is a case where it is not zero, and the
   drag shows it.

## Braeck, Podladchikov and Medvedev, arXiv:0805.3292v2

*Spontaneous dissipation of elastic energy by self-localizing thermal runaway.* Read in full from
the text layer.

- Abstract. "Thermal runaway instability induced by material softening due to shear heating
  represents a potential mechanism for mechanical failure of viscoelastic solids." Onset "is
  controlled by only two dimensionless combinations of physical parameters." Thermal diffusion
  "leads to continuous and extreme localization of the strain and temperature profiles in space".
- The model is a Maxwell slab between clamped walls held at the background temperature, with an
  Arrhenius viscosity, $\eta = A^{-1}e^{E/RT}\tau^{1-n}$, and an energy equation with the shear
  heating. A slightly warmer central zone of width $h$ starts it.
- Adiabatic case: runaway above a critical stress $\tau_c$, and the temperature rise is the stored
  elastic energy spread over the central zone, $\Delta T_{\max} = \tau_0^2 L/(2GCh)$.
- With diffusion: the critical stress grows with the ratio of relaxation time to diffusion time,
  and for that ratio below one $\tau_c$ stands. Two kinds of runaway: adiabatic, uniform across the
  zone; and self-localizing, where the band narrows to well below $h$ and the peak temperature
  exceeds the adiabatic estimate. "The self-localizing failure modes occur at lower values of the
  shear stress compared to the adiabatic modes."
- Discussion. The model "does not include corrections due to effects of melting, although melting
  of the material near the shear band may be possible." The introduction cites melted rock along
  shear faults and drops on the fracture surfaces of metallic glasses as evidence of the heat.

What changes. I13, first half. The runaway is reported again, here in solids, and it narrows the
band as it goes. The phase change it reaches is melting, which the source reports as evidence and
leaves out of the model. Nothing here is water or vapor.

## Zamansky and Ham, Center for Turbulence Research Annual Research Briefs 2013, 47--60

*Modelization of cavitation in shear flows.* Read in full from the text layer.

- Section 1. In diesel injectors "the sudden fuel acceleration in the injector causes a dramatic
  drop in static pressure and generation of an intense shear". Following Joseph, the liquid breaks
  where the largest principal stress, not the pressure, passes the threshold: $T_{11} + p_c > 0$,
  "Such a criterion can account for stress-induced cavitation." In the experiments of Mauger and
  others, "cavitation inception occurs in the shear layers between the recirculation zones and the
  bulk of flow, and not at the inlet corner where the average pressure is minimal."
- Section 3. A barotropic tabulated state equation; "heat effects such as viscous heating and
  modification of the local thermodynamic properties of the fluid are neglected, although they can
  affect the cavitation".
- Section 4. A stochastic model of vapor production driven by the largest principal stress, with
  the impurities entered as disorder in a random-field Ising model.
- Section 4.4. "The cavitation inception (S > 0), which is roughly connected to the location of
  the maximum stress, is seen to occur in the shear layer at the channel inlet, in the vortices
  resulting from the destabilization of the shear layer."

What changes. I13 and its addition. Inception is in the shear layer between two regions of flow,
and not where the mean pressure is least. The criterion that places it is the stress, which
includes the shear that equation (1) carries and the pressure alone does not.

## Brandao and Mahesh, CAV2021, 11th International Symposium on Cavitation

*LES of cavitating shear layer.* Read in full from the text layer.

- Abstract. Inception in the shear layer behind a backward-facing step, "inception occurs inside
  the core of the streamwise stretched/contracted vortical structures along the shear layer in
  axial positions around 67% of the reattachment point, which is in good agreement with
  experiments."
- Section 3. Low pressure and vapor do not coincide: "Low pressure regions need to be sustained
  for some amount of time to allow for the growth of vapor to more visible sizes."
- Citing O'Hern, inception is "in the stretched streamwise vortices, indicating that the lowest
  values of pressure are likely to be in the core of these vortices".

What changes. I13, the stated expectation that where the pressure is near the vapor pressure the
steam sheet and the cavitation of the core are one event. This source places the onset in the
cores of stretched vortices within the shear layer.

## Pimenova and Goldobin, arXiv:1407.4725v2, Eur. Phys. J. E (2014) 108

*Boiling of the interface between two immiscible liquids below the bulk boiling temperatures of
both components.* Read in full from the text layer.

- Abstract. "An intense vapour formation at such a direct contact is possible below the bulk
  boiling points of both components, meaning an effective decrease of the boiling temperature of
  the system."
- Section 1. "Boiling occurs at the interface between two liquids, but not in their bulk." Each
  liquid evaporates into the vapor layer between them. The vapor pressure in the layer is the
  sum of the two; it grows when the sum passes the atmospheric pressure, and either alone does
  not. The authors give it as the reason water "is forbidden for usage when one needs to stop fire
  of inflammable organic liquids".
- Section 2, demonstrations. A layer of white spirit over water, set alight: at first only surface
  evaporation, then "rare vapour bubbles rising from the white spirit--water interface. The bulk
  boiling of water does not occur, meaning the interface is below the bulk boiling points of both
  liquids." n-Heptane over water: one center of vapor formation at the interface, then many
  bubble lanes.
- Table 1. Water boils at 373.15 K and n-heptane at 371.58 K; their interface boils at 351.71 K,
  78.56 °C.
- Section 5. A thin vapor layer grows between the liquids and breaks away by buoyancy as bubbles;
  in a stratified system the breakaway is a Rayleigh--Taylor instability of an extremely thin
  vapor layer between two liquids, which Appendix C treats. The layer at breakaway is of order
  $10^{-5}$ to $10^{-4}$ m, and bubble diameters of about 3 mm match the demonstration.

What changes. The author's addition to I13, the chemical difference. Vapor forms at the boundary
between two liquids that differ and at a lower temperature than in either one alone, and the
source holds a thin vapor layer between two liquids as the first stage.

## Pfeiffer, Shahrooz, Tortora, Casciola, Holman, Salomir, Meloni and Ohl, arXiv:2306.01571v1

*Heterogeneous cavitation from atomically smooth liquid--liquid interfaces.* Read in full from the
text layer.

- Abstract. "Here, we present the finding of a so far unreported nucleation site, namely the
  atomically smooth interface between two immiscible liquids. The non-polar liquid of the two has
  a higher gas solubility and acts upon pressure reduction as a gas reservoir that accumulates at
  the interface."
- Background. Few experiments reach the cavitation threshold of water predicted by classical
  nucleation theory; "most experiments however suffer from a considerably lower threshold".
- Experiment. Tension from a Lamb-type wave in a gap of 3 to 5 µm of water holding droplets of a
  perfluorocarbon. "Bubbles are mostly nucleated along the PFC/water interface." A droplet can
  nucleate more than once and is not used up.
- Simulation. Water and perfluorocarbon slabs with dissolved nitrogen at $-20$ MPa: the nitrogen
  gathers at the interface, the two liquids separate there, and "no gas bubbles are formed in the
  PFC bulk" at 1 bar.
- Conclusion. Nucleation at the interface needs a liquid of high gas solubility and its interface
  with a second, immiscible liquid; "not only PFC droplets can induce cavitation, but any liquid
  immiscible with water that has also a high gas solubility."

What changes. The author's addition to I13, the chemical and dissolved-gas difference. Under
tension the vapor or gas starts at the boundary between two liquids and not in the bulk of
either.

## Maquet, Darbois-Texier, Duchesne, Brandenbourger, Dorbolo, Sobac, Rednikov and Colinet, arXiv:1603.05821v2

*Leidenfrost drops on a heated liquid pool.* Read in full from the text layer.

- Abstract. "A volatile liquid drop placed at the surface of a non-volatile liquid pool warmer
  than the boiling point of the drop can experience a Leidenfrost effect even for vanishingly
  small superheats."
- Section III A. Ethanol over silicone oil: the drop levitates on its vapor once the pool is above
  78 °C, and "Observing the Leidenfrost effect for a superheat as low as ΔT = 1°C is a feat that is
  never seen on a solid substrate". The drops are "highly mobile". On aluminum the Leidenfrost
  point of ethanol is near 158 °C.
- Section III B. For a 1.2 mm drop at a pool of 118 °C the vapor film is 57 µm at the center and
  18 µm at the neck.
- Section IV B. No Leidenfrost drop was seen on oils of viscosity above 150 mPa s, which the
  authors relate to convection in the pool that keeps the surface warm.
- Conclusion. "Over a pool, a Leidenfrost state is possible as soon as the liquid of the pool is
  just hotter than the drop boiling point, with no apparent Leidenfrost threshold. This is at
  least partly due to the fact that a liquid substrate has no roughness unlike the solid ones."

What changes. I13, both halves and the addition. One liquid rides another on a cushion of vapor,
mobile, at a step in temperature and composition between them, with a superheat near one kelvin.
The drive here is heat and not shear.

## Koplik and Banavar, arXiv:cond-mat/0508612v2

*Slip, immiscibility and boundary conditions at the liquid-liquid interface.* Read in full from
the text layer.

- Abstract. "When the total liquid density near the interface drops significantly compared to the
  bulk values, the tangential velocity varies very rapidly there, and would appear discontinuous
  at continuum resolution. The value of this apparent slip is given by a Navier boundary
  condition."
- Introduction. "It is difficult to imagine how two intermixed dense liquids could maintain
  distinct molecular speeds", and that argument "might fail when interfacial mixing is poor and the
  molecules of different species are spatially separated." For simple liquids they know of no
  measurement or systematic computation of liquid-liquid slip; for polymer melts there is indirect
  and direct evidence.
- Method. Molecular dynamics of Couette and Poiseuille flow of two layers of Lennard-Jones chains.
  The attraction between unlike atoms is set by $A_{12}$: $A_{12} = 0$ is immiscible, and the
  Lorentz--Berthelot value $A_{12} = 0.97$ is partly miscible.
- Results. In the miscible case the density varies monotonically across the interface and the
  velocity is continuous. In the immiscible case the density dips at the interface, by
  $\Delta = 0.66$ of the mean in the main example, and the velocity changes so fast there that at
  continuum resolution it is a slip. The slip is the Navier condition $\Delta u = \kappa S$, with
  $\kappa$ "approximately constant" for each pair of liquids, "independent of the flow
  configuration and the value of the driving force."
- Interaction strength. With $A_{12} = 0.2$ to $0.8$, "the apparent slip and the density dip were
  found to decrease roughly linearly to zero from their values at $A_{12} = 0$".
- Size. In argon units $\kappa \approx 10^{-5}$ m/(Pa s), "a value three orders of magnitude
  larger than observed or inferred in polymer melts"; the authors suggest their interactions may
  be too repulsive. A density dip is reported at the water/octane interface and not at the
  water/carbon tetrachloride interface, by other simulations they cite.

What changes. I14. The velocity jump at the interface between two liquids grows as the attraction
between unlike molecules weakens, and vanishes as the liquids become miscible. The jump sits where
the density dips: the two liquids hold apart at the interface. That gap is where I13's addition
and I15 put a vapor film.

## Komuro, Sukumaran, Sugimoto and Koyama, Rheologica Acta 53 (2014) 23--30

*Slip at the interface between immiscible polymer melts I: method to measure slip.* Open access,
doi:10.1007/s00397-013-0742-2. Read in full from the text layer.

- Introduction. "Typically, two chemically different polymers are immiscible, and the distinct
  phases are separated by interfaces. At the interface between two phases, the chemically
  different chains are likely to be weakly entangled. If entanglements are the main source of
  adhesion between the two components, then poor interfacial adhesion can be expected at the
  interface." As the stress at the interface rises, "one of the phases might slip with respect to
  the other."
- Method. Polypropylene coated with a thin sheath of polystyrene, of nearly equal viscosity,
  extruded through capillaries of three diameters at 230 °C; the slip velocity at the interface
  from a modified Mooney method, checked against the deviation from no-slip.
- Results. Slip at the interface appears above a critical interfacial stress, at stresses "that
  are significantly lower than the shear stress necessary for the onset of wall slip" near
  $10^5$ Pa. The slip velocity is a power of the interfacial stress, with exponent near 3 at low
  stress and near 2 above about $2\times10^4$ Pa. Their slip velocities are two to three times
  those measured at 200 °C by others, which they attribute to temperature.

What changes. I14. Two liquids unlike enough not to mix slip on each other, measured, and at a
lower stress than either slips on a wall. The source does not vary how unlike the two are.
