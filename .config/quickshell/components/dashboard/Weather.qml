import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import "../"
import "../../Config.js" as Config

// Current weather, or (left-click to toggle, plain fade - no stretch
// animation) a compact 3-day forecast in the same spot. Both come from one
// wttr.in ?format=j1 fetch instead of two separate requests.
Item {
    id: weatherBox

    property real uiScale: 1.0
    property bool showingForecast: false

    property string conditionText: "Loading..."
    property string tempText: ""

    // One entry per day: label, icon name (Quickshell.iconPath-ready), and
    // pre-formatted temp/humidity/precip/wind strings.
    property var forecastDays: []

    // Freedesktop's weather-*-symbolic set doesn't have a one-to-one
    // entry for every wttr.in condition string, so this is a coarse
    // keyword match rather than a precise table - good enough for a
    // small widget icon.
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

    function formatTemp(celsius) {
        const n = Number(celsius)
        return (n >= 0 ? "+" : "") + n + "°C"
    }

    function applyWeatherJson(parsed) {
        const current = (parsed.current_condition || [])[0]
        if (current) {
            weatherBox.conditionText = (current.weatherDesc && current.weatherDesc[0] && current.weatherDesc[0].value) || ""
            weatherBox.tempText = weatherBox.formatTemp(current.temp_C)
        }

        const days = []
        // weather[0] is today's own day-level summary (current_condition
        // above already covers "today" live) - only the following days are
        // new information here.
        const weather = parsed.weather || []
        for (let i = 0; i < weather.length; i++) {
            const day = weather[i]
            const mid = weatherBox.middayOf(day)
            days.push({
                label: Qt.formatDate(new Date(day.date), "ddd"),
                iconName: weatherBox.iconForCondition((mid.weatherDesc && mid.weatherDesc[0] && mid.weatherDesc[0].value) || ""),
                tempText: weatherBox.formatTemp(mid.tempC !== undefined ? mid.tempC : day.avgtempC),
                humidityText: (mid.humidity !== undefined ? mid.humidity : "?") + "%",
                precipText: (mid.precipMM !== undefined ? mid.precipMM : "?") + "mm",
                windText: (mid.windspeedKmph !== undefined ? mid.windspeedKmph : "?") + "km/h"
            })
        }
        weatherBox.forecastDays = days
    }

    Process {
        id: weatherProcess

        command: ["curl", "-s", "-A", "curl", "https://wttr.in/?format=j1"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    weatherBox.applyWeatherJson(JSON.parse(text))
                } catch (e) {
                    weatherBox.conditionText = "Weather unavailable"
                    weatherBox.tempText = ""
                }
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

    // Current conditions.
    Item {
        id: currentView

        anchors.fill: parent
        anchors.margins: Config.scaled(20, weatherBox.uiScale)

        opacity: weatherBox.showingForecast ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

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

    // 3-day forecast - compact enough to fit the same card, icon-only per
    // day (no condition text), all text fgcolor per spec.
    Row {
        id: forecastRow

        anchors.fill: parent
        anchors.margins: Config.scaled(10, weatherBox.uiScale)
        spacing: Config.scaled(6, weatherBox.uiScale)

        opacity: weatherBox.showingForecast ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        Repeater {
            model: weatherBox.forecastDays

            delegate: Column {
                id: dayColumn

                required property var modelData

                width: (forecastRow.width - forecastRow.spacing * 2) / 3
                spacing: Config.scaled(2, weatherBox.uiScale)

                Text {
                    width: parent.width
                    text: dayColumn.modelData.label
                    horizontalAlignment: Text.AlignHCenter
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(14, weatherBox.uiScale)
                    font.bold: true
                }

                Item {
                    width: parent.width
                    height: Config.scaled(28, weatherBox.uiScale)

                    IconImage {
                        id: dayIcon
                        anchors.centerIn: parent
                        implicitSize: Config.scaled(24, weatherBox.uiScale)
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
                    font.pixelSize: Config.scaled(14, weatherBox.uiScale)
                }

                Text {
                    width: parent.width
                    text: dayColumn.modelData.precipText
                    horizontalAlignment: Text.AlignHCenter
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(12, weatherBox.uiScale)
                }

                Text {
                    width: parent.width
                    text: dayColumn.modelData.humidityText
                    horizontalAlignment: Text.AlignHCenter
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(12, weatherBox.uiScale)
                }


                Text {
                    width: parent.width
                    text: dayColumn.modelData.windText
                    horizontalAlignment: Text.AlignHCenter
                    color: Config.fgcolor
                    font.family: Config.fontfamily
                    font.pixelSize: Config.scaled(12, weatherBox.uiScale)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: weatherBox.showingForecast = !weatherBox.showingForecast
    }
}
