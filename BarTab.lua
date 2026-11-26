-- BarTab: core: saved data, item counting, recipes, tooltips.
--
-- BarTab is split over several files (listed in BarTab.toc). They all
-- share one private table as their global environment, so what one file
-- defines is visible to the others without adding anything to _G.
-- Names not found there fall back to the real globals.
local addonName, ns = ...
setmetatable(ns, { __index = _G })
setfenv(1, ns)
ADDON_NAME = addonName


-- Replaced with the saved BarTabDB table once ADDON_LOADED fires.
trackedItems = {}
-- Replaced with the saved BarTabSettings table once ADDON_LOADED fires.
settings = {}
bars = {}        -- every bar ever created, for iteration
barsByKey = {}   -- section + item key -> its bar
updatePending = false
trackerSetupTried = false
-- (The settings window, minimap button and help text live in do ... end
-- blocks so their helpers don't count toward Lua's 200-local limit.)

-- Crafting bars assigned to a recipe are labeled with what you're making
-- (e.g. "Hillman's Cloak") while still counting the material (Heavy Leather).
function DisplayName(item)
    return item.label or item.name
end

function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBarTab:|r " .. message)
end

-- Errors in code BarTab runs inside Blizzard's own updates (the objective
-- tracker) are caught, so they can't stop that update partway and freeze
-- the tracker. They're kept (last 5) for /bartab errors, and mentioned once per
-- session.
errorNoticeShown = false

function ReportError(where, err)
    local log = settings and settings.errorLog
    if settings then
        settings.errorLog = settings.errorLog or {}
        log = settings.errorLog
        table.insert(log, 1, {
            where = where,
            message = tostring(err),
            when = date and date("%Y-%m-%d %H:%M") or "",
            version = C_AddOns and C_AddOns.GetAddOnMetadata
                and C_AddOns.GetAddOnMetadata("BarTab", "Version") or nil,
        })
        while #log > 5 do table.remove(log) end
    end
    if not errorNoticeShown then
        errorNoticeShown = true
        Print("hit an error while updating (" .. where .. "); your tracker keeps working. "
            .. "Type /bartab errors to see it.")
    end
end

-- Runs fn safely: an error is reported instead of passed on.
function Safe(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ReportError(where, err) end
    end
end

function CountOwned(itemID)
    if C_Item and C_Item.GetItemCount then
        -- Bags plus reagent bank (if the client has one), like crafting uses.
        return C_Item.GetItemCount(itemID, false, false, true) or 0
    end
    if _G.GetItemCount then
        return _G.GetItemCount(itemID) or 0
    end
    return 0
end

-- Works out how many crafts the current bag contents allow, straight from
-- the recipe's required reagents. The game's own GetCraftableCount is cached
-- and can lag behind bag changes, so it's only used as a fallback.
function ComputeCraftableCount(recipeID)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
        return nil
    end

    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table"
        or type(schematic.reagentSlotSchematics) ~= "table" then
        return nil
    end

    local result
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local needed = tonumber(slot.quantityRequired) or 0
        if slot.required ~= false and needed > 0 and slot.reagents then
            local owned = 0
            for _, reagent in ipairs(slot.reagents) do
                if reagent.itemID then
                    owned = owned + CountOwned(reagent.itemID)
                end
            end
            local crafts = math.floor(owned / needed)
            if not result or crafts < result then
                result = crafts
            end
        end
    end

    return result
end

function GetItemNameByID(itemID)
    if C_Item and C_Item.GetItemNameByID then
        return C_Item.GetItemNameByID(itemID)
    end
    if C_Item and C_Item.GetItemInfo then
        return (C_Item.GetItemInfo(itemID))
    end
end

-- Bars named "item 1529" (made before the game had loaded that item) get
-- their real name once it's known: at login, and when the game reports the
-- item has loaded. The bar's key holds its name, so it moves to the new key;
-- anything pointing at the old key or name follows. If a bar by the real
-- name already exists for the same recipe, the two are merged.
placeholderPending = {} -- itemID -> true while waiting for its name

function FixPlaceholderNames()
    if not trackedItems then return end
    local found = {}
    for key, item in pairs(trackedItems) do
        local id = tonumber((item.name or ""):match("^item (%d+)$"))
        if id then
            local ok, real = pcall(GetItemNameByID, id)
            if ok and real and real ~= "" then
                found[#found + 1] = { key = key, item = item, id = id, real = real }
                placeholderPending[id] = nil
            else
                placeholderPending[id] = true
                if C_Item and C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, id)
                end
            end
        end
    end
    if #found == 0 then return end
    for _, entry in ipairs(found) do
        local item, oldKey = entry.item, entry.key
        local oldLower, newLower = string.lower(item.name), string.lower(entry.real)
        item.name = entry.real
        item.itemID = item.itemID or entry.id
        knownItemIDs[newLower] = entry.id
        local newKey = oldKey
        if oldKey:sub(1, #oldLower) == oldLower then
            newKey = newLower .. oldKey:sub(#oldLower + 1)
        end
        if newKey ~= oldKey then
            local existing = trackedItems[newKey]
            trackedItems[oldKey] = nil
            if existing then
                existing.goal = math.max(existing.goal or 0, item.goal or 0)
            else
                trackedItems[newKey] = item
            end
            for _, other in pairs(trackedItems) do
                if other.chainFor == oldKey then other.chainFor = newKey end
            end
        end
        if item.recipeID and settings.recipeFocus and settings.recipeFocus[item.recipeID] == oldLower then
            settings.recipeFocus[item.recipeID] = newLower
        end
        if item.container and settings.containerFocus
            and settings.containerFocus[item.container.id] == oldLower then
            settings.containerFocus[item.container.id] = newLower
        end
    end
    UpdateBars()
end

-- The recipe's required ingredients for one craft:
-- { {name=, have=, need=}, ... }, or nil if the recipe can't be read.
function GetRecipeReagents(recipeID)
    if not (recipeID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
        return nil
    end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table"
        or type(schematic.reagentSlotSchematics) ~= "table" then
        return nil
    end

    local list = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local need = tonumber(slot.quantityRequired) or 0
        if slot.required ~= false and need > 0 and slot.reagents and slot.reagents[1] then
            local have, name = 0, nil
            for _, reagent in ipairs(slot.reagents) do
                if reagent.itemID then
                    have = have + CountOwned(reagent.itemID)
                    name = name or GetItemNameByID(reagent.itemID)
                end
            end
            if not name and C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, slot.reagents[1].itemID)
            end
            list[#list + 1] = {
                name = name or ("item " .. tostring(slot.reagents[1].itemID)),
                itemID = slot.reagents[1].itemID,
                have = have,
                need = need,
            }
        end
    end
    return list
end

-- How many of the named item one craft of the recipe uses (nil if none).
function GetReagentQuantity(recipeID, itemName)
    if not (recipeID and itemName and C_TradeSkillUI
        and C_TradeSkillUI.GetRecipeSchematic) then
        return nil
    end

    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table"
        or type(schematic.reagentSlotSchematics) ~= "table" then
        return nil
    end

    local wanted = string.lower(itemName)
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        for _, reagent in ipairs(slot.reagents or {}) do
            local name = reagent.itemID and GetItemNameByID(reagent.itemID)
            if name and string.lower(name) == wanted then
                return tonumber(slot.quantityRequired)
            end
        end
    end
end

function GetCraftableCount(recipeID)
    if not recipeID then return nil end

    local computed = ComputeCraftableCount(recipeID)
    if computed then return computed end

    if C_TradeSkillUI and C_TradeSkillUI.GetCraftableCount then
        local ok, amount = pcall(C_TradeSkillUI.GetCraftableCount, recipeID)
        if ok and type(amount) == "number" then
            return amount
        end
    end
end

function ShowBarTooltip(owner)
    local item = trackedItems[owner.itemKey]
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")

    if item and item.container then
        GameTooltip:SetText(item.container.name)
        AddStorageLines(item.name)
        AddSessionLines(item)
        GameTooltip:AddLine("Fill with any one of:", 1, 0.82, 0)
        for _, option in ipairs(item.container.options or {}) do
            local have = GetItemCount(option.name)
            local done = have >= option.count
            GameTooltip:AddLine(("  %s: %d / %d%s"):format(option.name, math.min(have, option.count),
                option.count, done and " (ready)" or ""), done and 1 or 0.7, done and 1 or 0.7, done and 1 or 0.7)
        end
        local _, full = GetFillState(item)
        if full and FindFullStack(item.name, item.goal) then
            GameTooltip:AddLine("Click: fill " .. item.container.name .. " with "
                .. item.goal .. " " .. item.name, 0.5, 1, 0.5)
        elseif full then
            GameTooltip:AddLine("Your " .. item.name .. " is split across stacks; the crate needs "
                .. item.goal .. " in one stack.", 1, 0.82, 0)
            GameTooltip:AddLine("BarTab is combining them; this bar turns Ready in a moment.", 0.5, 1, 0.5)
        end
        GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        return
    end

    if item and item.altNeed then
        GameTooltip:SetText(DisplayName(item))
        GameTooltip:AddLine(("%s's bars are short %d %s (from their last saved bags and bank)."):format(
            item.altName, item.goal, item.name), 1, 1, 1, true)
        GameTooltip:AddLine("Gather them, and BarTab offers to mail them at a mailbox.", 0.5, 1, 0.5, true)
        AddStorageLines(item.name)
        GameTooltip:AddLine("Right-click: hide it, or turn this off", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        return
    end
    if not item or not item.recipeID then
        GameTooltip:SetText(item and item.name or "No recipe assigned")
        if item then
            GameTooltip:AddLine("No recipe assigned", 0.7, 0.7, 0.7)
            AddStorageLines(item.name)
            AddSharedLines(item)
            AddSessionLines(item)
            AddChainLines(item)
            if item.noVendor then
                GameTooltip:AddLine("Not bought at vendors", 0.8, 0.8, 0.8)
            end
        end
        GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
        if owner.isBar then
            GameTooltip:AddLine("Ctrl-drag: reorder", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
        return
    end

    local craftable = GetCraftableCount(item.recipeID)
    local barCrafts = GetBarCraftCount(item)

    GameTooltip:SetText(DisplayName(item))
    if item.label and IsOutputBar(item) then
        GameTooltip:AddLine(("Making: %s, until you have %d"):format(item.name, item.goal), 0.8, 0.8, 0.8)
    elseif item.label then
        local perCraft = GetReagentQuantity(item.recipeID, item.name)
        GameTooltip:AddLine("Material: " .. item.name
            .. (perCraft and (" (" .. perCraft .. " per craft)") or ""), 0.8, 0.8, 0.8)
    end

    -- Shopping list for one craft when the recipe needs more than one thing.
    local reagents = GetRecipeReagents(item.recipeID)
    local outputBar = IsOutputBar(item)
    if reagents and (#reagents > 1 or outputBar) then
        if outputBar and craftable and craftable > 0 then
            local _, made = GetRecipeOutput(item.recipeID)
            local more = math.min(craftable * (made or 1), math.max(0, item.goal - GetBarCount(item)))
            GameTooltip:AddLine(("Your bags hold enough to make %d more (the lighter part of the bar)."):format(more),
                0.6, 0.85, 1, true)
        end
        GameTooltip:AddLine("Ingredients (have / need):", 1, 0.82, 0)
        for _, reagent in ipairs(reagents) do
            local short = reagent.have < reagent.need
            GameTooltip:AddLine(("  %s: %d / %d%s"):format(reagent.name, reagent.have,
                reagent.need, short and (" (" .. (reagent.need - reagent.have) .. " short)") or ""),
                short and 1 or 0.85, short and 0.82 or 0.85, short and 0 or 0.85)
        end
    end

    AddStorageLines(item.name)
    AddSharedLines(item)
    AddSessionLines(item)
    AddChainLines(item)
    if item.noVendor then
        GameTooltip:AddLine("Not bought at vendors", 0.8, 0.8, 0.8)
    end
    local skillLine = SkillLimitLine(item)
    if skillLine then GameTooltip:AddLine(skillLine, 0.8, 0.8, 0.8) end
    local goalLine = SkillGoalLine(item)
    if goalLine then GameTooltip:AddLine(goalLine, 1, 1, 1) end
    if item.notLearned then
        GameTooltip:AddLine("Not learned yet" .. (item.needSkill and (" (needs " .. item.needSkill .. ")") or "")
            .. "; becomes active when you learn it", 1, 0.82, 0, true)
    end
    local afterLabel = AfterCraftLabel(item)
    if CountsDown(item) then
        local left = CraftsLeft(item.recipeID)
        if left then
            GameTooltip:AddLine("Counting down: " .. left .. (left == 1 and " craft" or " crafts") .. " left"
                .. (afterLabel and (", then " .. afterLabel) or ", then moves to Inactive"), 0.8, 0.8, 0.8)
            afterLabel = nil
        end
    end
    if afterLabel then
        GameTooltip:AddLine("After crafting: " .. afterLabel, 0.8, 0.8, 0.8)
    end
    -- What each click does (set in the settings window).
    local function timed(crafts)
        local time = BatchTimeText(item.recipeID, crafts)
        return time and (", " .. time) or ""
    end
    local function describe(action)
        if action == "one" then
            return "craft 1" .. (BatchTimeText(item.recipeID, 1) and (" (" .. BatchTimeText(item.recipeID, 1) .. ")") or "")
        elseif action == "fit" then
            return barCrafts and ("craft " .. barCrafts .. " (fits the bar" .. timed(barCrafts) .. ")") or "craft as many as fit the bar"
        elseif action == "max" then
            -- A goal bar's clicks only craft what's still needed.
            local most = craftable
            if most and outputBar then most = math.min(most, CraftsToTarget(item)) end
            return most and ("craft " .. most .. " (maximum available" .. timed(most) .. ")") or "craft all you can"
        end
        return "nothing"
    end
    for _, modifier in ipairs(CLICK_MODIFIERS) do
        GameTooltip:AddLine(modifier.label .. ": " .. describe(GetClickAction(modifier.key)), 1, 1, 1)
    end
    GameTooltip:AddLine("Current action: " .. describe(GetClickAction(CurrentModifier())), 0.5, 1, 0.5)

    GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
    if owner.isBar then
        GameTooltip:AddLine("Ctrl-click: open recipe  ·  Ctrl-drag: reorder", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine("Ctrl-click: open recipe", 0.7, 0.7, 0.7)
    end

    GameTooltip:Show()
end

-- Click actions on recipe bars (chosen in the settings window) ---------------

CLICK_ACTIONS = {
    { key = "one", name = "Craft 1" },
    { key = "fit", name = "Craft as many as fit the bar" },
    { key = "max", name = "Craft all you can" },
    { key = "none", name = "Do nothing" },
}
CLICK_MODIFIERS = {
    { key = "click", label = "Click", default = "one" },
    { key = "shift", label = "Shift-click", default = "fit" },
    { key = "alt", label = "Alt-click", default = "max" },
}

function GetClickAction(modifier)
    local chosen = settings.clickActions and settings.clickActions[modifier]
    if chosen then return chosen end
    for _, entry in ipairs(CLICK_MODIFIERS) do
        if entry.key == modifier then return entry.default end
    end
    return "one"
end

-- Alt wins if both Alt and Shift are held.
function CurrentModifier()
    if IsAltKeyDown() then return "alt" end
    if IsShiftKeyDown() then return "shift" end
    return "click"
end

-- How many to craft for an action; nil plus a message when there's nothing to do.
function ResolveCraftAmount(item, action)
    if action == "one" then
        return 1
    elseif action == "max" then
        local amount = GetCraftableCount(item.recipeID) or 0
        if amount < 1 then return nil, "You don't have the materials to craft this recipe." end
        return amount
    elseif action == "fit" then
        local amount = GetBarCraftCount(item)
        if not amount then return nil, "Couldn't work out how many fit the bar." end
        if amount < 1 then return nil, "Nothing to craft within this bar." end
        return amount
    end
    return nil -- "Do nothing"
end

-- Lower-case item name -> item ID, for anything seen in your bags.
knownItemIDs = {}

-- One scan of your bags, shared by everything that counts items until the
-- bags change (or the next frame): counts by item ID and by lower-case name.
bagScan = nil
bagsDirty = true

function ScanBags()
    local now = GetTime()
    if bagScan and not bagsDirty and bagScan.time == now then return bagScan end
    local byID, byName = {}, {}
    -- Includes the reagent bag on clients that have one.
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    for bag = 0, lastBag do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local name = link:match("%[(.-)%]")
                local itemID = tonumber(link:match("item:(%d+)"))
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local count = (info and info.stackCount) or 1
                if itemID then byID[itemID] = (byID[itemID] or 0) + count end
                if name then
                    local lower = string.lower(name)
                    byName[lower] = (byName[lower] or 0) + count
                    if itemID then knownItemIDs[lower] = itemID end
                end
            end
        end
    end
    bagScan = { time = now, byID = byID, byName = byName }
    bagsDirty = false
    return bagScan
end

bagWatcher = CreateFrame("Frame")
for _, bagEvent in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED" }) do
    pcall(bagWatcher.RegisterEvent, bagWatcher, bagEvent)
end
bagWatcher:SetScript("OnEvent", function() bagsDirty = true end)

-- How many of the named item are in your bags.
GetItemCount = function(itemName)
    if not itemName then return 0 end
    return ScanBags().byName[string.lower(itemName)] or 0
end

-- A bar's item ID: saved on the bar once known (from a link, a recipe, your
-- bags or the item cache), so counts don't depend on the name.
function ItemIDFor(item)
    if item.itemID then return item.itemID end
    local id = ResolveItemID(item.name)
    if id then item.itemID = id end
    return id
end

-- How many of a fill-up item (the crate itself) are in your bags.
function CountContainer(container)
    local scan = ScanBags()
    if container.id then return scan.byID[container.id] or 0 end
    return scan.byName[string.lower(container.name)] or 0
end

-- How many of a bar's item are in your bags: by item ID when known.
function CountItem(item)
    local id = ItemIDFor(item)
    local scan = ScanBags()
    if id then return scan.byID[id] or 0 end
    return scan.byName[string.lower(item.name)] or 0
end

-- Bank and alt counts ---------------------------------------------------------
--
-- Tooltips show where else you have a bar's item. Your bank count comes
-- straight from the game. Other characters can't be seen from here, so
-- each character saves a snapshot of its own counts (bags, plus bank counts
-- of items BarTab knows about) as you play; an alt shows up once you've
-- logged into it. Bags alone still drive the bars.

-- "Name-Realm", which keys each character's bars. Once BarTab has bound this
-- session's list it keeps that key (the game can be slow to report the realm
-- right at login; see BindCharacterList).
function CharacterKey()
    if boundCharacterKey then return boundCharacterKey end
    return (UnitName("player") or "?") .. "-" .. (PlayerRealm() or "?")
end

-- The realm's name. Some clients report it empty (all session, not just at
-- login), so the last name the game did report is remembered, and failing
-- that, the realm of this character's existing saved list.
function PlayerRealm()
    local realm = GetRealmName and GetRealmName()
    if realm and realm ~= "" then
        if settings then settings.realmName = realm end
        return realm
    end
    if settings and settings.realmName and settings.realmName ~= "" then return settings.realmName end
    local name = UnitName and UnitName("player")
    local db = _G.BarTabDB
    if name and db and db.characters then
        local found
        for key in pairs(db.characters) do
            local keyName, keyRealm = key:match("^(.-)%-(.+)$")
            if keyName == name and keyRealm and keyRealm ~= "?" then
                if found and found ~= keyRealm then return nil end -- more than one: can't tell
                found = keyRealm
            end
        end
        if found then
            if settings then settings.realmName = found end
            return found
        end
    end
    return nil
end

-- Whether BarTab knows both the character's name and realm.
function CharacterKnown()
    local name = UnitName and UnitName("player")
    return name and name ~= "" and name ~= (_G.UNKNOWNOBJECT or "Unknown")
        and PlayerRealm() ~= nil and true or false
end

-- Where a character's full name might come from. WoW Forever characters have a
-- surname (the player frame shows "Alinda Windtotem") but UnitName only gives
-- the first name, so try the name the player frame shows, then other lookups.
function CharacterNameSources()
    local sources = {}
    local function add(label, getter)
        local ok, value = pcall(getter)
        if ok and type(value) == "string" and value ~= "" then
            value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            sources[#sources + 1] = { label = label, value = value }
        end
    end
    add("player frame (modern)", function()
        return PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.Name:GetText()
    end)
    add("player frame (name)", function() return PlayerFrame.name:GetText() end)
    add("PlayerName", function() return PlayerName:GetText() end)
    add("GetUnitName", function() return GetUnitName("player", false) end)
    add("UnitFullName", function() return (UnitFullName("player")) end)
    add("UnitName", function() return (UnitName("player")) end)
    return sources
end

-- "Shadowpope Malfus" if a source has it, else just "Shadowpope".
local function FullCharacterName()
    local first = UnitName("player")
    if not first then return nil end
    local pattern = "^" .. first:gsub("(%W)", "%%%1") .. " %S"
    for _, source in ipairs(CharacterNameSources()) do
        if source.value:find(pattern) then
            return source.value
        end
    end
    return first
end

-- C_Item.GetItemCount(item, includeBank, includeUses, includeReagentBank, includeAccountBank)
function CountWhere(itemID, bank, account)
    if not (C_Item and C_Item.GetItemCount) then return 0 end
    local ok, count = pcall(C_Item.GetItemCount, itemID, bank, false, bank, account)
    return (ok and count) or 0
end

local function ScanBagsForSnapshot()
    local counts, names = {}, {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local link = C_Container.GetContainerItemLink(bag, slot)
            local itemID = link and tonumber(link:match("item:(%d+)"))
            if itemID then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                counts[itemID] = (counts[itemID] or 0) + ((info and info.stackCount) or 1)
                local name = link:match("%[(.-)%]")
                if name then names[string.lower(name)] = itemID end
            end
        end
    end
    return counts, names
end

function RecordInventory()
    if not settings then return end
    settings.inventory = settings.inventory or {}
    local store = settings.inventory
    local counts, names = ScanBagsForSnapshot()

    -- An empty scan usually means the bags aren't readable yet (loading) or
    -- any more (logging out); never let it wipe a good snapshot.
    local key = CharacterKey()
    local old = store[key]
    if not next(counts) and old and old.bags and next(old.bags) then
        return
    end

    -- Bank counts for every item any character's snapshot or BarTab knows.
    local ids = {}
    for _, snapshot in pairs(store) do
        for id in pairs(snapshot.bags or {}) do ids[id] = true end
        for id in pairs(snapshot.bank or {}) do ids[id] = true end
    end
    for id in pairs(counts) do ids[id] = true end
    for _, id in pairs(knownItemIDs) do ids[id] = true end
    local bank = {}
    for id in pairs(ids) do
        local inBank = CountWhere(id, true, false) - (counts[id] or 0)
        if inBank > 0 then bank[id] = inBank end
    end

    -- Keep names this character has seen before, adding new ones.
    if old and old.names then
        for name, id in pairs(old.names) do
            if not names[name] then names[name] = id end
        end
    end
    local _, class = UnitClass("player")
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    store[key] = { bags = counts, bank = bank, names = names, class = class, faction = faction,
        fullName = FullCharacterName(), updated = time and time() }
end

function ResolveItemID(name)
    if not name then return nil end
    local lower = string.lower(name)
    if knownItemIDs[lower] then return knownItemIDs[lower] end
    for _, snapshot in pairs(settings.inventory or {}) do
        if snapshot.names and snapshot.names[lower] then return snapshot.names[lower] end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, itemID = pcall(C_Item.GetItemInfoInstant, name)
        if ok and itemID then return itemID end
    end
end

-- Adds "Bags 12 · Bank 30" and "Alts: ..." lines to a tooltip.
function AddStorageLines(name)
    if settings.storageCounts == false or not name then return end
    local itemID = ResolveItemID(name)
    if not itemID then return end

    local bags = CountWhere(itemID, false, false)
    local withBank = CountWhere(itemID, true, false)
    local parts = { "Bags " .. bags }
    if withBank - bags > 0 then parts[#parts + 1] = "Bank " .. (withBank - bags) end

    local me, myRealm = CharacterKey(), PlayerRealm()
    local alts = {}
    for key, snapshot in pairs(settings.inventory or {}) do
        if key ~= me then
            local count = ((snapshot.bags or {})[itemID] or 0) + ((snapshot.bank or {})[itemID] or 0)
            if count > 0 then
                local charName, realm = key:match("^(.-)%-(.*)$")
                charName = snapshot.fullName or charName
                local label = (realm == myRealm) and charName or (charName .. "-" .. (realm or "?"))
                local color = RAID_CLASS_COLORS and snapshot.class and RAID_CLASS_COLORS[snapshot.class]
                if color and color.colorStr then
                    label = "|c" .. color.colorStr .. label .. "|r"
                end
                alts[#alts + 1] = { text = label .. " " .. count, count = count }
            end
        end
    end

    if #parts > 1 or #alts > 0 then
        GameTooltip:AddLine(table.concat(parts, "  ·  "), 0.8, 0.8, 0.8)
    end
    if #alts > 0 then
        table.sort(alts, function(a, b) return a.count > b.count end)
        local texts = {}
        for _, alt in ipairs(alts) do texts[#texts + 1] = alt.text end
        GameTooltip:AddLine("Alts: " .. table.concat(texts, ", "), 0.8, 0.8, 0.8, true)
    end
end

-- Keep this character's snapshot current (at most every 2 seconds).
do
    local recorder = CreateFrame("Frame")
    local pending = false
    local function Queue(delay)
        if pending then return end
        pending = true
        C_Timer.After(delay, function()
            pending = false
            RecordInventory()
        end)
    end
    -- (Not at logout: by then the game has already emptied the bag data.)
    recorder:RegisterEvent("PLAYER_ENTERING_WORLD")
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED" }) do
        pcall(recorder.RegisterEvent, recorder, event)
    end
    recorder:SetScript("OnEvent", function(_, event)
        Queue(event == "PLAYER_ENTERING_WORLD" and 3 or 2)
    end)
end

-- BarTab lines on item tooltips ----------------------------------------------
-- Hovering an item you track, anywhere (bags, bank, auction house, loot,
-- vendors, chat links, profession reagents), adds a line per bar that counts
-- it: "BarTab: 4/5 for Hillman's Cloak". settings.itemTooltips (on by default).

function AddItemTooltipLines(tooltip, itemName, itemID)
    if settings.itemTooltips == false or not (itemName or itemID) then return end
    local wanted = itemName and string.lower(itemName)
    local list = {}
    for _, item in pairs(trackedItems) do
        local id = ItemIDFor(item)
        if (itemID and id and id == itemID)
            or ((not itemID or not id) and wanted and string.lower(item.name) == wanted) then
            list[#list + 1] = item
        end
    end
    -- "Alt-Shift-click" hints, except where that click does something else.
    local hint
    if not IsAuctionHouseTooltip(tooltip) then
        hint = CrateHint(tooltip, itemID) or RecipeItemHint(itemName or (itemID and GetItemNameByID(itemID)))
    end
    if #list == 0 and not hint then return end
    table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)

    for _, item in ipairs(list) do
        local count = GetBarCount(item)
        local target
        if item.container then
            target = " for " .. item.container.name
        elseif item.label then
            target = " for " .. item.label
        else
            target = ""
        end
        local text = ("BarTab: %d/%d%s"):format(math.min(count, item.goal), item.goal, target)
        if item.inactive then
            tooltip:AddLine(text .. " (inactive)", 0.6, 0.6, 0.6)
        elseif count >= item.goal then
            tooltip:AddLine(text, 0.4, 1, 0.4)
        else
            tooltip:AddLine(text, 0.4, 0.8, 1)
        end
    end
    if hint then tooltip:AddLine(hint, 0.4, 0.8, 1) end
    tooltip:Show() -- resize to fit the new lines
end

-- Whether the tooltip belongs to something in the auction house window, where
-- Alt-Shift-click opens the item's listings instead of reaching BarTab.
function IsAuctionHouseTooltip(tooltip)
    local ah = _G.AuctionHouseFrame or _G.AuctionFrame
    if not (ah and ah.IsShown and ah:IsShown() and tooltip.GetOwner) then return false end
    local frame = tooltip:GetOwner()
    for _ = 1, 20 do
        if not frame then return false end
        if frame == ah then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end

-- Whether the tooltip shows a fill-up item (a Waylaid Crate): known from an
-- earlier look, or read off the tooltip's own lines.
function IsFillUpTooltip(tooltip, itemID)
    if itemID and fillOptionsCache[itemID] ~= nil then return fillOptionsCache[itemID] and true or false end
    local name = tooltip.GetName and tooltip:GetName()
    if not name then return false end
    local lines = {}
    for i = 1, (tooltip.NumLines and tooltip:NumLines()) or 0 do
        local text = _G[name .. "TextLeft" .. i]
        text = text and text:GetText()
        if text and text ~= "" then lines[#lines + 1] = text end
    end
    local fillText = FindFillText(lines)
    return fillText ~= nil and #ParseFillOptions(fillText) > 0
end

-- On a crate's tooltip: how to track it, or that it's tracked. Crates are
-- tracked (and filled) from your bags, so one that's only in your bank says
-- to move it first; one you don't have (a chat link) says nothing.
function CrateHint(tooltip, itemID)
    if not itemID then return nil end
    local inBags = CountWhere(itemID, false, false)
    local inBank = CountWhere(itemID, true, false) - inBags
    if inBags == 0 and inBank <= 0 then return nil end
    if not IsFillUpTooltip(tooltip, itemID) then return nil end
    if inBags == 0 then return "BarTab: move this crate to your bags, then Alt-Shift-click it if it doesn't track automatically" end
    if IsContainerTracked(itemID) then return "BarTab: tracking this crate" end
    return "BarTab: Alt-Shift-click to track this crate"
end

-- Only the main tooltip and chat-link tooltips (not comparison tooltips).
function IsItemTooltipWanted(tooltip)
    return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not IsItemTooltipWanted(tooltip) or type(data) ~= "table" then return end
        pcall(function()
            local name = data.id and GetItemNameByID(data.id)
            if not name and tooltip.GetItem then name = tooltip:GetItem() end
            AddItemTooltipLines(tooltip, name, tonumber(data.id))
        end)
    end)
else
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
                local name, link
                if self.GetItem then name, link = self:GetItem() end
                pcall(AddItemTooltipLines, self, name, link and tonumber(link:match("item:(%d+)")))
            end)
        end
    end
end
