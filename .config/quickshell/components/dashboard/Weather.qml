import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import "../"
import "../../Config.js" as Config

Item {
    id: weatherBox

    property real uiScale: 1.0

    property string conditionText: "Loading..."
    property string tempText: ""

    // Freedesktop's weather-*-symbolic set doesn't have a one-to-one
    // entry for every wttr.in condition string, so this is a coarse
    // keyword match rather than a precise table - good enough for a
    // small bar widget icon.
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

    // "|" is a literal delimiter (not whitespace) since the condition
    // text itself contains spaces ("Partly cloudy").
    Process {
        id: weatherProcess

        command: ["curl", "-s", "-A", "curl", "https://wttr.in/?format=%C|%t"]

        stdout: SplitParser {
            onRead: (line) => {
                const trimmed = line.trim()
                if (trimmed.length === 0) {
                    return
                }
                const parts = trimmed.split("|")
                weatherBox.conditionText = parts[0]
                weatherBox.tempText = parts.length > 1 ? parts[1] : ""
            }
        }

        onExited: (exitCode) => {
            if (exitCode !== 0) {
                weatherBox.conditionText = "Weather unavailable"
                weatherBox.tempText = ""
            }
        }
    }

    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered: {
            // Force a real false->true transition. Re-assigning `true`
            // while it's already true (left over from the last run) is
            // a no-op in QML, so this is what actually makes it re-fetch
            // on every interval.
            weatherProcess.running = false
            weatherProcess.running = true
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: Config.scaled(20, weatherBox.uiScale)

        IconImage {
            id: weatherIconImage
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            implicitSize: Config.scaled(84, weatherBox.uiScale)
            source: Quickshell.iconPath(weatherBox.iconForCondition(weatherBox.conditionText))
        }

        // Symbolic icons are a plain alpha-masked shape, so ColorOverlay
        // can tint them cleanly to the theme color - this paints over
        // weatherIconImage, which is why it's declared after it.
        ColorOverlay {
            anchors.fill: weatherIconImage
            source: weatherIconImage
            color: Config.fgcolor
        }

        Column {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            width: parent.width - weatherIconImage.width - Config.scaled(12, weatherBox.uiScale)
            spacing: 0

            Text {
                width: parent.width
                text: weatherBox.conditionText
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(16, weatherBox.uiScale)
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignBottom
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: weatherBox.tempText
                color: Config.fgcolor
                font.family: Config.fontfamily
                font.pixelSize: Config.scaled(32, weatherBox.uiScale)
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
