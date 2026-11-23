.pragma library
// Island-local mirror of pet/PetSprites.js. QuickShell blackholes imports outside
// the config root, so the island cannot load the desktop pet's copy directly.
// Keep the frame data in sync; island/tests/pet_fx_test.js checks parity.
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
  },
  dragon: {
    label: "Dragon",
    kind: "drake",
    c: {
      o: "#0a1c14", // outline
      b: "#10b981", // emerald base
      s: "#059669", // mid-tone scale shade (extended)
      d: "#047857", // deep emerald shadow
      l: "#fde68a", // warm cream belly / claws
      p: "#f59e0b", // gold horns / wing membrane
      a: "#ef4444", // flame outer / wing accent (extended)
      g: "#fef08a", // bright flame glow (extended)
      e: "#fbbf24", // amber eyes
      w: "#ffffff", // eye glint
      m: "#064e3b", // mouth
      k: "#78350f"  // horn base
    }
  },
  mecha: {
    label: "Sentinel",
    kind: "mecha",
    c: {
      o: "#090d16", // outline
      b: "#cbd5e1", // titanium chassis
      s: "#94a3b8", // steel mid-tone (extended)
      d: "#475569", // dark gunmetal joints
      l: "#f8fafc", // armor highlight
      p: "#38bdf8", // cyan LED primary
      a: "#f43f5e", // alert coral-red (extended)
      g: "#7dd3fc", // cyan glow / thruster core (extended)
      e: "#0f172a", // dark visor screen
      w: "#ffffff", // LED glint / thruster tip
      m: "#38bdf8", // visor LED mouth
      k: "#f59e0b"  // sleep charging amber
    }
  },
  kitsune: {
    label: "Kitsune",
    kind: "spirit",
    c: {
      o: "#1c1018", // outline
      b: "#fff7ed", // warm snow-white coat
      s: "#fed7aa", // peach-cream mid shade (extended)
      d: "#cbd5e1", // soft underside shadow
      l: "#ffffff", // pure white fur highlights
      p: "#ef4444", // vermilion tips & shrine markings
      a: "#f97316", // shrine orange accent (extended)
      g: "#22d3ee", // cyan foxfire glow (extended)
      e: "#b91c1c", // crimson eyes
      w: "#ffffff", // eye glint
      m: "#991b1b", // mouth
      k: "#0e7490"  // foxfire halo
    }
  },
  owl: {
    label: "Owl",
    kind: "avian",
    c: {
      o: "#0f172a", // outline
      b: "#475569", // slate-indigo plumage
      s: "#334155", // mid wing feather shade
      d: "#1e293b", // deep wingtip & ear-tuft shadow
      l: "#fef3c7", // warm cream chevron chest
      p: "#f59e0b", // golden beak & talons
      a: "#fb923c", // amber ear-tuft / berry accent
      g: "#fde047", // bright eye glow / lantern glint
      e: "#fbbf24", // large golden owl eyes
      w: "#ffffff", // eye reflection
      m: "#0f172a", // pupils & closed eyelids
      k: "#78350f"  // brow shade
    }
  },
  axolotl: {
    label: "Axolotl",
    kind: "amphibian",
    c: {
      o: "#3b0764", // deep plum outline
      b: "#fbcfe8", // pastel sakura body
      s: "#f9a8d4", // mid pink shading
      d: "#f472b6", // deeper underside & tail ridge
      l: "#fff1f2", // soft cream belly highlight
      p: "#ec4899", // vibrant external gill fronds
      a: "#db2777", // gill tips & blush
      g: "#67e8f9", // water-bubble cyan accent
      e: "#1e1b4b", // dark glossy eyes
      w: "#ffffff", // eye glint
      m: "#be185d", // wide smile
      k: "#9d174d"  // gill base
    }
  },
  redpanda: {
    label: "Red Panda",
    kind: "biped_quad",
    c: {
      o: "#1c0f08", // outline
      b: "#ea580c", // rust-orange coat
      s: "#c2410c", // mid cinnamon shade
      d: "#451a03", // espresso belly & legs
      l: "#fffbeb", // crisp white muzzle, eyebrows & ear rims
      p: "#fb923c", // light tail rings
      a: "#9a3412", // dark tail rings
      g: "#22c55e", // bamboo shoot green accent
      e: "#1c1917", // dark eyes
      w: "#ffffff", // eye glint
      m: "#291005", // nose & mouth
      k: "#7c2d12"  // cheek fur
    }
  },
  penguin: {
    label: "Tux",
    kind: "penguin",
    c: {
      o: "#090d16", // outline
      b: "#1e293b", // midnight navy back
      s: "#334155", // flipper sheen
      d: "#0f172a", // deep back shadow
      l: "#f8fafc", // snow-white belly
      p: "#f97316", // tangerine beak & webbed feet
      a: "#06b6d4", // neon cyan scarf dark
      g: "#22d3ee", // neon cyan scarf glow & fish highlight
      e: "#090d16", // eyes
      w: "#ffffff", // eye glint
      m: "#ea580c", // open beak accent
      k: "#38bdf8"  // scarf trim
    }
  }
};

var order = [
  "cat", "shadow", "snow", "fox", "robot", "slime", "ghost",
  "dragon", "mecha", "kitsune",
  "owl", "axolotl", "redpanda", "penguin"
];

// Poses understood by every skin. The renderer maps them onto frames using `tick`.
var poses = [
  "sit", "stand", "walk", "run", "sleep", "air", "drag",
  "wave", "groove", "alert", "happy",
  "spin", "feed", "stretch", "celebrate",
  "fetch", "peek", "focus", "curious", "sweat"
];

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

  if (pose === "spin") {
    var sp = tick % 4;
    var bw = (sp === 1 || sp === 3) ? 6 : 8;
    var bx = Math.floor((20 - bw) / 2);
    // Ears
    if (s.ears === "antenna") {
      R(L, 9, 2, 2, 2, "p"); R(L, 9, 4, 2, 1, "d");
    } else {
      R(L, bx, 3, 2, 2, "b"); R(L, bx + bw - 2, 3, 2, 2, "b");
      if (sp !== 3) { R(L, bx, 4, 1, 1, "p"); R(L, bx + bw - 1, 4, 1, 1, "p"); }
    }
    // Head & body
    R(L, bx, 5, bw, 5, "b");
    R(L, bx, 10, bw, 5, "b");
    R(L, bx + 1, 11, bw - 2, 3, sp === 3 ? "d" : "l");
    if (sp === 0 || sp === 2) {
      // Side profile eyes
      var ex = sp === 0 ? bx + bw - 3 : bx + 1;
      R(L, ex, 7, 2, 1, "e");
    } else if (sp === 1) {
      // Front view
      R(L, bx + 1, 7, 1, 1, "e"); R(L, bx + bw - 2, 7, 1, 1, "e");
      R(L, bx + 2, 8, 2, 1, "p");
    }
    // Tail flick
    if (s.tail !== "none") {
      var tx = sp === 0 ? bx - 2 : (sp === 2 ? bx + bw : bx + 2);
      R(L, tx, 11, 2, 3, s.tail === "fox" ? "l" : "d");
    }
    // Tucked paws
    R(L, bx + 1, 15, 2, 3, "l"); R(L, bx + bw - 3, 15, 2, 3, "l");
    return L;
  }

  if (pose === "feed") {
    var chew = tick % 4 < 2;
    // Seated body
    if (s.tail !== "none") R(L, 3, 12 + (chew ? 0 : 1), 3, 2, s.tail === "fox" ? "l" : "d");
    R(L, 5, 10, 8, 6, "b"); R(L, 7, 12, 5, 4, "l");
    // Head leaning slightly toward treat
    var hy = chew ? 6 : 7;
    if (s.ears === "antenna") {
      R(L, 12, hy - 3, 2, 2, "p"); R(L, 12, hy - 1, 2, 1, "d");
    } else {
      R(L, 9, hy - 2, 2, 2, "b"); R(L, 13, hy - 2, 2, 2, "b");
    }
    R(L, 9, hy, 7, 5, "b");
    R(L, 13, hy + 1, 2, 1, "e"); R(L, 13, hy + 1, 1, 1, "w");
    R(L, 14, hy + 3, 2, chew ? 2 : 1, "m");
    // Paws
    R(L, 6, 16, 3, 2, "l"); R(L, 11, 16, 3, 2, "l");
    // Pixel treat bowl & snack
    R(L, 16, 16, 4, 2, "d");
    R(L, 17, 15, 2, 1, chew ? "p" : "l");
    return L;
  }

  if (pose === "stretch") {
    var yawn = tick % 6 >= 2 && tick % 6 <= 4;
    // Raised tail & rump
    if (s.tail !== "none") R(L, 2, 6, 2, 5, s.tail === "fox" ? "l" : "b");
    R(L, 4, 9, 5, 5, "b");
    R(L, 8, 12, 5, 4, "b"); R(L, 9, 14, 4, 2, "l");
    // Low bowed head
    if (s.ears !== "antenna") { R(L, 12, 9, 2, 2, "b"); R(L, 15, 9, 2, 2, "b"); }
    else { R(L, 14, 8, 2, 2, "p"); }
    R(L, 11, 11, 6, 5, "b");
    R(L, 14, 12, 2, 1, "e");
    if (yawn) R(L, 15, 14, 2, 2, "m");
    // Hind legs tall, front paws extended low
    R(L, 5, 14, 2, 4, "l");
    R(L, 14, 16, 5, 2, "l");
    return L;
  }

  if (pose === "celebrate") {
    var hop = tick % 2 === 0 ? 2 : 0;
    if (s.tail !== "none") R(L, 3, 10 - hop, 3, 3, s.tail === "fox" ? "l" : "b");
    R(L, 6, 9 - hop, 8, 6, "b"); R(L, 8, 11 - hop, 4, 4, "l");
    if (s.ears === "antenna") { R(L, 9, 1 - hop, 2, 2, "p"); R(L, 9, 3 - hop, 2, 1, "d"); }
    else { R(L, 7, 3 - hop, 2, 2, "b"); R(L, 11, 3 - hop, 2, 2, "b"); }
    R(L, 6, 5 - hop, 8, 5, "b");
    // Joyful ^ ^ eyes & open smile
    R(L, 7, 7 - hop, 2, 1, "e"); R(L, 11, 7 - hop, 2, 1, "e");
    R(L, 9, 8 - hop, 2, 2, "m");
    // Raised celebratory front paws
    R(L, 4, 7 - hop, 2, 3, "l"); R(L, 14, 7 - hop, 2, 3, "l");
    R(L, 7, 15 - hop, 2, 3, "l"); R(L, 11, 15 - hop, 2, 3, "l");
    return L;
  }

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

  if (pose === "spin") {
    var sp = tick % 4;
    var w = (sp === 1 || sp === 3) ? 8 : 10;
    var x = Math.floor((20 - w) / 2);
    var bob = s.float ? (tick % 2) : 0;
    R(L, x + 1, 7 - bob, w - 2, 2, "b");
    R(L, x, 9 - bob, w, 7, "b");
    R(L, x + 1, 8 - bob, 2, 2, "l");
    if (sp !== 3) {
      var ex = sp === 0 ? x + w - 4 : (sp === 2 ? x + 2 : x + 2);
      R(L, ex, 11 - bob, 1, 2, "e");
      if (sp === 1) R(L, x + w - 3, 11 - bob, 1, 2, "e");
    }
    if (s.wavy) {
      R(L, x, 16 - bob, 2, 2, "b"); R(L, x + w - 2, 16 - bob, 2, 2, "b");
    } else {
      R(L, x + 1, 16, w - 2, 2, "d");
    }
    return L;
  }

  if (pose === "feed") {
    var ch = tick % 4 < 2;
    var top = ch ? 8 : 9;
    R(L, 5, top, 8, 2, "b");
    R(L, 4, top + 2, 10, 18 - (top + 2), "b");
    R(L, 5, top + 1, 2, 2, "l");
    R(L, 10, top + 3, 2, 2, "e"); R(L, 10, top + 3, 1, 1, "w");
    R(L, 11, top + 6, 2, ch ? 2 : 1, "m");
    // Snack orb
    R(L, 16, 15, 3, 3, ch ? "p" : "l");
    return L;
  }

  if (pose === "stretch") {
    R(L, 3, 11, 14, 2, "b");
    R(L, 2, 13, 16, 5, "b");
    R(L, 4, 12, 3, 2, "l");
    R(L, 11, 14, 2, 1, "e"); R(L, 14, 14, 2, 1, "e");
    R(L, 13, 16, 2, 1, "m");
    return L;
  }

  if (pose === "celebrate") {
    var h = tick % 2 === 0 ? 3 : 0;
    R(L, 6, 7 - h, 8, 2, "b");
    R(L, 5, 9 - h, 10, 7, "b");
    R(L, 6, 8 - h, 2, 2, "l");
    R(L, 7, 11 - h, 2, 1, "e"); R(L, 11, 11 - h, 2, 1, "e");
    R(L, 9, 13 - h, 2, 2, "m");
    R(L, 6, 16 - h, 8, 2, s.wavy ? "b" : "d");
    return L;
  }

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

// ---- drake (dragon) ---------------------------------------------------------
function drake(s, pose, tick) {
  var L = [];
  var t = tick || 0;
  var breath = (t % 12) >= 6 ? 1 : 0;
  var blink = (t % 28) === 27;
  var flameHi = (t % 4) < 2;

  // --- SPIN (4-phase 360 turnaround) ---
  if (pose === "spin") {
    var sp = t % 4;
    if (sp === 1) {
      // Front-facing spread wings
      R(L, 2, 6, 4, 5, "p"); R(L, 14, 6, 4, 5, "p");
      R(L, 3, 5, 3, 2, "d"); R(L, 14, 5, 3, 2, "d");
      R(L, 7, 2, 2, 2, "p"); R(L, 11, 2, 2, 2, "p");
      R(L, 6, 4, 8, 6, "b"); R(L, 7, 10, 6, 6, "b"); R(L, 8, 11, 4, 4, "l");
      R(L, 7, 6, 2, 2, "e"); R(L, 11, 6, 2, 2, "e");
      R(L, 7, 6, 1, 1, "w"); R(L, 11, 6, 1, 1, "w");
      R(L, 7, 16, 2, 2, "l"); R(L, 11, 16, 2, 2, "l");
    } else if (sp === 3) {
      // Back-facing spine & folded wings
      R(L, 3, 6, 4, 6, "d"); R(L, 13, 6, 4, 6, "d");
      R(L, 7, 2, 2, 2, "p"); R(L, 11, 2, 2, 2, "p");
      R(L, 6, 4, 8, 11, "s"); R(L, 9, 5, 2, 9, "p");
      R(L, 9, 14, 2, 3, "a"); R(L, 9, 15, 2, 1, "g");
      R(L, 7, 15, 2, 3, "d"); R(L, 11, 15, 2, 3, "d");
    } else {
      // Left / Right side pass
      var left = sp === 2;
      var hx = left ? 4 : 10;
      var tx = left ? 15 : 2;
      R(L, 7, 6, 6, 4, "p"); R(L, 7, 5, 5, 2, "d");
      R(L, 6, 10, 8, 5, "b"); R(L, 7, 13, 6, 2, "l");
      R(L, hx, 4, 6, 6, "b");
      R(L, left ? hx + 3 : hx + 1, 2, 2, 2, "p");
      R(L, left ? hx + 1 : hx + 3, 6, 2, 2, "e");
      R(L, tx, 11, 3, 3, "a"); R(L, tx + 1, 12, 1, 1, "g");
      R(L, 7, 15, 2, 3, "l"); R(L, 11, 15, 2, 3, "l");
    }
    return L;
  }

  // --- SLEEP (Curled around glowing tail flame) ---
  if (pose === "sleep") {
    R(L, 4, 11, 11, 7, "b");
    R(L, 5, 10, 9, 2, "s");
    R(L, 6, 11, 6, 4, "d"); // Folded wing blanket
    R(L, 7, 12, 4, 2, "p");
    R(L, 6, 15, 7, 3, "l");
    // Resting head
    R(L, 11, 11, 6, 5, "b");
    R(L, 11, 9, 2, 2, "p");
    R(L, 13, 13, 3, 1, "m"); // Closed eye line
    // Tail flame tucked by nose
    R(L, 16, 13 - (flameHi ? 1 : 0), 3, 3, "a");
    R(L, 17, 14 - (flameHi ? 1 : 0), 1, 2, "g");
    return L;
  }

  // --- STRETCH (Low bow + arched wings) ---
  if (pose === "stretch") {
    var yawn = (t % 6) >= 2 && (t % 6) <= 4;
    // High tail & flame
    R(L, 1, 5 - (flameHi ? 1 : 0), 2, 3, "a");
    R(L, 1, 6 - (flameHi ? 1 : 0), 1, 2, "g");
    R(L, 3, 8, 2, 4, "b");
    // Arched rump & lifted wing
    R(L, 4, 9, 6, 5, "b"); R(L, 5, 6, 5, 3, "p"); R(L, 5, 5, 4, 2, "d");
    R(L, 9, 12, 4, 4, "s"); R(L, 9, 14, 4, 2, "l");
    // Low bowed head
    R(L, 11, 10, 2, 2, "p");
    R(L, 12, 11, 6, 5, "b");
    R(L, 15, 12, 2, 1, "e");
    if (yawn) R(L, 16, 14, 2, 2, "a");
    R(L, 5, 14, 2, 4, "b"); R(L, 5, 17, 3, 1, "l");
    R(L, 14, 16, 5, 2, "b"); R(L, 18, 17, 1, 1, "l");
    return L;
  }

  // --- SHARED BODY GEOMETRY FOR REMAINING POSES ---
  var hop = (pose === "happy" || pose === "celebrate") ? ((t % 2) === 0 ? 2 : 0) : 0;
  var grooveDy = (pose === "groove") ? ((t % 4) < 2 ? 1 : 0) : 0;
  var dy = (pose === "sit" ? breath : 0) + grooveDy - hop;
  var flap = (pose === "air" || pose === "celebrate" || pose === "alert")
    ? ((t % 4) < 2 ? 3 : 0)
    : (pose === "happy" || pose === "groove" ? ((t % 4) < 2 ? 2 : 0) : 0);

  // Tail + animated flame (x=1..6)
  var tailY = 12 + (pose === "run" ? -1 : 0) - hop;
  R(L, 3, tailY + 1, 4, 2, "d");
  R(L, 2, tailY, 2, 2, "b");
  R(L, 1, Math.max(0, tailY - 2 - (flameHi ? 1 : 0)), 2, 3, "a");
  R(L, 1, Math.max(0, tailY - 1 - (flameHi ? 1 : 0)), 1, 2, "g");

  // Articulated Bat Wing (x=4..10)
  var wy = Math.max(0, 6 - flap + Math.min(0, dy));
  R(L, 4, wy + 1, 6, 4, "p");
  R(L, 5, wy + 2, 4, 2, "a");
  R(L, 4, wy, 5, 2, "d");

  // Torso, dorsal spine & segmented belly (x=5..14)
  var bodyY = Math.max(2, 10 + dy);
  R(L, 5, bodyY, 9, 5, "b");
  R(L, 6, bodyY, 6, 2, "s");
  R(L, 7, bodyY - 1, 1, 1, "p"); R(L, 9, bodyY - 1, 1, 1, "p");
  R(L, 7, bodyY + 3, 6, 2, "l");

  // Head & swept golden horns (x=10..18)
  var hy = Math.max(2, 5 + dy + (pose === "feed" && (t % 4) >= 2 ? 1 : 0));
  var hx = (pose === "run") ? 12 : 11;
  R(L, hx - 1, Math.max(0, hy - 3), 2, 2, "p");
  R(L, hx, Math.max(0, hy - 1), 1, 1, "k");
  R(L, hx + 2, Math.max(0, hy - 3), 2, 2, "p");
  R(L, hx, hy, 7, 5, "b");
  R(L, hx + 1, hy, 5, 1, "s");
  R(L, hx + 5, hy + 1, 2, 3, "b"); // Snout

  // Eyes & Expressions
  if (pose === "happy" || pose === "celebrate" || pose === "groove") {
    R(L, hx + 3, hy + 1, 2, 1, "e");
    R(L, hx + 4, hy + 3, 2, 2, "a");
  } else if (pose === "air" || pose === "drag" || pose === "alert") {
    R(L, hx + 3, hy + 1, 2, 2, "w");
    R(L, hx + 4, hy + 1, 1, 2, "e");
    R(L, hx + 5, hy + 3, 2, 2, "a");
    if (pose === "alert" && flameHi) {
      R(L, Math.min(18, hx + 7), hy + 2, 2, 2, "g");
    }
  } else if (pose === "feed") {
    R(L, hx + 3, hy + 1, 2, 2, "e"); R(L, hx + 3, hy + 1, 1, 1, "w");
    R(L, hx + 5, hy + 3, 2, (t % 4) < 2 ? 2 : 1, "m");
    // Ember-berry snack
    R(L, 17, 15, 3, 3, "a"); R(L, 18, 15, 1, 1, "g");
  } else {
    if (blink) {
      R(L, hx + 3, hy + 2, 2, 1, "m");
    } else {
      R(L, hx + 3, hy + 1, 2, 2, "e");
      R(L, hx + 3, hy + 1, 1, 1, "w");
    }
    R(L, hx + 5, hy + 3, 2, 1, "m");
  }

  // Legs / Claws / Wave
  if (pose === "walk" || pose === "run") {
    var ph = t % 4;
    var a1 = (ph === 0 || ph === 2) ? 0 : (ph === 1 ? -1 : 1);
    R(L, 6 + a1, 15, 2, 3, "b"); R(L, 7 + a1, 17, 1, 1, "l");
    R(L, 12 - a1, 15, 2, 3, "b"); R(L, 13 - a1, 17, 1, 1, "l");
  } else if (pose === "air" || pose === "drag") {
    R(L, 5, 15, 2, 3, "d"); R(L, 13, 15, 2, 3, "d");
  } else if (pose === "wave") {
    R(L, 6, 15, 3, 3, "b"); R(L, 8, 17, 1, 1, "l");
    var wv = (t % 4) < 2 ? 10 : 12;
    R(L, 15, wv, 3, 2, "b"); R(L, 17, wv, 1, 1, "l");
  } else {
    var ly = 15 - hop;
    R(L, 6, ly, 3, 3, "b"); R(L, 8, ly + 2, 1, 1, "l");
    R(L, 11, ly, 3, 3, "b"); R(L, 13, ly + 2, 1, 1, "l");
  }

  return L;
}

// ---- mecha (Sentinel Unit) --------------------------------------------------
function mecha(s, pose, tick) {
  var L = [];
  var t = tick || 0;
  var blink = (t % 28) === 27;
  var pulse = (t % 4) < 2;

  // --- SPIN (360 hovering thruster twirl) ---
  if (pose === "spin") {
    var sp = t % 4;
    R(L, 9, 1, 2, 2, pulse ? "g" : "p");
    R(L, 6, 3, 8, 7, "b"); R(L, 7, 3, 6, 1, "l");
    if (sp === 0) { R(L, 9, 5, 5, 3, "e"); R(L, 11, 6, 2, 1, "g"); }
    else if (sp === 1) { R(L, 7, 5, 6, 3, "e"); R(L, 8, 6, 1, 1, "p"); R(L, 11, 6, 1, 1, "p"); }
    else if (sp === 2) { R(L, 6, 5, 5, 3, "e"); R(L, 7, 6, 2, 1, "g"); }
    else { R(L, 7, 5, 6, 4, "s"); R(L, 8, 11, 4, 3, "d"); } // Back thruster pack
    R(L, 6, 10, 8, 4, "s");
    R(L, 7, 14, 2, 2, "d"); R(L, 11, 14, 2, 2, "d");
    R(L, 7, 16, 2, 2, "p"); R(L, 11, 16, 2, 2, "g");
    return L;
  }

  var hover = (pose === "air" || pose === "celebrate" || pose === "run") ? 1 : 0;
  var hop = (pose === "happy" || pose === "celebrate") ? ((t % 2) === 0 ? 1 : 0) : 0;
  var dy = (pose === "groove" ? ((t % 4) < 2 ? 1 : 0) : 0) - hover - hop;
  var hy = Math.max(2, 3 + dy);

  // Antenna beacon
  var antCol = pose === "alert" ? (pulse ? "a" : "w") : (pose === "sleep" ? "k" : (pulse ? "g" : "p"));
  R(L, 9, Math.max(0, hy - 2), 2, 1, antCol);
  R(L, 9, Math.max(1, hy - 1), 2, 1, "d");

  // Helmet & Armored Ear Pods (x=5..15)
  R(L, 5, hy, 10, 7, "b");
  R(L, 6, hy, 8, 1, "l");
  R(L, 4, hy + 2, 1, 3, "s");
  R(L, 15, hy + 2, 1, 3, "s");

  // Wide Dark Visor Glass (x=6..14, y=hy+2..hy+5)
  R(L, 6, hy + 2, 8, 4, "e");

  // Dynamic LED Visor Expressions
  if (pose === "sleep") {
    // Charging battery bars
    var bars = 1 + (Math.floor(t / 3) % 3);
    R(L, 7, hy + 3, 6, 2, "d");
    R(L, 7, hy + 3, bars * 2, 2, "k");
  } else if (pose === "alert") {
    R(L, 8, hy + 2, 1, 2, "a"); R(L, 8, hy + 5, 1, 1, "w");
    R(L, 11, hy + 2, 1, 2, "a"); R(L, 11, hy + 5, 1, 1, "w");
  } else if (pose === "drag") {
    // > < startled eyes
    R(L, 7, hy + 3, 2, 1, "a"); R(L, 11, hy + 3, 2, 1, "a");
    R(L, 8, hy + 4, 1, 1, "w"); R(L, 11, hy + 4, 1, 1, "w");
  } else if (pose === "happy" || pose === "celebrate") {
    // ^ ^ cheerful LED chevrons
    R(L, 7, hy + 3, 2, 1, "g"); R(L, 7, hy + 4, 1, 1, "p");
    R(L, 11, hy + 3, 2, 1, "g"); R(L, 12, hy + 4, 1, 1, "p");
  } else if (pose === "groove") {
    // Live 4-bar audio equalizer
    var eq = [(t % 3) + 1, ((t + 1) % 3) + 1, ((t + 2) % 3) + 1, (t % 2) + 1];
    R(L, 7, hy + 6 - eq[0], 1, eq[0], "p");
    R(L, 9, hy + 6 - eq[1], 1, eq[1], "g");
    R(L, 11, hy + 6 - eq[2], 1, eq[2], "a");
    R(L, 13, hy + 6 - eq[3], 1, eq[3], "p");
  } else if (pose === "stretch") {
    // Diagnostic sweep bar
    var sw = 7 + (t % 5);
    R(L, sw, hy + 3, 2, 2, "g");
  } else if (pose === "feed") {
    // Power fill eyes
    R(L, 7, hy + 3, 2, 2, "g"); R(L, 11, hy + 3, 2, 2, "g");
    R(L, 9, hy + 5, 2, 1, pulse ? "w" : "p");
  } else {
    // Default cyan eyes + subtle blink
    if (blink) {
      R(L, 7, hy + 4, 2, 1, "p"); R(L, 11, hy + 4, 2, 1, "p");
    } else {
      var shift = pose === "run" ? 1 : 0;
      R(L, 7 + shift, hy + 3, 2, 2, "p"); R(L, 7 + shift, hy + 3, 1, 1, "w");
      R(L, 11 + shift, hy + 3, 2, 2, "p"); R(L, 11 + shift, hy + 3, 1, 1, "w");
    }
  }

  // Torso, Pauldrons & Chest Core (y = hy+7..hy+11)
  var ty = Math.min(11, hy + 7);
  R(L, 6, ty, 8, 5, "s");
  R(L, 7, ty, 6, 4, "b");
  R(L, 9, ty + 1, 2, 2, pose === "alert" ? "a" : (pulse ? "g" : "p"));

  // Articulated Arms
  if (pose === "stretch" || pose === "celebrate") {
    // Both arms raised high
    R(L, 3, Math.max(1, ty - 5), 2, 5, "b"); R(L, 3, Math.max(1, ty - 5), 2, 1, "l");
    R(L, 15, Math.max(1, ty - 5), 2, 5, "b"); R(L, 15, Math.max(1, ty - 5), 2, 1, "l");
  } else if (pose === "wave") {
    R(L, 4, ty, 2, 4, "s");
    R(L, 15, Math.max(2, ty - 3 + (pulse ? 0 : 1)), 2, 4, "b");
  } else if (pose === "feed") {
    R(L, 4, ty, 2, 4, "s");
    R(L, 14, ty + 1, 3, 2, "b");
    // Glowing energy cell
    R(L, 16, 12, 3, 6, "d");
    R(L, 17, 13, 1, pulse ? 4 : 3, "g");
  } else {
    var armSw = (pose === "walk" || pose === "run") ? ((t % 2) === 0 ? 1 : 0) : 0;
    R(L, 4, ty + armSw, 2, 4, "s"); R(L, 4, ty + armSw, 2, 1, "l");
    R(L, 14, ty + (1 - armSw), 2, 4, "s"); R(L, 14, ty + (1 - armSw), 2, 1, "l");
  }

  // Bipedal Boots & Foot Thrusters
  var footY = ty + 5;
  if (pose === "air" || pose === "celebrate" || pose === "run") {
    R(L, 6, Math.min(14, footY), 3, 2, "d");
    R(L, 11, Math.min(14, footY), 3, 2, "d");
    // Thruster flames
    var flH = pulse ? 2 : 1;
    R(L, 7, Math.min(16, footY + 2), 2, flH, "p");
    R(L, 11, Math.min(16, footY + 2), 2, flH, "g");
  } else if (pose === "walk") {
    var st = (t % 4) < 2 ? 1 : 0;
    R(L, 6, 15 - st, 3, 3, "d"); R(L, 11, 15 - (1 - st), 3, 3, "d");
  } else {
    R(L, 6, 15, 3, 3, "d"); R(L, 6, 15, 3, 1, "s");
    R(L, 11, 15, 3, 3, "d"); R(L, 11, 15, 3, 1, "s");
  }

  return L;
}

// ---- spirit (Kitsune) -------------------------------------------------------
function spirit(s, pose, tick) {
  var L = [];
  var t = tick || 0;
  var blink = (t % 28) === 27;
  var fastOrb = (pose === "groove" || pose === "celebrate" || pose === "alert");
  var orbPhase = (fastOrb ? t * 2 : t) % 8;
  var orbX = [2, 3, 4, 3, 2, 1, 1, 2][orbPhase];
  var orbY = [2, 1, 2, 3, 4, 3, 2, 1][orbPhase];
  var orbCol = (pose === "alert") ? "a" : "g";

  // Independent Orbiting Foxfire Orb
  R(L, orbX, orbY, 2, 2, "k");
  R(L, orbX, orbY, 1, 1, orbCol);
  if ((t % 2) === 0) R(L, orbX + 1, orbY, 1, 1, "w");

  // --- SPIN (Whirling 3-tail spirit twirl) ---
  if (pose === "spin") {
    var sp = t % 4;
    // Symmetrical fanned tails
    R(L, 2, 9, 4, 5, "b"); R(L, 2, 8, 2, 2, "p");
    R(L, 14, 9, 4, 5, "b"); R(L, 16, 8, 2, 2, "p");
    R(L, 7, 2, 2, 3, "b"); R(L, 7, 2, 2, 1, "p");
    R(L, 11, 2, 2, 3, "b"); R(L, 11, 2, 2, 1, "p");
    R(L, 6, 5, 8, 5, "b"); R(L, 9, 6, 2, 1, "p");
    if (sp !== 3) {
      R(L, 7, 7, 2, 1, "e"); R(L, 11, 7, 2, 1, "e");
    }
    R(L, 7, 10, 6, 1, "p"); // Shrine collar
    R(L, 6, 11, 8, 5, "b"); R(L, 8, 11, 4, 4, "l");
    R(L, 7, 16, 2, 2, "s"); R(L, 11, 16, 2, 2, "s");
    return L;
  }

  // --- SLEEP (Curled inside 3 vermilion-tipped tails) ---
  if (pose === "sleep") {
    R(L, 3, 11, 14, 7, "b");
    R(L, 3, 10, 4, 3, "l"); R(L, 3, 10, 2, 2, "p");
    R(L, 6, 9, 4, 3, "s"); R(L, 6, 9, 2, 1, "p");
    R(L, 5, 14, 9, 4, "l");
    R(L, 11, 11, 6, 5, "b");
    R(L, 11, 9, 2, 2, "p"); R(L, 14, 9, 2, 2, "p");
    R(L, 13, 13, 3, 1, "m");
    R(L, 11, 15, 5, 1, "p");
    return L;
  }

  // --- STRETCH (Fox-bow with fanned tails high) ---
  if (pose === "stretch") {
    // 3 Fanned Tails High
    R(L, 1, 5, 3, 4, "b"); R(L, 1, 5, 2, 2, "p");
    R(L, 4, 4, 3, 5, "l"); R(L, 4, 4, 2, 2, "p");
    R(L, 3, 9, 4, 4, "s");
    // Arched body
    R(L, 5, 10, 5, 4, "b"); R(L, 9, 12, 4, 4, "b");
    R(L, 11, 11, 2, 2, "p"); R(L, 14, 11, 2, 2, "p");
    R(L, 12, 12, 6, 4, "b"); R(L, 15, 13, 2, 1, "e");
    R(L, 6, 14, 2, 4, "b"); R(L, 6, 17, 2, 1, "p");
    R(L, 14, 16, 5, 2, "l");
    return L;
  }

  // --- SHARED KITSUNE GEOMETRY ---
  var hop = (pose === "happy" || pose === "celebrate") ? ((t % 2) === 0 ? 2 : 0) : 0;
  var dy = (pose === "groove" ? ((t % 4) < 2 ? 1 : 0) : 0) - hop;
  var sway = (t % 4) < 2 ? 0 : 1;

  // 3 Layered Fanned Tails (x=1..7)
  R(L, 1, Math.max(3, 9 - sway - hop), 4, 4, "b"); R(L, 1, Math.max(3, 9 - sway - hop), 2, 2, "p");
  R(L, 3, Math.max(2, 6 + sway - hop), 4, 5, "l"); R(L, 3, Math.max(2, 6 + sway - hop), 2, 2, "p");
  R(L, 2, Math.max(4, 12 - hop), 5, 3, "s"); R(L, 2, Math.max(4, 12 - hop), 2, 1, "p");

  // Body & Shrine Collar (x=6..15)
  var by = Math.max(3, 10 + dy);
  R(L, 6, by, 8, 5, "b");
  R(L, 7, by + 3, 6, 2, "d");
  R(L, 10, by, 4, 4, "l"); // Fluffy chest ruff
  R(L, 10, by, 4, 1, "p"); // Vermilion shrine collar
  R(L, 12, by + 1, 1, 1, "a");

  // Head & Tall Vermilion-Tipped Ears (x=10..18)
  var hy = Math.max(2, 5 + dy + (pose === "feed" && (t % 4) >= 2 ? 1 : 0));
  R(L, 10, Math.max(0, hy - 3), 2, 3, "b"); R(L, 10, Math.max(0, hy - 3), 2, 1, "p");
  R(L, 14, Math.max(0, hy - 3), 2, 3, "b"); R(L, 14, Math.max(0, hy - 3), 2, 1, "p");
  R(L, 10, hy, 7, 5, "b");
  R(L, 16, hy + 2, 2, 2, "l"); // Snout
  R(L, 13, hy, 1, 1, "p");     // Forehead shrine diamond
  R(L, 11, hy + 3, 1, 1, "p"); // Cheek marking

  // Eyes & Expressions
  if (pose === "happy" || pose === "celebrate" || pose === "groove") {
    R(L, 13, hy + 1, 2, 1, "e"); R(L, 15, hy + 3, 2, 1, "m");
  } else if (pose === "air" || pose === "drag" || pose === "alert") {
    R(L, 13, hy + 1, 2, 2, "w"); R(L, 14, hy + 1, 1, 2, "e");
    R(L, 16, hy + 3, 2, 2, "m");
  } else if (pose === "feed") {
    R(L, 13, hy + 1, 2, 2, "e"); R(L, 13, hy + 1, 1, 1, "w");
    R(L, 16, hy + 3, 2, (t % 4) < 2 ? 2 : 1, "m");
    // Shrine mochi / berry offering
    R(L, 17, 15, 3, 3, "l"); R(L, 18, 15, 1, 1, "p");
  } else {
    if (blink) { R(L, 13, hy + 2, 2, 1, "m"); }
    else { R(L, 13, hy + 1, 2, 2, "e"); R(L, 13, hy + 1, 1, 1, "w"); }
    R(L, 16, hy + 3, 2, 1, "m");
  }

  // Paws
  if (pose === "walk" || pose === "run") {
    var p = t % 4;
    var step = (p === 0 || p === 2) ? 0 : (p === 1 ? -1 : 1);
    R(L, 7 + step, 15, 2, 3, "b"); R(L, 7 + step, 17, 2, 1, "p");
    R(L, 12 - step, 15, 2, 3, "b"); R(L, 12 - step, 17, 2, 1, "p");
  } else if (pose === "wave") {
    R(L, 7, 15, 2, 3, "b"); R(L, 7, 17, 2, 1, "p");
    R(L, 15, (t % 4) < 2 ? 10 : 12, 3, 2, "l");
  } else {
    var py = 15 - hop;
    R(L, 7, py, 2, 3, "b"); R(L, 7, py + 2, 2, 1, "p");
    R(L, 12, py, 2, 3, "b"); R(L, 12, py + 2, 2, 1, "p");
  }

  return L;
}

// ---- helpers for extended palette & species poses --------------------------
function K(s, pref, fallback) {
  return (s.c && s.c[pref]) ? pref : fallback;
}

function peekPose(s, tick) {
  var L = [];
  var t = tick || 0;
  var look = (t % 12) < 6 ? 0 : 1;
  var blink = (t % 24) === 23;

  // Species-specific top silhouette (ears / horns / tufts / gills / antenna)
  if (s.kind === "drake") {
    R(L, 5, 9, 2, 3, "p"); R(L, 13, 9, 2, 3, "p");
    R(L, 6, 12, 8, 6, "b"); R(L, 7, 12, 6, 1, "s");
  } else if (s.kind === "mecha") {
    R(L, 9, 9, 2, 2, (t % 4) < 2 ? "g" : "p"); R(L, 9, 11, 2, 1, "d");
    R(L, 5, 12, 10, 6, "b"); R(L, 6, 14, 8, 4, "e");
    if (!blink) {
      R(L, 7 + look, 15, 2, 2, "p"); R(L, 11 + look, 15, 2, 2, "p");
    } else {
      R(L, 7, 16, 2, 1, "p"); R(L, 11, 16, 2, 1, "p");
    }
    R(L, 4, 16, 2, 2, "s"); R(L, 14, 16, 2, 2, "s");
    return L;
  } else if (s.kind === "spirit") {
    R(L, 5, 9, 2, 3, "b"); R(L, 5, 9, 2, 1, "p");
    R(L, 13, 9, 2, 3, "b"); R(L, 13, 9, 2, 1, "p");
    R(L, 5, 12, 10, 6, "b"); R(L, 9, 12, 2, 1, "p");
  } else if (s.kind === "avian") {
    R(L, 5, 10, 2, 2, "d"); R(L, 13, 10, 2, 2, "d");
    R(L, 5, 12, 10, 6, "b"); R(L, 9, 16, 2, 2, "p");
  } else if (s.kind === "amphibian") {
    var gw = (t % 4) < 2 ? 0 : 1;
    R(L, 2, 12 + gw, 3, 1, "p"); R(L, 2, 14, 3, 1, "a"); R(L, 3, 16 - gw, 2, 1, "p");
    R(L, 15, 12 + gw, 3, 1, "p"); R(L, 15, 14, 3, 1, "a"); R(L, 15, 16 - gw, 2, 1, "p");
    R(L, 5, 12, 10, 6, "b"); R(L, 6, 12, 8, 1, "l");
  } else if (s.kind === "biped_quad") {
    R(L, 5, 10, 3, 2, "b"); R(L, 6, 10, 1, 1, "l");
    R(L, 12, 10, 3, 2, "b"); R(L, 13, 10, 1, 1, "l");
    R(L, 5, 12, 10, 6, "b");
    R(L, 7, 13, 2, 1, "l"); R(L, 11, 13, 2, 1, "l");
  } else if (s.kind === "penguin") {
    R(L, 5, 12, 10, 6, "b"); R(L, 6, 14, 8, 4, "l");
    R(L, 9, 16, 2, 2, "p");
  } else if (s.kind === "blob") {
    R(L, 5, 12, 10, 6, "b"); R(L, 6, 13, 2, 2, "l");
  } else {
    // Original quad skins
    if (s.ears === "antenna") { R(L, 9, 9, 2, 2, "p"); R(L, 9, 11, 2, 1, "d"); }
    else { R(L, 5, 10, 2, 2, "b"); R(L, 13, 10, 2, 2, "b"); }
    R(L, 5, 12, 10, 6, "b");
  }

  // Peering eyes & gripping ledge paws
  if (blink) {
    R(L, 7, 15, 2, 1, "m"); R(L, 11, 15, 2, 1, "m");
  } else {
    R(L, 7 + look, 14, 2, 2, "e"); R(L, 7 + look, 14, 1, 1, "w");
    R(L, 11 + look, 14, 2, 2, "e"); R(L, 11 + look, 14, 1, 1, "w");
  }
  if (s.kind !== "blob") {
    var paw = (s.kind === "biped_quad") ? "d" : "l";
    R(L, 4, 16, 2, 2, paw); R(L, 14, 16, 2, 2, paw);
  }
  return L;
}

function avian(s, pose, tick) {
  var L = [];
  var t = tick || 0;
  var blink = (t % 28) === 27;
  var tilt = (pose === "sit" && (t % 16) >= 10) || pose === "curious" ? 1 : 0;

  if (pose === "spin") {
    var sp = t % 4;
    R(L, 6, 3, 2, 2, "d"); R(L, 12, 3, 2, 2, "d");
    R(L, 5, 5, 10, 11, sp === 3 ? "s" : "b");
    if (sp !== 3) {
      R(L, 7, 10, 6, 5, "l");
      var ex = sp === 0 ? 10 : (sp === 2 ? 6 : 7);
      R(L, ex, 6, 2, 2, "e"); R(L, ex, 6, 1, 1, "m");
      if (sp === 1) { R(L, 11, 6, 2, 2, "e"); R(L, 12, 6, 1, 1, "m"); R(L, 9, 8, 2, 2, "p"); }
    } else {
      R(L, 6, 8, 8, 6, "d");
    }
    R(L, 7, 16, 2, 2, "p"); R(L, 11, 16, 2, 2, "p");
    return L;
  }

  if (pose === "sleep") {
    // Puffed feathered ball perched on one talon
    R(L, 5, 6, 2, 2, "d"); R(L, 13, 6, 2, 2, "d");
    R(L, 4, 8, 12, 8, "b");
    R(L, 5, 8, 10, 2, "s");
    R(L, 6, 11, 8, 5, "l"); R(L, 7, 12, 2, 1, "s"); R(L, 11, 12, 2, 1, "s");
    R(L, 6, 10, 3, 1, "m"); R(L, 11, 10, 3, 1, "m");
    R(L, 9, 11, 2, 1, "p");
    R(L, 9, 16, 2, 2, "p");
    return L;
  }

  if (pose === "stretch") {
    // One wing fanned wide + angled tail
    R(L, 1, 7, 5, 5, "s"); R(L, 1, 8, 4, 3, "d");
    R(L, 6, 4, 2, 2, "d"); R(L, 12, 4, 2, 2, "d");
    R(L, 5, 6, 10, 10, "b"); R(L, 7, 10, 6, 5, "l");
    R(L, 7, 7, 2, 2, "e"); R(L, 11, 7, 2, 2, "e");
    R(L, 9, 9, 2, 2, "p");
    R(L, 14, 12, 4, 3, "d");
    R(L, 7, 16, 2, 2, "p"); R(L, 12, 16, 2, 2, "p");
    return L;
  }

  var hop = (pose === "happy" || pose === "celebrate") ? ((t % 2) === 0 ? 2 : 0) : 0;
  var bop = (pose === "groove") ? ((t % 4) < 2 ? 1 : -1) : 0;
  var spread = (pose === "air" || pose === "celebrate" || pose === "drag" || pose === "run");
  var flapUp = (t % 4) < 2;
  var topY = Math.max(2, 4 - hop + (pose === "groove" && flapUp ? 1 : 0));

  // Layered Wings
  if (spread) {
    var wy = Math.max(2, topY + (flapUp ? 0 : 4));
    R(L, 1, wy, 4, 4, "s"); R(L, 1, wy + 2, 3, 2, "d");
    R(L, 15, wy, 4, 4, "s"); R(L, 16, wy + 2, 3, 2, "d");
  } else if (pose === "wave") {
    R(L, 4, topY + 5, 2, 5, "s");
    R(L, 15, topY + (flapUp ? 2 : 4), 4, 3, "s");
  } else {
    R(L, 4, topY + 5 + (bop > 0 ? 1 : 0), 2, 6, "s"); R(L, 4, topY + 9, 2, 2, "d");
    R(L, 14, topY + 5 + (bop < 0 ? 1 : 0), 2, 6, "s"); R(L, 14, topY + 9, 2, 2, "d");
  }

  // Ear Tufts & Round Feathered Body
  R(L, 5 + tilt, Math.max(0, topY - 2), 2, 2, "d"); R(L, 5 + tilt, Math.max(0, topY - 2), 1, 1, "a");
  R(L, 13 - tilt, Math.max(0, topY - 2), 2, 2, "d"); R(L, 14 - tilt, Math.max(0, topY - 2), 1, 1, "a");
  R(L, 5, topY, 10, 12, "b");
  R(L, 6, topY, 8, 2, "s");

  // Chevron Chest Plumage
  R(L, 7, topY + 6, 6, 6, "l");
  R(L, 8, topY + 7, 1, 1, "s"); R(L, 11, topY + 7, 1, 1, "s");
  R(L, 9, topY + 9, 2, 1, "s");

  // Large Owl Eyes & Golden Beak
  var ey = topY + 2;
  if (pose === "happy" || pose === "celebrate" || pose === "groove") {
    R(L, 6, ey + 1, 3, 1, "m"); R(L, 11, ey + 1, 3, 1, "m");
    R(L, 7, ey, 1, 1, "e"); R(L, 12, ey, 1, 1, "e");
  } else if (pose === "alert" || pose === "air" || pose === "drag") {
    R(L, 6, ey, 3, 3, "g"); R(L, 7, ey + 1, 1, 1, "m");
    R(L, 11, ey, 3, 3, "g"); R(L, 12, ey + 1, 1, 1, "m");
  } else if (blink) {
    R(L, 6, ey + 1, 3, 1, "m"); R(L, 11, ey + 1, 3, 1, "m");
  } else {
    R(L, 6 + tilt, ey, 3, 3, "e"); R(L, 7 + tilt, ey + 1, 1, 1, "m"); R(L, 6 + tilt, ey, 1, 1, "w");
    R(L, 11 + tilt, ey, 3, 3, "e"); R(L, 12 + tilt, ey + 1, 1, 1, "m"); R(L, 11 + tilt, ey, 1, 1, "w");
  }
  R(L, 9 + tilt, ey + 2, 2, 2, "p");

  // Feed Berry Treat
  if (pose === "feed") {
    R(L, 16, 15, 3, 3, "a"); R(L, 17, 15, 1, 1, "g");
  }

  // Gripping Talons
  var fy = 16 - hop;
  if (pose === "walk") {
    var st = (t % 4) < 2 ? 1 : 0;
    R(L, 7, 16 - st, 2, 2, "p"); R(L, 11, 16 - (1 - st), 2, 2, "p");
  } else {
    R(L, 7, fy, 2, 2, "p"); R(L, 11, fy, 2, 2, "p");
  }
  return L;
}

function amphibian(s, pose, tick) {
  var L = [];
  var t = tick || 0;
  var blink = (t % 28) === 27;
  var wig = (t % 4) < 2 ? 0 : 1;

  if (pose === "spin") {
    var sp = t % 4;
    R(L, 3, 7 + wig, 3, 1, "p"); R(L, 3, 9, 3, 1, "a"); R(L, 3, 11 - wig, 3, 1, "p");
    R(L, 14, 7 + wig, 3, 1, "p"); R(L, 14, 9, 3, 1, "a"); R(L, 14, 11 - wig, 3, 1, "p");
    R(L, 6, 7, 8, 9, sp === 3 ? "s" : "b");
    R(L, 7, 11, 6, 4, "l");
    if (sp !== 3) {
      R(L, 7, 9, 2, 2, "e"); R(L, 11, 9, 2, 2, "e");
      R(L, 8, 12, 4, 1, "m");
    }
    R(L, 6, 16, 2, 2, "s"); R(L, 12, 16, 2, 2, "s");
    return L;
  }

  if (pose === "sleep") {
    R(L, 2, 13, 4, 3, "s"); R(L, 1, 14, 2, 2, "d");
    R(L, 5, 11, 11, 7, "b"); R(L, 6, 14, 9, 4, "l");
    R(L, 10, 10, 2, 2, "p"); R(L, 15, 10, 2, 2, "p");
    R(L, 12, 13, 3, 1, "m");
    return L;
  }

  if (pose === "stretch") {
    R(L, 0, 12, 5, 3, "d"); R(L, 1, 13, 4, 2, "s");
    R(L, 4, 12, 8, 4, "b"); R(L, 5, 14, 7, 2, "l");
    R(L, 11, 10, 7, 6, "b");
    R(L, 10, 9, 2, 2, "p"); R(L, 17, 9, 2, 2, "p");
    R(L, 14, 12, 2, 1, "e"); R(L, 15, 14, 3, 1, "m");
    R(L, 5, 16, 2, 2, "s"); R(L, 15, 16, 4, 2, "s");
    return L;
  }

  var hop = (pose === "happy" || pose === "celebrate") ? ((t % 2) === 0 ? 2 : 0) : 0;
  var swim = (pose === "air" || pose === "drag") ? ((t % 4) < 2 ? 1 : -1) : 0;
  var dy = (pose === "groove" ? wig : 0) - hop;
  var excited = (pose === "happy" || pose === "groove" || pose === "celebrate" || pose === "fetch");
  var gShift = excited ? wig : 0;

  // Undulating Finned Tail (x=1..6)
  var ty = Math.max(4, 11 + dy + swim);
  R(L, 1, ty, 5, 4, "d");
  R(L, 2, ty + 1, 4, 2, "b");
  R(L, 1, ty + 1, 2, 1, "l");

  // Rounded Pastel Body (x=5..13)
  var by = Math.max(4, 10 + dy);
  R(L, 5, by, 8, 6, "b");
  R(L, 6, by, 6, 1, "s");
  R(L, 6, by + 3, 6, 3, "l");

  // Head & 3 Feathery External Gill Fronds per side (x=9..19)
  var hy = Math.max(2, 7 + dy - (pose === "alert" ? 1 : 0));
  // Back gill fronds (left of head)
  R(L, 8, hy - 1 + gShift, 2, 1, "a");
  R(L, 8, hy + 1, 2, 1, "p");
  R(L, 8, hy + 3 - gShift, 2, 1, "a");
  // Front gill fronds (right of head)
  R(L, 17, hy - 1 + gShift, 2, 1, "a");
  R(L, 17, hy + 1, 2, 1, "p");
  R(L, 17, hy + 3 - gShift, 2, 1, "a");

  R(L, 10, hy, 7, 7, "b");
  R(L, 11, hy, 5, 1, "l");

  // Glossy Eyes, Blush & Wide Axolotl Smile
  if (pose === "happy" || pose === "celebrate" || pose === "groove") {
    R(L, 11, hy + 2, 2, 1, "e"); R(L, 15, hy + 2, 2, 1, "e");
    R(L, 12, hy + 4, 4, 2, "m");
  } else if (pose === "air" || pose === "drag" || pose === "alert") {
    R(L, 11, hy + 2, 2, 2, "e"); R(L, 11, hy + 2, 1, 1, "w");
    R(L, 15, hy + 2, 2, 2, "e"); R(L, 15, hy + 2, 1, 1, "w");
    R(L, 13, hy + 5, 2, 2, "m");
  } else {
    if (blink) {
      R(L, 11, hy + 3, 2, 1, "m"); R(L, 15, hy + 3, 2, 1, "m");
    } else {
      R(L, 11, hy + 2, 2, 2, "e"); R(L, 11, hy + 2, 1, 1, "w");
      R(L, 15, hy + 2, 2, 2, "e"); R(L, 15, hy + 2, 1, 1, "w");
    }
    R(L, 12, hy + 5, 4, 1, "m");
  }
  R(L, 10, hy + 4, 1, 1, "a"); R(L, 16, hy + 4, 1, 1, "a");

  // Feed Water-Pellet Treat
  if (pose === "feed") {
    R(L, 17, 15, 2, 3, "g"); R(L, 18, 15, 1, 1, "w");
  }

  // Stubby Waddling Legs
  if (pose === "walk" || pose === "run") {
    var ph = (t % 4) < 2 ? 1 : 0;
    R(L, 6 + ph, 16, 2, 2, "s"); R(L, 12 - ph, 16, 2, 2, "s");
  } else if (pose === "wave") {
    R(L, 6, 16, 2, 2, "s"); R(L, 15, 12 + wig, 3, 2, "s");
  } else {
    var ly = 16 - hop;
    R(L, 6, ly, 2, 2, "s"); R(L, 12, ly, 2, 2, "s");
  }
  return L;
}

function biped_quad(s, pose, tick) {
  var L = [];
  var t = tick || 0;
  var blink = (t % 28) === 27;
  var sway = (t % 4) < 2 ? 0 : 1;

  // Classic Upright Red Panda Stance (alert, wave, celebrate)
  if (pose === "alert" || pose === "wave" || pose === "celebrate") {
    var hop = (pose === "celebrate" && (t % 2) === 0) ? 1 : 0;
    var hy = 2 - hop;
    // Ringed Bushy Tail behind
    R(L, 2, 11 - hop, 5, 4, "b"); R(L, 3, 11 - hop, 1, 4, "p"); R(L, 5, 11 - hop, 1, 4, "a");
    // Raised Front Paws (classic threat / cheer stance)
    var lp = (pose === "wave") ? (sway ? 7 : 9) : 6 - hop;
    var rp = (pose === "wave") ? (sway ? 9 : 7) : 6 - hop;
    R(L, 3, lp, 3, 4, "d"); R(L, 14, rp, 3, 4, "d");
    // Upright Torso with dark espresso belly
    R(L, 6, 9 - hop, 8, 6, "b"); R(L, 7, 10 - hop, 6, 5, "d");
    // Round White-Rimmed Ears & Head
    R(L, 6, hy, 3, 2, "l"); R(L, 7, hy + 1, 2, 1, "b");
    R(L, 11, hy, 3, 2, "l"); R(L, 11, hy + 1, 2, 1, "b");
    R(L, 6, hy + 2, 8, 5, "b");
    R(L, 7, hy + 3, 2, 1, "l"); R(L, 11, hy + 3, 2, 1, "l"); // White eyebrows
    R(L, 8, hy + 5, 4, 2, "l"); R(L, 9, hy + 5, 2, 1, "m"); // White muzzle
    if (pose === "alert") {
      R(L, 7, hy + 4, 2, 1, "e"); R(L, 11, hy + 4, 2, 1, "e");
    } else {
      R(L, 7, hy + 4, 2, 1, "e"); R(L, 11, hy + 4, 2, 1, "e");
    }
    R(L, 7, 15 - hop, 2, 3, "d"); R(L, 11, 15 - hop, 2, 3, "d");
    return L;
  }

  if (pose === "spin") {
    var sp = t % 4;
    R(L, 2, 11, 4, 4, "b"); R(L, 3, 11, 1, 4, "p");
    R(L, 6, 3, 3, 2, "l"); R(L, 11, 3, 3, 2, "l");
    R(L, 6, 5, 8, 5, "b");
    if (sp !== 3) {
      R(L, 7, 6, 2, 1, "l"); R(L, 11, 6, 2, 1, "l");
      R(L, 7, 7, 2, 1, "e"); R(L, 11, 7, 2, 1, "e");
      R(L, 8, 8, 4, 2, "l");
    }
    R(L, 6, 10, 8, 5, sp === 3 ? "s" : "d");
    R(L, 7, 15, 2, 3, "d"); R(L, 11, 15, 2, 3, "d");
    return L;
  }

  if (pose === "sleep") {
    // Curled around oversized ringed tail
    R(L, 3, 11, 13, 7, "b");
    R(L, 3, 12, 8, 4, "b"); R(L, 4, 12, 1, 4, "p"); R(L, 6, 12, 1, 4, "a"); R(L, 8, 12, 1, 4, "p");
    R(L, 11, 11, 6, 5, "b");
    R(L, 11, 9, 2, 2, "l"); R(L, 14, 9, 2, 2, "l");
    R(L, 13, 13, 3, 1, "m"); R(L, 14, 14, 3, 2, "l");
    return L;
  }

  if (pose === "stretch") {
    R(L, 1, 6, 4, 5, "b"); R(L, 2, 7, 1, 3, "p"); R(L, 3, 7, 1, 3, "a");
    R(L, 5, 9, 5, 5, "b"); R(L, 9, 12, 4, 4, "d");
    R(L, 11, 10, 2, 2, "l"); R(L, 15, 10, 2, 2, "l");
    R(L, 11, 11, 7, 5, "b"); R(L, 15, 14, 3, 2, "l"); R(L, 14, 12, 2, 1, "e");
    R(L, 6, 14, 2, 4, "d"); R(L, 14, 16, 5, 2, "d");
    return L;
  }

  // Quadruped Red Panda (sit, stand, walk, run, air, drag, happy, groove, feed)
  var hop = (pose === "happy") ? ((t % 2) === 0 ? 2 : 0) : 0;
  var dy = (pose === "groove" ? sway : 0) - hop;

  // Oversized Ringed Bushy Tail (x=1..7)
  var ty = Math.max(5, 10 + sway - hop);
  R(L, 1, ty, 6, 4, "b");
  R(L, 2, ty, 1, 4, "p");
  R(L, 4, ty, 1, 4, "a");
  R(L, 1, ty + 1, 1, 2, "d");

  // Rust Torso & Dark Espresso Belly (x=6..14)
  var by = Math.max(4, 10 + dy);
  R(L, 6, by, 8, 5, "b");
  R(L, 6, by, 7, 2, "s");
  R(L, 7, by + 3, 6, 2, "d");

  // Head with White Eyebrow Spots & Muzzle (x=10..18)
  var hy = Math.max(2, 5 + dy + (pose === "feed" && sway ? 1 : 0));
  R(L, 10, Math.max(0, hy - 2), 2, 2, "l"); R(L, 11, Math.max(1, hy - 1), 1, 1, "b");
  R(L, 14, Math.max(0, hy - 2), 2, 2, "l"); R(L, 14, Math.max(1, hy - 1), 1, 1, "b");
  R(L, 10, hy, 7, 5, "b");
  R(L, 13, hy + 1, 2, 1, "l"); // White eyebrow spot
  R(L, 15, hy + 3, 3, 2, "l"); // White muzzle
  R(L, 17, hy + 3, 1, 1, "m"); // Nose

  if (pose === "happy" || pose === "groove") {
    R(L, 13, hy + 2, 2, 1, "e");
  } else if (blink) {
    R(L, 13, hy + 2, 2, 1, "m");
  } else {
    R(L, 13, hy + 2, 2, 2, "e"); R(L, 13, hy + 2, 1, 1, "w");
  }

  // Feed Bamboo Shoot
  if (pose === "feed") {
    R(L, 17, 11, 2, 7, "g"); R(L, 18, 12, 1, 1, "l");
  }

  // Dark Espresso Legs
  if (pose === "walk" || pose === "run") {
    var ph = t % 4;
    var st = (ph === 0 || ph === 2) ? 0 : (ph === 1 ? -1 : 1);
    R(L, 7 + st, 15, 2, 3, "d"); R(L, 12 - st, 15, 2, 3, "d");
  } else {
    var ly = 15 - hop;
    R(L, 7, ly, 2, 3, "d"); R(L, 12, ly, 2, 3, "d");
  }
  return L;
}

function penguin(s, pose, tick) {
  var L = [];
  var t = tick || 0;
  var blink = (t % 28) === 27;
  var flap = (t % 4) < 2;

  // Belly Toboggan Slide in RUN!
  if (pose === "run") {
    // Trailing neon cyan scarf
    R(L, 1, 10 + (flap ? 0 : 1), 4, 2, "g"); R(L, 3, 11, 2, 1, "a");
    // Horizontal sliding body
    R(L, 4, 11, 11, 5, "b"); R(L, 5, 11, 9, 2, "s");
    R(L, 5, 15, 10, 3, "l");
    // Flipper swept back & orange feet trailing
    R(L, 8, 12, 4, 2, "d");
    R(L, 2, 15, 3, 2, "p");
    // Forward head & beak
    R(L, 13, 9, 5, 6, "b"); R(L, 15, 11, 3, 3, "l");
    R(L, 15, 11, 2, 2, "e"); R(L, 15, 11, 1, 1, "w");
    R(L, 18, 12, 2, 2, "p");
    // Scarf wrap
    R(L, 12, 11, 2, 4, "g");
    return L;
  }

  if (pose === "spin") {
    var sp = t % 4;
    R(L, 6, 4, 8, 12, "b");
    if (sp !== 3) {
      R(L, 7, 9, 6, 6, "l");
      R(L, 7, 6, 2, 2, "e"); R(L, 11, 6, 2, 2, "e");
      R(L, 9, 8, 2, 1, "p");
    } else {
      R(L, 7, 5, 6, 10, "d");
    }
    R(L, 6, 9, 8, 2, "g"); R(L, 13, 10, 2, 3, "a");
    R(L, 7, 16, 2, 2, "p"); R(L, 11, 16, 2, 2, "p");
    return L;
  }

  if (pose === "sleep") {
    R(L, 5, 9, 10, 8, "b"); R(L, 6, 12, 8, 5, "l");
    R(L, 6, 12, 8, 2, "g"); R(L, 13, 13, 3, 2, "a"); // Cozy scarf wrap
    R(L, 7, 11, 2, 1, "w"); R(L, 11, 11, 2, 1, "w");
    R(L, 9, 12, 2, 1, "p");
    R(L, 7, 17, 2, 1, "p"); R(L, 11, 17, 2, 1, "p");
    return L;
  }

  if (pose === "stretch") {
    // Flippers raised wide + leaning tall
    R(L, 2, 5, 4, 3, "b"); R(L, 14, 5, 4, 3, "b");
    R(L, 6, 3, 8, 13, "b"); R(L, 7, 9, 6, 6, "l");
    R(L, 6, 9, 8, 2, "g");
    R(L, 7, 5, 2, 1, "w"); R(L, 11, 5, 2, 1, "w");
    R(L, 9, 7, 2, 2, "p");
    R(L, 7, 16, 2, 2, "p"); R(L, 11, 16, 2, 2, "p");
    return L;
  }

  // Upright Cyber Tux (sit, stand, walk, air, drag, wave, groove, alert, happy, celebrate, feed)
  var hop = (pose === "happy" || pose === "celebrate") ? ((t % 2) === 0 ? 2 : 0) : 0;
  var dy = (pose === "groove" ? (flap ? 1 : 0) : 0) - hop;
  var topY = Math.max(2, 4 + dy);

  // Flippers
  if (pose === "happy" || pose === "celebrate" || pose === "air" || pose === "alert") {
    var fy = topY + (flap ? 2 : 5);
    R(L, 3, fy, 3, 3, "b"); R(L, 14, fy, 3, 3, "b");
  } else if (pose === "wave") {
    R(L, 4, topY + 6, 2, 4, "b");
    R(L, 14, topY + (flap ? 2 : 4), 4, 3, "b");
  } else {
    R(L, 4, topY + 6, 2, 5, "s"); R(L, 14, topY + 6, 2, 5, "s");
  }

  // Body & Snow-White Belly
  R(L, 6, topY, 8, 12, "b");
  R(L, 7, topY, 6, 1, "s");
  R(L, 7, topY + 5, 6, 7, "l");

  // Neon Cyan Scarf + Trailing Tail
  R(L, 6, topY + 5, 8, 2, "g");
  R(L, 13, topY + 6, 2, 3, "a");
  if (pose === "air" || pose === "walk") {
    R(L, 15, topY + 5 + (flap ? 0 : 1), 2, 2, "g");
  }

  // Eyes & Tangerine Beak
  var ey = topY + 2;
  if (pose === "happy" || pose === "celebrate" || pose === "groove") {
    R(L, 7, ey + 1, 2, 1, "w"); R(L, 11, ey + 1, 2, 1, "w");
    R(L, 9, ey + 2, 2, 2, "p");
  } else if (blink) {
    R(L, 7, ey + 1, 2, 1, "s"); R(L, 11, ey + 1, 2, 1, "s");
    R(L, 9, ey + 2, 2, 1, "p");
  } else {
    R(L, 7, ey, 2, 2, "w"); R(L, 8, ey + 1, 1, 1, "e");
    R(L, 11, ey, 2, 2, "w"); R(L, 11, ey + 1, 1, 1, "e");
    R(L, 9, ey + 2, 2, 2, "p");
  }

  // Feed Silver-Cyan Fish Treat
  if (pose === "feed") {
    R(L, 16, 15, 3, 2, "g"); R(L, 19, 14, 1, 3, "a");
  }

  // Webbed Orange Feet
  if (pose === "walk") {
    var st = flap ? 1 : 0;
    R(L, 6, 16 - st, 3, 2, "p"); R(L, 11, 16 - (1 - st), 3, 2, "p");
  } else {
    var py = 16 - hop;
    R(L, 6, py, 3, 2, "p"); R(L, 11, py, 3, 2, "p");
  }
  return L;
}

// ---- public ------------------------------------------------------------------
// Returns {w, h, rects} for a skin/pose/tick. Colors are looked up with colors(skinId).
function build(skinId, pose, tick) {
  var s = skins[skinId] || skins.cat;
  var t = tick || 0;

  var L;
  if (pose === "peek") {
    L = peekPose(s, t);
  } else {
    // Map Phase 2 composite poses to base pose for body geometry
    var basePose = pose;
    if (pose === "fetch")   basePose = (t % 4) < 2 ? "happy" : "wave";
    if (pose === "focus")   basePose = "sit";
    if (pose === "curious") basePose = "sit";
    if (pose === "sweat")   basePose = "alert";

    if      (s.kind === "drake")      L = drake(s, basePose, t);
    else if (s.kind === "mecha")      L = mecha(s, basePose, t);
    else if (s.kind === "spirit")     L = spirit(s, basePose, t);
    else if (s.kind === "avian")      L = avian(s, basePose, t);
    else if (s.kind === "amphibian")  L = amphibian(s, basePose, t);
    else if (s.kind === "biped_quad") L = biped_quad(s, basePose, t);
    else if (s.kind === "penguin")    L = penguin(s, basePose, t);
    else if (s.kind === "blob")       L = blob(s, basePose, t);
    else                              L = quad(s, basePose, t);

    // Phase 2 Pose Overlays (strictly inside 0..19 x 0..17)
    if (pose === "fetch") {
      // Bouncing pixel toy ball batted in front of pet
      var arcY = [15, 12, 10, 12, 15][t % 5];
      var arcX = [16, 17, 17, 16, 16][t % 5];
      R(L, arcX, arcY, 3, 3, K(s, "a", "p"));
      R(L, arcX, arcY, 1, 1, "w");
    } else if (pose === "focus") {
      // Mini glowing study terminal / notebook at bottom-right
      R(L, 15, 16, 5, 2, "d");
      R(L, 16, 13, 4, 3, "d");
      R(L, 17, 14, 2, 1, (t % 6) < 3 ? K(s, "g", "l") : "w");
    } else if (pose === "curious") {
      // Subtle tilted ear/head accent + compact pixel '?' glint
      var qy = (t % 4) < 2 ? 1 : 2;
      R(L, 16, qy, 2, 1, K(s, "g", "p"));
      R(L, 17, qy + 1, 1, 1, K(s, "g", "p"));
      R(L, 17, qy + 3, 1, 1, "w");
    } else if (pose === "sweat") {
      // Subtle 1-cell nervous tremble (clamped to 20-cell width)
      var dx = (t % 2) === 0 ? 0 : 1;
      if (dx === 1) {
        for (var i = 0; i < L.length; i++) {
          if (L[i][0] + L[i][2] < 20) L[i][0] += 1;
        }
      }
      // Animated falling sweat drop at top-right
      var sy = 2 + (t % 3);
      R(L, 17, sy, 2, 3, K(s, "g", "w"));
      R(L, 17, sy, 1, 1, "w");
    }
  }

  return { w: W, h: H, rects: L };
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
