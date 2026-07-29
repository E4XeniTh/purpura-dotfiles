import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import QtQuick
import "../"
import "settings"
import "../../Config.js" as Config

// Dashboard dropdown, toggled from the avatar button in Bar.qml. Uses the
// same two-phase stretch-then-drop animation as Tray.qml's context menu.
// dashBox is fully opaque; each section inside sits in its own DashCard.
//
// Sizing rule: dashWidth/columnHeight scale with the screen, and every
// section within is a fraction of *available* space (container size minus
// its own padding/spacing), so fractions on the same axis always sum to
// 1.0 with no leftover/overflow. Everything else (fonts, icons, borders,
// spacing) scales with uiScale, computed against the 800px-wide reference
// this layout was tuned at on a 1920x1080 screen - see dashWindow below.
Scope {
    id: root

    property bool open: false
    property var screen: null

    // Set from shell.qml, so the power/lock buttons below can call these
    // directly instead of round-tripping through `qs ipc call` to talk to
    // another component in the very same process.
    property var powerMenu: null
    property var lockScreen: null

    // Shared across every screen's dashWindow (see below) - each one is
    // its own instance of everything nested inside it, including its own
    // ScreenSettings, so state that needs to affect *other* screens
    // (identify overlays, which monitor is "primary") has to live up
    // here instead of on whichever ScreenSettings instance the user
    // actually clicked. Bar.qml reads primaryMonitor too (via the
    // `dashboard` instance shell.qml passes it), to decide which
    // screen's bar shows the tray.
    property bool identifying: false
    property string primaryMonitor: "DP-1"

    // Same reasoning, for the currently-selected audio sink/source (see
    // AudioSettings.qml) - VolumeOsd.qml (instantiated separately in
    // shell.qml) needs to know which device was last explicitly picked
    // too, since Quickshell.Services.Pipewire's own defaultAudioSink
    // doesn't reliably update live after switching.
    property var audioSelectedSinkId: null
    property var audioSelectedSourceId: null

    // ---------------- Monitor brightness (DDC/CI + brightnessctl) ----------------
    // Lifted up here rather than living on each screen's own
    // ScreenSettings instance - brightness is a property of the
    // physical monitor, not of whichever screen's dashboard happens to
    // be open, and a single shared detection also means ddcutil/
    // brightnessctl only ever get probed once instead of once per
    // connected screen. ScreenSettings.qml reaches these through its own
    // dashboardRoot property (see how it's instantiated below).
    //
    // name -> I2C bus number, ddcutil-controllable monitors only (see
    // ddcDetectProcess below for how this is built).
    property var ddcBusNumbers: ({})
    // True if `brightnessctl -m` found a usable backlight device at all
    // - laptops report one for their internal panel, ddcutil can't see
    // it (no DDC/CI over eDP), desktops with no backlight device get
    // nothing here and brightnessctl is never used.
    property bool hasBrightnessctlDevice: false
    // 0-100, last known value per monitor name, from whichever of the
    // two backends actually controls it.
    property var liveBrightness: ({})
    // Staged edits (Screen Settings' per-card sliders stage here until
    // Apply; Bar.qml's BrightnessControl also writes here immediately
    // so any open Screen Settings card reflects the live drag too,
    // before its own debounced apply fires).
    property var pendingBrightness: ({})

    // Whether the two detect Processes below have completed at least
    // once since the last detectBrightnessControllers() call - false
    // for the (usually brief, but real - ddcutil talks to actual I2C
    // hardware) window right after startup/a re-detect, during which
    // supportsBrightness() can't yet be trusted either way. Bar.qml's
    // BrightnessControl shows a "detecting..." placeholder instead of
    // hiding itself while this is false, rather than assuming
    // unsupported and popping in later.
    property bool ddcDetectDone: false
    property bool brightnessctlDetectDone: false
    readonly property bool brightnessDetectionDone: root.ddcDetectDone && root.brightnessctlDetectDone

    // eDP is the standard Linux/Wayland output name for a laptop's own
    // built-in panel - the one case ddcutil structurally can't reach,
    // which is exactly the case brightnessctl exists for.
    function controlsViaBrightnessctl(name) {
        return root.hasBrightnessctlDevice && /^eDP/i.test(name)
    }

    function brightnessFor(name) {
        if (root.pendingBrightness[name] !== undefined) return root.pendingBrightness[name]
        if (root.liveBrightness[name] !== undefined) return root.liveBrightness[name]
        return 50
    }

    function supportsBrightness(name) {
        return root.ddcBusNumbers[name] !== undefined || root.controlsViaBrightnessctl(name)
    }

    function setPendingBrightness(name, value) {
        const updated = Object.assign({}, root.pendingBrightness)
        updated[name] = value
        root.pendingBrightness = updated
    }

    function detectBrightnessControllers() {
        root.ddcDetectDone = false
        root.brightnessctlDetectDone = false
        ddcDetectProcess.running = false
        ddcDetectProcess.running = true
        brightnessctlDetectProcess.running = false
        brightnessctlDetectProcess.running = true
    }

    // Queried one at a time, not all in parallel - ddcutil talks to real
    // I2C hardware, and overlapping queries against the same/adjacent
    // buses are a common source of ddcutil timeouts/errors.
    property var brightnessQueryQueue: []

    function queueBrightnessQueries() {
        const names = new Set(Object.keys(root.ddcBusNumbers))
        if (root.hasBrightnessctlDevice) {
            for (const s of Quickshell.screens) {
                if (/^eDP/i.test(s.name)) names.add(s.name)
            }
        }
        root.brightnessQueryQueue = Array.from(names)
        root.runNextBrightnessQuery()
    }

    function runNextBrightnessQuery() {
        if (root.brightnessQueryQueue.length === 0) return
        const name = root.brightnessQueryQueue[0]
        if (root.controlsViaBrightnessctl(name)) {
            brightnessctlGetProcess.currentName = name
            brightnessctlGetProcess.running = false
            brightnessctlGetProcess.running = true
        } else {
            ddcGetProcess.currentName = name
            ddcGetProcess.command = ["ddcutil", "--bus", String(root.ddcBusNumbers[name]), "getvcp", "10", "--brief"]
            ddcGetProcess.running = false
            ddcGetProcess.running = true
        }
    }

    // Flushes pendingBrightness for just the given monitor names (Bar.qml's
    // debounced widget calls this with a single name; Screen Settings'
    // own Apply flushes every staged monitor at once via applyBrightness()
    // below).
    function applyBrightnessFor(names) {
        const ddcCommands = []
        const updatedLive = Object.assign({}, root.liveBrightness)
        const updatedPending = Object.assign({}, root.pendingBrightness)

        for (const name of names) {
            const value = root.pendingBrightness[name]
            if (value === undefined) continue

            if (root.controlsViaBrightnessctl(name)) {
                brightnessctlSetProcess.command = ["brightnessctl", "set", value + "%"]
                brightnessctlSetProcess.running = false
                brightnessctlSetProcess.running = true
            } else if (root.ddcBusNumbers[name] !== undefined) {
                // --noverify skips ddcutil's default post-write readback
                // that confirms the value actually took - roughly halves
                // the round-trip, and we don't need it since the UI
                // already optimistically assumes success (liveBrightness
                // is updated below regardless).
                ddcCommands.push(`ddcutil --bus ${root.ddcBusNumbers[name]} --noverify setvcp 10 ${value}`)
            }

            updatedLive[name] = value
            delete updatedPending[name]
        }

        root.liveBrightness = updatedLive
        root.pendingBrightness = updatedPending

        if (ddcCommands.length > 0) {
            ddcApplyProcess.command = ["sh", "-c", ddcCommands.join(" ; ")]
            ddcApplyProcess.running = false
            ddcApplyProcess.running = true
        }
    }

    // Screen Settings' own Apply button - flushes every monitor currently
    // staged in pendingBrightness at once.
    function applyBrightness() {
        root.applyBrightnessFor(Object.keys(root.pendingBrightness))
    }

    Process {
        id: ddcDetectProcess
        command: ["ddcutil", "detect"]

        // Not set from the stdout/stderr collectors below - if ddcutil
        // isn't installed at all, the process fails to even start and
        // Quickshell never touches either stdio parser at all (confirmed
        // in Quickshell's own Process::onErrorOccurred, which only emits
        // runningChanged() for QProcess::FailedToStart), which left this
        // permanently stuck undetected the first time this shipped.
        // running transitions back to false on every path - normal exit,
        // manual stop, or failed-to-start - so this is the one signal
        // that's actually guaranteed to fire.
        onRunningChanged: if (!running) root.ddcDetectDone = true

        stdout: StdioCollector {
            onStreamFinished: {
                // Each block (one per detected display) contains both an
                // "I2C bus: /dev/i2c-N" line and a "DRM connector:"/
                // "DRM_connector:" line (separator varies by ddcutil
                // version, confirmed live) - captures the bus number
                // when seen, then attaches it to the connector name once
                // that line follows. "Invalid display" blocks (a monitor
                // that doesn't support DDC/CI at all, e.g. a TV) are
                // skipped entirely rather than mapped, since ddcutil can
                // never actually talk to them anyway.
                const map = {}
                let currentBus = null
                let skipBlock = false
                for (const line of text.split("\n")) {
                    if (/^Invalid display/.test(line)) {
                        currentBus = null
                        skipBlock = true
                        continue
                    }
                    if (/^Display \d+/.test(line)) {
                        currentBus = null
                        skipBlock = false
                        continue
                    }
                    if (skipBlock) continue

                    const busMatch = line.match(/I2C bus:\s*\/dev\/i2c-(\d+)/)
                    if (busMatch) {
                        currentBus = parseInt(busMatch[1], 10)
                        continue
                    }
                    const connectorMatch = line.match(/DRM[ _]connector:\s*card\d+-(.+)$/)
                    if (connectorMatch && currentBus !== null) {
                        map[connectorMatch[1].trim()] = currentBus
                    }
                }
                root.ddcBusNumbers = map
                root.queueBrightnessQueries()
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Dashboard: ddcutil detect error(s) (brightness sliders may not work):\n" + text)
                }
            }
        }
    }

    Process {
        id: ddcGetProcess
        property string currentName: ""
        command: ["true"]

        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/VCP\s+10\s+C\s+(\d+)/)
                if (match) {
                    const updated = Object.assign({}, root.liveBrightness)
                    updated[ddcGetProcess.currentName] = Math.max(0, Math.min(100, parseInt(match[1], 10)))
                    root.liveBrightness = updated
                }
                root.brightnessQueryQueue = root.brightnessQueryQueue.slice(1)
                root.runNextBrightnessQuery()
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Dashboard: ddcutil getvcp error for " + ddcGetProcess.currentName + ":\n" + text)
                }
            }
        }
    }

    Process {
        id: ddcApplyProcess
        command: ["true"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("Dashboard: ddcutil setvcp reply:\n" + text)
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Dashboard: ddcutil setvcp error(s):\n" + text)
                }
            }
        }
    }

    // `brightnessctl -m` machine-readable output is
    // "<device>,<class>,<current>,<percent>%,<max>" - the percent field
    // is already computed for us, no raw/max division needed the way
    // ddcutil's getvcp reply requires.
    Process {
        id: brightnessctlDetectProcess
        command: ["brightnessctl", "-m"]

        // See ddcDetectProcess's identical onRunningChanged above - the
        // only signal actually guaranteed to fire if brightnessctl isn't
        // installed at all.
        onRunningChanged: if (!running) root.brightnessctlDetectDone = true

        stdout: StdioCollector {
            onStreamFinished: {
                root.hasBrightnessctlDevice = /^[^,]+,backlight,/m.test(text)
                root.queueBrightnessQueries()
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Dashboard: brightnessctl detect error(s) (laptop panel brightness may not work):\n" + text)
                }
            }
        }
    }

    Process {
        id: brightnessctlGetProcess
        property string currentName: ""
        command: ["brightnessctl", "-m"]

        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/,backlight,\d+,(\d+)%,/)
                if (match) {
                    const updated = Object.assign({}, root.liveBrightness)
                    updated[brightnessctlGetProcess.currentName] = Math.max(0, Math.min(100, parseInt(match[1], 10)))
                    root.liveBrightness = updated
                }
                root.brightnessQueryQueue = root.brightnessQueryQueue.slice(1)
                root.runNextBrightnessQuery()
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Dashboard: brightnessctl get error:\n" + text)
                }
            }
        }
    }

    Process {
        id: brightnessctlSetProcess
        command: ["true"]

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Dashboard: brightnessctl set error(s):\n" + text)
                }
            }
        }
    }

    function close() {
        open = false
        screen = null
    }

    function toggle(screen_) {
        if (open && screen === screen_) {
            close()
        } else {
            open = true
            screen = screen_
        }
    }

    // Probes ddcutil/brightnessctl once, eagerly, rather than waiting
    // for a Screen Settings panel to open - Bar.qml's BrightnessControl
    // widget needs a live brightness reading from the moment the bar
    // itself appears.
    Component.onCompleted: root.detectBrightnessControllers()

    IpcHandler {
        target: "dashboard"

        // A keybind/IPC call carries no click position, so there's no
        // "which screen was clicked" the way there is from Bar.qml's
        // clock button - this just always targets the primary screen.
        function toggle(): void { root.toggle(Quickshell.screens[0]) }
        function show(): void {
            root.open = true
            root.screen = Quickshell.screens[0]
        }
        function hide(): void { root.close() }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dashWindow

            property var modelData
            screen: modelData

            // Screen-relative base size. ~0.42/0.43 reproduces the 800x460
            // this was tuned at on a 1920x1080 screen, just no longer fixed.
            property real dashWidth: modelData.width * 0.42
            property real columnHeight: modelData.height * 0.43

            // Everything sized in plain pixels below (fonts, icons,
            // borders, spacing) is written at its 800px-reference value
            // and multiplied by this. Clamped so a tiny or huge monitor
            // doesn't make text illegibly small or comically large.
            property real uiScale: Math.max(0.6, Math.min(1.8, dashWidth / 800))

            // Mutually-exclusive sub-panels (audio/bluetooth settings):
            // "" or the name of whichever one is active. Each
            // panel below binds active: activeSettingsPanel === "<name>",
            // so switching names closes the current one and opens the new
            // one - but not simultaneously. Since SettingsPanel.qml only
            // flips reallyVisible/hides once its own close animation
            // finishes (see its closed() signal), toggleSettingsPanel()
            // holds the requested target in pendingSettingsPanel until
            // then instead of assigning activeSettingsPanel directly.
            property string activeSettingsPanel: ""
            property string pendingSettingsPanel: ""

            function toggleSettingsPanel(name) {
                if (activeSettingsPanel === name) {
                    activeSettingsPanel = ""
                    pendingSettingsPanel = ""
                } else if (activeSettingsPanel === "") {
                    activeSettingsPanel = name
                } else {
                    pendingSettingsPanel = name
                    activeSettingsPanel = ""
                }
            }

            function onSettingsPanelClosed() {
                if (pendingSettingsPanel !== "") {
                    activeSettingsPanel = pendingSettingsPanel
                    pendingSettingsPanel = ""
                }
            }

            visible: root.open && root.screen === modelData

            WlrLayershell.namespace: "dashboard"
            WlrLayershell.layer: WlrLayer.Overlay

            exclusiveZone: 0

            // Anchoring only the top edge (no left/right) lets the
            // compositor center the window on that axis natively, instead
            // of us computing screen-width math.
            anchors {
                top: true
            }

            margins {
                // Bar's own top margin (10) + height (48) - border width
                // (2), so this window's top edge lands on the bar's bottom
                // border instead of leaving a gap or a seam.
                top: 4
            }

            implicitWidth: dashWidth
            implicitHeight: Math.max(dashContent.height, 1)

            color: "transparent"

            Rectangle {
                id: dashBox

                anchors.horizontalCenter: parent.horizontalCenter

                width: 0
                height: 4

                // Fully opaque - each section below sits on top of this in
                // its own DashCard.
                color: Config.fillcolor

                states: [

                    State {
                        name: "horizontal"

                        PropertyChanges {
                            target: dashBox

                            width: dashWidth
                            height: 2
                        }
                    },

                    State {
                        name: "open"

                        PropertyChanges {
                            target: dashBox

                            width: dashWidth
                            height: Math.max(dashContent.height, 1)
                        }
                    }

                ]

                transitions: [

                    Transition {

                        NumberAnimation {

                            properties: "width,height"

                            duration: 300

                            easing.type: Easing.OutCubic

                        }

                    }

                ]

                Item {
                    id: contentMask

                    anchors.fill: parent
                    clip: true

                    Row {
                        id: dashContent

                        width: dashWidth

                        topPadding: Config.scaled(16, dashWindow.uiScale)
                        bottomPadding: Config.scaled(16, dashWindow.uiScale)
                        leftPadding: Config.scaled(16, dashWindow.uiScale)
                        rightPadding: Config.scaled(16, dashWindow.uiScale)
                        spacing: Config.scaled(16, dashWindow.uiScale)

                        // Space actually left for the 3 columns once outer
                        // padding and the 2 inter-column gaps are removed.
                        // Column width fractions below sum to 1.0 against
                        // this, not against the raw dashWidth.
                        readonly property real availableWidth: width - leftPadding - rightPadding - 2 * spacing

                        // ---------------- LEFT COLUMN ----------------
                        Column {
                            id: leftColumn

                            width: dashContent.availableWidth * 0.35
                            height: columnHeight
                            spacing: Config.scaled(10, dashWindow.uiScale)

                            // top left: large numerical clock
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.2

                                Clock {
                                    anchors.centerIn: parent
                                    font.family: Config.fontfamily
                                    font.pixelSize: parent.height * 0.75
                                    color: Config.fgcolor
                                }
                            }

                            // middle left: current weather (wttr.in, no API
                            // key needed - refreshes every 15 min). Weather
                            // itself handles its own click-to-toggle fade
                            // between current conditions and a 3-day
                            // forecast, no separate panel involved.
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.3

                                Weather {
                                    anchors.fill: parent
                                    uiScale: dashWindow.uiScale
                                }
                            }

                            // bottom left: calendar
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - 2 * parent.spacing) * 0.5

                                Calendar {
                                    anchors.fill: parent
                                    anchors.margins: Config.scaled(8, dashWindow.uiScale)
                                    anchors.topMargin: Config.scaled(12, dashWindow.uiScale)
                                    uiScale: dashWindow.uiScale
                                    dashboardOpen: root.open
                                }
                            }
                        }

                        // --------------- CENTER COLUMN ----------------
                        Column {
                            id: centerColumn

                            width: dashContent.availableWidth * 0.30
                            height: columnHeight
                            spacing: Config.scaled(10, dashWindow.uiScale)
                            // Square, but never taller than its share of
                            // the column's height budget.

                            // top center: hostname/user greeting
                            DashCard {
                                id: greetingtext
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: Config.scaled(32, dashWindow.uiScale)

                                property string hostname: ""

                                // One-shot, not periodic - the machine's
                                // hostname doesn't change at runtime.
                                Process {
                                    running: true
                                    command: ["hostnamectl", "hostname"]

                                    stdout: SplitParser {
                                        onRead: (line) => {
                                            if (line.trim().length > 0) {
                                                greetingtext.hostname = line.trim()
                                            }
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent

                                    text: Quickshell.env("USER") + "@" + (greetingtext.hostname.length > 0 ? greetingtext.hostname : "...")

                                    color: Config.fgcolor
                                    font.family: Config.fontfamily
                                    font.pixelSize: Config.scaled(16, dashWindow.uiScale)

                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Rectangle {
                                id: avatarbox
                                width: parent.width
                                height: parent.width
                                color: "transparent"

                                DashCard {
                                    uiScale: dashWindow.uiScale
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: parent.height

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 2

                                        source: "file://" + Quickshell.env("HOME") + "/.face"
                                        fillMode: Image.PreserveAspectCrop
                                        clip: true
                                    }
                                }
                            }

                            // Empty filler - absorbs whatever height the
                            // fixed-size siblings above/below don't use.
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: columnHeight - greetingtext.height - avatarbox.height - powerrow.height - systemicons.height - parent.spacing * 4
                            }

                            Rectangle {
                                id: powerrow
                                width: parent.width
                                height: Config.scaled(48, dashWindow.uiScale)
                                color: "transparent"

                                Row {
                                    anchors.centerIn: parent
                                    spacing: powerrow.width / 11

                                    DashCard {
                                        uiScale: dashWindow.uiScale
                                        width: powerrow.width / 2.2
                                        height: powerrow.height
                                        color: mouseAreaPower.containsMouse ? Config.fgcolorhover : Config.fillcolor

                                        IconImage {
                                            id: powerIcon
                                            anchors.centerIn: parent
                                            implicitSize: Config.scaled(36, dashWindow.uiScale)
                                            source: Quickshell.iconPath("system-shutdown-symbolic")
                                        }

                                        ColorOverlay {
                                            anchors.fill: powerIcon
                                            source: powerIcon
                                            color: Config.fgcolor
                                        }

                                        MouseArea {
                                            id: mouseAreaPower
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                root.close()
                                                if (root.powerMenu) {
                                                    root.powerMenu.open = true
                                                }
                                            }
                                        }
                                    }

                                    DashCard {
                                        uiScale: dashWindow.uiScale
                                        width: powerrow.width / 2.2
                                        height: powerrow.height
                                        color: mouseAreaLock.containsMouse ? Config.fgcolorhover : Config.fillcolor

                                        IconImage {
                                            id: lockIcon
                                            anchors.centerIn: parent
                                            implicitSize: Config.scaled(36, dashWindow.uiScale)
                                            source: Quickshell.iconPath("system-lock-screen-symbolic")
                                        }

                                        ColorOverlay {
                                            anchors.fill: lockIcon
                                            source: lockIcon
                                            color: Config.fgcolor
                                        }

                                        MouseArea {
                                            id: mouseAreaLock
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                root.close()
                                                if (root.lockScreen) {
                                                    root.lockScreen.locked = true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Item {}

                            Rectangle {
                                id: systemicons
                                width: parent.width
                                height: Config.scaled(32, dashWindow.uiScale)
                                color: "transparent"

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Config.scaled(6, dashWindow.uiScale)

                                    Repeater {
                                        model: ["audio-volume-high-symbolic", "network-wired-symbolic", "network-bluetooth", "battery-100-symbolic", "video-display-symbolic", ""]

                                        delegate: DashCard {
                                            required property string modelData
                                            required property int index
                                            uiScale: dashWindow.uiScale

                                            width: systemicons.height
                                            height: systemicons.height
                                            color: iconMouseArea.containsMouse ? Config.fgcolorhover : Config.fillcolor

                                            IconImage {
                                                id: systemIcon
                                                anchors.centerIn: parent
                                                implicitSize: Config.scaled(20, dashWindow.uiScale)
                                                visible: modelData.length > 0
                                                source: modelData.length > 0 ? Quickshell.iconPath(modelData) : ""
                                            }

                                            ColorOverlay {
                                                anchors.fill: systemIcon
                                                source: systemIcon
                                                visible: systemIcon.visible
                                                color: Config.fgcolor
                                            }

                                            // The last icon is reserved for the same
                                            // settings-button treatment later, but it
                                            // hover-highlights already like the rest.
                                            MouseArea {
                                                id: iconMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: {
                                                    if (index === 0) {
                                                        dashWindow.toggleSettingsPanel("audio")
                                                    } else if (index === 1) {
                                                        dashWindow.toggleSettingsPanel("network")
                                                    } else if (index === 2) {
                                                        dashWindow.toggleSettingsPanel("bluetooth")
                                                    } else if (index === 3) {
                                                        dashWindow.toggleSettingsPanel("battery")
                                                    } else if (index === 4) {
                                                        dashWindow.toggleSettingsPanel("screen")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ---------------- RIGHT COLUMN ----------------
                        // Now playing (2/3) + an empty 1/3 reserved for
                        // future content.
                        Column {
                            id: rightColumn

                            width: dashContent.availableWidth * 0.35
                            height: columnHeight
                            spacing: Config.scaled(10, dashWindow.uiScale)

                            // Now playing. Loaded lazily by path (not
                            // instantiated directly) so a wrong MPRIS API
                            // guess only blanks this card instead of
                            // breaking the whole shell - verify this one
                            // live.
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - parent.spacing) * (2 / 3)

                                Loader {
                                    id: nowPlayingLoader
                                    anchors.fill: parent
                                    anchors.margins: Config.scaled(12, dashWindow.uiScale)

                                    source: "NowPlaying.qml"
                                }

                                // A one-time onLoaded assignment freezes at whatever
                                // uiScale happened to be when the Loader finished (which
                                // can be before dashWindow.uiScale settles to its final
                                // value) - a live Binding keeps it tracking afterwards.
                                Binding {
                                    target: nowPlayingLoader.item
                                    property: "uiScale"
                                    value: dashWindow.uiScale
                                    when: nowPlayingLoader.item !== null
                                }
                            }

                            // Audio visualizer (cava), same lazy-Loader
                            // treatment as NowPlaying above - a wrong
                            // cava/pipewire assumption only blanks this
                            // card instead of the whole shell.
                            DashCard {
                                uiScale: dashWindow.uiScale
                                width: parent.width
                                height: (columnHeight - parent.spacing) * (1 / 3)

                                Loader {
                                    id: cavaLoader
                                    anchors.fill: parent
                                    anchors.margins: Config.scaled(10, dashWindow.uiScale)

                                    source: "Cava.qml"
                                }

                                Binding {
                                    target: cavaLoader.item
                                    property: "uiScale"
                                    value: dashWindow.uiScale
                                    when: cavaLoader.item !== null
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent

                    color: "transparent"

                    border.width: Config.scaled(2, dashWindow.uiScale)
                    border.color: Config.fgcolor

                    radius: 0

                    z: 10
                }
            }

            onVisibleChanged: {
                if (visible) {
                    dashBox.width = 0
                    dashBox.height = 4

                    dashBox.state = "horizontal"
                    dashOpenTimer.start()
                } else {
                    // Snap-hide rather than let each panel play its own
                    // close animation - dashWindow itself has no closing
                    // animation, so a lingering sub-panel would look like
                    // an orphaned floating box once the dashboard above it
                    // has already vanished.
                    dashWindow.activeSettingsPanel = ""
                    dashWindow.pendingSettingsPanel = ""
                    audioSettings.forceHide()
                    networkSettings.forceHide()
                    bluetoothSettings.forceHide()
                    screenSettings.forceHide()
                }
            }

            Timer {
                id: dashOpenTimer

                // Must match the transition's duration above, so phase 1
                // (width) fully finishes before phase 2 (height) starts.
                interval: 300
                repeat: false

                onTriggered: {
                    dashBox.state = "open"
                }
            }

            // Audio settings, opened from the audio icon above. Anchored
            // directly below dashBox's own border (same width, same
            // screen) so it reads as an extension of the dashboard rather
            // than an unrelated popup.
            AudioSettings {
                id: audioSettings

                screen: dashWindow.screen
                panelWidth: dashWidth
                uiScale: dashWindow.uiScale
                anchorTop: dashWindow.margins.top + dashWindow.height + Config.scaled(8, dashWindow.uiScale)
                active: dashWindow.activeSettingsPanel === "audio"
                onPanelClosed: dashWindow.onSettingsPanelClosed()
                selectedSinkId: root.audioSelectedSinkId
                selectedSourceId: root.audioSelectedSourceId
                onSinkSelected: (id) => root.audioSelectedSinkId = id
                onSourceSelected: (id) => root.audioSelectedSourceId = id
            }

            // Network settings, opened from the network icon above. Same
            // width as AudioSettings.
            NetworkSettings {
                id: networkSettings

                screen: dashWindow.screen
                panelWidth: dashWidth
                uiScale: dashWindow.uiScale
                anchorTop: dashWindow.margins.top + dashWindow.height + Config.scaled(8, dashWindow.uiScale)
                active: dashWindow.activeSettingsPanel === "network"
                onPanelClosed: dashWindow.onSettingsPanelClosed()
            }

            // Bluetooth settings, opened from the bluetooth icon above.
            // Same width as AudioSettings.
            BluetoothSettings {
                id: bluetoothSettings

                screen: dashWindow.screen
                panelWidth: dashWidth
                uiScale: dashWindow.uiScale
                anchorTop: dashWindow.margins.top + dashWindow.height + Config.scaled(8, dashWindow.uiScale)
                active: dashWindow.activeSettingsPanel === "bluetooth"
                onPanelClosed: dashWindow.onSettingsPanelClosed()
            }

            // Screen settings, opened from the screen icon above. Same
            // width as Audio/Bluetooth. identifying/primaryMonitor are
            // mirrored up to root (see its own property comment) since
            // this ScreenSettings instance is local to this one screen's
            // dashWindow, but both need to affect every screen.
            ScreenSettings {
                id: screenSettings

                screen: dashWindow.screen
                panelWidth: dashWidth
                uiScale: dashWindow.uiScale
                anchorTop: dashWindow.margins.top + dashWindow.height + Config.scaled(8, dashWindow.uiScale)
                active: dashWindow.activeSettingsPanel === "screen"
                primaryMonitor: root.primaryMonitor
                dashboardRoot: root
                onPanelClosed: dashWindow.onSettingsPanelClosed()
                onIdentifyingChanged: root.identifying = screenSettings.identifying
                onPrimarySelected: (name) => root.primaryMonitor = name
            }

            // Battery levels, opened from the battery icon above (index
            // 3 in systemicons' Repeater below - reserved for this
            // ever since that row was first laid out). Same width as
            // Audio/Bluetooth/Screen.
            BatterySettings {
                id: batterySettings

                screen: dashWindow.screen
                panelWidth: dashWidth
                uiScale: dashWindow.uiScale
                anchorTop: dashWindow.margins.top + dashWindow.height + Config.scaled(8, dashWindow.uiScale)
                active: dashWindow.activeSettingsPanel === "battery"
                onPanelClosed: dashWindow.onSettingsPanelClosed()
            }

            // Invisible, full-screen click catcher that closes the
            // dashboard on an outside click - including a click on another
            // window, not just bare desktop. Per the wlr-layer-shell spec,
            // Background/Bottom render below regular windows while
            // Top/Overlay render above them, so this has to sit on
            // WlrLayer.Top (same as Bar.qml's default) to actually see
            // clicks over a normal window - Bottom would only ever catch
            // clicks on bare desktop. It still sits below this window's own
            // WlrLayer.Overlay, so the dashboard itself is unaffected.
            PanelWindow {
                screen: modelData
                visible: root.open && root.screen === modelData

                WlrLayershell.namespace: "dashboard-catcher"
                WlrLayershell.layer: WlrLayer.Top

                exclusiveZone: -1

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                color: "transparent"

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }
        }
    }

    // Identify overlay for ScreenSettings' Identify button - a name
    // label on every screen at once, for 3 seconds. A genuinely separate
    // per-screen Variants (not nested inside the dashWindow one above),
    // driven by the shared root.identifying, so it isn't limited to
    // whichever single screen's dashWindow the user actually clicked
    // Identify from. Can only show on a screen this compositor is
    // actually driving, so a monitor currently deactivated in Screen
    // settings has nothing to show this on.
    //
    // A small centered DashCard-style box rather than a fullscreen
    // window - a fullscreen layer-shell surface occupies its full input
    // region even with nothing but a MouseArea-free Text inside, so it
    // was blocking clicks to everything underneath it for the whole 3
    // seconds. No anchors at all (not even one edge) so the compositor
    // centers it on both axes, same trick Dashboard/SettingsPanel use
    // for horizontal-only centering. Click-through on top of that
    // (mask: Region {}) - even this small a window still ate clicks
    // landing inside its own bounds otherwise, same fix as
    // WorkspaceOsd.qml/VolumeOsd.qml.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            property var modelData
            screen: modelData
            visible: root.identifying

            WlrLayershell.namespace: "screen-identify"
            WlrLayershell.layer: WlrLayer.Overlay

            exclusiveZone: 0
            mask: Region {}

            implicitWidth: 320
            implicitHeight: 160

            color: "transparent"

            DashCard {
                anchors.fill: parent

                Text {
                    anchors.centerIn: parent
                    text: modelData ? modelData.name : ""
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: 48
                    font.bold: true
                }
            }
        }
    }
}
