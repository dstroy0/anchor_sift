// anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The shared control bar: one option model and one rendered surface for every blob viz unit, carrying
// the discipline the engine viewer's cfg.js holds. A unit hands the bar a schema, one entry per
// setting with its kind, its range and its fallback, and the opening values a build wrote. The bar
// draws one control per entry, and on every change it reports what it took and what it refused, each
// by name. An absent value takes its fallback. A value of the wrong kind or outside its range is named
// on the control that holds it and on the status line, and is not applied; the control stays. Nothing
// goes silently inert.
//
// The draw callback is the only place a change reaches the scene, and the bar calls it at most once an
// animation frame with the latest applied view. A control dragged through forty values applies forty
// times against the model and draws once a frame, so the drag stays smooth whatever the unit renders.
// The callback eases its targets and asks the unit for a frame; it never rebuilds geometry. The heavy
// transform is done once up front and the frame loop reads what it left.
//
// A builder injects this file whole at its marker, keeping each page a self-contained single file with
// one source for the bar. The unit calls BAR.mount with a container, its schema, the build's settings,
// and the draw callback. The bar styles its own controls from tokens that follow the page theme, so a
// unit supplies a bare host and every unit wears the same bar.

window.BAR = (function () {
  // Checks one value against its rule; returns the reason it errors, or null. The reasons read as a
  // control's allowed range, the same shape cfg.js reports.
  function errorValue(rule, value) {
    if (rule.kind === "int" || rule.kind === "float") {
      var number = rule.kind === "int"
        ? (typeof value === "number" && Number.isInteger(value))
        : (typeof value === "number" && Number.isFinite(value));
      if (!number) { return rule.kind === "int" ? "a whole number" : "a number"; }
      if (rule.low !== undefined && value < rule.low) { return "at least " + rule.low; }
      if (rule.high !== undefined && value > rule.high) { return "at most " + rule.high; }
      return null;
    }
    if (rule.kind === "switch") {
      return typeof value === "boolean" ? null : "on or off";
    }
    if (rule.kind === "word") {
      return rule.words.indexOf(value) >= 0 ? null : "one of " + rule.words.join(", ");
    }
    if (rule.kind === "color") {
      return (typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value)) ? null : "a color as #rrggbb";
    }
    // text takes any string.
    return typeof value === "string" ? null : "any text";
  }

  // A view with every setting at its fallback.
  function defaultView(schema) {
    var view = {};
    Object.keys(schema).forEach(function (name) { view[name] = schema[name].fallback; });
    return view;
  }

  // Applies a section over a view. Returns what was applied and what errored, each by name.
  function applyView(view, section, schema) {
    var applied = [];
    var error = [];
    if (!section || typeof section !== "object") {
      return { applied: applied, error: ["settings: an object of name to value"] };
    }
    Object.keys(section).forEach(function (name) {
      var rule = schema[name];
      if (!rule) { error.push(name + ": the bar has no such setting"); return; }
      var reason = errorValue(rule, section[name]);
      if (reason) { error.push(name + ": " + reason); return; }
      view[name] = section[name];
      applied.push(name);
    });
    return { applied: applied, error: error };
  }

  // The bar's own look, as tokens that read the page theme, injected once however many bars a page
  // holds. A unit gives the bar a bare host; the controls, their states and their spacing come from
  // here, so every unit wears one bar and a template carries none of this.
  var STYLE = [
    ".cbar{--cbar-ink:#e8edf6;--cbar-dim:#7f8798;--cbar-text:#9aa2b2;--cbar-line:#1d2230;",
    "--cbar-accent:#2f7fb5;--cbar-ok:#86c08a;--cbar-bad:#e7b0b8;--cbar-bad-bg:#180f14;",
    "--cbar-gap-2:10px;--cbar-gap-3:16px;--cbar-radius:6px;}",
    "[data-theme=light] .cbar{--cbar-ink:#1a1f29;--cbar-dim:#5a6372;--cbar-text:#323a48;",
    "--cbar-line:#c9d2e0;--cbar-bad:#8a2330;--cbar-bad-bg:#f6e8ea;}",
    ".cbar-strip{display:flex;flex-wrap:wrap;gap:var(--cbar-gap-3);align-items:start;}",
    ".cbar-row{display:grid;grid-template-columns:auto 1fr auto;align-items:center;",
    "column-gap:var(--cbar-gap-2);row-gap:2px;margin:0;color:var(--cbar-text);",
    "padding:4px 6px;border:1px solid transparent;border-radius:var(--cbar-radius);}",
    ".cbar-row:hover{border-color:var(--cbar-line);}",
    ".cbar-name{color:var(--cbar-dim);white-space:nowrap;}",
    ".cbar-field{accent-color:var(--cbar-accent);color:var(--cbar-ink);background:transparent;min-width:120px;}",
    ".cbar-field[type=range]{min-width:140px;}",
    ".cbar-field[type=color]{min-width:40px;width:40px;height:24px;padding:0;",
    "border:1px solid var(--cbar-line);border-radius:4px;}",
    ".cbar-field[type=checkbox]{min-width:0;width:16px;height:16px;}",
    ".cbar-field:focus-visible{outline:2px solid var(--cbar-accent);outline-offset:2px;}",
    ".cbar-value{color:var(--cbar-ink);min-width:2.5em;text-align:right;font-variant-numeric:tabular-nums;}",
    ".cbar-msg{grid-column:1 / -1;color:var(--cbar-bad);min-height:0;font-size:12px;}",
    ".cbar-row.is-invalid{border-color:var(--cbar-bad);background:var(--cbar-bad-bg);}",
    ".cbar-status{margin-top:var(--cbar-gap-2);color:var(--cbar-ok);min-height:1.2em;}",
  ].join("");

  function injectStyle() {
    if (document.getElementById("cbar-style")) { return; }
    var tag = document.createElement("style");
    tag.id = "cbar-style";
    tag.textContent = STYLE;
    document.head.appendChild(tag);
  }

  // Builds one control for a rule, reading view[name] for its opening value and writing it back through
  // report on every edit. Returns the row, the field and the row's message line, so mount can mark the
  // field that holds a refused value without searching the strip for it.
  function control(name, rule, view, report) {
    var row = document.createElement("label");
    row.className = "cbar-row";
    var caption = document.createElement("span");
    caption.className = "cbar-name";
    caption.textContent = name;

    var msg = document.createElement("span");
    msg.className = "cbar-msg";
    msg.id = "cbar-msg-" + name;

    var readout = null;
    var field;
    if (rule.kind === "word") {
      field = document.createElement("select");
      rule.words.forEach(function (word) {
        var option = document.createElement("option");
        option.value = word;
        option.textContent = word === "" ? "(system)" : word;
        field.appendChild(option);
      });
      field.value = view[name];
      field.addEventListener("change", function () { report(name, field.value); });
    } else if (rule.kind === "switch") {
      field = document.createElement("input");
      field.type = "checkbox";
      field.checked = view[name] === true;
      field.addEventListener("change", function () { report(name, field.checked); });
    } else if (rule.kind === "color") {
      field = document.createElement("input");
      field.type = "color";
      field.value = /^#[0-9a-fA-F]{6}$/.test(view[name]) ? view[name] : "#000000";
      field.addEventListener("input", function () { report(name, field.value); });
    } else if (rule.kind === "int" || rule.kind === "float") {
      var bounded = rule.low !== undefined && rule.high !== undefined;
      field = document.createElement("input");
      field.type = bounded ? "range" : "number";
      if (rule.low !== undefined) { field.min = rule.low; }
      if (rule.high !== undefined) { field.max = rule.high; }
      if (rule.kind === "int") { field.step = 1; }
      field.value = view[name];
      if (bounded) {
        readout = document.createElement("span");
        readout.className = "cbar-value";
        readout.setAttribute("aria-hidden", "true");
        readout.textContent = view[name];
      }
      field.addEventListener("input", function () {
        var text = field.value;
        var parsed = rule.kind === "int" ? parseInt(text, 10) : parseFloat(text);
        if (readout) { readout.textContent = field.value; }
        report(name, Number.isNaN(parsed) ? text : parsed);
      });
    } else {
      field = document.createElement("input");
      field.type = "text";
      field.value = view[name];
      field.addEventListener("input", function () { report(name, field.value); });
    }

    field.className = "cbar-field";
    field.setAttribute("aria-describedby", msg.id);
    row.appendChild(caption);
    row.appendChild(field);
    if (readout) { row.appendChild(readout); }
    row.appendChild(msg);
    return { row: row, field: field, msg: msg };
  }

  // Mounts the bar into container: a control per schema entry, opened at the build's settings over the
  // fallbacks, with a status line naming what each change took and refused. draw(view) is called once on
  // mount, and after that at most once an animation frame with the latest applied view.
  function mount(container, schema, settings, draw) {
    injectStyle();
    container.classList.add("cbar");
    var view = defaultView(schema);
    var opening = applyView(view, settings || {}, schema);

    var strip = document.createElement("div");
    strip.className = "cbar-strip";
    var status = document.createElement("div");
    status.className = "cbar-status";
    status.setAttribute("role", "status");
    status.setAttribute("aria-live", "polite");

    // The change reaches the scene here and only here, and no more than once a frame. A control's
    // every edit applies against the model at once, for the status line and the control's own state;
    // the draw it asks for is held to the next frame, so a drag coalesces to one draw however fast the
    // values arrive. The view the frame reads is the latest, since each edit writes it before asking.
    var pending = false;
    function schedule() {
      if (pending) { return; }
      pending = true;
      var raf = typeof requestAnimationFrame === "function"
        ? requestAnimationFrame
        : function (fn) { return setTimeout(fn, 16); };
      raf(function () { pending = false; draw(view); });
    }

    var rows = {};
    function say(name, value) {
      var one = {};
      one[name] = value;
      var report = applyView(view, one, schema);
      var reg = rows[name];
      if (report.error.length) {
        status.textContent = "refused " + report.error.join("; ");
        if (reg) {
          reg.row.classList.add("is-invalid");
          reg.field.setAttribute("aria-invalid", "true");
          reg.msg.textContent = report.error[0].slice((name + ": ").length);
        }
      } else {
        status.textContent = "applied " + name + " = " + view[name];
        if (reg) {
          reg.row.classList.remove("is-invalid");
          reg.field.removeAttribute("aria-invalid");
          reg.msg.textContent = "";
        }
        schedule();
      }
    }

    Object.keys(schema).forEach(function (name) {
      var built = control(name, schema[name], view, say);
      rows[name] = built;
      strip.appendChild(built.row);
    });
    container.appendChild(strip);
    container.appendChild(status);

    if (opening.error.length) {
      status.textContent = "the build asked for settings the bar refused: " + opening.error.join("; ");
    }
    draw(view);
    return view;
  }

  return { errorValue: errorValue, defaultView: defaultView, applyView: applyView, mount: mount };
})();
