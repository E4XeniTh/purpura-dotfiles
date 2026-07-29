import QtQuick
import "../Config.js" as Config

// Shared "digital"/segmented level bar - a row of lit/unlit blocks (a
// level-meter look) rather than a continuous slider track. Purely
// visual/read-only: VolumeControl.qml/BatteryControl.qml wrap this with
// their own MouseArea for drag/scroll since they're actual controls,
// but this component itself has no interaction.
//
// Two ways to size it: a fixed per-segment width (segmentWidth - the
// compact bar widgets in Bar.qml use this, a fixed pixel count
// regardless of container), or an explicit total width to fill
// (targetWidth >= 0 - BatterySettings.qml's "long" rows use this
// instead, since they need the bar to stretch to whatever space a
// RowLayout gives it rather than a fixed segment count of fixed-size
// blocks) - segmentWidth is derived from targetWidth instead whenever
// that's set.
Item {
    id: root

    property real uiScale: 1.0
    property real value: 0.0 // 0.0 - 1.0
    property int segmentCount: 14
    property real segmentWidth: Config.scaled(4, root.uiScale)
    property real segmentSpacing: Config.scaled(2, root.uiScale)
    property real barHeight: Config.scaled(16, root.uiScale)
    property color litColor: Config.fgcolor
    property color unlitColor: Config.fgcolordark
    property real targetWidth: -1

    readonly property real effectiveSegmentWidth: root.targetWidth >= 0
        ? Math.max(1, (root.targetWidth - (root.segmentCount - 1) * root.segmentSpacing) / root.segmentCount)
        : root.segmentWidth

    // Fixed/computed directly from the properties above rather than
    // measuring the Row/Repeater below - anchoring that Row to fill an
    // Item whose own size came *from* the Row would be a binding cycle.
    readonly property real totalWidth: root.targetWidth >= 0
        ? root.targetWidth
        : root.segmentCount * root.segmentWidth + (root.segmentCount - 1) * root.segmentSpacing
    readonly property int litSegments: Math.round(Math.max(0, Math.min(1, root.value)) * root.segmentCount)

    implicitWidth: root.totalWidth
    implicitHeight: root.barHeight

    Row {
        anchors.fill: parent
        spacing: root.segmentSpacing

        Repeater {
            model: root.segmentCount

            Rectangle {
                required property int index
                width: root.effectiveSegmentWidth
                height: root.barHeight
                radius: 0
                color: index < root.litSegments ? root.litColor : root.unlitColor
            }
        }
    }
}
