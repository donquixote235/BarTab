# Changelog

## 1.5

- Key binding "BarTab: Craft the next ready bar" (Key Bindings > AddOns), also `/bt craft` for macros: crafts the first active recipe bar that can craft now, as a plain click would.
- Settings window reorganized into tabs (General, Crafting, Quests & Items, Display) and made narrower; it opens on the tab you last used.
- BarTab window: width setting (180-400) and a Lock window checkbox in settings (also `/bt window lock|unlock`).
- Item tooltips: hovering an item you track anywhere (bags, bank, auction house, loot, vendors, chat links, profession reagents) adds a line per bar that counts it, e.g. "BarTab: 4/5 for Hillman's Cloak". On/off in settings (Look).
- Vendor materials: at a vendor that sells something your Crafting bars are short of (thread, dye, vials...), including ingredients of tracked recipes that have no bar of their own, BarTab asks whether to buy it, with the amounts and total cost. In settings (Vendors) you can have it buy automatically or turn it off. Only gold purchases, capped at the vendor's stock, your money, and a per-visit spend limit (1g by default; set it in settings). Anything over the limit is left out, and BarTab says what. To leave a recipe (or bar) out, untick "Buy materials at vendors" on its right-click menu.
- Recipe chains: when a bar's material is something you can craft (Heavy Leather from Medium Leather), its tooltip says so and the right-click menu offers "Also track how to make Heavy Leather". That adds bars for the recipe that makes it, sized to what the bar is still short, just above it in the list. BarTab learns your recipes whenever a profession loads.
- Profession headings in BarTab: Crafting show your skill level on the right (e.g. Leatherworking  139/150), updated as you skill up.
- Quest bars under their quests ("inline", /bt inline) are now off by default and marked experimental: they work inside Blizzard's quest-tracker layout, which on Forever could stop quests listed below them from updating. Quest bars show in the BarTab: Quests section instead. Turned off once for everyone; turn it back on in settings if you want it.
- Own window when the objective tracker is hidden (for example by an addon with its own quest tracker): BarTab shows its sections in a window of its own, with the same bars, clicks and menus, and moves back into the tracker when it returns. Drag a section heading to move the window. "Show in" in settings or `/bt window auto|on|off|reset`.
- "After crafting" on a recipe bar's right-click menu: keep the bar (default), move it to Inactive, or untrack it once you've crafted the recipe. Works for crafts from a bar or the profession window, after the whole batch finishes. Shared bar strings carry the choice.
- "Stop tracking" on a recipe bar's right-click menu: untrack the recipe's bars once its profession reaches a skill level (e.g. Hillman's Shoulders at Leatherworking 125), or once the recipe turns yellow, green or gray. Colors are checked whenever the profession is loaded (hovering a bar or opening the window). Shared bar strings carry it. "Ask before removing" in the same menu asks first; No keeps the bars and turns the rule off.

## 1.4

- Alt-Shift-click any item (bags, chat links, auction house, loot) to track it. Fill-up items are added right away; anything else opens a small window where you pick Item (Items section), Crafting material, or the open recipe if it uses the item, and set a goal. The bag's "how many" box that Shift opens is closed automatically.
- Session stats in bar tooltips: how many you've gained since login or /reload, the rate per hour, and about how long until the bar fills at that pace. Items taken from the bank don't count. `/bt session reset` starts over.
- Share bar setups as text: `/bt share` (or Share bars in settings, or "Share this bar" / "Share these bars" on the right-click menus) gives a string to paste to a friend; `/bt import` (or Import bars) adds bars from one. Bars you already have take the shared range. Quest and fill-up bars aren't shared.

## 1.3

- Per-character bar lists. Existing bars went to the first character to log in;
  `/bt copy <character>` copies another character's bars.
- Tooltips show bank, Warband bank and alt counts, with alts' full names
  (WoW Forever surnames) in class colors.
- "Track in BarTab" button on the profession window's recipe panel, beside the
  favorite star.
- "Focus on" for recipes with several ingredient bars, like crates have.
- Right-click "Assign to <recipe>" names the recipe and only appears when that
  recipe uses the material.
- Settings: choose what Click, Shift-click and Alt-click do on recipe bars.
- Shared materials: bars using the same material share it in list order
  (default), or count all of it with or without a tooltip warning.
- Goal alerts can use a raid-warning style message.
- High-contrast color set is now cyan/magenta.
- Settings window is two columns so it fits smaller screens.
- Fixed: assigning a material could take over a crate's bar (and existing
  mix-ups are repaired at login).
- Fixed: alt snapshots were wiped at logout.

## 1.2

- Split the single file into eight files sharing a private namespace (fixes
  hitting Lua's 200-local limit).
- Goal-reached alerts with optional chime, on-screen message and a Test
  button.

## 1.1

- Settings window (`/bt config`), Options > AddOns page, minimap button,
  addon compartment entry and icon.
- `/bt help` quick guide.
- Fill-up items (Waylaid Crates): bars per bundle, automatic stack combining,
  one-click fill, "Focus on" a bundle.
- Crafting with the profession window closed.
- Pieces that combine into quest objectives (pages into chapters), with
  per-piece progress read from tooltips.
- Bars show what a recipe makes ("Hillman's Cloak"); one bar per recipe and
  material.
- Shopping-list tooltips for multi-ingredient recipes.
- Quest bars can appear under their quests in Blizzard's tracker.
- Quests only show when they have a usable item.

## 1.0 (as ItemTrack)

- Track item counts as bars in the objective tracker, sections per profession
  and per quest zone, Inactive areas, assign recipes, click to craft,
  Ctrl-drag to reorder, right-click menus, color-blind friendly colors.
- Renamed from ItemTrack to BarTab, with `/bt` replacing `/it`.
