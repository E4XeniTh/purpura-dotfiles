--#######################################################################################
--## PURPURA                                                                            #
--##                                                                                    #
--## The shell's side of Hyprland - what the shell needs from it, kept out of the       #
--## personal hyprland.lua so that one stays yours and this one stays current.          #
--#######################################################################################
--
-- Installed and updated with the dotfiles (~/.config/hypr/purpura.lua), along with
-- workspace.lua beside it, which this file runs: the workspaces and the bar's workspace
-- widget's side of things (see WORKSPACES AND THE WORKSPACE WIDGET below). hyprland.lua
-- runs this one with one line, at the start of its binds:
--
--     pcall(loadfile(os.getenv("HOME") .. "/.config/hypr/purpura.lua") or function() end, mainMod)
--
-- Before the binds, since Close Window works by replacing the action every close bind is
-- made from, a maximize bind is checked by No maximizing a window on its own here,
-- dropping a window on a workspace (workspace.lua) makes its binds along with every
-- "Drag window" bind made after it, and "Next unmanaged workspace" and "Send window to
-- empty workspace" are actions made there. (The mainMod handed over is only for the
-- default binds made there for a hyprland.lua without them - see A workspace of its own
-- in workspace.lua.) loadfile rather than require: Hyprland watches each file require
-- loads and reloads the whole config when one changes - an update of this file would put
-- the monitors back to hyprland.lua's MONITORS rule. And a missing or broken file leaves
-- hyprland.lua loading as if the line weren't there.
--
-- Each part below runs on its own: should one fail (a Hyprland update renaming
-- something it uses), a notification says which, and the rest still load.

local handedOver = ...
local mainMod = type(handedOver) == "string" and handedOver ~= "" and handedOver or "SUPER"

-- A notification of what failed, in which file (workspace.lua's too).
local function reporter(file)
    return function(name, err)
        pcall(hl.notification.create, {
            text = file .. ", " .. name .. ": " .. tostring(err),
            duration = 15000,
            icon = "error",
        })
    end
end
local report = reporter("purpura.lua")

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
--## WORKSPACES AND THE WORKSPACE WIDGET                                                #
--#######################################################################################
-- In workspace.lua, beside this file: a window dropped on a workspace in the bar's
-- workspace widget or grabbed from it, the book of every workspace, and the workspaces
-- of their own, with Next unmanaged workspace and Send window to empty workspace. Run
-- here, where it makes its binds and actions in time (see the top of this file) - with
-- loadfile, as this file is, so an update of it reloads nothing either - and handed what
-- the two share. Its parts run on their own, as these do; should the file be missing or
-- not load at all, a notification says so, and the rest of this file still loads.

part("workspace.lua", function()
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local source = info and info.source or ""
    local dir = source:match("^@(.*/)[^/]*$") or ((os.getenv("HOME") or "") .. "/.config/hypr/")
    local chunk, err = loadfile(dir .. "workspace.lua")
    if not chunk then error(err, 0) end
    chunk({
        mainMod = mainMod,
        reporter = reporter,
        isObject = isObject,
        pair = pair,
        contains = contains,
        windowUnderCursor = windowUnderCursor,
    })
end)

--#######################################################################################
--## NO MAXIMIZING A WINDOW ON ITS OWN                                                  #
--#######################################################################################
-- A window that's the only one on its workspace isn't let be maximized. A maximize bind
-- (one made with hl.dsp.window.fullscreen({ mode = "maximized" }), as
-- hyprland.lua.example's META + W and Settings > Shortcuts' Maximize are) does nothing
-- on one, though it still takes one that's maximized out of it. Maximized any other
-- way (the app itself asking, or a window rule, Settings > General > Windows'
-- "maximized" among them), it's taken back out a moment later; and one left on its
-- own while maximized, the others there closed or moved off, comes out of it too.
-- Fullscreen (the whole monitor) is left be, and so are special workspaces. A window
-- being picked up from the workspace widget is off its workspace for the moment (see
-- Grabbing), so nothing's looked at again till it's put down. An app that maximizes
-- itself again and again is let be after TRIES goes in TRIES_S seconds, rather than
-- fought.

part("no maximizing a window on its own", function()
    local NAME = "no maximizing a window on its own"
    local GRABBED = "purpura-grabbed" -- dropping a window on a workspace's: one picked up
    local RETRY_MS = 250
    local TRIES, TRIES_S = 3, 2

    local function alone(window)
        local workspace = isObject(window) and window.workspace
        return isObject(workspace) and not workspace.special and workspace.windows == 1
    end

    -- The binds (see above): each maximize action as it's made, with what it was made
    -- with, so hl.bind can tell one.
    local maximizes = setmetatable({}, { __mode = "k" })
    local makeFullscreen = hl.dsp.window.fullscreen
    hl.dsp.window.fullscreen = function(opts, ...)
        local action = makeFullscreen(opts, ...)
        if action ~= nil and type(opts) == "table" and opts.mode == "maximized" and opts.action ~= "unset" then
            maximizes[action] = opts
        end
        return action
    end
    local bind = hl.bind
    hl.bind = function(keys, action, ...)
        local opts = action ~= nil and maximizes[action]
        if opts then
            local maximize = action
            action = function()
                local ok, err = pcall(function()
                    local window = type(opts.window) == "string" and hl.get_window(opts.window) or hl.get_active_window()
                    if isObject(window) and (window.fullscreen or 0) == 0 and alone(window) then return end
                    hl.dispatch(maximize)
                end)
                if not ok then report(NAME, err) end
            end
        end
        return bind(keys, action, ...)
    end

    -- Every other way: looked at a moment after anything that could have changed it.
    local scheduled = false
    local tries = {} -- by address: { n, since } - how often it's been taken out lately

    local function grabbing(windows)
        for _, window in ipairs(windows) do
            for _, name in ipairs(window.tags or {}) do
                if name == GRABBED then return true end
            end
        end
        return false
    end

    local look
    local function soon(ms)
        if scheduled then return end
        scheduled = true
        hl.timer(function()
            scheduled = false
            local ok, err = pcall(look)
            if not ok then report(NAME, err) end
        end, { timeout = ms or 1, type = "oneshot" })
    end

    look = function()
        local windows = hl.get_windows({ mapped = true })
        if grabbing(windows) then return soon(RETRY_MS) end
        local now = os.time()
        for _, window in ipairs(windows) do
            if window.fullscreen == 1 and window.address and alone(window) then
                local t = tries[window.address]
                if not t or now - t.since > TRIES_S then t = { n = 0, since = now } end
                if t.n < TRIES then
                    t.n = t.n + 1
                    tries[window.address] = t
                    hl.dispatch(hl.dsp.window.fullscreen({
                        mode = "maximized", action = "unset", window = "address:" .. window.address,
                    }))
                end
            end
        end
    end

    for _, event in ipairs({ "window.open", "window.fullscreen", "window.move_to_workspace" }) do
        hl.on(event, function() soon() end)
    end
    hl.on("window.close", function(window)
        if isObject(window) and window.address then tries[window.address] = nil end
        soon()
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
