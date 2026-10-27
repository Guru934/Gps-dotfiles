.pragma library
// Turns `hyprctl -j monitors` + `hyprctl -j clients` output into the pet's world:
// the focused monitor's logical size and the horizontal edges a pet can stand on.
// Pure JS (no Qt) so it can be tested with node.

function safe(text) {
  try { return JSON.parse(text); } catch (e) { return null; }
}

// spriteH = sprite height in logical px (used to discard edges with no headroom)
// floorInset = spare px below the feet for the sprite outline (one sprite cell)
function parse(monitorsText, clientsText, spriteH, spriteW, floorInset) {
  var mons = safe(monitorsText);
  var clients = safe(clientsText);
  if (!mons || !mons.length) return { ok: false };
  var m = null, i;
  for (i = 0; i < mons.length; i++) if (mons[i].focused) { m = mons[i]; break; }
  if (!m) m = mons[0];
  var sc = m.scale > 0 ? m.scale : 1;
  var rot = (m.transform | 0) % 2 === 1; // 90/270 degree rotations swap the axes
  var lw = (rot ? m.height : m.width) / sc;
  var lh = (rot ? m.width : m.height) / sc;
  var res = m.reserved || [0, 0, 0, 0]; // left, top, right, bottom
  var floor = lh - res[3];
  var inset = (typeof floorInset === "number" && floorInset > 0) ? floorInset : 0;
  var mon = {
    id: m.id, name: m.name, x: m.x, y: m.y, w: lw, h: lh,
    xMin: res[0], xMax: lw - res[2], yMin: res[1], floorY: floor - inset,
    ws: m.activeWorkspace ? m.activeWorkspace.id : -1,
    special: m.specialWorkspace && m.specialWorkspace.id ? m.specialWorkspace.id : 0
  };
  var surfaces = [];
  var fullscreen = false;
  var count = 0;
  if (clients && clients.length) {
    for (i = 0; i < clients.length; i++) {
      var c = clients[i];
      if (!c.mapped || c.hidden) continue;
      if (c.monitor !== m.id) continue;
      var wsid = c.workspace ? c.workspace.id : -99;
      var visible = (wsid === mon.ws) || (mon.special && wsid === mon.special);
      if (!visible) continue;
      count++;
      if (c.fullscreen === 2 || c.fullscreen === true) fullscreen = true;
      var x1 = c.at[0] - m.x, y1 = c.at[1] - m.y;
      var x2 = x1 + c.size[0], y2 = y1 + c.size[1];
      if (x1 < mon.xMin) x1 = mon.xMin;
      if (x2 > mon.xMax) x2 = mon.xMax;
      if (x2 - x1 < spriteW) continue;
      // top edge and bottom edge both count as ledges; both need headroom on screen
      var edges = [[y1, "t"], [y2, "b"]];
      for (var k = 0; k < edges.length; k++) {
        var ey = edges[k][0];
        if (ey - spriteH < mon.yMin) continue;
        if (ey >= floor - 14) continue; // that is the screen floor already
        surfaces.push({ id: c.address + edges[k][1], x1: x1, x2: x2, y: ey, floating: !!c.floating });
      }
    }
  }
  return { ok: true, monitor: mon, surfaces: surfaces, fullscreen: fullscreen, windows: count };
}

function parseCursor(text, mon) {
  var c = safe(text);
  if (!c || c.x === undefined) return null;
  return { x: c.x - (mon ? mon.x : 0), y: c.y - (mon ? mon.y : 0) };
}
