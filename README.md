# BarTab

Progress bars in the objective tracker for what you're collecting: crafting
materials, quest items, and fill-up crates. Built for WoW Forever.

## What it does

BarTab adds up to three sections to the objective tracker ("All Objectives"),
each split into subsections:

| Section | Subsections | Bars |
| --- | --- | --- |
| **BarTab: Quests** | One per zone, then Unknown/Other, then Inactive | Items your quests ask for |
| **BarTab: Crafting** | One per profession, then Other, then Inactive | Materials, usually tied to a recipe |
| **BarTab: Items** | One per fill-up item | Bundles that fill items like Waylaid Crates |

A section only appears when it has something to show.

### Crafting

- Track a material for a recipe and the bar is labeled with what you're making
  ("Hillman's Cloak: 3 / 5 Heavy Leather"), sized to one craft.
- Colored blocks show crafts you can make now (blue) and crafts held back by
  another ingredient (orange), in a color-blind friendly palette.
- Click a bar to craft, even with the profession window closed. By default:
  click crafts 1, Shift-click crafts as many as fit the bar, Alt-click crafts
  all you can (configurable).
- The tooltip shows the recipe's full shopping list, plus how many you have in
  your bank, Warband bank and on your other characters.
- When several bars use the same material, it's shared out in list order
  (configurable).
- A BarTab button on the profession window's recipe panel tracks any of the
  selected recipe's ingredients in one click.
- "Focus on" (right-click) shows just one ingredient of a recipe.
- Hovering an item you track anywhere adds a line per bar, e.g. "BarTab: 4/5 for Hillman's Cloak" (on/off in settings).
- At a vendor that sells materials your Crafting bars are short of, BarTab offers to buy them (or buys them automatically, or does nothing: Vendors in settings). It never spends more than your per-visit limit (1g by default). Untick "Buy materials at vendors" on a bar's right-click menu to leave that recipe out.
- "Also track how to make <item>" (right-click) adds bars for the recipe that makes a material you can craft, sized to what you're short.
- "After crafting" (right-click) can move a recipe's bar to Inactive or untrack it once you've crafted the recipe.
- "Stop tracking" (right-click) untracks a recipe's bars at a skill level, or when the recipe turns yellow, green or gray. Tick "Ask before removing" to be asked first.

### Quests

- Item objectives are tracked automatically when you accept a quest, once the
  quest has something you can use (its own item, or pieces that combine).
- Quests made of pieces (pages bound into chapters) show progress per piece,
  e.g. "1 / 4 pages", read from the items' tooltips.
- Click a Ready bar to use the quest item (not in combat).
- Optionally, bars appear right under their quest in Blizzard's quest tracker.

### Fill-up items (Waylaid Crates)

- Detected automatically when one reaches your bags; one bar per accepted
  bundle ("20 Light Leather", "40 Linen Cloth").
- Split stacks are combined for you, and one click fills the crate.
- "Focus on" (right-click) shows just one bundle.

### Everything else

- Goal alerts: a chat message, optional chime, and an on-screen or
  raid-warning style message when a bar fills.
- Each character has its own bars; `/bt copy <character>` copies another
  character's.
- Right-click bars and headings for options (assign, inactive, untrack...);
  Ctrl-drag to reorder.

## Getting started

1. Open a profession, select a recipe, and click the BarTab button next to the
   favorite star. Pick an ingredient.
2. Or type `/bt help` for a quick guide with examples.
3. `/bt config` (or the minimap button) opens the settings.

## Commands

| Command | What it does |
| --- | --- |
| `/bt help` | Quick guide with examples |
| `/bt config` | Settings window |
| `/bt track <item> [max \| min-max]` | Track an item, e.g. `/bt track Light Leather 20` |
| Alt-Shift-click an item | Track it: works in bags, chat links, the auction house and loot. Fill-up items are added right away; for anything else, pick Item (Items section), Crafting material, or the open recipe if it uses the item, and set a goal. |
| `/bt session reset` | Start the session stats over. Each bar's tooltip shows what you've gained since login (bank withdrawals excluded), the rate per hour, and about how long until the bar fills. |
| `/bt window auto\|on\|off\|reset\|lock\|unlock` | BarTab's own window: automatic (when the objective tracker is hidden), always, never, or back to its starting spot |
| `/bt craft` | Craft the next ready bar (also a key binding: "BarTab: Craft the next ready bar" in Key Bindings > AddOns) |
| `/bt share` | A text string of all your bars to paste to a friend or another account. Right-click a bar or heading to share just those. |
| `/bt import` | Opens a box to paste a shared string; adds those bars (ones you already have take the shared range). |
| `/bt assign <item> [min-max]` | Track a material for the recipe selected in your profession window |
| `/bt unassign <name>` | Remove a bar's recipe |
| `/bt untrack <name>` | Remove a bar (asks for the recipe name if several match) |
| `/bt copy <character>` | Copy another character's bars to this one |
| `/bt quests` | Add item bars for quests already in your log |
| `/bt item <name>` | Add a fill-up item (like a Waylaid Crate) by hand |
| `/bt auto on\|off` | Track quest items when accepting a quest |
| `/bt autoitems on\|off` | Track fill-up items when they reach your bags |
| `/bt inline on\|off` | Show quest bars under their quests in Blizzard's tracker (experimental, off by default: it can stop other quests in the tracker from updating) |

Shift-clicked item links work anywhere a name is expected.

## Settings

`/bt config`, the minimap button, the addon button by the minimap clock, or
Options > AddOns > BarTab. Covers: which sections show, quest and item
auto-tracking, bar height, text size, color sets (color-blind friendly,
classic, high contrast), what each click does, shared materials, Inactive
collapse, bank/alt counts, minimap button, and goal alerts.

## Notes and limits

- If the objective tracker is hidden (some addons replace it with their own quest tracker), BarTab shows its sections in its own window instead (drag a section heading to move it; width and a lock are in settings). Change this with "Show in" in settings or `/bt window auto|on|off|reset`.
- Using quest items and filling crates goes through a secure click button, so
  it doesn't work during combat (a game rule).
- Alt counts appear once you've logged into that character with BarTab.
- "Show quest bars under their quests" (off by default) works inside Blizzard's
  quest tracker layout. On Forever that can stop other quests in the tracker
  from updating; if it does, turn it off.
- Crafting with the profession window closed uses the same approach as the
  QuickCraft Forever addon: the profession is loaded without its window when
  you hover or click a bar, and closed again afterward.

## Files

| File | Contents |
| --- | --- |
| `BarTab.lua` | Core: saved data, item counting, recipes, tooltips, bank/alt counts |
| `QuestItems.lua` | Quest item state, pieces that combine, fill-up items |
| `Crafting.lua` | Crafting from bars |
| `Tracker.lua` | Tracker sections, bar layout, shared materials, alerts, reordering |
| `Actions.lua` | Assign/untrack, right-click menus, profession window button |
| `Quests.lua` | Quest and crate import, click-to-use buttons, inline quest bars |
| `Settings.lua` | Settings window, minimap button |
| `Bindings.xml` | The "Craft the next ready bar" key binding |
| `Commands.lua` | Help, slash commands, events, per-character lists |

All files share one private namespace (see the top of `BarTab.lua`).
Saved data: `BarTabDB` (bars, per character) and `BarTabSettings` (settings
and bank/alt snapshots, account-wide).

## License

MIT, see `LICENSE`. Copyright (c) 2026 Quixotic Software.
