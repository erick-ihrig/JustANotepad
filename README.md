# Just a Notepad

A minimal notepad for World of Warcraft: Forever. A movable, resizable text box with named page tabs that saves
as you type and fades into the background when you're not using it.

## What it does

- **Floats over your UI.** When the notepad isn't hovered or focused, the box, tabs and controls fade away and
  only your text is left. The eye control lets the text fade as well.
- **Stays open.** Escape only stops typing. The notepad closes only from its close control, `/note`, the keybind
  or a launcher, and it reopens at login if it was open when you logged out.
- **Pages.** Named tabs in a thin row above the text. Right-click a tab to rename, move or delete it.
  Pages can be shared by all characters or kept per character.
- **Small controls in line with the tabs.** Search all pages (Ctrl+F; the search box opens under the
  bottom-left corner), undo (Ctrl+Z), insert your location (Ctrl+L), the eye and
  close. Each can be hidden in the settings.
- **Moving and resizing.** Drag the margin around the text, a tab or the empty part of the tab row to move it; drag the bottom-right corner to
  resize it. Lock Window in the settings stops both.

## Commands

| Command | What it does |
| --- | --- |
| `/note` | Open or close the notepad |
| `/note settings` | Open the settings page |
| `/note reset` | Put the window back at its default position and size |
| `/note size 8-28` | Text size |
| `/note bg 0-100` | Background opacity |

A keybind is under Key Bindings > AddOns > Just a Notepad.

## Credits

Made by Erick Ihrig. Built with AI assistance (Claude, by Anthropic).

Licensed under the MIT License.
