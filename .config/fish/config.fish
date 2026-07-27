set -g fish_greeting
set -g fish_key_bindings fish_hybrid_key_bindings

setterm --linewrap on

if status is-interactive
# Commands to run in interactive sessions can go here
end

function fish_greeting
    fastfetch
end
