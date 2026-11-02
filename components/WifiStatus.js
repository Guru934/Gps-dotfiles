.pragma library

function resolve(backendAvailable, devices, wifiEnabled, wifiDeviceType) {
    if (!backendAvailable) {
        return {
            available: false,
            enabled: false,
            connected: false,
            ssid: "Unavailable",
            device: "",
            signalStrength: 0
        }
    }

    const list = devices || []
    let wifiDevice = null
    for (let i = 0; i < list.length; i++) {
        if (list[i].type === wifiDeviceType) {
            wifiDevice = list[i]
            break
        }
    }

    if (!wifiDevice) {
        return {
            available: false,
            enabled: false,
            connected: false,
            ssid: "Unavailable",
            device: "",
            signalStrength: 0
        }
    }

    const networks = wifiDevice.networks ? wifiDevice.networks.values : []
    let connectedNetwork = null
    for (let i = 0; i < networks.length; i++) {
        if (networks[i].connected) {
            connectedNetwork = networks[i]
            break
        }
    }

    return {
        available: true,
        enabled: wifiEnabled,
        connected: connectedNetwork !== null,
        ssid: connectedNetwork
            ? connectedNetwork.name
            : (wifiEnabled ? "Not Connected" : "Wi-Fi Off"),
        device: wifiDevice.name,
        signalStrength: connectedNetwork ? connectedNetwork.signalStrength : 0
    }
}
