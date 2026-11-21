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
-- bind is made from, and dropping a window on a workspace makes its binds along with
-- every "Drag window" bind made after it. (The mainMod handed over isn't needed any
-- more - those binds go wherever "Drag window" is.) loadfile rather than require:
-- Hyprland watches each file require loads and reloads the whole config when one
-- changes - an update of this file would put the monitors back to hyprland.lua's
-- MONITORS rule. And a missing or broken file leaves hyprland.lua loading as if the
-- line weren't there.
--
-- Each part below runs on its own: should one fail (a Hyprland update renaming
-- something it uses), a notification says which, and the rest still load.

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
    -- Last, where the separators between one monitor's boxes and the next's span: the
    -- window stays hidden there too, though there's nothing to drop it on - so it
    -- doesn't flash up between two boxes.
    purpura = purpura or {}
    function purpura.dropTargets(monitor, boxes, between)
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
    end

    -- The bar the cursor's on: its monitor, and the cursor in the bar's coordinates.
    local function barUnderCursor(cursor)
        for _, bar in ipairs(hl.get_layers({ namespace = "bar" })) do
            local monitor = bar.monitor
            if bar.mapped and monitor and contains(bar.x, bar.y, bar.w, bar.h, cursor) then
                return monitor, cursor.x - bar.x, cursor.y - bar.y
            end
        end
        return nil
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

    local function press()
        endDrag() -- one whose release never came
        local cursor = hl.get_cursor_pos()
        if not cursor or grab(cursor) then return end
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
    -- "purpura-drag,mod,<monitor>" a moment after the modifier goes down (so a quick
    -- META + key shortcut doesn't flash it up), again whenever the cursor moves to
    -- another monitor, and as "purpura-drag,mod," once it's let go.
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
    local modShown       -- the monitor posted, while the widget's shown for it
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
        if modShown then
            modShown = nil
            dragEvent("mod,")
        end
    end

    local function modTick()
        -- A release that never came (the session switched away, say) lets it go
        -- after as long as a drag gets.
        if not modHeld() or os.time() - modSince > FOLLOW_FOR_S then return modHide() end
        modTicks = modTicks + 1
        if modTicks < MOD_DELAY_TICKS then return end
        local monitor = hl.get_monitor_at_cursor()
        local name = monitor and monitor.name
        if name and name ~= modShown then
            modShown = name
            dragEvent("mod," .. name)
        end
    end

    local function modSide(side, down)
        sideDown[side] = down
        if not modHeld() then return modHide() end
        if modWatching then return end
        modWatching, modTicks, modSince = true, 0, os.time()
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
        bind(keys, press, { non_consuming = true })
        bind(keys, function() drop() end, { drag = true })
        bind(keys, function()
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

    local bind = hl.bind
    hl.bind = function(keys, action, ...)
        if type(keys) == "string" and action ~= nil and drags[action] and not along[comboKey(keys)] then
            local ok, err = pcall(bindAlong, bind, keys, comboKey(keys))
            if ok then along[comboKey(keys)] = true else report("dropping a window on a workspace", err) end
        end
        return bind(keys, action, ...)
    end

    local unbind = hl.unbind
    if unbind then
        hl.unbind = function(keys, ...)
            if keys == "all" and select("#", ...) == 0 then
                along, comboMods = {}, {}
                modHide()
            elseif type(keys) == "string" then
                local key = comboKey(keys)
                along[key], comboMods[key] = nil, nil
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
