/* opx77_admin -- the name tag page. Lua sends what each anchor's tag reads on its own tick; the
   plugin sends where every anchor is on each rendered frame. Only the second one moves anything. */
(function () {
  "use strict";

  var root = document.getElementById("tags");
  var tags = new Map();
  var frame = new Map();
  var scheduled = 0;
  var settings = { distance: 25, fadeStart: 0.55, technical: true, staffLabel: "STAFF" };

  function text(value) { return value === null || value === undefined || value === false ? "" : String(value); }
  function list(value) { return Array.isArray(value) ? value : []; }
  function number(value, fallback) {
    var parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  function colour(value, fallback) {
    return /^#[0-9a-f]{6}$/i.test(text(value)) ? text(value) : fallback;
  }

  function make(tag, className) {
    var node = document.createElement(tag);
    node.className = className;
    return node;
  }

  function alphaFor(distance) {
    var start = settings.distance * settings.fadeStart;
    if (distance <= start || settings.distance <= start) return 1;
    return Math.max(0, 1 - (distance - start) / (settings.distance - start));
  }

  function place() {
    scheduled = 0;
    var width = window.innerWidth;
    var height = window.innerHeight;
    tags.forEach(function (tag, anchor) {
      var seen = frame.get(anchor);
      // The batch is every anchor the plugin projects: one missing is behind the camera or out
      // of range, not somewhere it last was.
      if (!seen || seen.onScreen === false) {
        tag.node.style.opacity = "0";
        return;
      }
      var x = Math.max(0, Math.min(1, number(seen.x, 0))) * width;
      var y = Math.max(0, Math.min(1, number(seen.y, 0))) * height;
      tag.node.style.transform = "translate3d(" + x.toFixed(1) + "px," + y.toFixed(1) + "px,0) translate(-50%,-100%)";
      tag.node.style.opacity = alphaFor(Math.max(0, number(seen.distance, 0))).toFixed(2);
    });
  }

  function schedule() {
    if (!scheduled) scheduled = requestAnimationFrame(place);
  }

  function build() {
    var node = make("div", "tag");
    var id = make("span", "tag-id");
    var copy = make("span", "tag-copy");
    var name = make("span", "tag-name");
    var badge = make("span", "tag-badge");
    copy.append(name, badge);
    node.append(id, copy);
    root.append(node);
    return { node: node, id: id, name: name, badge: badge, key: "" };
  }

  function fill(tag, row) {
    var shownId = settings.technical && row.id !== undefined && row.id !== null ? text(row.id) : "";
    var key = shownId + "\t" + text(row.name) + "\t" + (row.staff === true ? "1" : "0");
    if (tag.key === key) return;
    tag.key = key;
    tag.id.textContent = shownId;
    tag.id.hidden = shownId === "";
    tag.name.textContent = text(row.name);
    tag.badge.textContent = settings.staffLabel;
    tag.badge.hidden = row.staff !== true;
    tag.node.classList.toggle("staff", row.staff === true);
  }

  Open77.on("tags:config", function (payload) {
    if (!payload || typeof payload !== "object") return;
    settings.distance = Math.max(1, number(payload.distance, settings.distance));
    settings.fadeStart = Math.max(0, Math.min(1, number(payload.fadeStart, settings.fadeStart)));
    settings.technical = payload.technical !== false;
    settings.staffLabel = text(payload.staffLabel) || settings.staffLabel;
    var colors = payload.colors && typeof payload.colors === "object" ? payload.colors : {};
    var style = document.documentElement.style;
    style.setProperty("--tag-text", colour(colors.text, "#f2f6f8"));
    style.setProperty("--tag-accent", colour(colors.accent, "#fcee0a"));
    style.setProperty("--tag-staff", colour(colors.staff, "#22d8e2"));
    style.setProperty("--tag-ink", colour(colors.background, "#0a1220"));
    tags.forEach(function (tag) { tag.key = ""; });
  });

  Open77.on("tags:rows", function (payload) {
    var wanted = new Set();
    list(payload && payload.rows).forEach(function (row) {
      var anchor = text(row && row.anchor);
      if (!anchor) return;
      wanted.add(anchor);
      var tag = tags.get(anchor);
      if (!tag) {
        tag = build();
        tags.set(anchor, tag);
      }
      fill(tag, row);
    });
    tags.forEach(function (tag, anchor) {
      if (wanted.has(anchor)) return;
      tag.node.remove();
      tags.delete(anchor);
    });
    schedule();
  });

  Open77.on("open77:anchors", function (payload) {
    frame.clear();
    list(payload && payload.anchors).forEach(function (anchor) {
      var id = text(anchor && anchor.id);
      if (id) frame.set(id, anchor);
    });
    schedule();
  });

  Open77.ready();
  Open77.emit("tags:ready", {});
})();
