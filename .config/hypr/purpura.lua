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

local function part(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        pcall(hl.notification.create, {
            text = "purpura.lua, " .. name .. ": " .. tostring(err),
            duration = 15000,
            icon = "error",
        })
    end
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
-- workspace in the bar's workspace widget sends it there. The three binds below share
-- the drag's buttons: pressing notes the window the drag picks up (the one under the
-- cursor) and tells the shell a drag began, so it can light up the workspace under the
-- cursor; letting go after a drag - Hyprland has ended the drag by then - reports where
-- on the bar the window went, if it went on the bar, and a plain click just ends it.
-- The shell (components/bar/WorkspaceRow.qml) knows which workspace is there and moves
-- the window itself, a floating one back to where it was on its own monitor before the
-- drag. All of it goes as custom events on Hyprland's event socket
-- ("purpura-drag,...").
--
-- non_consuming: mainMod + click on no window still reaches the app below. These have
-- no description, so Settings > Shortcuts keeps showing the drag bind's.

part("dropping a window on a workspace", function()
    local draggedWindow

    local function dragEvent(data)
        hl.dispatch(hl.dsp.event("purpura-drag," .. data))
    end

    hl.bind(mainMod .. " + mouse:272", function()
        local cursor = hl.get_cursor_pos()
        local window = cursor and windowUnderCursor(cursor)
        draggedWindow = nil
        if not window then return end
        local x, y = pair(window.at, "x", "y")
        local monitor = window.monitor
        draggedWindow = {
            address = window.address,
            relX = math.floor(x - (monitor and monitor.x or 0)),
            relY = math.floor(y - (monitor and monitor.y or 0)),
        }
        dragEvent("start")
    end, { non_consuming = true })

    hl.bind(mainMod .. " + mouse:272", function()
        local dragged = draggedWindow
        draggedWindow = nil
        if not dragged then return end
        local cursor = hl.get_cursor_pos()
        -- Still there - and floating or tiled as the drag left it.
        local window = hl.get_window("address:" .. dragged.address)
        if cursor and window then
            for _, bar in ipairs(hl.get_layers({ namespace = "bar" })) do
                local monitor = bar.monitor
                if bar.mapped and monitor and contains(bar.x, bar.y, bar.w, bar.h, cursor) then
                    local w, h = pair(window.size, "x", "y")
                    dragEvent(string.format("drop,%s,%d,%d,%s,%d,%d,%d,%d,%d", monitor.name,
                        math.floor(cursor.x - bar.x), math.floor(cursor.y - bar.y), dragged.address,
                        window.floating and 1 or 0, dragged.relX, dragged.relY, math.floor(w), math.floor(h)))
                    return
                end
            end
        end
        dragEvent("end")
    end, { drag = true })

    hl.bind(mainMod .. " + mouse:272", function()
        if not draggedWindow then return end
        draggedWindow = nil
        dragEvent("end")
    end, { click = true })
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
