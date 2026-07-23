--######################
--## HYPRLAND PURPURA ##
--######################

-- https://wiki.hypr.land/Configuring/

-- You can split this configuration into multiple files
-- Create your files separately and then link them to this file like this:
-- source = ~/.config/hypr/myColors.conf

--#######################################################################################
--## LOCALS                                                                             #
--#######################################################################################

local terminal = "kitty"
local filemanager = "dolphin"
local menu = "rofi -show drun"
local browser = "flatpak run net.waterfox.waterfox"
local noteapp = "obsidian"
local mainMod = "SUPER" -- "META" key is main modifier

--#######################################################################################
--## AUTOSTART                                                                          #
--##                                                                                    #
--## https://wiki.hypr.land/Configuring/Basics/Autostart/                               #
--#######################################################################################

hl.on("hyprland.start", function()
hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
hl.exec_cmd("solaar --window hide")
hl.exec_cmd("hyprpaper")
hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
hl.exec_cmd("XDG_MENU_PREFIX=arch- kbuildsycoca6")
hl.exec_cmd("qs")
end)

--#######################################################################################
--## ENVIRONMENT VARIABLES                                                              #
--##                                                                                    #
--## https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/        #
--#######################################################################################

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- Switched from "kde" to "hyprqt6engine" so Qt6 apps pick up
-- hyprqt6engine.conf's color_scheme instead of needing a full Plasma
-- install. See ~/.config/hypr/hyprqt6engine.conf.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
-- Belt-and-suspenders alongside kdeglobals' [KDE] widgetStyle=kvantum:
-- strict KDE Frameworks apps (Kate) were still showing default/white
-- chrome even after that, which QT_STYLE_OVERRIDE forces regardless of
-- whether an app actually reads kdeglobals' widgetStyle key outside a
-- full Plasma session.
hl.env("XDG_MENU_PREFIX", "arch-")

--#######################################################################################
--## MONITORS                                                                           #
--##                                                                                    #
--## https://wiki.hypr.land/Configuring/Monitors/                                       #
--#######################################################################################
hl.monitor({
    output = "DP-1",
    mode = "1920x1080@144",
    position = "0x0",
    scale = "1",
})

hl.monitor({
    output = "DP-2",
    disabled = true,
})

--monitor=DP-2,1680x1050@60, -1680x300, 1
hl.monitor({
    output = "HDMI-A-1",
    disabled = true,
})

--#######################################################################################
--## PERMISSIONS                                                                        #
--##                                                                                    #
--## https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/                  #
--#######################################################################################

-- ecosystem {
--   enforce_permissions = 1
-- }

-- permission = /usr/(bin|local/bin)/grim, screencopy, allow
-- permission = /usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland, screencopy, allow
-- permission = /usr/(bin|local/bin)/hyprpm, plugin, allow

--#######################################################################################
--## VARIABLES/CONFIG                                                                   #
--##                                                                                    #
--## https://wiki.hypr.land/Configuring/Basics/Variables/                               #
--#######################################################################################

hl.config({
    general = {
        gaps_in = 4,
        gaps_out = 10,
        border_size = 2,
        col = {
            active_border = { colors = { "rgba(9600faff)", "rgba(9f38ffee)" }, angle = 45 },
          inactive_border = "rgba(6e00b8aa)",
        },
        -- Set to true enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        rounding_power = 0,
        -- Change transparency of focused and unfocused windows
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled = true,
          range = 4,
          render_power = 3,
          color = "rgba(1a1a1aee)",
        },
        blur = {
            enabled = true,
          size = 2,
          passes = 3,
          vibrancy = 0.1696,
          new_optimizations = true,
        },
    },
    animations = {
        enabled = "1",
    },
    dwindle = {
        preserve_split = true,
    },
    master = {
        new_status = "master",
    },
    misc = {
        force_default_wallpaper = 0, -- Set to 0 or 1 to disable the anime mascot wallpapers
            disable_hyprland_logo = true,
    },
    input = {
        kb_layout = "hr",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = -1, -- -1.0 - 1.0, 0 means no modification.
        touchpad = {
            natural_scroll = false,
        },
    },
})

--#######################################################################################
--## KEYBINDINGS                                                                        #
--##                                                                                    #
--## https://wiki.hypr.land/Configuring/Basics/Binds/                                   #
--#######################################################################################

hl.bind("mouse:276", hl.dsp.pass({ window = "initialclass:^(discord)$" }))

hl.bind(mainMod .. " + return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + backspace", hl.dsp.exec_cmd("~/.config/hypr/scripts/switchmon.sh"))
hl.bind(mainMod .. " + delete", hl.dsp.global("caelestia:session"))

hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(filemanager))
hl.bind(mainMod .. " + W", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + S", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(mainMod .. " + F11", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + L", hl.dsp.global("quickshell:lockscreen"))
hl.bind(mainMod .. " + delete", hl.dsp.global("quickshell:powermenu"))
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd(noteapp))

hl.bind(mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))

hl.bind(mainMod .. " + CTRL + 1", hl.dsp.window.move({ workspace = 1, follow = false }))
hl.bind(mainMod .. " + CTRL + 2", hl.dsp.window.move({ workspace = 2, follow = false }))
hl.bind(mainMod .. " + CTRL + 3", hl.dsp.window.move({ workspace = 3, follow = false }))
hl.bind(mainMod .. " + CTRL + 4", hl.dsp.window.move({ workspace = 4, follow = false }))
hl.bind(mainMod .. " + CTRL + 5", hl.dsp.window.move({ workspace = 5, follow = false }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize())

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

--#######################################################################################
--## RULES                                                                              #
--##                                                                                    #
--## https://wiki.hypr.land/Configuring/Basics/Window-Rules/                            #
--## https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/                         #
--#######################################################################################

-- SEND DISCORD AND ZAPZAP TO WORKSPACE 2
hl.window_rule({
    match = {
        class = "^(com.rtosta.zapzap|discord)$",
    },
    workspace = "2",
})

-- SEND AIMP TO WORKSPACE 3
hl.window_rule({
    match = {
        class = "^(Aimp)$",
    },
    workspace = "3",
})

-- FULLSCREEN IS PINK
hl.window_rule({
    name = "fullscreenrule",
    match = {
        fullscreen_state_internal = 1,
    },
    border_color = "rgb(F600FF)",
})

-- KITTY STARTS AS FLOATING WINDOW
hl.window_rule({
    name = "kittyrule",
    match = {
        initial_class = "^(kitty)$",
    },
    float = true,
    persistent_size = false,
    size = "1500 760",
})

-- Ignore maximize requests from all apps.
hl.window_rule({
    name = "suppress-maximize-events",
    match = {
        class = ".*",
    },
    suppress_event = "maximize",
})

-- Fix XWayland dragging
hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    -- Fix some dragging issues with XWayland
    no_focus = true,
})

-- Allow blur in Purpura Quickshell Lockscreen
hl.layer_rule({
    match = { namespace = "lockscreen" },
    blur = true,
})

-- Allow blur in Purpura Quickshell Powermenu
hl.layer_rule({
    match = { namespace = "powermenu" },
    blur = true,
})

hl.layer_rule({
    match        = { namespace = "rofi" },
    blur         = false,
    ignore_alpha = 0,
    dim_around      = 1
})

--#######################################################################################
--## ANIMATIONS                                                                         #
--##                                                                                    #
--## https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/                   #
--#######################################################################################

-- CURVES
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })


-- ANIMATIONS
hl.animation({
    leaf = "global",
    enabled = true,
    speed = 10,
    bezier = "default",
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 5.39,
    bezier = "easeOutQuint",
})
hl.animation({
    leaf = "windows",
    enabled = true,
    speed = 4.79,
    bezier = "easeOutQuint",
})
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 4.1,
    bezier = "easeOutQuint",
    style = "popin 87%",
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 1.49,
    bezier = "linear",
    style = "popin 87%",
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 1.73,
    bezier = "almostLinear",
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 1.46,
    bezier = "almostLinear",
})
hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 3.03,
    bezier = "quick",
})
hl.animation({
    leaf = "layers",
    enabled = true,
    speed = 3.81,
    bezier = "easeOutQuint",
})
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 4,
    bezier = "easeOutQuint",
    style = "fade",
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 1.5,
    bezier = "linear",
    style = "fade",
})
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 1.79,
    bezier = "almostLinear",
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 1.39,
    bezier = "almostLinear",
})
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 1.94,
    bezier = "almostLinear",
    style = "fade",
})
hl.animation({
    leaf = "workspacesIn",
    enabled = true,
    speed = 1.21,
    bezier = "almostLinear",
    style = "fade",
})
hl.animation({
    leaf = "workspacesOut",
    enabled = true,
    speed = 1.94,
    bezier = "almostLinear",
    style = "fade",
})
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 7,
    bezier = "quick",
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

hl.device({
    name = "logitech-g703-lightspeed-wireless-gaming-mouse-w/-hero",
    sensitivity = 0,
    accel_profile = "flat",
})
