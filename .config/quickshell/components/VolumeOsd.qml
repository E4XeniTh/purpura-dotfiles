import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "dashboard/settings"
import "../Config.js" as Config

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
		target: root.activeSink?.audio

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

	Timer {
		id: hideTimer
		interval: 2500
		onTriggered: root.shouldShowOsd = false
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

			implicitWidth: 500
			implicitHeight: 84
			color: "transparent"

			// Click-through, like WorkspaceOsd.qml - purely a glance
			// indicator now, not an input surface. The mute button and
			// volume slider drawn below are therefore inert here (an
			// earlier version of this file actually had this same mask,
			// removed specifically so those would work) - muting/
			// adjusting volume still works from Audio settings, just not
			// from this popup anymore.
			mask: Region {}

			Rectangle {
				anchors.fill: parent
				color: Config.fillcolor
				radius: 0
				border.width: 2
				border.color: Config.fgcolor

				// Reuses the same device card the audio settings panel
				// uses, purely for its icon/label/level display now that
				// this window is click-through - guarded by a Loader (not
				// just visible:false) since DeviceCard dereferences
				// .device directly and activeSink can briefly be null.
				Loader {
					anchors {
						fill: parent
						margins: 0
					}
					active: root.activeSink !== null

					DeviceCard {
						anchors.fill: parent
						color: "transparent"
						border.width: 0
						device: root.activeSink
						isPrimary: true
						centered: true
					}
				}
			}
		}
	}
}
