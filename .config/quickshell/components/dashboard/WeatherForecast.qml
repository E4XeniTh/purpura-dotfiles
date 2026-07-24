import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config

// Multi-day forecast (today + next 2 days), opened from Dashboard's weather
// card. Same two-phase stretch-then-drop animation as AudioSettings.qml,
// anchored directly below the dashboard.
PanelWindow {
    id: root

    property bool open: false
    property real panelWidth: 800
    property real anchorTop: 0
    property real uiScale: 1.0

    function close() { root.open = false }
    function toggle() { root.open = !root.open }

    // One entry per day: label, icon name (Quickshell.iconPath-ready), and
    // pre-formatted temp/humidity/precip/wind strings.
    property var forecastDays: []

    // Same coarse keyword match as Weather.qml's iconForCondition - kept
    // in sync manually since there's no shared module to pull it from
    // without turning it into a bigger refactor than this needs.
    function iconForCondition(condition) {
        const c = condition.toLowerCase()
        if (c.includes("thunder")) return "weather-storm-symbolic"
        if (c.includes("snow") || c.includes("sleet") || c.includes("ice")) return "weather-snow-symbolic"
        if (c.includes("rain") || c.includes("drizzle") || c.includes("shower")) return "weather-showers-symbolic"
        if (c.includes("fog") || c.includes("mist") || c.includes("haze")) return "weather-fog-symbolic"
        if (c.includes("overcast")) return "weather-overcast-symbolic"
        if (c.includes("cloud")) return "weather-few-clouds-symbolic"
        return "weather-clear-symbolic"
    }

    // Representative hourly slot for a future day - noon, falling back to
    // the array's middle entry if wttr.in ever changes its time-of-day set.
    function middayOf(day) {
        const hourly = day.hourly || []
        return hourly.find(h => h.time === "1200") || hourly[Math.floor(hourly.length / 2)] || {}
    }

    function buildDays(parsed) {
        const days = []

        const current = (parsed.current_condition || [])[0]
        if (current) {
            days.push({
                label: "Today",
                iconName: iconForCondition((current.weatherDesc && current.weatherDesc[0] && current.weatherDesc[0].value) || ""),
                tempText: current.temp_C + "°C",
                humidityText: current.humidity + "%",
                precipText: current.precipMM + "mm",
                windText: current.windspeedKmph + "km/h"
            })
        }

        // weather[0] is today's own day-level summary (current_condition
        // above already covers "today" live) - only the following days are
        // new information here.
        const weather = parsed.weather || []
        for (let i = 1; i < weather.length; i++) {
            const day = weather[i]
            const mid = middayOf(day)
            days.push({
                label: Qt.formatDate(new Date(day.date), "ddd"),
                iconName: iconForCondition((mid.weatherDesc && mid.weatherDesc[0] && mid.weatherDesc[0].value) || ""),
                tempText: (mid.tempC !== undefined ? mid.tempC : day.avgtempC) + "°C",
                humidityText: (mid.humidity !== undefined ? mid.humidity : "?") + "%",
                precipText: (mid.precipMM !== undefined ? mid.precipMM : "?") + "mm",
                windText: (mid.windspeedKmph !== undefined ? mid.windspeedKmph : "?") + "km/h"
            })
        }

        forecastDays = days
    }

    Process {
        id: forecastProcess

        command: ["curl", "-s", "-A", "curl", "https://wttr.in/?format=j1"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.buildDays(JSON.parse(text))
                } catch (e) {
                    root.forecastDays = []
                }
            }
        }
    }

    // Fetched fresh every time the panel opens rather than on a timer -
    // this is a rarely-opened detail view, not the always-visible
    // Weather.qml card.
    onOpenChanged: {
        if (open) {
            forecastProcess.running = false
            forecastProcess.running = true
        }
    }

    visible: root.open

    WlrLayershell.namespace: "weatherForecast"
    WlrLayershell.layer: WlrLayer.Overlay

    exclusiveZone: 0

    anchors {
        top: true
    }

    margins {
        top: root.anchorTop
    }

    implicitWidth: root.panelWidth
    implicitHeight: Math.max(forecastContent.height, 1)

    color: "transparent"

    Rectangle {
        id: forecastBox

        anchors.horizontalCenter: parent.horizontalCenter

        width: 0
        height: 4

        color: Config.fillcolor

        states: [

            State {
                name: "horizontal"

                PropertyChanges {
                    target: forecastBox

                    width: root.panelWidth
                    height: 2
                }
            },

            State {
                name: "open"

                PropertyChanges {
                    target: forecastBox

                    width: root.panelWidth
                    height: Math.max(forecastContent.height, 1)
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
            anchors.fill: parent
            clip: true

            Row {
                id: forecastContent

                width: root.panelWidth

                topPadding: Config.scaled(16, root.uiScale)
                bottomPadding: Config.scaled(16, root.uiScale)
                leftPadding: Config.scaled(16, root.uiScale)
                rightPadding: Config.scaled(16, root.uiScale)
                spacing: Config.scaled(16, root.uiScale)

                readonly property real dayColumnWidth: root.forecastDays.length > 0
                    ? (width - leftPadding - rightPadding - spacing * (root.forecastDays.length - 1)) / root.forecastDays.length
                    : 0

                Repeater {
                    model: root.forecastDays

                    delegate: Column {
                        id: dayColumn

                        required property var modelData

                        width: forecastContent.dayColumnWidth
                        spacing: Config.scaled(6, root.uiScale)

                        Text {
                            width: parent.width
                            text: dayColumn.modelData.label
                            horizontalAlignment: Text.AlignHCenter
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(13, root.uiScale)
                            font.bold: true
                        }

                        // The "weather" field itself is icon-only, no
                        // condition text - temp/humidity/precip/wind below
                        // are still plain numbers, their units already
                        // disambiguate them without needing labels.
                        Item {
                            width: parent.width
                            height: Config.scaled(48, root.uiScale)

                            IconImage {
                                id: dayIcon
                                anchors.centerIn: parent
                                implicitSize: Config.scaled(40, root.uiScale)
                                source: Quickshell.iconPath(dayColumn.modelData.iconName)
                            }

                            ColorOverlay {
                                anchors.fill: dayIcon
                                source: dayIcon
                                color: Config.fgcolor
                            }
                        }

                        Text {
                            width: parent.width
                            text: dayColumn.modelData.tempText
                            horizontalAlignment: Text.AlignHCenter
                            color: Config.fgcolor
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(14, root.uiScale)
                        }

                        Text {
                            width: parent.width
                            text: dayColumn.modelData.humidityText
                            horizontalAlignment: Text.AlignHCenter
                            color: Config.fgcolordark
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, root.uiScale)
                        }

                        Text {
                            width: parent.width
                            text: dayColumn.modelData.precipText
                            horizontalAlignment: Text.AlignHCenter
                            color: Config.fgcolordark
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, root.uiScale)
                        }

                        Text {
                            width: parent.width
                            text: dayColumn.modelData.windText
                            horizontalAlignment: Text.AlignHCenter
                            color: Config.fgcolordark
                            font.family: Config.fontfamily
                            font.pixelSize: Config.scaled(11, root.uiScale)
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent

            color: "transparent"

            border.width: Config.scaled(2, root.uiScale)
            border.color: Config.fgcolor

            radius: 0

            z: 10
        }
    }

    onVisibleChanged: {
        if (visible) {
            forecastBox.width = 0
            forecastBox.height = 4

            forecastBox.state = "horizontal"
            forecastOpenTimer.start()
        }
    }

    Timer {
        id: forecastOpenTimer

        // Must match the transition's duration above, so phase 1 (width)
        // fully finishes before phase 2 (height) starts.
        interval: 300
        repeat: false

        onTriggered: {
            forecastBox.state = "open"
        }
    }
}
