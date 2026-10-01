// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The floating toolbar emitter. A page hands EV.toolbar a spec and gets back one toolbar in a corner: a menu button
// that opens it, and folding sections of rows. Every control is emitted with the id the spec gives it, and the page
// binds its controls by id as it would hand-written markup. A slider's value shows in an output whose id is the
// slider's id followed by "Out".
//
//   EV.toolbar({ id, title, corner: "top-left" | "top-right", open, onToggle(open), sections: [
//     { title, open, rows: [
//       { range: id, label, min, max, step, value, title },
//       { select: id, label, options: [[value, text], { group, options: [[value, text], ...] }, ...], value, title },
//       { number: id, label, min, max, step, value },
//       { switches: [{ id, label, checked, tone, title }, ...] },
//       { buttons: [{ id, text, title, icon }, ...], label },
//       { note: id, text },
//       { node: element, label },
//     ] },
//   ] })
//
// The toolbar returned carries root, isOpen() and setOpen(open). Escape inside it closes it and gives the focus back
// to its button.

EV.element = (tag, properties, children) => {
  const made = Object.assign(document.createElement(tag), properties || {});
  for (const child of children || []) {
    made.append(child);
  }
  return made;
};

// A slider's fill follows its value, however the value is set: by the pointer, by the keys, or by a program.
EV.fillSlider = (slider) => {
  const own = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value");
  const paint = () => {
    const low = Number(slider.min || 0);
    const high = Number(slider.max || 100);
    const at = high > low ? ((Number(own.get.call(slider)) - low) * 100) / (high - low) : 0;
    slider.style.setProperty("--fill", `${Math.max(0, Math.min(100, at))}%`);
  };
  Object.defineProperty(slider, "value", {
    configurable: true,
    get: () => own.get.call(slider),
    set: (value) => { own.set.call(slider, value); paint(); },
  });
  for (const name of ["min", "max"]) {
    const bound = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, name);
    Object.defineProperty(slider, name, {
      configurable: true,
      get: () => bound.get.call(slider),
      set: (value) => { bound.set.call(slider, value); paint(); },
    });
  }
  slider.addEventListener("input", paint);
  paint();
  return slider;
};

EV.toolbarRow = (row) => {
  const label = (text, target) => EV.element("label", { textContent: text, htmlFor: target || "" });
  if (row.range) {
    const slider = EV.element("input", { type: "range", id: row.range, min: String(row.min), max: String(row.max),
                                         step: String(row.step || 1), value: String(row.value), title: row.title || "" });
    return EV.element("div", { className: "row", title: row.title || "" },
                      [label(row.label, row.range), EV.fillSlider(slider), EV.element("output", { id: `${row.range}Out`, htmlFor: row.range })]);
  }
  if (row.select) {
    const option = ([value, text]) => EV.element("option", { value: String(value), textContent: text });
    const select = EV.element("select", { id: row.select, title: row.title || "" },
                              (row.options || []).map((one) => (Array.isArray(one) ? option(one)
                                : EV.element("optgroup", { label: one.group }, one.options.map(option)))));
    if (row.value !== undefined) {
      select.value = String(row.value);
    }
    return EV.element("div", { className: "row" }, [label(row.label, row.select), select]);
  }
  if (row.number) {
    const field = EV.element("input", { type: "number", id: row.number, min: String(row.min), max: String(row.max),
                                        step: String(row.step || 1), value: String(row.value) });
    return EV.element("div", { className: "row" }, [label(row.label, row.number), field]);
  }
  if (row.switches) {
    return EV.element("div", { className: "switches" }, row.switches.map((one) => {
      const box = EV.element("input", { type: "checkbox", id: one.id, checked: !!one.checked });
      if (one.tone) {
        box.dataset.tone = one.tone;
      }
      return EV.element("label", { className: "check", title: one.title || "" }, [box, one.label]);
    }));
  }
  if (row.buttons) {
    const strip = EV.element("div", { className: "inline" }, row.buttons.map((one) => EV.element("button", {
      type: "button", id: one.id, textContent: one.text, title: one.title || "", className: one.icon ? "icon" : "",
    })));
    return row.label === undefined ? strip : EV.element("div", { className: "row" }, [EV.element("span", { className: "label", textContent: row.label }), strip]);
  }
  if (row.note !== undefined) {
    return EV.element("div", { className: "note", id: row.note || "", textContent: row.text || "" });
  }
  if (row.node) {
    return row.label === undefined ? row.node : EV.element("div", { className: "row" }, [EV.element("span", { className: "label", textContent: row.label }), row.node]);
  }
  throw new Error("a toolbar row is a range, select, number, switches, buttons, note or node");
};

EV.toolbar = (spec) => {
  const button = EV.element("button", { type: "button", className: "toolbar-button", title: spec.title || "" },
                            [EV.element("span"), EV.element("span"), EV.element("span")]);
  const body = EV.element("div", { className: "toolbar-body", id: `${spec.id}Body` },
                          spec.sections.map((section) => EV.element("details", { className: "section", open: section.open !== false },
                            [EV.element("summary", { textContent: section.title }),
                             EV.element("div", { className: "rows" }, section.rows.map(EV.toolbarRow))])));
  const root = EV.element("nav", { id: spec.id, className: "toolbar" },
                          [EV.element("div", { className: "toolbar-head" }, [button, EV.element("span", { className: "toolbar-title", textContent: spec.title || "" })]), body]);
  root.dataset.corner = spec.corner || "top-left";
  root.setAttribute("aria-label", spec.title || spec.id);
  button.setAttribute("aria-controls", body.id);
  const setOpen = (open) => {
    root.classList.toggle("open", !!open);
    button.setAttribute("aria-expanded", open ? "true" : "false");
    body.inert = !open;
    if (spec.onToggle) {
      spec.onToggle(!!open);
    }
  };
  button.addEventListener("click", () => setOpen(!root.classList.contains("open")));
  root.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && root.classList.contains("open")) {
      setOpen(false);
      button.focus();
    }
  });
  document.body.appendChild(root);
  setOpen(!!spec.open);
  return { root, button, body, isOpen: () => root.classList.contains("open"), setOpen };
};
