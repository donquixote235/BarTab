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

function ProfessionsOpen()
    return ProfessionsFrame ~= nil and ProfessionsFrame:IsShown()
end

-- Name and ID of the profession the game has loaded, if any.
function LoadedProfession()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then return nil end
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if ok and type(info) == "table" and info.professionName and info.professionName ~= "" then
        return info.professionName, info.professionID
    end
end

function GetProfessionSkillLine(item)
    if item.skillLineID then return item.skillLineID end
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

function CraftNow(item, amount)
    crafting = { id = item.recipeID, amount = amount, done = 0, last = GetTime() }
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, item.recipeID, amount)
    if not ok then
        crafting = nil
        Print("Craft failed: " .. tostring(err))
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
    if item and item.recipeID and not item.quest and not IsProfessionLoaded(item) then
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

C_Timer.NewTicker(0.5, function()
    if crafting and GetTime() - crafting.last > 20 then
        crafting = nil
    end
    if not silent.loaded then return end
    if ProfessionsOpen() then
        silent.loaded = nil -- the visible window owns it now
    elseif crafting or craftJob or IsMouseOverCraftBar() or InCombatLockdown() then
        silent.idle = nil
    else
        silent.idle = (silent.idle or 0) + 0.5
        if silent.idle >= 1.5 then
            silent.loaded, silent.idle = nil, nil
            if C_TradeSkillUI.CloseTradeSkill then
                C_TradeSkillUI.CloseTradeSkill()
            end
        end
    end
end)

-- action: what to do ("one", "fit", "max"); by default whatever this click
-- (with its modifier) is set to do.
function CraftItem(itemKey, action)
    local item = trackedItems[itemKey]

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

    -- Quest items are used through the bar's secure click overlay; a click
    -- only gets here when that overlay is off.
    if item and item.quest then
        local state, missing = GetQuestState(item)
        local progress = not state and GetItemCount(item.name) < item.goal
            and GetPieceProgress(item)
        if progress and #progress.missing > 0 then
            Print("Still need " .. progress.word .. " " .. table.concat(progress.missing, ", ") .. ".")
            return
        end
        if state == "waiting" then
            Print("Still need " .. missing .. ".")
        elseif not state then
            Print("Still collecting " .. item.name .. ".")
        elseif InCombatLockdown() then
            Print("Can't use items in combat.")
        elseif not GetQuestUseItem(item) then
            Print("All items collected; there's nothing to use for this quest.")
        else
            Print("Click the bar itself (not the name) to use the item.")
        end
        return
    end

    if not item or not item.recipeID then
        Print("No recipe assigned to this item.")
        return
    end

    -- What this click does is chosen in the settings window.
    local amount, problem = ResolveCraftAmount(item, action or GetClickAction(CurrentModifier()))
    if not amount then
        if problem then Print(problem) end
        return
    end

    -- Say what's missing rather than letting the game quietly refuse.
    local craftable = GetCraftableCount(item.recipeID)
    if craftable and craftable < 1 then
        local short = {}
        for _, reagent in ipairs(GetRecipeReagents(item.recipeID) or {}) do
            if reagent.have < reagent.need then
                short[#short + 1] = reagent.name .. " (" .. reagent.have .. "/" .. reagent.need .. ")"
            end
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

    bar:SetScript("OnEnter", function(self)
        ShowBarTooltip(self)
        PreloadProfession(trackedItems[self.itemKey])
    end)

    bar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Refresh the tooltip if Shift or Alt is pressed or released while hovering.
    bar:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() then return end
        local modifiers = (IsShiftKeyDown() and 1 or 0) + (IsAltKeyDown() and 2 or 0)
        if modifiers ~= self.lastModifiers then
            self.lastModifiers = modifiers
            ShowBarTooltip(self)
        end
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

        -- A Ctrl-drag never crafts, even if released without moving.
        if self.dragStarted then
            self.dragStarted = nil
            EndDrag()
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
        if item.recipeID == recipeID and not item.quest and not item.container then
            return true
        end
    end
    return false
end

function AfterCraftDone(recipeID)
    if not recipeID then return end
    local moved, removed, name = 0, 0, nil
    for key, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.quest and not item.container then
            if item.afterCraft == "untrack" then
                trackedItems[key] = nil
                removed = removed + 1
                name = name or DisplayName(item)
            elseif item.afterCraft == "inactive" and not item.inactive then
                item.inactive = true
                moved = moved + 1
                name = name or DisplayName(item)
            end
        end
    end
    if moved + removed == 0 then return end
    if removed > 0 and settings.recipeFocus and not IsTrackedRecipe(recipeID) then
        settings.recipeFocus[recipeID] = nil
    end
    UpdateBars()
    local parts = {}
    if removed > 0 then parts[#parts + 1] = "untracked " .. removed .. " bar(s)" end
    if moved > 0 then parts[#parts + 1] = "moved " .. moved .. " bar(s) to Inactive" end
    Print(name .. " crafted; " .. table.concat(parts, ", ") .. ".")
end

-- Right-click submenu for a recipe bar.
function AfterCraftMenuEntry(item)
    local current = item.afterCraft or "keep"
    local choices = {}
    for _, mode in ipairs(AFTER_CRAFT_MODES) do
        choices[#choices + 1] = {
            mode.name,
            function()
                item.afterCraft = (mode.key ~= "keep") and mode.key or nil
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
function OnCraftSucceeded(spellID)
    if crafting and spellID == crafting.id then
        crafting.done = crafting.done + 1
        if crafting.done >= crafting.amount then
            crafting = nil
            C_Timer.After(0.3, function() AfterCraftDone(spellID) end)
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
        C_Timer.After(0.3, function() AfterCraftDone(spellID) end)
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
        if item.recipeID == recipeID and not item.quest and not item.container then
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

function CheckSkillLimits()
    local messages, colorCache, asks = {}, {}, {}
    for key, item in pairs(trackedItems) do
        if item.recipeID and not item.quest and not item.container
            and (item.untilSkill or item.untilColor) then
            local label = DisplayName(item)
            if item.untilSkill then
                local rank, profession = GetProfessionSkill(item)
                if rank and rank >= item.untilSkill then
                    local done = ("%s reached %d; stopped tracking %s."):format(
                        profession, item.untilSkill, label)
                    if item.stopAsk then
                        asks[item.recipeID] = asks[item.recipeID] or { recipeID = item.recipeID,
                            label = label, done = done,
                            reason = ("%s reached %s %d."):format(label, profession, item.untilSkill) }
                    else
                        trackedItems[key] = nil
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
                        asks[item.recipeID] = asks[item.recipeID] or { recipeID = item.recipeID,
                            label = label, done = done,
                            reason = ("%s is now %s."):format(label, ColorText(color)) }
                    else
                        trackedItems[key] = nil
                        messages[label] = done
                    end
                end
            end
        end
    end
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
        if other.recipeID == recipeID and not other.quest and not other.container then
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
                if other.recipeID == recipeID and not other.quest and not other.container then
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
skillWatcher:SetScript("OnEvent", function()
    -- Skill info can lag the event a moment; many events come in a burst.
    if skillCheckPending then return end
    skillCheckPending = true
    C_Timer.After(1, function()
        skillCheckPending = false
        CheckSkillLimits()
        RequestUpdate(0) -- skill levels on the profession headings
    end)
end)

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
    for _, recipeID in ipairs(ids) do
        local okRecipe, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if okRecipe and type(info) == "table" and info.learned then
            local okSchematic, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
            local output = okSchematic and type(schematic) == "table" and schematic.outputItemID
            if output and not mine[output] then
                mine[output] = {
                    recipeID = recipeID,
                    recipeName = info.name,
                    profession = profession,
                    skillLineID = base.professionID,
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
function TrackChain(parentKey)
    local parent = trackedItems[parentKey]
    if not parent then return end
    local producer = FindProducer(parent.name)
    if not producer then
        Print("BarTab doesn't know a recipe of yours that makes " .. parent.name
            .. ". Open that profession once so BarTab can see your recipes.")
        return
    end
    local short = parent.goal - GetBarCount(parent)
    if short <= 0 then
        Print("You already have enough " .. parent.name .. " for " .. DisplayName(parent) .. ".")
        return
    end
    local reagents = GetRecipeReagents(producer.recipeID)
    if not reagents or #reagents == 0 then
        Print("Couldn't read the " .. (producer.recipeName or parent.name) .. " recipe right now; try again with the profession open.")
        return
    end

    local crafts = math.ceil(short / producer.qty)
    local recipeName = producer.recipeName or GetRecipeName(producer.recipeID) or parent.name
    local parts = {}
    for index, reagent in ipairs(reagents) do
        local goal = crafts * reagent.need
        local key = RecipeKey(reagent.name, producer.recipeID)
        local item = trackedItems[key]
        if item then
            if item.goal < goal then item.goal = goal end
        else
            trackedItems[key] = {
                name = reagent.name,
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
    Print(("Tracking how to make %d %s for %s: %d craft(s) of %s, needing %s."):format(
        short, parent.name, DisplayName(parent), crafts, recipeName, table.concat(parts, ", ")))
end

-- The recipe that makes this bar's material, unless you already track it.
function CanTrackChain(item)
    if item.quest or item.container then return nil end
    local producer = FindProducer(item.name)
    if producer and not IsTrackedRecipe(producer.recipeID) then return producer end
end

-- Tooltip lines: what this bar feeds, and whether you can make its material.
function AddChainLines(item)
    if item.quest or item.container then return end
    local fed = item.chainFor and trackedItems[item.chainFor]
    if fed then
        GameTooltip:AddLine("Makes " .. fed.name .. " for " .. DisplayName(fed), 0.8, 0.8, 0.8)
    end
    local producer = CanTrackChain(item)
    if producer and GetBarCount(item) < item.goal then
        local how = producer.profession or producer.recipeName or "a recipe"
        if producer.recipeName and producer.profession
            and string.lower(producer.recipeName) ~= string.lower(item.name) then
            how = producer.profession .. " (" .. producer.recipeName .. ")"
        end
        GameTooltip:AddLine("You can make " .. item.name .. " with " .. how
            .. "; right-click to track that too.", 0.5, 1, 0.5, true)
    end
end

producerWatcher = CreateFrame("Frame")
producerWatcher.barTabOwn = true -- never muted by BarTab's silent profession loads
for _, tradeEvent in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED" }) do
    pcall(producerWatcher.RegisterEvent, producerWatcher, tradeEvent)
end
producerScanPending = false
producerWatcher:SetScript("OnEvent", function()
    if producerScanPending then return end
    producerScanPending = true
    C_Timer.After(0.5, function()
        producerScanPending = false
        pcall(ScanProducers)
    end)
end)

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
                and not other.quest and not other.container) then
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
function GetShortages()
    local short, names = {}, {}
    local barMaterials = {}   -- recipeID -> { material = true } with a bar
    local plannedCrafts = {}  -- recipeID -> crafts the bars are sized for
    for _, item in pairs(trackedItems) do
        if not item.quest and not item.container and not item.inactive
            and not item.noVendor and GetSection(item) == CRAFT_SECTION then
            local key = string.lower(item.name)
            local missing = item.goal - GetBarCount(item)
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
        for _, reagent in ipairs(GetRecipeReagents(recipeID) or {}) do
            local key = string.lower(reagent.name)
            if not barMaterials[recipeID][key] then
                claimed[key] = (claimed[key] or 0) + crafts * reagent.need
                names[key] = names[key] or reagent.name
            end
        end
    end
    for key, needed in pairs(claimed) do
        local missing = needed - GetItemCount(names[key])
        if missing > 0 then short[key] = (short[key] or 0) + missing end
    end
    return short, names
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

function FindVendorPurchases()
    if not GetMerchantNumItems then return {} end
    local short, names = GetShortages()
    local list = {}
    for index = 1, GetMerchantNumItems() do
        local name, price, perPurchase, available, goldOnly = GetMerchantSlot(index)
        local key = name and string.lower(name)
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
        .. table.concat(skipped, ", ") .. " (change the limit in /bt config)."
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
            .. MoneyText(GetVendorLimit()) .. " limit (change it in /bt config).")
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
        pcall(OnMerchantShow)
    end)
end)


-- Craft the next ready bar (key binding and /bt craft) -----------------------
-- The first active recipe bar, in list order, that can craft now (counting
-- only its share of a shared material), crafted as a plain click would.

function BarCraftable(item)
    local craftable = GetCraftableCount(item.recipeID)
    if not craftable then return 0 end
    local count = GetBarCount(item)
    if count < GetItemCount(item.name) then
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
        if item.recipeID and not item.quest and not item.container and not item.inactive
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
