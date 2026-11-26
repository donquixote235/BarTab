-- BarTab: crafting from bars (incl. with the profession window closed), bar frames.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

-- Crafting with the profession window closed -------------------------------
--
-- The game only crafts while the recipe's profession is loaded, and it
-- unloads a profession when its window closes. Loading one (OpenTradeSkill)
-- is allowed from a hover or a click, and normally pops up the window via
-- whatever frames listen for TRADE_SKILL_SHOW. Muting those frames for that
-- one event loads the profession without the window ("silent load").
-- Hovering a crafting bar loads its profession ahead of the click; a click
-- loads it if needed and crafts once it's ready. A silently loaded
-- profession is closed again once nothing needs it.
-- (Same approach as the QuickCraft Forever addon.)

silent = {}          -- .waiting, .loaded (profession name), .idle
mutedFrames = {}

-- /bartab debug craft: a timestamped log of crafting steps, saved with
-- /reload, for bug reports.
function CraftLog(message)
    if not settings.debugCraft then return end
    local line = ("%.2f %s"):format(GetTime(), message)
    settings.debugLog = settings.debugLog or {}
    table.insert(settings.debugLog, line)
    while #settings.debugLog > 300 do table.remove(settings.debugLog, 1) end
end

function ProfessionsOpen()
    return ProfessionsFrame ~= nil and ProfessionsFrame.IsShown ~= nil
        and ProfessionsFrame:IsShown() and true or false
end

-- Name and ID of the profession the game has loaded, if any.
function LoadedProfession()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then return nil end
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if ok and type(info) == "table" and info.professionName and info.professionName ~= "" then
        -- The game can report ID 0 (unknown); that's no ID at all.
        local id = tonumber(info.professionID)
        return info.professionName, (id and id > 0) and id or nil
    end
end

-- The profession's skill line ID (165 for Leatherworking), used to load it.
-- An ID of 0 (saved from a moment the game didn't know it) is ignored.
function GetProfessionSkillLine(item)
    if item.skillLineID and item.skillLineID > 0 then return item.skillLineID end
    item.skillLineID = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLineForRecipe then
        local ok, tradeSkillID, _, parentID =
            pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, item.recipeID)
        if ok then
            local id = (parentID and parentID > 0) and parentID or tradeSkillID
            if id and id > 0 then
                item.skillLineID = id
                return id
            end
        end
    end
    -- Else by name, from your professions.
    if item.profession and GetProfessions and GetProfessionInfo then
        local indexes = { GetProfessions() }
        for i = 1, 6 do
            if indexes[i] then
                local okInfo, name, _, _, _, _, _, skillLine = pcall(GetProfessionInfo, indexes[i])
                if okInfo and name and skillLine and skillLine > 0
                    and string.lower(name) == string.lower(item.profession) then
                    item.skillLineID = skillLine
                    return skillLine
                end
            end
        end
    end
end

function IsProfessionLoaded(item)
    local name, id = LoadedProfession()
    if not name then return false end
    return name == item.profession
        or (id ~= nil and id == GetProfessionSkillLine(item))
end

function Unmute()
    if not silent.waiting then return end
    silent.waiting = false
    for _, frame in ipairs(mutedFrames) do
        frame:RegisterEvent("TRADE_SKILL_SHOW")
    end
    wipe(mutedFrames)
end

-- Must run from a hover or click. Returns whether the game accepted it.
function SilentLoad(item)
    if InCombatLockdown() or ProfessionsOpen() then return false end
    local skillLine = GetProfessionSkillLine(item)
    if not (skillLine and C_TradeSkillUI.OpenTradeSkill) then return false end

    Unmute()
    if GetFramesRegisteredForEvent then
        for _, frame in ipairs({ GetFramesRegisteredForEvent("TRADE_SKILL_SHOW") }) do
            if not (frame.IsForbidden and frame:IsForbidden()) and not frame.barTabOwn then
                frame:UnregisterEvent("TRADE_SKILL_SHOW")
                mutedFrames[#mutedFrames + 1] = frame
            end
        end
    end
    silent.waiting = true
    silent.profession = item.profession
    silent.token = (silent.token or 0) + 1
    local token = silent.token
    C_Timer.After(1.5, function()
        if silent.token == token then Unmute() end
    end)

    local ok, result = pcall(C_TradeSkillUI.OpenTradeSkill, skillLine)
    if not (ok and result ~= false) then
        Unmute()
        return false
    end
    return true
end

-- TRADE_SKILL_SHOW while muted: the profession loaded without its window.
function OnTradeSkillShow()
    if not silent.waiting then return end
    silent.loaded = silent.profession
    silent.idle = nil
    -- Next frame, so the muted frames don't receive this event after all.
    C_Timer.After(0, Unmute)
end

-- How long crafts take -------------------------------------------------------
-- The time BarTab saw a recipe take last (settings.craftTimes[recipeID], in
-- seconds), else the cast time the game gives for it. nil if unknown or
-- instant.
castStarts = {}

function CraftSeconds(recipeID)
    local seen = settings.craftTimes and settings.craftTimes[recipeID]
    if seen then return seen end
    local ms
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, recipeID)
        if ok and type(info) == "table" then ms = info.castTime end
    end
    if not ms and GetSpellInfo then
        local ok, _, _, _, castTime = pcall(GetSpellInfo, recipeID)
        if ok then ms = castTime end
    end
    ms = tonumber(ms)
    if ms and ms > 0 then return ms / 1000 end
    return nil
end

-- "about 45 sec", "about 4 min", "about 1 h 20 min".
function FormatDuration(seconds)
    if seconds < 60 then
        return ("about %d sec"):format(math.max(1, math.floor(seconds / 5 + 0.5) * 5))
    end
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return ("about %d min"):format(minutes) end
    local hours = math.floor(minutes / 60)
    local rest = minutes - hours * 60
    return rest > 0 and ("about %d h %d min"):format(hours, rest) or ("about %d h"):format(hours)
end

-- "about 4 min" for that many crafts of the recipe; nil if unknown or quick.
function BatchTimeText(recipeID, crafts)
    local each = CraftSeconds(recipeID)
    if not (each and crafts and crafts > 0) then return nil end
    local total = each * crafts
    if total < 10 then return nil end
    return FormatDuration(total)
end

function NoteCraftStarted(recipeID)
    castStarts[recipeID] = GetTime()
end

function NoteCraftFinished(recipeID)
    local started = castStarts[recipeID]
    castStarts[recipeID] = nil
    if not started then return end
    local seconds = GetTime() - started
    if seconds > 0.3 and seconds < 900 then
        settings.craftTimes = settings.craftTimes or {}
        settings.craftTimes[recipeID] = math.floor(seconds * 10 + 0.5) / 10
    end
end

function CraftNow(item, amount)
    CraftLog("CraftRecipe " .. tostring(item.recipeID) .. " x" .. tostring(amount)
        .. " (craftable " .. tostring(GetCraftableCount(item.recipeID)) .. ", loaded silently: " .. tostring(silent.loaded ~= nil) .. ")")
    crafting = { id = item.recipeID, amount = amount, done = 0, last = GetTime() }
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, item.recipeID, amount)
    if not ok then
        crafting = nil
        Print("Craft failed: " .. tostring(err))
        return
    end
    -- Long batches say how long they'll take.
    local each = CraftSeconds(item.recipeID)
    if each and each * amount >= 30 then
        Print(("Crafting %d %s, %s."):format(amount, GetRecipeName(item.recipeID) or DisplayName(item),
            FormatDuration(each * amount)))
    end
end

function RunCraftJob()
    local job = craftJob
    if not job then return end
    if GetTime() - job.time > 3 then
        craftJob = nil
        Print("Couldn't load " .. (job.item.profession or "the profession")
            .. " to craft " .. DisplayName(job.item) .. ". Try opening its window.")
    elseif IsProfessionLoaded(job.item) then
        craftJob = nil
        CraftNow(job.item, job.amount)
    else
        C_Timer.After(0.1, RunCraftJob)
    end
end

-- Runs from the click.
function TryCraft(item, amount)
    if InCombatLockdown() then
        Print("Nothing can be crafted in combat.")
        return
    end
    if IsProfessionLoaded(item) then
        CraftNow(item, amount)
    elseif ProfessionsOpen() then
        Print("The profession window is showing another profession; switch it to "
            .. (item.profession or "the right one") .. " or close it, then click again.")
    else
        craftJob = { item = item, amount = amount, time = GetTime() }
        if SilentLoad(item) then
            RunCraftJob()
        else
            craftJob = nil
            Print("Open your " .. (item.profession or "profession") .. " window to craft "
                .. DisplayName(item) .. ".")
        end
    end
end

-- Hovering a crafting bar loads its profession ahead of the click.
function PreloadProfession(item)
    if item and item.recipeID and not IsProfessionLoaded(item) then
        SilentLoad(item)
    end
end

-- Closes a silently loaded profession once nothing needs it. Never during a
-- craft: closing would stop a multi-craft partway.
function IsMouseOverCraftBar()
    for _, bar in ipairs(bars) do
        if bar:IsVisible() and bar:IsMouseOver() then return true end
    end
    return false
end

-- Whether you're casting right now (a craft can take a minute or more).
function CastingNow()
    if UnitCastingInfo and UnitCastingInfo("player") then return true end
    if UnitChannelInfo and UnitChannelInfo("player") then return true end
    return false
end

function CraftTick()
    if crafting then
        -- Gone quiet for 20 seconds: the batch has ended without telling us.
        -- Not while a craft is still being cast or the game is repeating it.
        if CastingNow() or IsRepeatingCraft() then
            crafting.last = GetTime()
        elseif GetTime() - crafting.last > 20 then
            CraftLog("batch timed out (nothing for 20 seconds)")
            crafting = nil
        end
    end
    if not silent.loaded then return end
    if ProfessionsOpen() then
        silent.loaded = nil -- the visible window owns it now
    elseif crafting or craftJob or chainJob or IsMouseOverCraftBar() or InCombatLockdown()
        or CastingNow() or IsRepeatingCraft() then
        silent.idle = nil
    else
        silent.idle = (silent.idle or 0) + 0.5
        if silent.idle >= 1.5 then
            silent.loaded, silent.idle = nil, nil
            CraftLog("closing the silently loaded profession (idle)")
            if C_TradeSkillUI.CloseTradeSkill then
                C_TradeSkillUI.CloseTradeSkill()
            end
        end
    end
end
C_Timer.NewTicker(0.5, function() CraftTick() end)

-- Opens the profession window on the bar's recipe (Ctrl-click, or "Open
-- recipe" on the right-click menu).
function OpenBarRecipe(itemKey)
    local item = itemKey and trackedItems[itemKey]
    if not item then return end
    if not item.recipeID or item.container then
        Print(DisplayName(item) .. " has no recipe. Right-click it to assign one, with the recipe selected in the profession window.")
        return
    end
    if InCombatLockdown() then
        Print("Professions can't be opened in combat.")
        return
    end
    -- A profession BarTab loaded without its window has to be closed first,
    -- or opening it again doesn't bring the window up.
    if silent.loaded and not ProfessionsOpen() then
        silent.loaded, silent.idle = nil, nil
        if C_TradeSkillUI.CloseTradeSkill then pcall(C_TradeSkillUI.CloseTradeSkill) end
    end
    Unmute()
    local recipeID = item.recipeID
    if C_TradeSkillUI.OpenRecipe and pcall(C_TradeSkillUI.OpenRecipe, recipeID) then
        C_Timer.After(0.3, function() SelectRecipeInWindow(recipeID) end)
        return
    end
    local skillLine = GetProfessionSkillLine(item)
    if skillLine and C_TradeSkillUI.OpenTradeSkill and pcall(C_TradeSkillUI.OpenTradeSkill, skillLine) then
        C_Timer.After(0.3, function() SelectRecipeInWindow(recipeID) end)
    else
        Print("Couldn't open " .. (item.profession or "the profession") .. ". Try opening its window yourself.")
    end
end

-- Selects the recipe once the profession window is up, if the game didn't.
function SelectRecipeInWindow(recipeID, tries)
    tries = tries or 0
    if not ProfessionsOpen() then
        if tries < 10 then
            C_Timer.After(0.2, function() SelectRecipeInWindow(recipeID, tries + 1) end)
        end
        return
    end
    if GetSelectedRecipeID() == recipeID then return end
    local page = ProfessionsFrame.CraftingPage
    local list = page and page.RecipeList
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    if list and list.SelectRecipe and ok and info then
        pcall(list.SelectRecipe, list, info, true)
    elseif page and page.SelectRecipe and ok and info then
        pcall(page.SelectRecipe, page, info)
    end
end

-- action: what to do ("one", "fit", "max"); by default whatever this click
-- (with its modifier) is set to do.
function CraftItem(itemKey, action)
    local item = trackedItems[itemKey]
    if item and item.notLearned then
        Print("You haven't learned " .. (item.recipeName or DisplayName(item)) .. " yet"
            .. (item.needSkill and (" (needs " .. item.needSkill .. ")") or "") .. ".")
        return
    end

    if item and item.container then
        local count, full = GetFillState(item)
        if not full then
            Print("Still need " .. (item.goal - count) .. " more " .. item.name .. ".")
        elseif not FindFullStack(item.name, item.goal) and not InCombatLockdown() then
            if MergeStacks(item.name) then
                Print("Combining your " .. item.name .. " stacks; click again when the bar says Ready.")
            else
                Print("Couldn't combine your " .. item.name .. " stacks into one of "
                    .. item.goal .. "; it may not stack that high.")
            end
        elseif InCombatLockdown() then
            Print("Can't use items in combat.")
        else
            Print("Click the bar itself (not the name) to use " .. item.container.name .. ".")
        end
        return
    end

    if item and item.altNeed then
        Print(("%s's bars need %d %s; gather them and BarTab offers to mail them at a mailbox."):format(
            item.altName, item.goal, item.name))
        return
    end
    if not item or not item.recipeID then
        Print("No recipe assigned to this item.")
        return
    end

    -- What this click does is chosen in the settings window.
    local chosen = action or GetClickAction(CurrentModifier())
    -- Short of a material you can make: make it first (settings.chainCraft).
    if chosen ~= "none" and TryChainCraft(item, chosen) then return end
    local amount, problem = ResolveCraftAmount(item, chosen)
    if not amount then
        if problem then Print(ChainBlockedText(item) or problem) end
        return
    end
    -- A bar for what the recipe makes: craft only what's still missing.
    if IsOutputBar(item) then
        local crafts = CraftsToTarget(item)
        if crafts <= 0 then
            Print(("You already have %d %s."):format(CountItem(item), item.name))
            return
        end
        if chosen ~= "one" then
            local craftable = GetCraftableCount(item.recipeID)
            amount = craftable and math.min(craftable, crafts) or crafts
        end
    end

    -- Say what's missing rather than letting the game quietly refuse.
    local craftable = GetCraftableCount(item.recipeID)
    if craftable and craftable < 1 then
        local short = {}
        for _, reagent in ipairs(GetRecipeReagents(item.recipeID) or {}) do
            if reagent.have < reagent.need then
                local okNote, note = pcall(AltNote, reagent.itemID, reagent.name)
                short[#short + 1] = reagent.name .. " (" .. reagent.have .. "/" .. reagent.need
                    .. ((okNote and note) and ("; " .. note) or "") .. ")"
            end
        end
        local chainText = ChainBlockedText(item)
        if chainText then
            Print(chainText)
            return
        end
        Print("Can't craft " .. DisplayName(item) .. " yet"
            .. (#short > 0 and (": missing " .. table.concat(short, ", ")) or "") .. ".")
        return
    end

    TryCraft(item, amount)
end

function CreateBar(key, barID)
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetSize(240, 20)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.08, 0.08, 0.08, 0.85)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    -- Keep the text inside the bar; anything too long is cut off with "...".
    text:SetPoint("LEFT", 4, 0)
    text:SetPoint("RIGHT", -4, 0)
    text:SetJustifyH("CENTER")
    if text.SetWordWrap then text:SetWordWrap(false) end
    bar.text = text
    bar.isBar = true

    -- Shown on the bar you're about to drop onto while Ctrl-dragging.
    local dropHighlight = bar:CreateTexture(nil, "OVERLAY")
    dropHighlight:SetAllPoints()
    dropHighlight:SetColorTexture(1, 0.82, 0, 0.35)
    dropHighlight:Hide()
    bar.dropHighlight = dropHighlight

    bar:EnableMouse(true)

    -- Refresh the tooltip if Shift or Alt is pressed or released while
    -- hovering (only watched while the mouse is over the bar).
    local function WatchModifiers(self)
        if not self:IsMouseOver() then
            self:SetScript("OnUpdate", nil)
            return
        end
        local modifiers = (IsShiftKeyDown() and 1 or 0) + (IsAltKeyDown() and 2 or 0)
        if modifiers ~= self.lastModifiers then
            self.lastModifiers = modifiers
            ShowBarTooltip(self)
        end
    end

    bar:SetScript("OnEnter", function(self)
        ShowBarTooltip(self)
        PreloadProfession(trackedItems[self.itemKey])
        self.lastModifiers = (IsShiftKeyDown() and 1 or 0) + (IsAltKeyDown() and 2 or 0)
        self:SetScript("OnUpdate", WatchModifiers)
    end)

    bar:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", nil)
    end)

    bar:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsControlKeyDown() then
            self.dragStarted = true
            BeginDrag(self)
        end
    end)

    bar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            ShowItemMenu(self, self.itemKey)
            return
        end
        if button ~= "LeftButton" then return end

        -- A Ctrl-drag never crafts. Dropped on another bar it reorders;
        -- released on the same bar it's a Ctrl-click: open the recipe.
        if self.dragStarted then
            self.dragStarted = nil
            if not EndDrag() then OpenBarRecipe(self.itemKey) end
            return
        end

        CraftItem(self.itemKey)
    end)

    bar.itemKey = key
    bars[#bars + 1] = bar
    barsByKey[barID] = bar
    return bar
end

-- Each section keeps its own bar per item. When an item moves to another
-- section (e.g. after assigning a recipe), it gets a new bar there, so the old
-- section tidying up its bar can't hide the one now in use.
function GetBar(key, section)
    local barID = (section or "") .. "\0" .. key
    return barsByKey[barID] or CreateBar(key, barID)
end


-- After a craft ----------------------------------------------------------------
-- Each recipe bar can be kept (default), moved to Inactive, or untracked once
-- its recipe has been crafted (the whole batch): item.afterCraft.
AFTER_CRAFT_MODES = {
    { key = "keep", name = "Keep the bar", phrase = "keep the bar" },
    { key = "inactive", name = "Move to Inactive", phrase = "move to Inactive" },
    { key = "untrack", name = "Untrack", phrase = "untrack" },
}

function IsTrackedRecipe(recipeID)
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container then
            return true
        end
    end
    return false
end

-- reason: said instead of "crafted" when something else finished the
-- recipe's job (its appearance got collected).
function AfterCraftDone(recipeID, reason)
    if not recipeID then return end
    CraftLog("after-craft check " .. tostring(recipeID) .. (reason and (" (" .. reason .. ")") or ""))
    if not reason then Safe("appearances", RemindToEquip)(recipeID) end
    -- Counting down: the rule waits until no crafts are left.
    if not reason then
        local left = CraftsLeft(recipeID)
        if left and left > 0 then return end
    end
    local moved, removed, name = 0, 0, nil
    for key, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container then
            if item.afterCraft == "untrack" then
                trackedItems[key] = nil
                removed = removed + 1
                name = name or DisplayName(item)
            elseif item.afterCraft == "inactive" and not item.inactive then
                item.inactive = true
                if item.countFrom then -- full size again in Inactive
                    item.goal, item.countFrom, item.countDone = item.countFrom, nil, nil
                end
                moved = moved + 1
                name = name or DisplayName(item)
            end
        end
    end
    -- Bars the rule kept (countdown run out) go to Inactive at full size.
    local restart = not reason and CraftsLeft(recipeID) == 0
    if moved + removed == 0 then
        if restart then RestartCountdown(recipeID) end
        return
    end
    if removed > 0 and settings.recipeFocus and not IsTrackedRecipe(recipeID) then
        settings.recipeFocus[recipeID] = nil
    end
    UpdateBars()
    local parts = {}
    if removed > 0 then parts[#parts + 1] = "untracked " .. removed .. " bar(s)" end
    if moved > 0 then parts[#parts + 1] = "moved " .. moved .. " bar(s) to Inactive" end
    Print(name .. " " .. (reason or "crafted") .. "; " .. table.concat(parts, ", ") .. ".")
    if restart then RestartCountdown(recipeID) end
end

-- Right-click submenu for a recipe bar. allBars (from the profession
-- window's BarTab button): set it on every bar of the recipe.
function AfterCraftMenuEntry(item, allBars)
    local current = item.afterCraft or "keep"
    local choices = {}
    for _, mode in ipairs(AFTER_CRAFT_MODES) do
        choices[#choices + 1] = {
            mode.name,
            function()
                local value = (mode.key ~= "keep") and mode.key or nil
                if allBars then
                    for _, other in pairs(trackedItems) do
                        if other.recipeID == item.recipeID and not other.container then
                            other.afterCraft = value
                        end
                    end
                else
                    item.afterCraft = value
                end
                Print(DisplayName(item) .. ": after crafting, " .. mode.phrase .. ".")
            end,
            selected = current == mode.key,
        }
    end
    return { "After crafting", choices = choices }
end

function AfterCraftLabel(item)
    for _, mode in ipairs(AFTER_CRAFT_MODES) do
        if mode.key == item.afterCraft and mode.key ~= "keep" then return mode.phrase end
    end
end

-- Called on each successful craft cast. Crafts BarTab started finish when
-- their count is reached; crafts from the profession window when the
-- window's queue (Create All / a typed amount) runs out.
-- The rules wait for the bag update that takes the craft's materials out of
-- your bags. Run before that, a removed bar's share of a shared material
-- would briefly go to the other bars, counting materials already used up
-- (and could set off their goal alerts).
pendingAfterCraft = {}

function QueueAfterCraft(recipeID)
    pendingAfterCraft[recipeID] = true
    -- In case no bag update comes (nothing left the bags), go ahead anyway.
    C_Timer.After(2, function()
        ApplyCountdowns()
        if pendingAfterCraft[recipeID] then
            pendingAfterCraft[recipeID] = nil
            AfterCraftDone(recipeID)
        end
    end)
end

function RunPendingAfterCraft()
    if not next(pendingAfterCraft) and not next(pendingCountdown) then return end
    -- Next frame, once the bag counts have refreshed.
    C_Timer.After(0.1, function()
        ApplyCountdowns()
        for recipeID in pairs(pendingAfterCraft) do
            pendingAfterCraft[recipeID] = nil
            AfterCraftDone(recipeID)
        end
    end)
end

-- Counting down --------------------------------------------------------------
-- With "Count down as you craft" (item.countDown, or settings.countDownDefault
-- for bars not set either way), each craft lowers the goal of each of the
-- recipe's ingredient bars by one craft's worth: 8/32 Bolt of Linen Cloth
-- for 8 Red Linen Bags becomes 4/28 after one, not 4/32. The After crafting
-- rule then waits for the count to run out; with "keep the bar" the bars go
-- back to their full size for another round. Like the rule, the countdown
-- waits for the bag update, so a bar never briefly counts materials the
-- craft already used.
pendingCountdown = {} -- recipeID -> crafts not yet counted down

function CountsDown(item)
    if item.container or not item.recipeID then return false end
    if item.skillGoal then return false end -- sized by skill instead
    if item.countDown ~= nil then return item.countDown end
    return settings.countDownDefault and true or false
end

-- The recipe's ingredient bars that count down, each with its per-craft amount.
function CountdownBars(recipeID)
    local list = {}
    for key, item in pairs(trackedItems) do
        if item.recipeID == recipeID and CountsDown(item) then
            local need = GetReagentQuantity(recipeID, item.name)
            if need and need > 0 then list[#list + 1] = { key = key, item = item, need = need } end
        end
    end
    return list
end

-- Crafts left before the countdown runs out (nil: the recipe doesn't count down).
function CraftsLeft(recipeID)
    local left
    for _, entry in ipairs(CountdownBars(recipeID)) do
        local crafts = entry.item.countDone and 0
            or math.floor(((entry.item.goal or 0) - (entry.item.start or 0)) / entry.need)
        left = math.min(left or crafts, crafts)
    end
    return left
end

function QueueCountdown(recipeID)
    pendingCountdown[recipeID] = (pendingCountdown[recipeID] or 0) + 1
    C_Timer.After(2, ApplyCountdowns)
end

function ApplyCountdowns()
    if not next(pendingCountdown) then return end
    CraftLog("countdown applied")
    local changed = false
    for recipeID, crafts in pairs(pendingCountdown) do
        pendingCountdown[recipeID] = nil
        for _, entry in ipairs(CountdownBars(recipeID)) do
            local item = entry.item
            item.countFrom = item.countFrom or item.goal
            local goal = item.goal - entry.need * crafts
            if goal <= (item.start or 0) then
                -- Last craft: the bar keeps its size until the After
                -- crafting rule deals with it (a goal of nothing would count
                -- as reached and set off its alert).
                item.countDone = true
            else
                item.goal = goal
            end
            changed = true
        end
    end
    if changed then UpdateBars() end
end

-- Countdown ran out and the bars are kept: they move to Inactive at full
-- size, out of the way but ready to use again.
function RestartCountdown(recipeID)
    local name
    for _, entry in ipairs(CountdownBars(recipeID)) do
        local item = entry.item
        if item.countFrom then
            item.goal, item.countFrom, item.countDone = item.countFrom, nil, nil
            item.inactive = true
            name = name or DisplayName(item)
        end
    end
    if name then
        UpdateBars()
        Print(name .. ": all crafts done; its bars moved to Inactive (full size again, for next time).")
    end
end

-- Sizing a recipe's bars by crafts (right-click > Crafts): 1, 5, 10, or as
-- many as it takes to reach the next multiple of 5 in the profession (at
-- 162 Leatherworking: 3 crafts, to 165), assuming a skill point a craft.
function SizeRecipeBars(recipeID, crafts, quiet)
    local name
    for key, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container then
            local need = GetReagentQuantity(recipeID, item.name)
            if need and need > 0 then
                item.goal = (item.start or 0) + need * crafts
                item.countFrom, item.countDone = nil, nil
                item.skillGoal = nil -- a size you picked replaces the skill sizing
                -- A size you just picked isn't a goal you just reached: no alert.
                goalReached[key] = nil
                name = name or DisplayName(item)
            end
        end
    end
    if name and not quiet then
        UpdateBars()
        Print(name .. ": bars sized for " .. crafts .. (crafts == 1 and " craft." or " crafts."))
    end
end

-- How many crafts the recipe's bars are sized for now (nil if unknown).
function SizedCrafts(item)
    local need = GetReagentQuantity(item.recipeID, item.name)
    if not need or need <= 0 then return nil end
    return math.floor(((item.goal or 0) - (item.start or 0)) / need)
end

function CraftsMenuEntry(item)
    if not GetReagentQuantity(item.recipeID, item.name) then return nil end
    local current = SizedCrafts(item)
    local choices = {}
    for _, crafts in ipairs({ 1, 5, 10 }) do
        choices[#choices + 1] = {
            crafts == 1 and "1 craft" or (crafts .. " crafts"),
            function() SizeRecipeBars(item.recipeID, crafts) end,
            selected = current == crafts,
        }
    end
    local skill, profession, cap = GetProfessionSkill(item)
    if skill then
        local tier = (math.floor(skill / 5) + 1) * 5
        if cap and cap > 0 then tier = math.min(tier, cap) end
        local crafts = tier - skill
        if crafts > 0 then
            choices[#choices + 1] = {
                ("To %s %d (%d %s)"):format(profession or "skill", tier, crafts, crafts == 1 and "craft" or "crafts"),
                function() SizeRecipeBars(item.recipeID, crafts) end,
                selected = current == crafts,
            }
        end
    end
    -- As many crafts as this bar's material in your bags covers (37 Heavy
    -- Leather at 8 a craft: 4). Other ingredients (thread, dye) can be bought.
    local need = GetReagentQuantity(item.recipeID, item.name)
    local have = CountItem(item)
    local fromBags = need and need > 0 and math.floor(have / need) or 0
    if fromBags > 0 then
        choices[#choices + 1] = {
            ("Use all your %s (%d %s)"):format(item.name, fromBags, fromBags == 1 and "craft" or "crafts"),
            function() SizeRecipeBars(item.recipeID, fromBags) end,
            selected = current == fromBags,
        }
    end
    -- A full stack of what the recipe makes (10 Heavy Armor Kits: 10 crafts).
    local stackCrafts, stackSize = StackCrafts(item.recipeID)
    if stackCrafts then
        choices[#choices + 1] = {
            stackCrafts == stackSize
                and ("A full stack (%d crafts)"):format(stackCrafts)
                or ("A full stack of %d (%d %s)"):format(stackSize, stackCrafts, stackCrafts == 1 and "craft" or "crafts"),
            function() SizeRecipeBars(item.recipeID, stackCrafts) end,
            selected = current == stackCrafts,
        }
    end
    -- One dot: the first choice matching the bars' size, else "Other amount".
    local matched = false
    for _, choice in ipairs(choices) do
        if choice.selected and matched then choice.selected = false end
        if choice.selected then matched = true end
    end
    choices[#choices + 1] = {
        "Other amount...",
        function() AskCraftCount(item.recipeID, current) end,
        selected = current ~= nil and not matched,
    }
    -- Change what the bars are for: a goal for what the recipe makes, or a
    -- skill level.
    local outputID = GetRecipeOutput(item.recipeID)
    local outputName = outputID and GetItemNameByID(outputID)
    if outputName then
        choices[#choices + 1] = { "Until I have... (" .. outputName .. ")",
            function() AskMakeGoal(item.recipeID) end, selected = false }
    end
    choices[#choices + 1] = { "Until I reach a skill level...",
        function() AskSkillGoal(item.recipeID) end, selected = item.skillGoal ~= nil }
    return { "Crafts" .. (current and (" (" .. current .. ")") or ""), choices = choices }
end

-- Crafts for a "Make until I have..." bar: its target, or a different purpose.
function GoalCraftsMenuEntry(item)
    return { ("Crafts (until %d)"):format(item.goal), choices = {
        { ("Change target... (now %d)"):format(item.goal),
            function() AskMakeGoal(item.recipeID, item.goal) end, selected = true },
        { "Until I reach a skill level...", function() AskSkillGoal(item.recipeID) end, selected = false },
        { "Track its ingredients instead", function() GoalToIngredients(item) end, selected = false },
    } }
end

-- The recipe's "Make until I have..." bar, if any, removed.
function RemoveGoalBar(recipeID)
    for key, item in pairs(trackedItems) do
        if item.recipeID == recipeID and IsOutputBar(item) then
            trackedItems[key] = nil
        end
    end
end

-- From a goal bar back to an ingredient bar (the recipe's main ingredient),
-- sized for the crafts still to go (at least one).
function GoalToIngredients(item)
    local recipeID = item.recipeID
    local reagents = GetRecipeReagents(recipeID)
    if not reagents or #reagents == 0 then
        Print("Couldn't read this recipe's ingredients.")
        return
    end
    local crafts = math.max(1, CraftsToTarget(item))
    RemoveGoalBar(recipeID)
    local main = reagents[MainReagentIndex(reagents)]
    AssignMaterial(main.name, recipeID, 0, main.need * crafts)
    UpdateBars()
    Print(("%s: tracking %s for %d %s instead."):format(GetRecipeName(recipeID) or DisplayName(item),
        main.name, crafts, crafts == 1 and "craft" or "crafts"))
end

-- How many crafts make a full stack of what the recipe makes, and the stack
-- size; nil if it doesn't stack (or isn't known yet).
function StackCrafts(recipeID)
    local outputID, made = GetRecipeOutput(recipeID)
    if not outputID then return nil end
    local size
    if C_Item and C_Item.GetItemMaxStackSizeByID then
        local ok, value = pcall(C_Item.GetItemMaxStackSizeByID, outputID)
        if ok then size = tonumber(value) end
    end
    if not size then
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if getInfo then
            local results = { pcall(getInfo, outputID) }
            if results[1] then size = tonumber(results[9]) end
        end
    end
    if not size or size <= 1 then return nil end
    return math.ceil(size / math.max(1, made or 1)), size
end

-- "Other amount..." under Crafts: size the recipe's bars for any number.
function AskCraftCount(recipeID, current)
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    StaticPopupDialogs.BARTAB_CRAFT_COUNT = StaticPopupDialogs.BARTAB_CRAFT_COUNT or {
        text = "Size the bars of %s for how many crafts?",
        button1 = OKAY or "OK",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 4,
        OnShow = function(self, data)
            local box = self.editBox or self.EditBox
            if box then
                box:SetText(data.current and tostring(data.current) or "")
                box:HighlightText()
                box:SetFocus()
            end
        end,
        OnAccept = function(self, data)
            local box = self.editBox or self.EditBox
            ApplyCraftCount(data.recipeID, box and box:GetText())
        end,
        EditBoxOnEnterPressed = function(box, data)
            local parent = box:GetParent()
            data = data or parent.data
            ApplyCraftCount(data.recipeID, box:GetText())
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("BARTAB_CRAFT_COUNT", GetRecipeName(recipeID) or "this recipe", nil,
        { recipeID = recipeID, current = current })
end

function ApplyCraftCount(recipeID, text)
    local crafts = tonumber(text)
    if not crafts or crafts < 1 then
        Print("Give a number of crafts, 1 or more.")
        return
    end
    SizeRecipeBars(recipeID, math.floor(crafts))
end

-- Right-click toggle for a recipe bar (all of the recipe's bars together).
function CountdownMenuEntry(item)
    return {
        "Count down as you craft",
        function()
            local on = not CountsDown(item)
            for _, other in pairs(trackedItems) do
                if other.recipeID == item.recipeID and not other.container then
                    other.countDown = on
                    if not on then other.countFrom, other.countDone = nil, nil end
                end
            end
            Print(DisplayName(item) .. (on
                and ": each craft now takes one craft's worth off its bars."
                or ": bars keep their size as you craft."))
            UpdateBars()
        end,
        selected = CountsDown(item),
        isSelected = function() return CountsDown(item) end,
        check = true,
    }
end

-- A craft is starting that will bring the skill to a recipe's stop level:
-- an orange recipe always gives a point, so at one short of the level this
-- craft gets there. Stop the batch now and let this craft finish; waiting
-- for the skill-up would be too late, as the next craft has begun by then
-- (and addons can't cancel a craft in progress). Yellow and green recipes
-- don't always give a point, so those still stop on the skill-up.
function OnCraftStarted(recipeID)
    NoteCraftStarted(recipeID)
    if not IsTrackedRecipe(recipeID) then return end
    -- A "Make until I have..." goal this craft will reach (a craft always
    -- makes its item): stop the batch now, while this is the last craft.
    -- Checking after it finishes is too late; the next has begun by then.
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.inactive and IsOutputBar(item) then
            local _, made = GetRecipeOutput(recipeID)
            local have = CountItem(item)
            if have < item.goal and have + (made or 1) >= item.goal then
                local ours = crafting and crafting.id == recipeID
                local batch = (ours and crafting.amount > crafting.done + 1) or IsRepeatingCraft()
                if ours and crafting.amount > crafting.done + 1 then
                    crafting.amount = crafting.done + 1
                end
                -- Always stop: harmless with no batch, and whether the game
                -- says it's repeating isn't reliable.
                EndBatch()
                CraftLog("stopping after this craft of " .. tostring(recipeID) .. " (makes " .. item.goal .. ")")
                if batch then
                    Print(("Stopping after this %s: it makes %d."):format(item.name, item.goal))
                end
                return
            end
        end
    end
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container and item.untilSkill then
            local skill, profession = GetProfessionSkill(item)
            if skill and skill + 1 >= item.untilSkill and skill < item.untilSkill
                and GetRecipeColor(recipeID) == "orange" then
                local ours = crafting and crafting.id == recipeID
                if ours and crafting.amount > crafting.done + 1 then
                    crafting.amount = crafting.done + 1
                end
                if ours or IsRepeatingCraft() then
                    EndBatch()
                    CraftLog("stopping after this craft of " .. tostring(recipeID) .. " (reaches " .. item.untilSkill .. ")")
                    Print(("Stopping after this %s: it brings %s to %d."):format(DisplayName(item),
                        profession or item.profession or "your skill", item.untilSkill))
                end
            end
            return
        end
    end
end

function OnCraftSucceeded(spellID)
    lastCraftRecipe = spellID
    NoteCraftFinished(spellID)
    CraftLog("craft succeeded " .. tostring(spellID) .. (crafting and (" (" .. (crafting.done + 1) .. " of " .. crafting.amount .. ")") or " (not BarTab's)"))
    if spellID and IsTrackedRecipe(spellID) then
        for _, item in pairs(trackedItems) do
            if item.recipeID == spellID and CountsDown(item) then
                QueueCountdown(spellID)
                break
            end
        end
    end
    if crafting and spellID == crafting.id then
        crafting.done = crafting.done + 1
        if crafting.done >= crafting.amount then
            crafting = nil
            QueueAfterCraft(spellID)
        end
        return
    end
    if crafting or not IsTrackedRecipe(spellID) then return end
    local remaining = 0
    if C_TradeSkillUI and C_TradeSkillUI.GetRemainingRecasts then
        local ok, value = pcall(C_TradeSkillUI.GetRemainingRecasts)
        if ok and tonumber(value) then remaining = tonumber(value) end
    end
    if remaining <= 0 then
        QueueAfterCraft(spellID)
    end
end


-- Stop tracking ---------------------------------------------------------------
-- A recipe's bars can be untracked once its profession reaches a skill level
-- (item.untilSkill, e.g. Leatherworking 125) or once the recipe turns a
-- color (item.untilColor: "yellow", "green" or "gray"). One or the other.

RECIPE_COLORS = { "orange", "yellow", "green", "gray" }
COLOR_RANK = { orange = 1, yellow = 2, green = 3, gray = 4 }
COLOR_CODES = { orange = "ffff8040", yellow = "ffffff00", green = "ff40c040", gray = "ff808080" }
DIFFICULTY_COLORS = {
    [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray",
    optimal = "orange", medium = "yellow", easy = "green", trivial = "gray",
}

-- The recipe's color now, if the game will say (usually only while the
-- profession is loaded: hovering a bar or with the window open).
function GetRecipeColor(recipeID)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo) then return nil end
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    if not ok or type(info) ~= "table" or info.learned == false then return nil end
    local difficulty = info.relativeDifficulty
    if difficulty == nil then difficulty = info.difficulty end
    return difficulty ~= nil and DIFFICULTY_COLORS[difficulty] or nil
end

function ColorText(color)
    return "|c" .. (COLOR_CODES[color] or "ffffffff") .. color .. "|r"
end

-- Current skill in the item's profession, the profession's name, and its cap.
function GetProfessionSkill(item)
    local wantName = item.profession and string.lower(item.profession)
    if GetProfessions and GetProfessionInfo then
        local indexes = { GetProfessions() }
        for i = 1, 6 do
            local index = indexes[i]
            if index then
                local ok, name, _, rank, rankMax, _, _, skillLine = pcall(GetProfessionInfo, index)
                if ok and name and ((item.skillLineID and skillLine == item.skillLineID)
                    or (wantName and string.lower(name) == wantName)) then
                    return tonumber(rank), name, tonumber(rankMax)
                end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo and wantName then
        for index = 1, GetNumSkillLines() do
            local name, header, _, rank, _, _, rankMax = GetSkillLineInfo(index)
            if name and not header and string.lower(name) == wantName then
                return tonumber(rank), name, tonumber(rankMax)
            end
        end
    end
end

-- Recipes waiting on a "Stop tracking?" answer, asked one at a time.
stopPrompts = { queue = {}, waiting = {} }

function UntrackRecipe(recipeID)
    for key, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container then
            trackedItems[key] = nil
        end
    end
    UpdateBars()
end

function ShowNextStopPrompt()
    if stopPrompts.showing then return end
    local ask = table.remove(stopPrompts.queue, 1)
    if not ask then return end
    if not IsTrackedRecipe(ask.recipeID) then
        stopPrompts.waiting[ask.recipeID] = nil
        return ShowNextStopPrompt()
    end
    if not (StaticPopupDialogs and StaticPopup_Show) then
        stopPrompts.waiting[ask.recipeID] = nil
        UntrackRecipe(ask.recipeID)
        Print(ask.done)
        return ShowNextStopPrompt()
    end
    StaticPopupDialogs.BARTAB_STOP_ASK = StaticPopupDialogs.BARTAB_STOP_ASK or {
        text = "%s\nStop tracking it?",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, data)
            UntrackRecipe(data.recipeID)
            Print(data.done)
        end,
        OnCancel = function(_, data, reason)
            if reason == "clicked" then
                -- Keep the bars and drop the rule, so it doesn't ask again.
                SetStopRule(data.recipeID, nil, nil, true)
                Print(data.label .. ": kept; its stop rule is off now.")
            end
        end,
        OnHide = function()
            local current = stopPrompts.showing
            stopPrompts.showing = nil
            if type(current) == "table" then stopPrompts.waiting[current.recipeID] = nil end
            C_Timer.After(0.2, ShowNextStopPrompt)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        noCancelOnEscape = true, -- Escape = not now: ask again at the next check
    }
    stopPrompts.showing = ask
    StaticPopup_Show("BARTAB_STOP_ASK", ask.reason, nil, ask)
end

-- Stops a batch of the recipe in progress (from a bar, or the profession
-- window's Create All), if there is one.
-- Ends the batch for good. Asking the game to stop repeating isn't always
-- enough here, so a profession BarTab loaded in the background is closed
-- too: that ends the batch, and the craft being cast still finishes.
function EndBatch()
    if C_TradeSkillUI and C_TradeSkillUI.StopRecipeRepeat then
        pcall(C_TradeSkillUI.StopRecipeRepeat)
    end
    if silent.loaded and not ProfessionsOpen() then
        silent.loaded, silent.idle = nil, nil
        CraftLog("closing the silently loaded profession (batch stopped)")
        if C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill then pcall(C_TradeSkillUI.CloseTradeSkill) end
    end
end

function StopCraftingRecipe(recipeID, label, reason)
    local ours = crafting and crafting.id == recipeID
    local repeating = false
    if lastCraftRecipe == recipeID and C_TradeSkillUI and C_TradeSkillUI.IsRecipeRepeating then
        local ok, value = pcall(C_TradeSkillUI.IsRecipeRepeating)
        repeating = ok and value and true or false
    end
    -- Also a batch still being cast after BarTab lost track of it.
    local casting = lastCraftRecipe == recipeID and CastingNow()
    if not (ours or repeating or casting) then return end
    EndBatch()
    crafting = nil
    CraftLog("stopped repeating " .. tostring(recipeID) .. " (" .. (reason or "stop rule") .. ")")
    Print("Stopped crafting " .. (label or "it") .. ": " .. (reason or "its stop rule was reached") .. ".")
end

-- Recently removed bars ------------------------------------------------------------
-- Bars that leave the list (a stop rule or goal reached, Untrack, a bar
-- replaced by another) are remembered so they can be brought back:
-- /bartab undo, or "Recently removed..." on the profession window's BarTab
-- button. They're found by comparing the list before and after each
-- refresh, so every way a bar can go is covered. Fill-up item bars (crates)
-- aren't kept: they come and go with the item. Per character, newest first,
-- in settings.removedBars; each entry is the bars that went together.
REMOVED_KEEP = 10
removedShadow = { items = {} }

-- Seconds since 1970 (the game's time()); 0 if there's no clock.
function Now()
    return (time and time()) or 0
end

function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do copy[DeepCopy(k, seen)] = DeepCopy(v, seen) end
    return copy
end

function RemovedBars()
    settings.removedBars = settings.removedBars or {}
    local key = CharacterKey()
    settings.removedBars[key] = settings.removedBars[key] or {}
    return settings.removedBars[key]
end

-- "Thick Leather", "Fine Thread for Hillman's Cloak", "Hillman's Cloak (3
-- bars)", "Thick Leather and 2 more".
function RemovedLabel(entry)
    local first = entry.bars[1].item
    local label = DisplayName(first)
    local same = true
    for _, bar in ipairs(entry.bars) do
        if DisplayName(bar.item) ~= label then same = false end
    end
    if #entry.bars == 1 then
        -- One material bar of a recipe: "Fine Thread for Hillman's Cloak".
        if first.label and first.name and first.label ~= first.name then
            return first.name .. " for " .. first.label
        end
        return label
    end
    if same then return ("%s (%d bars)"):format(label, #entry.bars) end
    return ("%s and %d more"):format(label, #entry.bars - 1)
end

function AgoText(when)
    local minutes = math.floor((Now() - (when or Now())) / 60)
    if minutes < 1 then return "just now" end
    if minutes < 60 then return minutes .. " min ago" end
    local hours = math.floor(minutes / 60)
    if hours < 24 then return hours .. (hours == 1 and " hour ago" or " hours ago") end
    local days = math.floor(hours / 24)
    return days .. (days == 1 and " day ago" or " days ago")
end

-- Runs after every refresh: anything in the last snapshot that's gone now
-- (and wasn't just renamed to another key) was removed.
function NoteRemovedBars()
    local shadow = removedShadow
    if shadow.list == trackedItems then
        local still = {}
        for _, item in pairs(trackedItems) do still[item] = true end
        local gone = {}
        for key, saved in pairs(shadow.items) do
            if not trackedItems[key] and not still[saved.ref] then
                gone[#gone + 1] = { key = key, item = saved.copy }
            end
        end
        local added = false
        for key, item in pairs(trackedItems) do
            if not item.container and not item.altNeed and not shadow.items[key] then added = true end
        end
        if #gone > 0 then
            table.sort(gone, function(a, b) return (a.item.order or 0) < (b.item.order or 0) end)
            local entry = { bars = gone, time = Now() }
            local list = RemovedBars()
            table.insert(list, 1, entry)
            while #list > REMOVED_KEEP do table.remove(list) end
            -- A bar replaced by another (a goal bar for ingredient bars)
            -- isn't news; otherwise say how to get it back, after whatever
            -- message the removal printed.
            if not added then
                local label = RemovedLabel(entry)
                C_Timer.After(0, function()
                    Print("Type /bartab undo to bring back " .. label .. ".")
                end)
            end
        end
    end
    -- Snapshot for next time. A different list (logging in) starts fresh.
    local items = {}
    for key, item in pairs(trackedItems) do
        if not item.container and not item.altNeed then items[key] = { ref = item, copy = DeepCopy(item) } end
    end
    shadow.list, shadow.items = trackedItems, items
end

-- Brings back a group of removed bars (index into the list; 1 = newest).
-- A stop rule that's already been met is cleared, or it would take the bar
-- away again straight away.
function RestoreRemoved(index)
    index = index or 1
    local list = RemovedBars()
    local entry = list[index]
    if not entry then
        Print("Nothing to bring back: no bars have been removed lately.")
        return
    end
    table.remove(list, index)
    local back, already, cleared = 0, 0, {}
    for _, bar in ipairs(entry.bars) do
        if trackedItems[bar.key] then
            already = already + 1
        else
            local item = DeepCopy(bar.item)
            if item.untilSkill then
                local rank = GetProfessionSkill(item)
                if rank and rank >= item.untilSkill then
                    cleared[#cleared + 1] = "stop at skill " .. item.untilSkill
                    item.untilSkill = nil
                end
            end
            if item.untilColor and item.recipeID then
                local color = GetRecipeColor(item.recipeID)
                if color and COLOR_RANK[color] >= (COLOR_RANK[item.untilColor] or 9) then
                    cleared[#cleared + 1] = "stop when " .. item.untilColor
                    item.untilColor = nil
                end
            end
            trackedItems[bar.key] = item
            goalReached[bar.key] = nil
            back = back + 1
        end
    end
    UpdateBars()
    local label = RemovedLabel(entry)
    if back == 0 then
        Print(label .. " is already back.")
        return
    end
    local text = "Brought back " .. label
    if already > 0 then text = text .. (" (%d already tracked)"):format(already) end
    if #cleared > 0 then
        text = text .. "; cleared its " .. cleared[1] .. ", since that's already been reached"
    end
    Print(text .. ".")
end

-- The profession window's "Recently removed..." list.
function ShowRemovedMenu(owner)
    local list = RemovedBars()
    if #list == 0 then
        Print("No bars have been removed lately.")
        return
    end
    local entries = {}
    for index, entry in ipairs(list) do
        entries[#entries + 1] = { RemovedLabel(entry) .. "  |cff999999" .. AgoText(entry.time) .. "|r",
            function() RestoreRemoved(index) end }
    end
    entries[#entries + 1] = { divider = true }
    entries[#entries + 1] = { "Clear the list", function()
        for i = #list, 1, -1 do list[i] = nil end
        Print("Cleared the list of removed bars.")
    end }
    ShowMenu(owner, "Bring back a removed bar", entries)
end

-- Bars from "Make until I reach...": one craft's worth per skill point still
-- needed, so a craft that gives a point shrinks them and one that doesn't
-- leaves them as they are.
function ResizeSkillGoalBars()
    local changed = false
    for key, item in pairs(trackedItems) do
        if item.skillGoal and item.recipeID and not item.container then
            local skill = GetProfessionSkill(item)
            local need = skill and GetReagentQuantity(item.recipeID, item.name)
            if need and need > 0 then
                local crafts = math.max(1, item.skillGoal - skill)
                local goal = (item.start or 0) + need * crafts
                if goal ~= item.goal then
                    item.goal = goal
                    goalReached[key] = nil -- resized, not reached: no alert
                    changed = true
                end
            end
        end
    end
    if changed then UpdateBars() end
end

function IsRepeatingCraft()
    if not (C_TradeSkillUI and C_TradeSkillUI.IsRecipeRepeating) then return false end
    local ok, repeating = pcall(C_TradeSkillUI.IsRecipeRepeating)
    return ok and repeating and true or false
end

function CheckSkillLimits()
    Safe("skill", ResizeSkillGoalBars)()
    local messages, colorCache, asks, stopped = {}, {}, {}, {}
    for key, item in pairs(trackedItems) do
        if item.recipeID and not item.container
            and (item.untilSkill or item.untilColor) then
            local label = DisplayName(item)
            if item.untilSkill then
                local rank, profession = GetProfessionSkill(item)
                if rank and rank >= item.untilSkill then
                    local done = ("%s reached %d; stopped tracking %s."):format(
                        profession, item.untilSkill, label)
                    if item.stopAsk then
                        stopped[item.recipeID] = label
                        asks[item.recipeID] = asks[item.recipeID] or { recipeID = item.recipeID,
                            label = label, done = done,
                            reason = ("%s reached %s %d."):format(label, profession, item.untilSkill) }
                    else
                        trackedItems[key] = nil
                        stopped[item.recipeID] = label
                        messages[label] = done
                    end
                end
            else
                local color = colorCache[item.recipeID]
                if color == nil then
                    color = GetRecipeColor(item.recipeID) or false
                    colorCache[item.recipeID] = color
                end
                if color and COLOR_RANK[color] >= (COLOR_RANK[item.untilColor] or 9) then
                    local done = ("%s turned %s; stopped tracking it."):format(
                        label, ColorText(color))
                    if item.stopAsk then
                        stopped[item.recipeID] = label
                        asks[item.recipeID] = asks[item.recipeID] or { recipeID = item.recipeID,
                            label = label, done = done,
                            reason = ("%s is now %s."):format(label, ColorText(color)) }
                    else
                        trackedItems[key] = nil
                        stopped[item.recipeID] = label
                        messages[label] = done
                    end
                end
            end
        end
    end
    -- A batch of a recipe whose stop rule was just reached stops too.
    for recipeID, label in pairs(stopped) do StopCraftingRecipe(recipeID, label) end
    local any = false
    for _, message in pairs(messages) do
        any = true
        Print(message)
    end
    if any then UpdateBars() end
    for recipeID, ask in pairs(asks) do
        if not stopPrompts.waiting[recipeID] then
            stopPrompts.waiting[recipeID] = true
            stopPrompts.queue[#stopPrompts.queue + 1] = ask
        end
    end
    ShowNextStopPrompt()
end

-- Sets the stop rule on all of a recipe's bars: a level, a color, or neither.
function SetStopRule(recipeID, level, color, quiet)
    local item
    for _, other in pairs(trackedItems) do
        if other.recipeID == recipeID and not other.container then
            other.untilSkill, other.untilColor = level, color
            item = item or other
        end
    end
    if not item or quiet then return end
    if level then
        Print(("%s: stops tracking at %s %d."):format(DisplayName(item),
            item.profession or "skill", level))
    elseif color then
        Print(("%s: stops tracking when it turns %s."):format(DisplayName(item), ColorText(color)))
    else
        Print(DisplayName(item) .. ": no stop rule.")
    end
    CheckSkillLimits()
end

function AskSkillLimit(item)
    local recipeID = item.recipeID
    local profession = item.profession or "your profession"
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    StaticPopupDialogs.BARTAB_SKILL_LIMIT = StaticPopupDialogs.BARTAB_SKILL_LIMIT or {
        text = "Stop tracking %s when %s reaches skill level:",
        button1 = OKAY or "OK",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 4,
        OnShow = function(self, data)
            local box = self.editBox or self.EditBox
            if box then
                box:SetText(data.current and tostring(data.current) or "")
                box:HighlightText()
                box:SetFocus()
            end
        end,
        OnAccept = function(self, data)
            local box = self.editBox or self.EditBox
            SetStopRule(data.recipeID, tonumber(box and box:GetText() or ""), nil)
        end,
        EditBoxOnEnterPressed = function(box, data)
            local parent = box:GetParent()
            data = data or parent.data
            SetStopRule(data.recipeID, tonumber(box:GetText()), nil)
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(box)
            box:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("BARTAB_SKILL_LIMIT", DisplayName(item), profession,
        { recipeID = recipeID, current = item.untilSkill })
end

-- Right-click submenu: Never / At a skill level... / When yellow, green, gray.
function StopMenuEntry(item)
    local recipeID = item.recipeID
    local choices = {
        { "Never", function() SetStopRule(recipeID, nil, nil) end,
          selected = not item.untilSkill and not item.untilColor },
        { item.untilSkill and ("At skill level " .. item.untilSkill .. "...") or "At a skill level...",
          function() AskSkillLimit(item) end,
          selected = item.untilSkill ~= nil },
    }
    for _, color in ipairs({ "yellow", "green", "gray" }) do
        choices[#choices + 1] = {
            "When it turns " .. color,
            function() SetStopRule(recipeID, nil, color) end,
            selected = item.untilColor == color,
        }
    end
    choices[#choices + 1] = {
        "Ask before removing",
        function()
            local ask = not item.stopAsk or nil
            for _, other in pairs(trackedItems) do
                if other.recipeID == recipeID and not other.container then
                    other.stopAsk = ask
                end
            end
            Print(DisplayName(item) .. (ask and ": will ask before a stop rule removes it."
                or ": stop rules remove it without asking."))
        end,
        selected = item.stopAsk == true,
        isSelected = function() return item.stopAsk == true end,
        check = true,
    }
    return { "Stop tracking", choices = choices }
end

-- Tooltip line: "Stops at Leatherworking 125 (now 118)" or
-- "Stops when it turns gray (now green)".
-- Tooltip line for "Make until I reach..." bars: "At least 14 crafts to
-- Leatherworking 75" (at least: not every craft gives a point).
function SkillGoalLine(item)
    if not item.skillGoal then return nil end
    local rank, profession = GetProfessionSkill(item)
    if not rank or rank >= item.skillGoal then return nil end
    local crafts = item.skillGoal - rank
    local time = BatchTimeText(item.recipeID, crafts)
    return ("At least %d %s to %s %d%s"):format(crafts, crafts == 1 and "craft" or "crafts",
        profession or item.profession or "skill", item.skillGoal, time and (", " .. time) or "")
end

function SkillLimitLine(item)
    if item.untilSkill then
        local rank, profession = GetProfessionSkill(item)
        return ("Stops at %s %d%s%s"):format(profession or item.profession or "skill",
            item.untilSkill, rank and (" (now " .. rank .. ")") or "",
            item.stopAsk and ", asks first" or "")
    elseif item.untilColor then
        local color = GetRecipeColor(item.recipeID)
        return "Stops when it turns " .. ColorText(item.untilColor)
            .. (color and (" (now " .. ColorText(color) .. ")") or "")
            .. (item.stopAsk and ", asks first" or "")
    end
end

-- Skill-ups, logins and the profession loading (when colors can be read).
skillWatcher = CreateFrame("Frame")
skillWatcher.barTabOwn = true -- never muted by BarTab's silent profession loads
for _, skillEvent in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "PLAYER_ENTERING_WORLD",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
    pcall(skillWatcher.RegisterEvent, skillWatcher, skillEvent)
end
skillCheckPending = false
skillWatcher:SetScript("OnEvent", function(_, event)
    if event == "CHAT_MSG_SKILL" or event == "SKILL_LINES_CHANGED" then
        CraftLog("skill event " .. event)
        -- Right away too while a batch is running, so a stop rule halts it
        -- before its next craft. (Not otherwise: a level-up sends a burst
        -- of these, one per weapon and defense skill.)
        if crafting or IsRepeatingCraft() then
            Safe("skill", CheckSkillLimits)()
        end
    end
    -- Skill info can lag the event a moment; many events come in a burst.
    if skillCheckPending then return end
    skillCheckPending = true
    C_Timer.After(1, function()
        skillCheckPending = false
        CheckSkillLimits()
        Safe("training", CheckTraining)()
        RequestUpdate(0) -- skill levels on the profession headings
    end)
end)

-- Chain crafting ---------------------------------------------------------------
-- A click on a recipe bar that's short of a material you can make (Thick
-- Leather for an Ammo Pouch, from Heavy Leather) makes that first, then the
-- recipe; several steps deep (Medium -> Heavy -> Thick Leather). Only your
-- own recipes, from the same profession unless settings.chainOtherProfessions
-- (smelting bars for Blacksmithing). settings.chainCraft: "auto" (default),
-- "ask" (a prompt lists the steps) or "menu" (only "Craft, making materials
-- first" on a bar's right-click menu).
CHAIN_MODES = {
    { key = "auto", name = "Make missing materials first" },
    { key = "ask", name = "Ask before making materials first" },
    { key = "menu", name = "Only from a bar's right-click menu" },
}
CHAIN_DEPTH = 5
CHAIN_MOST = 100 -- the most crafts one click plans for
chainJob = nil

-- Your recipe that makes this item, by ID or name.
function ProducerFor(itemID, itemName)
    local mine = settings.producers and settings.producers[CharacterKey()]
    if mine and itemID and mine[itemID] then return mine[itemID] end
    return FindProducer(itemName)
end

-- Whether crafts of recipeID can be made from inv (item ID -> count, filled
-- from your bags as needed, and changed as the plan uses and makes things),
-- making materials as needed. Appends the steps (deepest first) to steps.
-- why (optional): collects what stops it, for the "Can't craft" message:
-- { name=, have=, need=, itemID= } for something you'd have to get, or
-- { name=, profession= } for something another profession makes.
-- vendor (optional): vendor items you're short of (thread, dye) don't stop
-- it; they're collected here instead (itemID -> { name=, count= }).
function ChainFeasible(recipeID, crafts, inv, depth, visiting, steps, profession, why, vendor)
    local reagents = GetRecipeReagents(recipeID)
    if not reagents or #reagents == 0 then return false end
    local feasible = true
    for _, reagent in ipairs(reagents) do
        local id = reagent.itemID
        if inv[id] == nil then inv[id] = CountOwned(id) end
        local need = reagent.need * crafts
        local blocked = false
        local producer = inv[id] < need and ProducerFor(id, reagent.name)
        if inv[id] < need and vendor and not producer and VendorBuyPrice(id) then
            -- Bought later, at a vendor: plan as if you had it.
            local entry = vendor[id] or { name = reagent.name, count = 0 }
            entry.count = entry.count + (need - inv[id])
            vendor[id] = entry
            inv[id] = need
        end
        if inv[id] < need then
            if not producer or depth >= CHAIN_DEPTH or visiting[producer.recipeID] then
                blocked = true
                if why then why[#why + 1] = { name = reagent.name, have = inv[id], need = need, itemID = id } end
            elseif not settings.chainOtherProfessions and profession and producer.profession
                and string.lower(producer.profession) ~= string.lower(profession) then
                blocked = true
                if why then why[#why + 1] = { name = reagent.name, profession = producer.profession } end
            else
                local qty = math.max(1, producer.qty or 1)
                local sub = math.ceil((need - inv[id]) / qty)
                visiting[producer.recipeID] = true
                -- Reasons go one step down only: "missing Heavy Leather" for a
                -- Thick Armor Kit, not the scraps at the bottom of the chain.
                local ok = ChainFeasible(producer.recipeID, sub, inv, depth + 1, visiting, steps, profession,
                    depth == 0 and why or nil, vendor)
                visiting[producer.recipeID] = nil
                if not ok then
                    blocked = true
                    if why and depth >= 1 then
                        why[#why + 1] = { name = reagent.name, have = inv[id], need = need, itemID = id }
                    end
                else
                    inv[id] = inv[id] + sub * qty
                    local last = steps[#steps]
                    if last and last.recipeID == producer.recipeID then
                        last.crafts = last.crafts + sub
                    else
                        steps[#steps + 1] = { recipeID = producer.recipeID, crafts = sub, qty = qty,
                            name = producer.name or reagent.name, profession = producer.profession,
                            skillLineID = producer.skillLineID }
                    end
                end
            end
        end
        if blocked then
            feasible = false
            if not why then return false end -- no need to look further
        else
            inv[id] = inv[id] - need
        end
    end
    return feasible
end

-- Your other characters, for messages: who can make an item (from the
-- recipes saved when you opened their professions), and who has some (their
-- last saved bags and bank).
function AltMakers(itemID, itemName)
    local me, names = CharacterKey(), {}
    local wanted = itemName and string.lower(itemName)
    for character, recipes in pairs(settings.producers or {}) do
        if character ~= me then
            local found = itemID and recipes[itemID]
            if not found and wanted then
                for _, entry in pairs(recipes) do
                    if entry.name and string.lower(entry.name) == wanted then found = entry break end
                end
            end
            if found then names[#names + 1] = CharacterName(character) end
        end
    end
    table.sort(names)
    return names
end

function AltStock(itemID)
    local me, list = CharacterKey(), {}
    if not itemID then return list end
    for character, snapshot in pairs(settings.inventory or {}) do
        if character ~= me then
            local count = ((snapshot.bags or {})[itemID] or 0) + ((snapshot.bank or {})[itemID] or 0)
            if count > 0 then list[#list + 1] = { name = CharacterName(character), count = count } end
        end
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
end

-- "[Alt] can make it; [Alt] has 30", or nil.
function AltNote(itemID, itemName)
    local parts = {}
    local makers = AltMakers(itemID, itemName)
    if #makers > 0 then parts[#parts + 1] = JoinNames(makers, 3) .. " can make it" end
    local stock = AltStock(itemID or ResolveItemID(itemName))
    if #stock > 0 then
        local holders = {}
        for index = 1, math.min(2, #stock) do
            holders[#holders + 1] = stock[index].name .. " has " .. stock[index].count
        end
        parts[#parts + 1] = table.concat(holders, ", ")
    end
    return #parts > 0 and table.concat(parts, "; ") or nil
end

-- Why one craft can't be made even making materials first: a sentence, or
-- nil when making materials doesn't come into it (nothing makeable).
function ChainBlockedText(item)
    local reagents = GetRecipeReagents(item.recipeID)
    if not reagents then return nil end
    local makeable = {}
    for _, reagent in ipairs(reagents) do
        if reagent.have < reagent.need and ProducerFor(reagent.itemID, reagent.name) then
            makeable[#makeable + 1] = reagent.name
        end
    end
    if #makeable == 0 then return nil end
    local why = {}
    ChainFeasible(item.recipeID, 1, {}, 0, { [item.recipeID] = true }, {}, item.profession, why)
    if #why == 0 then return nil end
    local parts, seen = {}, {}
    for _, reason in ipairs(why) do
        if not seen[reason.name] then
            seen[reason.name] = true
            if reason.profession then
                parts[#parts + 1] = reason.name .. " (made with " .. reason.profession
                    .. "; turn on \"Use my other professions too\" in settings)"
            else
                local where = VendorBuyPrice(reason.itemID) and "from a vendor" or "to get"
                local okNote, note = pcall(AltNote, reason.itemID, reason.name)
                if okNote and note then where = where .. "; " .. note end
                parts[#parts + 1] = ("%s (%d/%d, %s)"):format(reason.name, reason.have, reason.need, where)
            end
        end
    end
    return ("Can't craft %s yet, even making the %s first: missing %s."):format(
        GetRecipeName(item.recipeID) or DisplayName(item), JoinNames(makeable), table.concat(parts, ", "))
end

-- The most crafts (up to wanted) of the bar's recipe that making materials
-- allows, and the steps: { crafts=, steps={...} }, or nil.
-- vendorLater: plan as if vendor items you're short of were there (they're
-- listed in plan.vendor), to make the rest now.
function PlanChain(item, wanted, vendorLater)
    local bestVendor
    local function Try(n)
        local steps, vendor = {}, vendorLater and {} or nil
        if ChainFeasible(item.recipeID, n, {}, 0, { [item.recipeID] = true }, steps, item.profession, nil, vendor) then
            bestVendor = vendor
            return steps
        end
    end
    local low, best = 0, nil
    local high = math.min(wanted, CHAIN_MOST)
    -- Feasible counts run 1..k: find k.
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        local steps = Try(mid)
        if steps then low, best = mid, steps else high = mid - 1 end
    end
    if low < 1 or not best or #best == 0 then return nil end
    -- The vendor list that goes with the count found (Try ran last on it
    -- only if it succeeded last; run it again to be sure).
    if vendorLater then best = Try(low) end
    local plan = { crafts = low, steps = best, item = item }
    if vendorLater then
        plan.vendor = {}
        for _, entry in pairs(bestVendor or {}) do plan.vendor[#plan.vendor + 1] = entry end
        table.sort(plan.vendor, function(a, b) return a.name < b.name end)
        if #plan.vendor > 0 then plan.prepOnly = true end
    end
    return plan
end

-- How many crafts this click wants, before materials limit it.
function ChainWanted(item, chosen)
    local wanted
    if chosen == "one" then
        wanted = 1
    elseif chosen == "max" then
        wanted = CHAIN_MOST
    elseif chosen == "fit" then
        local perCraft = GetReagentQuantity(item.recipeID, item.name)
        if perCraft and perCraft > 0 then
            wanted = math.floor((item.goal or 0) / perCraft)
        else
            local _, perOutput = GetRecipeOutput(item.recipeID)
            wanted = math.floor(math.max(0, (item.goal or 0) - GetBarCount(item)) / math.max(1, perOutput or 1))
        end
    end
    if wanted and IsOutputBar(item) then wanted = math.min(wanted, CraftsToTarget(item)) end
    return wanted
end

-- Some progress when the whole recipe is out of reach: as much of each
-- makeable material as your bags allow (1 Thick Leather toward a Thick
-- Armor Kit that needs 4 more), up to what the click aims for (one craft,
-- or the bar's crafts for Shift- and Alt-click). Vendor items don't count
-- against it. nil if nothing can be made.
function PartialChainPlan(item, chosen)
    local target = 1
    if chosen ~= "one" then
        local perCraft = GetReagentQuantity(item.recipeID, item.name)
        if IsOutputBar(item) then
            target = math.max(1, CraftsToTarget(item))
        elseif perCraft and perCraft > 0 then
            target = math.max(1, math.ceil(((item.goal or 0) - (item.start or 0)) / perCraft))
        end
    end
    target = math.min(target, CHAIN_MOST)
    local reagents = GetRecipeReagents(item.recipeID)
    if not reagents then return nil end
    local steps = {}
    for _, reagent in ipairs(reagents) do
        local short = reagent.need * target - reagent.have
        local producer = short > 0 and ProducerFor(reagent.itemID, reagent.name)
        local allowed = producer and (settings.chainOtherProfessions or not (item.profession and producer.profession)
            or string.lower(item.profession) == string.lower(producer.profession))
        if allowed then
            local qty = math.max(1, producer.qty or 1)
            local function Try(n)
                local sub = {}
                if ChainFeasible(producer.recipeID, n, {}, 1, { [producer.recipeID] = true, [item.recipeID] = true },
                    sub, item.profession, nil, {}) then
                    return sub
                end
            end
            local low, best, high = 0, nil, math.min(math.ceil(short / qty), CHAIN_MOST)
            while low < high do
                local mid = math.floor((low + high + 1) / 2)
                local sub = Try(mid)
                if sub then low, best = mid, sub else high = mid - 1 end
            end
            if low > 0 then
                for _, step in ipairs(best) do steps[#steps + 1] = step end
                steps[#steps + 1] = { recipeID = producer.recipeID, crafts = low, qty = qty,
                    name = producer.name or reagent.name, profession = producer.profession,
                    skillLineID = producer.skillLineID }
            end
        end
    end
    if #steps == 0 then return nil end
    return { crafts = target, steps = steps, item = item, prepOnly = true, partial = true }
end

function ChainText(plan)
    local parts = {}
    for _, step in ipairs(plan.steps) do
        parts[#parts + 1] = (step.crafts * step.qty) .. " " .. step.name
    end
    local recipeName = GetRecipeName(plan.item.recipeID) or DisplayName(plan.item)
    if plan.partial then
        return ("%s now, toward %d %s (not enough for all of it yet)"):format(JoinNames(parts, 6),
            plan.crafts, recipeName)
    end
    if plan.prepOnly then
        local buy = {}
        for _, entry in ipairs(plan.vendor) do buy[#buy + 1] = entry.count .. " " .. entry.name end
        return ("%s now; buy %s at a vendor to finish %d %s"):format(JoinNames(parts, 6),
            JoinNames(buy), plan.crafts, recipeName)
    end
    return ("%s first, then %d %s"):format(JoinNames(parts, 6), plan.crafts, recipeName)
end

-- From a click: true if it started (or asked about) a chain.
function TryChainCraft(item, chosen, forced)
    if not (item and item.recipeID) or item.container or item.notLearned then return false end
    if chainJob then
        chainJob = nil
        Print("Stopped making materials first; a craft in progress still finishes.")
        return true
    end
    local mode = settings.chainCraft or "auto"
    if mode == "menu" and not forced then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local wanted = ChainWanted(item, chosen)
    if not wanted or wanted < 1 then return false end
    local craftable = GetCraftableCount(item.recipeID) or 0
    if craftable >= wanted then return false end
    local plan = PlanChain(item, wanted)
    if not plan or plan.crafts <= craftable then
        -- Held up only by vendor items (thread)? Make the rest now; the
        -- vendor prompt offers the thread once the other materials are in.
        if craftable >= 1 then return false end
        plan = PlanChain(item, wanted, true)
        if not (plan and plan.prepOnly) then
            -- Not enough for even one: make what you can of its materials,
            -- toward the bar.
            plan = PartialChainPlan(item, chosen)
            if not plan then return false end
        end
    end
    if mode == "ask" and not forced and StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs.BARTAB_CHAIN = StaticPopupDialogs.BARTAB_CHAIN or {
            text = "BarTab: make %s?",
            button1 = "Make",
            button2 = CANCEL or "Cancel",
            OnAccept = function(_, data) StartChain(data) end,
            timeout = 0,
            whileDead = false,
            hideOnEscape = true,
        }
        StaticPopup_Show("BARTAB_CHAIN", ChainText(plan), nil, plan)
        return true
    end
    StartChain(plan)
    return true
end

function StartChain(plan)
    local steps = {}
    for _, step in ipairs(plan.steps) do steps[#steps + 1] = step end
    if not plan.prepOnly then
        steps[#steps + 1] = { recipeID = plan.item.recipeID, crafts = plan.crafts, final = true, item = plan.item }
    end
    chainJob = { steps = steps, index = 0 }
    Print("Making " .. ChainText(plan)
        .. ((plan.prepOnly and not plan.partial) and " (BarTab offers it when you visit one)." or "."))
    RunChainStep()
end

-- One step at a time: craft it, wait until the batch is over, then the next.
function RunChainStep()
    local job = chainJob
    if not job then return end
    job.index = job.index + 1
    local step = job.steps[job.index]
    if not step then
        chainJob = nil
        return
    end
    local stepItem = step.item or { recipeID = step.recipeID, profession = step.profession,
        skillLineID = step.skillLineID, name = step.name, label = GetRecipeName(step.recipeID) }
    local craftable = GetCraftableCount(step.recipeID) or 0
    local amount = math.min(step.crafts, craftable)
    if amount < 1 then
        chainJob = nil
        Print("Couldn't make " .. (GetRecipeName(step.recipeID) or step.name or "the next step")
            .. ": the materials aren't there. Stopped.")
        return
    end
    TryCraft(stepItem, amount)
    job.started = GetTime()
    C_Timer.After(0.5, WaitChainStep)
end

function WaitChainStep()
    local job = chainJob
    if not job then return end
    -- Still loading the profession, crafting, or casting.
    if craftJob or crafting or CastingNow() or IsRepeatingCraft() then
        C_Timer.After(0.5, WaitChainStep)
        return
    end
    -- A moment for the bags to catch up, then the next step.
    C_Timer.After(0.6, function() Safe("chain", RunChainStep)() end)
end

-- Recipe chains ----------------------------------------------------------------
-- When a bar's material is something you can craft (Heavy Leather, from
-- Medium Leather), BarTab can track that recipe too, sized to what the bar
-- is still short. Which of your recipes make what is noted whenever a
-- profession loads, per character, so it works with the window closed:
-- settings.producers["Name-Realm"][outputItemID] =
--   { recipeID, recipeName, profession, skillLineID, qty, name }

function ScanProducers()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs
        and C_TradeSkillUI.GetRecipeSchematic) then return end
    local okInfo, base = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    local profession = okInfo and type(base) == "table" and base.professionName
    if not profession or profession == "" then return end
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" or #ids == 0 then return end

    settings.producers = settings.producers or {}
    local mine = settings.producers[CharacterKey()] or {}
    settings.producers[CharacterKey()] = mine
    -- Start this profession over, so forgotten recipes drop out.
    for itemID, entry in pairs(mine) do
        if entry.profession == profession then mine[itemID] = nil end
    end
    -- Every recipe of the profession by name, learned or not, so a recipe
    -- item ("Pattern: Red Woolen Bag") can be matched to its recipe.
    settings.recipeIndex = settings.recipeIndex or {}
    local index = settings.recipeIndex[CharacterKey()] or {}
    settings.recipeIndex[CharacterKey()] = index
    for name, entry in pairs(index) do
        if entry.profession == profession then index[name] = nil end
    end
    for _, recipeID in ipairs(ids) do
        local okRecipe, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if okRecipe and type(info) == "table" and info.name then
            index[string.lower(info.name)] = { recipeID = recipeID, profession = profession,
                skillLineID = (tonumber(base.professionID) or 0) > 0 and base.professionID or nil }
        end
        if okRecipe and type(info) == "table" and info.learned then
            local okSchematic, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
            local output = okSchematic and type(schematic) == "table" and schematic.outputItemID
            if output and not mine[output] then
                mine[output] = {
                    recipeID = recipeID,
                    recipeName = info.name,
                    profession = profession,
                    skillLineID = (tonumber(base.professionID) or 0) > 0 and base.professionID or nil,
                    qty = math.max(1, tonumber(schematic.quantityMin) or 1),
                    name = GetItemNameByID(output),
                }
            end
        end
    end
end

-- Your recipe that makes the named item, if BarTab has seen one.
function FindProducer(itemName)
    local mine = settings.producers and settings.producers[CharacterKey()]
    if not (mine and itemName) then return nil end
    local wanted = string.lower(itemName)
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, itemID = pcall(C_Item.GetItemInfoInstant, itemName)
        if ok and itemID and mine[itemID] then return mine[itemID] end
    end
    for itemID, entry in pairs(mine) do
        entry.name = entry.name or GetItemNameByID(itemID)
        if entry.name and string.lower(entry.name) == wanted then return entry end
    end
end

-- Bars for the recipe that makes this bar's material, sized to the shortfall.
-- How many crafts of the producing recipe cover what the bar is short of.
function ChainShortfallCrafts(item, producer)
    local short = item.goal - GetBarCount(item)
    if short <= 0 then return 0 end
    return math.ceil(short / producer.qty)
end

-- whole: size the new bars to the bar's whole shortfall (Alt-click);
-- otherwise one craft.
function TrackChain(parentKey, whole)
    local parent = trackedItems[parentKey]
    if not parent then return end
    local producer = FindProducer(parent.name)
    if not producer then
        Print("BarTab doesn't know a recipe of yours that makes " .. parent.name
            .. ". Open that profession once so BarTab can see your recipes.")
        return
    end
    -- Not short: you asked for it anyway, so one craft (to stock up).
    local short = parent.goal - GetBarCount(parent)
    local enough = short <= 0
    local reagents = GetRecipeReagents(producer.recipeID)
    if not reagents or #reagents == 0 then
        Print("Couldn't read the " .. (producer.recipeName or parent.name) .. " recipe right now; try again with the profession open.")
        return
    end

    local crafts = (whole and not enough) and math.ceil(short / producer.qty) or 1
    local recipeName = producer.recipeName or GetRecipeName(producer.recipeID) or parent.name
    local parts = {}
    for index, reagent in ipairs(reagents) do
        local goal = crafts * reagent.need
        local key = RecipeKey(reagent.name, producer.recipeID)
        local item = trackedItems[key]
        if item then
            if item.goal < goal then item.goal, item.countFrom, item.countDone = goal, nil, nil end
        else
            trackedItems[key] = {
                name = reagent.name,
                itemID = reagent.itemID,
                start = 0,
                goal = goal,
                recipeID = producer.recipeID,
                profession = producer.profession,
                skillLineID = producer.skillLineID,
                label = recipeName,
                chainFor = parentKey,
                -- Just above the bar it feeds: crafted first.
                order = (parent.order or NextOrder()) - 0.5 + index * 0.01,
            }
        end
        parts[#parts + 1] = goal .. " " .. reagent.name
    end
    NormalizeOrder()
    UpdateBars()
    if enough then
        Print(("You already have enough %s for %s; tracking one craft of %s anyway, needing %s. Use Crafts on its bar for more."):format(
            parent.name, DisplayName(parent), recipeName, table.concat(parts, ", ")))
        return
    end
    Print(("Tracking how to make %d %s for %s: %d craft(s) of %s, needing %s."):format(
        crafts * producer.qty, parent.name, DisplayName(parent), crafts, recipeName,
        table.concat(parts, ", ")))
end

-- The recipe that makes this bar's material, unless you already track it.
function CanTrackChain(item)
    if item.container then return nil end
    local producer = FindProducer(item.name)
    if producer and not IsTrackedRecipe(producer.recipeID) then return producer end
end

-- Tooltip lines: what this bar feeds, and whether you can make its material.
function AddChainLines(item)
    if item.container then return end
    local fed = item.chainFor and trackedItems[item.chainFor]
    if fed then
        GameTooltip:AddLine("Makes " .. fed.name .. " for " .. DisplayName(fed), 0.8, 0.8, 0.8)
    end
    -- What the lighter stretch on the bar means.
    local count = GetBarCount(item)
    local okMake, makeable = pcall(MakeableCount, item, count)
    if okMake and makeable and makeable > 0 then
        GameTooltip:AddLine(("You could make %d more %s from what's in your bags%s"):format(makeable, item.name,
            (count + makeable >= item.goal) and ", enough for the rest of the bar" or ""), 0.5, 1, 0.5, true)
    end
    -- Only one of your other characters can make it.
    if not ProducerFor(ItemIDFor(item), item.name) and count < item.goal then
        local okMakers, makers = pcall(AltMakers, ItemIDFor(item), item.name)
        if okMakers and #makers > 0 then
            GameTooltip:AddLine(JoinNames(makers, 3) .. " can make " .. item.name .. ".", 0.5, 0.8, 1, true)
        end
    end
    local producer = CanTrackChain(item)
    if producer and GetBarCount(item) < item.goal then
        local how = producer.profession or producer.recipeName or "a recipe"
        if producer.recipeName and producer.profession
            and string.lower(producer.recipeName) ~= string.lower(item.name) then
            how = producer.profession .. " (" .. producer.recipeName .. ")"
        end
        GameTooltip:AddLine("You can make " .. item.name .. " with " .. how
            .. "; right-click to track that too (one craft, or Alt-click the menu for all you're short).",
            0.5, 1, 0.5, true)
    end
end

producerWatcher = CreateFrame("Frame")
producerWatcher.barTabOwn = true -- never muted by BarTab's silent profession loads
for _, tradeEvent in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED" }) do
    pcall(producerWatcher.RegisterEvent, producerWatcher, tradeEvent)
end
producerScanPending = false
producerWatcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "NEW_RECIPE_LEARNED" and arg1 then
        -- Appearance offers are only made for recipes you know, so a mark on
        -- one you're only now learning is stray (an older trainer window).
        if settings.appearanceOffered and settings.appearanceOffered[CharacterKey()] then
            settings.appearanceOffered[CharacterKey()][arg1] = nil
        end
        Safe("trainer", ActivateLearnedRecipe)(arg1)
        C_Timer.After(1, function() Safe("appearances", CheckNewRecipe)(arg1, 1) end)
    end
    if producerScanPending then return end
    producerScanPending = true
    C_Timer.After(0.5, function()
        producerScanPending = false
        pcall(ScanProducers)
        Safe("trainer", CheckLearnedRecipes)()
        Safe("appearances", ScanAppearanceRecipes)()
    end)
end)

-- Appearances ------------------------------------------------------------------
-- Optionally (settings.appearanceRecipes), recipes that make gear whose
-- appearance you haven't collected get bars: one craft's worth of each
-- ingredient, untracked after crafting. Checked when you learn a recipe and
-- whenever a profession loads. Each recipe is offered once per character
-- (settings.appearanceOffered), so untracking one keeps it gone.
-- Recipes that no longer give skill (green, gray) are left out unless
-- settings.appearanceAllColors is on.

-- Which ingredients get bars (settings.appearanceBars).
APPEARANCE_MODES = {
    { key = "ask", name = "Ask which ingredients to track" },
    { key = "main", name = "Track the main ingredient only" },
    { key = "all", name = "Track every ingredient" },
}
appearanceQueue = {} -- recipes waiting for you to pick ingredients
appearanceSettled = {} -- recipeID -> true: not gear, can't collect, or collected (this session)

-- "uncollected", "collected", "none" (not gear), "unusable" (this character
-- can't collect it) or "loading" (ask again later).
function AppearanceStatus(itemID)
    local T = C_TransmogCollection
    if not (itemID and T and T.GetItemInfo) then return "none" end
    if not IsItemLoaded(itemID) then
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
        return "loading"
    end
    local ok, appearanceID, sourceID = pcall(T.GetItemInfo, itemID)
    if not ok or not appearanceID then return "none" end
    if sourceID and T.PlayerCanCollectSource then
        local okCan, hasData, canCollect = pcall(T.PlayerCanCollectSource, sourceID)
        if okCan and hasData and not canCollect then return "unusable" end
    end
    -- Any item with the same look counts, not just this one.
    if sourceID and T.GetAppearanceInfoBySource then
        local okInfo, info = pcall(T.GetAppearanceInfoBySource, sourceID)
        if okInfo and type(info) == "table" and info.appearanceIsCollected ~= nil then
            return info.appearanceIsCollected and "collected" or "uncollected"
        end
    end
    if sourceID and T.GetSourceInfo then
        local okInfo, info = pcall(T.GetSourceInfo, sourceID)
        if okInfo and type(info) == "table" and info.isCollected then return "collected" end
    end
    if T.PlayerHasTransmog then
        local okHas, has = pcall(T.PlayerHasTransmog, itemID)
        if okHas and has then return "collected" end
    end
    return "uncollected"
end

-- A copy already crafted (bags, bank or an alt) just needs
-- equipping or disenchanting, not another craft.
function OwnsCopy(itemID)
    if CountWhere(itemID, true, false) > 0 then return true end
    for _, snapshot in pairs(settings.inventory or {}) do
        if ((snapshot.bags or {})[itemID] or 0) + ((snapshot.bank or {})[itemID] or 0) > 0 then
            return true
        end
    end
    return false
end

function AppearanceOffered()
    settings.appearanceOffered = settings.appearanceOffered or {}
    local key = CharacterKey()
    settings.appearanceOffered[key] = settings.appearanceOffered[key] or {}
    return settings.appearanceOffered[key]
end

-- Whether the recipe's color lets it in. Unknown colors (profession not
-- loaded) count: a newly learned recipe is almost always orange.
function AppearanceColorOK(recipeID)
    if settings.appearanceAllColors then return true end
    local color = GetRecipeColor(recipeID)
    return color ~= "green" and color ~= "gray"
end

-- The profession a recipe belongs to, named the way BarTab's headings are
-- (the name your other bars or recipes of that skill line already use).
function RecipeProfession(recipeID)
    local id, name
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLineForRecipe then
        local ok, lineID, lineName, parentID, parentName = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, recipeID)
        if ok then
            if parentID and parentID > 0 then
                id, name = parentID, parentName
            else
                id, name = lineID, lineName
            end
        end
    end
    if id then
        for _, item in pairs(trackedItems) do
            if item.skillLineID == id and item.profession then return item.profession, id end
        end
        local mine = settings.producers and settings.producers[CharacterKey()]
        for _, entry in pairs(mine or {}) do
            if entry.skillLineID == id and entry.profession then return entry.profession, id end
        end
    end
    local loaded, loadedID = LoadedProfession()
    if loaded and (not id or loadedID == id) then return loaded, loadedID end
    if name and name ~= "" then return name, id end
    return loaded, loadedID
end

-- The ingredient needed most (Heavy Leather for Hillman's Cloak, not its
-- thread or hide); the first one listed wins a tie.
function MainReagentIndex(reagents)
    local best = 1
    for index, reagent in ipairs(reagents) do
        if reagent.need > reagents[best].need then best = index end
    end
    return best
end

-- Adds one craft's worth of bars for the recipe: for the ingredients picked
-- (a set of indexes), else every ingredient (which = "all") or the main one.
-- Bars go to Inactive when settings.appearanceInactive is on. Returns the
-- recipe's name, or nil.
function TrackRecipeForAppearance(recipeID, outputID, profession, skillLineID, picks, which, kind, crafts)
    local forAppearance = kind == nil or kind == "appearance"
    local reagents = GetRecipeReagents(recipeID)
    if not reagents or #reagents == 0 then return nil end
    if not picks then
        picks = {}
        if (which or settings.appearanceBars) == "all" then
            for index in ipairs(reagents) do picks[index] = true end
        else
            picks[MainReagentIndex(reagents)] = true
        end
    end
    local recipeName = GetRecipeName(recipeID) or GetItemNameByID(outputID) or ("recipe " .. recipeID)
    for index, reagent in ipairs(reagents) do
        local key = RecipeKey(reagent.name, recipeID)
        if picks[index] and not trackedItems[key] then
            trackedItems[key] = {
                name = reagent.name,
                itemID = reagent.itemID,
                start = 0,
                goal = reagent.need * (crafts or 1),
                recipeID = recipeID,
                profession = profession,
                skillLineID = skillLineID,
                label = recipeName,
                afterCraft = forAppearance and "untrack" or nil,
                forAppearance = forAppearance and outputID or nil,
                inactive = forAppearance and settings.appearanceInactive or nil,
                order = NextOrder(),
            }
        end
    end
    if forAppearance then AppearanceOffered()[recipeID] = true end
    return recipeName
end

-- Checks one recipe. Returns a candidate { recipeID, outputID, profession,
-- skillLineID } if it qualifies, "retry" if its item hasn't loaded yet,
-- else nil.
function ConsiderAppearanceRecipe(recipeID, profession, skillLineID)
    local offered = AppearanceOffered()
    if appearanceSettled[recipeID] or offered[recipeID] or IsTrackedRecipe(recipeID)
        or IsAppearanceQueued(recipeID) then
        return nil
    end
    local outputID = GetRecipeOutput(recipeID)
    if not outputID then return nil end
    local status = AppearanceStatus(outputID)
    if status == "loading" then return "retry" end
    if status == "none" or status == "unusable" or status == "collected" then
        appearanceSettled[recipeID] = true
        return nil
    end
    if status ~= "uncollected" or OwnsCopy(outputID) or not AppearanceColorOK(recipeID) then
        return nil
    end
    return { recipeID = recipeID, outputID = outputID, profession = profession, skillLineID = skillLineID }
end

function AnnounceAppearanceBars(names, kind)
    if #names == 0 then return end
    UpdateBars()
    if kind == "favorite" then
        if #names == 1 then
            Print("Tracking " .. names[1] .. " (one craft).")
        else
            Print("Tracking " .. #names .. " favorite recipes (one craft each): " .. table.concat(names, ", ") .. ".")
        end
        return
    end
    local where = settings.appearanceInactive and "; in Inactive" or ""
    if #names == 1 then
        Print("Tracking " .. names[1] .. " for an appearance you haven't collected (one craft"
            .. where .. "; untracked after crafting).")
    else
        Print("Tracking " .. #names .. " recipes for appearances you haven't collected (one craft each"
            .. where .. "; untracked after crafting): " .. table.concat(names, ", ") .. ".")
    end
end

-- Adds bars for each candidate; which = "main" or "all".
-- Whether every ingredient of these recipes has its name loaded (an item
-- the game hasn't loaded yet reads "item 1529"). Asks the game for any
-- that aren't.
function ReagentNamesLoaded(recipeIDs)
    local ready = true
    for _, recipeID in ipairs(recipeIDs) do
        for _, reagent in ipairs(GetRecipeReagents(recipeID) or {}) do
            if reagent.name == "item " .. tostring(reagent.itemID) then ready = false end
        end
    end
    return ready
end

-- Runs fn once the ingredients' names have loaded (or after 3 seconds).
function WhenReagentNamesLoaded(recipeIDs, fn, tries)
    tries = tries or 0
    if tries >= 10 or ReagentNamesLoaded(recipeIDs) then return fn() end
    C_Timer.After(0.3, function() WhenReagentNamesLoaded(recipeIDs, fn, tries + 1) end)
end

-- Places a BarTab window beside the settings window when that's open, so
-- neither hides the other; otherwise near the top of the screen.
function PlaceBesideSettings(frame)
    frame:ClearAllPoints()
    if configFrame and configFrame:IsShown() then
        frame:SetPoint("TOPLEFT", configFrame, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -135)
    end
end

function TrackAppearanceCandidates(list, which)
    local ids = {}
    for _, entry in ipairs(list) do ids[#ids + 1] = entry.recipeID end
    WhenReagentNamesLoaded(ids, function() TrackAppearanceCandidatesNow(list, which) end)
end

function TrackAppearanceCandidatesNow(list, which)
    local names = {}
    for _, entry in ipairs(list) do
        local name = TrackRecipeForAppearance(entry.recipeID, entry.outputID,
            entry.profession, entry.skillLineID, nil, which, entry.kind)
        if name then names[#names + 1] = name end
    end
    AnnounceAppearanceBars(names, list[1] and list[1].kind)
end

-- One recipe: ask which ingredients, or add it as the setting says.
function OfferAppearanceRecipe(entry)
    if (settings.appearanceBars or "ask") == "ask" then
        appearanceQueue[#appearanceQueue + 1] = entry
        ShowAppearancePrompt()
    else
        TrackAppearanceCandidates({ entry })
    end
end

-- Whether BarTab may ask now: not while a window is already up, and not
-- after you closed one with "Later" until you next open a profession window
-- yourself (profession loads also happen when you just hover a bar).
function AppearanceAskBlocked()
    if appearanceSnoozed then return true end
    if #appearanceQueue > 0 then return true end
    if appearanceSummary and appearanceSummary:IsShown() then return true end
    return false
end

-- A recipe you just learned. Always asked about, even after you closed an
-- earlier window: learning it is a fresh reason to ask.
function CheckNewRecipe(recipeID, attempt)
    if not settings.appearanceRecipes then return end
    if appearanceSummary and appearanceSummary:IsShown() then return end
    local profession, skillLineID = RecipeProfession(recipeID)
    local result = ConsiderAppearanceRecipe(recipeID, profession, skillLineID)
    if result == "retry" then
        if attempt < 4 then
            C_Timer.After(2, function() Safe("appearances", CheckNewRecipe)(recipeID, attempt + 1) end)
        end
    elseif result then
        OfferAppearanceRecipe(result)
    end
end

-- Every learned recipe of the loaded profession. Several at once (your first
-- scan, usually) get one summary window instead of a window each.
function ScanAppearanceRecipes()
    if not settings.appearanceRecipes or AppearanceAskBlocked() then return end
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return end
    local profession, professionID = LoadedProfession()
    if not profession then return end
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return end
    local list = {}
    for _, recipeID in ipairs(ids) do
        local okRecipe, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if okRecipe and type(info) == "table" and info.learned then
            local result = ConsiderAppearanceRecipe(recipeID, profession, professionID)
            if type(result) == "table" then list[#list + 1] = result end
        end
    end
    if #list == 1 then
        OfferAppearanceRecipe(list[1])
    elseif #list > 1 then
        ShowAppearanceSummary(list, profession)
    end
end

-- The summary window: N recipes found; track them all (main or every
-- ingredient), choose each, skip them all, or decide later.
function CreateAppearanceSummary()
    local ok, frame = pcall(CreateFrame, "Frame", "BarTabAppearanceSummary", UIParent,
        "BasicFrameTemplateWithInset")
    if not ok then
        frame = CreateFrame("Frame", "BarTabAppearanceSummary", UIParent, "BackdropTemplate")
        if frame.SetBackdrop then
            frame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    frame:SetWidth(360)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -135)
    -- Above BarTab's settings window (turning the option on there can
    -- open this) and other dialogs.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "BarTabAppearanceSummary") -- Escape closes it (Later)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -6)
    title:SetText("BarTab: new appearances")

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("TOPLEFT", 16, -32)
    frame.text:SetPoint("RIGHT", -16, 0)
    frame.text:SetJustifyH("LEFT")

    frame.names = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.names:SetPoint("TOPLEFT", frame.text, "BOTTOMLEFT", 0, -6)
    frame.names:SetPoint("RIGHT", -16, 0)
    frame.names:SetJustifyH("LEFT")

    local all = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    all:SetSize(24, 24)
    if type(all.Text) == "table" then all.Text:SetText("") end
    all.label = all:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    all.label:SetPoint("LEFT", all, "RIGHT", 4, 0)
    all.label:SetText("ALL INGREDIENTS (not just the main one)")
    frame.allCheck = all

    local function button(text, onClick)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(158, 22)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    frame.trackButton = button("Track main ingredients", function() AnswerAppearanceSummary("track") end)
    frame.trackButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 40)
    local each = button("Choose each", function() AnswerAppearanceSummary("each") end)
    each:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 40)
    frame.skipButton = button("Skip all", function() AnswerAppearanceSummary("skip") end)
    frame.skipButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 12)
    frame.laterButton = button("Later", function() AnswerAppearanceSummary("later") end)
    frame.laterButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 12)
    frame.title = title

    all:SetScript("OnClick", function(self)
        frame.trackButton:SetText(self:GetChecked() and "Track all ingredients" or "Track main ingredients")
    end)

    -- Closed with X or Escape: the same as Later (for favorites, Cancel).
    frame:SetScript("OnHide", function(self)
        if self.list and self.kind == "favorite" then
            self.list = nil
        elseif self.list then
            self.list = nil
            appearanceSnoozed = true
            Print("BarTab will ask about them again next time you open a profession window, or now with /bartab appearances scan.")
        end
    end)

    frame:Hide()
    return frame
end

APPEARANCE_SUMMARY_NAMES = 8

function ShowAppearanceSummary(list, profession, kind)
    local frame = appearanceSummary
    if not frame then
        frame = CreateAppearanceSummary()
        appearanceSummary = frame
    end
    frame.list, frame.kind = list, kind
    if kind == "favorite" then
        frame.title:SetText("BarTab: favorite recipes")
        frame.text:SetText(("%d of your favorite %s recipes aren't tracked yet. Track one craft of each?")
            :format(#list, profession or ""))
        frame.skipButton:Hide()
        frame.laterButton:SetText(CANCEL or "Cancel")
        frame.laterButton:ClearAllPoints()
        frame.laterButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    else
        frame.title:SetText("BarTab: new appearances")
        frame.text:SetText(("BarTab found %d %s recipes for appearances you haven't collected. Track one craft of each%s?")
            :format(#list, profession or "", settings.appearanceInactive and " (in Inactive)" or ""))
        frame.skipButton:Show()
        frame.laterButton:SetText("Later")
        frame.laterButton:ClearAllPoints()
        frame.laterButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 12)
    end
    local names = {}
    for i, entry in ipairs(list) do
        if i > APPEARANCE_SUMMARY_NAMES then
            names[#names + 1] = "and " .. (#list - APPEARANCE_SUMMARY_NAMES) .. " more"
            break
        end
        names[#names + 1] = GetRecipeName(entry.recipeID) or GetItemNameByID(entry.outputID) or ("recipe " .. entry.recipeID)
    end
    frame.names:SetText(table.concat(names, ", "))
    local checked = settings.appearanceBars == "all"
    frame.allCheck:SetChecked(checked)
    frame.trackButton:SetText(checked and "Track all ingredients" or "Track main ingredients")
    local textHeight = (frame.text:GetStringHeight() or 24) + 6 + (frame.names:GetStringHeight() or 24)
    frame.allCheck:ClearAllPoints()
    frame.allCheck:SetPoint("TOPLEFT", 16, -38 - textHeight)
    frame:SetHeight(38 + textHeight + 30 + 72)
    PlaceBesideSettings(frame)
    frame:Show()
    frame:Raise()
end

function AnswerAppearanceSummary(answer)
    local frame = appearanceSummary
    local list = frame and frame.list
    if not list then return end
    frame.list = nil -- answered: hiding isn't "Later"
    frame:Hide()
    if answer == "track" then
        TrackAppearanceCandidates(list, frame.allCheck:GetChecked() and "all" or "main")
    elseif answer == "each" then
        for _, entry in ipairs(list) do appearanceQueue[#appearanceQueue + 1] = entry end
        ShowAppearancePrompt()
    elseif frame.kind == "favorite" then
        return -- Cancel
    elseif answer == "skip" then
        local offered = AppearanceOffered()
        for _, entry in ipairs(list) do offered[entry.recipeID] = true end
        Print("Skipped " .. #list .. " recipes; BarTab won't offer them again. New recipes you learn will still be offered.")
    else
        appearanceSnoozed = true
        Print("BarTab will ask about them again next time you open a profession window, or now with /bartab appearances scan.")
    end
end

function IsAppearanceQueued(recipeID)
    for _, entry in ipairs(appearanceQueue) do
        if entry.recipeID == recipeID then return true end
    end
    return false
end

-- The "which ingredients?" window, one recipe at a time. Track adds bars for
-- the ticked ones; Not this one skips the recipe for good; closing it asks
-- again next session (or with /bartab appearances scan).
APPEARANCE_PROMPT_ROWS = 6

-- "Track with settings..." (the profession window's BarTab button): the same
-- window with the recipe's settings below the ingredients, so the bars start
-- out sized and set up rather than needing a trip to the right-click menu.
TRACK_OPTIONS_HEIGHT = 112
PROMPT_TITLES = {
    appearance = "BarTab: new appearance", favorite = "BarTab: favorite recipe",
    trainer = "BarTab: trainer recipe", skill = "BarTab: make until I reach",
    track = "BarTab: track recipe",
}
STOP_CHOICES = { "never", "skill", "yellow", "green", "gray" }

function TrackWithOptions(recipeID)
    if not recipeID then
        Print("Select the recipe in your profession window first.")
        return
    end
    local profession, skillLineID = LoadedProfession()
    if not profession then profession, skillLineID = RecipeProfession(recipeID) end
    local reagents = GetRecipeReagents(recipeID)
    if not reagents or #reagents == 0 then
        Print("Couldn't read this recipe's ingredients.")
        return
    end
    if (appearanceSummary and appearanceSummary:IsShown()) or #appearanceQueue > 0 then
        Print("Finish the BarTab window that's open first.")
        return
    end
    -- Start from the recipe's current settings if it already has bars.
    local existing
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container and not IsOutputBar(item)
            and (not existing or (item.order or 0) < (existing.order or 0)) then
            existing = item
        end
    end
    local options = {
        crafts = math.max(1, existing and SizedCrafts(existing) or 1),
        afterCraft = existing and existing.afterCraft or "keep",
        untilSkill = existing and existing.untilSkill or nil,
        untilColor = existing and existing.untilColor or nil,
    }
    if existing then
        options.countDown = CountsDown(existing)
    else
        options.countDown = settings.countDownDefault and true or false
    end
    appearanceQueue[1] = { recipeID = recipeID, outputID = GetRecipeOutput(recipeID),
        profession = profession, skillLineID = skillLineID, kind = "track",
        crafts = options.crafts, options = options }
    ShowAppearancePrompt()
end

-- The next multiple of 5 in the recipe's profession (capped), and the
-- current skill; nil if the skill can't be read.
function NextSkillTier(entry)
    local skill, profession, cap = GetProfessionSkill({ recipeID = entry.recipeID,
        profession = entry.profession, skillLineID = entry.skillLineID })
    if not skill then return nil end
    local tier = (math.floor(skill / 5) + 1) * 5
    if cap and cap > 0 then tier = math.min(tier, cap) end
    return tier, skill, profession or entry.profession
end

-- "4 Heavy Leather" at the current size; "(tracked)" for ones already tracked.
function UpdatePromptLabels(frame)
    local entry = frame.entry
    if not entry then return end
    for _, check in ipairs(frame.checks) do
        if check:IsShown() and check.reagent then
            check.label:SetText((check.reagent.need * (entry.crafts or 1)) .. " " .. check.reagent.name
                .. (check.tracked and "  |cff808080(tracked)|r" or ""))
        end
    end
end

local function StopText(options)
    if options.untilColor then return "Stop tracking: when it turns " .. options.untilColor end
    if options.untilSkill ~= nil then return "Stop tracking: at skill" end
    return "Stop tracking: never"
end

local function AfterText(options)
    for _, mode in ipairs(AFTER_CRAFT_MODES) do
        if mode.key == (options.afterCraft or "keep") then return "After crafting: " .. mode.phrase end
    end
    return "After crafting: keep the bar"
end

function CreateTrackOptions(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetSize(288, TRACK_OPTIONS_HEIGHT)

    local craftsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    craftsLabel:SetPoint("TOPLEFT", 4, -6)
    craftsLabel:SetText("Crafts:")
    local craftsBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    craftsBox:SetSize(44, 20)
    craftsBox:SetPoint("LEFT", craftsLabel, "RIGHT", 10, 0)
    craftsBox:SetAutoFocus(false)
    craftsBox:SetNumeric(true)
    craftsBox:SetMaxLetters(4)
    craftsBox:SetScript("OnTextChanged", function(self)
        local entry = frame.entry
        local crafts = tonumber(self:GetText())
        if entry and entry.options and crafts and crafts >= 1 then
            entry.crafts, entry.options.crafts = crafts, crafts
            UpdatePromptLabels(frame)
        end
    end)
    craftsBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    craftsBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.craftsBox = craftsBox

    local tierButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    tierButton:SetSize(150, 22)
    tierButton:SetPoint("LEFT", craftsBox, "RIGHT", 10, 0)
    tierButton:SetScript("OnClick", function(self)
        if self.crafts then craftsBox:SetText(tostring(self.crafts)) end
    end)
    panel.tierButton = tierButton

    local afterButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    afterButton:SetSize(288, 22)
    afterButton:SetPoint("TOPLEFT", 0, -32)
    afterButton:SetScript("OnClick", function(self)
        local options = frame.entry and frame.entry.options
        if not options then return end
        local index = 1
        for i, mode in ipairs(AFTER_CRAFT_MODES) do
            if mode.key == (options.afterCraft or "keep") then index = i end
        end
        options.afterCraft = AFTER_CRAFT_MODES[index % #AFTER_CRAFT_MODES + 1].key
        self:SetText(AfterText(options))
    end)
    panel.afterButton = afterButton

    local stopButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    stopButton:SetSize(230, 22)
    stopButton:SetPoint("TOPLEFT", 0, -60)
    local stopBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    stopBox:SetSize(44, 20)
    stopBox:SetPoint("LEFT", stopButton, "RIGHT", 12, 0)
    stopBox:SetAutoFocus(false)
    stopBox:SetNumeric(true)
    stopBox:SetMaxLetters(4)
    stopBox:SetScript("OnTextChanged", function(self)
        local options = frame.entry and frame.entry.options
        if options and options.untilSkill ~= nil then
            options.untilSkill = tonumber(self:GetText()) or false
        end
    end)
    stopBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    stopBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    stopButton:SetScript("OnClick", function(self)
        local entry = frame.entry
        local options = entry and entry.options
        if not options then return end
        local current = options.untilColor or (options.untilSkill ~= nil and "skill") or "never"
        local index = 1
        for i, key in ipairs(STOP_CHOICES) do
            if key == current then index = i end
        end
        local nextKey = STOP_CHOICES[index % #STOP_CHOICES + 1]
        options.untilSkill, options.untilColor = nil, nil
        if nextKey == "skill" then
            options.untilSkill = NextSkillTier(entry) or false
            stopBox:SetText(options.untilSkill and tostring(options.untilSkill) or "")
        elseif nextKey ~= "never" then
            options.untilColor = nextKey
        end
        stopBox:SetShown(options.untilSkill ~= nil)
        self:SetText(StopText(options))
    end)
    panel.stopButton, panel.stopBox = stopButton, stopBox

    local countCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    countCheck:SetSize(24, 24)
    countCheck:SetPoint("TOPLEFT", 0, -86)
    if type(countCheck.Text) == "table" then countCheck.Text:SetText("") end
    local countLabel = countCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countLabel:SetPoint("LEFT", countCheck, "RIGHT", 4, 0)
    countLabel:SetText("Count down as you craft")
    countCheck:SetScript("OnClick", function(self)
        local options = frame.entry and frame.entry.options
        if options then options.countDown = self:GetChecked() and true or false end
    end)
    panel.countCheck = countCheck

    panel:Hide()
    return panel
end

function FillTrackOptions(panel, entry)
    local options = entry.options
    panel.craftsBox:SetText(tostring(options.crafts or 1))
    local tier, skill, profession = NextSkillTier(entry)
    if tier and tier > skill then
        panel.tierButton.crafts = tier - skill
        panel.tierButton:SetText(("To %s %d"):format(profession or "skill", tier))
        panel.tierButton:Show()
    else
        panel.tierButton.crafts = nil
        panel.tierButton:Hide()
    end
    panel.afterButton:SetText(AfterText(options))
    panel.stopButton:SetText(StopText(options))
    panel.stopBox:SetText(options.untilSkill and tostring(options.untilSkill) or "")
    panel.stopBox:SetShown(options.untilSkill ~= nil)
    panel.countCheck:SetChecked(options.countDown and true or false)
end

-- After Track in the "Track with settings..." window: size and set up all of
-- the recipe's bars (new and existing ones alike).
-- A recipe first tracked for its appearance, now set up for something else
-- ("Make until I reach...", "Track with settings..."): its bars become
-- ordinary ones, no longer removed once the look is collected.
function ClearAppearanceRule(recipeID)
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container and item.forAppearance then
            item.forAppearance = nil
            if item.afterCraft == "untrack" then item.afterCraft = nil end
        end
    end
end

function ApplyTrackOptions(entry, name)
    local recipeID, options = entry.recipeID, entry.options
    ClearAppearanceRule(recipeID)
    local crafts = math.max(1, math.floor(tonumber(options.crafts) or 1))
    SizeRecipeBars(recipeID, crafts, true)
    local afterCraft = (options.afterCraft ~= "keep") and options.afterCraft or nil
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container then
            item.afterCraft = afterCraft
            if not IsOutputBar(item) then item.countDown = options.countDown and true or false end
        end
    end
    local level = options.untilSkill or nil
    local _, skill, profession = NextSkillTier(entry)
    if level and skill and level <= skill then
        Print(("Your %s is already %d, so no skill level to stop at was set."):format(profession or "skill", skill))
        level = nil
    end
    SetStopRule(recipeID, level, options.untilColor, true)
    UpdateBars()

    local parts = { crafts .. (crafts == 1 and " craft" or " crafts") }
    if afterCraft then
        for _, mode in ipairs(AFTER_CRAFT_MODES) do
            if mode.key == afterCraft then parts[#parts + 1] = "after crafting, " .. mode.phrase end
        end
    end
    if level then
        parts[#parts + 1] = ("stops at %s %d"):format(profession or "skill", level)
    elseif options.untilColor then
        parts[#parts + 1] = "stops when it turns " .. ColorText(options.untilColor)
    end
    if options.countDown then parts[#parts + 1] = "counts down as you craft" end
    Print(("Tracking %s: %s."):format(name, table.concat(parts, "; ")))
end

function CreateAppearancePrompt()
    local ok, frame = pcall(CreateFrame, "Frame", "BarTabAppearanceFrame", UIParent,
        "BasicFrameTemplateWithInset")
    if not ok then
        frame = CreateFrame("Frame", "BarTabAppearanceFrame", UIParent, "BackdropTemplate")
        if frame.SetBackdrop then
            frame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    frame:SetSize(320, 150)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -135)
    -- Above BarTab's settings window (turning the option on there can
    -- open this) and other dialogs.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "BarTabAppearanceFrame") -- Escape closes it

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -6)
    frame.title:SetText("BarTab: new appearance")

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("TOPLEFT", 16, -32)
    frame.text:SetPoint("RIGHT", -16, 0)
    frame.text:SetJustifyH("LEFT")

    frame.checks = {}
    for i = 1, APPEARANCE_PROMPT_ROWS do
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        if type(check.Text) == "table" then check.Text:SetText("") end
        check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        frame.checks[i] = check
    end

    frame.more = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.options = CreateTrackOptions(frame)

    local track = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    track:SetSize(110, 22)
    track:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 12)
    track:SetText("Track")
    track:SetScript("OnClick", function() AnswerAppearancePrompt("track") end)

    local skip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    skip:SetSize(110, 22)
    skip:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 12)
    skip:SetText("Not this one")
    skip:SetScript("OnClick", function() AnswerAppearancePrompt("skip") end)
    frame.skipButton = skip

    -- Closed without an answer (X or Escape): ask again next session.
    frame:SetScript("OnHide", function(self)
        if self.answered then self.answered = nil return end
        if self.entry then
            local appearance = self.entry.kind == nil or self.entry.kind == "appearance"
            self.entry = nil
            for i = #appearanceQueue, 1, -1 do appearanceQueue[i] = nil end
            if appearance then
                appearanceSnoozed = true
                Print("BarTab will ask again next time you open a profession window, or now with /bartab appearances scan.")
            end
        end
    end)

    frame:Hide()
    return frame
end

function ShowAppearancePrompt()
    local frame = appearancePrompt
    if frame and frame:IsShown() then return end
    local entry = appearanceQueue[1]
    if not entry then return end
    -- Wait (up to 3 seconds) for ingredient names, so the ticks and the
    -- bars don't read "item 1529".
    if not ReagentNamesLoaded({ entry.recipeID }) and (entry.nameTries or 0) < 10 then
        entry.nameTries = (entry.nameTries or 0) + 1
        if not appearancePromptWaiting then
            appearancePromptWaiting = true
            C_Timer.After(0.3, function()
                appearancePromptWaiting = nil
                ShowAppearancePrompt()
            end)
        end
        return
    end
    local reagents = GetRecipeReagents(entry.recipeID)
    if not reagents or #reagents == 0 then
        table.remove(appearanceQueue, 1)
        return ShowAppearancePrompt()
    end
    if not frame then
        frame = CreateAppearancePrompt()
        appearancePrompt = frame
    end
    frame.entry, frame.reagents = entry, reagents
    frame.title:SetText(PROMPT_TITLES[entry.kind or "appearance"] or PROMPT_TITLES.appearance)
    -- "Not this one" means "don't offer it again"; for something you asked
    -- for yourself it's just Cancel.
    frame.skipButton:SetText((entry.kind == "track" or entry.kind == "skill") and (CANCEL or "Cancel") or "Not this one")
    local recipeName = GetRecipeName(entry.recipeID) or GetItemNameByID(entry.outputID) or "This recipe"
    frame.text:SetText(recipeName .. (entry.kind == "skill" and (" until " .. (entry.profession or "skill") .. " "
            .. entry.level .. " (at least " .. entry.crafts .. (entry.crafts == 1 and " craft" or " crafts")
            .. "). Track ingredients for that many:")
        or entry.kind == "track" and ": tick the ingredients to track, and set the recipe up."
        or entry.kind == "favorite" and " is a favorite recipe."
        or entry.kind == "trainer" and (entry.notLearned and (" (not learned yet"
            .. (entry.needSkill and ("; needs " .. entry.needSkill) or "") .. ").") or ".")
        or " makes an appearance you haven't collected.")
        .. ((entry.kind == "skill" or entry.kind == "track") and "" or " Track one craft's worth of:"))
    local textHeight = frame.text:GetStringHeight() or 24
    local y = -36 - textHeight
    local main = MainReagentIndex(reagents)
    for i, check in ipairs(frame.checks) do
        local reagent = reagents[i]
        if reagent then
            check:ClearAllPoints()
            check:SetPoint("TOPLEFT", 16, y)
            check.reagent = reagent
            if entry.kind == "track" then
                -- The main ingredient, plus any the recipe already tracks.
                local tracked = trackedItems[RecipeKey(reagent.name, entry.recipeID)] ~= nil
                check.tracked = tracked
                check:SetChecked(i == main or tracked)
            else
                check.tracked = nil
                check:SetChecked(i == main or settings.appearanceBars == "all")
            end
            check:Show()
            y = y - 24
        else
            check:Hide()
        end
    end
    UpdatePromptLabels(frame)
    if entry.kind == "track" then
        frame.options:ClearAllPoints()
        frame.options:SetPoint("TOPLEFT", 16, y - 6)
        FillTrackOptions(frame.options, entry)
        frame.options:Show()
        y = y - 6 - TRACK_OPTIONS_HEIGHT
    else
        frame.options:Hide()
    end
    local waiting = #appearanceQueue - 1
    frame.more:ClearAllPoints()
    frame.more:SetPoint("TOPLEFT", 20, y - 4)
    frame.more:SetText(waiting > 0 and (waiting .. " more after this one") or "")
    frame:SetHeight(-y + (waiting > 0 and 62 or 48))
    PlaceBesideSettings(frame)
    frame:Show()
    frame:Raise()
end

function AnswerAppearancePrompt(answer)
    local frame = appearancePrompt
    local entry = frame and frame.entry
    if not entry then return end
    table.remove(appearanceQueue, 1)
    if entry.kind == nil or entry.kind == "appearance" then AppearanceOffered()[entry.recipeID] = true end
    if answer == "track" then
        local picks = {}
        for i, check in ipairs(frame.checks) do
            if check:IsShown() and check:GetChecked() then picks[i] = true end
        end
        if next(picks) then
            local name = TrackRecipeForAppearance(entry.recipeID, entry.outputID,
                entry.profession, entry.skillLineID, picks, nil, entry.kind, entry.crafts)
            if name and entry.kind == "skill" then
                RemoveGoalBar(entry.recipeID)
                SetStopRule(entry.recipeID, entry.level, nil, true)
                ClearAppearanceRule(entry.recipeID)
                for _, item in pairs(trackedItems) do
                    if item.recipeID == entry.recipeID and not item.container then
                        item.skillGoal = entry.level
                    end
                end
                UpdateBars()
                Print(("Tracking %s until %s %d (at least %d %s). Click a bar to craft; it stops when you get there."):format(
                    name, entry.profession or "skill", entry.level, entry.crafts, entry.crafts == 1 and "craft" or "crafts"))
            elseif name and entry.kind == "trainer" then
                MarkTrainerBars(entry, name)
            elseif name and entry.kind == "track" then
                ApplyTrackOptions(entry, name)
            elseif name then
                AnnounceAppearanceBars({ name }, entry.kind)
            end
        end
    end
    frame.entry = nil
    frame.answered = true
    frame:Hide()
    if appearanceQueue[1] then ShowAppearancePrompt() end
end

-- Recipes from the trainer ----------------------------------------------------
-- Alt-Shift-click a recipe in a profession trainer's list (or select it and
-- type /bartab trainer) to track its ingredients, even before you've
-- learned it. Until you do, its bars wait in Inactive, marked not learned;
-- they can't craft and vendor buying skips them. Learning the recipe makes
-- them ordinary active bars.

-- The trainer row's recipe ID, read from its tooltip.
function TrainerRecipeID(index)
    local tip = GetScanTooltip()
    if not (tip and tip.SetTrainerService and tip.GetSpell) then return nil end
    tip:SetOwner(_G.WorldFrame or UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    local ok = pcall(tip.SetTrainerService, tip, index)
    local spellID
    if ok then spellID = select(2, tip:GetSpell()) end
    tip:Hide()
    return spellID
end

function TrackTrainerService(index)
    if not (index and GetTrainerServiceInfo) then return end
    local name, status = GetTrainerServiceInfo(index)
    if not name or status == "header" then return end
    local recipeID = TrainerRecipeID(index)
    if not recipeID then
        Print("Couldn't tell which recipe " .. name .. " is.")
        return
    end
    if IsTrackedRecipe(recipeID) then
        Print(name .. " is already tracked.")
        return
    end
    local reagents = GetRecipeReagents(recipeID)
    if not reagents or #reagents == 0 then
        Print("Couldn't read the ingredients for " .. name .. ". Open your profession window as well, then try again.")
        return
    end
    local profession, skillLineID
    local needSkill
    if GetTrainerServiceSkillReq then
        local skill, rank = GetTrainerServiceSkillReq(index)
        if skill and skill ~= "" then
            profession = skill
            if rank and rank > 0 then needSkill = skill .. " " .. rank end
        end
    end
    local lineProfession, lineID = RecipeProfession(recipeID)
    profession = profession or lineProfession
    skillLineID = lineID
    local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    local learned = status == "used" or (okInfo and type(info) == "table" and info.learned)
    if (appearanceSummary and appearanceSummary:IsShown()) or #appearanceQueue > 0 then
        Print("Finish the BarTab window that's open first.")
        return
    end
    appearanceQueue[1] = { recipeID = recipeID, outputID = GetRecipeOutput(recipeID),
        profession = profession, skillLineID = skillLineID, kind = "trainer",
        recipeName = name, notLearned = not learned or nil, needSkill = needSkill }
    ShowAppearancePrompt()
end

-- The new bars: waiting in Inactive until the recipe is learned.
function MarkTrainerBars(entry, name)
    for _, item in pairs(trackedItems) do
        if item.recipeID == entry.recipeID then
            item.recipeName = entry.recipeName or name
            if entry.notLearned then
                item.notLearned = true
                item.inactive = true
                item.needSkill = entry.needSkill
                item.label = item.recipeName .. " (not learned)"
            end
        end
    end
    UpdateBars()
    if entry.notLearned then
        Print("Tracking " .. (entry.recipeName or name) .. " (one craft), in Inactive until you learn it"
            .. (entry.needSkill and (" (needs " .. entry.needSkill .. ")") or "") .. ".")
    else
        Print("Tracking " .. (entry.recipeName or name) .. " (one craft).")
    end
end

-- A recipe you've learned: its waiting bars become active.
function ActivateLearnedRecipe(recipeID)
    local name
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and item.notLearned then
            item.notLearned, item.inactive, item.needSkill = nil, nil, nil
            item.label = item.recipeName or GetRecipeName(recipeID) or item.label
            name = name or item.label
        end
    end
    if name then
        UpdateBars()
        Print(name .. " learned; its bars are now active.")
    end
end

-- Recipes learned while BarTab wasn't looking (another addon set, an older
-- session): checked whenever a profession loads.
function CheckLearnedRecipes()
    local seen = {}
    for _, item in pairs(trackedItems) do
        if item.notLearned and item.recipeID and not seen[item.recipeID] then
            seen[item.recipeID] = true
            local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, item.recipeID)
            if ok and type(info) == "table" and info.learned then
                ActivateLearnedRecipe(item.recipeID)
            end
        end
    end
end

-- Hovering a trainer row: say how to track it.
function TrainerHint(index)
    if not (index and GetTrainerServiceInfo) then return nil end
    local name, status = GetTrainerServiceInfo(index)
    if not name or status == "header" then return nil end
    local recipeID = TrainerRecipeID(index)
    if not recipeID then return nil end
    if IsTrackedRecipe(recipeID) then return "BarTab: tracking this recipe" end
    if status == "used" or IsRecipeLearned(recipeID) then
        return "BarTab: Alt-Shift-click to track this recipe"
    end
    return "BarTab: Alt-Shift-click to add this recipe to your Inactive list"
end

if GameTooltip and GameTooltip.SetTrainerService and hooksecurefunc then
    pcall(hooksecurefunc, GameTooltip, "SetTrainerService", function(self, index)
        if settings.itemTooltips == false then return end
        local ok, hint = pcall(TrainerHint, index)
        if ok and hint then
            self:AddLine(hint, 0.4, 0.8, 1)
            self:Show()
        end
    end)
end

-- Alt-Shift-click a trainer row: clicking one selects it.
if hooksecurefunc and SelectTrainerService then
    pcall(hooksecurefunc, "SelectTrainerService", function(index)
        if IsAltKeyDown() and IsShiftKeyDown() and not IsControlKeyDown() then
            Safe("trainer", TrackTrainerService)(index)
        end
    end)
end

-- Recipe items ("Pattern: Red Woolen Bag") -------------------------------------
-- Alt-Shift-clicking one (at a vendor, in your bags)
-- tracks the recipe it teaches the way the trainer does: in Inactive until
-- you learn it. Matched by name to your professions' recipes, which BarTab
-- notes whenever a profession loads.
RECIPE_ITEM_PREFIXES = { "Pattern", "Recipe", "Plans", "Formula", "Schematic", "Manual", "Design", "Technique" }

-- The recipe a recipe item teaches: { recipeID, profession, skillLineID }.
function RecipeFromItemName(itemName)
    if not itemName then return nil end
    local rest
    for _, prefix in ipairs(RECIPE_ITEM_PREFIXES) do
        rest = itemName:match("^" .. prefix .. ":%s*(.+)$")
        if rest then break end
    end
    if not rest then return nil end
    local index = settings.recipeIndex and settings.recipeIndex[CharacterKey()]
    return index and index[string.lower(rest)], rest
end

function IsRecipeLearned(recipeID)
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    return ok and type(info) == "table" and info.learned and true or false
end

-- Tooltip line for a recipe item, or nil.
function RecipeItemHint(itemName)
    local recipe = RecipeFromItemName(itemName)
    if not recipe then return nil end
    if IsTrackedRecipe(recipe.recipeID) then return "BarTab: tracking this recipe" end
    if IsRecipeLearned(recipe.recipeID) then return nil end
    return "BarTab: Alt-Shift-click to add this recipe to your Inactive list"
end

-- Alt-Shift-click on a recipe item. Returns true if it was one BarTab knows.
function TrackRecipeItem(itemName)
    local recipe, recipeName = RecipeFromItemName(itemName)
    if not recipe then return false end
    if IsTrackedRecipe(recipe.recipeID) then
        Print(recipeName .. " is already tracked.")
        return true
    end
    local reagents = GetRecipeReagents(recipe.recipeID)
    if not reagents or #reagents == 0 then
        Print("Couldn't read the ingredients for " .. recipeName .. ". Open your " .. (recipe.profession or "profession")
            .. " window as well, then try again.")
        return true
    end
    if (appearanceSummary and appearanceSummary:IsShown()) or #appearanceQueue > 0 then
        Print("Finish the BarTab window that's open first.")
        return true
    end
    appearanceQueue[1] = { recipeID = recipe.recipeID, outputID = GetRecipeOutput(recipe.recipeID),
        profession = recipe.profession, skillLineID = recipe.skillLineID, kind = "trainer",
        recipeName = recipeName, notLearned = not IsRecipeLearned(recipe.recipeID) or nil }
    ShowAppearancePrompt()
    return true
end

-- Make until you have N ---------------------------------------------------------
-- A bar for what a recipe makes ("Handful of Copper Bolts 12/52"). Its clicks
-- craft only what's still missing, and a batch (Create All in the profession
-- window too) stops once you have that many. Made from the profession
-- window's BarTab button ("Make until I have...") or /bartab make <count>.

function IsOutputBar(item)
    if not (item and item.recipeID) or item.container then return false end
    local outputID = GetRecipeOutput(item.recipeID)
    if not outputID then return false end
    if item.itemID and item.itemID == outputID then return true end
    local name = GetItemNameByID(outputID)
    return name ~= nil and string.lower(name) == string.lower(item.name)
end

-- Crafts it takes to reach the bar's target (rounded up: one craft can make
-- several).
function CraftsToTarget(item)
    local _, perCraft = GetRecipeOutput(item.recipeID)
    local missing = (item.goal or 0) - CountItem(item)
    if missing <= 0 then return 0 end
    return math.ceil(missing / math.max(1, perCraft or 1))
end

function MakeUntil(recipeID, goal)
    goal = tonumber(goal)
    if not recipeID then
        Print("Select the recipe in your profession window first.")
        return
    end
    if not goal or goal < 1 then
        Print("Give the number you want, e.g. /bartab make 52.")
        return
    end
    local outputID, perCraft = GetRecipeOutput(recipeID)
    local name = outputID and GetItemNameByID(outputID)
    if not name then
        Print("Couldn't tell what that recipe makes.")
        return
    end
    local profession, skillLineID = LoadedProfession()
    if not profession then profession, skillLineID = RecipeProfession(recipeID) end
    local key = RecipeKey(name, recipeID)
    local item = trackedItems[key]
    if item then
        item.start, item.goal, item.countFrom, item.countDone = 0, goal, nil, nil
        item.inactive = nil
    else
        item = { name = name, itemID = outputID, start = 0, goal = goal, recipeID = recipeID,
            profession = profession, skillLineID = skillLineID,
            label = GetRecipeName(recipeID) or name, order = NextOrder() }
        trackedItems[key] = item
    end
    goalReached[key] = nil
    -- The goal bar replaces the recipe's ingredient bars: one bar, one
    -- purpose (two bars headed with the same recipe name were confusing).
    local replaced = {}
    for otherKey, other in pairs(trackedItems) do
        if otherKey ~= key and other.recipeID == recipeID and not other.container then
            replaced[#replaced + 1] = other.name
            trackedItems[otherKey] = nil
        end
    end
    UpdateBars()
    if #replaced > 0 then
        table.sort(replaced)
        local list = #replaced > 1
            and (table.concat(replaced, ", ", 1, #replaced - 1) .. " and " .. replaced[#replaced])
            or replaced[1]
        Print(("Replaced the %s %s for %s with the goal bar."):format(list,
            #replaced == 1 and "bar" or "bars", GetRecipeName(recipeID) or name))
    end
    local have = CountItem(item)
    local crafts = CraftsToTarget(item)
    Print(("Crafting %s until you have %d (you have %d%s)."):format(name, goal, have,
        crafts > 0 and ("; " .. crafts .. (crafts == 1 and " craft" or " crafts") .. " to go") or ""))
end

function AskMakeGoal(recipeID, current)
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    local outputID = GetRecipeOutput(recipeID)
    local name = outputID and GetItemNameByID(outputID) or GetRecipeName(recipeID) or "it"
    StaticPopupDialogs.BARTAB_MAKE_GOAL = StaticPopupDialogs.BARTAB_MAKE_GOAL or {
        text = "Craft %s until you have how many?",
        button1 = OKAY or "OK",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 5,
        OnShow = function(self, data)
            local box = self.editBox or self.EditBox
            if box then
                box:SetText(data.current and tostring(data.current) or "")
                box:HighlightText()
                box:SetFocus()
            end
        end,
        OnAccept = function(self, data)
            local box = self.editBox or self.EditBox
            MakeUntil(data.recipeID, box and box:GetText())
        end,
        EditBoxOnEnterPressed = function(box, data)
            local parent = box:GetParent()
            data = data or parent.data
            MakeUntil(data.recipeID, box:GetText())
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("BARTAB_MAKE_GOAL", name, nil, { recipeID = recipeID, current = current })
end

-- Make until you reach a skill level: the recipe's ingredient bars (sized for
-- the fewest crafts it could take, one point a craft), a "stop at skill" rule
-- that ends the batch and clears the bars at that level, and a batch of as
-- many as your materials allow, started right away.
function CraftUntilSkill(recipeID, level)
    level = tonumber(level)
    if not recipeID then
        Print("Select the recipe in your profession window first.")
        return
    end
    local profession, skillLineID = LoadedProfession()
    if not profession then profession, skillLineID = RecipeProfession(recipeID) end
    local skill, _, cap = GetProfessionSkill({ recipeID = recipeID, profession = profession, skillLineID = skillLineID })
    if not level or level < 1 then
        Print("Give the skill level to reach, e.g. 165.")
        return
    end
    if cap and cap > 0 and level > cap then
        Print(("%s can only go to %d for now (train to raise it)."):format(profession or "This profession", cap))
        return
    end
    if skill and skill >= level then
        Print(("Your %s is already %d."):format(profession or "skill", skill))
        return
    end
    local reagents = GetRecipeReagents(recipeID)
    if not reagents or #reagents == 0 then
        Print("Couldn't read this recipe's ingredients.")
        return
    end
    local crafts = math.max(1, level - (skill or 0))
    if (appearanceSummary and appearanceSummary:IsShown()) or #appearanceQueue > 0 then
        Print("Finish the BarTab window that's open first.")
        return
    end
    -- Which ingredients to track: the usual window, main one ticked.
    appearanceQueue[1] = { recipeID = recipeID, outputID = GetRecipeOutput(recipeID),
        profession = profession, skillLineID = skillLineID, kind = "skill",
        level = level, crafts = crafts }
    ShowAppearancePrompt()
end

function AskSkillGoal(recipeID)
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    local profession = LoadedProfession() or "your profession"
    local skill = GetProfessionSkill({ recipeID = recipeID, profession = profession })
    StaticPopupDialogs.BARTAB_SKILL_GOAL = StaticPopupDialogs.BARTAB_SKILL_GOAL or {
        text = "Craft %s until %s reaches skill level:",
        button1 = OKAY or "OK",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 4,
        OnShow = function(self, data)
            local box = self.editBox or self.EditBox
            if box then
                box:SetText(data.default and tostring(data.default) or "")
                box:HighlightText()
                box:SetFocus()
            end
        end,
        OnAccept = function(self, data)
            local box = self.editBox or self.EditBox
            CraftUntilSkill(data.recipeID, box and box:GetText())
        end,
        EditBoxOnEnterPressed = function(box, data)
            local parent = box:GetParent()
            data = data or parent.data
            CraftUntilSkill(data.recipeID, box:GetText())
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    local default = skill and (math.floor(skill / 5) + 1) * 5 or nil
    StaticPopup_Show("BARTAB_SKILL_GOAL", GetRecipeName(recipeID) or "this recipe", profession,
        { recipeID = recipeID, default = default })
end

-- After each bag update: a batch of a recipe whose output bar has reached
-- its target stops.
function CheckMakeTargets()
    local recipeID = (crafting and crafting.id) or lastCraftRecipe
    if not recipeID then return end
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.inactive and IsOutputBar(item)
            and CountItem(item) >= item.goal then
            StopCraftingRecipe(recipeID, item.name, ("you have %d"):format(CountItem(item)))
            return
        end
    end
end

-- Training reminders -----------------------------------------------------------
-- Two nudges to visit a trainer (settings.trainingReminders, on by default):
--  * a profession reaching its current limit (75, 150, 225), once per limit;
--  * recipes you saw at a trainer that you couldn't learn yet, once your
--    skill (and level) is high enough. Each trainer visit notes what it
--    teaches; learned ones drop off. Kept per character in settings.training.
PROFESSION_NAMES = {
    alchemy = true, blacksmithing = true, enchanting = true, engineering = true,
    herbalism = true, leatherworking = true, mining = true, skinning = true,
    tailoring = true, jewelcrafting = true, inscription = true,
    cooking = true, ["first aid"] = true, fishing = true,
}
PROFESSION_TOP = 300 -- the highest limit; nothing to train past it
NEXT_RANKS = { [75] = { "Journeyman", 10 }, [150] = { "Expert", 20 }, [225] = { "Artisan", 35 } }

function TrainingData()
    settings.training = settings.training or {}
    local key = CharacterKey()
    settings.training[key] = settings.training[key] or {}
    local data = settings.training[key]
    data.capped = data.capped or {}
    data.recipes = data.recipes or {}
    return data
end

-- { { name=, rank=, rankMax= }, ... } for every profession you have.
function AllProfessionSkills()
    local list = {}
    if GetProfessions and GetProfessionInfo then
        local indexes = { GetProfessions() }
        for i = 1, 6 do
            if indexes[i] then
                local ok, name, _, rank, rankMax = pcall(GetProfessionInfo, indexes[i])
                if ok and name then
                    list[#list + 1] = { name = name, rank = tonumber(rank) or 0, rankMax = tonumber(rankMax) or 0 }
                end
            end
        end
        if #list > 0 then return list end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for index = 1, GetNumSkillLines() do
            local name, header, _, rank, _, _, rankMax = GetSkillLineInfo(index)
            if name and not header and PROFESSION_NAMES[string.lower(name)] then
                list[#list + 1] = { name = name, rank = tonumber(rank) or 0, rankMax = tonumber(rankMax) or 0 }
            end
        end
    end
    return list
end

function PlayerLevel()
    return (UnitLevel and UnitLevel("player")) or 0
end

-- "A, B and C", or "A, B, C and 4 more" for long lists.
function JoinNames(names, most)
    most = most or 4
    if #names <= 1 then return names[1] or "" end
    if #names > most then
        return table.concat(names, ", ", 1, most - 1) .. (" and %d more"):format(#names - most + 1)
    end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

function CheckSkillCaps()
    local data = TrainingData()
    for _, skill in ipairs(AllProfessionSkills()) do
        local lower = string.lower(skill.name)
        if skill.rankMax > 0 and skill.rankMax < PROFESSION_TOP and skill.rank >= skill.rankMax then
            if data.capped[lower] ~= skill.rankMax then
                data.capped[lower] = skill.rankMax
                local nextRank = NEXT_RANKS[skill.rankMax]
                local text = ("%s is at its limit (%d/%d): learn %s to keep gaining skill."):format(
                    skill.name, skill.rank, skill.rankMax,
                    nextRank and (nextRank[1] .. " " .. skill.name) or "the next rank")
                if nextRank and PlayerLevel() > 0 and PlayerLevel() < nextRank[2] then
                    text = text .. (" (Needs level %d.)"):format(nextRank[2])
                end
                PlayGoalAlert(text)
            end
        elseif data.capped[lower] and skill.rankMax > data.capped[lower] then
            data.capped[lower] = nil -- trained: remind again at the next limit
        end
    end
end

-- Recipes noted at a trainer that you've now reached, grouped by trainer.
function CheckTrainerRecipes()
    local data = TrainingData()
    local level = PlayerLevel()
    local ranks = {}
    for _, skill in ipairs(AllProfessionSkills()) do ranks[string.lower(skill.name)] = skill.rank end
    local byTrainer, order = {}, {}
    for profession, recipes in pairs(data.recipes) do
        local rank = ranks[profession]
        if rank then
            for name, recipe in pairs(recipes) do
                if not recipe.told and rank >= (recipe.skill or 0) and level >= (recipe.level or 0) then
                    recipe.told = true
                    local where = recipe.trainer or "your trainer"
                    if recipe.zone and recipe.zone ~= "" then where = where .. " (" .. recipe.zone .. ")" end
                    if not byTrainer[where] then
                        byTrainer[where] = { names = {}, profession = recipe.professionName or profession }
                        order[#order + 1] = where
                    end
                    table.insert(byTrainer[where].names, name)
                end
            end
        end
    end
    table.sort(order)
    for _, where in ipairs(order) do
        local group = byTrainer[where]
        table.sort(group.names)
        PlayGoalAlert(("%d new %s %s to learn at %s: %s."):format(#group.names, group.profession,
            #group.names == 1 and "recipe" or "recipes", where, JoinNames(group.names)))
    end
end

function CheckTraining()
    if settings.trainingReminders == false then return end
    CheckSkillCaps()
    CheckTrainerRecipes()
end

-- At a profession trainer: note what it teaches and what each needs. Every
-- type filter is turned on for the read (recipes you can't learn yet are
-- hidden by default), then put back as it was.
function ScanTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) then return end
    if IsTradeskillTrainer and not IsTradeskillTrainer() then return end
    local saved
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        saved = {}
        for _, kind in ipairs({ "available", "unavailable", "used" }) do
            local value = GetTrainerServiceTypeFilter(kind)
            saved[kind] = (value and value ~= 0) and 1 or 0
            if saved[kind] == 0 then SetTrainerServiceTypeFilter(kind, 1) end
        end
    end
    local data = TrainingData()
    local trainer = UnitName and UnitName("npc")
    local zone = GetZoneText and GetZoneText()
    local ok, err = pcall(function()
        for index = 1, GetNumTrainerServices() do
            local name, status = GetTrainerServiceInfo(index)
            if name and status ~= "header" then
                local skillName, skillRank = GetTrainerServiceSkillReq(index)
                if skillName and skillName ~= "" then
                    local profession = string.lower(skillName)
                    data.recipes[profession] = data.recipes[profession] or {}
                    local recipes = data.recipes[profession]
                    if status == "used" then
                        recipes[name] = nil
                    else
                        local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(index)
                        local old = recipes[name]
                        recipes[name] = {
                            skill = tonumber(skillRank) or 0, level = tonumber(level) or 0,
                            trainer = trainer, zone = zone, professionName = skillName,
                            -- What you can learn now is in front of you already.
                            told = status == "available" or (old and old.told) or nil,
                        }
                    end
                end
            end
        end
    end)
    if saved then
        for kind, value in pairs(saved) do
            if value == 0 then SetTrainerServiceTypeFilter(kind, 0) end
        end
    end
    if not ok then error(err) end
end

trainingWatcher = CreateFrame("Frame")
trainingWatcher.barTabOwn = true
for _, trainingEvent in ipairs({ "TRAINER_SHOW", "PLAYER_LEVEL_UP" }) do
    pcall(trainingWatcher.RegisterEvent, trainingWatcher, trainingEvent)
end
trainingWatcher:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" then
        -- A moment for the trainer's list to fill.
        C_Timer.After(0.2, function() Safe("training", ScanTrainer)() end)
    else
        C_Timer.After(1, function() Safe("training", CheckTraining)() end)
    end
end)

-- Favorite recipes ------------------------------------------------------------
-- /bartab favorites (or the settings button) tracks the loaded profession's
-- starred recipes that have no bars yet, through the same windows as
-- appearances. With settings.autoFavorites, starring a recipe offers it.

function FavoriteEntry(recipeID, profession, skillLineID)
    return { recipeID = recipeID, outputID = GetRecipeOutput(recipeID),
        profession = profession, skillLineID = skillLineID, kind = "favorite" }
end

function ImportFavoriteRecipes()
    local profession, professionID = LoadedProfession()
    if not profession or not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then
        Print("Open a profession first; BarTab imports the favorites of the profession that's open.")
        return
    end
    if (appearanceSummary and appearanceSummary:IsShown()) or #appearanceQueue > 0 then
        Print("Finish the BarTab window that's open first.")
        return
    end
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return end
    local list, already = {}, 0
    for _, recipeID in ipairs(ids) do
        local okRecipe, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if okRecipe and type(info) == "table" and info.favorite and info.learned ~= false then
            if IsTrackedRecipe(recipeID) then
                already = already + 1
            else
                local reagents = GetRecipeReagents(recipeID)
                if reagents and #reagents > 0 then
                    list[#list + 1] = FavoriteEntry(recipeID, profession, professionID)
                end
            end
        end
    end
    if #list == 0 then
        Print(already > 0 and ("All your favorite " .. profession .. " recipes are already tracked.")
            or ("You have no favorite " .. profession .. " recipes. Click the star beside a recipe in the profession window to make it one."))
    elseif #list == 1 then
        appearanceQueue[1] = list[1]
        ShowAppearancePrompt()
    else
        ShowAppearanceSummary(list, profession, "favorite")
    end
end

function OnRecipeFavorited(recipeID, favorite)
    if not (favorite and settings.autoFavorites and recipeID) then return end
    if IsTrackedRecipe(recipeID) or IsAppearanceQueued(recipeID) then return end
    if appearanceSummary and appearanceSummary:IsShown() then return end
    local profession, skillLineID = LoadedProfession()
    if not profession then profession, skillLineID = RecipeProfession(recipeID) end
    appearanceQueue[#appearanceQueue + 1] = FavoriteEntry(recipeID, profession, skillLineID)
    ShowAppearancePrompt()
end

if C_TradeSkillUI and C_TradeSkillUI.SetRecipeFavorite and hooksecurefunc then
    pcall(hooksecurefunc, C_TradeSkillUI, "SetRecipeFavorite", function(recipeID, favorite)
        Safe("favorites", OnRecipeFavorited)(recipeID, favorite)
    end)
end

-- Appearance bars whose appearance you've since collected some other way
-- (looted or bought the item, an alt equipped one) are done: they follow
-- their After crafting rule (untrack, unless you changed it).
function CheckCollectedAppearances()
    if not trackedItems then return end
    local done = {}
    for _, item in pairs(trackedItems) do
        if item.forAppearance and item.recipeID and not done[item.recipeID]
            and AppearanceStatus(item.forAppearance) == "collected" then
            done[item.recipeID] = true
        end
    end
    for recipeID in pairs(done) do
        AfterCraftDone(recipeID, "appearance collected")
    end
end

collectionWatcher = CreateFrame("Frame")
collectionWatcher.barTabOwn = true
pcall(collectionWatcher.RegisterEvent, collectionWatcher, "TRANSMOG_COLLECTION_UPDATED")
pcall(collectionWatcher.RegisterEvent, collectionWatcher, "PLAYER_ENTERING_WORLD")
collectionCheckPending = false
collectionWatcher:SetScript("OnEvent", function()
    if collectionCheckPending then return end
    collectionCheckPending = true
    C_Timer.After(2, function()
        collectionCheckPending = false
        Safe("appearances", CheckCollectedAppearances)()
    end)
end)

-- After crafting gear for an appearance: crafting alone doesn't collect it.
function RemindToEquip(recipeID)
    if not settings.appearanceRecipes then return end
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and item.forAppearance then
            if AppearanceStatus(item.forAppearance) == "uncollected" then
                local name = GetItemNameByID(item.forAppearance) or DisplayName(item)
                Print("Equip or disenchant " .. name .. " to collect its appearance (crafting it doesn't add it to your collection).")
            end
            return
        end
    end
end

-- Vendor materials -------------------------------------------------------------
-- At a vendor, offers to buy (or just buys) what your Crafting bars are short
-- of, when the vendor sells it for gold. settings.vendorBuy: "ask" (default),
-- "auto" or "off".
VENDOR_MODES = {
    { key = "ask", name = "Ask before buying missing materials" },
    { key = "auto", name = "Buy missing materials automatically" },
    { key = "off", name = "Off (buy by hand)" },
}

-- Right-click checkbox: whether vendor buying covers this bar (for a recipe
-- bar, the whole recipe). On unless turned off: item.noVendor.
function VendorMenuEntry(item)
    local function bars()
        local list = {}
        for _, other in pairs(trackedItems) do
            if other == item or (item.recipeID and other.recipeID == item.recipeID
                and not other.container) then
                list[#list + 1] = other
            end
        end
        return list
    end
    return {
        "Buy materials at vendors",
        function()
            local off = not item.noVendor or nil
            for _, other in ipairs(bars()) do other.noVendor = off end
            Print(DisplayName(item) .. (off and ": materials won't be bought at vendors."
                or ": materials can be bought at vendors."))
        end,
        selected = not item.noVendor,
        isSelected = function() return not item.noVendor end,
        check = true,
    }
end

-- Material name (lower case) -> how many your active Crafting bars are short.
-- Includes ingredients of tracked recipes that have no bar of their own
-- (Fine Thread for Hillman's Cloak when only Heavy Leather has a bar): the
-- recipe's bars say how many crafts are planned.
-- forAuction: the auction house list, which also covers the Items section
-- and recipes left out of vendor buying.
-- sold: what this vendor sells ({ ids = {[id]=true}, names = {[lower]=true} }).
-- With settings.vendorWhenReady, a recipe's vendor materials are only bought
-- for the crafts its tracked bars (the ones this vendor doesn't sell) already
-- cover: 8 of 10 Heavy Leather at 5 a craft -> thread for 1 craft. Ingredients
-- without a bar don't count.
function GetShortages(forAuction, sold)
    local short, names, ids = {}, {}, {}   -- ids: item ID -> material key
    local barMaterials = {}   -- recipeID -> { material = true } with a bar
    local plannedCrafts = {}  -- recipeID -> crafts the bars are sized for

    local function IsSold(name, itemID)
        return (itemID and sold.ids[itemID]) or sold.names[string.lower(name)]
    end

    -- recipeID -> crafts your other ingredients cover (only with the setting).
    local readyCrafts = {}
    if not forAuction and settings.vendorWhenReady and sold then
        local bars = {}   -- recipeID -> { material = bar }
        for _, item in pairs(trackedItems) do
            if item.recipeID and not item.container and not item.inactive then
                bars[item.recipeID] = bars[item.recipeID] or {}
                bars[item.recipeID][string.lower(item.name)] = item
            end
        end
        -- Only the recipe's tracked bars count: an ingredient with no bar
        -- (an Iron Buckle you'll get later) doesn't hold the purchase up.
        for recipeID, recipeBars in pairs(bars) do
            local crafts
            for _, bar in pairs(recipeBars) do
                if not IsSold(bar.name, ItemIDFor(bar)) then
                    local perCraft = GetReagentQuantity(recipeID, bar.name)
                    if perCraft and perCraft > 0 then
                        -- What you have, plus what you could make of it
                        -- first (Heavy Leather into Thick Leather): chain
                        -- crafting will.
                        local have = GetBarCount(bar)
                        local okMake, makeable = pcall(MakeableCount, bar, have)
                        if okMake and makeable then have = have + makeable end
                        local covered = math.floor(have / perCraft)
                        if not crafts or covered < crafts then crafts = covered end
                    end
                end
            end
            readyCrafts[recipeID] = crafts -- nil: every tracked bar is sold here
        end
    end

    for _, item in pairs(trackedItems) do
        local section = GetSection(item)
        -- Inactive bars only on the auction house list, and only with
        -- settings.auctionInactive (shelved or not-yet-learned recipes).
        if not item.container and not item.altNeed and (not item.inactive or (forAuction and settings.auctionInactive))
            and (forAuction or not (item.noVendor or item.notLearned))
            and (section == CRAFT_SECTION or (forAuction and section == ITEM_SECTION)) then
            local key = string.lower(item.name)
            local id = ItemIDFor(item)
            if id then ids[id] = key end
            local target = item.goal
            local ready = item.recipeID and readyCrafts[item.recipeID]
            if ready then
                -- Only enough for the crafts the other ingredients cover.
                local perCraft = GetReagentQuantity(item.recipeID, item.name)
                if perCraft and perCraft > 0 then
                    target = math.min(target, ready * perCraft)
                end
            end
            local missing = target - GetBarCount(item)
            if missing > 0 then
                short[key] = (short[key] or 0) + missing
                names[key] = item.name
            end
            if item.recipeID then
                barMaterials[item.recipeID] = barMaterials[item.recipeID] or {}
                barMaterials[item.recipeID][key] = true
                local perCraft = GetReagentQuantity(item.recipeID, item.name)
                if perCraft and perCraft > 0 then
                    local crafts = math.ceil(item.goal / perCraft)
                    if crafts > (plannedCrafts[item.recipeID] or 0) then
                        plannedCrafts[item.recipeID] = crafts
                    end
                end
            end
        end
    end

    -- Ingredients without a bar: crafts x amount per craft, less what you
    -- have (and less what other recipes already claimed above).
    local claimed = {}
    for recipeID, crafts in pairs(plannedCrafts) do
        if readyCrafts[recipeID] then crafts = math.min(crafts, readyCrafts[recipeID]) end
        for _, reagent in ipairs(GetRecipeReagents(recipeID) or {}) do
            local key = string.lower(reagent.name)
            if not barMaterials[recipeID][key] then
                claimed[key] = (claimed[key] or 0) + crafts * reagent.need
                names[key] = names[key] or reagent.name
                if reagent.itemID then ids[reagent.itemID] = key end
            end
        end
    end
    for key, needed in pairs(claimed) do
        local missing = needed - GetItemCount(names[key])
        if missing > 0 then short[key] = (short[key] or 0) + missing end
    end
    return short, names, ids
end

-- One merchant slot: name, price per purchase, items per purchase, stock
-- (-1 = unlimited), and whether it costs only gold.
function GetMerchantSlot(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" then
            return info.name, info.price, info.stackCount, info.numAvailable,
                info.isPurchasable ~= false and not info.hasExtendedCost
        end
    end
    if GetMerchantItemInfo then
        local name, _, price, quantity, numAvailable, isPurchasable, _, extendedCost =
            GetMerchantItemInfo(index)
        return name, price, quantity, numAvailable, isPurchasable ~= false and not extendedCost
    end
end

-- The item ID of a vendor's slot, if the game says.
function GetMerchantSlotID(index)
    local merchantID = GetMerchantItemID and GetMerchantItemID(index)
    if not merchantID and GetMerchantItemLink then
        local link = GetMerchantItemLink(index)
        merchantID = link and tonumber(link:match("item:(%d+)"))
    end
    return merchantID
end

function FindVendorPurchases()
    if not GetMerchantNumItems then return {} end
    -- What this vendor sells, so "only when ready" knows which bars to wait on.
    local sold = { ids = {}, names = {} }
    for index = 1, GetMerchantNumItems() do
        local slotName = GetMerchantSlot(index)
        local slotID = GetMerchantSlotID(index)
        if slotID then sold.ids[slotID] = true end
        if slotName then sold.names[string.lower(slotName)] = true end
    end
    local short, names, ids = GetShortages(false, sold)
    local list = {}
    for index = 1, GetMerchantNumItems() do
        local name, price, perPurchase, available, goldOnly = GetMerchantSlot(index)
        -- Match by item ID when the vendor says which item it is.
        local merchantID = GetMerchantSlotID(index)
        local key = (merchantID and ids[merchantID]) or (name and string.lower(name))
        if key and short[key] and goldOnly and price and price > 0 then
            perPurchase = math.max(1, tonumber(perPurchase) or 1)
            local purchases = math.ceil(short[key] / perPurchase)
            if available and available >= 0 then purchases = math.min(purchases, available) end
            if purchases > 0 then
                list[#list + 1] = {
                    index = index, name = names[key], perPurchase = perPurchase,
                    purchases = purchases, count = purchases * perPurchase,
                    cost = purchases * price,
                }
                short[key] = nil -- in case the vendor lists it twice
            end
        end
    end
    return list
end

function FormatMoney(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    if GetMoneyString then return GetMoneyString(copper) end
    return (copper / 10000) .. "g"
end

DEFAULT_VENDOR_LIMIT = 10000 -- 1 gold, in copper

function GetVendorLimit()
    return tonumber(settings.vendorLimit) or DEFAULT_VENDOR_LIMIT
end

-- "2g 50s", "75s", "1.5g", "30c" or a bare number of gold -> copper.
function ParseMoney(text)
    text = string.lower(Trim(text or ""))
    if text == "" then return nil end
    if text:match("^%d+%.?%d*$") then return math.floor(tonumber(text) * 10000 + 0.5) end
    local total, matched = 0, false
    for amount, unit in text:gmatch("(%d+%.?%d*)%s*([gsc])") do
        local value = tonumber(amount)
        total = total + value * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        matched = true
    end
    if matched then return math.floor(total + 0.5) end
    return nil
end

-- copper -> "2g 50s" (plain text, for the settings box).
function MoneyText(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
    return table.concat(parts, " ")
end

-- Trims the shopping list to fit the per-visit limit, in list order.
-- Returns the list that fits and what was left out.
function ApplyVendorLimit(list)
    local budget = GetVendorLimit()
    local kept, skipped = {}, {}
    for _, entry in ipairs(list) do
        local pricePer = entry.cost / entry.purchases
        local affordable = math.min(entry.purchases, math.floor(budget / pricePer))
        if affordable > 0 then
            kept[#kept + 1] = {
                index = entry.index, name = entry.name, perPurchase = entry.perPurchase,
                purchases = affordable, count = affordable * entry.perPurchase,
                cost = affordable * pricePer,
            }
            budget = budget - affordable * pricePer
        end
        if affordable < entry.purchases then
            skipped[#skipped + 1] = (entry.purchases - affordable) * entry.perPurchase .. " " .. entry.name
        end
    end
    return kept, skipped
end

function SkippedNote(skipped)
    if #skipped == 0 then return nil end
    return "Left out over your " .. MoneyText(GetVendorLimit()) .. " limit: "
        .. table.concat(skipped, ", ") .. " (change the limit in /bartab config)."
end

function DescribePurchases(list)
    local parts, total = {}, 0
    for _, entry in ipairs(list) do
        parts[#parts + 1] = entry.count .. " " .. entry.name
        total = total + entry.cost
    end
    return table.concat(parts, ", "), total
end

function BuyPurchases(list)
    local _, total = DescribePurchases(list)
    if GetMoney and GetMoney() < total then
        Print("Not enough money for the missing materials (" .. FormatMoney(total) .. ").")
        return
    end
    for _, entry in ipairs(list) do
        if entry.perPurchase == 1 then
            -- Single items: buy in chunks of at most one stack per call.
            local left = entry.count
            local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(entry.index)) or 20
            maxStack = math.max(1, maxStack)
            while left > 0 do
                local amount = math.min(left, maxStack)
                BuyMerchantItem(entry.index, amount)
                left = left - amount
            end
        else
            -- Sold in bundles: one bundle per call.
            for _ = 1, entry.purchases do
                BuyMerchantItem(entry.index)
            end
        end
    end
    local text = DescribePurchases(list)
    Print("Bought " .. text .. " for " .. FormatMoney(total) .. ".")
end

function OnMerchantShow()
    local mode = settings.vendorBuy or "ask"
    if mode == "off" then return end
    local wanted = FindVendorPurchases()
    if #wanted == 0 then return end
    local list, skipped = ApplyVendorLimit(wanted)
    local note = SkippedNote(skipped)
    if #list == 0 then
        Print("This vendor sells materials your bars need, but even one is over your "
            .. MoneyText(GetVendorLimit()) .. " limit (change it in /bartab config).")
        return
    end
    if mode == "auto" or not (StaticPopupDialogs and StaticPopup_Show) then
        BuyPurchases(list)
        if note then Print(note) end
        return
    end
    StaticPopupDialogs.BARTAB_VENDOR_BUY = StaticPopupDialogs.BARTAB_VENDOR_BUY or {
        text = "BarTab: this vendor sells materials your bars need.\n\n%s\n\nBuy them for %s?",
        button1 = "Buy",
        button2 = NO or "No",
        OnAccept = function(_, data) BuyPurchases(data) end,
        timeout = 0,
        whileDead = false,
        hideOnEscape = true,
    }
    local text, total = DescribePurchases(list)
    if note then
        text = text .. "\n|cffff8040" .. note .. "|r"
    end
    StaticPopup_Show("BARTAB_VENDOR_BUY", text, FormatMoney(total), list)
end

vendorWatcher = CreateFrame("Frame")
pcall(vendorWatcher.RegisterEvent, vendorWatcher, "MERCHANT_SHOW")
pcall(vendorWatcher.RegisterEvent, vendorWatcher, "MERCHANT_CLOSED")
vendorWatcher:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_CLOSED" then
        if StaticPopup_Hide then StaticPopup_Hide("BARTAB_VENDOR_BUY") end
        return
    end
    -- The vendor's list can take a moment to fill in.
    C_Timer.After(0.3, function()
        if MerchantFrame and MerchantFrame.IsShown and not MerchantFrame:IsShown() then return end
        pcall(RecordVendorPrices)
        pcall(OnMerchantShow)
    end)
end)

-- Bank materials -----------------------------------------------------------------
-- At the bank, offers to take out (or just takes out) what your Crafting bars
-- are short of in your bags, the same list the vendor prompt works from.
-- settings.bankWithdraw: "ask" (default), "auto" or "off". /bartab bank asks
-- again while the bank is open.
BANK_MODES = {
    { key = "ask", name = "Ask before taking out materials" },
    { key = "auto", name = "Take out materials automatically" },
    { key = "off", name = "Off (take them out by hand)" },
}
bankJob = nil
bankWindowOpen = false

function ContainerSlots(bag)
    local get = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
    if not get then return 0 end
    local ok, slots = pcall(get, bag)
    return ok and tonumber(slots) or 0
end

-- itemID, count, locked of a bag slot (nil when empty).
function ContainerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" and info.itemID then
            return info.itemID, info.stackCount or 1, info.isLocked
        end
        return nil
    end
    if _G.GetContainerItemInfo then
        local _, count, locked, _, _, _, _, _, _, itemID = _G.GetContainerItemInfo(bag, slot)
        if itemID then return itemID, count or 1, locked end
    end
end

-- The bank's containers: the bank itself and its bags (not your own bags).
function BankContainers()
    local list, seen = {}, {}
    local function Add(bag)
        if bag and not seen[bag] then
            seen[bag] = true
            list[#list + 1] = bag
        end
    end
    local index = Enum and Enum.BagIndex
    Add((index and index.Bank) or BANK_CONTAINER or -1)
    if index then
        for n = 1, 7 do Add(index["BankBag_" .. n]) end
        for n = 1, 6 do Add(index["CharacterBankTab_" .. n]) end
    end
    local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do Add(bag) end
    return list
end

-- An empty slot in your own bags, not one already used this run.
function FreeBagSlot(reserved)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, ContainerSlots(bag) do
            if not reserved[bag .. ":" .. slot] and not ContainerItem(bag, slot) then
                return bag, slot
            end
        end
    end
end

-- { { name=, itemID=, count= }, ... }: what the bank holds of what you're short.
function FindBankWithdrawals()
    local short, names, ids = GetShortages(false)
    if not next(short) then return {} end
    local inBank, idFor = {}, {}
    for _, bag in ipairs(BankContainers()) do
        for slot = 1, ContainerSlots(bag) do
            local itemID, count = ContainerItem(bag, slot)
            if itemID then
                local key = ids[itemID]
                if not key then
                    local name = GetItemNameByID(itemID)
                    key = name and string.lower(name)
                end
                if key and short[key] then
                    inBank[key] = (inBank[key] or 0) + count
                    idFor[key] = itemID
                end
            end
        end
    end
    local list = {}
    for key, need in pairs(short) do
        if inBank[key] then
            list[#list + 1] = { name = names[key] or key, itemID = idFor[key], count = math.min(need, inBank[key]) }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function DescribeWithdrawals(list, field)
    local parts = {}
    for _, entry in ipairs(list) do
        local count = entry[field or "count"]
        if count and count > 0 then parts[#parts + 1] = count .. " " .. entry.name end
    end
    return parts
end

-- Moves the list into your bags, one stack at a time (each move locks the
-- slots for a moment): a whole stack if you need all of it, else split off
-- just what you need into an empty bag slot.
function TakeOutMaterials(list)
    if bankJob then return end
    for _, entry in ipairs(list) do entry.left, entry.got = entry.count, 0 end
    bankJob = { list = list, index = 1, reserved = {}, waits = 0 }
    BankStep()
end

function FinishBankJob(problem)
    local job = bankJob
    bankJob = nil
    if not job then return end
    local parts = DescribeWithdrawals(job.list, "got")
    if #parts > 0 then Print("Took out " .. JoinNames(parts, 6) .. ".") end
    if problem then Print(problem) end
    RequestUpdate(0.5)
end

function BankStep()
    local job = bankJob
    if not job then return end
    if not bankWindowOpen then
        FinishBankJob("The bank closed before BarTab finished.")
        return
    end
    local entry = job.list[job.index]
    while entry and entry.left <= 0 do
        job.index = job.index + 1
        entry = job.list[job.index]
    end
    if not entry then
        FinishBankJob()
        return
    end
    -- A stack of it in the bank that isn't mid-move.
    local fromBag, fromSlot, stack, busy
    for _, bag in ipairs(BankContainers()) do
        for slot = 1, ContainerSlots(bag) do
            local itemID, count, locked = ContainerItem(bag, slot)
            if itemID == entry.itemID then
                if locked then
                    busy = true
                elseif not fromBag then
                    fromBag, fromSlot, stack = bag, slot, count
                end
            end
        end
        if fromBag then break end
    end
    if not fromBag then
        if busy and job.waits < 20 then
            job.waits = job.waits + 1
        else
            entry.left = 0 -- none left in the bank
        end
        C_Timer.After(0.2, BankStep)
        return
    end
    job.waits = 0
    local toBag, toSlot = FreeBagSlot(job.reserved)
    if not toBag then
        FinishBankJob("Your bags are full; BarTab took out what fit.")
        return
    end
    job.reserved[toBag .. ":" .. toSlot] = true
    if CursorHasItem and CursorHasItem() then
        FinishBankJob("Put down what's on your cursor, then type /bartab bank to finish.")
        return
    end
    local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
    local split = (C_Container and C_Container.SplitContainerItem) or _G.SplitContainerItem
    if stack <= entry.left then
        pickup(fromBag, fromSlot)
        pickup(toBag, toSlot)
        entry.left, entry.got = entry.left - stack, entry.got + stack
    else
        split(fromBag, fromSlot, entry.left)
        pickup(toBag, toSlot)
        entry.got, entry.left = entry.got + entry.left, 0
    end
    if CursorHasItem and CursorHasItem() and ClearCursor then ClearCursor() end
    C_Timer.After(0.25, BankStep)
end

-- force: /bartab bank (asks even with the setting off).
function OfferBankWithdrawals(force)
    local mode = settings.bankWithdraw or "ask"
    if mode == "off" and not force then return end
    if bankJob then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local list = FindBankWithdrawals()
    if #list == 0 then
        if force then Print("Your bank has nothing your bars are short of.") end
        return
    end
    if mode == "auto" and not force or not (StaticPopupDialogs and StaticPopup_Show) then
        TakeOutMaterials(list)
        return
    end
    StaticPopupDialogs.BARTAB_BANK_TAKE = StaticPopupDialogs.BARTAB_BANK_TAKE or {
        text = "BarTab: your bank has materials your bars need.\n\n%s\n\nTake them out?",
        button1 = "Take out",
        button2 = NO or "No",
        OnAccept = function(_, data) TakeOutMaterials(data) end,
        timeout = 0,
        whileDead = false,
        hideOnEscape = true,
    }
    StaticPopup_Show("BARTAB_BANK_TAKE", table.concat(DescribeWithdrawals(list), "\n"), nil, list)
end

bankWatcher = CreateFrame("Frame")
pcall(bankWatcher.RegisterEvent, bankWatcher, "BANKFRAME_OPENED")
pcall(bankWatcher.RegisterEvent, bankWatcher, "BANKFRAME_CLOSED")
bankWatcher:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_CLOSED" then
        bankWindowOpen = false
        if StaticPopup_Hide then StaticPopup_Hide("BARTAB_BANK_TAKE") end
        return
    end
    bankWindowOpen = true
    -- The bank's contents can take a moment to arrive.
    C_Timer.After(0.4, function()
        if bankWindowOpen then Safe("bank", OfferBankWithdrawals)() end
    end)
end)

-- Send to your other characters ---------------------------------------------------
-- At a mailbox, BarTab offers to mail your other characters (same realm and
-- faction) what their bars are short of and you have spare: ore for the
-- blacksmith, leather for the leatherworker. Their needs come from their bars
-- and their last saved bags and bank; "spare" is what's left after your own
-- bars' goals. settings.mailSend: "ask" (default) or "off". /bartab mail
-- asks again while the mailbox is open. Sent items are remembered until that
-- character next logs in, so they aren't offered twice.
MAIL_MODES = {
    { key = "ask", name = "Offer to mail my other characters what they need" },
    { key = "off", name = "Off (mail by hand)" },
}
MAIL_ATTACHMENTS = ATTACHMENTS_MAX_SEND or 12
mailJob = nil
mailboxOpen = false

-- item ID -> total of the goals of a bar list's active, non-crate bars.
function BarNeeds(list)
    local needs, names = {}, {}
    for _, item in pairs(list or {}) do
        if not item.container and not item.inactive and not item.altNeed and item.goal and item.goal > 0 then
            local id = ItemIDFor(item)
            if id then
                needs[id] = (needs[id] or 0) + item.goal
                names[id] = item.name
            end
        end
    end
    return needs, names
end

-- What your other characters' bars are short of (same realm and faction):
-- { { to = "[Alt]", character = key, itemID, name, short }, ... }, from
-- their bars and last saved bags and bank, less what you've mailed them.
function AltShortfalls()
    local me = CharacterKey()
    local myRealm = me:match("%-(.*)$")
    local myFaction = UnitFactionGroup and UnitFactionGroup("player")
    settings.mailed = settings.mailed or {}
    local list = {}
    local characters = (BarTabDB and BarTabDB.characters) or {}
    local keys = {}
    for key in pairs(characters) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local realm = key:match("%-(.*)$")
        local snapshot = settings.inventory and settings.inventory[key]
        if key ~= me and realm == myRealm and snapshot
            and not (snapshot.faction and myFaction and snapshot.faction ~= myFaction) then
            -- Mail sent since they last logged in still counts as theirs.
            local mailed = settings.mailed[key]
            if mailed and snapshot.updated and mailed.time and snapshot.updated > mailed.time then
                settings.mailed[key], mailed = nil, nil
            end
            local needs, names = BarNeeds(characters[key])
            for id, need in pairs(needs) do
                local have = ((snapshot.bags or {})[id] or 0) + ((snapshot.bank or {})[id] or 0)
                    + ((mailed and mailed.items[id]) or 0)
                local short = need - have
                if short > 0 then
                    list[#list + 1] = { to = CharacterName(key), character = key, itemID = id,
                        name = names[id] or GetItemNameByID(id) or ("item " .. id), short = short }
                end
            end
        end
    end
    return list
end

-- { { to = "[Alt]", character = key, itemID, name, count }, ... }
function FindMailSends()
    local scan = ScanBags()
    -- What's spare here: bags less your own bars' goals.
    local myNeeds = BarNeeds(trackedItems)
    local spare = {}
    for id, count in pairs(scan.byID) do
        local left = count - (myNeeds[id] or 0)
        if left > 0 then spare[id] = left end
    end
    local sends = {}
    for _, need in ipairs(AltShortfalls()) do
        if (spare[need.itemID] or 0) > 0 then
            local count = math.min(need.short, spare[need.itemID])
            spare[need.itemID] = spare[need.itemID] - count
            sends[#sends + 1] = { to = need.to, character = need.character, itemID = need.itemID,
                name = need.name, count = count }
        end
    end
    table.sort(sends, function(a, b)
        if a.to ~= b.to then return a.to < b.to end
        return a.name < b.name
    end)
    return sends
end

function DescribeMailSends(sends)
    local lines = {}
    for _, send in ipairs(sends) do
        lines[#lines + 1] = ("%d %s to %s"):format(send.count, send.name, send.to)
    end
    return table.concat(lines, "\n")
end

-- Sending: one recipient at a time, a stack per step (each attach locks the
-- slot for a moment), up to 12 attachments a letter; BarTab fills in the
-- name and subject and you click Send; the next letter follows once the
-- game says it went.
function SendMailNow(sends)
    if mailJob then return end
    if not ClickSendMailItemButton then
        Print("Couldn't reach the mail window.")
        return
    end
    for i = 1, MAIL_ATTACHMENTS do
        if GetSendMailItem and GetSendMailItem(i) then
            Print("Clear the items already attached to your letter first, then type /bartab mail.")
            return
        end
    end
    if MailFrameTab2 and MailFrameTab2.Click and not (SendMailFrame and SendMailFrame:IsShown()) then
        MailFrameTab2:Click()
    end
    -- Letters: per recipient, items in order.
    local letters, byTo = {}, {}
    for _, send in ipairs(sends) do
        send.left = send.count
        if not byTo[send.to] then
            byTo[send.to] = { to = send.to, character = send.character, items = {} }
            letters[#letters + 1] = byTo[send.to]
        end
        table.insert(byTo[send.to].items, send)
    end
    mailJob = { letters = letters, index = 1, attached = 0, sent = {}, waits = 0 }
    C_Timer.After(0.2, MailStep)
end

function FinishMailJob(problem)
    local job = mailJob
    mailJob = nil
    if not job then return end
    if #job.sent > 0 then Print("Mailed " .. JoinNames(job.sent, 8) .. ".") end
    if problem then Print(problem) end
end

function MailStep()
    local job = mailJob
    if not job then return end
    if not mailboxOpen then
        FinishMailJob("The mailbox closed before BarTab finished.")
        return
    end
    if job.waitingSend then return end -- MAIL_SEND_SUCCESS / MAIL_FAILED moves on
    local letter = job.letters[job.index]
    if not letter then
        FinishMailJob()
        return
    end
    -- The next item that still needs attaching.
    local send
    for _, item in ipairs(letter.items) do
        if item.left > 0 then send = item break end
    end
    if send and job.attached < MAIL_ATTACHMENTS then
        if CursorHasItem and CursorHasItem() then
            FinishMailJob("Put down what's on your cursor, then type /bartab mail.")
            return
        end
        -- A stack of it in your bags that isn't mid-move.
        local fromBag, fromSlot, stack, busy
        for bag = 0, NUM_BAG_SLOTS or 4 do
            for slot = 1, ContainerSlots(bag) do
                local itemID, count, locked = ContainerItem(bag, slot)
                if itemID == send.itemID then
                    if locked then busy = true
                    elseif not fromBag then fromBag, fromSlot, stack = bag, slot, count end
                end
            end
            if fromBag then break end
        end
        if not fromBag then
            if busy and job.waits < 20 then
                job.waits = job.waits + 1
            else
                send.left = 0 -- none left to send
            end
            C_Timer.After(0.2, MailStep)
            return
        end
        job.waits = 0
        local pickup = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
        local split = (C_Container and C_Container.SplitContainerItem) or _G.SplitContainerItem
        local amount = math.min(stack, send.left)
        if amount < stack then split(fromBag, fromSlot, amount) else pickup(fromBag, fromSlot) end
        job.attached = job.attached + 1
        ClickSendMailItemButton(job.attached)
        if CursorHasItem and CursorHasItem() and ClearCursor then ClearCursor() end
        send.left = send.left - amount
        send.sentNow = (send.sentNow or 0) + amount
        C_Timer.After(0.3, MailStep)
        return
    end
    if job.attached == 0 then
        -- Nothing could be attached for this one: next recipient.
        job.index = job.index + 1
        C_Timer.After(0.1, MailStep)
        return
    end
    -- Postage.
    local price = GetSendMailPrice and GetSendMailPrice() or 0
    if GetMoney and GetMoney() < price then
        FinishMailJob("Not enough money for the postage (" .. MoneyText(price) .. "); the items are still attached.")
        return
    end
    job.waitingSend = true
    job.letter = letter
    -- Fill in the letter and let you click Send (the game only sends mail
    -- from your own click); the next letter follows once it's gone.
    local nameBox = _G.SendMailNameEditBox or (SendMailFrame and SendMailFrame.SendMailNameEditBox)
    local subjectBox = _G.SendMailSubjectEditBox or (SendMailFrame and SendMailFrame.SendMailSubjectEditBox)
    local bodyBox = _G.SendMailBodyEditBox or (SendMailFrame and SendMailFrame.SendMailBodyEditBox)
    -- WoW Forever names have a surname ("[Alt] [Surname]"); address the full
    -- name when BarTab has seen it, so it can't reach someone else's [Alt].
    -- If the game turns that down, the first name is tried next.
    local snapshot = settings.inventory and settings.inventory[letter.character]
    local fullName = snapshot and snapshot.fullName
    letter.address = letter.address or ((fullName and fullName ~= letter.to) and fullName or letter.to)
    if nameBox and nameBox.SetText then nameBox:SetText(letter.address) end
    if subjectBox and subjectBox.SetText then subjectBox:SetText("BarTab: materials") end
    if bodyBox and bodyBox.SetText then bodyBox:SetText("Sent by BarTab for your bars.") end
    if SendMailFrame_Update then pcall(SendMailFrame_Update) end
    local left = #job.letters - job.index
    Print(("Letter to %s is ready: click Send%s."):format(letter.address,
        left > 0 and (" (" .. left .. " more to follow)") or ""))
end

function OnMailSent(success)
    local job = mailJob
    if not (job and job.waitingSend) then return end
    job.waitingSend = false
    local letter = job.letter
    if not success then
        -- Full name refused: try the first name once, on the same letter.
        if letter.address ~= letter.to then
            letter.address = letter.to
            job.waitingSend = true
            local nameBox = _G.SendMailNameEditBox or (SendMailFrame and SendMailFrame.SendMailNameEditBox)
            if nameBox and nameBox.SetText then nameBox:SetText(letter.to) end
            Print("The game didn't take the full name; trying " .. letter.to .. ". Click Send again.")
            return
        end
        FinishMailJob("Couldn't mail " .. letter.to .. " (the game said no). The items are still attached.")
        return
    end
    settings.mailed = settings.mailed or {}
    local mailed = settings.mailed[letter.character] or { items = {} }
    mailed.time = time and time() or 0
    for _, item in ipairs(letter.items) do
        if item.sentNow and item.sentNow > 0 then
            mailed.items[item.itemID] = (mailed.items[item.itemID] or 0) + item.sentNow
            job.sent[#job.sent + 1] = item.sentNow .. " " .. item.name .. " to " .. letter.to
            item.sentNow = 0
        end
    end
    settings.mailed[letter.character] = mailed
    Safe("alt shopping", SyncAltNeedBars)()
    job.attached = 0
    -- More of this letter's items (over 12 stacks)? Another letter to them.
    local more = false
    for _, item in ipairs(letter.items) do if item.left > 0 then more = true end end
    if not more then job.index = job.index + 1 end
    C_Timer.After(0.5, MailStep)
end

-- Shopping for your other characters ----------------------------------------------
-- With settings.altShopping, the Crafting section gets a "For your other
-- characters" subsection: a bar per material their bars are short of
-- ("Copper Ore for [Alt]"), counting what you carry (your own bars claim
-- it first). These bars are made fresh each session and never saved: they're
-- taken out at logout. settings.altShopHidden[key] hides one.
function AltNeedKey(character, itemID)
    return "altneed:" .. character .. ":" .. itemID
end

-- Whether this character can get the item for someone else: gather it
-- with one of its skills, make it with one of its recipes, or already has
-- some (bags or bank). Not things only another character can get.
function CanGetForAlt(itemID, itemName)
    if CountWhere(itemID, true, false) > 0 then return true end
    local mine = settings.producers and settings.producers[CharacterKey()]
    if mine and mine[itemID] then return true end
    local ok, skill = pcall(CanGather, itemID, itemName, GatherSkills())
    return ok and skill and true or false
end

function SyncAltNeedBars()
    local wanted = {}
    if settings.altShopping then
        settings.altShopHidden = settings.altShopHidden or {}
        for _, need in ipairs(AltShortfalls()) do
            local key = AltNeedKey(need.character, need.itemID)
            if not settings.altShopHidden[key] and CanGetForAlt(need.itemID, need.name) then
                wanted[key] = need
            end
        end
    end
    local changed = false
    for key, item in pairs(trackedItems) do
        if item.altNeed and not wanted[key] then
            trackedItems[key] = nil
            changed = true
        end
    end
    local order = 100000
    for key, need in pairs(wanted) do
        local item = trackedItems[key]
        if not item then
            item = { altNeed = true, start = 0 }
            trackedItems[key] = item
            changed = true
        end
        if item.goal ~= need.short then changed = true end
        item.name, item.itemID, item.goal = need.name, need.itemID, need.short
        item.altName, item.altCharacter = need.to, need.character
        item.label = need.name .. " for " .. need.to
        order = order + 1
        item.order = item.order and item.order >= 100000 and item.order or order
    end
    if changed then UpdateBars() end
end

-- At login: one line about what you're already carrying for your other
-- characters (a bar that starts out full gets no goal alert).
function AnnounceAltNeeds()
    if not settings.altShopping then return end
    local ready, partly = {}, {}
    for _, item in pairs(trackedItems) do
        if item.altNeed then
            local count = math.min(GetBarCount(item), item.goal)
            if count >= item.goal then
                ready[#ready + 1] = item.goal .. " " .. item.name .. " for " .. item.altName
            elseif count > 0 then
                partly[#partly + 1] = count .. "/" .. item.goal .. " " .. item.name .. " for " .. item.altName
            end
        end
    end
    table.sort(ready)
    table.sort(partly)
    if #ready > 0 then
        Print("You're carrying " .. JoinNames(ready, 5) .. ". Mail it at a mailbox.")
    end
    if #partly > 0 then
        Print("Partway: " .. JoinNames(partly, 5) .. ".")
    end
end

-- Never saved: out at logout (and at login, in case a session ended badly).
function RemoveAltNeedBars()
    for key, item in pairs(trackedItems) do
        if item.altNeed then trackedItems[key] = nil end
    end
end

altShopWatcher = CreateFrame("Frame")
pcall(altShopWatcher.RegisterEvent, altShopWatcher, "PLAYER_LOGOUT")
pcall(altShopWatcher.RegisterEvent, altShopWatcher, "PLAYER_LOGIN")
pcall(altShopWatcher.RegisterEvent, altShopWatcher, "BAG_UPDATE_DELAYED")
altShopSyncPending = false
altShopWatcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        pcall(RemoveAltNeedBars)
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Picking up something an alt needs can add its bar.
        if not settings or not settings.altShopping or altShopSyncPending then return end
        altShopSyncPending = true
        C_Timer.After(2, function()
            altShopSyncPending = false
            Safe("alt shopping", SyncAltNeedBars)()
        end)
    else
        C_Timer.After(4, function()
            pcall(RemoveAltNeedBars)
            Safe("alt shopping", SyncAltNeedBars)()
            Safe("alt shopping", AnnounceAltNeeds)()
        end)
    end
end)

-- force: /bartab mail (asks even with the setting off).
function OfferMailSends(force)
    if (settings.mailSend or "ask") == "off" and not force then return end
    if mailJob or (InCombatLockdown and InCombatLockdown()) then return end
    local sends = FindMailSends()
    if #sends == 0 then
        if force then Print("Nothing your other characters' bars need that you have spare.") end
        return
    end
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    StaticPopupDialogs.BARTAB_MAIL_SEND = StaticPopupDialogs.BARTAB_MAIL_SEND or {
        text = "BarTab: your other characters' bars need things you have spare.\n\n%s\n\nMail them?",
        button1 = "Mail",
        button2 = NO or "No",
        OnAccept = function(_, data) SendMailNow(data) end,
        timeout = 0,
        whileDead = false,
        hideOnEscape = true,
    }
    StaticPopup_Show("BARTAB_MAIL_SEND", DescribeMailSends(sends), nil, sends)
end

mailWatcher = CreateFrame("Frame")
for _, mailEvent in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }) do
    pcall(mailWatcher.RegisterEvent, mailWatcher, mailEvent)
end
mailWatcher:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        mailboxOpen = true
        C_Timer.After(0.5, function()
            if mailboxOpen then Safe("mail", OfferMailSends)() end
        end)
    elseif event == "MAIL_CLOSED" then
        mailboxOpen = false
        if StaticPopup_Hide then StaticPopup_Hide("BARTAB_MAIL_SEND") end
    elseif event == "MAIL_SEND_SUCCESS" then
        Safe("mail", OnMailSent)(true)
    elseif event == "MAIL_FAILED" then
        Safe("mail", OnMailSent)(false)
    end
end)

-- What crafts are worth at a vendor (/bartab profit) ---------------------------
-- For each recipe the open profession knows: what the item sells to a vendor
-- for, less what its ingredients cost. Two lists: using materials you have
-- (only vendor-bought ingredients such as thread cost anything), and buying
-- the rest at auction prices (from an auction addon, if you have one).

-- Vendor prices (copper per item) of things vendors sell for gold, noted as
-- you visit them: settings.vendorPrices[itemID].
function RecordVendorPrices()
    if not GetMerchantNumItems then return end
    settings.vendorPrices = settings.vendorPrices or {}
    for index = 1, GetMerchantNumItems() do
        local _, price, quantity, numAvailable, goldOnly = GetMerchantSlot(index)
        local itemID = GetMerchantSlotID(index)
        -- Unlimited stock only: limited items aren't a steady source.
        if itemID and goldOnly and price and price > 0 and numAvailable == -1 then
            settings.vendorPrices[itemID] = price / math.max(1, quantity or 1)
        end
    end
end

function AuctionAddonAPI()
    local addon = _G.Auctionator
    return addon and addon.API and addon.API.v1
end

-- What a vendor charges for the item (copper each), if known.
function VendorBuyPrice(itemID)
    local seen = settings.vendorPrices and settings.vendorPrices[itemID]
    if seen then return seen end
    local api = AuctionAddonAPI()
    if api and api.GetVendorPriceByItemID then
        local ok, price = pcall(api.GetVendorPriceByItemID, "BarTab", itemID)
        if ok and tonumber(price) and tonumber(price) > 0 then return tonumber(price) end
    end
end

-- Auction price (copper each), if an auction addon has one.
function AuctionPrice(itemID)
    local api = AuctionAddonAPI()
    if api and api.GetAuctionPriceByItemID then
        local ok, price = pcall(api.GetAuctionPriceByItemID, "BarTab", itemID)
        if ok and tonumber(price) and tonumber(price) > 0 then return tonumber(price) end
    end
end

-- How many days ago your auction addon last saw the item listed (0: today),
-- or nil if it can't say.
function AuctionAge(itemID)
    local api = AuctionAddonAPI()
    if api and api.GetAuctionAgeByItemID then
        local ok, days = pcall(api.GetAuctionAgeByItemID, "BarTab", itemID)
        if ok and tonumber(days) then return tonumber(days) end
    end
end

-- What a vendor pays for the item: copper, 0 if it can't be sold, or nil
-- while the item's data is still loading.
function VendorSellPrice(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return 0 end
    local results = { pcall(getInfo, itemID) }
    if not results[1] or results[2] == nil then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
        return nil
    end
    return tonumber(results[12]) or 0
end

-- The cheapest way to get one of an item, in copper: from a vendor, at the
-- auction house, or made with a recipe BarTab has seen this character know
-- (its ingredients priced the same way, several steps deep: ore to bar to
-- part). Returns the cost and whether making it was cheapest, or nil if it
-- can't be priced. state.memo remembers answers for one /bartab profit;
-- state.visiting stops chains that loop back (essences that convert both
-- ways).
PROFIT_MAX_DEPTH = 5

function BestCost(itemID, itemName, state, depth)
    local key = itemID or itemName
    if not key then return nil end
    local known = state.memo[key]
    if known ~= nil then
        if known then return known.cost, known.made, known.from end
        return nil
    end
    if state.visiting[key] then return nil end
    local vendor = itemID and VendorBuyPrice(itemID)
    if vendor then
        state.memo[key] = { cost = vendor, made = false }
        return vendor, false
    end
    -- The profit window can count what you gather yourself as free.
    if state.gathered and state.gathered(itemID, itemName) then
        state.memo[key] = { cost = 0, made = false }
        return 0, false
    end
    local best, made, from = itemID and AuctionPrice(itemID), false, nil
    if depth <= PROFIT_MAX_DEPTH then
        local mine = settings.producers and settings.producers[CharacterKey()]
        local producer = (mine and itemID and mine[itemID]) or FindProducer(itemName)
        local reagents = producer and producer.recipeID and GetRecipeReagents(producer.recipeID)
        if reagents and #reagents > 0 then
            state.visiting[key] = true
            local total, names = 0, {}
            for _, reagent in ipairs(reagents) do
                local each = BestCost(reagent.itemID, reagent.name, state, depth + 1)
                if not each then total = nil break end
                total = total + each * reagent.need
                names[#names + 1] = reagent.name
            end
            state.visiting[key] = nil
            if total then
                local each = total / math.max(1, producer.qty or 1)
                if not best or each < best then
                    best, made, from = each, true, table.concat(names, " and ")
                end
            end
        end
    end
    state.memo[key] = best and { cost = best, made = made, from = from } or false
    return best, made, from
end

-- One recipe's numbers, "loading", or nil if what it makes can't be vendored.
function RecipeProfit(recipeID, state)
    state = state or { memo = {}, visiting = {} }
    local outputID, made = GetRecipeOutput(recipeID)
    if not outputID then return nil end
    local sell = VendorSellPrice(outputID)
    if sell == nil then return "loading" end
    if sell <= 0 then return nil end
    local income = sell * (made or 1)
    local vendorCost, gatheredCost, unpriced, made = 0, 0, nil, {}
    -- This recipe's own item never counts as one of its ingredients' sources.
    state.visiting[outputID] = true
    for _, reagent in ipairs(GetRecipeReagents(recipeID) or {}) do
        local each = VendorBuyPrice(reagent.itemID)
        if each then
            vendorCost = vendorCost + each * reagent.need
        else
            -- Something you can make (a bar from ore, Thick Leather from
            -- Heavy Leather): whichever is cheaper, buying it or making it.
            local cost, ownMade = BestCost(reagent.itemID, reagent.name, state, 1)
            if cost then
                gatheredCost = gatheredCost + cost * reagent.need
                if ownMade then made[#made + 1] = reagent.name end
            else
                unpriced = unpriced or reagent.name
            end
        end
    end
    state.visiting[outputID] = nil
    return {
        name = GetRecipeName(recipeID) or GetItemNameByID(outputID) or ("recipe " .. recipeID),
        own = income - vendorCost,
        bought = (not unpriced) and (income - vendorCost - gatheredCost) or nil,
        unpriced = unpriced,
        made = #made > 0 and table.concat(made, ", ") or nil,
        seconds = CraftSeconds(recipeID),
    }
end

function SignedMoney(copper)
    copper = math.floor(copper + 0.5)
    if copper < 0 then return "-" .. FormatMoney(-copper) end
    return FormatMoney(copper)
end

function ShowProfitList()
    local profession = LoadedProfession()
    if not profession or not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then
        Print("Open the profession window first; BarTab checks the recipes of the profession that's open.")
        return
    end
    local results, loading = {}, 0
    local state = { memo = {}, visiting = {} }
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(info) == "table" and info.learned then
            local result = RecipeProfit(recipeID, state)
            if result == "loading" then
                loading = loading + 1
            elseif result then
                results[#results + 1] = result
            end
        end
    end
    local function Line(rank, result, value, showMade)
        local perHour = ""
        if result.seconds and result.seconds > 0 and value > 0 then
            perHour = ", about " .. SignedMoney(value * 3600 / result.seconds) .. " an hour"
        end
        local made = (showMade and result.made) and (" (making your own " .. result.made .. ")") or ""
        Print(("  %d. %s: %s a craft%s%s"):format(rank, result.name, SignedMoney(value), perHour, made))
    end
    local SHOWN = 8

    table.sort(results, function(a, b) return a.own > b.own end)
    Print(profession .. ", sold to a vendor, using materials you have (vendor items like thread at their price):")
    local shown = 0
    for _, result in ipairs(results) do
        if result.own <= 0 or shown >= SHOWN then break end
        shown = shown + 1
        Line(shown, result, result.own)
    end
    if shown == 0 then Print("  Nothing earns more at a vendor than its vendor-bought materials cost.") end

    local bought = {}
    for _, result in ipairs(results) do
        if result.bought then bought[#bought + 1] = result end
    end
    table.sort(bought, function(a, b) return a.bought > b.bought end)
    Print("Buying the other materials at auction prices (or their ingredients, where making them yourself is cheaper):")
    if #bought == 0 then
        Print("  No auction prices for these materials. Scan the auction house with your auction addon first.")
    else
        for rank = 1, math.min(SHOWN, #bought) do Line(rank, bought[rank], bought[rank].bought, true) end
        if bought[1].bought <= 0 then Print("  None of them make money this way.") end
        local skipped = #results - #bought
        if skipped > 0 then
            Print(("  (%d %s left out: no auction price for an ingredient.)"):format(skipped,
                skipped == 1 and "recipe" or "recipes"))
        end
    end
    if loading > 0 then
        Print(("%d %s still loading; type /bartab profit again in a moment for the full list."):format(loading,
            loading == 1 and "item was" or "items were"))
    end
    Print("Vendor items are priced once BarTab (or your auction addon) has seen them at a vendor.")
end


-- Craft the next ready bar (key binding and /bartab craft) -----------------------
-- The first active recipe bar, in list order, that can craft now (counting
-- only its share of a shared material), crafted as a plain click would.

function BarCraftable(item)
    local craftable = GetCraftableCount(item.recipeID)
    if not craftable then return 0 end
    local count = GetBarCount(item)
    if count < CountItem(item) then
        local perCraft = GetReagentQuantity(item.recipeID, item.name)
        if perCraft and perCraft > 0 then
            craftable = math.min(craftable, math.floor(count / perCraft))
        end
    end
    return craftable
end

function CraftNextReady()
    for _, key in ipairs(GetSortedKeys()) do
        local item = trackedItems[key]
        if item.recipeID and not item.container and not item.inactive
            and IsShown(item) and BarCraftable(item) >= 1 then
            CraftItem(key, GetClickAction("click"))
            return true
        end
    end
    Print("Nothing is ready to craft.")
    return false
end

_G.BINDING_HEADER_BARTAB = "BarTab"
-- Shown in Key Bindings > AddOns, where the header isn't, so it names BarTab.
_G.BINDING_NAME_BARTAB_CRAFT_NEXT = "BarTab: Craft the next ready bar"
_G.BarTab_CraftNext = function() CraftNextReady() end


-- Auction house shopping list ----------------------------------------------------
-- A BarTab tab on the right edge of the auction house (beside All The
-- Things' tab, sharing its tab strip) opens a panel listing what your bars
-- are short of, each with a Search button that runs the auction house's own
-- search. settings.auctionList (on by default); settings.auctionPanelOpen
-- remembers whether it was open.

function AuctionHouseOpen()
    local frame = AuctionHouseFrame or AuctionFrame
    return frame and frame.IsShown and frame:IsShown() and true or false
end

function SearchAuctionHouse(name)
    local frame = AuctionHouseFrame
    if frame and frame.SearchBar and frame.SearchBar.SearchBox and frame.SearchBar.StartSearch then
        -- Make sure the Buy tab is showing.
        if frame.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
            pcall(frame.SetDisplayMode, frame, AuctionHouseFrameDisplayMode.Buy)
        end
        frame.SearchBar.SearchBox:SetText(name)
        frame.SearchBar:StartSearch()
    elseif BrowseName and AuctionFrameBrowse_Search then
        BrowseName:SetText(name)
        AuctionFrameBrowse_Search()
    else
        Print("Couldn't reach the auction house search.")
    end
end

-- { {name=, count=}, ... } sorted by name.
function GetShoppingList()
    local short, names = GetShortages(true)
    local list = {}
    for key, count in pairs(short) do
        list[#list + 1] = { name = names[key] or key, count = count }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

AUCTION_ROWS = 24
AUCTION_PANEL_WIDTH = 270

function CreateAuctionPanel(parent)
    local ok, frame = pcall(CreateFrame, "Frame", "BarTabAuctionPanel", parent, "BackdropTemplate")
    if not ok or not frame then frame = CreateFrame("Frame", "BarTabAuctionPanel", parent) end
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    end
    -- A solid fill too: the tooltip background alone lets nameplates show through.
    frame.fill = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.fill:SetPoint("TOPLEFT", 3, -3)
    frame.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.fill:SetColorTexture(0.06, 0.06, 0.055, 0.97)
    frame:SetWidth(AUCTION_PANEL_WIDTH)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetText("BarTab shopping list")

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.empty:SetPoint("TOPLEFT", 12, -34)
    frame.empty:SetPoint("RIGHT", -12, 0)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetText("Your bars aren't short of anything.")

    frame.more = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.more:SetJustifyH("LEFT")

    frame.rows = {}
    for i = 1, AUCTION_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(AUCTION_PANEL_WIDTH - 24, 20)
        row:SetPoint("TOPLEFT", 12, -32 - (i - 1) * 22)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetPoint("RIGHT", -70, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.button:SetSize(64, 20)
        row.button:SetPoint("RIGHT", 0, 0)
        row.button:SetText(SEARCH or "Search")
        row.button:SetScript("OnClick", function(self)
            if self.itemName then SearchAuctionHouse(self.itemName) end
        end)
        frame.rows[i] = row
    end
    frame:Hide()
    return frame
end

function UpdateAuctionPanel()
    local frame = auctionPanel
    if not (frame and frame:IsShown()) then return end
    -- As many rows as fit the auction house's height.
    local fit = math.max(1, math.floor(((frame:GetHeight() or 400) - 60) / 22))
    local limit = math.min(AUCTION_ROWS, fit)
    local list = GetShoppingList()
    for i, row in ipairs(frame.rows) do
        local entry = i <= limit and list[i]
        if entry then
            row.label:SetText(entry.count .. "  " .. entry.name)
            row.button.itemName = entry.name
            row:Show()
        else
            row:Hide()
        end
    end
    frame.empty:SetShown(#list == 0)
    if #list > limit then
        frame.more:ClearAllPoints()
        frame.more:SetPoint("TOPLEFT", 12, -32 - limit * 22)
        frame.more:SetText("and " .. (#list - limit) .. " more")
        frame.more:Show()
    else
        frame.more:Hide()
    end
end

-- The tab strip on the auction house's right edge, shared with other addons
-- (All The Things makes the same one if it gets there first).
function GetAuctionSideBar()
    if not _G.AuctionHouseFrameTabSideBar then
        local bar = CreateFrame("Frame", nil, AuctionHouseFrame)
        bar:SetWidth(1)
        bar:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT")
        bar:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT")
        bar.Tabs = {}
        bar.selTab = 0
        _G.AuctionHouseFrameTabSideBar = bar
    end
    return _G.AuctionHouseFrameTabSideBar
end

function SetAuctionTabChecked(checked)
    local tab = auctionTab
    if not tab then return end
    if tab.SetChecked then pcall(tab.SetChecked, tab, checked) end
    if type(tab.Icon) == "table" then
        tab.Icon:SetTexture("Interface\\AddOns\\BarTab\\Media\\icon")
        tab.Icon:SetSize(24, 24)
    end
end

function SetAuctionPanelOpen(open)
    local bar = GetAuctionSideBar()
    local frame = auctionPanel
    bar:ClearAllPoints()
    if open then
        -- Close whichever other addon's tab is open (the way they close ours).
        for i, other in ipairs(bar.Tabs) do
            if bar.selTab == i and other ~= auctionTab then
                local handler = other:GetScript("OnMouseUp")
                if handler then pcall(handler, other) end
            end
        end
        for i, other in ipairs(bar.Tabs) do
            if other == auctionTab then bar.selTab = i end
        end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 0, 0)
        frame:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 0, 0)
        frame:Show()
        UpdateAuctionPanel()
        -- The tab strip follows the open panel's right edge.
        bar:SetPoint("TOPLEFT", frame, "TOPRIGHT")
        bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT")
    else
        frame:Hide()
        bar.selTab = 0
        bar:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT")
        bar:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT")
    end
    SetAuctionTabChecked(open)
end

function ToggleAuctionPanel()
    local open = not (auctionPanel and auctionPanel:IsShown())
    settings.auctionPanelOpen = open or nil
    SetAuctionPanelOpen(open)
end

function SetUpAuctionTab()
    if settings.auctionList == false then return end
    if not AuctionHouseFrame then return end
    if not auctionTab then
        auctionPanel = auctionPanel or CreateAuctionPanel(AuctionHouseFrame)
        local bar = GetAuctionSideBar()
        -- Blizzard's side-tab button (the one the world map's quest log uses).
        local ok, tab = pcall(CreateFrame, "Frame", "BarTabAuctionHouseTab", bar,
            "QuestLogTabButtonTemplate")
        if not ok or not tab then
            tab = CreateFrame("Button", "BarTabAuctionHouseTab", bar)
            tab:SetSize(32, 32)
            tab.Icon = tab:CreateTexture(nil, "ARTWORK")
            tab.Icon:SetPoint("CENTER")
        end
        if QuestLogDisplayMode then tab.displayMode = QuestLogDisplayMode.Quests end
        tab.tooltipText = "|cff66ccffBarTab|r shopping list"
        bar.Tabs[#bar.Tabs + 1] = tab
        -- Below the tabs already there (All The Things' sits at the top).
        local slot = #bar.Tabs
        if slot == 1 and C_AddOns and C_AddOns.IsAddOnLoaded
            and C_AddOns.IsAddOnLoaded("AllTheThings") then
            slot = 2 -- leave its spot free even if its tab isn't made yet
        end
        local height = math.max(tab:GetHeight() or 0, 40)
        tab:SetPoint("TOPLEFT", bar, "TOPRIGHT", -2, -52 - (slot - 1) * (height + 4))
        if tab.SetCustomOnMouseUpHandler then
            tab:SetCustomOnMouseUpHandler(ToggleAuctionPanel)
        else
            tab:EnableMouse(true)
            tab:SetScript("OnMouseUp", ToggleAuctionPanel)
        end
        if not tab.tooltipText or not tab.GetScript or not tab:GetScript("OnEnter") then
            tab:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("BarTab shopping list")
                GameTooltip:Show()
            end)
            tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        auctionTab = tab
        AuctionHouseFrame:HookScript("OnHide", function()
            if auctionPanel and auctionPanel:IsShown() then SetAuctionPanelOpen(false) end
        end)
    end
    auctionTab:Show()
    SetAuctionTabChecked(false)
    if settings.auctionPanelOpen then SetAuctionPanelOpen(true) end
end

auctionWatcher = CreateFrame("Frame")
for _, auctionEvent in ipairs({ "AUCTION_HOUSE_SHOW", "BAG_UPDATE_DELAYED" }) do
    pcall(auctionWatcher.RegisterEvent, auctionWatcher, auctionEvent)
end
auctionWatcher:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        -- The auction house window is built on first open; wait a moment.
        C_Timer.After(0.2, function() pcall(SetUpAuctionTab) end)
    elseif auctionPanel and auctionPanel:IsShown() then
        pcall(UpdateAuctionPanel)
    end
end)
