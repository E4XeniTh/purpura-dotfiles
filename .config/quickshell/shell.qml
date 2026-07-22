//@ pragma UseQApplication
// shell.qml
import Quickshell
import "components"
import "components/lockscreen"
import "components/tray"
import "components/powermenu"
import "components/dashboard"
import "components/notifications"

Scope {
  property bool wrongPassword: false
  Bar {}
  VolumeOsd {}
  LockScreen {}
  LockScreenShortcut {}
  TrayMenu {}
  PowerMenu {}
  Dashboard {}
  Notification {}
}
