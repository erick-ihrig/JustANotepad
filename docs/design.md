# Design

## What it's for

Just a Notepad is a text box that floats over the game. It isn't meant to be a window you manage; it's meant to be text that's simply there when you look for it. When you're not using it, the box, tabs and buttons fade away and only your words are left on screen.

Every feature is judged against that idea. If something adds a permanent visual element, or asks you to think about the notepad when you'd rather think about the game, it needs a very good reason.

## The rules it follows

1. **Nothing covers the text.** Tabs and buttons sit in a thin row above the box, never on top of it. The search button sits below the bottom-left corner for the same reason.
2. **It never closes by accident.** Escape only stops typing. The notepad closes only with the close button, `/note`, the keybind or a launcher, and it reopens at login if it was open when you logged out.
3. **Your text is never lost.** Everything saves as you type. Deleting a page asks first (unless it's empty) and can be undone. The movement-key catch exists for the same reason (see below).
4. **Quiet by default.** The minimap button is off by default. Every button can be hidden. There's one look, not a theme picker.
5. **Behave like the game already does.** Links act like they do in chat. Shift-click inserts them, the same as typing in the chat box. When the game has a convention, follow it.

## Decisions and why

### Escape never closes the notepad
Most WoW windows close with Escape. Here, Escape is the natural way to stop typing and get back to the game, and closing on top of that would hide your notes the moment you finished writing. So the notepad isn't registered as a special frame, and Escape only drops the keyboard focus.

### To-dos live inside the text
I considered a separate checklist section, or separate to-do pages. In the end, to-do lines can go anywhere in a note, mixed with ordinary text. A page is a list of blocks, and each block is either a stretch of text or a single to-do. Ticked items stay where they are, greyed and struck through, rather than jumping to the bottom. Highlighting lines and right-clicking turns them into to-dos, one per line.

### Two kinds of page
Some notes belong to the account ("Gold", "Raid times") and some to one character ("Pets", "Quests for this alt"). Left-click **+** makes an all-character page; right-click **+** makes one only this character sees, tinted in the class colour. Both kinds sit in the same tab row, all-character first. New pages are named with the lowest unused number for their kind, so renaming "1" means the next new page is "1" again.

### The lock and click-through are one feature
I first had a plain "lock position" setting, then wanted a click-through mode so I couldn't click into the notepad by accident while playing. There was no good reason for them to be separate: if the window is fixed in place, you also don't want it catching clicks. Locked now means fixed in place and click-through. See [One lock, not two](devlog/2026-11-16-one-lock.md).

### Monospace by default
Notes are often lists, prices and little tables. A monospace font makes columns line up without effort, so it's on by default for new installs (the bundled DejaVu Sans Mono). Existing installs keep whatever they had.

## Edge cases

- **Movement keys while typing.** If you start typing and then try to walk, the W you're holding types "wwwww" into your note. The notepad watches for a key that's bound to movement being held (for half a second, or three repeats). When it sees one, it puts the page back as it was before the key went down, drops the undo steps those letters made, and stops typing. Press the key again to move. It can't start the movement for you: addons aren't allowed to move your character.
- **Shift-clicking outside the notepad.** Normally, clicking outside stops typing. Shift-click is how you add a link, so a shift-click leaves the typing where it is; otherwise the link would arrive after the notepad had already let go.
- **Searching notes with links in them.** A link's hidden data (item IDs, colour codes) is part of the saved text. Search blanks those parts out first, keeping every position the same, so searching "19019" doesn't match an item ID, but searching the item's name does.
- **Strike-through lines on wrapped to-dos.** A ticked to-do that wraps needs one strike line per visible line, each the right length. The notepad simulates the game's word wrap to measure them, and keeps a link's words together so it doesn't break a link apart while measuring.
- **Checkboxes while locked.** When locked, only the lock and the to-do checkboxes take clicks, so you can still tick things off. If the text is set to fade out completely, the checkboxes stop taking clicks too, so there's never an invisible thing catching your clicks.
- **Links while locked.** Links in text take clicks on their own, separately from the text box, so the lock has to turn them off as well.
- **Hide in combat versus your own choice.** If you open or close the notepad by hand during combat, that wins: combat ending won't reopen something you closed, or hide something you opened.
- **Scrolling.** The page only scrolls when the cursor's line has actually left the visible area, and only by as much as needed. Pressing Enter, wrapping, or backspacing to a previous line doesn't move it.

## Limits of the WoW client

- **Addons can't start movement.** That's why the movement-key catch asks you to press the key again.
- **New files need a full restart.** The game only sees files that existed when it started, so a new font or texture won't load after `/reload`.
- **Fonts load late.** A font file is loaded a moment after it's first requested, so checking a font's measurements in the same frame you set it gives wrong answers. Checks happen a second or so later instead.
- **The game sizes multi-line text boxes itself.** Setting their height from addon code makes the addon and the game fight, which breaks the cursor. See [The invisible cursor](devlog/2026-11-16-invisible-cursor.md).

## How it's tested

Every build is tested in game before release. Alongside that, there's a set of offline tests that run the addon in plain Lua 5.1 against a fake version of the WoW API. The fake imitates the details that have caused bugs before, like fonts loading late, the game resizing text boxes, and frames passing clicks to their children. One test fails if the addon ever sets a text box's height, so that bug can't quietly come back.

## Ideas and roadmap

Not planned yet, but being considered:

- "Untick all" and "Remove ticked to-dos" in a tab's right-click menu, for reusable checklists.
- Sharing pages with other players, and sending a page to chat.

Possible, but not something I feel a need for: restoring an earlier version of a page, beyond this session's undo.

## Credits

- Inspired by MyNotepad by Foofi.
- Monospace font: DejaVu Sans Mono, under the Bitstream Vera license (included in `Fonts/`).
- Built with AI assistance (Claude, by Anthropic).
