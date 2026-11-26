-- BarTab: quest item state, combining pieces, fill-up items.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

-- Quest items ----------------------------------------------------------------

-- "ready": every item the quest needs is in your bags.
-- "waiting", name: this item is complete but another one isn't.
-- nil: this item isn't complete yet.
-- Whether an item has a "Use:" effect. Tries the name, then the item ID
-- (some clients only answer for IDs), then whether the game calls it usable.
function ItemHasUse(name)
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local itemID = knownItemIDs[string.lower(name)]

    if getSpell then
        local ok, spell = pcall(getSpell, name)
        if ok and spell then return true end
        if itemID then
            ok, spell = pcall(getSpell, itemID)
            if ok and spell then return true end
        end
    end

    local isUsable = (C_Item and C_Item.IsUsableItem) or IsUsableItem
    if isUsable and itemID then
        local ok, usable = pcall(isUsable, itemID)
        if ok and usable then return true end
    end
    return false
end

function GetItemSpellName(name)
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not getSpell then return nil end
    local itemID = knownItemIDs[string.lower(name)]
    local ok, spell = pcall(getSpell, itemID or name)
    return ok and spell or nil
end

-- "Shredder Operating Manual - Chapter 3" -> "shredder operating manual"
function NameStem(name)
    local stem = name and name:match("^(.-)%s*[%-:]%s")
    if stem and #stem >= 6 then
        return string.lower(stem)
    end
end

-- Items in your bags that build toward one of the quest's objectives without
-- being objectives themselves, e.g. "... Manual - Page 9" pages that combine
-- into the "... Manual - Chapter 3" the quest asks for. Matched by the shared
-- name before " - " and required to have a "Use:" effect.
function FindRelatedUseItems(quest)
    local stems, objectiveNames = {}, {}
    for _, req in ipairs(quest.items or {}) do
        objectiveNames[string.lower(req.name)] = true
        local stem = NameStem(req.name)
        if stem then stems[stem] = true end
    end
    if not next(stems) then return {} end

    local found, seen = {}, {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local link = C_Container.GetContainerItemLink(bag, slot)
            local name = link and link:match("%[(.-)%]")
            local lower = name and string.lower(name)
            if lower and not seen[lower] and not objectiveNames[lower] then
                seen[lower] = true
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID then knownItemIDs[lower] = itemID end
                local stem = NameStem(name)
                if stem and stems[stem] and ItemHasUse(name) then
                    found[#found + 1] = name
                end
            end
        end
    end
    table.sort(found)
    return found
end

-- Which related item to use for an objective that isn't complete yet: one
-- whose "Use:" effect mentions the objective (e.g. "Chapter 3") if possible,
-- otherwise the first one.
PickRelatedUseItem = function(item)
    local related = FindRelatedUseItems(item.quest)
    if #related == 0 then return nil end

    local wanted = string.lower(item.name)
    local suffix = wanted:match("[%-:]%s*(.+)$")
    for _, name in ipairs(related) do
        local spell = GetItemSpellName(name)
        spell = spell and string.lower(spell)
        if spell and (spell:find(wanted, 1, true)
            or (suffix and spell:find(suffix, 1, true))) then
            return name
        end
    end
    return related[1]
end

-- Pieces that combine into a quest objective ------------------------------
--
-- e.g. "Shredder Operating Manual - Page 3", whose tooltip says
-- "Use: Bind pages 1-4 into Chapter 1 of the Shredder Operating Manual."
-- BarTab reads that once per quest (looking at items with nearby IDs, so it
-- finds pages you don't have yet) and remembers which pages each objective
-- needs.

learningPieces = {} -- quest table -> true while a lookup is running

function EscapePattern(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

function GetUseLine(itemID)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or not data or not data.lines then return nil end
    for _, line in ipairs(data.lines) do
        if line.leftText and line.leftText:find("^Use:") then
            return line.leftText
        end
    end
end

-- "Shredder Operating Manual - Page 3" -> "Page", 3
function SplitPieceName(name)
    local word, number = name:match("[%-:]%s*(%a[%a ]-)%s*(%d+)%s*$")
    return word, tonumber(number)
end

function LearnPieceFromItem(quest, itemID, name)
    local word, number = SplitPieceName(name)
    local useLine = number and GetUseLine(itemID)
    if not useLine then return end

    local first, last = useLine:match("(%d+)%s*%-%s*(%d+)")
    first, last = tonumber(first), tonumber(last)
    if not first or not last or last < first then return end

    local lowerLine = string.lower(useLine)
    for _, req in ipairs(quest.items or {}) do
        local suffix = string.lower(req.name):match("[%-:]%s*(.+)$")
        if suffix and lowerLine:find(EscapePattern(suffix) .. "%f[%D]") then
            quest.pieces = quest.pieces or {}
            quest.pieces[string.lower(req.name)] = {
                first = first,
                last = last,
                stem = NameStem(name),
                word = word,
            }
            return
        end
    end
end

function LearnQuestPieces(quest)
    if learningPieces[quest] or quest.piecesLearned then return end
    if not (C_Item and C_Item.GetItemNameByID) then return end

    local stems = {}
    for _, req in ipairs(quest.items or {}) do
        local stem = NameStem(req.name)
        if stem then stems[stem] = true end
    end
    if not next(stems) then
        quest.piecesLearned = true -- nothing that could have pieces
        return
    end

    -- Start from the IDs of any of the quest's items or pieces in your bags.
    local bases = {}
    for _, req in ipairs(quest.items) do
        GetItemCount(req.name)
        local id = knownItemIDs[string.lower(req.name)]
        if id then bases[#bases + 1] = id end
    end
    for _, name in ipairs(FindRelatedUseItems(quest)) do
        local id = knownItemIDs[string.lower(name)]
        if id then bases[#bases + 1] = id end
    end
    if #bases == 0 then return end

    learningPieces[quest] = true
    local ids = {}
    for _, base in ipairs(bases) do
        for id = base - 20, base + 20 do
            if not ids[id] then
                ids[id] = true
                if C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, id)
                end
            end
        end
    end

    -- Item data loads in the background; read it a moment later.
    C_Timer.After(2, function()
        for id in pairs(ids) do
            local name = C_Item.GetItemNameByID(id)
            local stem = name and NameStem(name)
            if stem and stems[stem] then
                LearnPieceFromItem(quest, id, name)
            end
        end
        learningPieces[quest] = nil
        quest.piecesLearned = true
        UpdateBars()
    end)
end

-- For an objective built from pieces: how many of its pieces you have.
-- Returns nil if the objective isn't made of pieces (or not known yet).
GetPieceProgress = function(item)
    local quest = item.quest
    if not quest then return nil end
    if not quest.piecesLearned then
        LearnQuestPieces(quest)
    end

    local info = quest.pieces and quest.pieces[string.lower(item.name)]
    if not info then return nil end

    local objectiveNames = {}
    for _, req in ipairs(quest.items or {}) do
        objectiveNames[string.lower(req.name)] = true
    end

    local have, useName = {}, nil
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local link = C_Container.GetContainerItemLink(bag, slot)
            local name = link and link:match("%[(.-)%]")
            if name and not objectiveNames[string.lower(name)]
                and NameStem(name) == info.stem then
                local word, number = SplitPieceName(name)
                if number and word == info.word
                    and number >= info.first and number <= info.last then
                    have[number] = true
                    useName = useName or name
                end
            end
        end
    end

    local owned, missing = 0, {}
    for number = info.first, info.last do
        if have[number] then
            owned = owned + 1
        else
            missing[#missing + 1] = number
        end
    end

    return {
        owned = owned,
        required = info.last - info.first + 1,
        missing = missing,
        word = string.lower(info.word or "piece"),
        useName = useName,
    }
end

-- Fill-up items ("Waylaid Crate") --------------------------------------------
--
-- Items whose "Use:" text lists bundles that fill them, e.g.
-- "Fill the crate with any bundle from the following list: - 40 Linen Cloth
--  - 20 Light Leather". Each listed bundle becomes a bar under the item's name
-- in the "BarTab: Items" section; clicking a full bar uses the item.

-- How far this bundle is: count, and whether it's enough to fill the item.
GetFillState = function(item)
    local count = GetItemCount(item.name)
    return count, count >= item.goal
end

-- Every bag stack of an item: { {bag=, slot=, count=}, ... }, biggest first.
function GetStacks(name)
    local wanted = string.lower(name)
    local stacks = {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local link = C_Container.GetContainerItemLink(bag, slot)
            local itemName = link and link:match("%[(.-)%]")
            if itemName and string.lower(itemName) == wanted then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                stacks[#stacks + 1] = { bag = bag, slot = slot,
                    count = (info and info.stackCount) or 1,
                    locked = info and info.isLocked }
            end
        end
    end
    table.sort(stacks, function(a, b) return a.count > b.count end)
    return stacks
end

-- A stack holding at least `amount` (the crate takes a bundle from one stack).
FindFullStack = function(name, amount)
    local best
    for _, stack in ipairs(GetStacks(name)) do
        if stack.count >= amount and (not best or stack.count < best.count) then
            best = stack
        end
    end
    return best
end

-- Moves the next-biggest stack onto the biggest one. One move per click:
-- the game locks both stacks until the move finishes.
function MergeStacks(name)
    local stacks = GetStacks(name)
    if #stacks < 2 then return false end
    if InCombatLockdown() or (CursorHasItem and CursorHasItem()) then return false end
    local target, source = stacks[1], stacks[2]
    if target.locked or source.locked then return false end -- a move is still finishing
    C_Container.PickupContainerItem(source.bag, source.slot)
    C_Container.PickupContainerItem(target.bag, target.slot)
    if CursorHasItem and CursorHasItem() then
        -- Target stack was already full; put the rest back.
        C_Container.PickupContainerItem(source.bag, source.slot)
        return false
    end
    return true
end

-- Combines stacks ahead of time for any ready fill-up bar whose bundle is
-- split over stacks, so a single click on the bar fills the item. One move
-- per call; each bag update (when the move lands) triggers the next.
function AutoMergeForContainers()
    if settings.autoStack == false then return end
    if InCombatLockdown() or (CursorHasItem and CursorHasItem()) then return end
    for _, item in pairs(trackedItems) do
        local focus = item.container and settings.containerFocus
            and settings.containerFocus[item.container.id]
        if item.container and not item.inactive
            and (not focus or focus == string.lower(item.name))
            and GetItemCount(item.container.name) > 0 then
            local _, full = GetFillState(item)
            if full and not FindFullStack(item.name, item.goal) then
                MergeStacks(item.name)
                return
            end
        end
    end
end

GetQuestState = function(item)
    if not item.quest or GetItemCount(item.name) < item.goal then
        return nil
    end
    for _, req in ipairs(item.quest.items or {}) do
        if GetItemCount(req.name) < req.count then
            return "waiting", req.name
        end
    end
    return "ready"
end

-- The item to /use: the quest's own special item if it has one, otherwise
-- whichever of the quest's items has a "Use:" effect.
GetQuestUseItem = function(item)
    local quest = item.quest
    if not quest then return nil end

    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID
        and GetQuestLogSpecialItemInfo then
        local index = C_QuestLog.GetLogIndexForQuestID(quest.id)
        local link = index and GetQuestLogSpecialItemInfo(index)
        local name = link and link:match("%[(.-)%]")
        if name then return name end
    end

    for _, req in ipairs(quest.items or {}) do
        if GetItemCount(req.name) > 0 and ItemHasUse(req.name) then
            return req.name
        end
    end

    -- Nothing among the objectives; pieces that combine into one count too.
    return PickRelatedUseItem(item)
end

function GetRecipeOutput(recipeID)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
        return nil
    end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if ok and type(schematic) == "table" and schematic.outputItemID then
        return schematic.outputItemID, tonumber(schematic.quantityMin) or 1
    end
end

-- How many crafts stay within the bar:
--  * item is an ingredient: crafts using only the items up to the bar's max
--    (the blue blocks), e.g. 16 Light Leather on a 0-4 bar -> 1 craft.
--  * item is what the recipe makes: crafts needed to fill the bar without
--    going over, e.g. 12 / 20 Medium Leather -> 8 crafts.
-- Always capped by what your other ingredients allow. nil if unknown.
GetBarCraftCount = function(item)
    if not (item and item.recipeID) then return nil end

    local craftable = GetCraftableCount(item.recipeID)
    if not craftable then return nil end

    local count = GetBarCount(item) -- this bar's share if the material is shared

    local perCraft = GetReagentQuantity(item.recipeID, item.name)
    if perCraft and perCraft > 0 then
        return math.min(craftable, math.floor(math.min(count, item.goal) / perCraft))
    end

    local outputID, perOutput = GetRecipeOutput(item.recipeID)
    local outputName = outputID and GetItemNameByID(outputID)
    if outputName and string.lower(outputName) == string.lower(item.name) then
        local missing = math.max(0, item.goal - count)
        return math.min(craftable, math.floor(missing / math.max(1, perOutput)))
    end
end
