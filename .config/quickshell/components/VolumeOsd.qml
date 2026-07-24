import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "dashboard/settings"
import "../Config.js" as Config

Scope {
	id: root

	// Bind the pipewire node so its volume will be tracked
	PwObjectTracker {
		objects: [ Pipewire.defaultAudioSink ]
	}

	Connections {
		target: Pipewire.defaultAudioSink?.audio

		function onVolumeChanged() {
			root.shouldShowOsd = true;
			hideTimer.restart();
		}

		function onMutedChanged() {
			root.shouldShowOsd = true;
			hideTimer.restart();
		}
	}

	property bool shouldShowOsd: false
	// Set from the hover MouseArea below, so the OSD doesn't disappear out
	// from under the mouse while its mute button/slider are being used.
	property bool hovered: false

	Timer {
		id: hideTimer
		interval: 1000

		// Single-shot, so while hovered this just keeps re-arming itself
		// instead of actually hiding - it'll hide ~1s after hover ends.
		onTriggered: {
			if (root.hovered) {
				hideTimer.restart()
			} else {
				root.shouldShowOsd = false
			}
		}
	}

	// The OSD window will be created and destroyed based on shouldShowOsd.
	// PanelWindow.visible could be set instead of using a loader, but using
	// a loader will reduce the memory overhead when the window isn't open.
	LazyLoader {
		active: root.shouldShowOsd

		PanelWindow {
			// Since the panel's screen is unset, it will be picked by the compositor
			// when the window is created. Most compositors pick the current active monitor.

			anchors.bottom: true
			margins.bottom: screen.height / 8
			exclusiveZone: 0

			implicitWidth: 400
			implicitHeight: 84
			color: "transparent"

			// No click mask (unlike before) - the mute button and slider
			// below need real mouse input to reach them.

			Rectangle {
				anchors.fill: parent
				color: Config.fillcolor
				radius: 0
				border.width: 2
				border.color: Config.fgcolor

				MouseArea {
					anchors.fill: parent
					hoverEnabled: true
					onEntered: root.hovered = true
					onExited: root.hovered = false
				}

				// Reuses the same device card the sound settings panel
				// uses, so muting/dragging volume here behaves identically
				// - guarded by a Loader (not just visible:false) since
				// DeviceCard dereferences .device directly and
				// defaultAudioSink can briefly be null.
				Loader {
					anchors {
						fill: parent
						margins: 10
					}
					active: Pipewire.defaultAudioSink !== null

					DeviceCard {
						color: "transparent"
						border.width: 0
						device: Pipewire.defaultAudioSink
						isPrimary: true
						centered: true
					}
				}
			}
		}
	}
}
