import Quickshell
import Quickshell.Hyprland

GlobalShortcut {

    name: "lockscreen"

    onPressed: {

        LockMenuState.locked = true
    }

}
