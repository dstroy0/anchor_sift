# Intuitions recorded before the sources that test them are read

**Purpose:** Hold each intuition about the Navier-Stokes thought experiment in its author's words,
with the source that would test it and what would count as a hit or a miss, before that source is
held or read. A match afterwards is then a prediction that held, and a miss is on the record in the
same place. **Scope:** this file, and the millennium workbook whose chapters score its entries.

**Douglas Quigg (dstroy0).** Each entry is fixed when it is written. An entry is scored by adding
to it, below a line, and never by changing what is above the line. Where a criterion was written by
the person recording the entry and not by the author of the intuition, it says so.

## What was already read when these were written

Caupin and Herbert, *Cavitation in water: a review*, Comptes Rendus Physique 7 (2006), at its
introduction, its nucleation theory, its sections on inclusions and the Berthelot method, and its
section on acoustic cavitation. Nothing on seiches, on bubble growth after nucleation, on angular
momentum in cavitation, on quantum foam, or on recovering a container from its modes was held or
read.

## Entries, 2026-10-03

### I1. Microcavitation is a seiche: energy aligned

**In the author's words:** "conceptually, it is the same as a seiche, energy aligned."

**Already known when written.** The review reports that the experiments reaching the most tension
in water used standing waves in resonators or tightly focused waves. This entry is therefore not a
clean prediction for those experiments, and it is not scored against the review.

**Test.** A source on seiches, read, and the primary papers of Galloway and of Greenspan and
Tschiegg, read.

**Criterion, written by the recorder.** Hit if the tension that cavitates the water is reached by
energy arriving in phase at one place, and the threshold depends on that alignment: off resonance,
or out of focus, the same input does not cavitate. Miss if the threshold in those papers does not
depend on alignment.

### I2. The energy compounds for a short while and exponentiates

**In the author's words:** "the energy potential compounds for a short while and exponentiates."

**Already known when written.** The exponential part follows from the review's equations: the rate
of nucleation grows exponentially in a barrier that falls as the inverse square of the tension.
The duration, "a short while", was not in any source read.

**Test.** A source on the growth of a bubble after nucleation in water, read.

**Criterion, written by the recorder.** Hit if the growth after the critical radius accelerates for
a bounded time and then stops accelerating. Miss if it keeps accelerating until something outside
the bubble stops it.

### I3. Tension moves angular momentum between bulk and boundary, and only heat can carry it

**In the author's words:** "the surface of the water undergoes so much tension it needs to
bulk-boundary transfer angular momentum and it can only do it with heat", with the tension then
placed in the fluid itself and not in a surface.

**Already known when written.** The review reads nucleation as crossed by thermal fluctuations. It
says nothing on angular momentum.

**Test.** A source on angular momentum or rotation in bubble nucleation or collapse, read.

**Criterion.** None written: the statement has to be made more precise before a source can score
it. The recorder does not supply one in the author's name.

### I4. Microcavitation is to water what quantum foam is to space

**In the author's words:** "microcavitation is analagous to quantum foam."

**Test and criterion.** None. It is an analogy, held here as an analogy.

### I5. Spherical harmonics of the wave patterns recover the container

**In the author's words:** "we assume it is infinite because we dont know anything about its
container until we start using spherical harmonics to decode the wave patterns we see."

**Already known to the recorder when written, and stated here so it cannot be read into the result
afterwards.** Kac asked in 1966 whether the shape of a drum can be heard from its frequencies, and
Gordon, Webb and Wolpert answered in 1992 that two different plane domains can share every
frequency. Neither paper was held or read. If that is right, the frequencies alone do not recover a
container, and the strongest form of this entry is a miss.

**Test.** Those two papers, read, and a source on recovering a domain from its modes with more than
the frequencies: amplitudes, phases, or the field itself.

**Criterion, written by the recorder.** Hit if the container is recovered uniquely from the
harmonics of the field when more than the frequencies is kept. Miss if two containers give the same
harmonics even then.

### I6. Density has a gradient, and stirring lowers the density of the bottom layer

**In the author's words:** "density has a gradient, the space between the molecules on the bottom
of a column will have infinitesimally less space between them because of the mass of the fluid
above them, and you can absolutely decrease the density of the bottom layer by stirring."

**Already known when written.** IAPWS R6-95 (2018) is held and read, and it gives density as a
function of pressure and temperature. Nothing has been computed from it for this entry yet.

**What the recorder expects, stated before computing.** The first part holds: the weight of the
column raises the pressure at the bottom, and a liquid with a finite compressibility is denser
there, by a fraction small per meter. The second part splits. Stirring that sets the liquid
turning lowers the pressure at the bottom center and raises it at the bottom wall. Density
falls at the center and rises at the wall. The heat that stirring puts in lowers the density above
$3.978$ C and raises it below.

**Test.** IAPWS R6-95 (2018), evaluated for the compressibility, with the balance of momentum for a
column at rest and for a turning column.

**Criterion, written by the recorder.** First part: hit if the density at the bottom of a column at
rest exceeds the density at the top by a positive amount set by the compressibility. Second part:
hit if stirring lowers the density of the bottom layer everywhere on it; split if it lowers it at
some places and raises it at others; miss if it raises it everywhere.

---

**Scored, 2026-10-03, after the entry above was fixed with SHA-256 `576fa04a`.** Water at
$20$ C, IAPWS R6-95 (2018) evaluated by a program that reproduces its verification table, standard
gravity $9.80665$ m s$^{-2}$.

**First part: hit.** The isothermal compressibility is $4.589\times 10^{-10}$ per pascal, and a
column at rest is denser at the bottom by $4.49\times 10^{-6}$ of its density per meter of depth.
The mean spacing of the molecules, which goes as the cube root of the volume per molecule, is
smaller by about a third of that, $1.5\times 10^{-6}$ per meter. A column of $10$ meters is
$4.49\times 10^{-5}$ denser at the bottom, and an isothermal column of $4000$ meters is $1.74$
percent denser. The fluid above presses the fluid below closer together, by an amount the
compressibility fixes.

**Second part: split under turning alone, and a hit with enough stirring.** A liquid in a cup of
radius $R$ turning at rate $\Omega$ has a free surface lowered at the axis and raised at the wall by
$\Omega^2R^2/(4g)$, since the volume is the same as at rest. The bottom pressure falls at the center
and rises at the wall by $\rho\Omega^2R^2/4$. For $R = 4$ cm at two turns per second that is
$63$ Pa, and the density of the bottom layer falls at the center and rises at the wall by
$2.9\times 10^{-8}$ of itself. Stirring lowers the density of the bottom at its center, as the
author said, and raises it at the wall. The heat of stirring then decides the wall: at $20$ C the
rise there is canceled by warming of $1.4\times 10^{-4}$ kelvin. All the energy of the turning,
$63$ joules per cubic meter, dissipated as heat with $c_p = 4184$ J kg$^{-1}$ K$^{-1}$, warms the
water by $1.5\times 10^{-5}$ kelvin, a tenth of that. Stirring kept up for more than about ten
times the energy of the turning, with the heat kept in, lowers the density of the whole bottom
layer above $3.978$ C. Below $3.978$ C warming raises the density, and stirring cannot lower it at
the wall. How fast the turning decays and how much heat leaves were not computed.

### I7. Stirring only the outside of a column does not make the middle denser

**In the author's words:** "that totally depends on the kind of stirring, if we are talking about a
column if i drop an L shaped stirrer in that stirs the outside walls, will the middle become
denser? no."

**Already known when written.** I6 as scored above: under turning of the whole cup, the bottom
center becomes less dense and the bottom wall denser.

**What the recorder expects, stated before computing.** Agreement. With the core still and only a
ring at the wall turning, the pressure is flat across the still core, the surface over the ring
rises toward the wall, and with the volume fixed the surface over the core must fall. The whole
bottom of the core then becomes less dense by one amount, and the bottom at the wall denser.

**Test.** The balance of momentum for a steady ring turning at speed $V$ between radii $R_1$ and
$R_2$ around a core at rest, with a free surface and the volume of the column at rest, and IAPWS
R6-95 (2018) for the compressibility.

**Criterion, written by the recorder.** Hit if the bottom of the core is not denser than at rest
anywhere on it. Miss if it is denser anywhere on it.

---

**Scored, 2026-10-03, after the entry above was fixed with SHA-256 `28565614`.**

**The author's mechanism, given while this was being scored:** "we impart angular momentum, it
imparts mass outward and away as magnitude." In a steady turning flow the push outward on each
volume of fluid is $\rho|v|^2/r$, held by a pressure that rises outward, $dp/dr = \rho|v|^2/r$. It
depends on the magnitude of the velocity and not on its direction: turning either way pushes mass
outward by the same amount.

**Hit.** In the still core $v = 0$ and the pressure is flat. Across the ring $|v| = V$ and it rises
by $\rho V^2\ln(r/R_1)$, and the free surface follows it. With the volume of the column fixed, the
surface over the core falls by
\[
\frac{V^2}{g}\Bigl(\ln x - \tfrac12 + \tfrac{1}{2x^2}\Bigr),\qquad x = R_2/R_1 > 1,
\]
which is positive: the bracket is zero at $x = 1$ and its derivative $1/x - 1/x^3$ is positive
above it. The bottom of the core is less dense by one amount everywhere on it, and nowhere denser.
The surface at the wall rises by $(V^2/g)\bigl(\tfrac12 - \tfrac{1}{2x^2}\bigr)$, and the bottom
there is denser. Under a lid on a full rigid column the same holds: mass and volume are fixed, and
the wall cannot gain density without the core losing it.

For water at $20$ C, a ring from $3$ to $4$ cm turning at $0.5$ m s$^{-1}$ lowers the pressure
under the core by $17.2$ Pa, its density by $7.9\times 10^{-9}$ of itself, and raises it at the
wall by $54.6$ Pa and $2.5\times 10^{-8}$. A wider ring, from $2$ to $4$ cm, lowers the core by
$79.4$ Pa and $3.6\times 10^{-8}$.

The kind of stirring sets where the bottom thins and by how much: turning the whole cup thins it
most at the axis, and stirring the outside thins the whole core evenly. In both, the middle does
not become denser.

**Open.** Stirring also drives a slower circulation across the column, inward along the bottom and
up the middle, the one that gathers leaves at the center of a cup. Where that inflow meets at the
center and stops, the fluid pushes on itself and the pressure rises locally by about
$\tfrac12\rho u^2$, with $u$ the speed of the inflow. Whether that local rise can exceed the drop of
the core was not computed, and the speed of the inflow is in no source read.

### I8. In an infinite fluid held at 20 C, stirring changes density only near the stirrer

**In the author's words:** "if we had infinite fluid that had infinite thermal reservoir and was
for eternity 20 degrees C, would stirring it change its density at all? like if the column of water
were infinite, I say yes, but only where the stirrer is pushing, and then within a few kilometers
the force would be absorbed into background noise."

**Already known when written.** I6 and I7 as scored: density follows pressure through the
compressibility, and turning pushes mass outward by $\rho|v|^2/r$.

**What the recorder expects, stated before computing.** A rough estimate was made in thought while
reading the statement, before this entry was written, and it is set down here so it is not taken
for a blind prediction. With the temperature held fixed, density changes only through pressure.
Around a turning stirrer the speed falls off as the inverse square of distance in the far field,
and the pressure that holds the turning as the inverse fourth power. The change is largest at
the stirrer and falls fast. For a stirrer the size of a spoon the recorder expects it to fall below
the thermal fluctuations of density within meters, not kilometers, with the distance depending on
the volume over which density is measured.

**Test.** The flow around a sphere turning in an unbounded viscous fluid, the compressibility from
IAPWS R6-95 (2018), and the size of the thermal fluctuations of density in a volume $V$,
$\langle\delta\rho^2\rangle/\rho^2 = k_BT\kappa_T/V$.

**Criterion, written by the recorder.** First part: hit if the change of density is largest where
the stirrer pushes and falls off with distance. Second part: hit if the distance at which it falls
below the thermal fluctuations is of the order of kilometers for a stirrer the size of a spoon; the
distance found is recorded either way.

---

**Scored, 2026-10-03, after the entry above was fixed with SHA-256 `b87f1e74`.**

**The author's frame, given while this was being scored:** "I'm assuming a generally still system
not like an ocean." The only background is then the thermal fluctuation of density, and that is
the floor used below.

**Sources read for the test.** Kruger, *How to compute density fluctuations at the nanoscale*,
arXiv:2408.05530, equation (2): $\kappa_T = (V/k_BT)\langle\delta\rho^2\rangle/\rho^2$, which makes
the thermal floor $\sqrt{k_BT\kappa_T/V}$. Daddi-Moussa-Ider, Sprenger, Richter, Lowen and Menzel,
*Steady azimuthal flow field induced by a rotating sphere*, arXiv:2107.03927, equation (3): far from
a turning body in an unbounded fluid the speed is $|L\times s|/(8\pi\eta s^3)$, falling as the inverse
square of the distance $s$, with the torque on a sphere $L = 8\pi\eta a^3\Omega$ from the bulk
rotational mobility they state. Both formulas hold for slow flow.

**First part: hit.** With the temperature held, density changes only through pressure. The
pressure that holds the turning is of order $\rho v^2$, and with $v$ falling as $1/s^2$ the change of
density falls as $1/s^4$: largest where the stirrer pushes and falling fast away from it. The order
$\rho v^2$ is an estimate; the slow-flow solution itself carries no pressure at its leading order.

**Second part: depends on the torque, and the expectation recorded above missed a channel.** For a
sphere of radius $1$ cm turning at $50$ rad s$^{-1}$ in water at $20$ C, the slow-flow torque is
$1.26\times 10^{-6}$ N m, and the change of density meets the thermal floor at $0.17$ m for a
measured volume of one cubic centimeter, $0.40$ m for one liter, and $0.96$ m for one cubic meter:
meters, as the recorder expected. That distance grows as the square root of the torque, and
reaching one kilometer with a measured volume of one cubic meter takes $1.4$ N m, which a motor
gives easily. The slow-flow torque understates a stirrer moving at $0.5$ m s$^{-1}$, where the
Reynolds number is near $5000$; the real torque of a stirred spoon was not computed.

**Open: sound.** The recorder's expectation left out sound. A stirrer that is not symmetric about
its axis, the L-shaped stirrer of I7 among them, pushes the fluid at its turning rate and sends
out pressure waves. A wave spreading from a source loses amplitude as $1/s$ and not as $1/s^4$, and
at a few turns per second the absorption in water, set by its shear and bulk viscosity, is very
small. Sound could carry a change of density from a stirrer to kilometers before it falls below the
floor. No source on the sound a stirrer sends out is held, and this was not computed.

**Verdict.** The first part is a hit. The second is not scored: a slow, small, symmetric stirrer
gives meters, a stirrer with more than about a newton meter of torque gives kilometers, and sound
from a stirrer that is not symmetric is open.

### I9. Fluids are transitive, and the singularity is not observed

**In the author's words:** "all of this stirring, and thermodynamic floor positing was for this:
the system is transitive, we would be able to observe these in reality, we can't even though other
extreme objects exist in fluid."

**Already known when written.** Propositions 8 to 11 of the research paper; Eyink, Bandak,
Goldenfeld and Mailybaev on thermal noise; Caupin and Herbert on cavitation; I6 to I8 as scored.

**What the recorder expects, stated before scoring.** The claim splits in two. That a real fluid
cannot follow equation (1) to an unbounded value follows from what is already proved and read: the
fluid leaves the description before the value is reached. That a singularity is not observed in
real fluids is a claim about the whole record of observation, which no source held speaks to, and
an absence of observation is weak on its own, since a singularity below what an instrument
resolves would go unseen.

**Test.** The propositions and sources listed above for the first part. For the second, a source
that reviews the search for finite-time singularities in experiments on real fluids.

**Criterion, written by the recorder.** First part: hit if every route to an unbounded value in
equation (1) passes a scale or a level at which a member of $P_{\mathrm{all}}$ or $F_{\mathrm{all}}$
that equation (1) drops is shown to act. Second part: hit if a source held reports that no
finite-time singularity has been observed in a real fluid; open until one is held.

---

**Scored, 2026-10-03, in the same writing as the entry above.** No hash of the entry alone was
taken before scoring, and the score rests only on sources already held when the entry was written.

**First part: hit, for the routes this work has examined.** A solution of equation (1) that breaks
down has a length of flow with no positive lower bound, Proposition 11, and passes lengths where a
cell holds $33.4$ molecules of water and the average equation (1) stands for scatters by $17$
percent. The rate of shear heating has no bound there, Proposition 5, while equation (1) holds no
temperature. Thermal noise acts at about the Kolmogorov length, and Eyink, Bandak, Goldenfeld and
Mailybaev state that the deterministic equation is inadequate there and that extreme events can
break even the fluctuating description. A fluid pulled into tension breaks by cavitation at a
finite pressure, Caupin and Herbert, where equation (1) holds no level of pressure, Proposition 13.
Along each route a dropped member acts before the value becomes unbounded. Whether these are all the
routes is not shown.

**Second part: open.** No source held reports on the search for singularities in experiments on
real fluids. The extreme objects that are observed and read in this work, cavitation under tension
and the standing and focused waves that produce it, all end at finite values.

**What the two parts give together.** Even if equation (1) has solutions that become unbounded,
a real fluid cannot follow one there: it leaves the description first. A theorem about equation
(1) therefore says nothing about what a real fluid does at that point, and the absence of an
observed singularity is what transitivity across real fluids would lead one to expect. It does not
refute the theorem, which is about equation (1).

---

**The author's meaning, given after the score above, 2026-10-03.** "no I mean this object, is
reproducible under lab conditions specifically gem lab pressure vessel conditions and we do not see
these phenomenon." The object is the forced construction itself, and the claim is that its
conditions can be set up in the pressure vessels used to grow gems, and that the breakdown is not
seen there. The score above answered a wider reading, the record of observation across all real
fluids, and does not score this one.

**What the recorder expects, stated before reading the construction.** Theorem 1.1 of the forced
construction says only that the force is smooth and compactly supported, and the sections that
build it were not read. Whether a vessel can supply that force depends on its shape, its size and
its strength once the viscosity of water is fixed, and the recorder does not know these. The
construction reaches every viscosity by rescaling space. For water the force may need lengths
or strengths no vessel can give, or it may not. No prediction is made on that. That the breakdown
is not seen in gem-growing vessels is a claim about those vessels, and no source on them is held.

**Test.** The sections of *Finite time blowup for Navier--Stokes* that define the force and its
scales, read; and a source on the conditions inside the pressure vessels used to grow gems, held
and read.

**Criterion, written by the recorder.** Reproducible: hit if, at the viscosity of water, the force
of the construction has a length, a strength and a duration that a laboratory vessel can supply;
miss if any of the three is beyond one. Not seen: hit if a source held reports these conditions run
without the breakdown; open until one is held.

---

**Scored, 2026-10-03, after the meaning above was fixed with SHA-256 `07beef12`.** Read in
*Finite time blowup for Navier--Stokes*: Theorem 3.1 and Figure 6 on pages 15 and 16, section 10.1,
and section 10.4 with equation (10.22), checked on the rendered page.

**What the force is.** Equation (10.5) defines it as the residual of the built velocity,
$f = \partial_tu + (u\cdot\nabla)u - \Delta u + \nabla p$: the flow is built first, and the force is
whatever makes it satisfy the equation. Figure 6 states that the residual and all its derivatives
vanish to every order at the singularity. Near the point that breaks down, the force goes to zero
and the flow drives its own collapse. Lemma 10.3 makes the force smooth and supported in a compact
set over times in $[0,2]$.

**Reproducible: not scored on numbers, and a miss for a pressure vessel as the source of the
force.** Theorem 3.1 states that its constants exist, $0 < h < 1/100$, $q_* > 0$,
$0 < X_a < X_{\mathrm{ext}}$, $e_0 > 0$, and the parts read give none of them a value. The
size of the support and the strength of the force at the viscosity of water cannot be put in
meters and newtons from them. Equation (10.22) fixes how they scale: space and the force by
$\sqrt\nu$, time unchanged, which for water is a factor of $1.0017\times 10^{-3}$, about a
millimeter of support for each unit of the nondimensional support when the singular time is one
second. What a pressure vessel supplies is the pressure and temperature at its walls, and gravity.
It does not supply a force of a chosen shape inside the fluid, and $f$ is such a force. By
Proposition 13 the level of pressure does not enter equation (1). The high pressure of the vessel
changes nothing in equation (1) and changes the water: its density, its viscosity, and the level at which
it could cavitate.

**What the vessel does do.** It closes one exit. A high static pressure keeps the water far from
tension, and the route of I9 by which a stretched fluid leaves the description, cavitation, is
shut. A vessel is therefore a setting where the fluid has fewer ways out than in open water, and
its record is worth reading for that reason.

**A scaling estimate, marked as theory.** The core of the construction has speed growing as
$\tau^{-(1/2+h)}$ and radius shrinking as $\tau^{1/2}$, with $\tau$ the time left. Put in water with
the constants of order one, which the parts read do not give, the core reaches a nanometer with
about a picosecond left, moving near $1000$ m s$^{-1}$, against a speed of sound of $1482.35$
m s$^{-1}$. Condition (2) would fail at about the scale where the continuum does.

**Not seen: open.** No source on the conditions inside the vessels used to grow gems, or on what
is seen in them, is held.

### I10. The breakdown is a pressure cooker opened without venting, and no city has fallen

**In the author's words:** "the blowup would happen like the same if you open a pressure cooker
without releasing the pressure", "these are like microcavitation nukes", and "we havent leveled
any cities on gem vessel pressure failure."

**Already known when written.** Caupin and Herbert: a liquid leaves equilibrium by superheating or
by stretching, and "temperature and pressure are equivalent parameters controlling the departure
from equilibrium". Page 16 of *Finite time blowup for Navier--Stokes*, read for I9: the kinetic
energy of the collapsing core scales as $\tau^{1/2-3h}$ and goes to zero, and Theorem 1.1 keeps the
total energy bounded.

**What the recorder expects, stated before scoring.** The pressure cooker holds: opening it drops
the pressure on water above its boiling point, and the swirling core of the construction drops its
own pressure by about $\rho u^2$, which equation (1) lets fall without a floor. Both reach
cavitation, and water would cavitate in the core long before the speed became unbounded. The
nuclear image does not hold for the construction: its core carries less and less energy as it
collapses. The absence of cities leveled is consistent with the claim and also with the theorem.
It does not decide between them.

**Test.** The balance $dp/dr = \rho u^2/r$ across a swirling core, the cavitation pressures read in
Caupin and Herbert, and page 16 of the forced construction.

**Criterion, written by the recorder.** Pressure cooker: hit if the core of a swirl reaches the
cavitation pressure of water at a finite speed. Nuclear: hit if the construction concentrates an
unbounded energy; miss if its core energy is bounded or vanishes. Cities: scored as deciding only
if one side predicts a release of energy the other does not.

---

**Scored, 2026-10-03, in the same writing as the entry above.** The score uses only what was held
and read when the entry was written.

**Pressure cooker: hit.** Across a swirl the pressure rises outward as $\rho u^2/r$. For a core
turning as a solid body inside a free swirl, the pressure at the axis lies $\rho U^2$ below the
pressure far away, with $U$ the largest speed. Water at $20$ C and atmospheric pressure reaches the
cavitation pressures Caupin and Herbert report at core speeds of
$U = \sqrt{(p_\infty - p_{\mathrm{cav}})/\rho}$: $10.1$ m s$^{-1}$ to reach zero pressure, $142$
m s$^{-1}$ for $-20$ MPa, the most tension a standing wave gave, and $375$ m s$^{-1}$ for $-140$ MPa
in inclusions. The core speed of the construction has no bound. A swirling core of water would
reach each of these speeds at a finite time and cavitate. Equation (1), holding no level of pressure,
lets the core go on, Proposition 13.

**Nuclear: miss, for the construction.** The core energy goes to zero as $\tau^{1/2-3h}$ and the
total stays bounded. The breakdown concentrates speed into a point that carries less and less
energy, and releases nothing that was not put in by the force. What a collapsing cavitation bubble
releases is a separate question, and no source on it is held.

**Cities: not deciding.** A vessel that fails releases the energy stored in its compressed and
superheated contents, which is bounded and large enough to do damage. Neither the author's reading
nor the theorem predicts more than that, and the record of failed vessels does not separate them.

### I11. Force concentrated toward a singularity comes out as light, heat or both

**In the author's words:** "no when you multiply force like that to a singularity, usually in
physical reality that leads to light heat or both." This is the meaning of "microcavitation nukes"
in I10: the energy is converted, not a city leveled.

**Already known when written.** Proposition 5: the rate of shear heating has no bound at the
singular time. Page 16 of the forced construction: the core's integral of squared radial
derivatives scales as $\tau^{-1/2-3h}$, without bound, in a core of volume $\tau^{3/2-h}$. No source
on light from collapsing bubbles is held.

**What the recorder expects, stated before reading.** Heat: a hit already, from what is held. Light:
a source on sonoluminescence will report light from the collapse of cavitation bubbles in water.
Equation (1) carries no channel for light, and that is a further member of $F_{\mathrm{all}}$ and
$P_{\mathrm{all}}$ it drops.

**Test.** A review of sonoluminescence, held and read, and the scaling on page 16.

**Criterion, written by the recorder.** Heat: hit if the heating per volume in the core has no
bound. Light: hit if a source held reports light emitted when cavitation bubbles collapse in a
liquid.

---

**Scored, 2026-10-03, after the entry above was fixed with SHA-256 `bdaf236e`.** Read: Barber,
Hiller, Lofstedt, Putterman and Weninger, *Defining the unknowns of sonoluminescence*, Physics
Reports 281 (1997), at the abstract and section 1.

**Heat: hit.** On page 16 of the forced construction the core's integral of squared radial
derivatives scales as $\tau^{-1/2-3h}$ in a volume of $\tau^{3/2-h}$. The heating per volume in the
core then scales as $\tau^{-2-2h}$, without bound as $\tau \to 0$.

**Light: hit.** A gas bubble trapped at the pressure antinode of a resonator, driven at its
acoustic resonance, collapses each cycle with its wall moving at more than $1.4$ km s$^{-1}$, and
emits a flash of light shorter than $50$ ps, about a million photons, broadband into the
ultraviolet. The energy is concentrated by twelve orders of magnitude, from about
$4\times 10^{-12}$ eV per atom in the sound to photons of $6$ eV, and the light comes from a region
the authors call very hot and very stressed: both light and heat. They write that the sound energy
goes into "degrees of freedom, visible photons, which are not describable by the original equations
of fluid mechanics." The light is a member of $F_{\mathrm{all}}$ and $P_{\mathrm{all}}$ that
equation (1) does not hold. The mechanism that emits it is stated as open.

**Bearing on I1.** The bubble is held where the standing wave of a resonator puts its pressure
swing, and the flash repeats once each cycle in step with the sound: energy aligned. This bears on
I1 and does not score it, since its criterion asks whether the threshold of cavitation depends on
the alignment, and section 1 does not say.

### I12. The light comes from the gas in the bubble turned to plasma

**In the author's words:** "its generated by turning the gas in the bubble into plasma basically."

**Already known when written, and so not a blind prediction.** The review of I11 had been read at
its abstract and section 1. The recorder also knows by name, and has not read or held, a later
paper by Flannigan and Suslick in Nature in 2005 reported as measuring plasma in a single
collapsing bubble.

**Test.** The review of I11; and the 2005 paper, once held and read.

**Criterion, written by the recorder.** Hit if a source held states that the gas in the collapsed
bubble is ionized and that the light is emitted by the ionized gas; open if a source held names it
only as a candidate.

---

**Scored, 2026-10-03, in the same writing as the entry above.**

**Open, as the best candidate.** The review's abstract names "a supersonic bubble collapse launching
an imploding shock wave which ionizes the bubble contents so as to cause it to emit Bremsstrahlung
radiation" as the best candidate theory, and states the theory of the light-emitting mechanism
still open. Ionized gas is plasma, and the author's statement is the candidate the review prefers.
It moves to a hit when the 2005 paper, or another measurement of the ionized gas, is held and
read.

---

**Scored, 2026-10-03, after the 2005 paper was held and read.**

**Hit.** Flannigan and Suslick, *Plasma formation and temperature measurement during single-bubble
cavitation*, Nature 434 (2005) 52--55, read in full. In sulphuric acid under argon they measure
emission from argon states about 13 eV above the ground state and from O$_2^+$, which "cannot be
thermally populated at the measured Ar emission temperatures", and conclude that "these emitting
species must originate from collisions with high-energy electrons, ions or particles from a hot
plasma core." The review of I11, read in full since, names bremsstrahlung from "a dense ionized
region" as its most complete candidate. Both meet the criterion.

### I13. Shear heating turns to steam sheets, and one sheet of water rides another on the steam

**In the author's words:** "shear heating turns to steam sheets we already know you can accelerate
a sheet of water over another on a steam cushion."

**Already known when written, and so not a blind prediction for the second half.** The recorder
knows by name, and has not held or read, work on the Leidenfrost effect and on drag reduction by a
vapor layer around a hot sphere moving through water. Duraiswami, read in full, puts the viscous
heating of the forced construction in water at about 0.01 K before the core cavitates. Barber and
others, section 2, report that a stirrer opens voids in the liquid. Ladyzhenskaya (1968), read in
full, couples the viscosity to the temperature through the shear heating and, for a viscosity that
rises with temperature, finds the coupling regularizing.

**What the recorder expects, stated before reading.** In water the viscosity falls as it heats,
$(\ln\mu)' = -0.0245$ per kelvin at $20\,^\circ$C and atmospheric pressure (IAPWS R12-08). Shear
heating then thins the layer that is heating, the shear gathers into it, and it heats faster: a
runaway, and the end of the runaway is the phase change the author names. Two speeds from the
water properties, evaluated with the IAPWS formulations at $20\,^\circ$C and $0.101325$ MPa:

- the speed at which the dropped term matches the kept one, the scaling estimate of the first
  workbook chapter, $U^* = \sqrt{k/(2\mu|(\ln\mu)'|)} = 110$ m/s;
- the velocity jump across a layer whose walls are held at $20\,^\circ$C that heats its middle to
  $100\,^\circ$C with the viscosity held fixed, $U = \sqrt{8k\,\Delta T/\mu} = 618$ m/s.

The recorder expects the runaway to start near the first speed and to reach steam below the
second, since the viscosity falls as it heats. Where the pressure is already near the vapor
pressure, $0.00234$ MPa at $20\,^\circ$C, as in the core of a turning column, almost no heating is
needed, and the steam sheet and the cavitation of the core are one event.

**Test.** For the second half: a source on drag reduction by a vapor layer in water, held and
read. For the first half: a source on thermal runaway in plane shear of a liquid whose viscosity
falls with temperature, held and read, and a source reporting vapor formed in water by shear
heating alone.

**Criterion, written by the recorder.** Second half: hit if a source held reports that a vapor
layer between water and a moving body lowers the drag by a measured factor. First half: hit if a
source held reports that shear heating in a liquid whose viscosity falls with temperature
gathers into a thin layer with no steady state above a critical speed, and that in water that
layer reaches vapor; open if only the runaway is reported and the vapor is not; miss if a source
held shows the runaway does not occur in water at speeds the forced construction reaches before
its core cavitates.

---

**The author's addition, given after the entry above was fixed with SHA-256 `9d32f9f1`.**
"especially if theres a layer difference, chemical, density, temperature or otherwise."

**What the recorder expects, stated before reading.** Where two layers differ, the shear gathers at
the boundary between them, since that is where the velocity jumps, and each kind of difference
lowers what the steam sheet needs there:

- temperature: a layer already warmer starts nearer the boiling point and needs a smaller rise,
  and its lower viscosity takes more of the shear;
- chemical: a component that boils lower, or dissolved gas, starts the vapor at a smaller rise,
  and gas lowers the barrier to nucleation (Caupin and Herbert);
- density: a stable density step holds the boundary flat while the layers slide. The shear
  stays at one surface instead of spreading.

The recorder expects the steam sheet, where it forms, to form first at such a boundary and not in
a uniform bulk.

**Test.** A source on shear layers at a density or temperature step in a liquid, and a source on
vapor or cavitation onset at the boundary between two liquids or at a dissolved-gas gradient,
held and read.

**Criterion, written by the recorder.** Hit if a source held reports the shear, the heating or the
vapor onset concentrated at the boundary between layers that differ, and earlier than in a
uniform liquid under the same drive; miss if a source held reports onset in the bulk first.

---

**Scored, 2026-10-03, after the entry above was fixed with SHA-256 `9d32f9f1` and the addition with
`ce3b3d52`.** Read in full: Gruntfest and Becker, NASA contract NASw-708 (1964); Berry, Vakarelski,
Chan and Thoroddsen, arXiv:1612.08335; Braeck, Podladchikov and Medvedev, arXiv:0805.3292;
Zamansky and Ham, CTR Annual Research Briefs 2013; Brandao and Mahesh, CAV2021; Pimenova and
Goldobin, arXiv:1407.4725; Pfeiffer and others, arXiv:2306.01571; Maquet and others,
arXiv:1603.05821.

**Second half: hit, and not blind.** Berry and others, Figure 1: a hot sphere carrying a
Leidenfrost vapor layer, falling through water at $95\,^\circ$C, has a drag coefficient near 0.25 at
$\mathrm{Re} \approx 10^5$ and near 0.15 at $2$ to $3\times10^5$, against 0.4 to 0.5 for the same
sphere without the layer. They model the layer by Navier's slip condition. Maquet and others put a
drop of ethanol on its own vapor over a pool of hot oil at one kelvin of superheat, and the drop is
highly mobile: one liquid riding another on a cushion of its vapor.

**First half: miss.** The runaway is real. Gruntfest and Becker show that a liquid whose viscosity
falls with temperature has no steady shear flow between walls held at a fixed temperature above
$V_m = 4.27\,(k/(a\eta_0))^{1/2}$, and that above it the shear gathers in the middle. Braeck and
others show the band narrowing as it runs away, in solids, toward melting. For water at
$20\,^\circ$C $V_m$ is 666 m/s. Duraiswami puts the core of the forced construction in water at
cavitation when the swirl reaches 10 to 17 m/s, with the viscous heating near 0.01 K. At 17 m/s the
steady rise in Gruntfest's layer is 0.06 K. The runaway does not occur in water at the speeds the
forced construction reaches before its core cavitates: the miss as written. The bound is
for plane shear between walls held at a fixed temperature; under a fixed stress with no heat loss
the same law runs away at any stress, in a time that grows as the stress falls.

**The stated expectation, against the sources.** The runaway was expected near $U^* = 110$ m/s; the
bound is $6.04\,U^*$. Steam was expected below 618 m/s; at 618 m/s the steady middle of the layer
stands 44 K above the walls, near $64\,^\circ$C, and steady flow ends at $68\,^\circ$C with the
middle still liquid. The vapor that a source held does put in a shear layer of water comes from
the pressure and not the heat: Zamansky and Ham, and Brandao and Mahesh, put inception in the shear
layer, in the cores of its stretched vortices, and not where the mean pressure is least. The
expectation that near the vapor pressure the steam sheet and the cavitation of the core are one
event is the part the sources bear out.

**The addition: hit, on the chemical difference.** Pimenova and Goldobin: water and n-heptane in
contact boil at their interface at $78.56\,^\circ$C, below $100\,^\circ$C and $98.4\,^\circ$C, and
in their demonstrations the bubbles rise from the interface while neither bulk boils; the first
stage is a thin vapor layer between the two liquids. Pfeiffer and others: under the same tension,
bubbles nucleate mostly along the interface between water and a perfluorocarbon that holds more
dissolved gas, and in their simulation the gas gathers at the interface and forms no bubble in the
bulk. Both report the vapor onset at the boundary between layers that differ, and earlier than in
either liquid alone under the same drive.

The temperature difference is borne out by Maquet and others, a vapor cushion at a step of one
kelvin between two liquids, without a uniform liquid under the same drive to compare. The density
difference is not tested: no source held reports shear or vapor at a density step. In all three
sources that score it the drive is heat or tension, not shear.

---

**The author's objection to the second-half score, given after it was written.** "dropping a ball
through hot water isn't really the same thing, the force of gravity brings the balls heat close
enough to the water that it generates a steam curtain, the reason it experiences lower drag is
only because the water is not able to apply its tension to it"

**Second half, rescored: open.** The objection holds. In Berry and others the vapor is made by the
heat stored in the sphere, and the body that rides on it is a solid. The drag falls because the
water cannot put its stress on the sphere through the vapor; their slip length,
$s \approx (\mu_L/\mu_V)\,\delta_V$, states that in Navier's terms. The claim is water riding
water on steam made by the shear between them. Maquet and others have one liquid riding another,
with the vapor made by the heat of the pool, and the liquids are ethanol and silicone oil. No
source held shows water riding water on steam, or steam made by shear. The criterion above
accepted a case the claim does not make. It stays as written, and the hit under it is withdrawn.

**A correction to the first-half reading.** Gruntfest and Becker reach $V_m$ by carrying the limit
$\varphi_c \le 1.187$ over from the case of a fixed stress. With the walls moving at a fixed
speed the steady layer has one solution at every speed, $V^2 = 8\int_{T_0}^{T_c} k/\mu\,dT$,
independent of the gap, and 1.187 marks the peak of the wall stress. With the IAPWS $\mu(T)$ and
$k(T)$ at atmospheric pressure the middle of the layer is at $20.06\,^\circ$C at 17 m/s and
reaches $100\,^\circ$C near 956 m/s. "No steady shear flow above $V_m$", in the score above,
holds for a fixed stress only. The miss stands on the speeds.
