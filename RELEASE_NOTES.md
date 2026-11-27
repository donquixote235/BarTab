# BarTab 1.60.1.12: whole recipes, better mail

A /reload is enough after installing; no new files this time.

## New

- **Also track its other ingredients:** right-click a recipe bar to add bars for the ingredients it doesn't track yet ("Also track its other ingredients (Linen Cloth)"), sized and set up like the bars it has.
- **Whole recipes for your other characters:** mailing and the "For your other characters" bars count every ingredient of a tracked recipe, not just the ones with bars, so the Linen Cloth for a Copper Mace shows up even when only its Copper Bar is tracked.

## Improved

- Making materials first says what will still be missing ("toward 1 Copper Mace (still missing 2 Linen Cloth)") and that clicking the bar again stops it.
- Material and recipe bars use the same colors as ingredient bars: blue for what you can craft now, orange for whole crafts waiting on another ingredient, and the plain fill for part of a craft.
- Mail uses one attachment per item where it can (postage is per attachment), splitting from a bigger stack or merging small ones first.

## Fixed

- Making a material in another profession first (smelting Copper Bar for a Copper Mace) could do nothing; with another profession's window open, BarTab now says to close it.
- Mailing part of a stack sent the whole stack.
- "Mail all I have of each" gave all the extra to the first character; it's shared out evenly now.
- With "Send letters in one press", the craft key typed into the letter instead of sending it.
- Tracking a recipe could take over a "For your other characters" bar.
