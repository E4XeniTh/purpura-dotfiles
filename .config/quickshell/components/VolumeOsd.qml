import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects
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

	// Fed in from shell.qml too - a cross-reference to the other OSD's
	// own Scope instance, so each can tell whether the other is
	// currently shown (see otherOsdShown below) and shift itself out of
	// dead center instead of the two overlapping directly. A plain id
	// reference doesn't work here - VolumeOsd.qml/BrightnessOsd.qml are
	// separate top-level Scopes (siblings in shell.qml), and QML ids
	// aren't visible outside the component they're declared in.
	property var brightnessOsd: null
	readonly property bool otherOsdShown: !!(root.brightnessOsd && root.brightnessOsd.shouldShowOsd)

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
			mask: Region {}
			// Centered by default (no left/right anchor at all) - only
			// shifted left-of-center when BrightnessOsd is ALSO up right
			// now, so the pair sits side by side (volume left,
			// brightness right - same left-to-right order Bar.qml's own
			// widgets use) instead of directly on top of each other.
			// Symmetric with BrightnessOsd.qml's own mirror-image
			// version of this same margin.
			anchors.left: root.otherOsdShown
			margins.left: root.otherOsdShown ? Math.max(0, screen.width / 2 - implicitWidth - 10) : 0
			exclusiveZone: 0

			implicitWidth: 500
			implicitHeight: 84
			color: "transparent"

			// Purely a display now - no click mask needed since nothing
			// inside accepts mouse input for muting/dragging anymore (see
			// the icon/DigitalBar/percentage row below).

			Rectangle {
				anchors.fill: parent
				color: Config.fillcolor
				radius: 0
				border.width: 2
				border.color: Config.fgcolor

				// Read-only - guarded by a Loader (not just visible:false)
				// since the row below dereferences activeSink.audio
				// directly and activeSink can briefly be null.
				Loader {
					anchors {
						fill: parent
						margins: 20
					}
					active: root.activeSink !== null

					RowLayout {
						id: volumeRow
						anchors.fill: parent
						spacing: 16

						readonly property bool muted: root.activeSink && root.activeSink.audio ? root.activeSink.audio.muted : false
						readonly property real volume: root.activeSink && root.activeSink.audio ? root.activeSink.audio.volume : 0

						Item {
							Layout.preferredWidth: 48
							Layout.preferredHeight: 48

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
								uiScale: 1.5
								targetWidth: parent.width
								segmentCount: 30
								value: volumeRow.volume
								// Same red-on-mute treatment as VolumeControl.qml/DeviceSlider.qml.
								litColor: volumeRow.muted ? Config.fgcolorred : Config.fgcolor
							}
						}

						Text {
							Layout.preferredWidth: 60
							horizontalAlignment: Text.AlignHCenter
							text: Math.round(volumeRow.volume * 100) + "%"
							color: Config.fgcolor
							font.family: Config.fontfamily
							font.pixelSize: 24
							font.bold: true
						}
					}
				}
			}
		}
	}
}
