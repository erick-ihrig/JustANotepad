# Just a Notepad

A minimal notepad for World of Warcraft: Forever. It's a text box that floats over your UI; when you're not using it, everything fades away except your text.

## Features

- **Fades out of the way.** When the notepad isn't hovered or focused, the box, tabs and buttons fade out and only your text is left. Turn on the eye button and the text fades too.
- **Pages for everyone or for one character.** Left-click **+** for a page all your characters see, right-click **+** for a page only this character sees. Right-click a tab to rename, move, convert or delete it.
- **To-do lines anywhere in a note.** Add one with the checkmark button or Ctrl+T. Highlight text and right-click it to convert it into to-dos.
- **Item, spell and quest links.** While typing, shift-click an item, spell or quest to put its link in your note, just like in chat. Click the link later to see it.
- **Saves as you type,** with undo (Ctrl+Z) and search across all pages (Ctrl+F).
- **Catches movement keys.** Hold a movement key while typing and the notepad stops typing and takes the stray letters back, so nothing you wrote is lost. Press the key again to move.
- **Out of the way when you want it.** Drag it by a tab, its edge or any empty space; resize it from the corner. Lock it with the lock button and clicks go straight through it to the game, so you never click into it by accident. It can also hide or lock itself in combat. Choose which buttons show, the text size and the background opacity. Notes use a monospace font by default, so lists and columns line up; you can switch to the game's normal font.

## Getting started

Type `/note` to open or close the notepad. A new install opens with a short welcome page explaining the basics.

| Command | What it does |
| --- | --- |
| `/note` | Open or close the notepad |
| `/note settings` | Open the settings |
| `/note reset` | Put the window back at its default position and size |
| `/note size 8-28` | Text size |
| `/note bg 0-100` | Background opacity |
| `/note lock` | Lock or unlock (clicks go through it while locked) |
| `/note mono` | Monospace font on or off |
| `/note welcome` | Add the welcome page again |

A keybind is under Key Bindings > AddOns > Just a Notepad.

## Download and feedback

Download on CurseForge: https://www.curseforge.com/projects/1804445

Report issues or suggest features: https://github.com/erick-ihrig/JustANotepad/issues

Design notes and dev log: [docs](docs/README.md)

## Credits

Made by Erick Ihrig. Built with AI assistance (Claude, by Anthropic). MIT licensed.

The monospace font is DejaVu Sans Mono, included unmodified under its own license (`Fonts/LICENSE-DejaVu.txt`).
