-- BarTab: help, slash commands and events.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

do
-- /bartab help ---------------------------------------------------------------------
-- In chat, "|" starts a formatting code ("|r" ends a color), so a literal bar
-- in a message is written "||".

-- Short enough to read without scrolling: an overview, then one topic at a
-- time (/bartab help crafting, shopping, items, bars).
local function cmd(text) return "|cff80c0ff" .. text .. "|r" end
local function head(text) return "|cffffd100" .. text .. "|r" end

HELP_TOPICS = {
    overview = {
        head("BarTab") .. " shows what you're collecting as progress bars in the objective tracker:",
        "  " .. head("Crafting") .. " - materials, often tied to a recipe you can craft from the bar.",
        "  " .. head("Items") .. " - fill-up items like Waylaid Crates, and anything else you're collecting.",
        "Start: open a profession, pick a recipe, click the BarTab button by the favorite star.",
        "More: " .. cmd("/bartab help") .. " crafting, goals, profit, shopping, items or bars. "
            .. cmd("/btab") .. " works too.",
        "Settings: " .. cmd("/bartab config") .. ", the minimap button, or Options > AddOns > BarTab.",
        "The full user's guide, section by section: " .. cmd("/bartab guide") .. ".",
    },
    crafting = {
        head("Crafting:"),
        "  " .. cmd("/bartab assign Heavy Leather") .. " - a bar for the selected recipe, one craft's worth (or "
            .. cmd("0-12") .. "). " .. cmd("/bartab track Light Leather 20") .. " - a plain bar up to 20.",
        "  Alt-Shift-click any item (bags, bank, chat links, loot) to track it.",
        "  Click a recipe bar to craft 1, Shift-click as many as fit, Alt-click all you can (change in " .. cmd("/bartab config") .. ").",
        "  Short of a material you can make? A click makes it first, then the recipe (chain crafting). Click again to stop.",
        "  A lighter stretch on a bar shows how much more your bags could make; an alert says when it's enough.",
        "  " .. cmd("/bartab craft") .. " or a key (Key Bindings > AddOns) crafts the next bar that's ready.",
        "  Arrows by a bar's name show the recipe's difficulty, like the profession window (Display settings).",
        "  " .. cmd("/bartab favorites") .. " (profession open) tracks your starred recipes. At a trainer, Alt-Shift-click a recipe to track it before you learn it.",
        "  " .. cmd("/bartab appearances on") .. " tracks recipes for appearances you haven't collected (" .. cmd("scan") .. " asks again).",
    },
    goals = {
        head("Goals and rules:"),
        "  " .. cmd("/bartab make 52") .. " (recipe selected) crafts it until you have 52; or Goals on the BarTab button.",
        "  Make until I reach... crafts until your skill gets there, and clears the bars when it does.",
        "  Right-click a recipe bar: Crafts (1, 5, 10, a stack, any number), After crafting, Count down, Stop tracking.",
        "  Training reminders say when a profession needs its next rank, and when a trainer's recipes come within reach.",
    },
    profit = {
        head("Profit and leveling:"),
        "  " .. cmd("/bartab profit") .. " (profession open) - what each recipe earns sold to a vendor or at auction, your way of counting materials.",
        "  " .. cmd("/bartab next") .. " - what to craft next: recipes ranked by what a skill point costs (or takes).",
        "  " .. cmd("/bartab session") .. " - what you've crafted, gained in skill, gathered and spent since you logged in (" .. cmd("last") .. " for the session before).",
        "  In the list: hover for the breakdown, click to show the recipe, Shift-click to search the auction house, right-click to track.",
    },
    shopping = {
        head("Shopping:"),
        "  At a vendor that sells what your recipes are short of (thread, dye, vials), BarTab asks to buy it.",
        "  At your bank, it offers to take out what your bars are short of (" .. cmd("/bartab bank") .. " asks again).",
        "  At a mailbox, it offers to mail your other characters what their bars need and you have spare (" .. cmd("/bartab mail") .. "), and to take what they mailed you (" .. cmd("/bartab mail take") .. ").",
        "  Optionally, bars for what your other characters need, so you can gather for them (" .. cmd("/bartab config") .. " > Shopping).",
        "  " .. cmd("/bartab config") .. " > Shopping: ask, automatic or off; a spend limit; only buy for crafts your bars cover.",
        "  At the auction house, the BarTab tab on the right edge lists what you're short of, with Search buttons.",
        "  Hover any item you track to see lines like \"BarTab: 4/5 for Hillman's Cloak\".",
    },
    items = {
        head("Items:"),
        "  Fill-up items like Waylaid Crates get a bar per bundle when they reach your bags.",
        "  " .. cmd("/bartab item Waylaid Crate") .. " adds one by hand; split stacks are combined for you.",
        "  When a crate bar says Ready, click it to fill the crate. Not in combat.",
        "  Alt-Shift-click anything else (a potion, a reagent) to collect it here with a goal.",
    },
    bars = {
        head("Managing bars:"),
        "  Right-click a bar: Crafting, Rules and This bar (assign, move to Inactive, untrack...).",
        "  Right-click a heading: move all to Inactive, share, untrack all. Ctrl-drag a bar to reorder; Ctrl-click opens its recipe.",
        "  Removed one by mistake? " .. cmd("/bartab undo") .. " brings it back (" .. cmd("/bartab undo list") .. " for more).",
        "  Hover a bar for details: shopping list, bank and alt counts, this session's gains and time to goal.",
        "  " .. cmd("/bartab copy [Alt]") .. " copies another character's bars; " .. cmd("/bartab share") .. " and "
            .. cmd("/bartab import") .. " pass bars as text.",
        "  If another addon hides the objective tracker, BarTab gets its own window (" .. cmd("/bartab window") .. ").",
    },
}
HELP_ALIASES = { craft = "crafting", shop = "shopping", vendor = "shopping", vendors = "shopping",
    auction = "shopping", ah = "shopping", item = "items", crate = "items", crates = "items",
    bar = "bars", manage = "bars", goal = "goals", rules = "goals", training = "goals",
    leveling = "profit", next = "profit", money = "profit", bank = "shopping", chain = "crafting" }

ShowHelp = function(topic)
    topic = string.lower(topic or "")
    topic = HELP_ALIASES[topic] or topic
    local lines = HELP_TOPICS[topic]
    if not lines then
        if topic ~= "" then Print("No help topic \"" .. topic .. "\"; here's the overview.") end
        lines = HELP_TOPICS.overview
    end
    for _, line in ipairs(lines) do
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
end
end

-- Per-character bar lists ------------------------------------------------------
--
-- BarTabDB.characters["Name-Realm"] holds each character's bars. Bars saved
-- before lists were per character go to the first character that logs in.

-- Tidies a list loaded from saved data (old link names, old key formats).
local function TidyList()
    CleanSavedNames()

    -- Quest tracking was removed in 1.6: drop quest bars.
    for key, item in pairs(trackedItems) do
        if item.quest then trackedItems[key] = nil end
    end

    -- Repair: an assign used to be able to take over a crate's bar, leaving
    -- one bar that was both a crate bar and a recipe bar. Split it back into
    -- the crate's bar and a recipe bar.
    local broken = {}
    for key, item in pairs(trackedItems) do
        if item.container and item.recipeID then broken[key] = item end
    end
    for key, item in pairs(broken) do
        trackedItems[key] = nil
        local crateGoal = item.goal
        for _, option in ipairs(item.container.options or {}) do
            if string.lower(option.name) == string.lower(item.name) then crateGoal = option.count end
        end
        local crateKey = string.lower(item.name) .. "#" .. item.container.id
        if not trackedItems[crateKey] then
            trackedItems[crateKey] = { name = item.name, start = 0, goal = crateGoal,
                order = item.order, container = item.container }
        end
        local recipeKey = string.lower(item.name) .. "@" .. item.recipeID
        if not trackedItems[recipeKey] then
            local perCraft = GetReagentQuantity(item.recipeID, item.name)
            trackedItems[recipeKey] = { name = item.name, start = 0,
                goal = (perCraft and perCraft > 0) and perCraft or item.goal,
                order = NextOrder(), recipeID = item.recipeID,
                profession = item.profession, label = item.label,
                skillLineID = item.skillLineID }
        end
    end
    -- Recipe bars use "material@recipeID" keys (one bar per recipe).
    local moves = {}
    for key, item in pairs(trackedItems) do
        if item.recipeID then
            local wanted = string.lower(item.name) .. "@" .. item.recipeID
            if key ~= wanted and not trackedItems[wanted] then
                moves[key] = wanted
            end
        end
    end
    for oldKey, newKey in pairs(moves) do
        trackedItems[newKey] = trackedItems[oldKey]
        trackedItems[oldKey] = nil
    end
    NormalizeOrder()
end

-- Lists saved under a key missing its realm ("[Alt]-"), from a login where
-- the game hadn't reported the realm yet: merged into the real list.
function MergeBrokenCharacterKeys(db, key)
    local name = UnitName("player")
    if not name or name == "" then return end
    local merged = 0
    for brokenKey, list in pairs(db.characters) do
        if brokenKey ~= key and (brokenKey == name .. "-" or brokenKey == name .. "-?") then
            local real = db.characters[key]
            for itemKey, item in pairs(list) do
                local existing = real[itemKey]
                if not existing then
                    item.order = NextOrderIn(real)
                    real[itemKey] = item
                    merged = merged + 1
                elseif existing.inactive and not item.inactive then
                    existing.inactive = nil -- you made it active again since
                end
            end
            db.characters[brokenKey] = nil
            -- Per-character settings saved under the broken key: keep what
            -- matters (offered recipes, untracked crates), drop the rest
            -- (they're rebuilt as you play).
            for _, store in ipairs({ "appearanceOffered", "dismissedContainers" }) do
                local t = settings[store]
                if t and t[brokenKey] then
                    t[key] = t[key] or {}
                    for k, v in pairs(t[brokenKey]) do
                        if t[key][k] == nil then t[key][k] = v end
                    end
                    t[brokenKey] = nil
                end
            end
            for _, store in ipairs({ "inventory", "producers", "recipeIndex" }) do
                if settings[store] then settings[store][brokenKey] = nil end
            end
        end
    end
    if merged > 0 then
        C_Timer.After(5, function()
            Print("Recovered " .. merged .. " bar(s) saved while the game hadn't reported your realm yet.")
        end)
    end
end

function NextOrderIn(list)
    local highest = 0
    for _, item in pairs(list) do highest = math.max(highest, item.order or 0) end
    return highest + 1
end

function BindCharacterList(tries)
    -- The game can report the realm a moment after login; until it does,
    -- don't pick (or create) a list, or the bars land under "Name-".
    tries = tries or 0
    if not CharacterKnown() and tries < 20 then
        C_Timer.After(0.5, function() BindCharacterList(tries + 1) end)
        return
    end
    local db = _G.BarTabDB
    db.characters = db.characters or {}
    boundCharacterKey = nil
    local key = CharacterKey()
    if CharacterKnown() then boundCharacterKey = key end

    if not db.characters[key] then
        -- One-time move of the old shared list.
        local legacy = {}
        for itemKey, item in pairs(db) do
            if itemKey ~= "characters" and type(item) == "table" and item.name then
                legacy[itemKey] = item
            end
        end
        if next(legacy) then
            for itemKey in pairs(legacy) do db[itemKey] = nil end
            db.characters[key] = legacy
            C_Timer.After(5, function()
                Print("Bars are now kept per character. Your existing bars are on this character; "
                    .. "others start empty. Use /bartab copy <character> on another character to copy them.")
            end)
        else
            db.characters[key] = {}
        end
    end

    trackedItems = db.characters[key]
    if boundCharacterKey then MergeBrokenCharacterKeys(db, key) end
    TidyList()
    UpdateBars()
end

-- /bartab copy <character>: adds that character's bars to this one's.
local function CopyFromCharacter(text)
    local db = _G.BarTabDB
    local wanted = string.lower(text or "")
    if wanted == "" then
        Print("Use: /bartab copy <character name>")
        return
    end
    local me = CharacterKey()
    local matches = {}
    for key in pairs(db.characters or {}) do
        if key ~= me then
            local first = string.lower(key:match("^(.-)%-") or key)
            local snapshot = settings.inventory and settings.inventory[key]
            local full = snapshot and snapshot.fullName and string.lower(snapshot.fullName)
            if first == wanted or string.lower(key) == wanted or full == wanted then
                matches[#matches + 1] = key
            end
        end
    end
    if #matches == 0 then
        Print("No other character called \"" .. text .. "\" has BarTab bars yet.")
        return
    elseif #matches > 1 then
        Print(text .. " matches several characters: " .. table.concat(matches, ", ")
            .. ". Use the full name shown, e.g. /bartab copy " .. matches[1])
        return
    end

    local function deepCopy(value)
        if type(value) ~= "table" then return value end
        local copy = {}
        for k, v in pairs(value) do copy[k] = deepCopy(v) end
        return copy
    end
    local added = 0
    for itemKey, item in pairs(db.characters[matches[1]]) do
        if not trackedItems[itemKey] then
            local copy = deepCopy(item)
            copy.order = NextOrder()
            trackedItems[itemKey] = copy
            added = added + 1
        end
    end
    UpdateBars()
    Print("Copied " .. added .. " bar(s) from " .. matches[1] .. ".")
end

_G.SLASH_BARTAB1 = "/bartab"
_G.SLASH_BARTAB2 = "/btab"

-- /bt is also BarTab's, but only when no other addon uses it (Bartender4,
-- for one, does). Checked after login, once other addons have registered
-- their commands.
function ClaimShortSlash()
    for key, value in pairs(_G) do
        if type(key) == "string" and type(value) == "string"
            and key:find("^SLASH_") and string.lower(value) == "/bt"
            and not key:find("^SLASH_BARTAB%d") then
            if not settings.shortSlashNotice then
                settings.shortSlashNotice = true
                Print("Another addon uses /bt, so BarTab's commands are /bartab or /btab.")
            end
            return false
        end
    end
    _G.SLASH_BARTAB3 = "/bt"
    return true
end
SlashCmdList.BARTAB = function(message)
    local command, args = message:match("^%s*(%S+)%s*(.-)%s*$")
    command = string.lower(command or "")
    args = Trim(args)

    if command == "track" then
        local name, startCount, goal, err = ParseTrackArgs(StripLinks(args))
        if not name then
            Print(err or "Use: /bartab track Item Name [max] or /bartab track Item Name min-max")
            return
        end

        if not goal or goal <= startCount then
            Print("Max must be greater than min.")
            return
        end

        TrackMaterial(name, startCount, goal)

    elseif command == "assign" or command == "attach" then
        local targetText = ParseAssignTarget(args)
        local name, startCount, goal = ParseExplicitRange(targetText)
        if not name then
            name = targetText
        end

        if name == "" then
            Print("Use: /bartab assign Item Name [min-max] (with a recipe selected)")
            return
        end

        local recipeID = GetSelectedRecipeID()
        if not recipeID then
            Print("Select a recipe in the tradeskill window first.")
            return
        end

        if goal and goal <= startCount then
            Print("Max must be greater than min.")
            return
        end

        AssignMaterial(name, recipeID, startCount, goal)

    elseif command == "unassign" or command == "detach" then
        local key = FindKeyByName(StripLinks(args), "unassign")
        if key then
            UnassignRecipe(key)
        end

    elseif command == "untrack" then
        if args == "" then
            local removed = {}
            for key, item in pairs(trackedItems) do
                removed[#removed + 1] = item
                trackedItems[key] = nil
            end
            NoteUntrackedContainers(removed)
            UpdateBars()
            Print("Stopped tracking all items.")
        else
            local key = FindKeyByName(StripLinks(args), "untrack")
            if key then
                UntrackItem(key)
            end
        end

    elseif command == "debug" then
        -- Troubleshooting only; not listed in /bartab help or the README.
        local itemFilter = args:match("^[Ii][Tt][Ee][Mm]%s+(.+)$")
        if string.lower(args) == "name" then
            Print("Character name sources:")
            for _, source in ipairs(CharacterNameSources()) do
                Print("  " .. source.label .. ": " .. source.value)
            end
        elseif itemFilter then
            DebugItems(itemFilter)
        elseif string.lower(args) == "perf" then
            Safe("debug", DebugPerf)()
        elseif string.lower(args) == "perf reset" then
            perf.since, perf.updates, perf.ms, perf.redraws, perf.redrawMs, perf.collapses = GetTime(), 0, 0, 0, 0, 0
            Print("Counting from now.")
        elseif string.lower(args) == "recipes" then
            Safe("debug", DebugRecipeList)()
        elseif string.lower(args) == "tracker" then
            Safe("debug", DebugTracker)()
        elseif string.lower(args) == "craft" then
            settings.debugCraft = not settings.debugCraft or nil
            if settings.debugCraft then settings.debugLog = { "BarTab craft log" } end
            Print("Craft log " .. (settings.debugCraft and "on: craft, then /reload to save it. Type /bartab debug craft again to stop."
                or "off.") )
        elseif string.lower(args) == "log" then
            local log = settings.debugLog or {}
            if #log <= 1 then Print("The craft log is empty.") end
            for i = 2, #log do DEFAULT_CHAT_FRAME:AddMessage("  " .. log[i]) end
        elseif args == "" then
            ShowDebugWindow()
        else
            Print("Debug: /bartab debug (window), name, item <part of a name>, craft, log, perf, recipes, tracker.")
        end

    elseif command == "help" or command == "" or command == "?" then
        ShowHelp(args)

    elseif command == "config" or command == "options" or command == "settings" then
        ToggleConfig()

    elseif command == "share" or command == "export" then
        ShareAll()

    elseif command == "import" then
        if args ~= "" then
            ImportText(args)
        else
            ShowShareWindow(nil)
        end

    elseif command == "session" then
        local value = string.lower(args)
        if value == "last" then
            ShowSession("last")
        elseif value == "reset" then
            -- Bar tooltips' gained-and-rate counts, and the summary.
            ResetSessionStats()
            UpdateBars()
            local _, mine = SessionData()
            mine.current = nil
            SessionData()
            Print("Session stats reset.")
        else
            ShowSession()
        end

    elseif command == "craft" then
        _G.BarTab_CraftNext()

    elseif command == "window" then
        local value = string.lower(args)
        if value == "reset" then
            ResetPanelPosition()
        elseif value == "lock" or value == "unlock" then
            settings.panelLocked = (value == "lock") or nil
            Print("BarTab window " .. (settings.panelLocked and "locked." or "unlocked; drag a section heading to move it."))
        else
            local modes = { auto = "auto", on = "window", off = "tracker" }
            if modes[value] then
                settings.displayMode = modes[value]
                UpdateBars()
            end
            Print("BarTab window: " .. (settings.displayMode == "window" and "on"
                or settings.displayMode == "tracker" and "off" or "auto")
                .. (panelActive and " (showing)" or " (not showing)")
                .. (IsTrackerHidden() and ", the objective tracker is hidden" or "")
                .. ". Use /bartab window auto||on||off||reset||lock||unlock.")
        end

    elseif command == "refresh" then
        Safe("refresh", SnapshotTracker)("refresh, before")
        Safe("refresh", RefreshTracker)(true)
        C_Timer.After(1, function() Safe("refresh", SnapshotTracker)("refresh, after") end)
        Print("Redrew the tracker sections. Details are saved for bug reports at your next /reload.")

    elseif command == "errors" then
        local log = settings.errorLog or {}
        if string.lower(args) == "clear" then
            settings.errorLog = nil
            Print("Error log cleared.")
        elseif #log == 0 then
            Print("No errors recorded.")
        else
            Print(#log .. " recent error(s), newest first (/bartab errors clear to empty the list):")
            for i, entry in ipairs(log) do
                DEFAULT_CHAT_FRAME:AddMessage(("  %d. %s %s (v%s) - %s"):format(i, entry.when or "",
                    entry.where or "?", entry.version or "?", (entry.message or ""):gsub("|", "||")))
            end
        end

    elseif command == "copy" then
        CopyFromCharacter(args)

    elseif command == "item" then
        local filter = string.lower(StripLinks(args))
        if filter == "" then
            Print("Use: /bartab item <item name or shift-clicked link>, e.g. /bartab item Waylaid Crate")
        else
            ScanForContainers(filter)
        end

    elseif command == "make" then
        Safe("make", MakeUntil)(GetSelectedRecipeID(), args:match("%d+"))

    elseif command == "trainer" then
        if GetTrainerSelectionIndex and GetTrainerSelectionIndex() and GetTrainerSelectionIndex() > 0 then
            Safe("trainer", TrackTrainerService)(GetTrainerSelectionIndex())
        else
            Print("Open a profession trainer and select a recipe first (or Alt-Shift-click it).")
        end

    elseif command == "undo" then
        local list = RemovedBars()
        if string.lower(args) == "list" then
            if #list == 0 then
                Print("No bars have been removed lately.")
            else
                Print("Recently removed (/bartab undo <number> brings one back):")
                for index, entry in ipairs(list) do
                    Print(("  %d. %s, %s"):format(index, RemovedLabel(entry), AgoText(entry.time)))
                end
            end
        else
            RestoreRemoved(tonumber(args) or 1)
        end

    elseif command == "guide" then
        Safe("guide", ShowGuide)(args)

    elseif command == "mail" then
        if mailboxOpen and args == "take" then
            if #BarTabLetters() == 0 then
                Print("No BarTab letters with items in your mailbox.")
            else
                Safe("mail", StartCollect)()
            end
        elseif mailboxOpen then
            Safe("mail", OfferMailSends)(true)
        else
            Print("Open a mailbox first; BarTab then offers to mail your other characters what their bars need.")
        end

    elseif command == "bank" then
        if bankWindowOpen then
            Safe("bank", OfferBankWithdrawals)(true)
        else
            Print("Open your bank first; BarTab then offers to take out what your bars are short of.")
        end

    elseif command == "next" then
        Safe("profit", ShowCraftNext)(args)

    elseif command == "profit" then
        if string.lower(args) == "list" then
            Safe("profit", ShowProfitList)()
        else
            Safe("profit", ShowProfitWindow)()
        end

    elseif command == "favorites" or command == "favourites" or command == "favs" then
        Safe("favorites", ImportFavoriteRecipes)()

    elseif (command == "appearances" or command == "appearance") and string.lower(args) == "scan" then
        if not settings.appearanceRecipes then
            Print("Turn it on first: /bartab appearances on")
        elseif not LoadedProfession() then
            appearanceSnoozed = nil
            Print("Open a profession and BarTab will check its recipes.")
        else
            appearanceSnoozed = nil
            Safe("appearances", ScanAppearanceRecipes)()
        end

    elseif command == "appearances" or command == "appearance" then
        local value = string.lower(args)
        if value == "on" or value == "off" then
            settings.appearanceRecipes = (value == "on")
            if value == "on" then appearanceSnoozed = nil end
        end
        Print("Tracking recipes for appearances you haven't collected is "
            .. (settings.appearanceRecipes and "on" or "off") .. ". Use /bartab appearances on or off to change it.")
        if value == "on" then
            Safe("appearances", ScanAppearanceRecipes)()
            if not LoadedProfession() then
                Print("Open a profession and BarTab will check its recipes.")
            end
        end

    elseif command == "autoitems" then
        local value = string.lower(args)
        if value == "on" or value == "off" then
            settings.autoItems = (value == "on")
        end
        Print("Auto-tracking fill-up items (like Waylaid Crates) when they reach your bags is "
            .. (settings.autoItems and "on" or "off") .. ". Use /bartab autoitems on or off to change it.")

    else
        Print("Commands (after /bartab or /btab): help, guide, config, track, assign, unassign, untrack, copy, share, import, window, craft, session reset, errors, refresh, undo [list||number], item, autoitems on||off, favorites, trainer, make <count>, profit, next [profession], bank, mail, appearances on||off")
        Print("Type /bartab help for a quick guide with examples.")
    end
end

-- Watches bags for new fill-up items (Waylaid Crates etc.).
containerScanPending = false
function QueueContainerScan(delay)
    if containerScanPending then return end
    containerScanPending = true
    C_Timer.After(delay, function()
        containerScanPending = false
        UpdateDismissedContainers()
        if settings.autoItems then
            ScanForContainers(nil)
        end
        AutoMergeForContainers()
    end)
end

events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

-- BAG_UPDATE_DELAYED fires once after a batch of bag changes; fall back to
-- BAG_UPDATE on clients that don't have it.
if not pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED") then
    events:RegisterEvent("BAG_UPDATE")
end

events.barTabOwn = true -- never muted by SilentLoad
pcall(events.RegisterEvent, events, "GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
-- Session stats leave out items taken from the bank or guild bank.
for _, bankEvent in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED" }) do
    pcall(events.RegisterEvent, events, bankEvent)
end
for _, tradeEvent in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE" }) do
    pcall(events.RegisterEvent, events, tradeEvent)
end
for _, castEvent in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    if events.RegisterUnitEvent then
        pcall(events.RegisterUnitEvent, events, castEvent, "player")
    else
        pcall(events.RegisterEvent, events, castEvent)
    end
end

events:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            _G.BarTabDB = _G.BarTabDB or {}
            -- Each character's bars are picked at PLAYER_LOGIN (the
            -- character's name isn't reliably known before that).
            trackedItems = {}
            -- No saved settings at all: a brand-new install (for the login tip).
            brandNewInstall = _G.BarTabSettings == nil
            _G.BarTabSettings = _G.BarTabSettings or {}
            settings = _G.BarTabSettings
            -- Quest tracking was removed in 1.6: drop its settings.
            settings.autoQuests, settings.inlineQuests = nil, nil
            settings.inlineDefaultOff, settings.questsUsableOnly = nil, nil
            if settings.autoItems == nil then
                settings.autoItems = true
            end
            settings.barHeight = settings.barHeight or 20
            settings.textSize = settings.textSize or 12
            settings.palette = settings.palette or "colorblind"
            settings.hiddenSections = settings.hiddenSections or {}
            ApplyPalette(settings.palette)
            settings.hiddenSections["BarTab: Quests"] = nil
            -- 1.60.1.4 counted redraws on a flag that's always on: start over.
            if settings.trackerWatch ~= 2 then
                settings.trackerUnstuck, settings.trackerWatch = nil, 2
            end
            if settings.collapsed then
                for key in pairs(settings.collapsed) do
                    if type(key) == "string" and (key:find("^BarTab: Quests") or key:find("^Quests/")) then
                        settings.collapsed[key] = nil
                    end
                end
            end
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        BindCharacterList()
        C_Timer.After(3, function() Safe("names", FixPlaceholderNames)() end)
        C_Timer.After(1, function() pcall(ClaimShortSlash) end)
        C_Timer.After(6, function() Safe("guide", ShowLoginTip)() end)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if arg1 and placeholderPending[arg1] then
            C_Timer.After(0.1, function() Safe("names", FixPlaceholderNames)() end)
        end
        -- A fill-up item's tooltip wasn't loaded when we first looked.
        if arg1 and fillOptionsPending[arg1] then
            fillOptionsPending[arg1] = nil
            fillOptionsCache[arg1], fillOptionsTries[arg1] = nil, nil
            QueueContainerScan(0.3)
        end
    elseif event:find("^UNIT_SPELLCAST_") then
        -- Follow our craft so the silently loaded profession isn't closed under it.
        -- Only casts that could be crafts: not combat abilities.
        if arg1 == "player" and (crafting or (arg3 and IsTrackedRecipe(arg3))
            or ProfessionsOpen()) then
            CraftLog(event:gsub("UNIT_SPELLCAST_", "cast ") .. " " .. tostring(arg3))
            if crafting then
                crafting.last = GetTime()
                crafting.castAt = GetTime()
                if event ~= "UNIT_SPELLCAST_FAILED" then crafting.cast = true end
            end
            if event == "UNIT_SPELLCAST_START" and arg3 then
                Safe("craft start", OnCraftStarted)(arg3)
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg3 then
                OnCraftSucceeded(arg3)
            elseif crafting and (event == "UNIT_SPELLCAST_FAILED"
                or event == "UNIT_SPELLCAST_INTERRUPTED") then
                crafting = nil
            end
        end
    elseif event == "TRADE_SKILL_SHOW" then
        CraftLog("profession opened (TRADE_SKILL_SHOW)")
        -- You opened it yourself (not BarTab reading it quietly): offers
        -- you closed earlier may be made again.
        if not silent.waiting then appearanceSnoozed = nil end
        OnTradeSkillShow()
    elseif event == "TRADE_SKILL_CLOSE" then
        CraftLog("profession closed (TRADE_SKILL_CLOSE)")
        silent.loaded = nil
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Last chance to switch secure overlays off before combat lockdown.
        HideAllOverlays()
    elseif event == "BANKFRAME_OPENED" or event == "GUILDBANKFRAME_OPENED" then
        UpdateBars()
        bankOpen = true
    elseif event == "BANKFRAME_CLOSED" or event == "GUILDBANKFRAME_CLOSED" then
        UpdateBars() -- take in what moved while the bank was open
        bankOpen = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Bags can read empty for a moment at login; don't count that as gains.
        sessionReadyAt = sessionReadyAt or (GetTime() + 5)
        if trackerSetupTried then
            RequestUpdate(1)
            return
        end
        trackerSetupTried = true
        RegisterOptionsPage()
        UpdateMinimapButton()
        C_Timer.After(0.5, function() TrySetUpTracker(1) end)
        RequestUpdate(1)
        QueueContainerScan(2)
    else
        if event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
            RunPendingAfterCraft()
            C_Timer.After(0.1, function() Safe("make", CheckMakeTargets)() end)
            Safe("names", FixPlaceholderNames)()
        end
        RequestUpdate(0.2)
        QueueContainerScan(0.3)
    end
end)

-- The debug window (/bartab debug): every troubleshooting switch and
-- report in one place, plus Reload. Not listed in the help.
do
    local REPORTS = {
        { "Craft log", "debug log", "Print the craft log in chat." },
        { "Errors", "errors", "Print BarTab's recent errors." },
        { "Clear errors", "errors clear", "Empty the error list." },
        { "Character names", "debug name", "Where BarTab gets your characters' names." },
        { "Performance", "debug perf", "How long BarTab's updates take." },
        { "Reset counters", "debug perf reset", "Start the performance counts from now." },
        { "Recipe list", "debug recipes", "What the open profession's recipe list says." },
        { "Tracker", "debug tracker", "The objective tracker's state, section by section." },
    }

    function ShowDebugWindow()
        local frame = BarTabDebugFrame
        if not frame then
            local ok
            ok, frame = pcall(CreateFrame, "Frame", "BarTabDebugFrame", UIParent, "BasicFrameTemplateWithInset")
            if not ok then
                frame = CreateFrame("Frame", "BarTabDebugFrame", UIParent, "BackdropTemplate")
                frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32,
                    edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
                local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
                close:SetPoint("TOPRIGHT", -4, -4)
            end
            frame:SetSize(330, 330)
            frame:SetPoint("CENTER")
            frame:SetFrameStrata("DIALOG")
            frame:SetMovable(true)
            frame:EnableMouse(true)
            frame:RegisterForDrag("LeftButton")
            frame:SetScript("OnDragStart", frame.StartMoving)
            frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
            frame:SetClampedToScreen(true)
            tinsert(UISpecialFrames, "BarTabDebugFrame")

            local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            title:SetPoint("TOP", 0, -6)
            title:SetText("BarTab debug")

            -- Switches.
            local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
            check:SetSize(24, 24)
            check:SetPoint("TOPLEFT", 16, -32)
            if type(check.Text) == "table" then check.Text:SetText("") end
            check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
            check:SetScript("OnClick", function() SlashCmdList.BARTAB("debug craft"); frame:Refresh() end)
            frame.craftCheck = check

            -- Reports: two columns of buttons.
            for index, report in ipairs(REPORTS) do
                local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                button:SetSize(140, 22)
                local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
                button:SetPoint("TOPLEFT", 16 + column * 150, -70 - row * 28)
                button:SetText(report[1])
                button:SetScript("OnClick", function() SlashCmdList.BARTAB(report[2]); frame:Refresh() end)
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(report[1])
                    GameTooltip:AddLine(report[3] .. " (/bartab " .. report[2] .. ")", 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end

            -- Item lookup.
            local itemLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            itemLabel:SetPoint("TOPLEFT", 18, -190)
            itemLabel:SetText("Look up an item (part of its name):")
            local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            box:SetSize(200, 20)
            box:SetPoint("TOPLEFT", 22, -206)
            box:SetAutoFocus(false)
            local find = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            find:SetSize(80, 22)
            find:SetPoint("LEFT", box, "RIGHT", 8, 0)
            find:SetText("Look up")
            local function Lookup()
                local text = box:GetText() or ""
                if text ~= "" then SlashCmdList.BARTAB("debug item " .. text) end
                box:ClearFocus()
            end
            find:SetScript("OnClick", Lookup)
            box:SetScript("OnEnterPressed", Lookup)
            box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

            -- Reload, to save the logs (and load changed files).
            local reload = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            reload:SetSize(140, 26)
            reload:SetPoint("BOTTOM", 0, 16)
            reload:SetText("Reload UI")
            reload:SetScript("OnClick", function() ReloadUI() end)
            local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            note:SetPoint("BOTTOM", reload, "TOP", 0, 6)
            note:SetText("Reloading saves the logs to disk.")
            frame.note = note

            function frame:Refresh()
                local on = settings.debugCraft and true or false
                local lines = math.max(0, #(settings.debugLog or {}) - 1)
                self.craftCheck:SetChecked(on)
                self.craftCheck.label:SetText("Craft log" .. (on and (" (on, " .. lines .. " lines)") or " (off)"))
            end
            frame:SetScript("OnShow", function(self) self:Refresh() end)
        end
        frame:Show()
        frame:Refresh()
    end
end
