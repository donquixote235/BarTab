-- BarTab: fill-up items (Waylaid Crates) and item helpers.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

-- Item helpers ---------------------------------------------------------------

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

-- Fill-up items ("Waylaid Crate") --------------------------------------------
--
-- Items whose "Use:" text lists bundles that fill them, e.g.
-- "Fill the crate with any bundle from the following list: - 40 Linen Cloth
--  - 20 Light Leather". Each listed bundle becomes a bar under the item's name
-- in the "BarTab: Items" section; clicking a full bar uses the item.

-- How far this bundle is: count, and whether it's enough to fill the item.
GetFillState = function(item)
    local count = CountItem(item)
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
            and CountContainer(item.container) > 0 then
            local _, full = GetFillState(item)
            if full and not FindFullStack(item.name, item.goal) then
                MergeStacks(item.name)
                return
            end
        end
    end
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
