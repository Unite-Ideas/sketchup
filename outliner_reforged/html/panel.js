/* Outliner Reforged - panel logic
 * Talks to Ruby via sketchup.msg(JSON). Ruby pushes state back through the
 * global OR object below. */
(function () {
  "use strict";

  var state = {
    nodes: [],
    selected: {},        // pid -> true
    schemes: [],
    settings: {},
    filtersOpen: false
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
    search: document.getElementById("search"),
    filterBtn: document.getElementById("filter-btn"),
    filters: document.getElementById("filters"),
    fType: document.getElementById("f-type"),
    fTag: document.getElementById("f-tag"),
    fLocked: document.getElementById("f-locked"),
    fHidden: document.getElementById("f-hidden"),
    fNoMat: document.getElementById("f-nomat"),
    scheme: document.getElementById("scheme"),
    sort: document.getElementById("sort"),
    showall: document.getElementById("showall"),
    ctx: document.getElementById("ctxmenu")
  };

  // ---- inbound API (called by Ruby) --------------------------------------
  window.OR = {
    render: function (nodes) {
      state.nodes = nodes || [];
      renderTree();
    },
    setSelection: function (pids) {
      state.selected = {};
      (pids || []).forEach(function (p) { if (p) state.selected[p] = true; });
      paintSelection();
      scrollToFirstSelected();
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
    // color scheme dropdown
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

  // ---- rendering ----------------------------------------------------------
  function renderTree() {
    var frag = document.createDocumentFragment();
    state.nodes.forEach(function (n) { renderNode(n, 0, frag); });
    el.tree.innerHTML = "";
    el.tree.appendChild(frag);
    el.empty.classList.toggle("hidden", state.nodes.length > 0);
    paintSelection();
  }

  function renderNode(node, depth, parent) {
    var row = document.createElement("div");
    row.className = "row";
    row.dataset.id = node.id;
    row.dataset.type = node.type;
    row.style.paddingLeft = (6 + depth * 14) + "px";
    if (node.hidden) row.classList.add("dim");

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
      caret.textContent = "";
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

    // interactions
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

    parent.appendChild(row);
    if (node.children) node.children.forEach(function (c) { renderNode(c, depth + 1, parent); });
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
      case "group": return "\u25A2";       // dotted square
      case "component": return "\u25C8";   // diamond in square
      case "image": return "\u25A6";
      case "section": return "\u25F0";
      case "geometry": return "\u2500";
      case "text": case "dimension": return "\u2137";
      case "guide": return "\u00B7";
      default: return "\u2022";
    }
  }

  function paintSelection() {
    var rows = el.tree.querySelectorAll(".row");
    rows.forEach(function (r) {
      r.classList.toggle("selected", !!state.selected[r.dataset.id]);
    });
  }

  function scrollToFirstSelected() {
    var first = el.tree.querySelector(".row.selected");
    if (first && first.scrollIntoView) first.scrollIntoView({ block: "nearest" });
  }

  // ---- rename -------------------------------------------------------------
  function startRename(row, nameEl, node) {
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
    var items = [];

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
    if (isContainer) {
      items.push({ label: "Rename…", act: "__rename" });
    }
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
          var row = el.tree.querySelector('.row[data-id="' + cssEsc(node.id) + '"]');
          if (row) startRename(row, row.querySelector(".name"), node);
        } else {
          send("action", { name: it.act, id: node.id });
        }
      });
      ul.appendChild(li);
    });

    ul.classList.remove("hidden");
    // keep on screen
    var w = ul.offsetWidth, h = ul.offsetHeight;
    if (x + w > window.innerWidth) x = window.innerWidth - w - 4;
    if (y + h > window.innerHeight) y = window.innerHeight - h - 4;
    ul.style.left = x + "px";
    ul.style.top = y + "px";
  }

  function closeContextMenu() { el.ctx.classList.add("hidden"); }

  document.addEventListener("click", function (e) {
    if (!el.ctx.contains(e.target)) closeContextMenu();
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") closeContextMenu();
  });
  window.addEventListener("blur", closeContextMenu);
  el.tree.addEventListener("scroll", closeContextMenu);

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
  [el.fType, el.fTag].forEach(function (n) { n.addEventListener("change", pushSearch); });
  [el.fLocked, el.fHidden, el.fNoMat].forEach(function (n) { n.addEventListener("change", pushSearch); });

  el.scheme.addEventListener("change", function () {
    send("set_setting", { key: "color_scheme", value: el.scheme.value });
  });
  el.sort.addEventListener("change", function () {
    send("set_setting", { key: "sort", value: el.sort.value });
  });
  el.showall.addEventListener("change", function () {
    send("set_setting", { key: "show_all", value: el.showall.checked });
  });

  // ---- helpers ------------------------------------------------------------
  function truthy(v) { return v === true || v === "true"; }
  function cssEsc(s) { return String(s).replace(/["\\]/g, "\\$&"); }

  // ---- boot ---------------------------------------------------------------
  send("ready", {});
})();
