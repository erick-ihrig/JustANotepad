# The invisible cursor

*16 November 2026, fixed in 1.2.0*

This bug took three releases and three different fixes. The real fix turned out to be deleting code, not adding it.

## The symptoms

In 1.0.0, text in a to-do line was invisible: you could type, and the text was saved, but nothing showed. In 1.0.1 I fixed that, and a new problem appeared: in to-dos, the blinking cursor was invisible. Then two more turned up:

- A note with only one line couldn't be highlighted. Dragging across it did nothing, while two-line notes worked fine.
- Clicking anywhere in a to-do put the cursor at the very start of its text, invisibly, no matter where you clicked.

## Attempt one: give the box the right height

The invisible text looked like a text box squashed too small to show anything. So the addon worked out how tall each to-do should be (number of wrapped lines × the height of a line) and set it. The text came back. The cursor didn't.

## Attempt two: measure better

Maybe the height was slightly wrong. The cursor's own height can be read when it moves, so the addon learned the real line height from that and fed it into the calculation. The cursor still didn't show. Adding a little extra room made things worse: now you couldn't place a cursor in to-dos at all.

## Finding out what was really happening

Guessing wasn't working, so I added a temporary debug command, `/note clickdebug`, that printed exactly what happened on each click: which box it landed on, whether that box got focus, where the cursor ended up, and the box's height alongside the measured line height.

On a one-line note, the output showed:

- the click landed on the right box, and that box got focus,
- the cursor was at position 0 (the start), not where I clicked,
- the box was 22 pixels tall, the measured line was 20, and the game's own cursor height was 16.

Three different numbers for "one line". The addon was setting the box to its idea of the right height, and the game had its own idea.

## The real cause

The game sizes multi-line text boxes to fit their text. Every time the addon set a height, the game resized the box back on the next change, the addon set it again, and so on, on every click and every cursor move. Caught in the middle of that, the game reset the cursor to the start and stopped drawing it.

Two-line notes worked because they were already taller than the minimum the addon enforced, so it never touched them.

## The fix: stop helping

The fix was to never set the height of a text box at all. The game sizes the boxes; the addon only sizes the rows around them (a to-do row is the text box plus a little padding, and the checkbox sits beside its first line). Strike-through lines and checkbox positions use the game's own line height once it's known.

All four symptoms went away at once. The original invisible-text bug didn't come back either, which suggests it was the same fight all along.

## What I kept from this

- **Don't fight the client.** If the game manages something, read it, don't set it.
- **Measure before guessing.** One debug command that printed real numbers did more than two releases of educated guesses. It was removed again once the bug was fixed.
- **Lock the lesson into the tests.** The offline tests now fail if the addon ever sets a text box's height.
