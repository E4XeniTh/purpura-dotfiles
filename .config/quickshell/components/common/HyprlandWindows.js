.pragma library

// The windows on a workspace, by each window's own workspace - not by the workspace's
// own list of them (HyprlandWorkspace.toplevels), which Quickshell can leave a window
// in once it's moved off. A j/clients reply asked for before a window's moved and
// come back after (purpura.lua moving a fullscreen app to a workspace of its own the
// moment it opens, say) puts it back on the workspace it left: in that one's list,
// and as its workspace. Later replies set its workspace right again, but never take
// it out of that list. `toplevels` is Hyprland.toplevels.values.
function on(toplevels, workspace) {
    if (!workspace || !toplevels) return []
    return toplevels.filter(t => same(t.workspace, workspace))
}

// The same workspace: the same one, or numbered alike (Quickshell can hold two
// objects for one workspace for a moment).
function same(a, b) {
    if (!a || !b) return false
    return a === b || (a.id >= 1 && a.id === b.id)
}
