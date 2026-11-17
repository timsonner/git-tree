# AGENTS.md

Instructions for AI agents that install, update, or remove Git Tree for a user, and for agents changing this repo. README.md has the user-facing detail.

## Ground rules

- `omarchy plugin add` installs and enables the overlay only. It does not edit Hyprland. Do not copy bindings as part of that command.
- Keys live in `bindings.snippet.lua`. Offer them after the plugin is installed. Copy or merge them into `~/.config/hypr/bindings.lua` only after the user agrees. Tell them what changes: Super+Ctrl+G toggles the overlay while Files is focused or the overlay is open, and passes through otherwise. Super+G stays window grouping. Do not bind it.
- Escape may already be bound. Do not add a second Escape bind. If the user agrees to Escape and a dismiss function already consumes it, call `omarchy-shell timsonner.git-tree back` when `git_tree_mapped()` is true, then return before that function does its own work. Add the snippet's Escape bind only when Escape is free and the user agrees.
- Back up `~/.config/hypr/bindings.lua` before you edit it.
- Never use sudo. Never edit `/usr/share/omarchy` or anything under `$OMARCHY_PATH`.
- Do not pass `--yes` to `omarchy plugin add`, `update`, or `remove` unless the user has already agreed to that exact command. Those commands ask before they change the machine. Plugins run unsandboxed inside the shell.
- The overlay does not checkout a branch or write to the repository it is showing.

## Install

1. Add the plugin and let the command ask the user:

   ```sh
   omarchy plugin add https://github.com/timsonner/git-tree --enable
   ```

   That clones the plugin to `~/.config/omarchy/plugins/timsonner.git-tree/` and enables `timsonner.git-tree` in `~/.config/omarchy/shell.json`.

   If that directory already exists and is a git checkout, run `omarchy plugin update timsonner.git-tree`, then `omarchy plugin enable timsonner.git-tree`. If it exists and is not a git checkout, do not delete it unless asked.

2. Ask whether they want the shortcut. If they agree, back up `bindings.lua`, check current binds with `omarchy menu keybindings --print`, and append the Super+Ctrl+G bind from `bindings.snippet.lua`. Skip lines that are already there. If Super+Ctrl+G is already bound to something else, ask before replacing it. Use `o.rebind` only when they want the replacement, and tell them which action it replaces.

3. Ask separately about Escape, and follow the ground rules.

4. If you changed Hyprland config:

   ```sh
   hyprctl reload
   hyprctl configerrors
   ```

   `hyprctl configerrors` must print nothing.

5. Restart the shell so the overlay mounts:

   ```sh
   omarchy restart shell
   ```

   A later QML change stays invisible until the shell is restarted again. Saving the file is not enough.

6. Ask the user to open a git repository in Files. If they installed the key, they press Super+Ctrl+G. Without the key, summon with `omarchy-shell shell summon timsonner.git-tree '{}'`.

## Update

```sh
omarchy plugin update timsonner.git-tree
```

The update shows the diff and asks before it applies. It only refreshes the plugin folder. If `bindings.snippet.lua` changed, offer to update the user's binds. Do not edit `bindings.lua` unless they agree. Then run `hyprctl reload`, `hyprctl configerrors`, and `omarchy restart shell` if anything changed.

## Uninstall

Follow the Uninstall section of README.md. Remove only the Git Tree binds, and keep the user's own.

In `~/.config/hypr/bindings.lua`:

- Remove `toggle_git_tree` and its Super+Ctrl+G `o.bind`.
- Remove `git_tree_mapped` if nothing else calls it.
- If Escape was bound only for Git Tree, remove that dismiss function and its `o.bind`.
- If an existing dismiss function calls `omarchy-shell timsonner.git-tree back`, remove that check and leave the rest of the function.

Then, after the user agrees:

```sh
omarchy plugin remove timsonner.git-tree
hyprctl reload
omarchy restart shell
```

`omarchy plugin remove` disables the plugin first. A git checkout is deleted. A hand-copied folder with no git repo is moved to a timestamped backup in the plugins directory, not deleted outright. Removing the plugin does not restore keys by itself, because those lines live in the user's config.

## Changing this repo

- Run `./validate` before you commit. It includes `omarchy plugin validate`.
- Do not add em dashes or en dashes to docs.
- The overlay does not checkout a branch, commit, or change any file in the repository it shows.
