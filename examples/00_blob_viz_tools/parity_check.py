"""Do the bar and the scheme judge a setting alike, and does the frame watch report what it exists to report?

    python examples/00_blob_viz_tools/parity_check.py --check

THE DEFECT THIS EXISTS FOR

Two option models live in the toolbox. ui/bar.js is the bar the blob viz units mount; core/scheme.js
is the scheme the engine view and the shapes gallery apply. Both take a section of settings, apply what
is valid and name what is not, and a reader moving between pages expects one answer to one question.
Each model has its own tests of its own behavior, and nothing holds the two to each other. A range
check that drifts in one turns a value one page takes into a value another page refuses.

The frame watch, core/watch.js, is a reporter: it is only worth its place on a page if it reports a
loop that throws, a loop that stops turning and a page with no device to draw on, and stays quiet for
a page that is hidden or a loop that is asleep with nothing to draw. A reporter nobody has seen fire
is a reporter nobody has tested.

WHAT IT DOES

Loads both models into node beside one table of rules and values, in the kinds both carry: a bounded
whole number, a switch and a word. Each case is applied through both, and the names taken, the names
refused and the view that results must agree. The bar's int is the scheme's integer.

Loads the watch into node with a frame clock and a timer it drives by hand, runs each kind of loop
through it, and holds window.__loopHealth to the verdict each one must give.

Reads every tracked page in view/ and every page in build/view and holds each one's loops to the
same rule script_check holds a template to: a page whose code schedules frames hands every loop to
the watch and carries it.

A missing node is reported and never treated as a pass.
"""

import io
import json
import os
import subprocess
import sys
import tempfile

import script_check

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLBOX = os.path.join(HERE, "toolbox")
ROOT = os.path.dirname(os.path.dirname(HERE))
PAGES = [os.path.join(HERE, "view"), os.path.join(ROOT, "build", "view")]

# One rule per shared kind, written once and given to each model in its own words.
RULES = {
    "count": {"bar": {"kind": "int", "low": 3, "high": 9, "fallback": 5},
              "scheme": {"kind": "integer", "low": 3, "high": 9, "fallback": 5}},
    "spin": {"bar": {"kind": "switch", "fallback": True}, "scheme": {"kind": "switch", "fallback": True}},
    "face": {"bar": {"kind": "word", "words": ["human", "machine"], "fallback": "human"},
             "scheme": {"kind": "word", "words": ["human", "machine"], "fallback": "human"}},
}

# Each case is a section applied over the fallbacks. Every edge of every rule, and every wrong kind.
CASES = [
    {"count": 3}, {"count": 9}, {"count": 6}, {"count": 2}, {"count": 10}, {"count": 4.5}, {"count": "4"},
    {"count": None}, {"count": True}, {"spin": False}, {"spin": True}, {"spin": "on"}, {"spin": 1},
    {"face": "machine"}, {"face": "human"}, {"face": "clinical"}, {"face": 0}, {"face": "Machine"},
    {"count": 7, "spin": False, "face": "machine"}, {"count": 99, "spin": False}, {"ghost": 1},
    {"count": 8, "ghost": 1, "face": "nobody"}, {},
]

PARITY_JS = r"""
const window = {};
const document = { createElement: () => ({ appendChild() {}, addEventListener() {} }) };
const EV = {};
%(bar)s
%(scheme)s
const RULES = %(rules)s;
const CASES = %(cases)s;
const barSchema = {};
EV.VIEW_SCHEME = {};
for (const [name, rule] of Object.entries(RULES)) {
  barSchema[name] = rule.bar;
  EV.VIEW_SCHEME[name] = rule.scheme;
}
const named = (list) => list.map((one) => one.split(":")[0]).sort();
const out = { defaults: [JSON.stringify(window.BAR.defaultView(barSchema)), JSON.stringify(EV.defaultView())], cases: [] };
for (const section of CASES) {
  const barView = window.BAR.defaultView(barSchema);
  const schemeView = EV.defaultView();
  const bar = window.BAR.applyView(barView, section, barSchema);
  const scheme = EV.applyView(schemeView, section);
  out.cases.push({ section, bar: { applied: named(bar.applied), refused: named(bar.error), view: barView },
                   scheme: { applied: named(scheme.applied), refused: named(scheme.error), view: schemeView } });
}
console.log(JSON.stringify(out));
"""

WATCH_JS = r"""
let now = 0;
let frames = [];
let timers = [];
const listeners = {};
const page = { hidden: false };
const made = [];
const document = {
  get visibilityState() { return page.hidden ? "hidden" : "visible"; },
  get hidden() { return page.hidden; },
  addEventListener: (name, fn) => { (listeners[name] = listeners[name] || []).push(fn); },
  getElementById: (id) => made.find((one) => one.id === id) || null,
  createElement: () => { const one = { style: {}, setAttribute() {}, hidden: true, textContent: "" }; made.push(one); return one; },
  body: { appendChild() {} },
};
const window = {};
const requestAnimationFrame = (fn) => { frames.push(fn); return frames.length; };
const setTimeout = (fn, wait) => { timers.push({ at: now + wait, fn }); return timers.length; };
const clearTimeout = () => {};
console.error = () => {};
const EV = {};
%(clock)s
%(watch)s
// One display refresh: every queued frame runs, then every timer that has come due.
const refresh = (count = 1) => {
  for (let one = 0; one < count; one++) {
    now += 16;
    const due = frames;
    frames = [];
    due.forEach((fn) => fn(now));
    const ready = timers.filter((timer) => timer.at <= now);
    timers = timers.filter((timer) => timer.at > now);
    ready.forEach((timer) => timer.fn());
  }
};
// Time passing with the frame clock held, as a browser holds it for a hidden page or a stopped loop.
const wait = (ms) => {
  now += ms;
  const ready = timers.filter((timer) => timer.at <= now);
  timers = timers.filter((timer) => timer.at > now);
  ready.forEach((timer) => timer.fn());
};
const fresh = () => { EV.loops.length = 0; frames = []; timers = []; made.length = 0; page.hidden = false; };
const health = () => { const one = window.__loopHealth; return { ok: one.ok, turns: one.turns, why: one.why }; };
const out = {};

fresh();
out.nothing = health();

fresh();
EV.watchLoop("steady", () => {}).wake();
refresh(3);
out.steady = health();

fresh();
EV.watchLoop("throws", () => { throw new Error("broken step"); }).wake();
refresh(3);
out.throws = health();
out.throwsShown = made.some((one) => one.id === "loopAlarm" && !one.hidden);

fresh();
EV.watchLoop("held", () => {}).wake();
wait(1600);
out.dead = health();

fresh();
page.hidden = true;
EV.watchLoop("hidden", () => {}).wake();
wait(1600);
out.hidden = health();
page.hidden = false;
(listeners.visibilitychange || []).forEach((fn) => fn());
refresh(3);
wait(1600);
out.shown = health();

fresh();
const asleep = EV.watchLoop("on demand", () => false);
out.neverWoken = health();
asleep.wake();
refresh(2);
wait(1600);
out.sleptAfterOne = health();

fresh();
EV.noLoop("no device", "no device", "the page has nothing to draw on");
out.noDevice = health();

fresh();
EV.watchLoop("first", () => {}).wake();
EV.watchLoop("second", () => { throw new Error("second breaks"); }).wake();
refresh(3);
out.oneOfTwo = health();
console.log(JSON.stringify(out));
process.exit(0);
"""


def read(path):
    with io.open(path, encoding="utf-8") as handle:
        return handle.read()


def node(source):
    """(parsed output, None) from running source in node, or (None, reason)."""
    handle = tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8")
    try:
        handle.write(source)
        handle.close()
        done = subprocess.run(["node", handle.name], capture_output=True, text=True, timeout=60)
        if done.returncode != 0:
            return None, done.stderr.strip()[-600:]
        return json.loads(done.stdout.strip().splitlines()[-1]), None
    except FileNotFoundError:
        return None, "node is not on the path, so nothing was run"
    except subprocess.TimeoutExpired:
        return None, "node did not finish"
    finally:
        try:
            os.unlink(handle.name)
        except OSError:
            pass


def parity(lines):
    source = PARITY_JS % {"bar": read(os.path.join(TOOLBOX, "ui", "bar.js")),
                          "scheme": read(os.path.join(TOOLBOX, "core", "scheme.js")),
                          "rules": json.dumps(RULES), "cases": json.dumps(CASES)}
    got, why = node(source)
    if got is None:
        lines.append("  NOT RUN: %s" % why)
        return 1
    failed = 0
    if got["defaults"][0] != got["defaults"][1]:
        lines.append("  FAIL the two models open at different views: bar %s, scheme %s" % tuple(got["defaults"]))
        failed += 1
    for case in got["cases"]:
        bar, scheme = case["bar"], case["scheme"]
        if bar == scheme:
            continue
        lines.append("  FAIL %s: bar takes %s and refuses %s, scheme takes %s and refuses %s"
                     % (json.dumps(case["section"]), bar["applied"], bar["refused"], scheme["applied"], scheme["refused"]))
        failed += 1
    lines.append("  %d section(s) applied through both models, %d disagreement(s)" % (len(got["cases"]), failed))
    return failed


# The verdict each loop must give: ok, and a word its reason carries.
WANTED = [
    ("nothing", None, "no frame loop", "a page with no loop has no verdict"),
    ("steady", True, "turned twice", "a loop that turns is healthy"),
    ("throws", False, "threw on turn 1", "a loop that throws is reported"),
    ("dead", False, "turned 0 time(s)", "a loop that never turns in its patience is reported"),
    ("hidden", None, "not judged yet", "a hidden page is not judged"),
    ("shown", True, "turned twice", "a page seen again is judged again, and passes"),
    ("neverWoken", True, "asleep", "a loop never woken is asleep and healthy"),
    ("sleptAfterOne", True, "asleep", "a loop that draws once and sleeps is healthy"),
    ("noDevice", False, "no device", "a page with no device says so"),
    ("oneOfTwo", False, "second", "one failed loop of two fails the page"),
]


def watch(lines):
    source = WATCH_JS % {"clock": read(os.path.join(TOOLBOX, "core", "clock.js")),
                         "watch": read(os.path.join(TOOLBOX, "core", "watch.js"))}
    got, why = node(source)
    if got is None:
        lines.append("  NOT RUN: %s" % why)
        return 1
    failed = 0
    for key, ok, word, label in WANTED:
        one = got[key]
        good = one["ok"] is ok and word in one["why"]
        lines.append("  %s%s: ok %s, %s" % ("" if good else "FAIL ", label, one["ok"], one["why"]))
        failed += 0 if good else 1
    shown = got.get("throwsShown") is True
    lines.append("  %sa throw shows on the page as well" % ("" if shown else "FAIL "))
    return failed + (0 if shown else 1)


def pages(lines):
    failed = 0
    seen = 0
    for folder in PAGES:
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".html"):
                continue
            state, findings = script_check.loop_watch(read(os.path.join(folder, name)))
            if state == "none":
                continue
            seen += 1
            if state == "unwatched":
                where = os.path.relpath(os.path.join(folder, name), ROOT).replace("\\", "/")
                lines.append("  FAIL %s: %s" % (where, "; ".join(findings)))
                failed += 1
    lines.append("  %d page(s) with a frame loop, %d unwatched" % (seen, failed))
    return failed


def _check():
    lines = ["  the bar and the scheme"]
    failed = parity(lines)
    lines.append("  the frame watch")
    failed += watch(lines)
    lines.append("  the tracked and built pages")
    failed += pages(lines)
    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        sys.exit(1 if _check() else 0)
    sys.stdout.write(__doc__)
    sys.exit(2)
