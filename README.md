# purpura-dotfiles

Hyprland + Quickshell dotfiles. Sharp corners, translucent black panels, purple accents.

## New install

```bash
cp -r .config/hypr .config/quickshell ~/.config/
```

### Lock screen password check

The lock screen (`quickshell/components/Lock.qml`) authenticates against your real
Linux account via PAM, using a small helper binary so the shell process itself
never touches `/etc/shadow`.

```bash
cd ~/.config/quickshell/helpers
make
sudo cp ../pam.d/quickshell-auth /etc/pam.d/quickshell-auth
```

No setuid bit needed on the helper: `pam_unix` already delegates the shadow read
to the setuid-root `unix_chkpwd`, same as `su`/i3lock/swaylock.

Re-run `make` after pulling changes to `helpers/auth.c` — the compiled binary is
gitignored since it's machine-specific.
