//@ pragma UseQApplication
// shell.qml
import Quickshell
import "components/bar"
import "components/dashboard"
import "components/lock"
import "components/osd"
import "components/panels"
import "components/power"
import "components/settings"
import "components/system"

Scope {
  // Settings > General's global UI Scale - every component below that sizes
  // itself gets its value as shellScale.
  UiScale { id: uiScaleSetting }
  EdgeGaps { id: edgeGaps }

  PowerMenu { id: powerMenu; dashboard: dashboard; lockScreen: lockScreen; shellScale: uiScaleSetting.value }
  LockScreen {
    id: lockScreen
    dashboard: dashboard
    shellScale: uiScaleSetting.value
    showTime: idle.showTime
    showMedia: idle.showMedia
    idle: idle
  }
  // Settings > General > Power: auto-lock, auto-dim and auto-suspend.
  Idle { id: idle; lockScreen: lockScreen; shellScale: uiScaleSetting.value }
  SettingsScreen {
    id: settingsScreen
    dashboard: dashboard
    nightLight: nightLight
    dropdownConsole: dropdownConsole
    idle: idle
    edgeGaps: edgeGaps
    uiScaleSetting: uiScaleSetting
    shellScale: uiScaleSetting.value
  }
  NightLight { id: nightLight }
  // Settings > General > Input: mouse and input languages, and the input
  // language shortcut with its OSD.
  InputDevices { id: inputDevices; osd: languageOsd }
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

  DropdownConsole {
    id: dropdownConsole
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
  }

  BrightnessOsd {
    id: brightnessOsd
    dashboard: dashboard
  }

  // Never with just one input language.
  LanguageOsd { id: languageOsd; available: inputDevices.multipleLanguages }

  // Shows the three above - size, place and stacking from Settings >
  // General > Shell > OSD - on the bar's monitor.
  OsdHost {
    shellScale: uiScaleSetting.value
    screenName: mainBar.effectivePrimaryName
    osds: [volumeOsd, brightnessOsd, languageOsd]
  }

  WorkspaceOsd { shellScale: uiScaleSetting.value }
  FullscreenHintOsd { dashboard: dashboard; shellScale: uiScaleSetting.value }
}
