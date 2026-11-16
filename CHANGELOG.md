# Changelog

## Unreleased

- Fixed: a note with only one line couldn't be clicked into or highlighted until it had a second line.
- Fixed: turning on Monospace Font could leave the notes in the normal font.

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
