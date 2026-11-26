-- BarTab: objective tracker sections, bar layout, alerts, reordering.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

-- Sections and subsections -----------------------------------------------
--
-- Two tracker sections, each split into subsections:
--   BarTab: Crafting  -> one subsection per profession, "Other", "Inactive"
--   BarTab: Items     -> one subsection per fill-up item, "Other", "Inactive"

ITEM_SECTION = "BarTab: Items"
CRAFT_SECTION = "BarTab: Crafting"
INACTIVE_GROUP = "Inactive"
OTHER_GROUP = "Other"          -- crafting items with no recipe

-- Crafting, then Items.
SECTION_ORDER = { [CRAFT_SECTION] = 1, [ITEM_SECTION] = 2 }

function CompareSections(a, b)
    if a == b then return false end
    return (SECTION_ORDER[a] or 9) < (SECTION_ORDER[b] or 9)
end

-- Subsections alphabetically, then Other, then Inactive last.
function GroupRank(name)
    if name == INACTIVE_GROUP then return 2 end
    if name == OTHER_GROUP then return 1 end
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

function GetSection(item)
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
    if item.recipeID and not item.label then
        item.label = GetRecipeName(item.recipeID)
    end
end

-- Subsection within the section: Inactive, the fill-up item, or the
-- recipe's profession (Other if no recipe).
function GetGroup(item)
    EnsureLabel(item)
    if item.inactive then
        return INACTIVE_GROUP
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

function IsShown(item)
    -- Fill-up bars only show while you have the item they fill.
    if item.container then
        -- "Focus on" one material hides the crate's other bars.
        local focus = settings.containerFocus and settings.containerFocus[item.container.id]
        if focus and focus ~= string.lower(item.name) then
            return false
        end
        return CountContainer(item.container) > 0
    end
    -- "Focus on" one ingredient hides a recipe's other bars (as long as the
    -- focused ingredient still has a bar).
    if item.recipeID then
        local focus = settings.recipeFocus and settings.recipeFocus[item.recipeID]
        if focus and focus ~= string.lower(item.name) then
            for _, other in pairs(trackedItems) do
                if other.recipeID == item.recipeID
                    and string.lower(other.name) == focus then
                    return false
                end
            end
        end
    end
    return true
end

function GetSectionKeys(section)
    local result = {}
    if settings.hiddenSections and settings.hiddenSections[section] then
        return result
    end
    for _, key in ipairs(GetSortedKeys()) do
        local item = trackedItems[key]
        if GetSection(item) == section and IsShown(item) then
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
    -- readyFill / blockedFill: the single color craft blocks use, with a
    -- dark line between crafts (the lighter shade, so the lines show).
    { key = "colorblind", name = "Color-blind friendly (blue / orange)",
      ready = { { 0.00, 0.45, 0.70 }, { 0.34, 0.71, 0.91 } },
      blocked = { { 0.94, 0.89, 0.26 }, { 0.90, 0.62, 0.00 } },
      readyFill = { 0.34, 0.71, 0.91 }, blockedFill = { 0.90, 0.62, 0.00 } },
    { key = "classic", name = "Classic (green / yellow)",
      ready = { { 0.05, 0.55, 0.05 }, { 0.30, 0.85, 0.30 } },
      blocked = { { 1.00, 0.85, 0.20 }, { 0.70, 0.55, 0.00 } },
      readyFill = { 0.30, 0.85, 0.30 }, blockedFill = { 1.00, 0.85, 0.20 } },
    { key = "contrast", name = "High contrast (cyan / magenta)",
      ready = { { 0.00, 0.85, 0.85 }, { 0.00, 0.45, 0.50 } },
      blocked = { { 1.00, 0.25, 0.75 }, { 0.60, 0.05, 0.40 } },
      readyFill = { 0.00, 0.85, 0.85 }, blockedFill = { 1.00, 0.25, 0.75 } },
}
READY_FILL = { 0.34, 0.71, 0.91 }
BLOCKED_FILL = { 0.90, 0.62, 0.00 }

function ApplyPalette(key)
    for _, palette in ipairs(PALETTES) do
        if palette.key == key then
            for i = 1, 2 do
                SEGMENT_COLORS[i] = palette.ready[i]
                BLOCKED_SEGMENT_COLORS[i] = palette.blocked[i]
            end
            READY_FILL = palette.readyFill or palette.ready[1]
            BLOCKED_FILL = palette.blockedFill or palette.blocked[1]
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

-- A thin dark line marking where one craft ends and the next begins.
function GetDivider(bar, index)
    bar.dividers = bar.dividers or {}
    local line = bar.dividers[index]
    if not line then
        line = bar:CreateTexture(nil, "ARTWORK", nil, 3)
        line:SetColorTexture(0, 0, 0, 0.85)
        -- Thin textures can vanish when the game snaps them to the pixel
        -- grid; keep them.
        if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(false) end
        if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
        bar.dividers[index] = line
    end
    return line
end

FUTURE_LINE_SHADE = 0.65
-- How strongly the "could make" stretch on a Make-until-I-have bar shows.
OUTPUT_STRETCH_ALPHA = 0.8

-- How many crafts the recipe's other ingredients (everything but this bar's
-- material) would allow; very large if there are none.
function OtherIngredientsLimit(item)
    local limit = math.huge
    local own = string.lower(item.name)
    for _, reagent in ipairs(GetRecipeReagents(item.recipeID) or {}) do
        if string.lower(reagent.name) ~= own and reagent.need > 0 then
            limit = math.min(limit, math.floor(reagent.have / reagent.need))
        end
    end
    return limit
end

-- Two screen pixels wide at whatever UI scale, centered on x (in the bar's
-- units), lined up with whole pixels so it always shows.
-- edge: nil for a full-height line, or "TOP" / "BOTTOM" for a short tick
-- along that edge (tickHeight in bar units).
function PlaceDivider(line, bar, x, edge, tickHeight)
    local scale = bar:GetEffectiveScale() or 1
    local pixel = 1
    if GetPhysicalScreenSize then
        local _, physicalHeight = GetPhysicalScreenSize()
        if physicalHeight and physicalHeight > 0 then
            pixel = 768 / physicalHeight / scale   -- one screen pixel, in bar units
        end
    end
    local width = 2 * pixel
    local left = math.floor((x - pixel) / pixel + 0.5) * pixel
    line:SetWidth(width)
    line:ClearAllPoints()
    if edge == "TOP" then
        line:SetPoint("TOPLEFT", bar, "TOPLEFT", left, 0)
        line:SetHeight(tickHeight)
    elseif edge == "BOTTOM" then
        line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", left, 0)
        line:SetHeight(tickHeight)
    else
        line:SetPoint("TOPLEFT", bar, "TOPLEFT", left, 0)
        line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", left, 0)
    end
end

-- Shades the bar one block per craft's worth of this item: one color for
-- crafts you can make now, another for crafts held back by other reagents,
-- with a line between crafts. Anything left over keeps the normal bar color.
function UpdateSegments(bar, item, count, craftable)
    bar.segments = bar.segments or {}
    for _, segment in ipairs(bar.segments) do
        segment:Hide()
    end
    for _, line in ipairs(bar.dividers or {}) do
        line:Hide()
    end

    -- Fill-up items: blue once this bundle is enough to fill it.
    if item.container then
        local _, full = GetFillState(item)
        if full then
            local color = READY_FILL
            local segment = GetSegment(bar, 1)
            segment:SetVertexColor(color[1], color[2], color[3])
            segment:SetAlpha(1)
            segment:ClearAllPoints()
            segment:SetAllPoints(bar)
            segment:Show()
        end
        return
    end

    -- "Make until I have..." bars: a lighter stretch after what you have,
    -- showing how far the materials in your bags would take the bar
    -- (2 Coarse Stone on a 0 / 51 Coarse Blasting Powder bar: 2 more).
    if IsOutputBar(item) then
        local range = item.goal - item.start
        local width = bar:GetWidth()
        if not craftable or craftable <= 0 or range <= 0 or not width or width <= 0 then return end
        local _, perCraftMade = GetRecipeOutput(item.recipeID)
        local from = math.max(count, item.start)
        local to = math.min(item.goal, from + craftable * (perCraftMade or 1))
        if to > from then
            local color = READY_FILL
            local segment = GetSegment(bar, 1)
            segment:SetVertexColor(color[1], color[2], color[3])
            segment:SetAlpha(OUTPUT_STRETCH_ALPHA)
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", bar, "TOPLEFT", (from - item.start) / range * width, 0)
            segment:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", (from - item.start) / range * width, 0)
            segment:SetWidth((to - from) / range * width)
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
    local used, lines = 0, 0

    for i = 1, blocks do
        local low = math.max((i - 1) * perCraft, item.start)
        local high = math.min(i * perCraft, item.goal)

        if high > low then
            used = used + 1
            local segment = GetSegment(bar, used)

            local color = (i <= craftable) and READY_FILL or BLOCKED_FILL
            segment:SetVertexColor(color[1], color[2], color[3])
            segment:SetAlpha(1)
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", bar, "TOPLEFT",
                (low - item.start) / range * width, 0)
            segment:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT",
                (low - item.start) / range * width, 0)
            segment:SetWidth((high - low) / range * width)
            segment:Show()

            -- The line at this craft's right edge (not at the bar's end).
            if high < item.goal then
                lines = lines + 1
                local line = GetDivider(bar, lines)
                local x = (high - item.start) / range * width
                PlaceDivider(line, bar, x)
                line:SetColorTexture(0, 0, 0, 0.85)
                line:SetAlpha(1)
                line:Show()
            end
        end

        if high >= item.goal then break end
    end

    -- Lines across the rest of the bar, where future crafts would end, so you
    -- can see how many crafts the whole bar holds. Each is the color that
    -- craft's block would be once you have this material: ready if the
    -- recipe's other ingredients already cover it, held back if not.
    local otherLimit = OtherIngredientsLimit(item)
    local boundary = (math.max(blocks, math.floor(item.start / perCraft)) + 1) * perCraft
    while boundary < item.goal do
        if boundary > item.start then
            -- Short ticks at the top and bottom edges (the middle stays clear
            -- for the bar's text), marking where the line between crafts
            -- will be.
            local craftNumber = boundary / perCraft
            local color = (craftNumber <= otherLimit) and READY_FILL or BLOCKED_FILL
            local shade = FUTURE_LINE_SHADE -- a darker shade of the same color
            local x = (boundary - item.start) / range * width
            -- A notch about a tenth of the bar's height, at least 1 screen pixel.
            local pixel = 1
            if GetPhysicalScreenSize then
                local _, physicalHeight = GetPhysicalScreenSize()
                if physicalHeight and physicalHeight > 0 then
                    pixel = 768 / physicalHeight / (bar:GetEffectiveScale() or 1)
                end
            end
            -- Whole pixels, so the notch doesn't blur or vanish.
            local tickHeight = math.max(1, math.floor((bar:GetHeight() or 18) * 0.1 / pixel + 0.5)) * pixel
            for _, edge in ipairs({ "TOP", "BOTTOM" }) do
                lines = lines + 1
                local tick = GetDivider(bar, lines)
                PlaceDivider(tick, bar, x, edge, tickHeight)
                tick:SetColorTexture(color[1] * shade, color[2] * shade, color[3] * shade, 1)
                tick:SetAlpha(1)
                tick:Show()
            end
        end
        boundary = boundary + perCraft
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

-- Which material a bar counts: its item ID when known, else its name.
function MaterialKey(item)
    local id = ItemIDFor(item)
    return id and ("id:" .. id) or string.lower(item.name)
end

local function BuildSharedCounts()
    local cache = { counts = {}, users = {} }
    for _, key in ipairs(GetSortedKeys()) do
        local item = trackedItems[key]
        -- "Make until I have..." bars count everything you own and take no
        -- share from (or give none to) bars using the item as a material.
        if not item.container and not item.inactive and IsShown(item) and not IsOutputBar(item) then
            local material = MaterialKey(item)
            cache.users[material] = cache.users[material] or {}
            table.insert(cache.users[material], item)
        end
    end
    if (settings.sharedMaterials or "share") == "share" then
        for _, list in pairs(cache.users) do
            if #list > 1 then
                local remaining = CountItem(list[1])
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
    makeableCache = nil
end

-- "Could make" on material bars -------------------------------------------------
-- How many more of a bar's material you could make from what's in your bags
-- with your own recipes (8 / 10 Thick Leather with Heavy Leather for 2 more:
-- 2), several steps deep, the same way chain crafting plans. Up to what the
-- bar is short. Cached until the next refresh.
makeableCache = nil
makeableReady = {} -- itemKey -> whether you could make the rest, for the alert
MAKEABLE_ALPHA = 0.75

function MakeableCount(item, count)
    if item.container or IsOutputBar(item) then return 0 end
    local short = (item.goal or 0) - count
    if short <= 0 then return 0 end
    makeableCache = makeableCache or {}
    if makeableCache[item] then return makeableCache[item] end
    local result, producer = 0, ProducerFor(ItemIDFor(item), item.name)
    if producer then
        local qty = math.max(1, producer.qty or 1)
        local profession = item.profession or producer.profession
        local otherProfession = item.profession and producer.profession
            and string.lower(item.profession) ~= string.lower(producer.profession)
        if not otherProfession or settings.chainOtherProfessions then
            local function Can(n)
                return ChainFeasible(producer.recipeID, n, {}, 0, { [producer.recipeID] = true }, {},
                    producer.profession or profession)
            end
            local low, high = 0, math.min(math.ceil(short / qty), CHAIN_MOST)
            while low < high do
                local mid = math.floor((low + high + 1) / 2)
                if Can(mid) then low = mid else high = mid - 1 end
            end
            result = math.min(short, low * qty)
        end
    end
    makeableCache[item] = result
    return result
end

-- The lighter stretch after what you have, and the alert when it covers the
-- rest of the bar.
function UpdateMakeable(bar, item, count, itemKey)
    local makeable = 0
    if item.recipeID or ProducerFor(ItemIDFor(item), item.name) then
        local ok, value = pcall(MakeableCount, item, count)
        makeable = ok and value or 0
    end
    bar.makeable = makeable
    local range = item.goal - item.start
    local width = bar:GetWidth()
    if makeable > 0 and range > 0 and width and width > 0 then
        if not bar.makeableFill then
            bar.makeableFill = bar:CreateTexture(nil, "ARTWORK", nil, 1)
            bar.makeableFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        end
        local from = math.max(count, item.start)
        local to = math.min(item.goal, count + makeable)
        local fill = bar.makeableFill
        fill:SetVertexColor(READY_FILL[1], READY_FILL[2], READY_FILL[3])
        fill:SetAlpha(MAKEABLE_ALPHA)
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", bar, "TOPLEFT", (from - item.start) / range * width, 0)
        fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", (from - item.start) / range * width, 0)
        fill:SetWidth(math.max(1, (to - from) / range * width))
        fill:Show()
    elseif bar.makeableFill then
        bar.makeableFill:Hide()
    end
    -- Alert once when you go from short to able to make the rest (not the
    -- first time a bar is seen, e.g. at login).
    if itemKey and not item.inactive then
        local ready = count < item.goal and count + makeable >= item.goal
        local before = makeableReady[itemKey]
        makeableReady[itemKey] = ready
        if before == false and ready and settings.makeableAlerts ~= false then
            PlayGoalAlert(("%s: you have the materials to make the rest (%d %s for %s)."):format(
                item.name, item.goal - count, item.name, DisplayName(item)))
        end
    end
end

-- The count a bar shows: its share of a shared material, else all of it.
function GetBarCount(item)
    if item.container then
        return CountItem(item)
    end
    sharedCache = sharedCache or BuildSharedCounts()
    return sharedCache.counts[item] or CountItem(item)
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
    local list = sharedCache.users[MaterialKey(item)]
    if list and #list > 1 then return list end
end

-- Tooltip lines about a shared material.
function AddSharedLines(item)
    local mode = settings.sharedMaterials or "share"
    if mode == "off" or item.container then return end
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
    if craftable and count < CountItem(item) then
        local perCraft = GetReagentQuantity(item.recipeID, item.name)
        if perCraft and perCraft > 0 then
            craftable = math.min(craftable, math.floor(count / perCraft))
        end
    end
    if craftable then
        craftText = " | Crafts: " .. craftable
    end
    UpdateSegments(bar, item, count, craftable)
    UpdateMakeable(bar, item, count, bar.itemKey)

    -- Fill-up items: status text, and the item a click should use (read by the
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
    -- Bars labeled with what you're making also name the material counted,
    -- in slightly smaller text.
    local textSize = settings.textSize or 12
    -- (Not when the heading already says it: a "Make until I have..." bar
    -- for Mageweave Bandage just says "18 / 40", leaving room for the rest.)
    if item.label and string.lower(item.label) ~= string.lower(item.name) then
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
            -- At the limit with more to train: orange, as a reminder.
            if rankMax and rankMax > 0 and rank >= rankMax and rankMax < PROFESSION_TOP then
                skillText = "|cffff9933" .. skillText .. "|r"
            end
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
    -- Runs inside Blizzard's tracker update: never let an error escape.
    module.LayoutContents = Safe("drawing " .. name, LayoutSection)

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
        elseif mouseButton == "LeftButton" and IsControlKeyDown() then
            OpenBarRecipe(block.itemKey)
        elseif mouseButton == "LeftButton" then
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

-- Whether the tracker still lists the section (it can drop sections when
-- it rebuilds; BarTab then puts them back).
function IsInTracker(module)
    local list = ObjectiveTrackerFrame and ObjectiveTrackerFrame.modules
    if type(list) == "table" then
        for _, other in pairs(list) do
            if other == module then return true end
        end
        return false
    end
    local map = ObjectiveTrackerManager and ObjectiveTrackerManager.moduleToContainerMap
    if type(map) == "table" then return map[module] ~= nil end
    return true -- can't tell on this client
end

function ReattachLostSections()
    for _, module in pairs(sectionModules) do
        if not IsInTracker(module) then
            pcall(ObjectiveTrackerManager.SetModuleContainer, ObjectiveTrackerManager, module, ObjectiveTrackerFrame)
            reattachCount = (reattachCount or 0) + 1
        end
    end
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
-- Returns false if a new section couldn't be made right now (the game can
-- refuse, e.g. during combat); the sections already made keep working and
-- BarTab tries again shortly.
function EnsureSectionModules()
    local added, complete = false, true
    for _, name in ipairs(GetSectionNames()) do
        if not sectionModules[name] then
            local module = CreateSectionModule(name)
            if module then
                sectionModules[name] = module
                added = true
            else
                complete = false
            end
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

    return complete
end

-- Joining the tracker at login. The tracker may not be ready that early (or
-- after a client update, a little later than before), so keep trying for
-- about 30 seconds before falling back to the plain list.
trackerSetupAttempts = 0
function TrySetUpTracker(attempt)
    trackerSetupAttempts = attempt
    if SetUpTracker() then
        UpdateBars()
        return
    end
    if attempt < 15 then
        C_Timer.After(2, function() TrySetUpTracker(attempt + 1) end)
    else
        Print("Couldn't add a section to the objective tracker; using standalone bars. /bartab window on shows them in BarTab's own window instead.")
    end
    UpdateBars()
end

-- /bartab debug tracker: how BarTab is showing its bars, for bug reports.
function DebugTracker(quiet)
    local lines = {}
    if not quiet then
        settings.debugLog = { "BarTab debug tracker" }
        lines = settings.debugLog
    end
    local function Line(text)
        if not quiet then Print(text) end
        table.insert(lines, text)
    end
    local tracker = ObjectiveTrackerFrame
    Line(("mode setting=%s; own window=%s; tracker sections=%s (after %d tries); hidden tracker=%s"):format(
        tostring(settings.displayMode or "auto"), tostring(panelActive), tostring(trackerAvailable),
        trackerSetupAttempts or 0, tostring(IsTrackerHidden())))
    if tracker then
        Line(("tracker: shown=%s alpha=%s height=%s manager=%s setContainer=%s"):format(
            tostring(tracker:IsShown()), tostring(tracker.GetAlpha and tracker:GetAlpha()),
            tostring(tracker.GetHeight and math.floor(tracker:GetHeight())),
            tostring(ObjectiveTrackerManager ~= nil),
            tostring(ObjectiveTrackerManager and ObjectiveTrackerManager.SetModuleContainer ~= nil)))
        local flags = {}
        for _, field in ipairs({ "isUpdating", "isDirty", "isCollapsed", "needsUpdate" }) do
            if tracker[field] ~= nil then flags[#flags + 1] = field .. "=" .. tostring(tracker[field]) end
        end
        if type(tracker.modules) == "table" then
            local count, shown = 0, 0
            for _, module in pairs(tracker.modules) do
                count = count + 1
                if module.IsShown and module:IsShown() then shown = shown + 1 end
            end
            flags[#flags + 1] = ("sections=%d shown=%d"):format(count, shown)
        end
        if #flags > 0 then Line("tracker state: " .. table.concat(flags, " ")) end
        -- Where things are: if the tracker stops laying itself out, a
        -- section's place stops matching the sections above it.
        local function Round(value) return value and math.floor(value + 0.5) or nil end
        local function Place(frame)
            local ok, top, bottom = pcall(function() return frame:GetTop(), frame:GetBottom() end)
            if not ok then return "?" end
            return ("top=%s bottom=%s"):format(tostring(Round(top)), tostring(Round(bottom)))
        end
        Line("tracker place: " .. Place(tracker))
        local switches = {}
        for field, value in pairs(tracker) do
            if type(value) == "boolean" and type(field) == "string" then
                switches[#switches + 1] = field .. "=" .. tostring(value)
            end
        end
        table.sort(switches)
        if #switches > 0 then Line("tracker switches: " .. table.concat(switches, " ")) end
        if type(tracker.modules) == "table" then
            for _, module in pairs(tracker.modules) do
                if module.IsShown and module:IsShown() then
                    local name = module.sectionName
                    if not name and module.Header and module.Header.Text and module.Header.Text.GetText then
                        name = module.Header.Text:GetText()
                    end
                    Line(("  section %s: %s height=%s collapsed=%s dirty=%s"):format(tostring(name or module.headerText or "?"),
                        Place(module), tostring(module.GetHeight and Round(module:GetHeight())),
                        tostring(module.collapsed or module.isCollapsed), tostring(module.isDirty)))
                end
            end
        end
    else
        Line("tracker: ObjectiveTrackerFrame missing")
    end
    local names = GetSectionNames()
    Line("sections with bars: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    for name, module in pairs(sectionModules) do
        Line(("  %s: shown=%s attached=%s in tracker=%s height=%s collapsed=%s"):format(name,
            tostring(module:IsShown()), tostring(IsAttached(module) and true or false),
            tostring(IsInTracker(module)),
            tostring(module.GetHeight and math.floor(module:GetHeight())),
            tostring(settings.collapsed and settings.collapsed[name])))
    end
    -- Every bar: where it belongs, whether BarTab wants it shown, and
    -- whether a bar for it is actually on screen.
    for _, key in ipairs(GetSortedKeys()) do
        local item = trackedItems[key]
        local visible = false
        for barID, bar in pairs(barsByKey) do
            if bar.itemKey == key and bar:IsVisible() then visible = true end
        end
        local ok, group = pcall(GetGroup, item)
        Line(("  bar %s [%s / %s] order=%s wanted=%s inactive=%s on screen=%s"):format(
            key, tostring(GetSection(item)), ok and tostring(group) or "?", tostring(item.order),
            tostring(IsShown(item)), tostring(item.inactive and true or false), tostring(visible)))
    end
    local standalone = 0
    for barID, bar in pairs(barsByKey) do
        if barID:sub(1, 11) == "standalone\0" and bar:IsShown() then standalone = standalone + 1 end
    end
    Line("plain-list bars showing: " .. standalone .. "; sections put back this session: " .. (reattachCount or 0))
    if not quiet then Line("Saved for bug reports with /reload.") end
    return lines
end

-- Quiet snapshots of the tracker (around level-ups and /bartab refresh),
-- kept in the saved variables for bug reports: the last few only.
function SnapshotTracker(reason)
    settings.trackerSnapshots = settings.trackerSnapshots or {}
    local lines = DebugTracker(true)
    table.insert(lines, 1, ("%s %s; level %s; in combat=%s"):format(
        date and date("%Y-%m-%d %H:%M:%S") or "", reason,
        tostring(UnitLevel and UnitLevel("player")), tostring(InCombatLockdown())))
    table.insert(settings.trackerSnapshots, 1, lines)
    while #settings.trackerSnapshots > 6 do table.remove(settings.trackerSnapshots) end
end

-- When any other tracker section (Quests, All Objectives...) collapses or
-- expands, the game doesn't always move BarTab's sections to match, which
-- leaves them where they were (e.g. stuck at the bottom with a gap above).
-- Redraw them right after. Hooked once per section, as sections appear.
collapseHooked = setmetatable({}, { __mode = "k" })
collapseStates = setmetatable({}, { __mode = "k" })

-- /bartab debug perf: how much work BarTab is doing.
perf = { since = GetTime(), updates = 0, ms = 0, redraws = 0, redrawMs = 0, collapses = 0 }
function PerfClock()
    return debugprofilestop and debugprofilestop() or nil
end

-- Runs the game's tracker redraw, timed and marked as BarTab's own.
function ForceTrackerRedraw(tracker, where)
    local started = PerfClock()
    forcingRedraw = true
    local ok, err = pcall(tracker.Update, tracker)
    forcingRedraw = false
    perf.redraws = perf.redraws + 1
    if started then perf.redrawMs = perf.redrawMs + (PerfClock() - started) end
    lastForcedRedraw = GetTime()
    if not ok then ReportError(where, err) end
end
function HookTrackerCollapse()
    if not hooksecurefunc then return end
    local function Hook(target)
        if type(target) ~= "table" or collapseHooked[target] then return end
        for _, own in pairs(sectionModules) do
            if own == target then return end
        end
        -- Only a real change, and not one made while BarTab itself is
        -- redrawing the tracker (the redraw re-applies every section's
        -- state; reacting to that would start the next redraw, and so on).
        local function Changed(self)
            if forcingRedraw then return end
            local state = (self.collapsed or self.isCollapsed) and true or false
            if collapseStates[self] == state then return end
            collapseStates[self] = state
            perf.collapses = perf.collapses + 1
            RequestUpdate(0.05)
        end
        collapseStates[target] = (target.collapsed or target.isCollapsed) and true or false
        for _, method in ipairs({ "SetCollapsed", "ToggleCollapsed" }) do
            if type(target[method]) == "function" then
                pcall(hooksecurefunc, target, method, Changed)
            end
        end
        collapseHooked[target] = true
    end
    local tracker = ObjectiveTrackerFrame
    if not tracker then return end
    Hook(tracker)
    if type(tracker.modules) == "table" then
        for _, module in pairs(tracker.modules) do Hook(module) end
    end
end

-- Puts back any section the tracker dropped and redraws every bar.
-- full (/bartab refresh, out of combat): also ask the game's tracker to lay
-- every section out again, in case it has stopped doing that itself.
function RefreshTracker(full)
    if trackerAvailable and not panelActive then ReattachLostSections() end
    UpdateBars()
    local tracker = ObjectiveTrackerFrame
    if full and trackerAvailable and not panelActive and not InCombatLockdown()
        and tracker and type(tracker.Update) == "function" then
        ForceTrackerRedraw(tracker, "refresh")
    end
end

-- The tracker has stopped updating after a level-up a few times. Note how it
-- looks shortly after one, then redraw BarTab's sections as a precaution.
levelWatcher = CreateFrame("Frame")
pcall(levelWatcher.RegisterEvent, levelWatcher, "PLAYER_LEVEL_UP")
levelWatcher:SetScript("OnEvent", function()
    C_Timer.After(3, function() Safe("level-up", SnapshotTracker)("level-up +3s") end)
    C_Timer.After(15, function()
        Safe("level-up", SnapshotTracker)("level-up +15s, before redraw")
        Safe("level-up", RefreshTracker)(true)
    end)
end)

-- A section's "needs a redraw" flag (isDirty: Quests, BarTab's own) can get
-- stuck on, most often after a level-up; then nothing redraws and the
-- tracker freezes until a /reload. (The tracker's own "dirty" is on all the
-- time in this client, so it says nothing.) Check every few seconds: if a
-- section's flag is still on at the next check, run the redraw (out of
-- combat; after combat otherwise).
trackerStuckChecks = 0
function AnySectionStuck(tracker)
    if type(tracker.modules) ~= "table" then return false end
    for _, module in pairs(tracker.modules) do
        if module.isDirty == true and module.IsShown and module:IsShown() then return true end
    end
    return false
end

function CheckTrackerStuck()
    local tracker = ObjectiveTrackerFrame
    if not (trackerAvailable and not panelActive and tracker
        and type(tracker.Update) == "function") then
        trackerStuckChecks = 0
        return
    end
    if not AnySectionStuck(tracker) then
        trackerStuckChecks = 0
        return
    end
    trackerStuckChecks = trackerStuckChecks + 1
    if trackerStuckChecks < 2 then return end
    if InCombatLockdown() then
        pcall(trackerWatch.RegisterEvent, trackerWatch, "PLAYER_REGEN_ENABLED")
        return
    end
    trackerStuckChecks = 0
    settings.trackerUnstuck = (settings.trackerUnstuck or 0) + 1
    Safe("tracker watch", SnapshotTracker)("stuck tracker, before redraw")
    ForceTrackerRedraw(tracker, "tracker watch")
end

-- BarTab asks for a redraw by marking its sections; in this client the
-- tracker doesn't always act on that (its own "needs a redraw" flag stays
-- on, so a new request doesn't schedule anything), and new counts then wait
-- for something else (a quest update) to redraw it. Shortly after asking,
-- check that BarTab's sections were drawn, and draw them if not.
function BarTabSectionsWaiting()
    for _, module in pairs(sectionModules) do
        if module.isDirty == true and module.IsShown and module:IsShown() then return true end
    end
    return false
end

function RedrawIfWaiting()
    redrawCheckPending = false
    local tracker = ObjectiveTrackerFrame
    if not (trackerAvailable and not panelActive and tracker and type(tracker.Update) == "function") then return end
    if not BarTabSectionsWaiting() then return end
    if InCombatLockdown() then
        pcall(trackerWatch.RegisterEvent, trackerWatch, "PLAYER_REGEN_ENABLED")
        return
    end
    -- At most one forced redraw a second; a later check picks up the rest.
    if lastForcedRedraw and GetTime() - lastForcedRedraw < 1 then
        CheckRedrawSoon(1)
        return
    end
    settings.trackerNudges = (settings.trackerNudges or 0) + 1
    ForceTrackerRedraw(tracker, "tracker redraw")
end

function CheckRedrawSoon(delay)
    if redrawCheckPending then return end
    redrawCheckPending = true
    C_Timer.After(delay or 0.3, function() Safe("tracker redraw", RedrawIfWaiting)() end)
end

trackerWatch = CreateFrame("Frame")
trackerWatch:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    C_Timer.After(0.5, function() Safe("tracker redraw", RedrawIfWaiting)() end)
    C_Timer.After(1, function() Safe("tracker watch", CheckTrackerStuck)() end)
end)
if C_Timer.NewTicker then
    C_Timer.NewTicker(4, function() Safe("tracker watch", CheckTrackerStuck)() end)
end

-- Retry a section that couldn't be made: soon, and again once combat ends.
sectionRetry = CreateFrame("Frame")
sectionRetry:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    RequestUpdate(0.5)
end)
function RetrySectionsLater()
    if sectionRetryPending then return end
    sectionRetryPending = true
    C_Timer.After(3, function()
        sectionRetryPending = false
        RequestUpdate(0)
    end)
    pcall(sectionRetry.RegisterEvent, sectionRetry, "PLAYER_REGEN_ENABLED")
end

-- Hides the fallback bars (used only when tracker sections can't be made at
-- all), so they never show alongside the tracker or BarTab's window.
function HideStandaloneBars()
    for barID, bar in pairs(barsByKey) do
        if barID:sub(1, 11) == "standalone\0" then bar:Hide() end
    end
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
        GameTooltip:AddLine(settings.panelLocked and "Window locked (unlock in /bartab config)"
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
-- ready), BarTab says so in chat and,
-- optionally, with a sound and an on-screen message.

goalReached = {}   -- item key -> whether it was at its goal last check
lastAlertTime = {} -- item key -> GetTime() of its last alert

function IsGoalReached(item)
    if item.container then
        local _, full = GetFillState(item)
        return full
    end
    return GetBarCount(item) >= item.goal
end

function AlertText(item)
    if item.container then
        return item.container.name .. " is ready: " .. item.goal .. " " .. item.name
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
        HideStandaloneBars()
        UpdatePanel()
    elseif trackerAvailable then
        HideStandaloneBars()
        if not EnsureSectionModules() then RetrySectionsLater() end
        ReattachLostSections()
        Safe("tracker hooks", HookTrackerCollapse)()
        for _, module in pairs(sectionModules) do
            module:MarkDirty()
        end
        CheckRedrawSoon()
    else
        UpdateStandaloneBars()
    end

    CheckGoalAlerts()
    Safe("recipe list", RefreshRecipeListMarks)()
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
    lastDragResult = nil
    dragState = { key = bar.itemKey, bar = bar }
    bar:SetAlpha(0.6)
    GameTooltip:Hide()
    if SetCursor then SetCursor("UI_MOVE_CURSOR") end
    dragDriver:Show()
end

EndDrag = function()
    local state = dragState
    -- Already ended (by the safety net below, before the bar's mouse-up):
    -- give the same answer again.
    if not state then return lastDragResult ~= false end
    dragState = nil
    dragDriver:Hide()

    for _, bar in ipairs(bars) do
        bar.dropHighlight:Hide()
    end
    state.bar:SetAlpha(1)
    if ResetCursor then ResetCursor() end

    -- Returns false only when let go on the bar it started on: a Ctrl-click.
    local target = GetBarUnderCursor()
    if target and target.itemKey and target.itemKey ~= state.key
        and target.section == state.bar.section
        and target.group == state.bar.group then
        MoveItem(state.key, target.itemKey)
        lastDragResult = true
        return true
    end
    lastDragResult = target == nil or target.itemKey ~= state.key
    return lastDragResult
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

-- Time every refresh, for /bartab debug perf.
do
    local inner = UpdateBars
    UpdateBars = function(...)
        local started = PerfClock()
        inner(...)
        perf.updates = perf.updates + 1
        if started then perf.ms = perf.ms + (PerfClock() - started) end
    end
end

-- Remember bars that leave the list, for /bartab undo.
do
    local inner = UpdateBars
    UpdateBars = function(...)
        inner(...)
        Safe("undo", NoteRemovedBars)()
    end
end

function DebugPerf()
    local minutes = math.max((GetTime() - perf.since) / 60, 1 / 60)
    local function Rate(n) return ("%.1f/min"):format(n / minutes) end
    Print(("In the last %.0f min: %d bar refreshes (%s, %.1f ms total, %.2f ms each); %d forced tracker redraws (%s, %.1f ms total); %d section collapses noticed."):format(
        minutes, perf.updates, Rate(perf.updates), perf.ms, perf.updates > 0 and perf.ms / perf.updates or 0,
        perf.redraws, Rate(perf.redraws), perf.redrawMs, perf.collapses))
    Print("Type /bartab debug perf reset to start counting again.")
end

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

-- For /bartab assign: the item is either a leading link or the text before the
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
        return nil, nil, nil, "Could not determine stack size. Specify a max, e.g. /bartab track Light Leather 20."
    end

    return name, 0, stackSize
end
