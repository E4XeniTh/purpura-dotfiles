import Quickshell
import Quickshell.Hyprland

Scope {

    GlobalShortcut {

        name: "lockscreen"

        onPressed: {

            LockScreenState.locked = true
        }

    }

    // TEMPORARY DEBUG ESCAPE HATCH - remove once PamContext auth is
    // confirmed working. This bypasses the password check entirely: it
    // just flips LockScreenState directly, so anyone with this keybind
    // can unlock the screen with no password at all. Fine while testing
    // lock/unlock in isolation from PAM; not something to leave bound
    // permanently.
    GlobalShortcut {

        name: "lockscreen-toggle-debug"

        onPressed: {

            LockScreenState.locked = !LockScreenState.locked
        }

    }

}
