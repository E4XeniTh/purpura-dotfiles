//@ pragma UseQApplication
// shell.qml
import Quickshell
import "components"

Scope {
  property bool wrongPassword: false
  Bar {}
  VolumeOsd {}
  LockMenu {}
  LockMenuShortcut {}
  TrayMenu {}
  PowerMenu {}
}
