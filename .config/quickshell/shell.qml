//@ pragma UseQApplication
// shell.qml
import Quickshell
import QtQuick
import "components"
import "components/lockscreen"
import "components/tray"
import "components/powermenu"
import "components/dashboard"

Scope {
  property bool wrongPassword: false
  Bar {}
  VolumeOsd {}
  LockScreen {}
  LockScreenShortcut {}
  TrayMenu {}
  PowerMenu {}
  Dashboard {}
  Loader { source: "components/ThemeLoader.qml" }
}
