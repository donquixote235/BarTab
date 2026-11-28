# BarTab

Progress bars in the objective tracker for what you're collecting: crafting
materials and fill-up crates. Craft straight from the bars, and
let BarTab shop for what's missing at vendors and the auction house. Built for
WoW Forever.

## What it does

BarTab adds up to two sections to the objective tracker ("All Objectives"),
each split into subsections:

| Section | Subsections | Bars |
| --- | --- | --- |
| **BarTab: Crafting** | One per profession, then Other, then Inactive | Materials, usually tied to a recipe |
| **BarTab: Items** | One per fill-up item, then Other | Bundles that fill items like Waylaid Crates, and anything else you're collecting |

A section only appears when it has something to show.

### Crafting

- Track a material for a recipe and the bar is labeled with what you're making
  ("Hillman's Cloak: 3 / 5 Heavy Leather"), sized to one craft.
- Colored blocks show crafts you can make now (blue) and crafts held back by
  another ingredient (orange), with a line between crafts, in a color-blind
  friendly palette.
- Three layouts per profession (right-click its heading): a bar per
  ingredient, one per material ("Peacebloom 2 / 3", for every recipe that
  uses it), or one per recipe ("Minor Mana Potion: 1 / 3 materials").
  Vendor-bought ingredients (vials, thread) stay off the bars.
- Click a bar to craft, even with the profession window closed. By default:
  click crafts 1, Shift-click crafts as many as fit the bar, Alt-click crafts
  all you can (configurable).
- Chain crafting: short of a material one of your recipes makes? A click makes
  it first, then the recipe, several steps deep (Medium to Heavy to Thick
  Leather). Only vendor items missing? It makes the rest and the vendor prompt
  offers them. Not enough for even one? It makes what it can toward the bar.
  Otherwise it says what's missing, one step down the chain. Automatic, ask
  first, or only from the bar's menu; optionally using your other professions.
- A lighter stretch after what you have shows how much more the materials in
  your bags could make, with an alert when it's enough for the rest of the bar.
- Recipe difficulty next to a bar's name: the profession window's skill-up
  arrows (or the name in the recipe's color, or nothing).
- The tooltip shows the recipe's full shopping list, plus how many you have in
  your bank and on your other characters.
- When several bars use the same material, it's shared out in list order
  (configurable).
- A BarTab button on the profession window's recipe panel (with a check mark
  while the selected recipe has bars). Its menu:
  - Track all ingredients, Track one ingredient (a submenu), or "Track with
    settings..." to pick the ingredients and set the recipe up (crafts,
    After crafting, Stop tracking, Count down) in one window.
  - Make until I have... and Make until I reach a skill level....
  - Its bars (once the recipe has some): Crafts, Rules (After crafting, Stop
    tracking, Count down as you craft) for all of its bars at once, and
    Untrack this recipe.
  - More: What to craft next..., the profit calculator and recently removed bars.
- Tracked recipes have a check mark beside them in the profession window's
  recipe list (on/off in settings).
- "Focus on" (right-click) shows just one ingredient of a recipe.
- Hovering an item you track anywhere adds a line per bar, e.g. "BarTab: 4/5 for Hillman's Cloak" (on/off in settings).
- At the auction house, a BarTab tab on the right edge opens a list of what your bars are short of, with a Search button for each (on/off in settings). Inactive bars are left out unless you tick "Include Inactive bars in the list".
- At a vendor that sells materials your Crafting bars are short of, BarTab offers to buy them (or buys them automatically, or does nothing: Vendors in settings). It never spends more than your per-visit limit (1g by default). Untick "Buy materials at vendors" (right-click a bar, Rules) to leave that recipe out.
- "Track more > How to make <item>" (right-click) adds bars for one craft of the recipe that makes a material you can craft (Alt-click it for everything you're short); handy as a gathering target, since chain crafting makes it for you anyway.
- At your bank, BarTab offers to take out what your bars are short of, only as much as you need (`/bartab bank`), then to put away crafting materials none of your bars use (`/bartab bank put`). Both use a window where you untick items or change amounts; what you untick from putting away is remembered.
- At a mailbox, BarTab offers to take everything from the letters your other characters sent with BarTab (`/bartab mail take`); other mail is left alone.
- At a vendor, BarTab offers to sell what you crafted that no bar or other character needs (`/bartab sell`): common quality only unless you include uncommon (green) and better, with food, potions and crafting tools unticked to start and an option to keep a stack of each. What you untick is remembered.
- Crafted green (and better) gear no bar uses is offered in the mail window to your character with Enchanting, to disenchant (Characters settings: which character, or nobody).
- The mail window remembers what you untick; "Mail all I have of each" applies to that time only.
- Bag space warnings: a chat message when your bags get down to 2 free slots and when they're full; a crafting bar with no room for what it makes says so instead of trying.
- Profit calculator (`/bartab profit`): what each of the open profession's recipes earns sold to a vendor or at auction (after the cut), counting your materials and missing ones your way; sort by profit per craft, per hour, or in total. What to craft next (`/bartab next`): the same list ranked by what a skill point costs, or takes.
- Training reminders: when a profession reaches its limit (75, 150, 225) and needs the next rank, and when recipes you saw at a trainer come within reach.
- Optional: the profession window's "Track Recipe" checkbox opens BarTab's Track with settings window instead of the game's own tracking.
- "Rules > After crafting" (right-click) can move a recipe's bar to Inactive or untrack it once you've crafted the recipe.
- "Rules > Count down as you craft" (right-click, or a default in settings; off unless you turn it on): each craft takes one craft's worth off the recipe's bars, so 8/32 Bolt of Linen Cloth for 8 Red Linen Bags becomes 4/28 after one craft rather than 4/32. When the count runs out, the After crafting rule applies; with "keep the bar" they move to Inactive at full size, ready for next time.
- "Make until I reach..." (same button) sets a recipe up to craft until your skill reaches a level: pick which ingredients to track, sized at one craft per skill point still needed, with "Stop tracking at skill" at that level. The bars shrink only when a craft gives you a skill point ("Count down as you skill up" on the right-click menu), and running out of materials partway leaves them in place. Click a bar to craft; the batch stops and the bars clear when you get there.
- "Make until I have..." (the BarTab button in the profession window, or `/bartab make 52` with the recipe selected) adds a bar for what the recipe makes, in place of the recipe's ingredient bars. Its clicks craft only what's still missing, and a Create All batch stops once you have that many. Crafts on a bar's right-click menu switches a recipe between ingredient bars, a goal for what it makes, and a skill level.
- "Crafts" (right-click a recipe bar) sizes the recipe's bars for 1, 5 or 10 crafts, or for the crafts it takes to reach the next multiple of 5 in the profession (at 162: 3 crafts, to 165), or to use all of that bar's material you have (37 Heavy Leather at 8 a craft: 4 crafts).
- "Rules > Stop tracking" (right-click) untracks a recipe's bars at a skill level, or when the recipe turns yellow, green or gray. Tick "Ask before removing" to be asked first.
- Recipe items (patterns, plans, formulas...) for recipes you haven't learned can be Alt-Shift-clicked the same way, at a vendor or in your bags; their tooltip says so. (In the auction house window that click opens the item's listings instead, so the line isn't shown there.) Open each profession once so BarTab knows its recipes.
- At a profession trainer, Alt-Shift-click a recipe (or select it and type `/bartab trainer`) to track its ingredients before you've learned it. Its bars wait in Inactive, marked "(not learned)", and become active when you learn the recipe.
- Favorite recipes: with a profession open, `/bartab favorites` (or Import favorites in settings) tracks its starred recipes that aren't tracked yet, one craft each; a window lets you take the main ingredients or all of them, or choose for each recipe. Optionally, starring a recipe asks which of its ingredients to track.
- Appearances (optional, off by default): recipes that make gear with an appearance you haven't collected get bars for one craft, untracked after crafting. By default a window asks which ingredients to track, with the main one (the one needed most) ticked; you can switch to "main ingredient only" or "every ingredient" in settings. When several recipes turn up at once (usually the first time), one summary window lists them: track them all (main ingredients, or tick ALL INGREDIENTS), choose each, skip all, or decide later. "Add appearance bars to Inactive" keeps them out of the way until you move one up. Checked when you learn a recipe or open a profession; each recipe is offered once, and skipped if you already have one crafted (bags, bank or an alt). Only orange and yellow recipes unless you include the rest. Crafting doesn't collect an appearance, so BarTab reminds you to equip or disenchant the result. Bars for an appearance you collect some other way are untracked automatically.

### Fill-up items (Waylaid Crates)

- Detected automatically when one reaches your bags; one bar per accepted
  bundle ("20 Light Leather", "40 Linen Cloth").
- Split stacks are combined for you, and one click fills the crate.
- A crate's tooltip (in your bags) says whether BarTab is tracking it; Alt-Shift-click it to track one you untracked. Crates in the bank aren't tracked; their tooltip says to move them to your bags first.
- "Focus on" (right-click) shows just one bundle.

### Everything else

- Goal alerts: a chat message, optional chime, and an on-screen or
  raid-warning style message when a bar fills.
- Each character has its own bars; `/bartab copy <character>` copies another
  character's.
- Removed bars (by a rule, a goal or Untrack) can be brought back with
  `/bartab undo`, or "Recently removed" on the profession window's BarTab button.
- Right-click bars and headings for options (assign, inactive, untrack...);
  Ctrl-drag to reorder; Ctrl-click a recipe bar to open its recipe in the
  profession window (also "Open recipe" on the right-click menu).

## Getting started

1. Open a profession, select a recipe, and click the BarTab button next to the
   favorite star. Pick an ingredient.
2. Or type `/bartab guide` for the full user's guide, or `/bartab help` for a quick guide (`/bartab help crafting`, `goals`, `profit`, `shopping`, `items`, `bars` for more).
3. `/bartab config` (or the minimap button) opens the settings.

## Commands

Every command starts with `/bartab`, or the shorter `/btab`. `/bt` works too
unless another addon (such as an action bar addon) already uses it.

| Command | What it does |
| --- | --- |
| `/bartab help [topic]` | Quick guide: an overview, then `crafting`, `goals`, `profit`, `shopping`, `items` or `bars` |
| `/bartab guide [section]` | The user's guide: every feature, section by section (also the settings window's title bar, or right-click the minimap button) |
| `/bartab config` | Settings window |
| `/bartab track <item> [max \| min-max]` | Track an item, e.g. `/bartab track Light Leather 20` |
| Alt-Shift-click an item | Track it: works in bags, the bank, chat links and loot (not in the auction house window, where that click opens the item's listings). Fill-up items are added right away; for anything else, pick Item (Items section), Crafting material, or the open recipe if it uses the item, and set a goal. |
| `/bartab session` | What you've crafted, gained in skill, gathered and spent since you logged in (`/bartab session last` for the session before; a summary of it shows at login). |
| `/bartab session reset` | Start the session stats over. Each bar's tooltip shows what you've gained since login (bank withdrawals excluded), the rate per hour, and about how long until the bar fills. |
| `/bartab window auto\|on\|off\|reset\|lock\|unlock` | BarTab's own window: automatic (when the objective tracker is hidden), always, never, or back to its starting spot |
| `/bartab craft` | Craft the next ready bar (also a key binding: "BarTab: Craft the next ready bar" in Key Bindings > AddOns) |
| `/bartab share` | A text string of all your bars to paste to a friend or another account. Right-click a bar or heading to share just those. |
| `/bartab import` | Opens a box to paste a shared string; adds those bars (ones you already have take the shared range). |
| `/bartab assign <item> [min-max]` | Track a material for the recipe selected in your profession window |
| `/bartab unassign <name>` | Remove a bar's recipe |
| `/bartab untrack <name>` | Remove a bar (asks for the recipe name if several match) |
| `/bartab undo` | Bring back the bars removed last (by a stop rule, a goal, or Untrack). `/bartab undo list` shows the last 10; `/bartab undo 3` brings back the third |
| `/bartab refresh` | Redraw BarTab's tracker sections if they stop updating (saves details for bug reports) |
| `/bartab errors [clear]` | Show (or clear) the last few errors BarTab caught, for bug reports |
| `/bartab copy <character>` | Copy another character's bars to this one |
| `/bartab item <name>` | Add a fill-up item (like a Waylaid Crate) by hand |
| `/bartab profit` | The profit window: with a profession open, which recipes earn the most sold to a vendor or at auction, counting your materials and missing ones the way you choose (`/bartab profit list` prints the short version in chat) |
| `/bartab bank` | At the bank: offer again to take out what your bars are short of |
| `/bartab mail` | At a mailbox: offer again to mail your other characters what their bars need |
| `/bartab mail take` | At a mailbox: take everything from BarTab letters your other characters sent |
| `/bartab bank put` | At the bank: offer again to put away materials none of your bars use |
| `/bartab sell` | At a vendor: offer again to sell what you crafted that nothing needs |
| `/bartab restock` | What your bars are short of, grouped by where to get it: your bank, your other characters, making it, gathering it, a vendor, the auction house |
| `/bartab ask` | Ask your other characters for what they have that you're short of; they're offered it at their next mailbox (or bank), even if their own bars would keep it |
| `/bartab next` | What to craft next: the profit window sorted by what a skill point costs (after selling what you make), for the open profession. With none open, it opens yours (asks which if you have several; `/bartab next first aid` picks one) |
| `/bartab make <count>` | Craft the selected recipe until you have that many (adds a bar for what it makes) |
| `/bartab trainer` | At a profession trainer: track the selected recipe (waits in Inactive until learned) |
| `/bartab favorites` | Track the open profession's favorite (starred) recipes |
| `/bartab appearances on\|off` | Track recipes for appearances you haven't collected |
| `/bartab appearances scan` | Ask again now about recipes you put off with Later |
| `/bartab autoitems on\|off` | Track fill-up items when they reach your bags |

Shift-clicked item links work anywhere a name is expected.

## Settings

`/bartab config`, the minimap button, the addon button by the minimap clock, or
Options > AddOns > BarTab. Six tabs:

| Tab | Settings |
| --- | --- |
| **General** | Which sections show, Inactive collapse, bank/alt counts, minimap button, alerts (goal reached, enough to make the rest, sound, on-screen style), reset / share / import / untrack all |
| **Crafting** | What each click does, making materials first (automatic / ask / menu only, other professions), count down as you craft, shared materials |
| **Shopping** | Vendor buying (ask / automatic / off, spend limit, only for crafts your bars cover), selling crafts (ask / automatic / off, greens, keep a stack), bank withdraw and put away (ask / automatic / off), the auction house tab |
| **Recipes** | Recipe list check marks, training reminders, "Track Recipe" in BarTab, import favorite recipes, track when you favorite, appearance recipes (which ingredients, Inactive, which colors) |
| **Items** | Fill-up item auto-tracking, stack combining |
| **Display** | Bar height, text size, color sets (color-blind friendly, classic, high contrast), recipe difficulty marking, item tooltip lines, BarTab's own window (when to show it, width, lock, position) |

## Notes and limits

- If the objective tracker is hidden (for example by an addon with its own quest tracker), BarTab shows its sections in its own window instead (drag a section heading to move it; width and a lock are in settings). Change this with "Show in" in settings or `/bartab window auto|on|off|reset`.
- Filling crates goes through a secure click button, so
  it doesn't work during combat (a game rule).
- Alt counts appear once you've logged into that character with BarTab.
- Crafting with the profession window closed works by loading the profession
  without its window when you hover or click a bar, and closing it again
  afterward.

## Files

| File | Contents |
| --- | --- |
| `BarTab.lua` | Core: saved data, item counting by ID, recipes, tooltips (bars and items), bank/alt counts |
| `QuestItems.lua` | Fill-up items (crates), stack combining, item helpers |
| `Crafting.lua` | Crafting from bars, chain crafting, craft-next key, after-crafting and stop rules, undo, training reminders, recipe chains, vendor buying, bank withdraw, auction house tab, prices |
| `Tracker.lua` | Tracker sections, BarTab's own window, bar layout, shared materials, session stats, alerts, reordering |
| `Actions.lua` | Assign/untrack, right-click menus, profession window button, Alt-Shift-click tracking, sharing |
| `Quests.lua` | Fill-up item import, click-to-use buttons (crates) |
| `Settings.lua` | Settings window, minimap button |
| `Profit.lua` | The profit window and "what to craft next" |
| `Guide.lua` | The user's guide window and the login tip |
| `Bindings.xml` | The "Craft the next ready bar" key binding |
| `Commands.lua` | Help, slash commands, events, per-character lists |

All files share one private namespace (see the top of `BarTab.lua`).
Saved data: `BarTabDB` (bars, per character) and `BarTabSettings` (settings
and bank/alt snapshots, account-wide).

## License

MIT, see `LICENSE`. Copyright (c) 2026 Quixotic Software.
