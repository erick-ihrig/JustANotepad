# Just a Notepad

A minimal notepad for World of Warcraft: Forever. A movable, resizable text box with named page tabs that saves
as you type and fades into the background when you're not using it.

## What it does

- **Floats over your UI.** When the notepad isn't hovered or focused, the box, tabs and controls fade away and
  only your text is left. The eye control lets the text fade as well. An option keeps a faint border so you can still
  see where the box is.
- **Catches movement keys.** Hold a movement key while typing and the notepad stops typing and takes the held
  letters back (along with anything they replaced), so nothing is lost. The game doesn't let an addon start
  movement, so release the key and press it again to move.
- **Stays open.** Escape only stops typing. The notepad closes only from its close control, `/note`, the keybind
  or a launcher, and it reopens at login if it was open when you logged out.
- **Pages.** Named tabs in a thin row above the text. A page is either for all your characters or for one
  character only (those tabs are tinted in the class color). Left-click + for an all-characters page, right-click
  + for a character page. Right-click a tab to rename, move, convert or delete it.
- **To-do lines.** Add a to-do anywhere in a page (the checkmark control, or Ctrl+T). Tick its box to strike it
  through; hover it and click the red circle to delete it. Long to-dos wrap, indented under their first line.
  Highlight some text and right-click it to convert it into to-dos, one per line. Enter adds another to-do; Enter on an empty one goes
  back to ordinary text.
- **Small controls.** In line with the tabs: undo (Ctrl+Z), add a to-do (Ctrl+T), the eye and close. Under the
  bottom-left corner: search all pages (Ctrl+F), with a box that pops out beside the icon. Each control can be
  hidden in the settings.
- **Welcome page.** A new install opens with a short page explaining all of this. `/note welcome` adds it again.
- **Moving and resizing.** Drag a tab, the edge of the box or any empty space in it to move it; drag the
  bottom-right corner to resize it. Lock Window in the settings stops both.

## Commands

| Command | What it does |
| --- | --- |
| `/note` | Open or close the notepad |
| `/note settings` | Open the settings page |
| `/note reset` | Put the window back at its default position and size |
| `/note size 8-28` | Text size |
| `/note bg 0-100` | Background opacity |
| `/note welcome` | Add the welcome page again |

A keybind is under Key Bindings > AddOns > Just a Notepad.

## Credits

Made by Erick Ihrig. Built with AI assistance (Claude, by Anthropic).

Licensed under the MIT License.
