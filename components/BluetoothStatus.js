.pragma library

function resolve(adapter) {
    if (!adapter) {
        return {
            available: false,
            enabled: false,
            connected: false,
            name: "",
            state: "unavailable",
            statusText: "Unavailable",
            connectedName: "",
            connectedCount: 0,
            devices: [],
            connecting: false,
            disconnecting: false,
            discovering: false
        }
    }

    const devModel = (adapter.devices && adapter.devices.values) ? adapter.devices.values : []
    const devices = []
    let firstConnected = ""
    let connectedCount = 0
    let connecting = false
    let disconnecting = false

    for (let i = 0; i < devModel.length; i++) {
        const d = devModel[i]
        if (!d) continue
        const mac = d.address || ""
        const name = d.name || d.deviceName || mac
        const isConn = !!d.connected
        const isPaired = !!d.paired
        // BluetoothDeviceState: 0=Disconnected, 1=Connected, 2=Disconnecting, 3=Connecting
        const devState = (typeof d.state === "number") ? d.state : (isConn ? 1 : 0)
        const isConnecting = (devState === 3 || !!d.pairing)
        const isDisconnecting = (devState === 2)

        if (isConn) {
            connectedCount++
            if (firstConnected === "") firstConnected = name
        }
        if (isConnecting) connecting = true
        if (isDisconnecting) disconnecting = true

        devices.push({
            mac: mac,
            name: name,
            connected: isConn,
            paired: isPaired,
            state: devState,
            batteryAvailable: !!d.batteryAvailable,
            battery: (typeof d.battery === "number") ? d.battery : 0
        })
    }

    const isEnabled = !!adapter.enabled
    const isConnected = isEnabled && connectedCount > 0

    let statusText = "Unavailable"
    let state = "unavailable"

    if (!isEnabled) {
        state = "off"
        statusText = "Bluetooth Off"
    } else if (isConnected) {
        state = "connected"
        statusText = "Connected: " + firstConnected
    } else if (connecting) {
        state = "connecting"
        statusText = "Connecting…"
    } else if (disconnecting) {
        state = "disconnecting"
        statusText = "Disconnecting…"
    } else {
        state = "on"
        statusText = "Not Connected"
    }

    return {
        available: true,
        enabled: isEnabled,
        connected: isConnected,
        name: adapter.name || "",
        state: state,
        statusText: statusText,
        connectedName: firstConnected,
        connectedCount: connectedCount,
        devices: devices,
        connecting: connecting,
        disconnecting: disconnecting,
        discovering: !!adapter.discovering
    }
}
