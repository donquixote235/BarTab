-- BarTab: help, slash commands and events.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

do
-- /bt help ---------------------------------------------------------------------

HELP_LINES = {
    "|cffffd100BarTab|r tracks items you're collecting as progress bars in the objective tracker, in up to three sections:",
    "  |cffffd100Crafting|r - materials, optionally tied to a recipe so you can craft from the bar.",
    "  |cffffd100Quests|r - items your quests ask for, added when you accept the quest.",
    "  |cffffd100Items|r - fill-up items like Waylaid Crates, added when they reach your bags.",
    "|cffffd100Crafting examples:|r",
    "  |cff80c0ff/bt track Light Leather 20|r - a bar counting Light Leather up to 20.",
    "  |cffffd100Alt-Shift-click|r any item (bags, chat links, auction house) to track it as an item, a crafting material, or for the open recipe.",
    "  |cff80c0ff/bt assign Heavy Leather|r - with Hillman's Cloak selected in your profession window: a bar for that recipe, sized to one craft.",
    "  |cff80c0ff/bt assign Heavy Leather 0-12|r - the same, with your own bar size.",
    "  On a recipe bar (by default): click crafts 1, Shift-click as many as fit the bar, Alt-click all you can. Change these in /bt config.",
    "  |cff80c0ff/bt craft|r (or a key: |cffffd100BarTab: Craft the next ready bar|r in Key Bindings > AddOns) crafts the next bar that's ready.",
    "|cffffd100Quests and Items:|r",
    "  |cff80c0ff/bt quests|r - add items for quests already in your log.",
    "  |cff80c0ff/bt item Waylaid Crate|r - add a fill-up item by hand (shift-clicked links work too).",
    "  When a bar says Ready, click it to use the quest item or fill the crate (not in combat).",
    "|cffffd100Managing bars:|r",
    "  Right-click a bar: assign/unassign a recipe, what to do after crafting it, stop at a skill level or recipe color, move to Inactive, untrack.",
    "  Right-click a section or subsection heading: move all to Inactive, untrack all.",
    "  Ctrl-drag a bar onto another to reorder. Hover a bar for details, including what you've gained this session and time to goal (|cff80c0ff/bt session reset|r starts over).",
    "  |cff80c0ff/bt untrack Light Leather|r, |cff80c0ff/bt unassign Hillman's Cloak|r - by name.",
    "  Each character has its own bars; |cff80c0ff/bt copy Alinda|r copies another character's bars to this one.",
    "  |cff80c0ff/bt share|r gives you a text string of your bars to paste to a friend; |cff80c0ff/bt import|r adds bars from one. Right-click a bar or heading to share just those.",
    "  If another addon hides the objective tracker, BarTab shows in its own window instead (drag a section heading to move it; |cff80c0ff/bt window|r).",
    "|cffffd100Settings:|r |cff80c0ff/bt config|r, the minimap button, or Options > AddOns > BarTab.",
}

ShowHelp = function()
    for _, line in ipairs(HELP_LINES) do
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
        if item.recipeID and not item.quest then
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

function BindCharacterList()
    local db = _G.BarTabDB
    db.characters = db.characters or {}
    local key = CharacterKey()

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
                    .. "others start empty. Use /bt copy <character> on another character to copy them.")
            end)
        else
            db.characters[key] = {}
        end
    end

    trackedItems = db.characters[key]
    TidyList()
    UpdateBars()
end

-- /bt copy <character>: adds that character's bars to this one's.
local function CopyFromCharacter(text)
    local db = _G.BarTabDB
    local wanted = string.lower(text or "")
    if wanted == "" then
        Print("Use: /bt copy <character name>")
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
            .. ". Use the full name shown, e.g. /bt copy " .. matches[1])
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

_G.SLASH_BARTAB1 = "/bt"
SlashCmdList.BARTAB = function(message)
    local command, args = message:match("^%s*(%S+)%s*(.-)%s*$")
    command = string.lower(command or "")
    args = Trim(args)

    if command == "track" then
        local name, startCount, goal, err = ParseTrackArgs(StripLinks(args))
        if not name then
            Print(err or "Use: /bt track Item Name [max] or /bt track Item Name min-max")
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
            Print("Use: /bt assign Item Name [min-max] (with a recipe selected)")
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
            for key in pairs(trackedItems) do
                trackedItems[key] = nil
            end
            UpdateBars()
            Print("Stopped tracking all items.")
        else
            local key = FindKeyByName(StripLinks(args), "untrack")
            if key then
                UntrackItem(key)
            end
        end

    elseif command == "quests" then
        ImportAllQuests()

    elseif command == "inline" then
        local value = string.lower(args)
        if value == "on" or value == "off" then
            SetInlineQuests(value == "on")
        end
        Print("Quest bars under their quests in the quest tracker: "
            .. (inlineQuestsActive and "on" or "off")
            .. ". Use /bt inline on or /bt inline off to change it.")

    elseif command == "debug" then
        -- Troubleshooting only; not listed in /bt help or the README.
        local itemFilter = args:match("^[Ii][Tt][Ee][Mm]%s+(.+)$")
        if string.lower(args) == "name" then
            Print("Character name sources:")
            for _, source in ipairs(CharacterNameSources()) do
                Print("  " .. source.label .. ": " .. source.value)
            end
        elseif itemFilter then
            DebugItems(itemFilter)
        else
            DebugQuests(args)
        end

    elseif command == "help" or command == "" or command == "?" then
        ShowHelp()

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

    elseif command == "craft" then
        CraftNextReady()

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
                .. ". Use /bt window auto|on|off|reset|lock|unlock.")
        end

    elseif command == "session" then
        if string.lower(args) == "reset" then
            ResetSessionStats()
            UpdateBars()
            Print("Session stats reset.")
        else
            Print("Session stats (gained, rate, time to goal) are in each bar's tooltip and start over at login or /reload. Use /bt session reset to start over now.")
        end

    elseif command == "copy" then
        CopyFromCharacter(args)

    elseif command == "item" then
        local filter = string.lower(StripLinks(args))
        if filter == "" then
            Print("Use: /bt item <item name or shift-clicked link>, e.g. /bt item Waylaid Crate")
        else
            ScanForContainers(filter)
        end

    elseif command == "autoitems" then
        local value = string.lower(args)
        if value == "on" or value == "off" then
            settings.autoItems = (value == "on")
        end
        Print("Auto-tracking fill-up items (like Waylaid Crates) when they reach your bags is "
            .. (settings.autoItems and "on" or "off") .. ". Use /bt autoitems on or off to change it.")

    elseif command == "auto" then
        local value = string.lower(args)
        if value == "on" or value == "off" then
            settings.autoQuests = (value == "on")
        end
        Print("Auto-tracking quest items when you accept a quest is "
            .. (settings.autoQuests and "on" or "off")
            .. ". Use /bt auto on or /bt auto off to change it.")

    else
        Print("Commands: /bt help, /bt config, /bt track, /bt assign, /bt unassign, /bt untrack, /bt copy, /bt share, /bt import, /bt window, /bt craft, /bt session reset, /bt quests, /bt item, /bt auto on|off, /bt autoitems on|off, /bt inline on|off")
        Print("Type /bt help for a quick guide with examples.")
    end
end

-- Watches bags for new fill-up items (Waylaid Crates etc.).
containerScanPending = false
function QueueContainerScan(delay)
    if containerScanPending then return end
    containerScanPending = true
    C_Timer.After(delay, function()
        containerScanPending = false
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
for _, questEvent in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    pcall(events.RegisterEvent, events, questEvent)
end

events:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            _G.BarTabDB = _G.BarTabDB or {}
            -- Each character's bars are picked at PLAYER_LOGIN (the
            -- character's name isn't reliably known before that).
            trackedItems = {}
            _G.BarTabSettings = _G.BarTabSettings or {}
            settings = _G.BarTabSettings
            if settings.autoQuests == nil then
                settings.autoQuests = true
            end
            -- Inline quest bars run inside Blizzard's quest-tracker layout,
            -- which on this client can break the tracker (quests stop
            -- updating). Off by default since 1.5; switched off once for
            -- everyone who had the old default.
            if settings.inlineQuests == nil or not settings.inlineDefaultOff then
                settings.inlineQuests = false
            end
            settings.inlineDefaultOff = true
            if settings.autoItems == nil then
                settings.autoItems = true
            end
            settings.barHeight = settings.barHeight or 20
            settings.textSize = settings.textSize or 12
            settings.palette = settings.palette or "colorblind"
            settings.hiddenSections = settings.hiddenSections or {}
            ApplyPalette(settings.palette)
            if settings.inlineQuests then
                inlineQuestsActive = InstallInlineHooks()
            end
            -- Carry over zone collapse states from the old "Quests" section.
            if settings.collapsed then
                local moved = {}
                for key, value in pairs(settings.collapsed) do
                    local zone = type(key) == "string" and key:match("^Quests/(.+)$")
                    if zone then moved[key] = zone end
                end
                for key, zone in pairs(moved) do
                    settings.collapsed[QUEST_SECTION .. "/" .. zone] = settings.collapsed[key]
                    settings.collapsed[key] = nil
                end
            end
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        BindCharacterList()
    elseif event:find("^UNIT_SPELLCAST_") then
        -- Follow our craft so the silently loaded profession isn't closed under it.
        if arg1 == "player" then
            if crafting then crafting.last = GetTime() end
            if event == "UNIT_SPELLCAST_SUCCEEDED" and arg3 then
                OnCraftSucceeded(arg3)
            elseif crafting and (event == "UNIT_SPELLCAST_FAILED"
                or event == "UNIT_SPELLCAST_INTERRUPTED") then
                crafting = nil
            end
        end
    elseif event == "TRADE_SKILL_SHOW" then
        OnTradeSkillShow()
    elseif event == "TRADE_SKILL_CLOSE" then
        silent.loaded = nil
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Last chance to switch secure overlays off before combat lockdown.
        HideAllOverlays()
    elseif event == "QUEST_ACCEPTED" then
        -- Retail passes questID; some clients pass (logIndex, questID).
        local questID = arg2 or arg1
        if settings.autoQuests and questID then
            ImportQuestWhenReady(questID, true)
        end
    elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        if arg1 then
            RemoveQuest(arg1)
        end
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
        HookQuestTrackerMenu()
        RegisterOptionsPage()
        UpdateMinimapButton()
        -- In case the quest tracker wasn't loaded yet when BarTab loaded.
        if settings.inlineQuests and not inlineQuestsActive then
            inlineQuestsActive = InstallInlineHooks()
        end
        C_Timer.After(0.5, function()
            if not SetUpTracker() then
                Print("Couldn't add a section to the objective tracker; using standalone bars.")
            end
            UpdateBars()
        end)
        RequestUpdate(1)
        QueueContainerScan(2)
    else
        RequestUpdate(0.2)
        QueueContainerScan(0.3)
    end
end)
