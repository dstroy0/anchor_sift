// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The controls, emitted as one toolbar in the top left corner. Each id matches EV.CONTROLS, and each range and
// fallback matches the scheme.

EV.lightsRow = () => EV.element("div", { className: "inline" }, [
  EV.element("button", { type: "button", id: "lightFewer", className: "icon", title: "one fewer light", textContent: "−" }),
  EV.element("output", { id: "lightCount", textContent: "2", style: "min-width: 14px; text-align: center; font-variant-numeric: tabular-nums;" }),
  EV.element("button", { type: "button", id: "lightMore", className: "icon", title: "one more light", textContent: "+" }),
  EV.element("select", { id: "lightPick" }),
]);

EV.controlBar = EV.toolbar({
  id: "panel",
  title: "controls",
  corner: "top-left",
  sections: [
    { title: "object", rows: [{ select: "sample", label: "sample" }] },
    { title: "view", rows: [
      { range: "yaw", label: "turn", min: 0, max: 359, value: 30 },
      { range: "pitch", label: "tilt", min: -89, max: 89, value: 35 },
      { range: "zoom", label: "zoom", min: 1, max: 1024, value: 64 },
      { range: "zScale", label: "z scale", min: 2, max: 16, step: 2, value: 8 },
      { range: "spread", label: "spread", min: 0, max: 2048, step: 16, value: 0 },
    ] },
    { title: "cells", rows: [
      { select: "body", label: "draw as", options: [[0, "smooth"], [1, "voxels"], [2, "centroids"]] },
      { range: "smoothRadius", label: "smooth reach", min: 1, max: 8, value: 3 },
      { range: "smoothOpacity", label: "smooth opacity", min: 1, max: 255, value: 16 },
      { switches: [{ id: "walls", label: "cell walls", checked: true }] },
      { range: "wallTone", label: "wall lightness", min: 0, max: 255, value: 110 },
      { range: "wallOpacity", label: "wall opacity", min: 1, max: 255, value: 220 },
      { select: "palette", label: "color", options: [[1, "by lineage"], [3, "lineage, color-blind safe"], [0, "by cell"], [2, "by volume"]] },
      { range: "ghosts", label: "earlier frames", min: 0, max: 8, value: 0 },
      { range: "ghostFade", label: "their fade", min: 0, max: 224, value: 48 },
      { range: "minVoxels", label: "smallest", min: 0, max: 16, value: 0 },
      { switches: [{ id: "shadeOn", label: "light", checked: true }] },
      { range: "bodyOpacity", label: "body opacity", min: 0, max: 255, value: 160 },
      { range: "slide", label: "slide", min: 0, max: 255, value: 0, title: "fade between the microscope's own voxels and what the engine made of them" },
    ] },
    { title: "lights", rows: [
      { node: EV.lightsRow(), label: "sources" },
      { range: "lightTurnBox", label: "turn", min: 0, max: 359, value: 300 },
      { range: "lightTiltBox", label: "tilt", min: -89, max: 89, value: 50 },
      { range: "lightStrength", label: "strength", min: 0, max: 255, value: 210 },
      { note: "", text: "Drag a light's marker on the view to move it." },
    ] },
    { title: "show", rows: [
      { switches: [
        { id: "links", label: "links", checked: true }, { id: "tracks", label: "whole tracks" },
        { id: "edges", label: "answer key", checked: true }, { id: "onlyChosen", label: "only chosen" },
        { id: "glow", label: "glow chosen", checked: true }, { id: "ride", label: "labels ride" },
        { id: "labels", label: "labels", checked: true },
      ] },
      { switches: [
        { id: "status0", label: "correct", checked: true, tone: "good" }, { id: "status1", label: "branched", checked: true, tone: "warn" },
        { id: "status2", label: "wrong", checked: true, tone: "bad" }, { id: "status3", label: "no link", checked: true, tone: "none" },
      ] },
    ] },
    { title: "map", rows: [
      { switches: [{ id: "slice", label: "show the map", checked: true }] },
      { select: "mapMode", label: "shows", options: [["projection", "the whole volume from above"], ["slice", "one layer"]] },
      { switches: [{ id: "sliceFollow", label: "cells turn with the camera", checked: true }] },
      { range: "sliceZ", label: "depth z", min: 0, max: 63, value: 32 },
      { range: "windowLow", label: "black at", min: 0, max: 65535, value: 0 },
      { range: "windowHigh", label: "white at", min: 1, max: 65535, value: 1024 },
      { note: "rawNote" },
    ] },
    { title: "page", open: false, rows: [
      { range: "sheer", label: "panel opacity", min: 20, max: 100, value: 90 },
      { range: "textSize", label: "text size", min: 80, max: 200, step: 10, value: 100 },
      { select: "theme", label: "theme", options: [["dark", "dark"], ["light", "light"]] },
      { switches: [{ id: "vsync", label: "vsync", checked: true, title: "draw once per display refresh; off, draw as fast as the card finishes" }] },
    ] },
  ],
});
