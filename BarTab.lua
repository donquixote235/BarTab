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
settings = { autoQuests = true }
bars = {}        -- every bar ever created, for iteration
barsByKey = {}   -- section + item key -> its bar
updatePending = false
trackerSetupTried = false
-- True while quest bars are shown under their quests in Blizzard's tracker
-- (/bt inline on) and the hooks for that are in place.
inlineQuestsActive = false
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

function ShowQuestTooltip(owner, item)
    GameTooltip:SetText(item.name)
    GameTooltip:AddLine(item.quest.title or "Quest item", 1, 0.82, 0)

    for _, req in ipairs(item.quest.items or {}) do
        local have = GetItemCount(req.name)
        local done = have >= req.count
        GameTooltip:AddLine(
            req.name .. ": " .. math.min(have, req.count) .. " / " .. req.count
                .. (done and " (done)" or ""),
            done and 1 or 0.7, done and 1 or 0.7, done and 1 or 0.7
        )
    end

    local state, missing = GetQuestState(item)
    local incomplete = not state and GetItemCount(item.name) < item.goal
    local progress = incomplete and GetPieceProgress(item)
    local piece = incomplete and not progress and PickRelatedUseItem(item)
    if progress then
        GameTooltip:AddLine(("%s collected: %d / %d"):format(
            progress.word:gsub("^%l", string.upper) .. "s", progress.owned, progress.required),
            1, 1, 1)
        if #progress.missing > 0 then
            GameTooltip:AddLine("Still need " .. progress.word .. " "
                .. table.concat(progress.missing, ", "), 1, 0.82, 0)
        elseif progress.useName then
            GameTooltip:AddLine("Click: use " .. progress.useName, 0.5, 1, 0.5)
        end
    elseif piece then
        GameTooltip:AddLine("Click: use " .. piece, 0.5, 1, 0.5)
    elseif state == "ready" then
        local useName = GetQuestUseItem(item)
        if useName then
            GameTooltip:AddLine("Click: use " .. useName, 0.5, 1, 0.5)
        else
            GameTooltip:AddLine("All items collected", 0.5, 1, 0.5)
        end
    elseif state == "waiting" then
        GameTooltip:AddLine("Still need " .. missing, 1, 0.82, 0)
    end

    GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
    if owner.isBar then
        GameTooltip:AddLine("Ctrl-drag: reorder", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

function ShowBarTooltip(owner)
    local item = trackedItems[owner.itemKey]
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")

    if item and item.quest then
        ShowQuestTooltip(owner, item)
        return
    end

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
    if item.label then
        local perCraft = GetReagentQuantity(item.recipeID, item.name)
        GameTooltip:AddLine("Material: " .. item.name
            .. (perCraft and (" (" .. perCraft .. " per craft)") or ""), 0.8, 0.8, 0.8)
    end

    -- Shopping list for one craft when the recipe needs more than one thing.
    local reagents = GetRecipeReagents(item.recipeID)
    if reagents and #reagents > 1 then
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
    local afterLabel = AfterCraftLabel(item)
    if afterLabel then
        GameTooltip:AddLine("After crafting: " .. afterLabel, 0.8, 0.8, 0.8)
    end
    -- What each click does (set in the settings window).
    local function describe(action)
        if action == "one" then
            return "craft 1"
        elseif action == "fit" then
            return barCrafts and ("craft " .. barCrafts .. " (fits the bar)") or "craft as many as fit the bar"
        elseif action == "max" then
            return craftable and ("craft " .. craftable .. " (maximum available)") or "craft all you can"
        end
        return "nothing"
    end
    for _, modifier in ipairs(CLICK_MODIFIERS) do
        GameTooltip:AddLine(modifier.label .. ": " .. describe(GetClickAction(modifier.key)), 1, 1, 1)
    end
    GameTooltip:AddLine("Current action: " .. describe(GetClickAction(CurrentModifier())), 0.5, 1, 0.5)

    GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
    if owner.isBar then
        GameTooltip:AddLine("Ctrl-drag: reorder", 0.7, 0.7, 0.7)
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

GetItemCount = function(itemName)
    local total = 0
    local wanted = string.lower(itemName)
    -- Includes the reagent bag on clients that have one.
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS

    for bag = 0, lastBag do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local name = link:match("%[(.-)%]")
                local itemID = tonumber(link:match("item:(%d+)"))
                if name and itemID then
                    knownItemIDs[string.lower(name)] = itemID
                end
                if name and string.lower(name) == wanted then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    total = total + ((info and info.stackCount) or 1)
                end
            end
        end
    end

    return total
end

-- Bank, Warband bank and alt counts ---------------------------------------------
--
-- Tooltips show where else you have a bar's item. Your bank and Warband bank
-- come straight from the game. Other characters can't be seen from here, so
-- each character saves a snapshot of its own counts (bags, plus bank counts
-- of items BarTab knows about) as you play; an alt shows up once you've
-- logged into it. Bags alone still drive the bars.

function CharacterKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
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
local function CountWhere(itemID, bank, account)
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
    store[key] = { bags = counts, bank = bank, names = names, class = class,
        fullName = FullCharacterName(), updated = time and time() }
end

local function ResolveItemID(name)
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

-- Adds "Bags 12 · Bank 30 · Warband 5" and "Alts: ..." lines to a tooltip.
function AddStorageLines(name)
    if settings.storageCounts == false or not name then return end
    local itemID = ResolveItemID(name)
    if not itemID then return end

    local bags = CountWhere(itemID, false, false)
    local withBank = CountWhere(itemID, true, false)
    local withWarband = CountWhere(itemID, true, true)
    local parts = { "Bags " .. bags }
    if withBank - bags > 0 then parts[#parts + 1] = "Bank " .. (withBank - bags) end
    if withWarband - withBank > 0 then parts[#parts + 1] = "Warband " .. (withWarband - withBank) end

    local me, myRealm = CharacterKey(), GetRealmName and GetRealmName()
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

function AddItemTooltipLines(tooltip, itemName)
    if settings.itemTooltips == false or not itemName then return end
    local wanted = string.lower(itemName)
    local list = {}
    for _, item in pairs(trackedItems) do
        if string.lower(item.name) == wanted then list[#list + 1] = item end
    end
    if #list == 0 then return end
    table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)

    for _, item in ipairs(list) do
        local count = GetBarCount(item)
        local target
        if item.container then
            target = " for " .. item.container.name
        elseif item.quest then
            target = " for " .. (item.quest.title or "a quest")
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
    tooltip:Show() -- resize to fit the new lines
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
            AddItemTooltipLines(tooltip, name)
        end)
    end)
else
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
                local name = self.GetItem and self:GetItem()
                pcall(AddItemTooltipLines, self, name)
            end)
        end
    end
end
