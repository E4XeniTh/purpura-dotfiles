//@ pragma UseQApplication
// shell.qml
import Quickshell
import "components"
import "components/dashboard"

Scope {
  PowerMenu { id: powerMenu; dashboard: dashboard }
  LockScreen { id: lockScreen; dashboard: dashboard }
  SettingsScreen { id: settingsScreen; dashboard: dashboard }
  Dashboard {
    id: dashboard
    powerMenu: powerMenu
    lockScreen: lockScreen
    settingsScreen: settingsScreen
  }
  Notification { id: notification }
  Clipboard { id: clipboard }
  Screenshot { id: screenshot }

  Bar {
    locked: lockScreen.locked
    powerMenuOpen: powerMenu.open
    dashboard: dashboard
    notification: notification
  }

  VolumeOsd {
    id: volumeOsd
    selectedSinkId: dashboard.audioSelectedSinkId
    brightnessOsd: brightnessOsd
  }

  BrightnessOsd {
    id: brightnessOsd
    dashboard: dashboard
    volumeOsd: volumeOsd
  }

  WorkspaceOsd {}
  FullscreenHintOsd { dashboard: dashboard }
}
