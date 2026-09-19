import QtQuick
import Quickshell.Io
import "../"
import "../../Config.js" as Config

// CPU/GPU/RAM usage meters for the dashboard's center column filler slot
// (see Dashboard.qml) - same "digital"/segmented bar look as Volume/
// Brightness/Battery in the bar, plus a small bracket-tagged sub-stat row
// under CPU (temp) and GPU (temp + VRAM), matching the reference image's
// "└ LABEL [bar] value ┘" convention. Loaded lazily by path (not
// instantiated directly), same as NowPlaying.qml/Cava.qml right next to
// it - a wrong shell-tool assumption here only blanks this card instead
// of breaking the whole shell.
//
// Sized noticeably smaller than the reference image's own text - this
// column is much narrower and shorter than that image's layout, and the
// original size didn't fit three sections vertically.
Item {
    id: root

    property real uiScale: 1.0

    anchors.fill: parent

    // ---------------- CPU ----------------
    property real cpuUsage: 0 // 0.0 - 1.0
    property real cpuTemp: -1 // degrees C, -1 = not yet known/unsupported
    property real _lastCpuTotal: -1
    property real _lastCpuIdle: -1

    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuStatProcess.running = false
            cpuStatProcess.running = true
        }
    }

    Process {
        id: cpuStatProcess
        command: ["cat", "/proc/stat"]

        stdout: StdioCollector {
            onStreamFinished: {
                // First line: "cpu  user nice system idle iowait irq
                // softirq steal guest guest_nice" (all-core aggregate,
                // jiffies since boot). Usage % needs two samples - a
                // single snapshot has no notion of "busy vs idle", only
                // a delta between two points in time does.
                const line = text.split("\n")[0]
                const fields = line.trim().split(/\s+/).slice(1).map(Number)
                if (fields.some(isNaN) || fields.length < 4) return

                const idle = fields[3] + (fields[4] || 0)
                const total = fields.reduce((a, b) => a + b, 0)

                if (root._lastCpuTotal >= 0) {
                    const totalDelta = total - root._lastCpuTotal
                    const idleDelta = idle - root._lastCpuIdle
                    if (totalDelta > 0) {
                        root.cpuUsage = Math.max(0, Math.min(1, 1 - idleDelta / totalDelta))
                    }
                }
                root._lastCpuTotal = total
                root._lastCpuIdle = idle
            }
        }
    }

    // lm-sensors' chip/field naming varies by CPU vendor/driver
    // (coretemp's "Package id 0" on Intel, k10temp/zenpower's "Tctl"/
    // "Tdie" on AMD Ryzen) - this is a best-effort match across the
    // common ones, not a guaranteed hit on every machine. Hidden
    // entirely (see cpuTemp/root.hasCpuTemp below) rather than showing a
    // wrong reading if nothing matches, same convention
    // BrightnessControl.qml/BatteryControl.qml use for "not supported
    // here".
    readonly property bool hasCpuTemp: root.cpuTemp >= 0
    property bool _sensorsGotOutput: false

    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            sensorsProcess.running = false
            sensorsProcess.running = true
        }
    }

    Process {
        id: sensorsProcess
        command: ["sensors", "-j"]

        // _sensorsGotOutput is reset before every run and only ever set
        // true from inside a successful parse below - onRunningChanged
        // fires again right after stdout finishes (once the process has
        // actually exited), so without this flag its "not running"
        // branch would immediately stomp right back over whatever the
        // stdout handler just set, every single cycle.
        onRunningChanged: {
            if (running) {
                root._sensorsGotOutput = false
            } else if (!root._sensorsGotOutput) {
                root.cpuTemp = -1
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    let found = -1
                    for (const chip in parsed) {
                        if (!/coretemp|k10temp|zenpower|cpu/i.test(chip)) continue
                        const fields = parsed[chip]
                        for (const key in fields) {
                            if (!/^(Package id 0|Tdie|Tctl|Core 0)/.test(key)) continue
                            const sub = fields[key]
                            for (const subkey in sub) {
                                if (subkey.endsWith("_input")) {
                                    found = sub[subkey]
                                    break
                                }
                            }
                            if (found >= 0) break
                        }
                        if (found >= 0) break
                    }
                    if (found >= 0) {
                        root.cpuTemp = found
                        root._sensorsGotOutput = true
                    }
                } catch (e) {
                    // Leave _sensorsGotOutput false - onRunningChanged
                    // above clears cpuTemp once the process exits.
                }
            }
        }
    }

    // ---------------- RAM ----------------
    property real ramUsage: 0 // 0.0 - 1.0
    property real ramUsedMb: 0
    property real ramTotalMb: 0

    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            memInfoProcess.running = false
            memInfoProcess.running = true
        }
    }

    Process {
        id: memInfoProcess
        command: ["cat", "/proc/meminfo"]

        stdout: StdioCollector {
            onStreamFinished: {
                const totalMatch = text.match(/^MemTotal:\s+(\d+)/m)
                const availMatch = text.match(/^MemAvailable:\s+(\d+)/m)
                if (!totalMatch || !availMatch) return
                const total = Number(totalMatch[1])
                const avail = Number(availMatch[1])
                if (total > 0) {
                    root.ramUsage = Math.max(0, Math.min(1, 1 - avail / total))
                    root.ramTotalMb = total / 1024
                    root.ramUsedMb = (total - avail) / 1024
                }
            }
        }
    }

    // ---------------- GPU (NVIDIA only for now - see nvidiaProcess) ----------------
    property real gpuUsage: 0 // 0.0 - 1.0
    property real gpuTemp: -1
    property real gpuVramUsedMb: 0
    property real gpuVramTotalMb: 0
    property bool gpuAvailable: false
    property bool _nvidiaGotOutput: false

    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            nvidiaProcess.running = false
            nvidiaProcess.running = true
        }
    }

    // AMD/Intel GPUs aren't covered here yet - nvidia-smi is the only
    // single, well-documented command that reports usage/temp/VRAM in
    // one call without guessing at sysfs paths that vary by driver/card.
    // Missing entirely (not installed, or no NVIDIA GPU) just hides this
    // whole section - see gpuAvailable below - rather than guess wrong.
    Process {
        id: nvidiaProcess
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"]

        // See sensorsProcess's identical _sensorsGotOutput above for why
        // this can't just unconditionally clear gpuAvailable once the
        // process stops running.
        onRunningChanged: {
            if (running) {
                root._nvidiaGotOutput = false
            } else if (!root._nvidiaGotOutput) {
                root.gpuAvailable = false
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",").map(s => parseFloat(s.trim()))
                if (parts.length >= 4 && !parts.some(isNaN)) {
                    root.gpuUsage = Math.max(0, Math.min(1, parts[0] / 100))
                    root.gpuTemp = parts[1]
                    root.gpuVramUsedMb = parts[2]
                    root.gpuVramTotalMb = parts[3]
                    root.gpuAvailable = true
                    root._nvidiaGotOutput = true
                }
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: Config.scaled(10, root.uiScale)

        // ---------------- CPU ----------------
        Column {
            width: parent.width
            spacing: Config.scaled(4, root.uiScale)

            Text {
                text: "CPU"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(12, root.uiScale)
                font.bold: true
            }

            DigitalBar {
                uiScale: root.uiScale
                value: root.cpuUsage
                targetWidth: parent.width
                segmentCount: 28
                barHeight: Config.scaled(9, root.uiScale)
            }

            Row {
                anchors.right: parent.right
                spacing: Config.scaled(6, root.uiScale)

                BracketTag {
                    uiScale: root.uiScale
                    visible: root.hasCpuTemp
                    text: Math.round(root.cpuTemp) + "°"
                }

                BracketTag {
                    uiScale: root.uiScale
                    text: Math.round(root.cpuUsage * 100) + "%"
                }
            }
        }

        // ---------------- GPU ----------------
        Column {
            width: parent.width
            spacing: Config.scaled(4, root.uiScale)
            visible: root.gpuAvailable

            Text {
                text: "GPU"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(12, root.uiScale)
                font.bold: true
            }

            DigitalBar {
                uiScale: root.uiScale
                value: root.gpuUsage
                targetWidth: parent.width
                segmentCount: 28
                barHeight: Config.scaled(9, root.uiScale)
            }

            Row {
                anchors.right: parent.right
                spacing: Config.scaled(6, root.uiScale)

                BracketTag {
                    uiScale: root.uiScale
                    text: Math.round(root.gpuTemp) + "°"
                }

                BracketTag {
                    uiScale: root.uiScale
                    text: Math.round(root.gpuUsage * 100) + "%"
                }
            }
        }

        // ---------------- VRAM ----------------
        Column {
            width: parent.width
            spacing: Config.scaled(4, root.uiScale)
            visible: root.gpuAvailable

            Text {
                text: "VRAM"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(12, root.uiScale)
                font.bold: true
            }

            DigitalBar {
                uiScale: root.uiScale
                value: root.gpuVramTotalMb > 0 ? root.gpuVramUsedMb / root.gpuVramTotalMb : 0
                targetWidth: parent.width
                segmentCount: 28
                barHeight: Config.scaled(9, root.uiScale)
            }

            Row {
                anchors.right: parent.right
                spacing: Config.scaled(6, root.uiScale)

                BracketTag {
                    uiScale: root.uiScale
                    text: (root.gpuVramUsedMb / 1024).toFixed(2) + "GB / " + (root.gpuVramTotalMb / 1024).toFixed(1) + "GB"
                }

                BracketTag {
                    uiScale: root.uiScale
                    text: (root.gpuVramTotalMb > 0 ? Math.round(root.gpuVramUsedMb / root.gpuVramTotalMb * 100) : 0) + "%"
                }
            }
        }

        // ---------------- RAM ----------------
        Column {
            width: parent.width
            spacing: Config.scaled(4, root.uiScale)

            Text {
                text: "RAM"
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(12, root.uiScale)
                font.bold: true
            }

            DigitalBar {
                uiScale: root.uiScale
                value: root.ramUsage
                targetWidth: parent.width
                segmentCount: 28
                barHeight: Config.scaled(9, root.uiScale)
            }

            Row {
                anchors.right: parent.right
                spacing: Config.scaled(6, root.uiScale)

                BracketTag {
                    uiScale: root.uiScale
                    text: (root.ramUsedMb / 1024).toFixed(2) + "GB / " + (root.ramTotalMb / 1024).toFixed(1) + "GB"
                }

                BracketTag {
                    uiScale: root.uiScale
                    text: Math.round(root.ramUsage * 100) + "%"
                }
            }
        }
    }
}
