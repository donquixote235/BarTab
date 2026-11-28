# BarTab 1.60.1.15: mail and bank, both ways

A /reload is enough after installing; no new files this time.

## New

- **Mail on arrival:** at a mailbox, BarTab offers to take everything from the letters your other characters sent with BarTab, in one go (or does it automatically). Other mail is left alone, and it stops if your bags fill up. `/bartab mail take` takes them now.
- **Put away at the bank:** after taking out what you need, BarTab offers to put away crafting materials none of your bars use (ore, herbs, cloth, leather, parts). It leaves anything your other characters need, and vendor-bought things like thread and vials. `/bartab bank put` offers again.
- **Bank windows:** taking out and putting away use a window like the mail one: untick items or change amounts. What you untick from putting away is remembered for next time.
- **Bag space warnings:** a chat message when your bags get down to 2 free slots and when they're full. Clicking a crafting bar with no room for what it makes says so instead of trying.

## Improved

- "Until I reach a skill level..." resizes a recipe's existing bars for the crafts needed, and they count down as you skill up ("Count down as you skill up" on the right-click menu).
- Bars working toward a skill level wait for the level before their "After crafting" rule, so running out of materials partway doesn't untrack them.
- At a vendor, the offer to buy again waits until you've used the last of the item.
- With "Send letters in one press", your craft key at a mailbox only mails while BarTab's mail window is showing, and crafts otherwise.

## Fixed

- "Until I reach a skill level..." left a recipe's existing bars at their old size.
- A stalled letter no longer keeps your craft key from crafting at the mailbox.
