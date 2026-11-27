# BarTab 1.60.1.13: smarter sharing

A /reload is enough after installing; no new files this time.

## New

- **One bar per recipe by default:** professions you haven't set show one bar per recipe ("Minor Mana Potion: 1 / 3 materials"). Change the default with the Recipe bars button (Display tab in `/bartab config`), or one profession from its heading's right-click menu.
- **All ingredients ticked:** tracking a new recipe ticks every ingredient except vendor-bought ones (vials, thread).
- **One step down for your characters:** a character short of something they can make needs its materials too. Ein, short of Copper Bar and able to smelt, needs Copper Ore, so another character is offered to mail the ore. The character mailing keeps what it would smelt for its own recipes.

## Improved

- Recipe bars share what you carry between recipes in list order, like ingredient bars, so one Rough Grinding Stone counts for only one recipe.
- Making materials first goes by the recipe's own share, and "Can't craft" messages say when recipes above it use the material.

## Fixed

- Opening another profession's window mid-batch left BarTab thinking it was still crafting, so the next click stopped instead of carrying on.
