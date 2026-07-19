import Quickshell
import Quickshell.Hyprland

GlobalShortcut {

    name: "lockscreen"

    onPressed: {

        LockState.locked = true
    }

}
