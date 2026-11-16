-- Git Tree (timsonner.git-tree)
--
-- Drop this into ~/.config/hypr/bindings.lua (that file is already loaded).
-- Super+Ctrl+G toggles the branch history while Files is focused, or while
-- the overlay is already open. Anywhere else the chord is left alone.
-- Super+G stays Omarchy's window grouping chord.
--
-- If NittyGriddy already binds Escape, do not bind Escape again. Add the
-- git_tree_mapped() check to that dismiss function instead.

local function git_tree_mapped()
  local layers = hl.get_layers({ namespace = "timsonner-git-tree" })
  return layers ~= nil and #layers > 0
end

local function folio_focused()
  local window = hl.get_active_window()
  if not window then
    return false
  end
  local class = string.lower(window.class or "")
  local initial = string.lower(window.initial_class or window.initialClass or "")
  return class == "folio" or initial == "folio"
end

local function toggle_git_tree()
  if not git_tree_mapped() and not folio_focused() then
    return { ok = false }
  end
  hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell toggle timsonner.git-tree '{}'"))
end

o.bind_commands[toggle_git_tree] = "omarchy-shell shell toggle timsonner.git-tree"
o.bind("SUPER + CTRL + G", "Git history in Files", toggle_git_tree, { auto_consuming = true })

-- fcitx5's input-method grab sits in front of the overlay, so the overlay
-- never sees Escape. Hyprland runs this bind first. Consume the key only
-- while Git Tree is mapped. back returns to the history when a commit is
-- open, and hides the overlay otherwise.
local function dismiss_git_tree()
  if not git_tree_mapped() then
    return { ok = false }
  end
  hl.dispatch(hl.dsp.exec_cmd("omarchy-shell timsonner.git-tree back"))
end

o.bind_commands[dismiss_git_tree] = "omarchy-shell timsonner.git-tree back"
o.bind("ESCAPE", "Git Tree dismiss", dismiss_git_tree, { auto_consuming = true })
