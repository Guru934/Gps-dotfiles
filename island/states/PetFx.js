.pragma library
// Deterministic frame-based mascot reactions. The island owns the clock; these
// helpers only map a start frame plus the current frame to a transient pose.

var waveFrames = 12
var jumpLift = [0, -4, -8, -8, -5, -2]

function elapsed(start, tick) {
    if (start < 0 || tick < start) return -1
    return tick - start
}

function waving(start, tick) {
    var frame = elapsed(start, tick)
    return frame >= 0 && frame < waveFrames
}

function jumping(start, tick) {
    var frame = elapsed(start, tick)
    return frame >= 0 && frame < jumpLift.length
}

function lift(start, tick) {
    var frame = elapsed(start, tick)
    if (frame < 0 || frame >= jumpLift.length) return 0
    return jumpLift[frame]
}
