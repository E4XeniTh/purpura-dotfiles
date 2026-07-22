//@ pragma UseQApplication
// shell.qml
import Quickshell
import "components"
import "components/dashboard"

Scope {
  PowerMenu { id: powerMenu }
  LockScreen { id: lockScreen }

  Bar {
    locked: lockScreen.locked
    powerMenuOpen: powerMenu.open
  }

  VolumeOsd {}
  Dashboard {}
  Notification {}
}
