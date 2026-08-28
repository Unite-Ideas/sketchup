/* Outliner Reforged - panel logic
 * Talks to Ruby via sketchup.msg(JSON). Ruby pushes state back through the
 * global OR object below. The tree is virtualized: the model tree is flattened
 * to a list of visible rows and only the rows inside the viewport are in the
 * DOM, so a model with tens of thousands of entities stays smooth. */
(function () {
  "use strict";

  var ROW_H = 24;   // must match --row-h in panel.css
  var BUFFER = 8;   // extra rows rendered above/below the viewport

  var state = {
    nodes: [],
    flat: [],            // [{node, depth}]
    indexById: {},       // pid -> flat index
    selected: {},        // pid -> true
    schemes: [],
    settings: {},
    filtersOpen: false,
    editing: false       // a rename input is open; pause slice rebuilds
  };

  // ---- bridge -------------------------------------------------------------
  function send(action, extra) {
    var payload = Object.assign({ action: action }, extra || {});
    if (window.sketchup && sketchup.msg) {
      sketchup.msg(JSON.stringify(payload));
    } else {
      console.log("[dev] send", payload);
    }
  }

  var el = {
    tree: document.getElementById("tree"),
    empty: document.getElementById("empty"),
    status: document.getElementById("statusbar"),
    search: document.getElementById("search"),
    filterBtn: document.getElementById("filter-btn"),
    filters: document.getElementById("filters"),
    fType: document.getElementById("f-type"),
    fTag: document.getElementById("f-tag"),
    fLocked: document.getElementById("f-locked"),
    fHidden: document.getElementById("f-hidden"),
    fNoMat: document.getElementById("f-nomat"),
    scheme: document.getElementById("scheme"),
    schemeEdit: document.getElementById("scheme-edit"),
    sort: document.getElementById("sort"),
    showall: document.getElementById("showall"),
    ctx: document.getElementById("ctxmenu"),
    // rules modal
    rulesModal: document.getElementById("rules-modal"),
    rulesList: document.getElementById("rules-list"),
    rulesAdd: document.getElementById("rules-add"),
    rulesSave: document.getElementById("rules-save"),
    rulesClose: document.getElementById("rules-close"),
    // batch modal
    batchModal: document.getElementById("batch-modal"),
    batchTitle: document.getElementById("batch-title"),
    batchPattern: document.getElementById("batch-pattern"),
    batchStart: document.getElementById("batch-start"),
    batchPreview: document.getElementById("batch-preview"),
    batchApply: document.getElementById("batch-apply"),
    batchClose: document.getElementById("batch-close")
  };

  // the absolutely-positioned scroll canvas
  var canvas = document.createElement("div");
  canvas.id = "tree-canvas";
  el.tree.appendChild(canvas);

  // ---- inbound API (called by Ruby) --------------------------------------
  window.OR = {
    render: function (nodes) {
      state.nodes = nodes || [];
      buildFlat();
      renderTree();
      updateStatus();
    },
    setSelection: function (pids) {
      state.selected = {};
      (pids || []).forEach(function (p) { if (p) state.selected[p] = true; });
      renderSlice();
      scrollToFirstSelected();
      updateStatus();
    },
    setSettings: function (s) {
      state.settings = s || {};
      state.schemes = s.schemes || [];
      applySettings();
    },
    setTags: function (tags) {
      var cur = el.fTag.value;
      el.fTag.innerHTML = '<option value="any">Any</option>';
      (tags || []).forEach(function (t) {
        var o = document.createElement("option");
        o.value = t; o.textContent = t;
        el.fTag.appendChild(o);
      });
      el.fTag.value = cur;
    }
  };

  function applySettings() {
    el.scheme.innerHTML = "";
    state.schemes.forEach(function (s) {
      var o = document.createElement("option");
      o.value = s.id; o.textContent = s.label;
      el.scheme.appendChild(o);
    });
    if (state.settings.color_scheme) el.scheme.value = state.settings.color_scheme;
    if (state.settings.sort) el.sort.value = state.settings.sort;
    el.showall.checked = truthy(state.settings.show_all);
  }

  // ---- flatten + virtualized render --------------------------------------
  function buildFlat() {
    state.flat = [];
    state.indexById = {};
    (function walk(nodes, depth) {
      nodes.forEach(function (n) {
        state.indexById[n.id] = state.flat.length;
        state.flat.push({ node: n, depth: depth });
        if (n.children && n.children.length) walk(n.children, depth + 1);
      });
    })(state.nodes, 0);
  }

  function renderTree() {
    canvas.style.height = (state.flat.length * ROW_H) + "px";
    el.empty.classList.toggle("hidden", state.flat.length > 0);
    renderSlice();
  }

  var sliceQueued = false;
  function scheduleSlice() {
    if (sliceQueued) return;
    sliceQueued = true;
    requestAnimationFrame(function () { sliceQueued = false; renderSlice(); });
  }

  function renderSlice() {
    if (state.editing) return; // don't yank the row out from under an editor
    var scrollTop = el.tree.scrollTop;
    var vh = el.tree.clientHeight || 400;
    var start = Math.max(0, Math.floor(scrollTop / ROW_H) - BUFFER);
    var end = Math.min(state.flat.length, Math.ceil((scrollTop + vh) / ROW_H) + BUFFER);

    var frag = document.createDocumentFragment();
    for (var i = start; i < end; i++) {
      var item = state.flat[i];
      frag.appendChild(buildRow(item.node, item.depth, i));
    }
    canvas.innerHTML = "";
    canvas.appendChild(frag);
  }

  function buildRow(node, depth, index) {
    var row = document.createElement("div");
    row.className = "row";
    row.dataset.id = node.id;
    row.dataset.type = node.type;
    row.style.top = (index * ROW_H) + "px";
    row.style.height = ROW_H + "px";
    row.style.paddingLeft = (6 + depth * 14) + "px";
    if (node.hidden) row.classList.add("dim");
    if (state.selected[node.id]) row.classList.add("selected");

    // caret
    var caret = document.createElement("span");
    if (node.expandable) {
      caret.className = "caret" + (node.expanded ? " open" : "");
      caret.textContent = "\u25B6";
      caret.addEventListener("click", function (e) {
        e.stopPropagation();
        send("toggle_expand", { id: node.id, expanded: !node.expanded });
      });
    } else {
      caret.className = "caret spacer";
    }
    row.appendChild(caret);

    // type glyph
    var glyph = document.createElement("span");
    glyph.className = "tglyph";
    glyph.textContent = glyphFor(node.type);
    row.appendChild(glyph);

    // name
    var name = document.createElement("span");
    name.className = "name";
    name.textContent = node.name;
    if (node.color) name.style.color = node.color;
    row.appendChild(name);

    // badges
    var badges = document.createElement("span");
    badges.className = "badges";
    (node.badges || []).forEach(function (b) { badges.appendChild(badgeEl(b)); });
    row.appendChild(badges);

    // tag color chip
    if (node.tagColor) {
      var chip = document.createElement("span");
      chip.className = "tagchip";
      chip.style.background = node.tagColor;
      chip.title = node.tag || "";
      row.appendChild(chip);
    }

    if (node.selectable !== false) {
      row.addEventListener("click", function (e) {
        send("select", { id: node.id, add: e.ctrlKey || e.metaKey || e.shiftKey });
      });
      row.addEventListener("dblclick", function (e) {
        e.preventDefault();
        if (node.type === "group" || node.type === "component") startRename(row, name, node);
      });
      row.addEventListener("contextmenu", function (e) {
        e.preventDefault();
        if (!state.selected[node.id]) send("select", { id: node.id, add: false });
        openContextMenu(e.clientX, e.clientY, node);
      });
    }
    return row;
  }

  function badgeEl(b) {
    var s = document.createElement("span");
    if (b === "lock") { s.className = "badge lock"; s.textContent = "\uD83D\uDD12"; s.title = "Locked"; }
    else if (b === "hidden") { s.className = "badge hidden"; s.textContent = "\uD83D\uDC41"; s.title = "Hidden"; }
    else if (b === "dyn") { s.className = "badge dyn"; s.textContent = "\u26A1"; s.title = "Dynamic component"; }
    else if (b[0] === "x") { s.className = "badge count"; s.textContent = b; s.title = b.slice(1) + " instances"; }
    else { s.className = "badge"; s.textContent = b; }
    return s;
  }

  function glyphFor(type) {
    switch (type) {
      case "group": return "\u25A2";
      case "component": return "\u25C8";
      case "image": return "\u25A6";
      case "section": return "\u25F0";
      case "geometry": return "\u2500";
      case "text": case "dimension": return "\u2137";
      case "guide": return "\u00B7";
      default: return "\u2022";
    }
  }

  function scrollToFirstSelected() {
    var idx = -1;
    for (var id in state.selected) {
      if (state.indexById[id] !== undefined) {
        idx = (idx === -1) ? state.indexById[id] : Math.min(idx, state.indexById[id]);
      }
    }
    if (idx === -1) return;
    var top = idx * ROW_H;
    var vh = el.tree.clientHeight;
    if (top < el.tree.scrollTop || top + ROW_H > el.tree.scrollTop + vh) {
      el.tree.scrollTop = Math.max(0, top - vh / 3);
    }
    renderSlice();
  }

  function updateStatus() {
    var n = state.flat.length;
    var sel = Object.keys(state.selected).length;
    var msg = n + (n === 1 ? " row" : " rows");
    if (sel > 0) msg += " · " + sel + " selected";
    el.status.textContent = msg;
  }

  // ---- rename -------------------------------------------------------------
  function startRename(row, nameEl, node) {
    state.editing = true;
    nameEl.classList.add("editing");
    var input = document.createElement("input");
    input.className = "rename-input";
    input.value = node.name;
    nameEl.textContent = "";
    nameEl.appendChild(input);
    input.focus();
    input.select();
    var done = false;
    function commit(save) {
      if (done) return; done = true;
      state.editing = false;
      if (save && input.value.trim() !== "" && input.value !== node.name) {
        send("rename", { id: node.id, name: input.value.trim() });
      } else {
        nameEl.textContent = node.name;
      }
    }
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); commit(true); }
      else if (e.key === "Escape") { e.preventDefault(); commit(false); }
      e.stopPropagation();
    });
    input.addEventListener("blur", function () { commit(true); });
    input.addEventListener("click", function (e) { e.stopPropagation(); });
  }

  // ---- context menu -------------------------------------------------------
  function openContextMenu(x, y, node) {
    var isContainer = node.type === "group" || node.type === "component";
    var selIds = Object.keys(state.selected);
    var multi = selIds.length > 1;
    var items = [];

    if (multi) {
      items.push({ label: "Rename " + selIds.length + " selected…", act: "__batch" });
      items.push({ sep: true });
    }
    if (isContainer) {
      items.push({ label: "Move to Top Level", act: "move_to_top", cls: "headline" });
      items.push({ label: "Move Up One Level", act: "move_up" });
      items.push({ sep: true });
    }
    items.push({ label: "Zoom to", act: "zoom" });
    if (isContainer) {
      items.push({ label: "Isolate", act: "isolate" });
      items.push({ label: "Select All Instances", act: "select_instances" });
    }
    items.push({ label: "Show All (unhide)", act: "show_all" });
    items.push({ sep: true });
    if (isContainer && !multi) items.push({ label: "Rename…", act: "__rename" });
    items.push({ label: node.hidden ? "Unhide" : "Hide", act: "toggle_visible" });
    items.push({ label: node.locked ? "Unlock" : "Lock", act: "toggle_lock" });
    if (isContainer) {
      items.push({ label: "Make Unique", act: "make_unique", disabled: (node.count || 1) < 2 });
      items.push({ label: "Explode", act: "explode" });
    }
    items.push({ sep: true });
    items.push({ label: "Delete", act: "delete", cls: "danger" });

    var ul = el.ctx;
    ul.innerHTML = "";
    items.forEach(function (it) {
      var li = document.createElement("li");
      if (it.sep) { li.className = "sep"; ul.appendChild(li); return; }
      li.textContent = it.label;
      if (it.cls) li.className = it.cls;
      if (it.disabled) li.classList.add("disabled");
      li.addEventListener("click", function () {
        closeContextMenu();
        if (it.act === "__rename") {
          var row = canvas.querySelector('.row[data-id="' + cssEsc(node.id) + '"]');
          if (row) startRename(row, row.querySelector(".name"), node);
        } else if (it.act === "__batch") {
          openBatchModal(selIds);
        } else {
          send("action", { name: it.act, id: node.id });
        }
      });
      ul.appendChild(li);
    });

    ul.classList.remove("hidden");
    var w = ul.offsetWidth, h = ul.offsetHeight;
    if (x + w > window.innerWidth) x = window.innerWidth - w - 4;
    if (y + h > window.innerHeight) y = window.innerHeight - h - 4;
    ul.style.left = x + "px";
    ul.style.top = y + "px";
  }

  function closeContextMenu() { el.ctx.classList.add("hidden"); }

  // ---- color-rule editor --------------------------------------------------
  var FIELDS = [
    { id: "tag", label: "Tag", kind: "text" },
    { id: "type", label: "Type", kind: "type" },
    { id: "locked", label: "Locked", kind: "bool" },
    { id: "hidden", label: "Hidden", kind: "bool" },
    { id: "unique", label: "Unique", kind: "bool" },
    { id: "material", label: "Has material", kind: "bool" },
    { id: "dynamic", label: "Dynamic", kind: "bool" }
  ];
  var TYPES = ["group", "component", "image", "section", "dimension", "text", "guide"];

  function openRulesModal() {
    renderRules(state.settings.rules || []);
    el.rulesModal.classList.remove("hidden");
  }
  function closeRulesModal() { el.rulesModal.classList.add("hidden"); }

  function renderRules(rules) {
    el.rulesList.innerHTML = "";
    if (!rules.length) {
      var em = document.createElement("div");
      em.className = "rules-empty";
      em.textContent = "No rules yet. Add one below.";
      el.rulesList.appendChild(em);
    }
    rules.forEach(function (r) { el.rulesList.appendChild(ruleRow(r)); });
  }

  function ruleRow(rule) {
    var row = document.createElement("div");
    row.className = "rule-row";

    var fsel = document.createElement("select");
    FIELDS.forEach(function (f) {
      var o = document.createElement("option");
      o.value = f.id; o.textContent = f.label;
      fsel.appendChild(o);
    });
    fsel.value = rule.field || "tag";

    var opsel = document.createElement("select");
    var valWrap = document.createElement("span");
    var color = document.createElement("input");
    color.type = "color";
    color.value = /^#[0-9a-fA-F]{6}$/.test(rule.color || "") ? rule.color : "#3355e6";

    function rebuildOps() {
      var f = FIELDS.find(function (x) { return x.id === fsel.value; });
      opsel.innerHTML = "";
      var ops = (f.kind === "bool")
        ? [["is", "is"], ["isnot", "is not"]]
        : [["eq", "="], ["neq", "≠"]];
      ops.forEach(function (p) {
        var o = document.createElement("option");
        o.value = p[0]; o.textContent = p[1];
        opsel.appendChild(o);
      });
      if (rule.op) opsel.value = rule.op;
      valWrap.innerHTML = "";
      if (f.kind === "text") {
        var inp = document.createElement("input");
        inp.type = "text"; inp.placeholder = "value"; inp.value = rule.value || "";
        inp.dataset.role = "val";
        valWrap.appendChild(inp);
      } else if (f.kind === "type") {
        var sel = document.createElement("select");
        TYPES.forEach(function (t) {
          var o = document.createElement("option");
          o.value = t; o.textContent = t;
          sel.appendChild(o);
        });
        sel.value = rule.value || "group";
        sel.dataset.role = "val";
        valWrap.appendChild(sel);
      } // bool: no value field
    }
    fsel.addEventListener("change", rebuildOps);
    rebuildOps();

    var del = document.createElement("button");
    del.className = "del"; del.textContent = "×"; del.title = "Remove";
    del.addEventListener("click", function () { row.remove(); if (!el.rulesList.children.length) renderRules([]); });

    row.appendChild(fsel);
    row.appendChild(opsel);
    row.appendChild(valWrap);
    row.appendChild(color);
    row.appendChild(del);
    return row;
  }

  function collectRules() {
    var out = [];
    el.rulesList.querySelectorAll(".rule-row").forEach(function (row) {
      var sels = row.querySelectorAll("select");
      var field = sels[0].value;
      var op = sels[1].value;
      var valEl = row.querySelector('[data-role="val"]');
      var color = row.querySelector('input[type="color"]').value;
      out.push({ field: field, op: op, value: valEl ? valEl.value : "", color: color });
    });
    return out;
  }

  // ---- batch rename -------------------------------------------------------
  var batchIds = [];
  function openBatchModal(ids) {
    batchIds = ids.slice();
    el.batchTitle.textContent = "Batch Rename (" + ids.length + ")";
    updateBatchPreview();
    el.batchModal.classList.remove("hidden");
    el.batchPattern.focus();
    el.batchPattern.select();
  }
  function closeBatchModal() { el.batchModal.classList.add("hidden"); }
  function updateBatchPreview() {
    var pat = el.batchPattern.value || "";
    var start = parseInt(el.batchStart.value, 10) || 0;
    el.batchPreview.textContent = "e.g. " + pat.replace(/#/g, String(start));
  }

  // ---- toolbar wiring -----------------------------------------------------
  var searchTimer;
  function pushSearch() {
    var filters = {
      type: el.fType.value,
      tag: el.fTag.value,
      locked: el.fLocked.checked ? "true" : "",
      hidden: el.fHidden.checked ? "true" : "",
      material: el.fNoMat.checked ? "none" : ""
    };
    send("search", { query: el.search.value, filters: filters });
    updateFilterBtn();
  }
  function updateFilterBtn() {
    var active = el.fType.value !== "any" || el.fTag.value !== "any" ||
      el.fLocked.checked || el.fHidden.checked || el.fNoMat.checked;
    el.filterBtn.classList.toggle("active", active);
  }

  el.search.addEventListener("input", function () {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(pushSearch, 180);
  });
  el.filterBtn.addEventListener("click", function () {
    state.filtersOpen = !state.filtersOpen;
    el.filters.classList.toggle("hidden", !state.filtersOpen);
    if (state.filtersOpen) send("get_tags", {});
  });
  [el.fType, el.fTag, el.fLocked, el.fHidden, el.fNoMat].forEach(function (n) {
    n.addEventListener("change", pushSearch);
  });

  el.scheme.addEventListener("change", function () {
    send("set_setting", { key: "color_scheme", value: el.scheme.value });
  });
  el.sort.addEventListener("change", function () {
    send("set_setting", { key: "sort", value: el.sort.value });
  });
  el.showall.addEventListener("change", function () {
    send("set_setting", { key: "show_all", value: el.showall.checked });
  });

  // rules modal events
  el.schemeEdit.addEventListener("click", openRulesModal);
  el.rulesClose.addEventListener("click", closeRulesModal);
  el.rulesAdd.addEventListener("click", function () {
    if (el.rulesList.querySelector(".rules-empty")) el.rulesList.innerHTML = "";
    el.rulesList.appendChild(ruleRow({}));
  });
  el.rulesSave.addEventListener("click", function () {
    var rules = collectRules();
    state.settings.rules = rules;
    send("set_rules", { rules: rules });
    el.scheme.value = "custom";
    send("set_setting", { key: "color_scheme", value: "custom" });
    closeRulesModal();
  });

  // batch modal events
  el.batchClose.addEventListener("click", closeBatchModal);
  el.batchPattern.addEventListener("input", updateBatchPreview);
  el.batchStart.addEventListener("input", updateBatchPreview);
  el.batchApply.addEventListener("click", function () {
    send("batch_rename", {
      ids: batchIds,
      pattern: el.batchPattern.value,
      start: parseInt(el.batchStart.value, 10) || 0
    });
    closeBatchModal();
  });

  // global handlers
  el.tree.addEventListener("scroll", function () { closeContextMenu(); scheduleSlice(); });
  window.addEventListener("resize", scheduleSlice);
  document.addEventListener("click", function (e) {
    if (!el.ctx.contains(e.target)) closeContextMenu();
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { closeContextMenu(); closeRulesModal(); closeBatchModal(); }
  });
  window.addEventListener("blur", closeContextMenu);
  // clicking a modal backdrop closes it
  [el.rulesModal, el.batchModal].forEach(function (m) {
    m.addEventListener("click", function (e) { if (e.target === m) m.classList.add("hidden"); });
  });

  // ---- helpers ------------------------------------------------------------
  function truthy(v) { return v === true || v === "true"; }
  function cssEsc(s) { return String(s).replace(/["\\]/g, "\\$&"); }

  // ---- boot ---------------------------------------------------------------
  send("ready", {});
})();
