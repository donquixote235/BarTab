# BarTab 1.60.1.11: bar layouts, one-press mail

A /reload is enough after installing; no new files this time.

## New

- **Three ways to show recipe bars:** right-click a profession's heading in BarTab: Crafting, or set the default with the Recipe bars button (Display tab in `/bartab config`).
  - **One per ingredient**, as before.
  - **One per material:** "Peacebloom 2 / 3" for every tracked recipe that uses it, which keeps a long list of small recipes (alchemy, cooking) short. Click it to pick a recipe, Shift-click to craft the first one that's ready, Alt-click to craft everything that's ready, one recipe after another.
  - **One per recipe:** "Minor Mana Potion: 1 / 3 materials", filling as you gather any of its ingredients. Blue is what you can craft now; orange is waiting on something else, such as vials.
- **Vendor-bought ingredients are hidden:** vials, thread, flux and the like no longer get bars of their own or count on material and recipe bars. BarTab still buys them for you at vendors. Tick "Show vendor-bought materials on recipe bars" (Display tab) to bring them back.
- **Send letters in one press:** tick it under Mailbox (Shopping tab). Clicking Mail in BarTab's prompt sends the first letter, and your BarTab craft key sends each one after. The game allows one letter per click or key press.
- **Mail all I have of each:** a checkbox in the mail prompt sends everything you have spare of a material, not just what the other character is short.

## Improved

- When a recipe can't be crafted, clicking its bar says what's missing ("missing Empty Vial (0 / 1, sold by vendors)").
- Letters to your other characters have no body text, so they disappear once you take the items.
- Ctrl-drag reorders recipe and material bars; Ctrl-click a recipe bar's name opens the recipe.
- Tracking a recipe with just its main ingredient no longer picks a vial or thread as the main one.

## Fixed

- Mailing skipped items in your reagent bag, so a letter could go out without them.
- The craft-next key ignored recipes shown as material bars.
- After a stop rule ended one recipe of an Alt-click "craft everything ready", the next recipe didn't start, and the next click said "Stopped crafting".
- An error at profession trainers ("Missing on/off parameter").
