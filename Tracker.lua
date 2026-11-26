-- BarTab: objective tracker sections, bar layout, alerts, reordering.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

-- Sections and subsections -----------------------------------------------
--
-- Two tracker sections, each split into subsections:
--   BarTab: Quests    -> one subsection per zone, "Unknown/Other", "Inactive"
--   BarTab: Crafting  -> one subsection per profession, "Other", "Inactive"

QUEST_SECTION = "BarTab: Quests"
ITEM_SECTION = "BarTab: Items"
CRAFT_SECTION = "BarTab: Crafting"
INACTIVE_GROUP = "Inactive"
OTHER_GROUP = "Other"          -- crafting items with no recipe
UNKNOWN_ZONE = "Unknown/Other" -- quests whose zone can't be found

-- The quest log header (usually the zone) a quest is listed under.
function GetQuestZone(questID)
    if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID
        and C_QuestLog.GetInfo) then
        return nil
    end
    local index = C_QuestLog.GetLogIndexForQuestID(questID)
    if not index then return nil end
    for i = index, 1, -1 do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader and info.title and info.title ~= "" then
            return info.title
        end
    end
end

-- Quests above Crafting.
SECTION_ORDER = { [QUEST_SECTION] = 1, [CRAFT_SECTION] = 2, [ITEM_SECTION] = 3 }

-- Quests, then Crafting, then Items.
function CompareSections(a, b)
    if a == b then return false end
    return (SECTION_ORDER[a] or 9) < (SECTION_ORDER[b] or 9)
end

-- Subsections alphabetically, then Other / Unknown, then Inactive last.
function GroupRank(name)
    if name == INACTIVE_GROUP then return 2 end
    if name == OTHER_GROUP or name == UNKNOWN_ZONE then return 1 end
    return 0
end

function CompareGroups(a, b)
    if a == b then return false end
    local rankA, rankB = GroupRank(a), GroupRank(b)
    if rankA ~= rankB then return rankA < rankB end
    return a < b
end

function LookUpRecipeProfession(recipeID)
    if not (recipeID and C_TradeSkillUI) then return nil end

    if C_TradeSkillUI.GetProfessionInfoByRecipeID then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID, recipeID)
        if ok and type(info) == "table" then
            local name = info.parentProfessionName
            if not name or name == "" then
                name = info.professionName
            end
            if name and name ~= "" then
                return name
            end
        end
    end

    if C_TradeSkillUI.GetTradeSkillLineForRecipe then
        local ok, _, skillLineName =
            pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, recipeID)
        if ok and type(skillLineName) == "string" and skillLineName ~= "" then
            return skillLineName
        end
    end
end

-- Name of the profession window that's currently open, if any.
GetOpenProfessionName = function()
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" and info.professionName
            and info.professionName ~= "" then
            return info.professionName
        end
    end
end

-- Zone subsection for a quest item inside the Quests section.
function GetQuestZoneName(item)
    if not item.quest then return nil end
    if not item.quest.zone then
        item.quest.zone = GetQuestZone(item.quest.id)
    end
    return item.quest.zone or UNKNOWN_ZONE
end

function GetSection(item)
    if item.quest then return QUEST_SECTION end
    if item.container then return ITEM_SECTION end
    -- Alt-Shift-clicked items, until they're tied to a recipe.
    if item.collect and not item.recipeID then return ITEM_SECTION end
    return CRAFT_SECTION
end

function GetRecipeName(recipeID)
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(info) == "table" and info.name then
            return info.name
        end
    end
end

function EnsureLabel(item)
    if item.recipeID and not item.quest and not item.label then
        item.label = GetRecipeName(item.recipeID)
    end
end

-- Subsection within the section: Inactive, the quest's zone, or the
-- recipe's profession (Other if no recipe).
function GetGroup(item)
    EnsureLabel(item)
    if item.inactive then
        return INACTIVE_GROUP
    end
    if item.quest then
        return GetQuestZoneName(item)
    end
    if item.container then
        return item.container.name
    end
    if not item.recipeID then
        return OTHER_GROUP
    end
    if not item.profession then
        item.profession = LookUpRecipeProfession(item.recipeID)
    end
    return item.profession or OTHER_GROUP
end

-- All tracked keys, grouped by section and subsection, then in saved order.
function GetSortedKeys()
    local keys, sections, groups = {}, {}, {}
    for key, item in pairs(trackedItems) do
        keys[#keys + 1] = key
        sections[key] = GetSection(item)
        groups[key] = GetGroup(item)
    end
    table.sort(keys, function(a, b)
        if sections[a] ~= sections[b] then
            return CompareSections(sections[a], sections[b])
        end
        if groups[a] ~= groups[b] then
            return CompareGroups(groups[a], groups[b])
        end
        local orderA = trackedItems[a].order or math.huge
        local orderB = trackedItems[b].order or math.huge
        if orderA ~= orderB then
            return orderA < orderB
        end
        return a < b
    end)
    return keys
end

-- Quest items only show once the quest has something you can click to use:
-- the quest's own item, or one of its items with a "Use:" effect (e.g.
-- combining pages into a book). Usually that's known once the item is in
-- your bags. Once found, it's remembered for the rest of the quest.
function QuestHasUsableItem(item)
    local quest = item.quest
    if not quest then return true end
    if quest.usable then return true end

    local usable = false
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID
        and GetQuestLogSpecialItemInfo then
        local index = C_QuestLog.GetLogIndexForQuestID(quest.id)
        if index and GetQuestLogSpecialItemInfo(index) then
            usable = true
        end
    end

    if not usable then
        for _, req in ipairs(quest.items or {}) do
            GetItemCount(req.name) -- refreshes its item ID if it's in your bags
            if ItemHasUse(req.name) then
                usable = true
                break
            end
        end
    end

    -- Pieces in your bags that combine into an objective (pages -> chapter).
    if not usable and #FindRelatedUseItems(quest) > 0 then
        usable = true
    end

    if usable then
        quest.usable = true
    end
    return usable
end

function IsShown(item)
    -- Fill-up bars only show while you have the item they fill.
    if item.container then
        -- "Focus on" one material hides the crate's other bars.
        local focus = settings.containerFocus and settings.containerFocus[item.container.id]
        if focus and focus ~= string.lower(item.name) then
            return false
        end
        return GetItemCount(item.container.name) > 0
    end
    -- "Focus on" one ingredient hides a recipe's other bars (as long as the
    -- focused ingredient still has a bar).
    if item.recipeID and not item.quest then
        local focus = settings.recipeFocus and settings.recipeFocus[item.recipeID]
        if focus and focus ~= string.lower(item.name) then
            for _, other in pairs(trackedItems) do
                if other.recipeID == item.recipeID and not other.quest
                    and string.lower(other.name) == focus then
                    return false
                end
            end
        end
    end
    if item.quest and settings.questsUsableOnly == false then
        return true
    end
    return QuestHasUsableItem(item)
end

-- With /bt inline on, active quest bars live under their quests in
-- Blizzard's tracker; only inactive ones stay in the BarTab: Quests section.
function IsInlineQuestItem(item)
    return inlineQuestsActive and not panelActive and item.quest ~= nil and not item.inactive
end

function GetSectionKeys(section)
    local result = {}
    if settings.hiddenSections and settings.hiddenSections[section] then
        return result
    end
    for _, key in ipairs(GetSortedKeys()) do
        local item = trackedItems[key]
        if GetSection(item) == section and IsShown(item)
            and not IsInlineQuestItem(item) then
            result[#result + 1] = key
        end
    end
    return result
end

function GetSectionNames()
    local seen, names = {}, {}
    for _, item in pairs(trackedItems) do
        local section = GetSection(item)
        if not seen[section] then
            seen[section] = true
            names[#names + 1] = section
        end
    end
    table.sort(names, CompareSections)
    return names
end

-- Gives every item a sequential order number, keeping the current order.
function NormalizeOrder()
    for index, key in ipairs(GetSortedKeys()) do
        trackedItems[key].order = index
    end
end

function NextOrder()
    local highest = 0
    for _, item in pairs(trackedItems) do
        if item.order and item.order > highest then
            highest = item.order
        end
    end
    return highest + 1
end

-- Colors use the Okabe-Ito palette, which stays distinguishable for the
-- common types of color blindness: blues for crafts you can make now,
-- yellow/orange for crafts held back by another reagent.

-- Blocks you can craft right now.
SEGMENT_COLORS = {
    { 0.00, 0.45, 0.70 }, -- blue
    { 0.34, 0.71, 0.91 }, -- sky blue
}

-- Blocks where you have enough of this item but are short on another reagent.
BLOCKED_SEGMENT_COLORS = {
    { 0.94, 0.89, 0.26 }, -- yellow
    { 0.90, 0.62, 0.00 }, -- orange
}

-- Color sets you can pick in the settings window.
PALETTES = {
    { key = "colorblind", name = "Color-blind friendly (blue / orange)",
      ready = { { 0.00, 0.45, 0.70 }, { 0.34, 0.71, 0.91 } },
      blocked = { { 0.94, 0.89, 0.26 }, { 0.90, 0.62, 0.00 } } },
    { key = "classic", name = "Classic (green / yellow)",
      ready = { { 0.05, 0.55, 0.05 }, { 0.30, 0.85, 0.30 } },
      blocked = { { 1.00, 0.85, 0.20 }, { 0.70, 0.55, 0.00 } } },
    { key = "contrast", name = "High contrast (cyan / magenta)",
      ready = { { 0.00, 0.85, 0.85 }, { 0.00, 0.45, 0.50 } },
      blocked = { { 1.00, 0.25, 0.75 }, { 0.60, 0.05, 0.40 } } },
}

function ApplyPalette(key)
    for _, palette in ipairs(PALETTES) do
        if palette.key == key then
            for i = 1, 2 do
                SEGMENT_COLORS[i] = palette.ready[i]
                BLOCKED_SEGMENT_COLORS[i] = palette.blocked[i]
            end
            return palette
        end
    end
end

function GetSegment(bar, index)
    local segment = bar.segments[index]
    if not segment then
        segment = bar:CreateTexture(nil, "ARTWORK", nil, 2)
        segment:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar.segments[index] = segment
    end
    return segment
end

-- Shades the bar one block per craft's worth of this item: alternating blue
-- for crafts you can make now, alternating yellow/orange for crafts held back
-- by other reagents. Anything left over keeps the normal bar color.
function UpdateSegments(bar, item, count, craftable)
    bar.segments = bar.segments or {}
    for _, segment in ipairs(bar.segments) do
        segment:Hide()
    end

    -- Fill-up items: blue once this bundle is enough to fill it.
    if item.container then
        local _, full = GetFillState(item)
        if full then
            local color = SEGMENT_COLORS[1]
            local segment = GetSegment(bar, 1)
            segment:SetVertexColor(color[1], color[2], color[3])
            segment:ClearAllPoints()
            segment:SetAllPoints(bar)
            segment:Show()
        end
        return
    end

    -- Quest items: once this item is complete, the whole bar turns blue if
    -- everything the quest needs is collected, or yellow if something's missing.
    if item.quest then
        local state = GetQuestState(item)
        if not state and count < item.goal then
            -- Built from pieces: blue once you have them all.
            local progress = GetPieceProgress(item)
            if progress and progress.owned >= progress.required then
                local color = SEGMENT_COLORS[1]
                local segment = GetSegment(bar, 1)
                segment:SetVertexColor(color[1], color[2], color[3])
                segment:ClearAllPoints()
                segment:SetAllPoints(bar)
                segment:Show()
            end
            return
        end
        if state then
            local color = (state == "ready") and SEGMENT_COLORS[1]
                or BLOCKED_SEGMENT_COLORS[1]
            local segment = GetSegment(bar, 1)
            segment:SetVertexColor(color[1], color[2], color[3])
            segment:ClearAllPoints()
            segment:SetAllPoints(bar)
            segment:Show()
        end
        return
    end

    local perCraft = GetReagentQuantity(item.recipeID, item.name)
    if not perCraft or perCraft <= 0 or not craftable then
        return
    end

    local range = item.goal - item.start
    local width = bar:GetWidth()
    if range <= 0 or not width or width <= 0 then return end

    local blocks = math.floor(count / perCraft)
    local used = 0

    for i = 1, blocks do
        local low = math.max((i - 1) * perCraft, item.start)
        local high = math.min(i * perCraft, item.goal)

        if high > low then
            used = used + 1
            local segment = GetSegment(bar, used)

            local palette = (i <= craftable) and SEGMENT_COLORS
                or BLOCKED_SEGMENT_COLORS
            local color = palette[(i - 1) % 2 + 1]
            segment:SetVertexColor(color[1], color[2], color[3])
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", bar, "TOPLEFT",
                (low - item.start) / range * width, 0)
            segment:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT",
                (low - item.start) / range * width, 0)
            segment:SetWidth((high - low) / range * width)
            segment:Show()
        end

        if high >= item.goal then break end
    end
end

-- Shared materials ---------------------------------------------------------------
--
-- Several crafting bars can count the same material (Heavy Leather for both
-- Green Leather Belt and Hillman's Cloak). Setting "sharedMaterials":
--   "share" (default): bars higher in the list claim it first, each up to its
--                      goal; the last bar gets whatever is left.
--   "warn":            every bar counts all of it; the tooltip says it's shared.
--   "off":             every bar counts all of it, no mention.

local sharedCache -- rebuilt after each UpdateBars

local function BuildSharedCounts()
    local cache = { counts = {}, users = {} }
    for _, key in ipairs(GetSortedKeys()) do
        local item = trackedItems[key]
        if not item.quest and not item.container and not item.inactive and IsShown(item) then
            local material = string.lower(item.name)
            cache.users[material] = cache.users[material] or {}
            table.insert(cache.users[material], item)
        end
    end
    if (settings.sharedMaterials or "share") == "share" then
        for _, list in pairs(cache.users) do
            if #list > 1 then
                local remaining = GetItemCount(list[1].name)
                for i, item in ipairs(list) do
                    local share = (i == #list) and remaining or math.min(remaining, math.max(0, item.goal))
                    cache.counts[item] = share
                    remaining = remaining - share
                end
            end
        end
    end
    return cache
end

function InvalidateSharedCounts()
    sharedCache = nil
end

-- The count a bar shows: its share of a shared material, else all of it.
function GetBarCount(item)
    if item.quest or item.container then
        return GetItemCount(item.name)
    end
    sharedCache = sharedCache or BuildSharedCounts()
    return sharedCache.counts[item] or GetItemCount(item.name)
end

-- Session stats -------------------------------------------------------------
-- Per material, since login or /reload: what you've gained (count going up;
-- spending or crafting doesn't take it back) and how fast. Not saved.
-- Items taken out of the bank don't count as gained.
sessionStats = {}
sessionReadyAt = nil   -- bag counts are trusted a few seconds after login
bankOpen = false

function UpdateSessionStats(name)
    local key = string.lower(name)
    local count = GetItemCount(name)
    local stat = sessionStats[key]
    if not stat then
        sessionStats[key] = { last = count, gained = 0 }
        return
    end
    local now = GetTime()
    if count > stat.last and not bankOpen and sessionReadyAt and now >= sessionReadyAt then
        stat.gained = stat.gained + (count - stat.last)
        stat.firstGain = stat.firstGain or now
        stat.lastGain = now
    end
    stat.last = count
end

function ResetSessionStats()
    for key in pairs(sessionStats) do sessionStats[key] = nil end
end

function FormatMinutes(minutes)
    minutes = math.max(1, math.floor(minutes + 0.5))
    if minutes < 60 then return minutes .. " min" end
    local hours = math.floor(minutes / 60)
    local rest = minutes % 60
    return hours .. " hr" .. (rest > 0 and (" " .. rest .. " min") or "")
end

-- "This session: +14 in 32 min (26/hr)" and, with enough to go on, an
-- estimate of when the bar fills at that pace.
function AddSessionLines(item)
    local stat = sessionStats[string.lower(item.name)]
    if not stat or stat.gained <= 0 or not stat.firstGain then return end
    local elapsed = math.max(GetTime() - stat.firstGain, 60)
    local perHour = stat.gained * 3600 / elapsed
    GameTooltip:AddLine(("This session: +%d in %s (%d/hr)"):format(stat.gained,
        FormatMinutes(elapsed / 60), math.floor(perHour + 0.5)), 0.6, 0.85, 1)

    local remaining = item.goal - GetBarCount(item)
    if remaining > 0 and stat.gained >= 2 and perHour > 0 then
        GameTooltip:AddLine("Goal in about " .. FormatMinutes(remaining / perHour * 60)
            .. " at this pace", 0.6, 0.85, 1)
    end
end

-- The bars (in list order) counting the same material, if more than one.
function GetMaterialSharers(item)
    sharedCache = sharedCache or BuildSharedCounts()
    local list = sharedCache.users[string.lower(item.name)]
    if list and #list > 1 then return list end
end

-- Tooltip lines about a shared material.
function AddSharedLines(item)
    local mode = settings.sharedMaterials or "share"
    if mode == "off" or item.quest or item.container then return end
    local sharers = GetMaterialSharers(item)
    if not sharers then return end

    if mode == "share" then
        local parts = {}
        for _, other in ipairs(sharers) do
            parts[#parts + 1] = DisplayName(other) .. " " .. GetBarCount(other)
        end
        GameTooltip:AddLine("Shared " .. item.name .. " (in list order): " .. table.concat(parts, ", "),
            1, 0.82, 0, true)
    else
        local others = {}
        for _, other in ipairs(sharers) do
            if other ~= item then others[#others + 1] = DisplayName(other) end
        end
        GameTooltip:AddLine(item.name .. " is also counted by: " .. table.concat(others, ", "),
            1, 0.82, 0, true)
    end
end

function RefreshBar(bar, item, includeName)
    UpdateSessionStats(item.name)
    local count = GetBarCount(item)
    bar:SetMinMaxValues(item.start, item.goal)
    bar:SetValue(math.max(item.start, math.min(count, item.goal)))

    local craftText = ""
    local craftable = GetCraftableCount(item.recipeID)
    -- With a shared material, crafts are limited to this bar's share of it.
    if craftable and count < GetItemCount(item.name) then
        local perCraft = GetReagentQuantity(item.recipeID, item.name)
        if perCraft and perCraft > 0 then
            craftable = math.min(craftable, math.floor(count / perCraft))
        end
    end
    if craftable then
        craftText = " | Crafts: " .. craftable
    end
    UpdateSegments(bar, item, count, craftable)

    -- Quest items: status text, and the item a click should use (read by the
    -- secure click overlay).
    bar.useItemName = nil
    bar.useTargetName = nil
    local valueText = count .. " / " .. item.goal
    if item.container then
        local _, full = GetFillState(item)
        if full then
            if FindFullStack(item.name, item.goal) then
                craftText = " | Ready"
                bar.useItemName = "item:" .. item.container.id
                -- Using the crate asks you to pick the bundle; the click picks it.
                bar.useTargetName = item.name
                bar.useTargetAmount = item.goal
            else
                -- Enough in total but split over stacks; BarTab combines
                -- them by itself (clicking also does it).
                craftText = " | Stacking..."
            end
        end
    end
    if item.quest then
        local state, missing = GetQuestState(item)
        local progress = not state and count < item.goal and GetPieceProgress(item)
        if progress then
            -- Show the pieces collected toward this objective, e.g. 1 / 4 pages.
            bar:SetMinMaxValues(0, progress.required)
            bar:SetValue(progress.owned)
            valueText = progress.owned .. " / " .. progress.required .. " " .. progress.word .. "s"
            if progress.owned >= progress.required then
                craftText = " | Ready"
                bar.useItemName = progress.useName
            end
        elseif state == "ready" then
            craftText = " | Ready"
            bar.useItemName = GetQuestUseItem(item)
        elseif state == "waiting" then
            -- "Need Chapter 2" rather than repeating "Shredder Operating
            -- Manual - " when both share that start.
            local short = missing
            if NameStem(missing) and NameStem(missing) == NameStem(item.name) then
                short = missing:match("[%-:]%s*(.+)$") or missing
            end
            craftText = " | Need " .. short
        elseif count < item.goal then
            -- Not collected yet, but pieces that combine into it are in
            -- your bags (e.g. pages for a chapter): click to combine.
            local piece = PickRelatedUseItem(item)
            if piece then
                craftText = " | Click to combine"
                bar.useItemName = piece
            end
        end
    end

    -- Bars labeled with what you're making also name the material counted,
    -- in slightly smaller text.
    local textSize = settings.textSize or 12
    if item.label and not item.quest then
        valueText = valueText .. " " .. item.name
        textSize = textSize - 2
    end
    local fontFile, _, fontFlags = GameFontHighlight:GetFont()
    if fontFile then
        bar.text:SetFont(fontFile, textSize, fontFlags)
    end
    bar:SetHeight(settings.barHeight or 20)

    local prefix = includeName and (DisplayName(item) .. ": ") or ""
    bar.text:SetText(prefix .. valueText .. craftText)
end

-- Objective tracker: one section per profession -------------------------

trackerAvailable = false
sectionModules = {} -- section name -> tracker module

-- Adds one tracked item (name + bar) to a section. Returns false when the
-- tracker is out of room.
function LayoutItemBlock(module, key, section, group, shownBars)
    local item = trackedItems[key]
    local block = module:GetBlock(key)
    block.itemKey = key
    block.groupKey = nil
    block:SetHeader(DisplayName(item))

    local bar = GetBar(key, section)
    bar.section = section
    bar.group = group
    bar:SetParent(block)
    bar:ClearAllPoints()
    local width = block:GetWidth()
    if not width or width < 150 then width = 230 end
    bar:SetWidth(width - 20)
    RefreshBar(bar, item, false)
    block:AddCustomRegion(bar, 0, -4)

    if not module:LayoutBlock(block) then
        return false
    end
    shownBars[bar] = true
    return true
end

-- Subsection headings (zones / professions / Inactive) ---------------------

groupHeaders = {} -- "Section/Group" -> clickable heading

-- Collapsed state is saved per "Section/Group". Inactive starts collapsed.
function IsGroupCollapsed(groupKey)
    local saved = settings.collapsed and settings.collapsed[groupKey]
    if saved == nil then
        return settings.inactiveCollapsed ~= false
            and groupKey:match("/(.*)$") == INACTIVE_GROUP
    end
    return saved
end

function SetGroupCollapsed(groupKey, collapsed)
    settings.collapsed = settings.collapsed or {}
    settings.collapsed[groupKey] = collapsed and true or false
end

function ToggleGroup(groupKey)
    SetGroupCollapsed(groupKey, not IsGroupCollapsed(groupKey))
    UpdateBars()
end

function GetGroupHeader(groupKey, label, section)
    local header = groupHeaders[groupKey]
    if header then return header end

    header = CreateFrame("Button", nil, UIParent)
    header:SetHeight(18)
    -- Right side: the profession's skill level (e.g. 139/150), if it is one.
    header.skill = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header.skill:SetPoint("RIGHT", -2, 0)
    header.skill:SetJustifyH("RIGHT")
    header.skill:SetTextColor(0.7, 0.7, 0.7)
    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header.label:SetPoint("LEFT", 2, 0)
    header.label:SetPoint("RIGHT", header.skill, "LEFT", -6, 0)
    header.label:SetJustifyH("LEFT")
    header.label:SetWordWrap(false)
    header.label:SetTextColor(0.85, 0.85, 0.85)

    -- Thin line under the heading to set it apart from item names.
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.6, 0.6, 0.6, 0.5)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 2, 0)
    line:SetPoint("BOTTOMRIGHT", -2, 0)

    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    header:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ShowGroupMenu(self, section, label)
        else
            ToggleGroup(groupKey)
        end
    end)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(label)
        GameTooltip:AddLine(IsGroupCollapsed(groupKey) and "Click to expand"
            or "Click to collapse", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)

    groupHeaders[groupKey] = header
    return header
end

-- "- Leatherworking" (or "+ Leatherworking (3)" collapsed), with the skill
-- level right-aligned when the subsection is a profession you have.
function SetGroupHeaderText(header, section, group, count, collapsed)
    header.label:SetText((collapsed and "+ " or "- ") .. group
        .. (collapsed and (" (" .. count .. ")") or ""))
    local skillText = ""
    if section == CRAFT_SECTION and group ~= OTHER_GROUP and group ~= INACTIVE_GROUP
        and GetProfessionSkill then
        local rank, _, rankMax = GetProfessionSkill({ profession = group })
        if rank then
            skillText = (rankMax and rankMax > 0) and (rank .. "/" .. rankMax) or tostring(rank)
        end
    end
    header.skill:SetText(skillText)
end

-- Lays out a section as subsection headings with their items below.
function LayoutGroups(module, section, keys, shownBars, shownHeaders)
    local members, groups = {}, {}
    for _, key in ipairs(keys) do
        local group = GetGroup(trackedItems[key])
        if not members[group] then
            members[group] = {}
            groups[#groups + 1] = group
        end
        table.insert(members[group], key)
    end
    table.sort(groups, CompareGroups)

    for _, group in ipairs(groups) do
        local groupKey = section .. "/" .. group
        local collapsed = IsGroupCollapsed(groupKey)

        -- A block holding just the subsection heading (no item name).
        local block = module:GetBlock("group:" .. group)
        block.itemKey = nil
        block.groupKey = groupKey
        block.HeaderText:SetText("")

        local header = GetGroupHeader(groupKey, group, section)
        SetGroupHeaderText(header, section, group, #members[group], collapsed)
        header:SetParent(block)
        header:SetFrameLevel(block:GetFrameLevel() + 10)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -2)
        header:SetPoint("TOPRIGHT", block, "TOPRIGHT", -10, -2)
        header:Show()
        block.height = header:GetHeight() + 4

        if not module:LayoutBlock(block) then
            return
        end
        shownHeaders[header] = true

        if not collapsed then
            for _, key in ipairs(members[group]) do
                if not LayoutItemBlock(module, key, section, group, shownBars) then
                    return
                end
            end
        end
    end
end

function LayoutSection(module)
    -- While BarTab's own window shows the bars, the tracker sections stay
    -- empty (and so hidden), and leave the bars alone.
    if panelActive then return end
    local section = module.sectionName
    local shownBars, shownHeaders = {}, {}

    LayoutGroups(module, section, GetSectionKeys(section), shownBars, shownHeaders)

    local prefix = section .. "/"
    for groupKey, header in pairs(groupHeaders) do
        if groupKey:sub(1, #prefix) == prefix and not shownHeaders[header] then
            header:Hide()
        end
    end
    for _, bar in ipairs(bars) do
        if bar.section == section and not shownBars[bar] then
            bar:Hide()
        end
    end
end

function CreateSectionModule(name)
    local ok, module = pcall(CreateFrame, "Frame", nil, UIParent,
        "ObjectiveTrackerModuleTemplate")
    if not ok or not module or not module.GetBlock then
        return nil
    end

    module.sectionName = name
    module.uiOrder = 100 -- after every built-in section

    if module.Header and module.Header.HookScript then
        module.Header:HookScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                ShowGroupMenu(self, name, nil)
            end
        end)
    end
    module:SetHeader(name)

    -- Remember each section's collapsed state between sessions.
    if module.SetCollapsed then
        local blizzardSetCollapsed = module.SetCollapsed
        module.SetCollapsed = function(self, collapsed)
            blizzardSetCollapsed(self, collapsed)
            settings.collapsed = settings.collapsed or {}
            settings.collapsed[name] = collapsed and true or false
        end

        local saved = settings.collapsed and settings.collapsed[name]
        if saved then
            pcall(blizzardSetCollapsed, module, true)
        end
    end
    module.LayoutContents = LayoutSection

    module.OnBlockHeaderClick = function(_, block, mouseButton)
        if block.groupKey then
            if mouseButton == "RightButton" then
                local section, group = block.groupKey:match("^(.-)/(.*)$")
                ShowGroupMenu(block, section, group)
            else
                ToggleGroup(block.groupKey)
            end
        elseif mouseButton == "RightButton" then
            ShowItemMenu(block, block.itemKey)
        elseif mouseButton == "LeftButton" and not IsControlKeyDown() then
            CraftItem(block.itemKey)
        end
    end
    module.OnBlockHeaderEnter = function(_, block)
        if block.groupKey then return end
        ShowBarTooltip(block)
    end
    module.OnBlockHeaderLeave = function()
        GameTooltip:Hide()
    end

    return module
end

function IsAttached(module)
    local map = ObjectiveTrackerManager.moduleToContainerMap
    return module.parentContainer or (map and map[module])
end

-- Checks that the game accepts addon sections, starting with "Other".
-- Empty sections hide themselves, like the built-in ones do.
function SetUpTracker()
    if trackerAvailable then return true end
    if not (ObjectiveTrackerFrame and ObjectiveTrackerManager
        and ObjectiveTrackerManager.SetModuleContainer) then
        return false
    end

    local module = CreateSectionModule(CRAFT_SECTION)
    if not module then return false end

    module.uiOrder = 1000
    ObjectiveTrackerManager:SetModuleContainer(module, ObjectiveTrackerFrame)
    if not IsAttached(module) then
        module:Hide()
        return false
    end

    sectionModules[CRAFT_SECTION] = module
    trackerAvailable = true
    return true
end

-- Creates sections for any new professions and keeps them in order.
function EnsureSectionModules()
    local added = false
    for _, name in ipairs(GetSectionNames()) do
        if not sectionModules[name] then
            local module = CreateSectionModule(name)
            if not module then return false end
            sectionModules[name] = module
            added = true
        end
    end

    if added then
        -- Re-attach every section in order so new ones slot into place.
        local names = {}
        for name in pairs(sectionModules) do
            names[#names + 1] = name
        end
        table.sort(names, CompareSections)
        for index, name in ipairs(names) do
            local module = sectionModules[name]
            module.uiOrder = 100 + index
            ObjectiveTrackerManager:SetModuleContainer(module, ObjectiveTrackerFrame)
        end
    end

    return true
end

-- Fallback when tracker sections aren't available: standalone bars.
function UpdateStandaloneBars()
    local parent = ObjectiveTrackerFrame or UIParent
    local previous

    for _, key in ipairs(GetSortedKeys()) do
        local item = trackedItems[key]
        local bar = GetBar(key, "standalone")
        bar.section = GetSection(item)
        bar:SetParent(UIParent)

        -- Standalone bars can't collapse, so inactive items stay hidden.
        if item.inactive or not IsShown(item) then
            bar:Hide()
        else
            bar:ClearAllPoints()
            if previous then
                bar:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)
            elseif parent == ObjectiveTrackerFrame then
                bar:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -8)
            else
                bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 80)
            end

            RefreshBar(bar, item, true)
            bar:Show()
            previous = bar
        end
    end
end

-- BarTab window ------------------------------------------------------------
-- When the default objective tracker is hidden (an addon such as Questie
-- replacing it with its own), BarTab shows its sections in a window of its own instead. Same
-- bars, headings, clicks and menus. settings.displayMode: "auto" (the window
-- only when needed), "window" (always) or "tracker" (never).

panelActive = false
PANEL_WIDTH = 250 -- default; settings.panelWidth overrides
PANEL_WIDTH_MIN, PANEL_WIDTH_MAX = 180, 400

function PanelWidth()
    local width = tonumber(settings.panelWidth) or PANEL_WIDTH
    return math.max(PANEL_WIDTH_MIN, math.min(PANEL_WIDTH_MAX, width))
end
DISPLAY_MODES = {
    { key = "auto", name = "Tracker, or own window if hidden" },
    { key = "window", name = "Own window" },
    { key = "tracker", name = "Tracker only" },
}

-- Whether the default objective tracker has been hidden, typically by an
-- addon with its own quest tracker (Questie's, which is on by default,
-- hides it and keeps it hidden).
function IsTrackerHidden()
    local questie = _G.Questie
    if type(questie) == "table" and type(questie.db) == "table"
        and type(questie.db.profile) == "table" and questie.db.profile.trackerEnabled then
        return true
    end
    local frame = ObjectiveTrackerFrame
    if frame and frame.IsShown then
        return not frame:IsShown() or (frame.GetAlpha and frame:GetAlpha() < 0.05)
    end
    return false
end

function UsePanel()
    local mode = settings.displayMode or "auto"
    if mode == "window" then return true end
    if mode == "tracker" then return false end
    return IsTrackerHidden()
end

-- Notice when something hides or shows the tracker.
if ObjectiveTrackerFrame and ObjectiveTrackerFrame.HookScript then
    ObjectiveTrackerFrame:HookScript("OnHide", function() RequestUpdate(0.5) end)
    ObjectiveTrackerFrame:HookScript("OnShow", function() RequestUpdate(0.5) end)
end

function SavePanelPosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    settings.panelPosition = { x = left * scale, y = top * scale - UIParent:GetHeight() }
end

-- Saved spot, else just under the replacement tracker (Questie's), else
-- where the default tracker sits.
function PlacePanel()
    local frame = barTabPanel
    frame:ClearAllPoints()
    local saved = settings.panelPosition
    frame.underOtherTracker = nil
    if saved and saved.x and saved.y then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", saved.x, saved.y)
    elseif _G.Questie_BaseFrame then
        frame:SetPoint("TOPLEFT", _G.Questie_BaseFrame, "BOTTOMLEFT", 0, -10)
        frame.underOtherTracker = true
    elseif ObjectiveTrackerFrame and ObjectiveTrackerFrame:GetLeft() then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            ObjectiveTrackerFrame:GetLeft(), ObjectiveTrackerFrame:GetTop() or 600)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -260)
    end
end

function ResetPanelPosition()
    settings.panelPosition = nil
    if barTabPanel then PlacePanel() end
    Print("BarTab window moved back to its starting spot.")
end

function CreatePanel()
    local frame = CreateFrame("Frame", "BarTabPanel", UIParent)
    frame:SetSize(PANEL_WIDTH, 40)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("LOW")
    frame.sectionHeaders, frame.nameRows = {}, {}
    barTabPanel = frame
    PlacePanel()
    return frame
end

-- Section heading: click to collapse, right-click for the section menu,
-- drag to move the window.
function GetPanelSectionHeader(section)
    local frame = barTabPanel
    local header = frame.sectionHeaders[section]
    if header then return header end
    header = CreateFrame("Button", nil, frame)
    header:SetHeight(20)
    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.label:SetPoint("LEFT", 2, 0)
    header.label:SetPoint("RIGHT", -2, 0)
    header.label:SetJustifyH("LEFT")
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.4)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)

    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if settings.panelLocked then return end
        frame:StartMoving()
        header.dragged = true
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePanelPosition(frame)
    end)
    header:SetScript("OnClick", function(self, button)
        if self.dragged then self.dragged = nil return end
        if button == "RightButton" then
            ShowGroupMenu(self, section, nil)
        else
            settings.collapsed = settings.collapsed or {}
            settings.collapsed[section] = not settings.collapsed[section]
            UpdateBars()
        end
    end)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(section)
        GameTooltip:AddLine((settings.collapsed and settings.collapsed[section])
            and "Click to expand" or "Click to collapse", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(settings.panelLocked and "Window locked (unlock in /bt config)"
            or "Drag to move the window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.sectionHeaders[section] = header
    return header
end

-- The line above each bar (recipe or item name), clickable like the bar.
function GetPanelNameRow(barID)
    local frame = barTabPanel
    local row = frame.nameRows[barID]
    if row then return row end
    row = CreateFrame("Button", nil, frame)
    row:SetHeight(16)
    row.isBar = false
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", 2, 0)
    row.label:SetPoint("RIGHT", -2, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ShowItemMenu(self, self.itemKey)
        elseif not IsControlKeyDown() then
            CraftItem(self.itemKey)
        end
    end)
    row:SetScript("OnEnter", function(self)
        ShowBarTooltip(self)
        PreloadProfession(trackedItems[self.itemKey])
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.nameRows[barID] = row
    return row
end

function UpdatePanel()
    local frame = barTabPanel or CreatePanel()
    frame:SetWidth(PanelWidth())
    -- The replacement tracker's frame can appear after BarTab places its
    -- window; move under it then, unless you've placed the window yourself.
    if not settings.panelPosition and not frame.underOtherTracker and _G.Questie_BaseFrame then
        PlacePanel()
    end
    local width = PanelWidth()
    local y = 0
    local shownHeaders, shownGroupHeaders, shownBars, shownRows = {}, {}, {}, {}

    local function place(region, height, indent)
        region:SetParent(frame)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", frame, "TOPLEFT", indent or 0, -y)
        region:SetWidth(width - (indent or 0))
        region:Show()
        y = y + height
    end

    local names = GetSectionNames()
    table.sort(names, CompareSections)
    for _, section in ipairs(names) do
        local keys = GetSectionKeys(section)
        if #keys > 0 then
            if y > 0 then y = y + 8 end
            local collapsed = settings.collapsed and settings.collapsed[section]
            local header = GetPanelSectionHeader(section)
            header.label:SetText((collapsed and "+ " or "") .. section)
            place(header, header:GetHeight() + 4)
            shownHeaders[header] = true

            if not collapsed then
                local members, groups = {}, {}
                for _, key in ipairs(keys) do
                    local group = GetGroup(trackedItems[key])
                    if not members[group] then
                        members[group] = {}
                        groups[#groups + 1] = group
                    end
                    table.insert(members[group], key)
                end
                table.sort(groups, CompareGroups)

                for _, group in ipairs(groups) do
                    local groupKey = section .. "/" .. group
                    local groupCollapsed = IsGroupCollapsed(groupKey)
                    local groupHeader = GetGroupHeader(groupKey, group, section)
                    SetGroupHeaderText(groupHeader, section, group, #members[group], groupCollapsed)
                    place(groupHeader, groupHeader:GetHeight() + 4, 4)
                    groupHeader:SetFrameLevel(frame:GetFrameLevel() + 5)
                    shownGroupHeaders[groupHeader] = true

                    if not groupCollapsed then
                        for _, key in ipairs(members[group]) do
                            local item = trackedItems[key]
                            local row = GetPanelNameRow(section .. "\0" .. key)
                            row.itemKey = key
                            row.label:SetText(DisplayName(item))
                            place(row, row:GetHeight(), 10)
                            shownRows[row] = true

                            local bar = GetBar(key, section)
                            bar.section = section
                            bar.group = group
                            RefreshBar(bar, item, false)
                            place(bar, bar:GetHeight() + 6, 14)
                            bar:SetWidth(width - 24)
                            shownBars[bar] = true
                        end
                    end
                end
            end
        end
    end

    -- Hide whatever isn't in use now.
    for _, header in pairs(frame.sectionHeaders) do
        if not shownHeaders[header] then header:Hide() end
    end
    for _, header in pairs(groupHeaders) do
        if header:GetParent() == frame and not shownGroupHeaders[header] then header:Hide() end
    end
    for _, row in pairs(frame.nameRows) do
        if not shownRows[row] then row:Hide() end
    end
    for _, bar in ipairs(bars) do
        if bar:GetParent() == frame and not shownBars[bar] then bar:Hide() end
    end

    frame:SetHeight(math.max(y, 1))
    frame:SetShown(y > 0)
end

-- Goal-reached alerts ----------------------------------------------------------
--
-- When a bar reaches its goal (a material bar fills, a crate bundle is
-- ready, a quest has everything it needs), BarTab says so in chat and,
-- optionally, with a sound and an on-screen message.

goalReached = {}   -- item key -> whether it was at its goal last check
lastAlertTime = {} -- item key -> GetTime() of its last alert

function IsGoalReached(item)
    if item.container then
        local _, full = GetFillState(item)
        return full
    elseif item.quest then
        return GetQuestState(item) == "ready"
    end
    return GetBarCount(item) >= item.goal
end

function AlertText(item)
    if item.container then
        return item.container.name .. " is ready: " .. item.goal .. " " .. item.name
    elseif item.quest then
        return (item.quest.title or item.name) .. ": all items collected"
    elseif item.label then
        return item.label .. ": " .. item.name .. " " .. item.goal .. " / " .. item.goal
    end
    return item.name .. ": " .. item.goal .. " / " .. item.goal .. ", goal reached"
end

function PlayGoalAlert(text)
    if settings.alertSound ~= false and PlaySound then
        local sound = (SOUNDKIT and (SOUNDKIT.ALARM_CLOCK_WARNING_3 or SOUNDKIT.READY_CHECK)) or 12889
        pcall(PlaySound, sound, "Master")
    end
    -- On-screen style: "top" (small, top of screen), "raid" (big raid-warning
    -- text in the middle of the screen) or "off".
    local style = settings.alertStyle or (settings.alertScreen == false and "off" or "top")
    if style == "raid" and RaidNotice_AddMessage and RaidWarningFrame then
        local color = (ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]) or { r = 1, g = 0.28, b = 0 }
        RaidNotice_AddMessage(RaidWarningFrame, "BarTab: " .. text, color)
    elseif style ~= "off" and UIErrorsFrame then
        UIErrorsFrame:AddMessage("BarTab: " .. text, 0.4, 0.8, 1.0)
    end
    Print(text)
end

function CheckGoalAlerts()
    for key, item in pairs(trackedItems) do
        if not item.inactive and IsShown(item) then
            local reached = IsGoalReached(item) and true or false
            local before = goalReached[key]
            goalReached[key] = reached
            -- No alert the first time a bar is seen (e.g. at login), only
            -- when it goes from short to complete; at most once per 10 s.
            if before == false and reached and settings.goalAlerts ~= false
                and GetTime() - (lastAlertTime[key] or 0) > 10 then
                lastAlertTime[key] = GetTime()
                PlayGoalAlert(AlertText(item))
            end
        else
            goalReached[key] = nil
        end
    end
end

UpdateBars = function()
    InvalidateSharedCounts()
    -- Hide bars for items that are no longer tracked.
    for _, bar in pairs(barsByKey) do
        if not trackedItems[bar.itemKey] then
            bar:Hide()
            bar.section = nil
        end
    end

    local usePanel = UsePanel()
    if usePanel ~= panelActive then
        panelActive = usePanel
        if not usePanel and barTabPanel then barTabPanel:Hide() end
        -- Give the bars back to (or take them from) the tracker sections.
        for _, module in pairs(sectionModules) do
            module:MarkDirty()
        end
    end

    if panelActive then
        UpdatePanel()
    elseif trackerAvailable and EnsureSectionModules() then
        for _, module in pairs(sectionModules) do
            module:MarkDirty()
        end
    else
        UpdateStandaloneBars()
    end

    if UpdateInlineQuests then
        UpdateInlineQuests()
    end

    CheckGoalAlerts()
end

-- Ctrl-drag reordering ----------------------------------------------------

dragDriver = CreateFrame("Frame")
dragDriver:Hide()

function GetBarUnderCursor()
    for _, bar in ipairs(bars) do
        if bar:IsVisible() and bar:IsMouseOver() then
            return bar
        end
    end
end

-- Moves the dragged item into the dropped-on item's position.
function MoveItem(fromKey, toKey)
    local keys = GetSortedKeys()
    local fromIndex, toIndex
    for index, key in ipairs(keys) do
        if key == fromKey then fromIndex = index end
        if key == toKey then toIndex = index end
    end
    if not fromIndex or not toIndex or fromIndex == toIndex then return end

    table.remove(keys, fromIndex)
    table.insert(keys, toIndex, fromKey)
    for index, key in ipairs(keys) do
        trackedItems[key].order = index
    end
    UpdateBars()
end

BeginDrag = function(bar)
    if not bar.itemKey then return end
    dragState = { key = bar.itemKey, bar = bar }
    bar:SetAlpha(0.6)
    GameTooltip:Hide()
    if SetCursor then SetCursor("UI_MOVE_CURSOR") end
    dragDriver:Show()
end

EndDrag = function()
    local state = dragState
    if not state then return end
    dragState = nil
    dragDriver:Hide()

    for _, bar in ipairs(bars) do
        bar.dropHighlight:Hide()
    end
    state.bar:SetAlpha(1)
    if ResetCursor then ResetCursor() end

    local target = GetBarUnderCursor()
    if target and target.itemKey and target.itemKey ~= state.key
        and target.section == state.bar.section
        and target.group == state.bar.group then
        MoveItem(state.key, target.itemKey)
    end
end

dragDriver:SetScript("OnUpdate", function(self)
    if not dragState then
        self:Hide()
        return
    end

    -- Safety net in case the bar never receives its mouse-up.
    if not IsMouseButtonDown("LeftButton") then
        EndDrag()
        return
    end

    local target = GetBarUnderCursor()
    for _, bar in ipairs(bars) do
        bar.dropHighlight:SetShown(bar == target and bar ~= dragState.bar
            and bar.section == dragState.bar.section
            and bar.group == dragState.bar.group)
    end
end)

-- Collapses bursts of bag events into a single refresh.
function RequestUpdate(delay)
    if updatePending then return end
    updatePending = true
    C_Timer.After(delay, function()
        updatePending = false
        UpdateBars()
    end)
end

function GetSelectedRecipeID()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
    return info and tonumber(info.recipeID)
end

function Trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

-- Turns shift-clicked item links into plain names:
-- "|cffffffff|Hitem:2318::|h[Light Hide]|h|r" -> "Light Hide"
function StripLinks(text)
    text = text or ""
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|cn[^:|]*:", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H[^|]*|h(.-)|h", "%1")
    text = text:gsub("%[(.-)%]", "%1")
    return Trim(text)
end

-- For /bt assign: the item is either a leading link or the text before the
-- (shift-clicked) recipe.
-- Returns e.g. "Light Leather" or "Light Leather 0-20".
function ParseAssignTarget(args)
    local function textBeforeLink(text)
        return text:match("^(.-)%s*|c")
            or text:match("^(.-)%s*|H")
            or text:match("^(.-)%s*%[")
            or text
    end

    local link, rest = args:match("^(|c[^|]*|H[^|]*|h%[.-%]|h)(.*)$")
    if not link then
        link, rest = args:match("^(|H[^|]*|h%[.-%]|h)(.*)$")
    end
    if link then
        -- Drop the link's trailing "|r" before looking for the recipe link.
        rest = rest:gsub("^|r", "")
        return StripLinks(link .. textBeforeLink(rest))
    end

    return StripLinks(textBeforeLink(args))
end

-- Fixes items saved with link text as their name by earlier versions.
function CleanSavedNames()
    local changes = {}
    for key, item in pairs(trackedItems) do
        local clean = StripLinks(item.name)
        if clean ~= "" and clean ~= item.name then
            changes[#changes + 1] = { key = key, clean = clean }
        end
    end

    for _, change in ipairs(changes) do
        local item = trackedItems[change.key]
        local newKey = string.lower(change.clean) .. (change.key:match("(@%d+)$") or "")
        item.name = change.clean
        if newKey ~= change.key then
            trackedItems[change.key] = nil
            local existing = trackedItems[newKey]
            if existing then
                existing.recipeID = existing.recipeID or item.recipeID
                existing.profession = existing.profession or item.profession
            else
                trackedItems[newKey] = item
            end
        end
    end
end

function GetStackSize(itemName)
    local _, _, _, _, _, _, _, stackSize = C_Item.GetItemInfo(itemName)
    return tonumber(stackSize)
end

-- "Name 5-20" -> Name, 5, 20; "Name 20" -> Name, 0, 20; otherwise nil.
function ParseExplicitRange(args)
    local name, minText, maxText =
        args:match("^%s*(.-)%s+(%d+)%s*%-%s*(%d+)%s*$")

    if name then
        return Trim(name), tonumber(minText), tonumber(maxText)
    end

    name, maxText = args:match("^%s*(.-)%s+(%d+)%s*$")
    if name then
        return Trim(name), 0, tonumber(maxText)
    end
end

function ParseTrackArgs(args)
    local name, startCount, goal = ParseExplicitRange(args)
    if name then
        return name, startCount, goal
    end

    name = Trim(args)
    if name == "" then return nil end

    local stackSize = GetStackSize(name)
    if not stackSize then
        return nil, nil, nil, "Could not determine stack size. Specify a max, e.g. /bt track Light Leather 20."
    end

    return name, 0, stackSize
end
