import Quickshell
import Quickshell.Hyprland

GlobalShortcut {

    name: "lockscreen"

    onPressed: {

        LockScreenState.locked = true
    }

}
