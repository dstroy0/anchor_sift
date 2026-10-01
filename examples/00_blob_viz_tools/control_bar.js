// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The shared control bar: one option model for every blob viz unit, carrying the discipline the
// engine viewer's cfg.js holds. A unit hands the bar a schema, one entry per setting with its kind,
// its range and its fallback, and the opening values a build wrote. The bar draws one control per
// entry, and on every change it reports what it took and what it refused, each by name. An absent
// value takes its fallback. A value of the wrong kind or outside its range is named in the status
// line and not applied, and the control that holds it stays. Nothing goes silently inert.
//
// A builder injects this file whole at its marker, keeping each page a self-contained single file
// with one source for the bar. The unit calls BAR.mount with a container, its schema, the build's
// settings, and a draw callback the bar hands a view on every applied change.

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

  // Builds one control for a rule, reading and writing view[name]. report() runs on every edit.
  function control(name, rule, view, report) {
    var row = document.createElement("label");
    row.className = "bar-row";
    var caption = document.createElement("span");
    caption.className = "bar-name";
    caption.textContent = name;
    row.appendChild(caption);

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
      var readout = null;
      if (bounded) {
        readout = document.createElement("span");
        readout.className = "bar-value";
        readout.textContent = view[name];
      }
      field.addEventListener("input", function () {
        var text = field.value;
        var parsed = rule.kind === "int" ? parseInt(text, 10) : parseFloat(text);
        if (readout) { readout.textContent = field.value; }
        report(name, Number.isNaN(parsed) ? text : parsed);
      });
      row.appendChild(field);
      if (readout) { row.appendChild(readout); }
      return row;
    } else {
      field = document.createElement("input");
      field.type = "text";
      field.value = view[name];
      field.addEventListener("input", function () { report(name, field.value); });
    }
    row.appendChild(field);
    return row;
  }

  // Mounts the bar into container: a control per schema entry, opened at the build's settings over the
  // fallbacks, with a status line naming what each change took and refused. draw(view) is called once
  // on mount and again on every applied change.
  function mount(container, schema, settings, draw) {
    var view = defaultView(schema);
    var opening = applyView(view, settings || {}, schema);

    var strip = document.createElement("div");
    strip.className = "bar-strip";
    var status = document.createElement("div");
    status.className = "bar-status";

    function say(name, value) {
      var one = {};
      one[name] = value;
      var report = applyView(view, one, schema);
      if (report.error.length) {
        status.textContent = "refused " + report.error.join("; ");
      } else {
        status.textContent = "applied " + name + " = " + view[name];
        draw(view);
      }
    }

    Object.keys(schema).forEach(function (name) {
      strip.appendChild(control(name, schema[name], view, say));
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
