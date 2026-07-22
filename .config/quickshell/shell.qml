//@ pragma UseQApplication
// shell.qml
import Quickshell
import "components"
import "components/dashboard"

Scope {
  PowerMenu { id: powerMenu }
  LockScreen { id: lockScreen }
  Dashboard {
    id: dashboard
    powerMenu: powerMenu
    lockScreen: lockScreen
  }
  Notification { id: notification }

  Bar {
    locked: lockScreen.locked
    powerMenuOpen: powerMenu.open
    dashboard: dashboard
    notification: notification
  }

  VolumeOsd {}
}
