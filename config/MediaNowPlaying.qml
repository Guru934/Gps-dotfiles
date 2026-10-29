pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property var players: Mpris.players ? Mpris.players.values : []
    property string preferredPlayerId: ""
    readonly property var player: selectPlayer()

    function idFor(candidate) {
        return candidate ? String(candidate.dbusName || candidate.uniqueId || candidate.identity || "") : ""
    }

    function selectPlayer() {
        const available = root.players
        if (!available || available.length === 0) return null
        if (root.preferredPlayerId !== "") {
            for (const candidate of available) {
                if (root.idFor(candidate) === root.preferredPlayerId) return candidate
            }
        }
        for (const candidate of available) {
            if (candidate.isPlaying) return candidate
        }
        for (const candidate of available) {
            if (candidate.trackTitle) return candidate
        }
        return available[0]
    }

    function choosePlayer(candidate) {
        if (!candidate || root.players.indexOf(candidate) < 0) return false
        root.preferredPlayerId = root.idFor(candidate)
        return true
    }

    function automaticPlayerSelection() {
        root.preferredPlayerId = ""
    }
}
