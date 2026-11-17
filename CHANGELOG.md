# Changelog

## Unreleased
- Fixed: the box for renaming a tab now grows to fit the name as you type, instead of staying as narrow as the tab (a new page's tab is only one number wide).

## 1.2.0

- New: locking the notepad now also lets clicks go through it to the game, so you can't click into it by accident. Lock and unlock it with the new lock control at the top-left (left of the tabs), the Lock Window setting or `/note lock`. While locked, only the lock control and the to-do checkboxes take clicks (the checkboxes stop too if the text is set to fade out completely), and hovering shows only the lock control.
- New: shift-click an item, spell or quest while typing to put its link in your note, like in chat. Click a link to see it (not while locked); it deletes as one piece. Search finds the link's name, not its hidden data.
- New Hide in Combat option (Settings > Window): the notepad hides when combat starts and comes back when it ends.
- New settings control (gear) with the other controls at the top-right. It can be hidden like the others.
- The monospace font is now on by default for new installs. Existing settings are kept.
- The welcome page covers links, the lock and the settings control.
- Removed the Keep the Border When Faded option.
- Fixed: a note with only one line couldn't be highlighted, and clicking into a to-do always put an invisible cursor at the start of its text.
- Fixed: turning on Monospace Font could leave the notes in the normal font.
- Fixed: after changing the text size, switching pages could leave the text laid out wrongly until the window was resized.

## 1.1.0

- Fixed: the blinking cursor didn't show in to-do lines.
- New Monospace Font option (Settings > Look, or `/note mono`): every character takes the same width, so columns, lists and spacing line up. Uses the bundled DejaVu Sans Mono.
- New pages are numbered with the lowest number not already in use, so renaming page 1 and adding a page gives a new 1. All-character pages and character pages are numbered separately.

## 1.0.1

- Fixed: the text and cursor in to-do lines didn't show (typing and ticking still worked). This also affected text converted into to-dos.

## 1.0.0

First public release.

- A text box that floats over your UI. When it isn't hovered or focused, the box, tabs and buttons fade out and only your text is left; the eye button makes the text fade too. An optional faint border can stay, with a slider for how visible it is.
- Saves as you type, with undo (Ctrl+Z) and search across all pages (Ctrl+F).
- Pages for all your characters or for one character only: left-click + for one, right-click + for the other. Right-click a tab to rename, move, convert or delete it.
- To-do lines anywhere in a note (checkmark button or Ctrl+T): tick to strike through, hover to delete, long ones wrap under their own indent. Highlight text and right-click it to convert it into to-dos, one per line.
- Holding a movement key while typing stops typing and takes back the letters it typed. Press the key again to move.
- Escape only stops typing; it never closes the notepad. It reopens at login if it was open when you logged out.
- Drag it by a tab, its edge or any empty space; resize from the corner; lock it in place. Choose which buttons show, the text size and the background opacity.
- Opens with a welcome page on a new install (`/note welcome` adds it again). Optional minimap button, Escape-menu button and addon compartment entry, plus a keybind.
