--#######################################################################################
--## PURPURA                                                                            #
--##                                                                                    #
--## The shell's side of Hyprland - what the shell needs from it, kept out of the       #
--## personal hyprland.lua so that one stays yours and this one stays current.          #
--#######################################################################################
--
-- Installed and updated with the dotfiles (~/.config/hypr/purpura.lua). hyprland.lua
-- runs it with one line, at the start of its binds, handing it its mainMod:
--
--     pcall(loadfile(os.getenv("HOME") .. "/.config/hypr/purpura.lua") or function() end, mainMod)
--
-- Before the binds, since Close Window works by replacing the action every close
-- bind is made from. loadfile rather than require: Hyprland watches each file require
-- loads and reloads the whole config when one changes - an update of this file would
-- put the monitors back to hyprland.lua's MONITORS rule. And a missing or broken file
-- leaves hyprland.lua loading as if the line weren't there.
--
-- Each part below runs on its own: should one fail (a Hyprland update renaming
-- something it uses), a notification says which, and the rest still load.

local mainMod = ... or "SUPER"

local function report(name, err)
    pcall(hl.notification.create, {
        text = "purpura.lua, " .. name .. ": " .. tostring(err),
        duration = 15000,
        icon = "error",
    })
end

local function part(name, fn)
    local ok, err = pcall(fn)
    if not ok then report(name, err) end
end

--#######################################################################################
--## WINDOWS UNDER THE MOUSE                                                            #
--#######################################################################################

local function pair(v, a, b)
    if type(v) ~= "table" then return 0, 0 end
    return v[a] or v[1] or 0, v[b] or v[2] or 0
end

local function contains(x, y, w, h, cursor)
    return cursor.x >= x and cursor.x < x + w and cursor.y >= y and cursor.y < y + h
end

-- Hyprland can't say which window is on top, so this goes by the order it draws them
-- in: a shown special workspace over the rest, pinned windows over the rest of theirs,
-- then - with a fullscreen or maximized window there - the floating windows it lets
-- over that window (any opened or focused since), then the window itself, then the
-- rest, floating over tiled; the most recently focused one among equals.
--
-- The fullscreen window has the "allowed over fullscreen" flag on too - Hyprland only
-- turns it off for the others on its workspace - so it doesn't count for that one. If
-- it did, a maximized window would win over a floating one drawn right on top of it,
-- and close instead.
local function windowUnderCursor(cursor)
    local best, bestRank, bestHistory
    for _, window in ipairs(hl.get_windows({ mapped = true })) do
        local workspace = window.workspace
        if window.visible ~= false and not window.hidden and workspace and workspace.visible then
            local x, y = pair(window.at, "x", "y")
            local w, h = pair(window.size, "x", "y")
            if contains(x, y, w, h, cursor) then
                local fullscreen = (window.fullscreen or 0) > 0
                local rank = 0
                if workspace.special then rank = rank + 16 end
                if window.pinned then rank = rank + 8 end
                if window.floating and window.allowed_over_fullscreen and not fullscreen then rank = rank + 4 end
                if fullscreen then rank = rank + 2 end
                if window.floating then rank = rank + 1 end
                local history = window.focus_history_id or math.huge
                if history < 0 then history = math.huge end
                if not best or rank > bestRank or (rank == bestRank and history < bestHistory) then
                    best, bestRank, bestHistory = window, rank, history
                end
            end
        end
    end
    return best
end

--#######################################################################################
--## CLOSE WINDOW                                                                       #
--#######################################################################################
-- Close Window closes whatever's under the mouse: the dropdown console if it's up and
-- the mouse is over it, otherwise the window there, so a stray press can't close
-- something the mouse isn't on. With nothing under the mouse it does nothing. The
-- console isn't a window, so nothing else can reach it, and a program stuck in it can
-- leave no other way out. This wraps the action rather than one bind, so any key bound
-- to it counts, Settings > Shortcuts' included. kitty is stopped from here rather than
-- through the shell so that a stuck shell can't get in the way, with SIGKILL following
-- in case kitty is what's stuck. While the console slides in or out, kitty's surface
-- isn't always up, so the shell covers the console's area with an empty
-- "dropdownconsolesliding" surface, and a press there does nothing rather than close
-- the window underneath.
--
-- The pid check matters: it's -1 if Hyprland can't tell, and kill -9 -1 would stop
-- every process the user owns.

part("Close Window", function()
    local closeWindow = hl.dsp.window.close
    hl.dsp.window.close = function(...)
        local close = closeWindow(...)
        -- A bind that names its own window keeps it.
        if select("#", ...) > 0 then return close end
        return function()
            local cursor = hl.get_cursor_pos()
            if not cursor then return end
            for _, layer in ipairs(hl.get_layers({ namespace = "dropdownconsole" })) do
                if layer.mapped and layer.pid > 0 and contains(layer.x, layer.y, layer.w, layer.h, cursor) then
                    hl.dispatch(hl.dsp.exec_cmd("kill " .. layer.pid .. "; sleep 1; kill -9 " .. layer.pid .. " 2>/dev/null"))
                    return
                end
            end
            for _, layer in ipairs(hl.get_layers({ namespace = "dropdownconsolesliding" })) do
                if layer.mapped and contains(layer.x, layer.y, layer.w, layer.h, cursor) then return end
            end
            local window = windowUnderCursor(cursor)
            if window then hl.dispatch(closeWindow({ window = window })) end
        end
    end
end)

--#######################################################################################
--## DROPPING A DRAGGED WINDOW ON A WORKSPACE                                           #
--#######################################################################################
-- Dropping a window dragged with hyprland.lua's "Drag window" bind (mainMod + LMB) on a
-- workspace in the bar's workspace widget sends it there. While it's over one, that
-- workspace lights up and the window turns invisible, out of the way.
--
-- Hyprland keeps the pointer on the dragged window until the button's let go, so the
-- bar never sees the cursor during a drag - it's followed from here instead, by a
-- timer, and the three binds below share the drag's buttons:
--
-- - Pressing notes the window the drag picks up (the one under the cursor) and posts
--   "purpura-drag,start" on Hyprland's event socket. Each bar
--   (components/bar/WorkspaceRow.qml) answers with its workspace boxes, through
--   purpura.dropTargets() below, and the timer starts looking for one under the cursor.
-- - On the cursor reaching a box, the window gets the purpura-dragged tag - the rule
--   below turns a window with it invisible - and "purpura-drag,over,<monitor>,
--   <workspace>" lights the box up; on the cursor leaving the boxes, the tag comes off
--   and "purpura-drag,off" follows.
-- - Letting go over a box - Hyprland has ended the drag by then - sends the window to
--   that workspace without following it, a floating one back to where it was on its own
--   monitor before the drag, only on the workspace's monitor (kept on it whole). Then
--   the tag comes off and "purpura-drag,end" posts. A plain click just ends it.
--
-- Taking the tag off gives the window back whatever opacity its own rules give it.
-- non_consuming: mainMod + click on no window still reaches the app below. These have
-- no description, so Settings > Shortcuts keeps showing the drag bind's.

part("dropping a window on a workspace", function()
    local TAG = "purpura-dragged"
    local FOLLOW_MS = 25
    -- Should the release never come (a submap switched to mid-drag), the drag ends
    -- here after this long.
    local FOLLOW_FOR_S = 120

    hl.window_rule({
        name = TAG,
        match = { tag = TAG },
        opacity = "0",
    })

    local targets = {} -- each monitor's workspace boxes, from its bar
    local dragged      -- { address, relX, relY } while the button's down
    local over         -- the box under the cursor, while there is one
    local follower, startedAt

    local function dragEvent(data)
        hl.dispatch(hl.dsp.event("purpura-drag," .. data))
    end

    local function invisible(address, on)
        hl.dispatch(hl.dsp.window.tag({ tag = (on and "+" or "-") .. TAG, window = "address:" .. address }))
    end

    -- A bar's boxes, from the shell through hyprctl eval:
    --   purpura.dropTargets("DP-1", { { from = 412, to = 498, workspace = "3",
    --       x = 0, y = 0, w = 2560, h = 1440 }, ... })
    -- from/to: where it spans across the bar, in the bar's own coordinates; then the
    -- workspace to send a window to, and the area of the monitor it's on.
    purpura = purpura or {}
    function purpura.dropTargets(monitor, boxes)
        if type(monitor) ~= "string" or type(boxes) ~= "table" then return end
        local valid = {}
        for _, box in ipairs(boxes) do
            if type(box) == "table" and type(box.workspace) == "string" and type(box.from) == "number"
                and type(box.to) == "number" and type(box.x) == "number" and type(box.y) == "number"
                and type(box.w) == "number" and type(box.h) == "number" then
                valid[#valid + 1] = box
            end
        end
        targets[monitor] = valid
    end

    -- The box under the cursor, and the monitor of the bar it's on.
    local function boxUnderCursor()
        local cursor = hl.get_cursor_pos()
        if not cursor then return nil end
        for _, bar in ipairs(hl.get_layers({ namespace = "bar" })) do
            local monitor = bar.monitor
            if bar.mapped and monitor and contains(bar.x, bar.y, bar.w, bar.h, cursor) then
                local x = cursor.x - bar.x
                for _, box in ipairs(targets[monitor.name] or {}) do
                    if x >= box.from and x < box.to then return box, monitor.name end
                end
                return nil
            end
        end
        return nil
    end

    -- Stops following, and gives the window back its own opacity.
    local function endDrag()
        local window = dragged
        dragged, over = nil, nil
        if follower then follower:set_enabled(false) end
        if not window then return end
        invisible(window.address, false)
        dragEvent("end")
    end

    local function follow()
        if not dragged then
            follower:set_enabled(false)
            return
        end
        if os.time() - startedAt > FOLLOW_FOR_S then return endDrag() end
        local box, monitor = boxUnderCursor()
        if box == over then return end
        if (box == nil) ~= (over == nil) then invisible(dragged.address, box ~= nil) end
        over = box
        dragEvent(box and ("over," .. monitor .. "," .. box.workspace) or "off")
    end

    hl.bind(mainMod .. " + mouse:272", function()
        endDrag() -- one whose release never came
        local cursor = hl.get_cursor_pos()
        local window = cursor and windowUnderCursor(cursor)
        if not window then return end
        local x, y = pair(window.at, "x", "y")
        local monitor = window.monitor
        dragged = {
            address = window.address,
            relX = math.floor(x - (monitor and monitor.x or 0)),
            relY = math.floor(y - (monitor and monitor.y or 0)),
        }
        startedAt = os.time()
        dragEvent("start")
        if follower then
            follower:set_enabled(true)
        else
            -- Made here rather than as the file loads, so that it never runs without a
            -- drag. An error turns it off rather than repeating every tick.
            follower = hl.timer(function()
                local ok, err = pcall(follow)
                if not ok then
                    follower:set_enabled(false)
                    pcall(endDrag)
                    report("dropping a window on a workspace", err)
                end
            end, { timeout = FOLLOW_MS, type = "repeat" })
        end
    end, { non_consuming = true })

    hl.bind(mainMod .. " + mouse:272", function()
        if not dragged then return end
        local box = boxUnderCursor()
        local selector = "address:" .. dragged.address
        -- Still there - and floating or tiled as the drag left it.
        local window = box and hl.get_window(selector)
        if window then
            hl.dispatch(hl.dsp.window.move({ workspace = box.workspace, window = selector, follow = false }))
            if window.floating then
                local w, h = pair(window.size, "x", "y")
                hl.dispatch(hl.dsp.window.move({
                    x = math.floor(box.x + math.max(0, math.min(dragged.relX, box.w - w))),
                    y = math.floor(box.y + math.max(0, math.min(dragged.relY, box.h - h))),
                    window = selector,
                }))
            end
        end
        endDrag()
    end, { drag = true })

    hl.bind(mainMod .. " + mouse:272", function() endDrag() end, { click = true })

    -- A config reload mid-drag drops all of this, the timer included, with the old Lua
    -- state - so a window it left invisible is brought back here.
    hl.on("config.reloaded", function()
        for _, window in ipairs(hl.get_windows()) do
            for _, tag in ipairs(window.tags or {}) do
                if tag == TAG then invisible(window.address, false) end
            end
        end
    end)
end)

--#######################################################################################
--## THE SHELL'S LAYERS                                                                 #
--#######################################################################################
-- The lock screen is a real session lock rather than a layer, so no rule here: its
-- blur is misc.session_lock_xray + session_lock_blur, which the shell turns on itself
-- (components/lock/LockScreen.qml).

part("layer rules", function()
    -- Blur behind the power menu and the Settings screen.
    hl.layer_rule({
        match = { namespace = "powermenu" },
        blur = true,
    })

    hl.layer_rule({
        match = { namespace = "settingsscreen" },
        blur = true,
    })

    -- The dropdown console's terminal: no fades, as it comes and goes with the panel
    -- around it (see components/panels/DropdownConsole.qml).
    hl.layer_rule({
        match   = { namespace = "dropdownconsole" },
        no_anim = true,
    })
end)
