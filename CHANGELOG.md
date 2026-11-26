# Changelog

## 1.60.1.3

- "Track with settings..." on the profession window's BarTab button opens the ingredients window with the recipe's settings below it: how many crafts to size the bars for (with a button for the next skill tier), After crafting, Stop tracking (at a skill level or a recipe color), and Count down as you craft. Track creates the bars already set up. If the recipe already has bars, the window starts from their settings, and Track applies the new ones to all of them.
- Tracked recipes get a check mark at the right end of their row in the profession window's recipe list. Turn it off with "Mark tracked recipes in the profession window" on the Crafting tab in settings.
- BarTab now redraws its sections whenever another tracker section (Quests, All Objectives) collapses or expands, so they follow it.
- Sometimes the whole tracker stops laying itself out, leaving BarTab's sections stuck with a gap above them until a /reload. `/bartab refresh` (out of combat) now also asks the tracker to lay itself out again, and its saved details now include where each section sits, to help track down the cause.
- The ingredients window's title now says what it's for (track recipe, make until I reach, trainer recipe, favorite recipe), not always "new appearance".

## 1.60.1.2

BarTab's version now follows WoW Forever's (1.60.1), plus a number for BarTab's own releases. 1.6 was the first public release (1.60.1.1).

- Make until you reach a skill level: "Make until I reach..." on the profession window's BarTab button asks for a level (the next multiple of 5 by default), then which ingredients to track (the main one ticked; tick the rest for all of them), sized at one craft per skill point still needed. The bars get "Stop tracking at skill" at that level; click one to craft, and the batch stops and the bars clear themselves when you get there. The bars resize with your skill rather than counting down: a craft that gives a skill point shrinks them by one craft, and one that doesn't leaves them as they are. Picking a size from the Crafts submenu switches them back to normal bars.
- Make until you have N: "Make until I have..." on the profession window's BarTab button (or `/bartab make 52` with the recipe selected) adds a bar for what the recipe makes, e.g. "Handful of Copper Bolts 12/52". Shift-click and Alt-click on it craft only what's still missing, and a Create All batch from the profession window stops once you have that many. Right-click the bar to change the number.
- Fixed: with "Stop tracking at skill N", reaching the skill in the middle of a batch (an Alt-click, or Create All in the profession window) removed the bars but the game kept crafting. BarTab now stops the batch when the rule is reached, and says so. Skill-ups are also checked right away, so the batch stops before its next craft.
- `/bartab refresh` redraws BarTab's tracker sections if they stop updating, without a /reload. It also saves how the tracker looked before and after, for bug reports. BarTab saves the same details shortly after each level-up and then redraws its sections as a precaution, since the tracker has stopped updating after a level-up a few times.
- A level-up no longer runs BarTab's skill checks once for every weapon and defense skill that changes at the same moment; it checks once, a second later. Your combat abilities are no longer treated as possible crafts or written to the craft log.
- The profession window's BarTab button now has the recipe settings from a bar's right-click menu once the selected recipe has bars: Crafts, After crafting, Count down as you craft, Stop tracking, and "Untrack this recipe" (all of its bars at once). After crafting set from there applies to every bar of the recipe. The button shows a check mark while the selected recipe has bars.
- Bars from "Make until I reach..." say how many crafts are left in their tooltip: "At least 14 crafts to Leatherworking 75".

## 1.6 (1.60.1.1, first public release)

- "Crafts" on a recipe bar's right-click menu sizes all of the recipe's bars at once: 1, 5 or 10 crafts, or the crafts it takes to reach the next multiple of 5 in the profession ("To Leatherworking 165 (3 crafts)" at 162), or "Use all your Heavy Leather" (37 at 8 a craft: 4 crafts). Resizing never sets off a goal alert.
- Recipe items: a pattern, recipe, plans, formula or schematic for one of your professions that you haven't learned says "BarTab: Alt-Shift-click to add this recipe to your Inactive list" in its tooltip (at a vendor or in your bags; not in the auction house window, where that click opens the item's listings). Alt-Shift-clicking it tracks the recipe like the trainer does: in Inactive, marked not learned, active once you learn it. Works once you've opened that profession with this version.
- "Include Inactive bars in the list" (Crafting tab, under Auction house; off by default): the auction house shopping list also covers your Inactive bars, such as shelved recipes or ones you haven't learned yet from the trainer.
- Track recipes from the trainer: Alt-Shift-click a recipe in a profession trainer's list (or select it and type `/bartab trainer`) to track its ingredients, even before you've learned it. A window asks which ingredients. Recipes you haven't learned wait in Inactive, marked "(not learned)" with the skill they need; they can't be crafted and vendor buying skips them. Learning the recipe makes them ordinary active bars. Hovering a trainer recipe says so: "BarTab: Alt-Shift-click to add this recipe to your Inactive list" (or "to track this recipe" if you know it, or "tracking this recipe").
- A Waylaid Crate in your bags says "BarTab: Alt-Shift-click to track this crate" in its tooltip (or "BarTab: tracking this crate" once it is). Follows the "Show BarTab lines on item tooltips" setting. Crates are only tracked from your bags: one that's only in your bank says "BarTab: move this crate to your bags, then Alt-Shift-click it if it doesn't track automatically", and Alt-Shift-clicking it there says the same in chat.
- "Count down as you craft" on a recipe bar's right-click menu (and a default on the Crafting tab, off unless you turn it on): each craft takes one craft's worth off the recipe's bars, so they show what's left to make (8/32 becomes 4/28, not 4/32). The After crafting rule then waits until the count runs out; bars kept by the rule move to Inactive at full size, ready for next time. Waits for the bag update like the After crafting rule, so it never sets off a false goal alert. Shared bar strings carry it.
- Ctrl-click a recipe bar (or its name) to open the profession window on that recipe; also "Open recipe" on the bar's right-click menu. Ctrl-drag still reorders.
- Favorite recipes: `/bartab favorites` or "Import favorites" (new Recipes tab in settings) tracks the open profession's starred recipes that aren't tracked yet, one craft each, through the same window as appearances (main ingredients, ALL INGREDIENTS, or choose each). "Track recipes when you favorite them" (off by default) offers a recipe as soon as you star it.
- Appearances: "Track recipes for appearances you haven't collected" (Recipes tab, or `/bartab appearances on`). When you learn a recipe or open a profession, recipes that make gear with an appearance this character can collect but hasn't get bars for one craft, set to untrack after crafting. A window asks which ingredients to track (the main one, needed most, is ticked); "Not this one" skips the recipe, and closing the window asks again later. Settings can switch this to the main ingredient only, or every ingredient. Each recipe is offered once (untrack it and it stays gone), recipes you already have a crafted copy of (bags, bank or an alt) are skipped, and only orange and yellow recipes count unless "Include recipes that no longer give skill" is on. When several recipes qualify at once (usually the first scan), a single summary window lists them instead: Track main ingredients (or tick ALL INGREDIENTS), Choose each, Skip all, or Later (asks again next login, or with `/bartab appearances scan`). "Add appearance bars to Inactive" (off by default) puts new appearance bars in the profession's Inactive area. After crafting one, BarTab reminds you to equip or disenchant it, since crafting alone doesn't collect the appearance. If you collect an appearance some other way (loot, purchase, an alt), its bars are untracked too.
- Commands are now `/bartab`, with `/btab` as a short form. `/bt` still works unless another addon uses it, in which case BarTab leaves it to that addon and says so once.
- Fixed: when "After crafting" untracked (or shelved) a recipe's bars, another bar sharing the same material could briefly count the materials just used up, and fire a false goal alert. The rule now waits for your bags to update after the craft.
- Fixed: a bar made before the game had loaded its item could be stuck with a name like "item 1529". BarTab now renames it once the name is known (at login, or as soon as the item loads), merging it into an existing bar for the same thing if there is one. Windows that list ingredients also wait a moment for their names.
- Fixed: untracking a crate's bars didn't stick; the next bag change (even moving a crate to the bank) tracked it again. BarTab now remembers untracked crates by how many are in your bags: crates leaving your bags (used, sold or banked) don't bring tracking back, a crate coming in (looted, or taken back out of the bank) does, and `/bartab item` adds one back by hand.
- Fixed: Waylaid Crates weren't detected on clients where the game's tooltip data comes back empty. BarTab now falls back to reading the item's tooltip directly, and accepts the fill list whether it's inside the "Use:" line or on the lines after it. `/bartab debug item <name>` now also says where it read the tooltip from and what BarTab made of it.
- Fixed: a Waylaid Crate the game hadn't loaded yet (for example one bought at the auction house and taken from the mailbox) could be missed until /reload. BarTab now waits for it to load and adds it then.
- Quest tracking removed: the BarTab: Quests section, quest auto-tracking, bars under quests in the quest tracker, and clicking quest items from bars are gone, along with `/bt quests`, `/bt auto` and `/bt inline`. They added little over the game's own quest tracker and were the riskiest part of BarTab. Existing quest bars and their settings are cleared at login. Crafting, fill-up crates and the Items section are unchanged; the "Quests & Items" settings tab is now "Items", and `/bt help items` replaces `/bt help quests`.
- Fixed: after a login where the game reported your realm a moment late, BarTab could start an empty bar list for "Name-" (no realm) instead of using yours, so all your bars seemed to vanish. BarTab now waits until the game has reported your name and realm before picking your list, and merges any list saved under a missing realm back into yours at login (it says how many bars it recovered).
- BarTab now also puts back any of its sections the objective tracker drops, keeps trying to join the tracker for about 30 seconds after login, and `/bartab debug tracker` lists how each bar is being shown, for bug reports.
- Safer tracker: an error in BarTab's part of the objective tracker update can no longer stop the whole tracker from updating (which could freeze your quest list until /reload). Errors are kept instead; `/bt errors` shows the last few.
- Fixed: bars could show twice, in the tracker and in a plain list below it, after BarTab briefly couldn't add a new section (e.g. in combat). It now retries the section shortly and after combat, and the fallback list never shows alongside the tracker.
- Craft blocks on recipe bars are one color (blue: craftable now, orange: held back by another ingredient) with a thin line (2 screen pixels at any UI scale) between crafts, instead of alternating shades. Short ticks at the top and bottom edges of the rest of the bar mark where each future craft would end, in a darker shade of the color that craft would be once you have the material (blue if the recipe's other ingredients already cover it, orange if not).
- `/bt help` is now a short overview with topics (`/bt help crafting`, `shopping`, `items`, `bars`) that each fit on screen, and covers the newer features (vendors, the auction house tab, recipe chains, item tooltips).
- Recipe chains: "Also track how to make..." now adds one craft's worth; Alt-click it for enough to cover everything the bar is short (the menu shows how many crafts that is).
- Vendors: "Only buy for crafts your bars cover" (Crafting tab, off by default) buys a recipe's vendor materials only for the crafts its tracked bars already cover, e.g. 8 of 10 Heavy Leather for Heavy Armor Kits (5 a kit) buys thread for 1 kit, not 2. Ingredients without a bar (an Iron Buckle you'll get later) don't hold it up.
- Auction house shopping list: a BarTab tab on the auction house's right edge (sharing the tab strip with other addons' tabs) opens a list of what your Crafting and Items bars are short of (recipe ingredients without a bar included), each with a Search button that runs the auction house's own search. Updates as you buy, and reopens if you left it open. On/off on the Crafting tab of the settings. The panel has a solid background, so nameplates behind it don't show through.
- Bars remember their item ID (from links, recipes, your bags or the item cache) and count, match tooltips and match vendor items by it, falling back to the name. Counting is also faster: one bag scan is shared by every bar instead of each bar scanning your bags. Shared bar strings carry the ID.

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

- Alt-Shift-click any item (bags, chat links, loot) to track it. Fill-up items are added right away; anything else opens a small window where you pick Item (Items section), Crafting material, or the open recipe if it uses the item, and set a goal. The bag's "how many" box that Shift opens is closed automatically.
- Session stats in bar tooltips: how many you've gained since login or /reload, the rate per hour, and about how long until the bar fills at that pace. Items taken from the bank don't count. `/bt session reset` starts over.
- Share bar setups as text: `/bt share` (or Share bars in settings, or "Share this bar" / "Share these bars" on the right-click menus) gives a string to paste to a friend; `/bt import` (or Import bars) adds bars from one. Bars you already have take the shared range. Quest and fill-up bars aren't shared.

## 1.3

- Per-character bar lists. Existing bars went to the first character to log in;
  `/bt copy <character>` copies another character's bars.
- Tooltips show bank and alt counts, with alts' full names
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
