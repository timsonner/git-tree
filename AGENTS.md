# Git Tree

Omarchy shell overlay for the git repository open in Files. Plugin id: `timsonner.git-tree`.

Do not edit `/usr/share/omarchy`. User plugins live in `~/.config/omarchy/plugins/`.

The overlay does not checkout a branch or write to the repository it is showing.

## Install

Requires Omarchy, Files (Folio), Hyprland with a Lua config, `git`, `jq`, and `hyprctl`.

```sh
omarchy plugin add https://github.com/timsonner/git-tree --enable --yes
```

That clones the plugin to `~/.config/omarchy/plugins/timsonner.git-tree/` and enables `timsonner.git-tree` in `~/.config/omarchy/shell.json`.

If that directory already exists and is a git checkout:

```sh
omarchy plugin update timsonner.git-tree --yes
omarchy plugin enable timsonner.git-tree
```

If the directory exists and is not a git checkout, it was copied by hand. Do not delete it unless asked. Copy the changed files into it, then restart the shell.

## Keys

`omarchy plugin add` does not install keys. Copy the Super+Ctrl+G bind from `bindings.snippet.lua` into `~/.config/hypr/bindings.lua`.

Super+Ctrl+G toggles the overlay only while a Files window is focused, or while the `timsonner-git-tree` layer is mapped. Leave it `auto_consuming` so the chord passes through otherwise. Do not bind Super+G. That chord is window grouping.

Escape may already be bound. Do not add a second Escape bind. If a dismiss function already consumes Escape, call `omarchy-shell timsonner.git-tree back` when `git_tree_mapped()` is true, then return before that function does its own work. Use the snippet's Escape bind only when Escape is not already bound.

`back` returns to the history when a commit is open. From a reviewed branch it returns to the current branch. The next press closes the overlay.

Then:

```sh
hyprctl reload
omarchy restart shell
```

`hyprctl reload` picks up the key. `omarchy restart shell` mounts the overlay. A later QML change stays invisible until the shell is restarted again. Saving the file is not enough.

## Check

```sh
omarchy plugin list
```

`timsonner.git-tree` should be enabled. Open a git repository in Files and press Super+Ctrl+G. The overlay lists local branches and recent commits. Esc steps back, then closes. The repository's checked-out branch does not change.

From the plugin source, `./validate` checks the manifest, the lane layout, and the folder rules. It does not need a running shell.
