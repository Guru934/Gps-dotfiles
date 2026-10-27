.pragma library
// Pixel sprite engine for the desktop pet.
// Sprites are built from rectangles on a W x H cell grid (feet touch y = H).
// Each rect is [x, y, w, h, colorKey]. An outline is drawn automatically by the renderer.
// Nothing here touches Qt: it is plain JS so it can be tested with node.

var W = 20;
var H = 18;

// ---- skins -----------------------------------------------------------------
// kind: "quad" (cat/fox/robot) or "blob" (slime/ghost)
var skins = {
  cat: {
    label: "Amber Cat", kind: "quad", ears: "cat", tail: "cat", stripes: true,
    c: { o: "#1a1208", b: "#ffd47b", d: "#d9a441", l: "#fff1cf", p: "#ff5d7a", e: "#261a00", w: "#ffffff", m: "#690005" }
  },
  shadow: {
    label: "Shadow Cat", kind: "quad", ears: "cat", tail: "cat", stripes: false,
    c: { o: "#07080d", b: "#4a4f66", d: "#2f3347", l: "#7b82a3", p: "#ddb8ff", e: "#57f1db", w: "#ffffff", m: "#2a0a3a" }
  },
  snow: {
    label: "Snow Cat", kind: "quad", ears: "cat", tail: "cat", stripes: false,
    c: { o: "#2a3140", b: "#f2f5fb", d: "#c9d2e4", l: "#ffffff", p: "#ff9db1", e: "#1b2a4a", w: "#ffffff", m: "#7a2a3a" }
  },
  fox: {
    label: "Fox", kind: "quad", ears: "fox", tail: "fox", stripes: false,
    c: { o: "#2a1204", b: "#f59e0b", d: "#c2670a", l: "#fff4e0", p: "#2a1204", e: "#1a0d00", w: "#ffffff", m: "#5a1a0a", k: "#2a1204" }
  },
  robot: {
    label: "Robot", kind: "quad", ears: "antenna", tail: "none", stripes: false,
    c: { o: "#0b0e16", b: "#8a94a6", d: "#5b6577", l: "#cfd6e3", p: "#ff5d7a", e: "#57f1db", w: "#ffffff", m: "#003731" }
  },
  slime: {
    label: "Slime", kind: "blob", wavy: false, float: false,
    c: { o: "#04302b", b: "#2dd4bf", d: "#1aa090", l: "#a8fff2", p: "#ff9db1", e: "#003731", w: "#ffffff", m: "#003731" }
  },
  ghost: {
    label: "Ghost", kind: "blob", wavy: true, float: true,
    c: { o: "#241338", b: "#ddb8ff", d: "#b48ad8", l: "#f6ebff", p: "#ff9db1", e: "#40215d", w: "#ffffff", m: "#40215d" }
  }
};

var order = ["cat", "shadow", "snow", "fox", "robot", "slime", "ghost"];

// Poses understood by every skin. The renderer maps them onto frames using `tick`.
var poses = ["sit", "stand", "walk", "run", "sleep", "air", "drag", "wave", "groove", "alert", "happy"];

function skin(id) { return skins[id] || skins.cat; }

// ---- helpers ---------------------------------------------------------------
function R(list, x, y, w, h, k) { list.push([x, y, w, h, k]); }

// blink schedule: eyes closed for 1 of every 28 ticks
function blinking(tick) { return (tick % 28) === 0; }

// ---- quadruped (cat / fox / robot) ------------------------------------------
function head(s, L, hx, hy, eyes, mouth, earsUp) {
  // head block 7 x 6
  R(L, hx, hy, 7, 6, "b");
  // ears
  var up = earsUp ? 1 : 0;
  if (s.ears === "cat") {
    R(L, hx, hy - 2 - up, 2, 2 + up, "b");
    R(L, hx + 5, hy - 2 - up, 2, 2 + up, "b");
    R(L, hx + 1, hy - 1, 1, 1, "p");
    R(L, hx + 5, hy - 1, 1, 1, "p");
  } else if (s.ears === "fox") {
    R(L, hx, hy - 3 - up, 2, 3 + up, "b");
    R(L, hx + 5, hy - 3 - up, 2, 3 + up, "b");
    R(L, hx, hy - 3 - up, 2, 1, "k");
    R(L, hx + 5, hy - 3 - up, 2, 1, "k");
    R(L, hx + 1, hy - 1, 1, 1, "l");
    R(L, hx + 5, hy - 1, 1, 1, "l");
  } else if (s.ears === "antenna") {
    R(L, hx + 3, hy - 3 - up, 1, 3 + up, "d");
    R(L, hx + 2, hy - 4 - up, 3, 2, "p");
  }
  // muzzle
  if (s.ears === "fox") R(L, hx + 2, hy + 3, 5, 3, "l"); else if (s.ears !== "antenna") R(L, hx + 3, hy + 4, 4, 2, "l");
  if (s.ears !== "antenna") R(L, hx + 6, hy + 4, 1, 1, "p");
  // eyes
  var ey = hy + 2;
  if (eyes === "open") {
    R(L, hx + 2, ey, 1, 2, "e"); R(L, hx + 5, ey, 1, 2, "e");
  } else if (eyes === "wide") {
    R(L, hx + 1, ey - 1, 2, 3, "w"); R(L, hx + 4, ey - 1, 2, 3, "w");
    R(L, hx + 2, ey, 1, 2, "e"); R(L, hx + 5, ey, 1, 2, "e");
  } else if (eyes === "happy") {
    R(L, hx + 1, ey + 1, 2, 1, "e"); R(L, hx + 4, ey + 1, 2, 1, "e");
    R(L, hx + 1, ey, 1, 1, "e"); R(L, hx + 5, ey, 1, 1, "e");
    R(L, hx, hy + 4, 1, 1, "p");
  } else { // closed / blink / sleepy
    R(L, hx + 1, ey + 1, 2, 1, "e"); R(L, hx + 4, ey + 1, 2, 1, "e");
  }
  if (s.ears === "antenna") {
    // robot face is a visor strip
    R(L, hx + 1, hy + 4, 5, 1, "d");
  }
  // mouth
  if (mouth === "open") R(L, hx + 4, hy + 5, 2, 1, "m");
  else if (mouth === "o") R(L, hx + 4, hy + 4, 2, 2, "m");
}

function tailQuad(s, L, base, sway, down) {
  // base = [x, y] where tail leaves the body
  var bx = base[0], by = base[1];
  if (s.tail === "none") return;
  if (s.tail === "fox") {
    if (down) { R(L, bx - 3, by + 1, 4, 3, "b"); R(L, bx - 4, by + 2, 2, 2, "l"); return; }
    R(L, bx - 2, by - 1, 3, 3, "b");
    R(L, bx - 4 + sway, by - 4, 4, 4, "b");
    R(L, bx - 4 + sway, by - 5, 3, 2, "l");
    return;
  }
  if (down) { R(L, bx - 3, by + 1, 4, 2, "b"); R(L, bx - 4, by + 2, 2, 2, "d"); return; }
  R(L, bx - 1, by - 1, 2, 2, "b");
  R(L, bx - 2 + sway, by - 5, 2, 5, "b");
  R(L, bx - 2 + sway, by - 6, 2, 2, "d");
}

function stripes(s, L, x, y, h) {
  if (!s.stripes) return;
  R(L, x, y, 1, h, "d");
  R(L, x + 3, y, 1, h, "d");
}

function legs(s, L, kind, p) {
  // 4 legs; positions along the body
  var xs = [4, 7, 10, 12];
  var lift = [false, false, false, false];
  var fwd = [0, 0, 0, 0];
  var bodyDy = 0;
  if (kind === "walk" || kind === "run") {
    var ph = p % 4;
    // diagonal pairs: (0,3) and (1,2)
    if (ph === 0) { lift[1] = lift[2] = true; fwd[0] = 1; fwd[3] = 1; }
    else if (ph === 1) { bodyDy = 1; }
    else if (ph === 2) { lift[0] = lift[3] = true; fwd[1] = 1; fwd[2] = 1; }
    else { bodyDy = 1; }
  }
  for (var i = 0; i < 4; i++) {
    var h = lift[i] ? 3 : 5 - bodyDy;
    var y = 13 + bodyDy;
    var col = s.ears === "antenna" ? "d" : "b";
    R(L, xs[i] + fwd[i], y, 2, h, col);
    R(L, xs[i] + fwd[i], y + h - 1, 2, 1, s.ears === "antenna" ? "l" : "l");
  }
  return bodyDy;
}

function quad(s, pose, tick) {
  var L = [];
  var eyes = blinking(tick) ? "closed" : "open";
  var mouth = "none";
  var sway = (tick % 8) < 4 ? 0 : 1;

  if (pose === "stand" || pose === "walk" || pose === "run" || pose === "alert") {
    var moving = pose === "walk" || pose === "run";
    var p = pose === "run" ? Math.floor(tick * 1.0) : Math.floor(tick / 1);
    if (pose === "walk") p = Math.floor(tick / 2) ;
    var bdy = (moving ? ((p % 2 === 1) ? 1 : 0) : 0);
    var alert = pose === "alert";
    if (alert) { eyes = "wide"; mouth = "o"; }
    if (pose === "run") mouth = "open";
    // body
    R(L, 4, 8 + bdy, 10, 5, "b");
    R(L, 5, 12 + bdy, 8, 1, "d");
    stripes(s, L, 6, 8 + bdy, 2);
    if (s.ears === "antenna") R(L, 6, 9 + bdy, 4, 2, "d");
    tailQuad(s, L, [3, 9 + bdy], alert ? 0 : (pose === "run" ? 1 : sway), false);
    legs(s, L, pose, p);
    head(s, L, 12, 4 + bdy, eyes, mouth, alert);
    return L;
  }

  if (pose === "sit" || pose === "wave" || pose === "groove" || pose === "happy") {
    var hdy = 0, pawUp = false;
    var br = (tick % 12) < 6 ? 0 : 1; // breathing
    if (pose === "groove") { hdy = (tick % 2); eyes = "happy"; mouth = (tick % 4 < 2) ? "open" : "none"; }
    if (pose === "happy") { eyes = "happy"; mouth = "open"; hdy = (tick % 4 < 2) ? 0 : -1; }
    if (pose === "wave") { pawUp = true; eyes = "open"; mouth = "open"; }
    // body (haunch + torso)
    R(L, 4, 8 + br, 8, 10 - br, "b");
    R(L, 3, 12 + br, 5, 6 - br, "d");
    R(L, 10, 9, 3, 9, "l");
    R(L, 3, 17, 6, 1, "l");
    R(L, 10, 17, 4, 1, "l");
    if (s.ears === "antenna") R(L, 5, 10, 4, 3, "d");
    // tail lying on the ground
    if (s.tail === "fox") { R(L, 0, 15, 4, 3, "b"); R(L, 0, 13 + sway, 3, 3, "b"); R(L, 0, 12 + sway, 2, 2, "l"); }
    else if (s.tail !== "none") { R(L, 0, 16, 4, 2, "b"); R(L, 0, 13 + sway, 2, 4 - sway, "b"); R(L, 0, 13 + sway, 2, 1, "d"); }
    head(s, L, 10, 2 + hdy + br, eyes, mouth, false);
    if (pawUp) {
      var wy = (tick % 4 < 2) ? 6 : 8;
      R(L, 15, wy, 2, 4, "b");
      R(L, 15, wy, 2, 1, "l");
    }
    return L;
  }

  if (pose === "sleep") {
    var sb = (tick % 12) < 6 ? 0 : 1;
    R(L, 2, 11 + sb, 14, 7 - sb, "b");
    R(L, 3, 16, 12, 2, "d");
    stripes(s, L, 5, 11 + sb, 2);
    if (s.tail === "fox") { R(L, 0, 13, 4, 5, "b"); R(L, 0, 13, 3, 2, "l"); }
    else if (s.tail !== "none") { R(L, 0, 14, 3, 4, "b"); R(L, 0, 14, 3, 1, "d"); }
    head(s, L, 12, 11 + sb, "closed", "none", false);
    return L;
  }

  // air (jumping/falling) and drag (dangling)
  if (pose === "air") {
    R(L, 4, 7, 10, 5, "b");
    R(L, 5, 11, 8, 1, "d");
    stripes(s, L, 6, 7, 2);
    tailQuad(s, L, [3, 8], 1, false);
    // legs spread
    R(L, 1, 11, 3, 2, "b"); R(L, 2, 13, 3, 2, "l");
    R(L, 14, 11, 3, 2, "b"); R(L, 13, 13, 3, 2, "l");
    head(s, L, 12, 3, "wide", "o", true);
    return L;
  }
  // drag: held by the scruff
  var fl = (tick % 4 < 2) ? 0 : 1;
  R(L, 5, 8, 8, 6, "b");
  R(L, 6, 13, 6, 1, "d");
  stripes(s, L, 7, 8, 3);
  tailQuad(s, L, [4, 11], 0, true);
  R(L, 5 - fl, 14, 2, 4, "b"); R(L, 5 - fl, 17, 2, 1, "l");
  R(L, 8 + fl, 14, 2, 4, "b"); R(L, 8 + fl, 17, 2, 1, "l");
  R(L, 11 - fl, 14, 2, 4, "b"); R(L, 11 - fl, 17, 2, 1, "l");
  head(s, L, 11, 3, "wide", "o", true);
  return L;
}

// ---- blob (slime / ghost) ----------------------------------------------------
function blobRows(L, top, rows, key) {
  // rows: array of [x0, x1] spans, one per row from `top`
  for (var i = 0; i < rows.length; i++) R(L, rows[i][0], top + i, rows[i][1] - rows[i][0] + 1, 1, key);
}

function blob(s, pose, tick) {
  var L = [];
  var eyes = blinking(tick) ? "closed" : "open";
  var mouth = "smile";
  var squash = 0;   // + = taller, - = flatter
  var hop = 0;      // lift off the ground
  var lean = 0;
  var arm = 0;
  if (pose === "sit" || pose === "stand") { squash = (tick % 12) < 6 ? 0 : -1; }
  else if (pose === "walk" || pose === "run") {
    var ph = (pose === "run" ? tick : Math.floor(tick / 2)) % 4;
    squash = [-1, 1, 2, 0][ph]; hop = [0, 2, 3, 1][ph]; lean = 1;
  }
  else if (pose === "sleep") { squash = -3; eyes = "closed"; mouth = "none"; }
  else if (pose === "air") { squash = 2; eyes = "wide"; mouth = "o"; hop = 0; }
  else if (pose === "drag") { squash = 3; eyes = "wide"; mouth = "o"; }
  else if (pose === "wave") { arm = 1 + (tick % 4 < 2 ? 1 : 0); mouth = "open"; }
  else if (pose === "groove") { squash = (tick % 2) ? 1 : -1; eyes = "happy"; mouth = "open"; }
  else if (pose === "alert") { squash = 2; eyes = "wide"; mouth = "o"; }
  else if (pose === "happy") { squash = (tick % 4 < 2) ? 1 : 0; eyes = "happy"; mouth = "open"; hop = (tick % 4 < 2) ? 1 : 0; }

  var floatY = 0;
  if (s.float) {
    floatY = [0, 1, 2, 1, 0, 0, 1, 0][tick % 8];
    if (pose === "sleep") floatY = 0;
    if (pose === "air" || pose === "drag") floatY = 0;
  }
  var bottom = H - hop - floatY; // y just under the body
  // body height & width from squash
  var bh = 11 + squash;
  var half = 8 + (squash < 0 ? -squash : 0); // wider when flat
  if (half > 9) half = 9;
  var cx = 10 + lean;
  var top = bottom - bh;
  // rounded rect body
  var rows = [];
  for (var i = 0; i < bh; i++) {
    var inset = 0;
    if (i === 0) inset = 3; else if (i === 1) inset = 2; else if (i === 2) inset = 1;
    if (!s.wavy && i === bh - 1) inset = 1;
    rows.push([cx - half + inset, cx + half - 1 - inset]);
  }
  blobRows(L, top, rows, "b");
  // shading along the bottom/right
  R(L, cx - half + 2, bottom - 2, half * 2 - 4, 1, "d");
  // highlight
  R(L, cx - half + 2, top + 2, 2, 2, "l");
  if (s.wavy) {
    // ragged ghost hem
    var hemY = bottom - 1;
    for (var k = 0; k < 4; k++) {
      var hx = cx - half + k * ((half * 2) / 4) ;
      var x0 = Math.round(hx);
      R(L, x0, hemY, 2, 1 + ((k + tick) % 2), "b");
    }
  }
  // face
  var ey = top + Math.floor(bh * 0.45);
  var ex1 = cx - 4, ex2 = cx + 2;
  if (eyes === "open") { R(L, ex1, ey, 2, 3, "e"); R(L, ex2, ey, 2, 3, "e"); R(L, ex1, ey, 1, 1, "w"); R(L, ex2, ey, 1, 1, "w"); }
  else if (eyes === "wide") { R(L, ex1 - 1, ey - 1, 4, 5, "w"); R(L, ex2 - 1, ey - 1, 4, 5, "w"); R(L, ex1, ey + 1, 2, 2, "e"); R(L, ex2, ey + 1, 2, 2, "e"); }
  else if (eyes === "happy") { R(L, ex1, ey + 1, 3, 1, "e"); R(L, ex2, ey + 1, 3, 1, "e"); R(L, ex1, ey, 1, 1, "e"); R(L, ex2 + 2, ey, 1, 1, "e"); }
  else { R(L, ex1, ey + 1, 3, 1, "e"); R(L, ex2, ey + 1, 3, 1, "e"); }
  var my = ey + 4;
  if (mouth === "smile") { R(L, cx - 1, my, 2, 1, "m"); }
  else if (mouth === "open") { R(L, cx - 1, my, 3, 2, "m"); }
  else if (mouth === "o") { R(L, cx - 1, my, 2, 2, "m"); }
  // cheeks
  if (eyes !== "wide" && pose !== "sleep") { R(L, ex1 - 1, my, 1, 1, "p"); R(L, ex2 + 3, my, 1, 1, "p"); }
  // arm for waving
  if (arm) { R(L, cx + half, top + 5 - arm, 3, 2, "b"); R(L, cx + half + 2, top + 4 - arm, 1, 2, "l"); }
  return L;
}

// ---- public ------------------------------------------------------------------
// Returns {w, h, rects} for a skin/pose/tick. Colors are looked up with colors(skinId).
function build(skinId, pose, tick) {
  var s = skin(skinId);
  var rects = s.kind === "blob" ? blob(s, pose, tick) : quad(s, pose, tick);
  return { w: W, h: H, rects: rects };
}

function colors(skinId) { return skin(skinId).c; }

// Draw into a 2D canvas context. `px` = pixels per cell. Adds a 1-cell margin for the outline.
function draw(ctx, skinId, pose, tick, px, flip, dim) {
  var fr = build(skinId, pose, tick);
  var c = colors(skinId);
  var cw = (W + 2) * px;
  var ch = (H + 2) * px;
  ctx.clearRect(0, 0, cw, ch);
  ctx.save();
  if (flip) { ctx.translate(cw, 0); ctx.scale(-1, 1); }
  var i, r;
  ctx.fillStyle = c.o;
  for (i = 0; i < fr.rects.length; i++) {
    r = fr.rects[i];
    ctx.fillRect(r[0] * px, r[1] * px, (r[2] + 2) * px, (r[3] + 2) * px);
  }
  for (i = 0; i < fr.rects.length; i++) {
    r = fr.rects[i];
    ctx.fillStyle = c[r[4]] || c.b;
    ctx.fillRect((r[0] + 1) * px, (r[1] + 1) * px, r[2] * px, r[3] * px);
  }
  ctx.restore();
}
