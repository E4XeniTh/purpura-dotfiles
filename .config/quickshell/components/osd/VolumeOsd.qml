import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects
import "../../Config.js" as Config
import "../common"

Scope {
	id: root

	// Fed in from shell.qml (dashboard.audioSelectedSinkId there) -
	// whichever sink was last explicitly picked in Audio settings takes
	// priority over Quickshell.Services.Pipewire's own
	// Pipewire.defaultAudioSink, which doesn't reliably emit a change
	// once quickshell is already running (confirmed live: this OSD kept
	// tracking the old device - requiring a full quickshell restart to
	// pick up the new one - while Audio settings' own device list
	// correctly followed the switch immediately, because it never
	// actually relied on defaultAudioSink for that either; see
	// AudioSettings.qml).
	property var selectedSinkId: null

	readonly property var activeSink: root.selectedSinkId !== null
		? (Pipewire.nodes.values.find(n => n.audio && !n.isStream && n.isSink && n.id === root.selectedSinkId) ?? Pipewire.defaultAudioSink)
		: Pipewire.defaultAudioSink

	// Bind the pipewire node so its volume will be tracked
	PwObjectTracker {
		objects: [ root.activeSink ]
	}

	Connections {
		// ?? null rather than bare optional chaining - target expects a
		// real QObject* or null, and assigning plain `undefined` (what
		// `?.` produces before activeSink resolves at startup) warned
		// ("Unable to assign [undefined] to QObject*").
		target: root.activeSink?.audio ?? null

		// PwNodeAudioIface's "volume" property (see Quickshell's own
		// Pipewire service) is declared with NOTIFY volumesChanged, not
		// volumeChanged - it's computed from the underlying per-channel
		// volumes array. Connections resolves a handler against the
		// real signal name, so onVolumeChanged never matched anything
		// ("no signal of the target matches the name").
		function onVolumesChanged() {
			root.shouldShowOsd = true;
			hideTimer.restart();
		}

		function onMutedChanged() {
			root.shouldShowOsd = true;
			hideTimer.restart();
		}
	}

	property bool shouldShowOsd: false

	Timer {
		id: hideTimer
		interval: 1500

		onTriggered: {
				root.shouldShowOsd = false
		}
	}

	// Its box - OsdHost.qml shows it, with the other OSDs, where Settings >
	// General > Shell > OSD says, and sets uiScale.
	property Component box: Rectangle {
		id: volumeBox

		property real uiScale: 1.0

		width: Config.scaled(500, volumeBox.uiScale)
		height: Config.scaled(84, volumeBox.uiScale)
		color: Config.fillcolor
		radius: 0
		border.width: Config.scaled(2, volumeBox.uiScale)
		border.color: Config.fgcolor

		Loader {
			anchors {
				fill: parent
				margins: Config.scaled(20, volumeBox.uiScale)
			}

			active: root.activeSink !== null

			RowLayout {
				id: volumeRow
				anchors.fill: parent
				spacing: Config.scaled(16, volumeBox.uiScale)

				readonly property bool muted: root.activeSink && root.activeSink.audio ? root.activeSink.audio.muted : false
				readonly property real volume: root.activeSink && root.activeSink.audio ? root.activeSink.audio.volume : 0

				Item {
					Layout.preferredWidth: Config.scaled(48, volumeBox.uiScale)
					Layout.preferredHeight: Config.scaled(48, volumeBox.uiScale)

					IconImage {
						id: volIcon
						anchors.fill: parent
						source: Quickshell.iconPath(volumeRow.muted || volumeRow.volume <= 0
							? "audio-volume-muted-symbolic"
							: (volumeRow.volume < 0.5 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic"))
					}

					ColorOverlay {
						anchors.fill: volIcon
						source: volIcon
						color: Config.fgcolor
					}
				}

				Item {
					Layout.fillWidth: true
					Layout.preferredHeight: bar.implicitHeight

					DigitalBar {
						id: bar
						uiScale: 1.5 * volumeBox.uiScale
						targetWidth: parent.width
						segmentCount: 30
						value: volumeRow.volume
						litColor: volumeRow.muted ? Config.fgcolorred : Config.fgcolor
						unlitColor: volumeRow.muted ? Qt.darker(Config.fgcolorred, 2.5) : Config.fgcolordark
					}
				}

				Text {
					Layout.preferredWidth: Config.scaled(60, volumeBox.uiScale)
					horizontalAlignment: Text.AlignHCenter
					text: Math.round(volumeRow.volume * 100) + "%"
					color: Config.fgcolor
					font.family: Config.fontfamily
					font.pixelSize: Config.scaled(24, volumeBox.uiScale)
					font.bold: true
				}
			}
		}
	}
}
