//@ pragma UseQApplication
// shell.qml
import Quickshell
import "components"
import "components/dashboard"

Scope {
  PowerMenu { id: powerMenu; dashboard: dashboard; lockScreen: lockScreen }
  LockScreen { id: lockScreen; dashboard: dashboard }
  SettingsScreen { id: settingsScreen; dashboard: dashboard }
  Dashboard {
    id: dashboard
    powerMenu: powerMenu
    settingsScreen: settingsScreen
  }
  Notification { id: notification; updater: updater }
  Updater { id: updater; notification: notification }
  Clipboard { id: clipboard }
  Screenshot { id: screenshot }

  Bar {
    locked: lockScreen.locked
    powerMenuOpen: powerMenu.open
    dashboard: dashboard
    notification: notification
    updater: updater
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
