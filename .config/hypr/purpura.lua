--#######################################################################################
--## PURPURA                                                                            #
--##                                                                                    #
--## The shell's side of Hyprland - what the shell needs from it, kept out of the       #
--## personal hyprland.lua so that one stays yours and this one stays current.          #
--#######################################################################################
--
-- Installed and updated with the dotfiles (~/.config/hypr/purpura.lua). hyprland.lua
-- runs it with one line, at the start of its binds:
--
--     pcall(loadfile(os.getenv("HOME") .. "/.config/hypr/purpura.lua") or function() end, mainMod)
--
-- Before the binds, since Close Window works by replacing the action every close
-- bind is made from, dropping a window on a workspace makes its binds along with
-- every "Drag window" bind made after it, and "Reserve workspace" and "New workspace"
-- are actions made here. (The mainMod handed over is only for the default binds made
-- here for a hyprland.lua without them - see A workspace of its own.) loadfile rather
-- than require: Hyprland watches each file require loads and reloads the whole config
-- when one changes - an update of this file would put the monitors back to
-- hyprland.lua's MONITORS rule. And a missing or broken file leaves hyprland.lua
-- loading as if the line weren't there.
--
-- Each part below runs on its own: should one fail (a Hyprland update renaming
-- something it uses), a notification says which, and the rest still load.

local handedOver = ...
local mainMod = type(handedOver) == "string" and handedOver ~= "" and handedOver or "SUPER"

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

-- Hyprland's objects (a workspace, a window, a monitor) are userdata, not tables -
-- both count.
local function isObject(v)
    local t = type(v)
    return t == "table" or t == "userdata"
end

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
-- Dropping a window dragged with the "Drag window" bind (hyprland.lua's mainMod + LMB,
-- unless it's been moved) on a workspace in the bar's workspace widget sends it there.
-- While it's over one, that workspace lights up and the window turns invisible, out
-- of the way.
--
-- Hyprland keeps the pointer on the dragged window until the button's let go, so the
-- bar never sees the cursor during a drag - it's followed from here instead, by a
-- timer, and three binds share the drag's combo - made along with "Drag window"
-- wherever that's bound, so they follow it if it's moved (see the end of this part):
--
-- - Pressing notes the window the drag picks up (the one under the cursor) and posts
--   "purpura-drag,start,<address>" on Hyprland's event socket. Each bar
--   (components/bar/WorkspaceRow.qml) answers with its workspace boxes, through
--   purpura.dropTargets() below - it hands them over whenever they change as well -
--   and the timer starts looking for one under the cursor.
-- - On the cursor reaching a box, the window gets the purpura-dragged tag - the rule
--   below turns a window with it invisible - and "purpura-drag,over,<monitor>,
--   <workspace>" lights the box up. On a separator between two monitors' boxes it stays
--   hidden too, with "purpura-drag,between,<monitor>" (no box lit); on the cursor
--   leaving both, the tag comes off and "purpura-drag,off" follows. While it's on
--   either, "purpura-drag,at,<monitor>,<x>,<y>" says where on that monitor the cursor
--   is, whenever it moves (once a tick at most), for the window's icon the shell shows
--   under it. And "purpura-drag,monitor,<monitor>" whenever the cursor's on another
--   monitor, the first time included: the floating copy of the widget on a monitor
--   without the bar shows only there.
-- - Letting go over a box - Hyprland has ended the drag by then - sends the window to
--   that workspace without following it, a floating one back to where it was on its own
--   monitor before the drag, only on the workspace's monitor (kept on it whole). Then
--   the tag comes off and "purpura-drag,end" posts. A plain click just ends it.
--
-- Taking the tag off gives the window back whatever opacity its own rules give it.
-- The window fades out and back in with Hyprland's fade, and without its blur:
-- Hyprland draws the blur behind a window at full strength whatever the window's own
-- opacity, so it would hang there, behind a window that's already faded out, until
-- the fade ends - and show up again before the window, coming back. So the tag turns
-- the blur off with the opacity, and a second one (purpura-reappearing) keeps it off
-- until the fade back in is over.
--
-- Grabbing from the widget: the drag's combo on a window drawn in the widget picks
-- that window up from whichever workspace it's on, at the press - nothing waits for
-- the mouse to move. The window there is found from the box under the cursor (the
-- bars hand over where their boxes are): the cursor's spot in it, scaled up to that
-- workspace's monitor - a fullscreen window wherever it's pressed, as the widget
-- draws only that one then, otherwise floating over tiled, the most recently focused
-- among equals. The press bind runs before the "Drag window" bind for the same press
-- (binds go in the order they're made, and it's made just before), so by the time
-- that one looks for a window to drag, the grabbed one is already under the cursor,
-- on the workspace shown there: out of sight first, then out of fullscreen, floating
-- if it was tiled, raised, and held by its top edge, centred on the cursor. That bind
-- starts Hyprland's own drag of it, the very drag as any other from there on - hidden
-- over a box, that box lit up.
--
-- Hyprland's drag looks for its window where it's drawn right now, which mid-
-- animation is still where it was - so for that one moment the window also has
-- dim_around (purpura-grabbing), for which Hyprland counts a window as covering its
-- whole monitor. Being invisible, it dims nothing; the tag comes off a millisecond
-- later, the drag under way by then. Until it's let go, purpura-grabbed keeps its
-- animations off, so it never fades out or glides where it lands - and it vanishes
-- and comes back at once over the boxes. Let go, it's put down as any drag: on a
-- box, sent there; anywhere else, left there. One that was tiled goes back into the
-- tiling either way, and one that was fullscreen is fullscreen again on a box. Let
-- go without moving, it's over its own box - so it's back where it was.
--
-- A press on the widget that's on no window drawn there - an empty workspace, the gap
-- between two, the floating widget's edge - drags nothing at all, rather than the
-- window under the widget: it turns "Drag window" off for that one press (see
-- holdOffDrag()).
--
-- non_consuming: the drag's combo clicked on no window still reaches the app below.
-- These have no description, so Settings > Shortcuts keeps showing the drag bind's.

part("dropping a window on a workspace", function()
    local TAG = "purpura-dragged"
    local REAPPEARING = "purpura-reappearing"
    local GRABBED = "purpura-grabbed"
    local GRABBING = "purpura-grabbing"
    -- Longer than the fade back in: hyprland.lua.example's takes 0.3s, Hyprland's
    -- default 1s. An opaque window shows nothing of its blur once it's back anyway.
    local REAPPEAR_MS = 1200
    -- How often the cursor's looked for on the boxes; "at" goes out at most every
    -- AT_EVERY ticks (16ms).
    local FOLLOW_MS = 8
    local AT_EVERY = 2
    -- How far below a grabbed window's top edge the cursor holds it - by its top, as
    -- by a title bar.
    local GRIP = 16
    -- Should the release never come (a submap switched to mid-drag), the drag ends
    -- here after this long.
    local FOLLOW_FOR_S = 120
    -- How long a window sent off to a workspace that isn't on screen stays invisible
    -- (see endDrag()): past Hyprland's hold on its move (misc:transaction_timeout,
    -- 250ms at most) and its fade out of sight (hyprland.lua.example's: 0.15s).
    local AWAY_MS = 500

    hl.window_rule({
        name = TAG,
        match = { tag = TAG },
        opacity = "0",
        no_blur = true,
    })

    hl.window_rule({
        name = REAPPEARING,
        match = { tag = REAPPEARING },
        no_blur = true,
    })

    hl.window_rule({
        name = GRABBED,
        match = { tag = GRABBED },
        no_anim = true,
    })

    hl.window_rule({
        name = GRABBING,
        match = { tag = GRABBING },
        dim_around = true,
    })

    local targets = {}     -- each monitor's workspace boxes, from its bar
    local separators = {}  -- and the spans between monitors' boxes there
    local dragged          -- { address, relX, relY } while the button's down
    local grabbed          -- { tiled, fullscreen } while it's one grabbed from the widget
    local over             -- the box or separator under the cursor, while there's one (the window's hidden)
    -- A grabbed window is hidden before the box under the cursor's been posted.
    local HIDDEN_AT_START = {}
    local lastAt           -- the last "at" posted, so a still cursor isn't posted again
    local cursorMonitor    -- the monitor last posted as the cursor's
    -- Where the widget's posted to be while the drag's modifier is held (see Holding
    -- the modifier, below), and whether it's been shown there yet; and what shows it
    -- at once, set there.
    local modName, modShown = nil, false
    local showModNow
    local ticksSinceAt = 0
    local reappearing = {} -- each window's latest reappearance, till its blur's back
    local follower, startedAt

    local function dragEvent(data)
        hl.dispatch(hl.dsp.event("purpura-drag," .. data))
    end

    local function tag(address, change)
        hl.dispatch(hl.dsp.window.tag({ tag = change, window = "address:" .. address }))
    end

    local function hide(address)
        tag(address, "+" .. TAG)
    end

    local function reappear(address)
        local mark = {}
        reappearing[address] = mark
        tag(address, "+" .. REAPPEARING) -- first, so the blur's never on between the two
        tag(address, "-" .. TAG)
        hl.timer(function()
            if reappearing[address] ~= mark then return end -- a later one's still fading in
            reappearing[address] = nil
            tag(address, "-" .. REAPPEARING)
        end, { timeout = REAPPEAR_MS, type = "oneshot" })
    end

    local function workspaceSelector(workspace)
        if workspace.id and workspace.id > 0 then return tostring(workspace.id) end
        return workspace.name and ("name:" .. workspace.name) or nil
    end

    -- A bar's boxes, from the shell through hyprctl eval:
    --   purpura.dropTargets("DP-1", { { from = 412, to = 498, workspace = "3",
    --       x = 0, y = 0, w = 2560, h = 1440, bx = 414, by = 6, bw = 82, bh = 46 }, ... },
    --       { { from = 498, to = 534 }, ... })
    -- from/to: where it spans across the bar, in the bar's own coordinates; then the
    -- workspace to send a window to, the area of the monitor it's on, and the box itself
    -- (bx/by/bw/bh, in the bar's coordinates too), which draws that area scaled down.
    -- Then where the separators between one monitor's boxes and the next's span: the
    -- window stays hidden there too, though there's nothing to drop it on - so it
    -- doesn't flash up between two boxes. Last, from Bar.qml's floating copy only,
    -- where on the screen its window sits - { x = 1880, y = 10, w = 640, h = 48 } -
    -- for a press that comes before Hyprland's mapped it (see barUnderCursor()).
    local floatingAt = {} -- by monitor
    purpura = purpura or {}
    function purpura.dropTargets(monitor, boxes, between, floating)
        if type(monitor) ~= "string" or type(boxes) ~= "table" then return end
        local spans = {}
        for _, span in ipairs(type(between) == "table" and between or {}) do
            if type(span) == "table" and type(span.from) == "number" and type(span.to) == "number" then
                spans[#spans + 1] = span
            end
        end
        separators[monitor] = spans
        local valid = {}
        for _, box in ipairs(boxes) do
            if type(box) == "table" and type(box.workspace) == "string" and type(box.from) == "number"
                and type(box.to) == "number" and type(box.x) == "number" and type(box.y) == "number"
                and type(box.w) == "number" and type(box.h) == "number" then
                -- Without a box to find its windows in, it's still somewhere to drop on.
                if not (type(box.bx) == "number" and type(box.by) == "number" and type(box.bw) == "number"
                    and type(box.bh) == "number" and box.bw > 0 and box.bh > 0 and box.w > 0 and box.h > 0) then
                    box.bx, box.by, box.bw, box.bh = nil, nil, nil, nil
                end
                valid[#valid + 1] = box
            end
        end
        targets[monitor] = valid
        local at
        if type(floating) == "table" and type(floating.x) == "number" and type(floating.y) == "number"
            and type(floating.w) == "number" and type(floating.h) == "number" and floating.w > 0 and floating.h > 0 then
            at = { x = floating.x, y = floating.y, w = floating.w, h = floating.h }
        end
        floatingAt[monitor] = at
    end

    -- Bar.qml's floating copy of the widget, on a monitor without the bar: on screen
    -- (on every such monitor) from the moment the drag's modifier goes down, though
    -- only seen a moment later; and during a drag, on the cursor's monitor. All that
    -- while it's something to grab from or drop on - from the press on, not from when
    -- it's seen, as that's what a quick META + click goes for. Otherwise it's not
    -- looked at: it isn't there.
    local FLOATING = "bar-floating"
    local function floatingShown(name)
        return modName ~= nil or (dragged ~= nil and cursorMonitor == name)
    end

    -- The bar the cursor's on: its monitor, the cursor in the bar's coordinates, and
    -- whether it's the floating widget rather than the bar itself.
    local function barUnderCursor(cursor)
        for _, namespace in ipairs({ "bar", FLOATING }) do
            for _, bar in ipairs(hl.get_layers({ namespace = namespace })) do
                local monitor = bar.monitor
                if bar.mapped and monitor and contains(bar.x, bar.y, bar.w, bar.h, cursor)
                    and (namespace ~= FLOATING or floatingShown(monitor.name)) then
                    return monitor, cursor.x - bar.x, cursor.y - bar.y, namespace == FLOATING
                end
            end
        end
        -- A floating widget that's to be there but isn't mapped yet - a META + click as
        -- quick as the META, before Hyprland's put its window up - or is, but not yet
        -- where Hyprland says: where it's to sit, as its row said.
        local monitor = hl.get_monitor_at_cursor()
        local at = monitor and floatingAt[monitor.name]
        if at and floatingShown(monitor.name) and contains(at.x, at.y, at.w, at.h, cursor) then
            return monitor, cursor.x - at.x, cursor.y - at.y, true
        end
        return nil
    end

    -- The cursor's on a workspace widget: anywhere on the floating one - it's nothing
    -- else - or along the bar's row of boxes, the gaps and its ends included.
    local function onWidget(cursor)
        local monitor, x, _, floating = barUnderCursor(cursor)
        if not monitor then return false end
        if floating then return true end
        local from, to
        for _, spans in ipairs({ targets[monitor.name] or {}, separators[monitor.name] or {} }) do
            for _, span in ipairs(spans) do
                if not from or span.from < from then from = span.from end
                if not to or span.to > to then to = span.to end
            end
        end
        return from ~= nil and x >= from and x < to
    end

    -- The box or separator under the cursor (a box first, the other nil), the monitor
    -- of the bar it's on, and where on that monitor the cursor is.
    local function spotUnderCursor()
        local cursor = hl.get_cursor_pos()
        if not cursor then return nil end
        local monitor, x = barUnderCursor(cursor)
        if not monitor then return nil end
        local function found(box, span)
            return box, span, monitor.name,
                math.floor(cursor.x - (monitor.x or 0)), math.floor(cursor.y - (monitor.y or 0))
        end
        for _, box in ipairs(targets[monitor.name] or {}) do
            if x >= box.from and x < box.to then return found(box, nil) end
        end
        for _, span in ipairs(separators[monitor.name] or {}) do
            if x >= span.from and x < span.to then return found(nil, span) end
        end
        return nil
    end

    -- Just the box under the cursor, if any - somewhere to drop.
    local function boxUnderCursor()
        return (spotUnderCursor())
    end

    -- The window the widget draws under the cursor, if any (see above).
    local function windowInWidget(cursor)
        local monitor, x, y = barUnderCursor(cursor)
        if not monitor then return nil end
        for _, box in ipairs(targets[monitor.name] or {}) do
            if box.bw and x >= box.bx and x < box.bx + box.bw and y >= box.by and y < box.by + box.bh then
                local point = {
                    x = box.x + (x - box.bx) / box.bw * box.w,
                    y = box.y + (y - box.by) / box.bh * box.h,
                }
                local best, bestRank, bestHistory
                for _, window in ipairs(hl.get_windows({ mapped = true })) do
                    local workspace = window.workspace
                    if not window.hidden and workspace and workspaceSelector(workspace) == box.workspace then
                        local fullscreen = (window.fullscreen or 0) > 0
                        local wx, wy = pair(window.at, "x", "y")
                        local ww, wh = pair(window.size, "x", "y")
                        if fullscreen or contains(wx, wy, ww, wh, point) then
                            local rank = (fullscreen and 2 or 0) + (window.floating and 1 or 0)
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
        end
        return nil
    end

    -- Stops following, and brings the window back if it's hidden.
    -- A window sent off to a workspace that isn't on screen stays invisible, with its
    -- animations off (purpura-grabbed), for AWAY_MS. Hyprland 0.57 holds a window's
    -- move back until it's got its new size, or 50ms (misc:transaction_timeout) - and
    -- meanwhile keeps drawing it where it was. Its opacity given back at once, it would
    -- fade in there, faintly, for that moment before it went. By the time it's given
    -- back here it's gone; its move out of sight, with no animations, was instant.
    local away = {} -- by address, the window's hold while it goes

    local function settleAway(address)
        local hold = away[address]
        if not hold then return end
        away[address] = nil
        if hold.hidden then reappear(address) end
        tag(address, "-" .. GRABBED)
    end

    local function holdWhileGoing(address, hidden, workspace)
        local hold = { hidden = hidden, workspace = workspace }
        away[address] = hold
        hl.timer(function()
            if away[address] == hold then settleAway(address) end
        end, { timeout = AWAY_MS, type = "oneshot" })
    end

    -- Stops following, and brings the window back if it's hidden - once it's gone, if
    -- it's being sent off out of sight (see above).
    local function endDrag(sentAway)
        local window, hidden, wasGrabbed = dragged, over ~= nil, grabbed ~= nil
        dragged, over, grabbed = nil, nil, nil
        if follower then follower:set_enabled(false) end
        if not window then return end
        if wasGrabbed then tag(window.address, "-" .. GRABBING) end
        if sentAway then
            holdWhileGoing(window.address, hidden, sentAway)
        else
            if hidden then reappear(window.address) end
            if wasGrabbed then tag(window.address, "-" .. GRABBED) end
        end
        dragEvent("end")
    end

    local function follow()
        if not dragged then
            follower:set_enabled(false)
            return
        end
        if os.time() - startedAt > FOLLOW_FOR_S then return endDrag() end
        -- The monitor the cursor's on, whenever that changes: the bar shows its
        -- floating copy of the widget only there (Bar.qml).
        local onMonitor = hl.get_monitor_at_cursor()
        local onName = onMonitor and onMonitor.name
        if onName and onName ~= cursorMonitor then
            cursorMonitor = onName
            dragEvent("monitor," .. onName)
        end
        local box, span, monitor, x, y = spotUnderCursor()
        local spot = box or span
        -- First, so the icon's in place by the time "over" shows it - on reaching a
        -- box or separator whenever, otherwise once every AT_EVERY ticks at most.
        ticksSinceAt = ticksSinceAt + 1
        if spot then
            local at = monitor .. "," .. x .. "," .. y
            if at ~= lastAt and (spot ~= over or ticksSinceAt >= AT_EVERY) then
                lastAt, ticksSinceAt = at, 0
                dragEvent("at," .. at)
            end
        else
            lastAt = nil
        end
        if spot == over then return end
        if spot and not over then
            hide(dragged.address)
        elseif over and not spot then
            reappear(dragged.address)
        end
        over = spot
        dragEvent(box and ("over," .. monitor .. "," .. box.workspace)
            or span and ("between," .. monitor) or "off")
    end

    local function startFollowing()
        if follower then
            follower:set_enabled(true)
            return
        end
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

    local function fullscreenMode(mode)
        return mode == 1 and "maximized" or "fullscreen"
    end

    -- Picks up the window drawn under the cursor in the widget (see above) - false
    -- when there's none, or a special workspace is shown there, which Hyprland's drag
    -- would look in instead.
    local function grab(cursor)
        local window = windowInWidget(cursor)
        local monitor = window and hl.get_monitor_at_cursor()
        if not monitor or monitor.active_special_workspace then return false end
        local here = monitor.active_workspace and workspaceSelector(monitor.active_workspace)
        if not here then return false end
        local address, selector = window.address, "address:" .. window.address
        settleAway(address) -- still going from a drop a moment ago
        dragged = { address = address }
        grabbed = { tiled = not window.floating, fullscreen = window.fullscreen or 0 }
        startedAt = os.time()
        lastAt, ticksSinceAt, cursorMonitor = nil, 0, nil
        dragEvent("start," .. address)
        -- Out of sight before it moves at all, with no animations first, so its
        -- opacity doesn't fade where it lands.
        tag(address, "+" .. GRABBED)
        hide(address)
        over = HIDDEN_AT_START
        if grabbed.fullscreen > 0 then
            hl.dispatch(hl.dsp.window.fullscreen({
                mode = fullscreenMode(grabbed.fullscreen), action = "unset", window = selector,
            }))
            window = hl.get_window(selector) or window -- its own spot again
        end
        -- Where it was on its monitor, for a floating one to go back to on a box.
        local x, y = pair(window.at, "x", "y")
        local own = window.monitor
        dragged.relX = math.floor(x - (own and own.x or 0))
        dragged.relY = math.floor(y - (own and own.y or 0))
        -- Floating first, while it's out of sight, so it never joins the tiling here.
        if grabbed.tiled then
            hl.dispatch(hl.dsp.window.float({ action = "enable", window = selector }))
        end
        if workspaceSelector(window.workspace) ~= here then
            hl.dispatch(hl.dsp.window.move({ workspace = here, window = selector, follow = false }))
        end
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = selector }))
        -- Its size as a floating window, which Hyprland reports at once.
        local w = pair((hl.get_window(selector) or window).size, "x", "y")
        hl.dispatch(hl.dsp.window.move({
            x = math.floor(cursor.x - w / 2),
            y = math.floor(cursor.y - GRIP),
            window = selector,
        }))
        -- For "Drag window"'s search, next - see above.
        tag(address, "+" .. GRABBING)
        hl.timer(function() tag(address, "-" .. GRABBING) end, { timeout = 1, type = "oneshot" })
        startFollowing()
        follow() -- the box lit up and the icon shown now, not a tick later
        return true
    end

    -- Letting go (see above).
    local function drop()
        if not dragged then return end
        local selector = "address:" .. dragged.address
        -- Still there - and floating or tiled as the drag left it.
        local window = hl.get_window(selector)
        local box = window and boxUnderCursor()
        local sentAway = false
        if box then
            -- Out of sight with it, if that workspace isn't on screen (see endDrag()):
            -- animations off before it moves.
            -- On screen: the one it's on already (a grabbed window is on the one
            -- shown), any monitor's shown one, or one Hyprland says is visible.
            local shown = window.workspace ~= nil and workspaceSelector(window.workspace) == box.workspace
            if not shown then
                local okMonitors, monitors = pcall(hl.get_monitors)
                for _, monitor in ipairs(okMonitors and type(monitors) == "table" and monitors or {}) do
                    local active = monitor.active_workspace
                    if active and workspaceSelector(active) == box.workspace then shown = true end
                end
            end
            if not shown then
                local ok, target = pcall(hl.get_workspace, box.workspace)
                shown = ok and isObject(target) and target.visible == true
            end
            sentAway = not shown and box.workspace
            if sentAway then tag(dragged.address, "+" .. GRABBED) end
            hl.dispatch(hl.dsp.window.move({ workspace = box.workspace, window = selector, follow = false }))
        end
        if window and grabbed and grabbed.tiled then
            hl.dispatch(hl.dsp.window.float({ action = "disable", window = selector }))
        elseif box and window.floating then
            local w, h = pair(window.size, "x", "y")
            hl.dispatch(hl.dsp.window.move({
                x = math.floor(box.x + math.max(0, math.min(dragged.relX, box.w - w))),
                y = math.floor(box.y + math.max(0, math.min(dragged.relY, box.h - h))),
                window = selector,
            }))
        end
        if box and grabbed and grabbed.fullscreen > 0 then
            hl.dispatch(hl.dsp.window.fullscreen({
                mode = fullscreenMode(grabbed.fullscreen), action = "set", window = selector,
            }))
        end
        endDrag(sentAway)
    end

    -- Each combo's "Drag window" binds, as hl.bind made them (see below), and those a
    -- press has turned off for now.
    local dragBinds = {} -- by comboKey
    local heldOff = {}

    -- Back on, whichever press turned them off.
    local function letDragsBe()
        local list = heldOff
        heldOff = {}
        for _, made in ipairs(list) do pcall(function() made:set_enabled(true) end) end
    end

    -- For a press on the widget that's on no window drawn there: no drag at all, not
    -- even of the window under the widget, which "Drag window" would go for next.
    -- Hyprland runs a combo's binds in the order they were made, and passes over one
    -- that's off when its turn comes - so turned off here, by the press, which comes
    -- before it, it never starts a drag. On again a moment later, that press dealt
    -- with, or at its release if that comes first.
    local function holdOffDrag(key)
        for _, made in ipairs(dragBinds[key] or {}) do
            pcall(function()
                if made:is_enabled() then
                    made:set_enabled(false)
                    heldOff[#heldOff + 1] = made
                end
            end)
        end
        if #heldOff > 0 then hl.timer(letDragsBe, { timeout = 1, type = "oneshot" }) end
    end

    local function press(key)
        endDrag() -- one whose release never came
        if showModNow then showModNow() end -- in use: no waiting to see it
        local cursor = hl.get_cursor_pos()
        if not cursor or grab(cursor) then return end
        -- On the widget, though on no window drawn there - an empty workspace, a gap
        -- between them, its edge: nothing's dragged.
        if onWidget(cursor) then return holdOffDrag(key) end
        local window = windowUnderCursor(cursor)
        if not window then return end
        settleAway(window.address) -- still going from a drop a moment ago
        local x, y = pair(window.at, "x", "y")
        local monitor = window.monitor
        dragged = {
            address = window.address,
            relX = math.floor(x - (monitor and monitor.x or 0)),
            relY = math.floor(y - (monitor and monitor.y or 0)),
        }
        startedAt = os.time()
        lastAt, ticksSinceAt, cursorMonitor = nil, 0, nil
        dragEvent("start," .. window.address)
        startFollowing()
    end

    -- Holding the drag's modifier - META, for META + LMB - shows the widget too where
    -- there's no bar, on the monitor the cursor's on (Bar.qml), as during a drag: so a
    -- window can be grabbed from it before any drag starts. Posted as
    -- "purpura-drag,mod,<monitor>,0" the moment the modifier goes down: the widget's
    -- windows are made and put on screen, on every monitor without the bar, empty and
    -- taking no clicks - and they can be grabbed from at once (see floatingShown()) -
    -- and it's seen on the cursor's monitor with "purpura-drag,mod,<monitor>,1", a
    -- moment later (so a quick META + key shortcut doesn't flash it up), or at once on
    -- a press of the drag's combo. Again whenever the cursor moves to another
    -- monitor, and "purpura-drag,mod," once it's let go. Made only once it was to be
    -- seen, it came up a moment after; and grabbed from only once seen, a META + click
    -- right away went to the window under it.
    --
    -- Which keys are down comes from Hyprland's input.keyboard.key event: every key's
    -- press and release, by keycode, before any bind sees it - so nothing a bind does
    -- can lose one. Binds on the modifier keys themselves did lose releases: after a
    -- bind that takes its input (META + LMB's drag, META + Q), Hyprland shadows or
    -- skips binds on a key still held, which left the widget up for good.
    local MOD_FOLLOW_MS = 50
    local MOD_DELAY_TICKS = 3 -- 150ms
    local MOD_NAMES = {
        SUPER = "META", WIN = "META", LOGO = "META", MOD4 = "META", META = "META",
        ALT = "ALT", MOD1 = "ALT", CTRL = "CTRL", CONTROL = "CTRL", SHIFT = "SHIFT",
    }
    -- Each modifier's two keys, by keycode (xkb's, the evdev code + 8): left and right.
    local SIDES = {
        META = { 133, 134 }, ALT = { 64, 108 }, CTRL = { 37, 105 }, SHIFT = { 50, 62 },
    }
    local comboMods = {} -- by combo (see comboKey below): the modifiers each drag combo needs
    local sideDown = {}  -- by keycode: held now
    local modWatch, modWatching = nil, false
    local modTicks, modSince = 0, 0

    local function modifiersOf(keys)
        local mods = {}
        for token in keys:gmatch("[^+]+") do
            local name = MOD_NAMES[(token:gsub("%s", "")):upper()]
            if name then mods[name] = true end
        end
        return mods
    end

    -- Every modifier of some drag combo held, on either side.
    local function modHeld()
        for _, mods in pairs(comboMods) do
            local any, all = false, true
            for name in pairs(mods) do
                any = true
                local down = false
                for _, side in ipairs(SIDES[name] or {}) do down = down or sideDown[side] == true end
                all = all and down
            end
            if any and all then return true end
        end
        return false
    end

    local function modHide()
        modWatching = false
        if modWatch then modWatch:set_enabled(false) end
        if modName then
            modName, modShown = nil, false
            dragEvent("mod,")
        end
    end

    -- On the cursor's monitor: got ready at once, shown MOD_DELAY_TICKS on.
    local function modUpdate()
        local monitor = hl.get_monitor_at_cursor()
        local name = monitor and monitor.name
        local shown = modTicks >= MOD_DELAY_TICKS
        if name and (name ~= modName or shown ~= modShown) then
            modName, modShown = name, shown
            dragEvent("mod," .. name .. (shown and ",1" or ",0"))
        end
    end

    -- The widget shown at once, the wait cut short: a press of the drag's combo while
    -- the modifier's held is using it.
    showModNow = function()
        if not modWatching then return end
        modTicks = math.max(modTicks, MOD_DELAY_TICKS)
        modUpdate()
    end

    local function modTick()
        -- A release that never came (the session switched away, say) lets it go
        -- after as long as a drag gets.
        if not modHeld() or os.time() - modSince > FOLLOW_FOR_S then return modHide() end
        modTicks = modTicks + 1
        modUpdate()
    end

    local function modSide(side, down)
        sideDown[side] = down
        if not modHeld() then return modHide() end
        if modWatching then return end
        modWatching, modTicks, modSince = true, 0, os.time()
        modUpdate()
        if modWatch then
            modWatch:set_enabled(true)
            return
        end
        -- Made at the first press rather than as the file loads.
        modWatch = hl.timer(function()
            local ok, err = pcall(modTick)
            if not ok then
                modWatching = false
                modWatch:set_enabled(false)
                report("showing the workspace widget while the modifier's held", err)
            end
        end, { timeout = MOD_FOLLOW_MS, type = "repeat" })
    end

    local modCodes = {} -- every modifier key's keycode, to tell them from the rest
    for _, codes in pairs(SIDES) do
        for _, code in ipairs(codes) do modCodes[code] = true end
    end

    hl.on("input.keyboard.key", function(code, _, state)
        if not modCodes[code] then return end
        local ok, err = pcall(modSide, code, state ~= 0) -- 0 is a release
        if not ok then report("showing the workspace widget while the modifier's held", err) end
    end)

    -- The three binds on the drag's combo (see above): the press, the release after
    -- a drag, and the release after a click - which puts a grabbed window down even
    -- without a move (back on its own box), and just ends any other drag. And the
    -- modifiers it needs, for the widget while they're held.
    local function bindAlong(bind, keys, key)
        bind(keys, function() press(key) end, { non_consuming = true })
        bind(keys, function()
            letDragsBe()
            drop()
        end, { drag = true })
        bind(keys, function()
            letDragsBe()
            if grabbed then drop() else endDrag() end
        end, { click = true })
        comboMods[key] = modifiersOf(keys)
    end

    -- Made along with every bind of hl.dsp.window.drag(), on whatever combo that's
    -- given, so they follow "Drag window" wherever it's bound: hyprland.lua's own
    -- bind, or one from Settings > Shortcuts (hypr/shortcuts.lua, and the hyprctl
    -- eval that changes it there at once). Just before it, so that the press here
    -- runs first (see Grabbing). Unbinding a combo takes them along with the drag's
    -- bind, as Hyprland unbinds every bind on it; a combo already holding them
    -- isn't given them twice.
    local drags = setmetatable({}, { __mode = "k" }) -- every action drag() has made
    local makeDrag = hl.dsp.window.drag
    hl.dsp.window.drag = function(...)
        local action = makeDrag(...)
        if action ~= nil then drags[action] = true end
        return action
    end

    -- A combo as Hyprland tells one from another: case and spaces don't count.
    local function comboKey(keys)
        return (keys:gsub("%s", "")):lower()
    end
    local along = {} -- by comboKey, the combos holding them now

    -- The drag's own bind is kept too, as Hyprland hands it back, for holdOffDrag().
    local bind = hl.bind
    hl.bind = function(keys, action, ...)
        local isDrag = type(keys) == "string" and action ~= nil and drags[action]
        local key = isDrag and comboKey(keys)
        if isDrag and not along[key] then
            local ok, err = pcall(bindAlong, bind, keys, key)
            if ok then along[key] = true else report("dropping a window on a workspace", err) end
        end
        local made = table.pack(bind(keys, action, ...))
        if isDrag and made[1] ~= nil then
            dragBinds[key] = dragBinds[key] or {}
            table.insert(dragBinds[key], made[1])
        end
        return table.unpack(made, 1, made.n)
    end

    local unbind = hl.unbind
    if unbind then
        hl.unbind = function(keys, ...)
            if keys == "all" and select("#", ...) == 0 then
                along, comboMods, dragBinds = {}, {}, {}
                modHide()
            elseif type(keys) == "string" then
                local key = comboKey(keys)
                along[key], comboMods[key], dragBinds[key] = nil, nil, nil
                if not modHeld() then modHide() end
            end
            return unbind(keys, ...)
        end
    end

    -- Switched to the workspace a held window was sent to: it's needed there now, so
    -- the hold ends at once rather than when its time's up.
    hl.on("workspace.active", function(workspace)
        local selector = isObject(workspace) and workspaceSelector(workspace)
        if not selector then return end
        for address, hold in pairs(away) do
            if hold.workspace == selector then settleAway(address) end
        end
    end)

    -- A config reload mid-drag drops all of this, the timers included, with the old
    -- Lua state - so a window it left invisible, without its blur or its animations,
    -- is brought back here.
    hl.on("config.reloaded", function()
        for _, window in ipairs(hl.get_windows()) do
            for _, name in ipairs(window.tags or {}) do
                if name == TAG or name == REAPPEARING or name == GRABBED or name == GRABBING then
                    tag(window.address, "-" .. name)
                end
            end
        end
    end)
end)

--#######################################################################################
--## WORKSPACES                                                                         #
--#######################################################################################
-- Purpura's book of workspaces, kept over Hyprland's own: every workspace Hyprland has,
-- by its id, with the number purpura shows for it, what kind it is and what it's for.
-- The shell reads it (components/common/WorkspaceRegistry.qml) and the rest of this
-- file asks it (purpura.workspaces).
--
-- Numbers. 1-5 are the workspaces Display settings pins to the monitors, one monitor
-- each, and keep Hyprland's own numbers - META + 1-5 go to them as Hyprland's. Any
-- other gets the lowest number from 6 that no other has, the moment it's seen, and
-- keeps it till it's gone. One purpura makes is given that number as its Hyprland id
-- too when no workspace has it, else the lowest id from 6 none has - the book
-- remembers which is which.
--
-- Types:
--   pinned      one of 1-5, which Display settings has on a monitor
--   spare       what a monitor none of 1-5 is on is given, to have somewhere to be
--   reserved    Reserve workspace's, for a window (its app and address kept)
--   fullscreen  a fullscreen app's own, from as it opened (its app and address kept)
--   new         New workspace's
--   other       one purpura didn't make - a hyprland.lua rule's, a plain `workspace 9`
-- Only a pinned one is managed. Special workspaces aren't in the book.
--
-- On Hyprland's own workspace rules: a monitor's assigned workspaces are persistent
-- rules on it, its lowest its default - so Hyprland keeps them, makes one that's
-- missing, moves one home when its monitor's back, and starts a monitor on its
-- default. Rules for one workspace merge, so hyprland.lua's own for it (gaps, a
-- layout) stay as they are. A reserved, fullscreen or new one is bound to its monitor
-- the same way, but not kept.
--
-- Remembered for the session, in $XDG_RUNTIME_DIR: purpura-workspaces.lua for this
-- file, read back as it loads - a config reload starts a new Lua state and clears
-- every workspace rule, so the rules are made again then, from it - and
-- purpura-workspaces.json for the shell. Another Hyprland's (one that's since
-- restarted) is left be: the login's scripts/apply-monitors.sh assigns them afresh.
--
-- purpura.workspaces.assign(map, pins, opts) - Display settings' Apply, and
-- apply-monitors.sh at login:
--     purpura.workspaces.assign({ ["DP-1"] = { 1, 2, 3, 4 }, ["DP-2"] = { 5 } }, pins)
-- each monitor with its workspaces of 1-5 (anything past 5 is left out), one with none
-- given a spare. pins are what Display settings' buttons picked, kept for them. Each
-- monitor that isn't showing one of its own then shows its default - unless it's
-- showing a reserved, fullscreen or new workspace, which stays - and a workspace one
-- leaves that's spare or other and no monitor's any more has its windows brought
-- along, as has each in opts.rescue (what a monitor being switched off showed).
-- opts.home switches every monitor to its default, and opts.primary is focused last,
-- so the focus ends there (both at login). The focused monitor switches as any switch
-- does; another without the cursor moving or the focus going there, and then the
-- shell's told, as Hyprland says nothing of a switch like that:
-- "purpura-workspace,shown,<monitor>" (components/osd/WorkspaceOsd.qml).

part("workspaces", function()
    local FIRST = 6
    local OWN = { reserved = true, fullscreen = true, new = true }
    local TYPES = { pinned = true, spare = true, reserved = true, fullscreen = true, new = true, other = true }
    local DIR = os.getenv("XDG_RUNTIME_DIR") or ((os.getenv("HOME") or "") .. "/.cache")
    local STATE = DIR .. "/purpura-workspaces.lua"
    local SHARED = DIR .. "/purpura-workspaces.json"
    local INSTANCE = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or ""
    local INTENT_S = 10 -- a workspace that's to be made and isn't by then won't be

    local entries = {}  -- [Hyprland id] = { id, number, type, monitor, since, app, window }
    local assigned = {} -- [monitor] = its workspaces, lowest (its default) first
    local pins = {}     -- [monitor] = what Display settings' buttons picked
    local intended = {} -- [id] = { type, number, app, window, at }: one about to be made

    local api = {}

    local function validName(name)
        return type(name) == "string" and #name <= 64 and name:match("^[%w_%.%-]+$") ~= nil
    end

    local function integer(n)
        return math.type(n) == "integer"
    end

    local function later(fn)
        hl.timer(function()
            local ok, err = pcall(fn)
            if not ok then report("workspaces", err) end
        end, { timeout = 1, type = "oneshot" })
    end

    local function sortedKeys(t)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        return keys
    end

    -- Hyprland's workspaces, but the special ones.
    local function live()
        local ok, list = pcall(hl.get_workspaces)
        local out = {}
        for _, ws in ipairs(ok and type(list) == "table" and list or {}) do
            if isObject(ws) and not ws.special and integer(ws.id) then out[#out + 1] = ws end
        end
        return out
    end

    local function assignedTo(id)
        for name, ids in pairs(assigned) do
            for _, x in ipairs(ids) do
                if x == id then return name end
            end
        end
    end

    local function pruneIntended()
        local now = os.time()
        for id, want in pairs(intended) do
            if now - want.at > INTENT_S then intended[id] = nil end
        end
    end

    local function numberTaken(n)
        for _, e in pairs(entries) do
            if e.number == n then return true end
        end
        for _, want in pairs(intended) do
            if want.number == n then return true end
        end
        return false
    end

    local function nextNumber()
        local n = FIRST
        while numberTaken(n) do n = n + 1 end
        return n
    end

    -- A Hyprland id and a number for one purpura's to make (see above).
    local function allocate()
        pruneIntended()
        local number = nextNumber()
        local taken = {}
        for id in pairs(entries) do taken[id] = true end
        for id in pairs(intended) do taken[id] = true end
        for _, ws in ipairs(live()) do taken[ws.id] = true end
        local id = number
        if taken[id] then
            id = FIRST
            while taken[id] do id = id + 1 end
        end
        return id, number
    end

    -- ---- the files ----
    local queued = false
    local flush

    local function changed()
        if queued then return end
        queued = true
        later(function()
            queued = false
            flush()
        end)
    end

    local function numbers(list, sep)
        local out = {}
        for _, n in ipairs(list) do out[#out + 1] = tostring(n) end
        return table.concat(out, sep)
    end

    local function jsonString(s)
        return '"' .. (s:gsub('[%c"\\]', function(c)
            if c == '"' then return '\\"' end
            if c == "\\" then return "\\\\" end
            return string.format("\\u%04x", c:byte())
        end)) .. '"'
    end

    local function write(path, text)
        local file = io.open(path, "w")
        if not file then return end
        file:write(text)
        file:close()
    end

    flush = function()
        local names = {}
        for name in pairs(assigned) do names[name] = true end
        for name in pairs(pins) do names[name] = true end
        local luaMonitors, jsonMonitors = {}, {}
        for _, name in ipairs(sortedKeys(names)) do
            local a, p = assigned[name] or {}, pins[name] or {}
            luaMonitors[#luaMonitors + 1] = string.format("        [%q] = { assigned = { %s }, pins = { %s } },",
                name, numbers(a, ", "), numbers(p, ", "))
            jsonMonitors[#jsonMonitors + 1] = string.format('%s:{"workspaces":[%s],"pins":[%s]}',
                jsonString(name), numbers(a, ","), numbers(p, ","))
        end
        local luaEntries, jsonEntries = {}, {}
        for _, id in ipairs(sortedKeys(entries)) do
            local e = entries[id]
            local luaFields = { "number = " .. e.number, string.format("type = %q", e.type), "since = " .. e.since }
            local jsonFields = { '"id":' .. id, '"number":' .. e.number, '"type":' .. jsonString(e.type), '"since":' .. e.since }
            for _, key in ipairs({ "monitor", "app", "window" }) do
                if e[key] then
                    luaFields[#luaFields + 1] = string.format("%s = %q", key, e[key])
                    jsonFields[#jsonFields + 1] = jsonString(key) .. ":" .. jsonString(e[key])
                end
            end
            luaEntries[#luaEntries + 1] = string.format("        [%d] = { %s },", id, table.concat(luaFields, ", "))
            jsonEntries[#jsonEntries + 1] = jsonString(tostring(id)) .. ":{" .. table.concat(jsonFields, ",") .. "}"
        end
        write(STATE, table.concat({
            "-- purpura.lua's workspaces (WORKSPACES there), for this Hyprland - rewritten as they change.",
            "return {",
            string.format("    instance = %q,", INSTANCE),
            "    monitors = {", table.concat(luaMonitors, "\n"), "    },",
            "    entries = {", table.concat(luaEntries, "\n"), "    },",
            "}",
            "",
        }, "\n"))
        write(SHARED, '{"instance":' .. jsonString(INSTANCE) .. ',"monitors":{' .. table.concat(jsonMonitors, ",")
            .. '},"workspaces":{' .. table.concat(jsonEntries, ",") .. "}}\n")
    end

    -- This Hyprland's book, as it was before a reload.
    local function restore()
        if INSTANCE == "" then return end
        local chunk = loadfile(STATE)
        if not chunk then return end
        local ok, saved = pcall(chunk)
        if not ok or type(saved) ~= "table" or saved.instance ~= INSTANCE then return end
        for name, m in pairs(type(saved.monitors) == "table" and saved.monitors or {}) do
            if validName(name) and type(m) == "table" then
                local a, p = {}, {}
                for _, id in ipairs(type(m.assigned) == "table" and m.assigned or {}) do
                    if integer(id) then a[#a + 1] = id end
                end
                for _, n in ipairs(type(m.pins) == "table" and m.pins or {}) do
                    if integer(n) and n >= 1 and n <= 5 then p[#p + 1] = n end
                end
                table.sort(a)
                table.sort(p)
                if #a > 0 then assigned[name] = a end
                pins[name] = p
            end
        end
        for id, e in pairs(type(saved.entries) == "table" and saved.entries or {}) do
            if integer(id) and type(e) == "table" and integer(e.number) and TYPES[e.type] then
                entries[id] = {
                    id = id,
                    number = e.number,
                    type = e.type,
                    monitor = validName(e.monitor) and e.monitor or nil,
                    since = integer(e.since) and e.since or os.time(),
                    app = type(e.app) == "string" and e.app:sub(1, 256) or nil,
                    window = type(e.window) == "string" and e.window:match("^0x%x+$") and e.window or nil,
                }
            end
        end
    end

    -- ---- keeping it in step with Hyprland ----
    -- In the book, as it's made or first seen: what it was made for, else pinned or
    -- spare by Display settings, else other. One that's in it already has its monitor
    -- looked at.
    local function register(ws)
        if not isObject(ws) or ws.special or not integer(ws.id) then return nil end
        local id = ws.id
        local monitor = isObject(ws.monitor) and validName(ws.monitor.name) and ws.monitor.name or nil
        local e = entries[id]
        if e then
            if monitor and e.monitor ~= monitor then
                e.monitor = monitor
                changed()
            end
            return e
        end
        local want = intended[id]
        intended[id] = nil
        local kind = want and want.type or (assignedTo(id) and "spare") or "other"
        if id >= 1 and id <= 5 and assignedTo(id) then kind = "pinned" end
        local app = want and want.app or nil
        e = {
            id = id,
            number = (id >= 1 and id <= 5) and id or (want and want.number) or nextNumber(),
            type = kind,
            monitor = monitor,
            since = os.time(),
            app = type(app) == "string" and app ~= "" and app:sub(1, 256) or nil,
            window = want and want.window or nil,
        }
        entries[id] = e
        changed()
        return e
    end

    -- Gone ones out, unknown ones in. (workspace.removed comes from the workspace's
    -- end, too late to ask it which it was - so this looks a moment after.)
    local function reconcile()
        local seen = {}
        for _, ws in ipairs(live()) do
            seen[ws.id] = true
            register(ws)
        end
        for id in pairs(entries) do
            if not seen[id] then
                entries[id] = nil
                changed()
            end
        end
    end

    -- ---- rules ----
    -- Kept on its monitor, and its default when it's the monitor's lowest.
    local function keep(id, monitor, default)
        pcall(hl.workspace_rule, { workspace = tostring(id), monitor = monitor, persistent = true, default = default })
    end

    -- Made on, and brought back to, its monitor - not kept.
    local function bind(id, monitor)
        pcall(hl.workspace_rule, { workspace = tostring(id), monitor = monitor })
    end

    -- Kept no longer, nor a default. (A rule can't be told to forget its monitor; a
    -- reload drops it.)
    local function release(id)
        pcall(hl.workspace_rule, { workspace = tostring(id), persistent = false, default = false })
    end

    local function makeRules()
        for _, name in ipairs(sortedKeys(assigned)) do
            for i, id in ipairs(assigned[name]) do keep(id, name, i == 1) end
        end
        for _, id in ipairs(sortedKeys(entries)) do
            local e = entries[id]
            if OWN[e.type] and e.monitor and not assignedTo(id) then bind(id, e.monitor) end
        end
    end

    -- ---- switching and bringing windows along ----
    local function showOn(monitor, selector)
        local focused = hl.get_active_monitor()
        if isObject(focused) and focused.name == monitor.name then
            hl.dispatch(hl.dsp.focus({ workspace = selector }))
            return
        end
        monitor:set_workspace(selector)
        hl.dispatch(hl.dsp.event("purpura-workspace,shown," .. monitor.name))
    end

    local function bringAlong(from, to)
        local ok, windows = pcall(hl.get_workspace_windows, tostring(from))
        if not ok or type(windows) ~= "table" then return end
        for _, window in ipairs(windows) do
            if isObject(window) and window.address then
                hl.dispatch(hl.dsp.window.move({ workspace = tostring(to), window = "address:" .. window.address, follow = false }))
            end
        end
    end

    local function workspaceById(id)
        local ok, ws = pcall(hl.get_workspace, tostring(id))
        return ok and isObject(ws) and ws or nil
    end

    -- ---- the book's own ways in ----
    function api.assign(map, picked, opts)
        if type(map) ~= "table" then error("expected { [monitor] = { workspaces } }", 0) end
        opts = type(opts) == "table" and opts or {}

        -- Each monitor's of 1-5, one monitor each.
        local wanted, owner = {}, {}
        for _, name in ipairs(sortedKeys(map)) do
            local list = map[name]
            if validName(name) and type(list) == "table" then
                local ids = {}
                for _, n in ipairs(list) do
                    if integer(n) and n >= 1 and n <= 5 and not owner[n] then
                        owner[n] = name
                        ids[#ids + 1] = n
                    end
                end
                table.sort(ids)
                wanted[name] = ids
            end
        end

        -- A spare for a monitor with none of them: its own from before, else the one
        -- it's showing if that's past 5 and nobody's, else a new one.
        for _, name in ipairs(sortedKeys(wanted)) do
            if #wanted[name] == 0 then
                local spare
                for _, id in ipairs(assigned[name] or {}) do
                    if id > 5 and entries[id] then spare = id end
                end
                if not spare then
                    local monitor = hl.get_monitor(name)
                    local active = isObject(monitor) and monitor.active_workspace or nil
                    local e = isObject(active) and register(active) or nil
                    if e and e.type == "other" and e.number >= FIRST and not assignedTo(active.id) then spare = active.id end
                end
                if not spare then
                    local id, number = allocate()
                    intended[id] = { type = "spare", number = number, at = os.time() }
                    spare = id
                end
                wanted[name] = { spare }
            end
        end

        local still = {}
        for _, ids in pairs(wanted) do
            for _, id in ipairs(ids) do still[id] = true end
        end
        for _, name in ipairs(sortedKeys(assigned)) do
            for _, id in ipairs(assigned[name]) do
                if not still[id] then
                    release(id)
                    local e = entries[id]
                    if e and (e.type == "pinned" or e.type == "spare") then e.type = "other" end
                end
            end
        end
        assigned = wanted

        pins = {}
        for name, list in pairs(type(picked) == "table" and picked or {}) do
            if validName(name) and type(list) == "table" then
                local p = {}
                for _, n in ipairs(list) do
                    if integer(n) and n >= 1 and n <= 5 then p[#p + 1] = n end
                end
                table.sort(p)
                pins[name] = p
            end
        end

        for id in pairs(still) do
            local e = entries[id]
            if e then
                if id <= 5 then
                    e.type, e.app, e.window = "pinned", nil, nil
                elseif not OWN[e.type] then
                    e.type = "spare"
                end
            end
        end
        makeRules()
        -- Written as soon as it's decided, should a switch below fail.
        changed()

        -- Home now, rather than when Hyprland next gets to its rules: the switches
        -- below go by where they are.
        for _, name in ipairs(sortedKeys(assigned)) do
            if hl.get_monitor(name) then
                for _, id in ipairs(assigned[name]) do
                    local ws = workspaceById(id)
                    if ws and isObject(ws.monitor) and ws.monitor.name ~= name then
                        hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = name }))
                    end
                end
            end
        end

        local bring = {}
        for _, name in ipairs(sortedKeys(assigned)) do
            local monitor = hl.get_monitor(name)
            local ids = assigned[name]
            local active = isObject(monitor) and monitor.active_workspace or nil
            if isObject(active) and ids[1] then
                local e = register(active)
                local own = false
                for _, id in ipairs(ids) do
                    if id == active.id then own = true end
                end
                local stays = e and OWN[e.type] and not own
                if not stays and (not own or (opts.home and active.id ~= ids[1])) then
                    showOn(monitor, tostring(ids[1]))
                    if e and (e.type == "spare" or e.type == "other") and not still[active.id] then
                        bring[active.id] = ids[1]
                    end
                end
            end
        end
        for _, id in ipairs(type(opts.rescue) == "table" and opts.rescue or {}) do
            local e = integer(id) and entries[id] or nil
            if e and (e.type == "spare" or e.type == "other") and not still[id] and not bring[id] then
                local home = e.monitor and assigned[e.monitor] and assigned[e.monitor][1]
                if not home then
                    for _, ids in pairs(assigned) do
                        if ids[1] and (not home or ids[1] < home) then home = ids[1] end
                    end
                end
                if home then bring[id] = home end
            end
        end
        for _, from in ipairs(sortedKeys(bring)) do bringAlong(from, bring[from]) end

        if validName(opts.primary) and hl.get_monitor(opts.primary) then
            hl.dispatch(hl.dsp.focus({ monitor = opts.primary }))
        end
        changed()
    end

    function api.entry(id)
        return entries[id]
    end

    -- Not one Display settings pinned.
    function api.unmanaged(id)
        local e = entries[id]
        return e ~= nil and e.type ~= "pinned"
    end

    -- Where that window's to have a workspace of its own, of that kind, on that
    -- monitor: the one the monitor's showing if that's past 5, unmanaged, and holds
    -- nothing else; else a new one, bound to the monitor.
    function api.claim(window, monitor, kind)
        local here = isObject(window.workspace) and window.workspace.id or nil
        local app = window.class ~= "" and window.class or window.initial_class
        local current = monitor.active_workspace
        local e = isObject(current) and register(current) or nil
        if e and e.type ~= "pinned" and e.number >= FIRST then
            local others = (current.windows or 0) - (here == current.id and 1 or 0)
            if others <= 0 then
                e.type, e.window = kind, window.address
                e.app = type(app) == "string" and app ~= "" and app:sub(1, 256) or nil
                bind(current.id, monitor.name)
                changed()
                return current.id
            end
        end
        local id, number = allocate()
        intended[id] = { type = kind, number = number, app = app, window = window.address, at = os.time() }
        bind(id, monitor.name)
        return id
    end

    -- A new workspace of that kind for that monitor, bound to it - made once it's
    -- gone to.
    function api.make(monitor, kind)
        local id, number = allocate()
        intended[id] = { type = kind, number = number, at = os.time() }
        bind(id, monitor.name)
        return id
    end

    -- That monitor's workspaces, by number.
    function api.onMonitor(name)
        local list = {}
        for _, ws in ipairs(live()) do
            if isObject(ws.monitor) and ws.monitor.name == name then
                local e = register(ws)
                list[#list + 1] = { id = ws.id, number = e and e.number or ws.id }
            end
        end
        table.sort(list, function(a, b) return a.number < b.number end)
        return list
    end

    -- That monitor showing that workspace, as described above.
    api.showOn = showOn

    hl.on("workspace.created", function(ws)
        register(ws)
    end)

    hl.on("workspace.move_to_monitor", function(ws, monitor)
        local e = isObject(ws) and integer(ws.id) and entries[ws.id] or nil
        if e and isObject(monitor) and validName(monitor.name) and e.monitor ~= monitor.name then
            e.monitor = monitor.name
            changed()
        end
    end)

    hl.on("workspace.removed", function()
        later(reconcile)
    end)

    hl.on("config.reloaded", function()
        reconcile()
        changed()
    end)

    restore()
    makeRules()
    purpura = purpura or {}
    purpura.workspaces = api
end)

--#######################################################################################
--## A WORKSPACE OF ITS OWN                                                             #
--#######################################################################################
-- "Reserve workspace" (hyprland.lua.example: META + CTRL + W) gives the focused window
-- an empty unmanaged workspace (see WORKSPACES): the one the focused monitor's
-- showing, when that's past 5, isn't pinned and holds nothing else, or else a new one,
-- numbered from 6. The window goes there, the monitor's switched to it, and the
-- workspace is bound to that monitor (a workspace rule, so it's made there and comes
-- back there). The book has it as reserved, for that window's app.
--
-- With Create Workspace For Fullscreen Apps on (Settings > General > Shell > Main Bar;
-- off unless it's been turned on), a fullscreen app opening is given one the same way,
-- on its own monitor, kept as fullscreen: a window that's fullscreen as it opens, or
-- goes fullscreen within its first few seconds, as games do; maximized doesn't count,
-- nor a window going fullscreen later on. Then
-- "purpura-workspace,fullscreen,<monitor>,<workspace>" goes out on Hyprland's event
-- socket, for the workspace OSD to show it (components/osd/WorkspaceOsd.qml). Each
-- move comes a moment after what prompts it, never inside Hyprland's handling of that;
-- and Hyprland's own move of a fullscreen window takes it out of fullscreen and back
-- in, which is let pass. The setting's read from the shell's barsettings.json each
-- time a fullscreen app opens, so it counts the moment it's changed, with no reload;
-- off (or with no shell to have saved it), the app's left where it opened.
--
-- "Next workspace" (META + TAB) switches the monitor under the cursor to its next
-- workspace by the book's numbers - left to right in the workspace widget - round to
-- the first after the last. "New workspace" (META + CTRL + TAB) makes an empty one,
-- numbered from 6, on the monitor under the cursor, bound to it, and switches that
-- monitor to it. On the focused monitor - which the cursor's nearly always on, as
-- moving onto a monitor focuses it - each is an ordinary switch; on another (something
-- else took the focus while the cursor rested there), one without the focus going
-- there or the cursor moving, and the next move of the mouse focuses that monitor as
-- any does (see WORKSPACES).
--
-- hyprland.lua.example binds all three; a hyprland.lua from before doesn't. So each is
-- made here once the config has loaded, unless hyprland.lua or shortcuts.lua bound
-- that combo to something (or unbound it - Settings > Shortcuts taking it off), or
-- bound that action somewhere else.

part("workspaces of their own", function()
    local book = purpura and purpura.workspaces
    if not book then error("needs the workspaces part, which didn't load", 0) end
    local GRACE_S = 5   -- fullscreen this soon after opening counts as opening fullscreen
    local opened = {}   -- by address: when each window opened, for GRACE_S
    local moving = false -- one of ours under way: the fullscreen changes it makes pass

    local function later(fn)
        hl.timer(function()
            local ok, err = pcall(fn)
            if not ok then report("workspaces of their own", err) end
        end, { timeout = 1, type = "oneshot" })
    end

    local function focusMonitor(monitor)
        local focused = hl.get_active_monitor()
        if not (isObject(focused) and focused.name == monitor.name) then
            hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
        end
    end

    local function hoveredMonitor()
        local monitor = hl.get_monitor_at_cursor()
        if isObject(monitor) and monitor.name then return monitor end
    end

    -- A workspace of its own on that monitor for the window, of that kind (see above),
    -- the window on it and the monitor showing it. Its id, and whether the window had
    -- to move there - or nil, for a window on a special workspace.
    local function giveOwn(window, monitor, kind)
        if not isObject(window) or window.mapped == false or not isObject(monitor) or not monitor.name then return nil end
        local workspace = window.workspace
        if isObject(workspace) and workspace.special then return nil end
        local here = isObject(workspace) and workspace.id or nil
        local id = book.claim(window, monitor, kind)
        focusMonitor(monitor)
        if here == id then
            hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
            return id, false
        end
        moving = true
        local ok, err = pcall(hl.dispatch, hl.dsp.window.move({
            workspace = tostring(id), window = "address:" .. window.address, follow = true,
        }))
        moving = false
        if not ok then error(err, 0) end
        return id, true
    end

    -- Create Workspace For Fullscreen Apps (see above): on only when the shell's saved
    -- it on - JSON.stringify's own spacing or none.
    local SETTINGS = (os.getenv("HOME") or "") .. "/.config/quickshell/barsettings.json"
    local function fullscreenWorkspaces()
        local file = io.open(SETTINGS, "r")
        if not file then return false end
        local text = file:read(65536) or ""
        file:close()
        return text:find('"createFullscreenWorkspaces"%s*:%s*true') ~= nil
    end

    -- A fullscreen app that's opened: its own workspace, on its own monitor - said.
    local function fullscreenOpened(address)
        opened[address] = nil
        if not fullscreenWorkspaces() then return end
        local window = hl.get_window("address:" .. address)
        if not isObject(window) or window.fullscreen ~= 2 then return end
        local monitor = window.monitor
        local id, moved = giveOwn(window, monitor, "fullscreen")
        if id and moved then
            hl.dispatch(hl.dsp.event("purpura-workspace,fullscreen," .. monitor.name .. "," .. id))
        end
    end

    local reserveActions = setmetatable({}, { __mode = "k" }) -- every action reserve_workspace() has made
    hl.dsp.window.reserve_workspace = function()
        local action = function()
            local ok, err = pcall(function()
                local window = hl.get_active_window()
                if isObject(window) then giveOwn(window, hl.get_active_monitor(), "reserved") end
            end)
            if not ok then report("workspaces of their own", err) end
        end
        reserveActions[action] = true
        return action
    end

    if type(hl.dsp.workspace) ~= "table" then hl.dsp.workspace = {} end

    local nextActions = setmetatable({}, { __mode = "k" }) -- every action next_on_hovered() has made
    hl.dsp.workspace.next_on_hovered = function()
        local action = function()
            local ok, err = pcall(function()
                local monitor = hoveredMonitor()
                if not monitor then return end
                local list = book.onMonitor(monitor.name)
                if #list < 2 then return end
                local active = monitor.active_workspace
                local at = 0
                for i, ws in ipairs(list) do
                    if isObject(active) and ws.id == active.id then at = i end
                end
                book.showOn(monitor, tostring(list[at % #list + 1].id))
            end)
            if not ok then report("workspaces of their own", err) end
        end
        nextActions[action] = true
        return action
    end

    local newActions = setmetatable({}, { __mode = "k" }) -- every action new_on_hovered() has made
    hl.dsp.workspace.new_on_hovered = function()
        local action = function()
            local ok, err = pcall(function()
                local monitor = hoveredMonitor()
                if not monitor then return end
                book.showOn(monitor, tostring(book.make(monitor, "new")))
            end)
            if not ok then report("workspaces of their own", err) end
        end
        newActions[action] = true
        return action
    end

    hl.on("window.open", function(window)
        if not isObject(window) or not window.address then return end
        local now = os.time()
        for address, at in pairs(opened) do
            if now - at > GRACE_S then opened[address] = nil end
        end
        local address = window.address
        opened[address] = now
        if window.fullscreen == 2 then later(function() fullscreenOpened(address) end) end
    end)

    -- Looked at again a moment later, as it is by then.
    hl.on("window.fullscreen", function(window)
        if moving or not isObject(window) or window.fullscreen ~= 2 then return end
        local address = window.address
        local at = address and opened[address]
        if not at or os.time() - at > GRACE_S then return end
        later(function() fullscreenOpened(address) end)
    end)

    hl.on("window.close", function(window)
        if isObject(window) and window.address then opened[window.address] = nil end
    end)

    -- The default binds, for a config with none of them (see above).
    local MODIFIERS = {
        SUPER = "SUPER", WIN = "SUPER", LOGO = "SUPER", MOD4 = "SUPER", META = "SUPER",
        CTRL = "CTRL", CONTROL = "CTRL", ALT = "ALT", MOD1 = "ALT", SHIFT = "SHIFT",
    }
    local function comboOf(keys)
        local mods, key = {}, ""
        for token in keys:gmatch("[^+]+") do
            local name = token:gsub("%s", ""):upper()
            if MODIFIERS[name] then mods[#mods + 1] = MODIFIERS[name] elseif name ~= "" then key = name end
        end
        table.sort(mods)
        return table.concat(mods, "+") .. "+" .. key
    end
    local defaults = {
        { keys = mainMod .. " + CTRL + W", description = "Reserve workspace", made = reserveActions,
          action = function() return hl.dsp.window.reserve_workspace() end },
        { keys = mainMod .. " + Tab", description = "Next workspace", made = nextActions,
          action = function() return hl.dsp.workspace.next_on_hovered() end },
        { keys = mainMod .. " + CTRL + Tab", description = "New workspace", made = newActions,
          action = function() return hl.dsp.workspace.new_on_hovered() end },
    }
    for _, default in ipairs(defaults) do default.combo = comboOf(default.keys) end

    local bind = hl.bind
    hl.bind = function(keys, action, ...)
        for _, default in ipairs(defaults) do
            if action ~= nil and default.made and default.made[action] then default.bound = true end
            if type(keys) == "string" and comboOf(keys) == default.combo then default.used = true end
        end
        return bind(keys, action, ...)
    end
    local unbind = hl.unbind
    if unbind then
        hl.unbind = function(keys, ...)
            for _, default in ipairs(defaults) do
                if type(keys) == "string" and comboOf(keys) == default.combo then default.used = true end
            end
            return unbind(keys, ...)
        end
    end

    hl.on("config.reloaded", function()
        for _, default in ipairs(defaults) do
            if not default.used and not default.bound then
                local ok, err = pcall(bind, default.keys, default.action(), { description = default.description })
                if not ok then report("workspaces of their own", err) end
            end
        end
    end)
end)

--#######################################################################################
--## HOW APPS OPEN                                                                      #
--#######################################################################################
-- Settings > General > Windows: for each app picked there, how its windows look as
-- they open - tiled, floating (at a size, centered), maximized or fullscreen; how
-- see-through; with which animation. The shell keeps them in
-- ~/.config/quickshell/windowrules.json and writes them out as hypr/windowrules.lua -
--     return { { app = "kitty", layout = "float", width = 1500, height = 760 }, ... }
-- - read here once the config has loaded (loadfile, not require: see the top of this
-- file). A change there is handed over at once, through hyprctl eval, as
-- purpura.windowRules({ ... }).
--
-- Each app gets a rule of its own, on its windows' initial class. Hyprland adds a
-- named rule's effects to those it has rather than replacing them, so each change
-- makes its rules afresh, under new names, and turns the last ones off. kitty's
-- floating window comes pre-included there: until the shell's rules take over, it's
-- hyprland.lua's own "kittyrule", turned off once they do - kitty's among them. With
-- no windowrules.lua yet, nothing here changes anything.

part("how apps open", function()
    local FILE = os.getenv("HOME") .. "/.config/hypr/windowrules.lua"
    local LAYOUTS = { tile = true, float = true, maximize = true, fullscreen = true }
    -- Pop in from further than hyprland.lua.example's own default does (87%), so
    -- it's something else.
    local ANIMATIONS = { popin = "popin 60%", slide = "slide", gnomed = "gnomed" }
    local made, generation = {}, 0

    -- The class as Hyprland matches it: the whole of it, as it is.
    local function wholly(app)
        return "^(" .. (app:gsub("[%^%$%(%)%.%[%]%*%+%?{}|\\]", "\\%0")) .. ")$"
    end

    local function effectsOf(entry)
        local rule = {}
        if LAYOUTS[entry.layout] then rule[entry.layout] = true end
        if entry.layout == "float" then
            local w, h = tonumber(entry.width), tonumber(entry.height)
            if w and h and w >= 100 and h >= 100 and w <= 16384 and h <= 16384 then
                rule.size = string.format("%d %d", math.floor(w), math.floor(h))
                rule.persistent_size = false
            end
            if entry.center == true then rule.center = true end
        end
        local opacity = tonumber(entry.opacity)
        if opacity and opacity >= 0.1 and opacity < 1 then rule.opacity = string.format("%.2f", opacity) end
        if entry.animation == "none" then
            rule.no_anim = true
        elseif ANIMATIONS[entry.animation] then
            rule.animation = ANIMATIONS[entry.animation]
        end
        return rule
    end

    local function apply(list)
        if type(list) ~= "table" then error("not a list of apps", 0) end
        generation = generation + 1
        local old = made
        made = {}
        for i, entry in ipairs(list) do
            if type(entry) == "table" and type(entry.app) == "string" and #entry.app <= 128
                and entry.app:match("^[%w%._%+%- ]+$") then
                local rule = effectsOf(entry)
                if next(rule) ~= nil then
                    rule.name = "purpura-app-" .. generation .. "-" .. i
                    rule.match = { initial_class = wholly(entry.app) }
                    local ok, result = pcall(hl.window_rule, rule)
                    if ok and result ~= nil then made[#made + 1] = result end
                end
            end
        end
        for _, rule in ipairs(old) do pcall(function() rule:set_enabled(false) end) end
        -- hyprland.lua's own rule for kitty, from before kitty's was the shell's.
        pcall(hl.window_rule, { name = "kittyrule", enabled = false })
    end

    purpura = purpura or {}
    function purpura.windowRules(list)
        apply(list)
    end

    hl.on("config.reloaded", function()
        local present = io.open(FILE, "r")
        if not present then return end
        present:close()
        local chunk, err = loadfile(FILE)
        if not chunk then return report("how apps open", err) end
        local ok, list = pcall(chunk)
        if ok then ok, err = pcall(apply, list) else err = list end
        if not ok then report("how apps open", err) end
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
