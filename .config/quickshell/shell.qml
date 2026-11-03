//@ pragma UseQApplication
// shell.qml
import Quickshell
import "components"
import "components/dashboard"

Scope {
  // Settings > Shell's global UI Scale - every component below that sizes
  // itself gets its value as shellScale.
  UiScale { id: uiScaleSetting }
  EdgeGaps { id: edgeGaps }

  PowerMenu { id: powerMenu; dashboard: dashboard; lockScreen: lockScreen; shellScale: uiScaleSetting.value }
  LockScreen { id: lockScreen; dashboard: dashboard; shellScale: uiScaleSetting.value }
  SettingsScreen {
    id: settingsScreen
    dashboard: dashboard
    nightLight: nightLight
    quakeConsole: quakeConsole
    edgeGaps: edgeGaps
    uiScaleSetting: uiScaleSetting
    shellScale: uiScaleSetting.value
  }
  NightLight { id: nightLight }
  Dashboard {
    id: dashboard
    powerMenu: powerMenu
    settingsScreen: settingsScreen
    shellScale: uiScaleSetting.value
  }
  Notification { id: notification; updater: updater; edgeGaps: edgeGaps; shellScale: uiScaleSetting.value }
  Updater { id: updater; notification: notification; edgeGaps: edgeGaps; shellScale: uiScaleSetting.value }
  Clipboard { id: clipboard; edgeGaps: edgeGaps; shellScale: uiScaleSetting.value }
  Screenshot { id: screenshot; shellScale: uiScaleSetting.value }

  QuakeConsole {
    id: quakeConsole
    edgeGaps: edgeGaps
    screenName: mainBar.effectivePrimaryName
    barHidden: mainBar.hiddenOnPrimary
    shellScale: uiScaleSetting.value
  }

  Bar {
    id: mainBar
    edgeGaps: edgeGaps
    locked: lockScreen.locked
    powerMenuOpen: powerMenu.open
    dashboard: dashboard
    notification: notification
    updater: updater
    shellScale: uiScaleSetting.value
  }

  VolumeOsd {
    id: volumeOsd
    selectedSinkId: dashboard.audioSelectedSinkId
    brightnessOsd: brightnessOsd
    shellScale: uiScaleSetting.value
  }

  BrightnessOsd {
    id: brightnessOsd
    dashboard: dashboard
    volumeOsd: volumeOsd
    shellScale: uiScaleSetting.value
  }

  WorkspaceOsd { shellScale: uiScaleSetting.value }
  FullscreenHintOsd { dashboard: dashboard; shellScale: uiScaleSetting.value }
}
