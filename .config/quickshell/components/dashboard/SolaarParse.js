.pragma library

// `solaar show`'s human-readable dump (it has no stable machine-readable
// output) read into the peripherals that report a battery - kept apart from
// Dashboard.qml, which polls it, so it can be tested on its own.
//
// Two header shapes exist: a receiver-paired peripheral is indented exactly 2
// spaces as "N: Name" (e.g. "  1: G703 LIGHTSPEED..."), while a receiver
// itself or a peripheral of its own (Bluetooth, USB - no receiver) is a bare
// name at column 0 (e.g. "Lightspeed Receiver", "PRO X TKL"). Which of those
// two a column-0 one is only shows further down: a receiver says "Has N
// paired device(s)", and the devices after it are its own. Deeper "N: ..."
// lines also exist inside a device's block (its HID++ feature list), indented
// well past 2 spaces, which is what anchoring to exactly 2 keeps out.
//
// A device's last "Battery: N%" line is its reading: some features (e.g.
// ADC MEASUREMENT) print a nested one of their own before the summary line
// that ends the block, which is the one that counts. BatteryStatus is one of
// FULL, DISCHARGING and RECHARGING - only RECHARGING means it's charging.
//
// Each device: name, percentage (0 - 1), charging, status, and whichever of
// receiver, kind, codename, serial, firmware, protocol, reportRate and wpid
// its block gives.

var fields = {
    "Kind": "kind",
    "Codename": "codename",
    "Serial number": "serial",
    "Firmware": "firmware",
    "Protocol": "protocol",
    "Report Rate": "reportRate",
    "Polling Rate": "reportRate",
    "WPID": "wpid"
}

function parse(text) {
    const devices = []
    let receiver = ""
    let block = null

    // A block with a battery reading is a device; anything else (a receiver,
    // a device that didn't say) isn't listed.
    function finish() {
        if (block && block.battery)
            devices.push(Object.assign({ name: block.name, receiver: block.receiver }, block.battery, block.info))
    }

    for (const line of text.split("\n")) {
        const paired = line.match(/^ {2}(\d+):\s+(.+?)\s*$/)
        if (paired) {
            finish()
            block = { name: paired[2], receiver: receiver, info: {}, battery: null }
            continue
        }

        if (/^\S/.test(line) && !/^(solaar version|solaar show|rules cannot access)/i.test(line)) {
            finish()
            block = { name: line.trim(), receiver: "", info: {}, battery: null }
            continue
        }

        if (!block) continue

        if (/^\s+Has \d+ paired device/.test(line)) {
            receiver = block.name
            continue
        }

        const field = line.match(/^\s+([A-Za-z][A-Za-z ]*?)\s*:\s*(.*?)\s*$/)
        if (field && fields[field[1]] && !(fields[field[1]] in block.info) && field[2].length > 0)
            block.info[fields[field[1]]] = field[2]

        const battery = line.match(/Battery:\s*(\d+)%(?:.*?BatteryStatus\.(\w+))?/)
        if (battery) {
            block.battery = {
                percentage: parseInt(battery[1], 10) / 100,
                charging: battery[2] === "RECHARGING",
                status: (battery[2] || "").toLowerCase()
            }
        }
    }
    finish()
    return devices
}
