-- BarTab: fill-up and quest import, click-to-use buttons, debug, inline quest bars.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

-- Fill-up item import ------------------------------------------------------

fillOptionsCache = {} -- itemID -> options list, or false if none

-- "- 40 Linen Cloth" lines in a "Use:" text -> { {name=, count=}, ... }
function ParseFillOptions(useText)
    local text = useText:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|cn[^:|]*:", "")
    text = text:gsub("|r", "")
    local options = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        local count, name = line:match("^%s*%-%s*(%d+)%s+(.-)%s*$")
        if count and name ~= "" then
            options[#options + 1] = { name = name, count = tonumber(count) }
        end
    end
    return options
end

function GetFillOptions(bag, slot, itemID)
    if fillOptionsCache[itemID] ~= nil then return fillOptionsCache[itemID] end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not ok or not data or not data.lines then return false end
    local options = false
    for _, line in ipairs(data.lines) do
        if line.leftText and line.leftText:find("^Use:") then
            local parsed = ParseFillOptions(line.leftText)
            if #parsed > 0 then options = parsed end
            break
        end
    end
    fillOptionsCache[itemID] = options
    return options
end

function IsContainerTracked(itemID)
    for _, item in pairs(trackedItems) do
        if item.container and item.container.id == itemID then return true end
    end
    return false
end

-- Adds a bar for each bundle that fills the item.
function ImportContainer(itemID, name, options, announce)
    local names = {}
    for _, option in ipairs(options) do
        local key = string.lower(option.name) .. "#" .. itemID
        if not trackedItems[key] then
            trackedItems[key] = {
                name = option.name,
                start = 0,
                goal = option.count,
                order = NextOrder(),
                container = { id = itemID, name = name, options = options },
            }
        end
        names[#names + 1] = option.count .. " " .. option.name
    end
    UpdateBars()
    if announce then
        Print("Tracking " .. name .. ": " .. table.concat(names, " or ") .. ".")
    end
end

-- Looks through your bags for fill-up items. With a filter, adds matching
-- ones (reporting what it finds); without, adds any new ones quietly.
function ScanForContainers(filter)
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    local matched = false
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local link = C_Container.GetContainerItemLink(bag, slot)
            local name = link and link:match("%[(.-)%]")
            local itemID = link and tonumber(link:match("item:(%d+)"))
            if name and itemID and (not filter or string.lower(name):find(filter, 1, true)) then
                local options = GetFillOptions(bag, slot, itemID)
                if filter then
                    matched = true
                    if not options then
                        Print(name .. " doesn't list anything to fill it with.")
                    elseif IsContainerTracked(itemID) then
                        Print(name .. " is already tracked.")
                    else
                        ImportContainer(itemID, name, options, true)
                    end
                    return
                elseif options and not IsContainerTracked(itemID) then
                    ImportContainer(itemID, name, options, true)
                end
            end
        end
    end
    if filter and not matched then
        Print("Nothing in your bags matches \"" .. filter .. "\".")
    end
end

-- Quest import -------------------------------------------------------------

-- Objective text is "3/5 Book Page" or "Book Page: 3/5" depending on client.
function ParseObjectiveItemName(text)
    if not text then return nil end
    local name = text:match("^%s*%d+%s*/%s*%d+%s+(.-)%s*$")
        or text:match("^%s*(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
    return name and StripLinks(name)
end

-- The "collect N of X" objectives of a quest, as { {name=, count=}, ... }.
function GetQuestItemObjectives(questID)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" then return nil end

    local result = {}
    for _, objective in ipairs(objectives) do
        if objective.type == "item" then
            local name = ParseObjectiveItemName(objective.text)
            local count = tonumber(objective.numRequired)
            if name and name ~= "" and count and count > 0 then
                result[#result + 1] = { name = name, count = count }
            end
        end
    end
    return result
end

function GetQuestTitle(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local title = C_QuestLog.GetTitleForQuestID(questID)
        if title and title ~= "" then return title end
    end
    return "Quest " .. questID
end

-- Adds a bar for each item the quest asks you to collect. Items you already
-- track by hand are left as they are. Returns how many bars were added, or
-- nil if there are no item objectives (yet).
function ImportQuest(questID, announce)
    local objectives = GetQuestItemObjectives(questID)
    if not objectives or #objectives == 0 then return nil end

    local title = GetQuestTitle(questID)
    local added = {}
    for _, objective in ipairs(objectives) do
        local key = string.lower(objective.name)
        local existing = trackedItems[key]
        if not existing then
            trackedItems[key] = {
                name = objective.name,
                start = 0,
                goal = objective.count,
                order = NextOrder(),
                quest = {
                    id = questID,
                    title = title,
                    zone = GetQuestZone(questID),
                    items = objectives
                }
            }
            added[#added + 1] = objective.name
        elseif existing.quest and existing.quest.id == questID then
            -- Refresh in case the quest's counts changed.
            existing.goal = objective.count
            existing.quest.title = title
            existing.quest.items = objectives
            existing.quest.zone = GetQuestZone(questID) or existing.quest.zone
        end
    end

    UpdateBars()

    local key = string.lower(objectives[1].name)
    local usable = trackedItems[key] and QuestHasUsableItem(trackedItems[key])
    if announce and #added > 0 then
        if usable then
            Print("Tracking items for " .. title .. ": " .. table.concat(added, ", ") .. ".")
        elseif announce == "manual" then
            Print(title .. " doesn't have an item you can use yet; its bars will appear once it does.")
        end
    elseif announce == "manual" then
        Print("Items for " .. title .. " are already tracked.")
    end
    return #added, usable
end

-- Objectives can take a moment to load after accepting, so retry briefly.
function ImportQuestWhenReady(questID, announce, attempt)
    attempt = attempt or 1
    if ImportQuest(questID, announce) then return end

    if attempt < 4 then
        C_Timer.After(1, function()
            ImportQuestWhenReady(questID, announce, attempt + 1)
        end)
    elseif announce == "manual" then
        Print(GetQuestTitle(questID) .. " has no items to collect.")
    end
end

-- Stops tracking a quest's items once it's turned in or abandoned.
function RemoveQuest(questID)
    local removed = {}
    for key, item in pairs(trackedItems) do
        if item.quest and item.quest.id == questID then
            removed[#removed + 1] = key
        end
    end
    if #removed == 0 then return end

    for _, key in ipairs(removed) do
        trackedItems[key] = nil
    end
    UpdateBars()
    Print("Quest finished: stopped tracking its items.")
end

function ImportAllQuests()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
        Print("Couldn't read your quest log.")
        return
    end

    -- Zones that already have quest bars keep their state; zones this
    -- import adds start collapsed.
    local existingZones = {}
    for _, item in pairs(trackedItems) do
        if item.quest and not item.inactive then
            existingZones[GetQuestZoneName(item)] = true
        end
    end

    local total, waiting = 0, 0
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            local added, usable = ImportQuest(info.questID, false)
            if added and added > 0 then
                if usable then
                    total = total + added
                else
                    waiting = waiting + 1
                end
            end
        end
    end
    for _, item in pairs(trackedItems) do
        if item.quest and not item.inactive then
            local zone = GetQuestZoneName(item)
            if not existingZones[zone] then
                SetGroupCollapsed(QUEST_SECTION .. "/" .. zone, true)
            end
        end
    end
    UpdateBars()

    Print(total > 0 and ("Added " .. total .. " quest item bar(s).")
        or "No new quest items to track.")
    if waiting > 0 then
        Print(waiting .. " other quest(s) will appear once you have an item you can use for them.")
    end
end

-- Adds "BarTab: track quest items" to the quest tracker's right-click menu.
function HookQuestTrackerMenu()
    if not (Menu and Menu.ModifyMenu) then return end

    for _, tracker in ipairs({ QuestObjectiveTracker, CampaignQuestObjectiveTracker }) do
        if tracker and tracker.OnBlockHeaderClick then
            hooksecurefunc(tracker, "OnBlockHeaderClick", function(_, block)
                lastMenuQuestID = block and block.id
            end)
        end
    end

    Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", function(_, root)
        root:CreateDivider()
        root:CreateButton("BarTab: track quest items", function()
            if lastMenuQuestID then
                ImportQuestWhenReady(lastMenuQuestID, "manual")
            end
        end)
    end)
end

-- Secure click overlays (using quest items) --------------------------------
--
-- Using an item from an addon needs a secure button, and secure buttons
-- can't be changed during combat. Each quest bar that's ready to use gets an
-- invisible secure button laid over it, positioned in screen coordinates (not
-- attached to the tracker, so the tracker can still move freely in combat).
-- Overlays switch off when combat starts and come back afterwards.

function CreateUseOverlay(bar)
    local overlay = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("AnyUp", "AnyDown")
    overlay:SetAttribute("type1", "item")
    overlay:SetAttribute("ctrl-type1", "noop") -- Ctrl is for reordering
    overlay:Hide()

    overlay:SetScript("OnEnter", function() ShowBarTooltip(bar) end)
    overlay:SetScript("OnLeave", function() GameTooltip:Hide() end)

    overlay:HookScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and IsControlKeyDown() then
            bar.dragStarted = true
            BeginDrag(bar)
        end
    end)
    overlay:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ShowItemMenu(bar, bar.itemKey)
        elseif bar.dragStarted then
            bar.dragStarted = nil
            EndDrag()
        end
    end)

    bar.useOverlay = overlay
    return overlay
end

function SyncOverlay(bar)
    if InCombatLockdown() then return end

    local overlay = bar.useOverlay
    local useName = bar.useItemName
    local left = bar:IsVisible() and bar:GetLeft()

    if not useName or not left then
        if overlay then overlay:Hide() end
        return
    end

    overlay = overlay or CreateUseOverlay(bar)
    local scale = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y = left * scale, bar:GetBottom() * scale
    local width, height = bar:GetWidth() * scale, bar:GetHeight() * scale

    if overlay.x ~= x or overlay.y ~= y or overlay.w ~= width or overlay.h ~= height then
        overlay.x, overlay.y, overlay.w, overlay.h = x, y, width, height
        overlay:ClearAllPoints()
        overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        overlay:SetSize(width, height)
    end
    -- Items that then ask you to pick another item (a crate asking for the
    -- bundle to fill it with) use a two-line macro: use the item, then use
    -- the bag slot holding the bundle, which answers the targeting cursor.
    local macro
    if bar.useTargetName then
        local stack = FindFullStack(bar.useTargetName, bar.useTargetAmount or 1)
        if stack then
            macro = "/use " .. useName .. "\n/use " .. stack.bag .. " " .. stack.slot
        end
    end
    if macro then
        if overlay:GetAttribute("type1") ~= "macro" then
            overlay:SetAttribute("type1", "macro")
        end
        if overlay:GetAttribute("macrotext1") ~= macro then
            overlay:SetAttribute("macrotext1", macro)
        end
    else
        if overlay:GetAttribute("type1") ~= "item" then
            overlay:SetAttribute("type1", "item")
        end
        if overlay:GetAttribute("item") ~= useName then
            overlay:SetAttribute("item", useName)
        end
    end
    overlay:SetFrameStrata(bar:GetFrameStrata())
    overlay:SetFrameLevel(bar:GetFrameLevel() + 5)
    overlay:Show()
end

overlayDriver = CreateFrame("Frame")
overlayElapsed = 0
overlayDriver:SetScript("OnUpdate", function(_, elapsed)
    overlayElapsed = overlayElapsed + elapsed
    if overlayElapsed < 0.1 then return end
    overlayElapsed = 0
    for _, bar in ipairs(bars) do
        if bar.useItemName or bar.useOverlay then
            SyncOverlay(bar)
        end
    end
end)

function HideAllOverlays()
    for _, bar in ipairs(bars) do
        if bar.useOverlay then
            bar.useOverlay:Hide()
        end
    end
end

-- /bt debug <part of a quest name>: prints what the game reports for
-- matching quests, to work out why one does or doesn't show.
function DebugQuests(filter)
    -- Also saved to the BarTab saved-variables file (written on /reload or
    -- logout) so the output can be read outside the game.
    settings.debugLog = { "BarTab debug: " .. tostring(filter) }
    local debugStems, debugIDs = {}, {}
    local function DebugPrint(message)
        Print(message)
        table.insert(settings.debugLog, (message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    end

    filter = string.lower(filter or "")
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
        DebugPrint("debug: C_QuestLog isn't available on this client.")
        return
    end

    local found = 0
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID and info.title
            and string.lower(info.title):find(filter, 1, true) then
            found = found + 1
            local questID = info.questID
            DebugPrint(("debug: %s (questID %s, log index %d)"):format(info.title, tostring(questID), index))
            DebugPrint("  zone: " .. tostring(GetQuestZone(questID)))

            if GetQuestLogSpecialItemInfo then
                local ok, link = pcall(GetQuestLogSpecialItemInfo, index)
                DebugPrint("  quest's own item: " .. tostring(ok and link or ("error: " .. tostring(link))))
            else
                DebugPrint("  quest's own item: GetQuestLogSpecialItemInfo missing")
            end

            local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
            if not ok or type(objectives) ~= "table" then
                DebugPrint("  objectives: unavailable (" .. tostring(objectives) .. ")")
            else
                for i, o in ipairs(objectives) do
                    DebugPrint(("  objective %d: type=%s text=%q required=%s"):format(
                        i, tostring(o.type), tostring(o.text), tostring(o.numRequired)))
                    local name = o.type == "item" and ParseObjectiveItemName(o.text)
                    if name then
                        local count = GetItemCount(name)
                        DebugPrint(("    item %q: in bags=%d, itemID=%s, has Use effect=%s"):format(
                            name, count, tostring(knownItemIDs[string.lower(name)]),
                            tostring(ItemHasUse(name))))
                        local stem = NameStem(name)
                        if stem then debugStems[stem] = true end
                        local id = knownItemIDs[string.lower(name)]
                        if id then debugIDs[#debugIDs + 1] = id end
                    end
                end
            end

            local tracked = 0
            for _, item in pairs(trackedItems) do
                if item.quest and item.quest.id == questID then
                    tracked = tracked + 1
                    DebugPrint(("  tracked: %s (usable=%s, inactive=%s)"):format(
                        item.name, tostring(QuestHasUsableItem(item)), tostring(item.inactive)))
                end
            end
            if tracked == 0 then
                DebugPrint("  tracked: none")
            end
        end
    end

    local function PrintTooltip(data)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.leftText and line.leftText ~= "" then
                    DebugPrint("    tooltip: " .. line.leftText)
                end
            end
        end
    end

    -- Quest items in your bags, plus anything sharing a quest item's name
    -- (e.g. pages of a manual the quest wants chapters of).
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local link = C_Container.GetContainerItemLink(bag, slot)
            local questInfo = C_Container.GetContainerItemQuestInfo
                and C_Container.GetContainerItemQuestInfo(bag, slot)
            local name = link and link:match("%[(.-)%]")
            local stem = name and NameStem(name)
            if name and ((questInfo and questInfo.isQuestItem)
                or (stem and debugStems[stem])) then
                GetItemCount(name)
                DebugPrint(("debug: bag item: %s (itemID %s, Use effect=%s [%s], quest item=%s)"):format(
                    name, tostring(knownItemIDs[string.lower(name)]),
                    tostring(ItemHasUse(name)), tostring(GetItemSpellName(name)),
                    tostring(questInfo and questInfo.isQuestItem)))
                if C_TooltipInfo and C_TooltipInfo.GetBagItem then
                    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
                    if ok then PrintTooltip(data) end
                end
            end
        end
    end

    -- Items with IDs near the quest's items that share their name: finds the
    -- whole set of pages even ones you don't have. Item data loads in the
    -- background, so this part prints a couple of seconds later.
    if #debugIDs > 0 and C_Item and C_Item.GetItemNameByID then
        local range = {}
        for _, base in ipairs(debugIDs) do
            for id = base - 20, base + 20 do
                range[id] = true
                if C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, id)
                end
            end
        end
        C_Timer.After(2, function()
            local ids = {}
            for id in pairs(range) do ids[#ids + 1] = id end
            table.sort(ids)
            for _, id in ipairs(ids) do
                local name = C_Item.GetItemNameByID(id)
                local stem = name and NameStem(name)
                if stem and debugStems[stem] then
                    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
                    local spell = getSpell and select(2, pcall(getSpell, id))
                    DebugPrint(("debug: related item %d: %s (Use effect [%s])"):format(
                        id, name, tostring(spell)))
                    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
                        local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
                        if ok then PrintTooltip(data) end
                    end
                end
            end
            Print("Debug scan finished. Type /reload to write it to disk.")
        end)
    end

    if found == 0 then
        DebugPrint("debug: no quest in your log matches \"" .. filter .. "\".")
    end
    if #debugIDs == 0 then
        Print("Debug output saved. Type /reload to write it to disk.")
    else
        Print("Scanning related items; wait for 'Debug scan finished' before /reload.")
    end
end

-- Quest bars inside Blizzard's quest tracker (/bt inline) ------------------
--
-- Blizzard builds each tracked quest by adding its objective lines one at a
-- time. We hook that: right after an item objective line BarTab tracks is
-- added, its bar is inserted below it, before Blizzard positions the quest.
-- This touches Blizzard's own layout, so it's optional.

QUEST_MODULE_NAMES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }
inlineHooksInstalled = false
layoutPass = {}   -- quest module -> layout counter

function IsQuestModule(module)
    for _, name in ipairs(QUEST_MODULE_NAMES) do
        if module ~= nil and module == _G[name] then return true end
    end
    return false
end

function OnAddObjective(block, objectiveKey, text)
    if not inlineQuestsActive or type(objectiveKey) ~= "number" then return end
    local module = block.parentModule
    if not IsQuestModule(module) then return end

    local name = ParseObjectiveItemName(text)
    local key = name and string.lower(name)
    local item = key and trackedItems[key]
    if not (item and item.quest and item.quest.id == block.id
        and not item.inactive and IsShown(item)) then
        return
    end

    local bar = GetBar(key, "inline")
    bar.section = "inline"
    bar.group = block.id
    bar.inlineModule = module
    bar.inlinePass = layoutPass[module]
    bar:SetParent(block)
    bar:ClearAllPoints()
    local width = block:GetWidth()
    if not width or width < 150 then width = 230 end
    bar:SetWidth(width - 40)
    RefreshBar(bar, item, false)
    block:AddCustomRegion(bar, 0, -2)
end

-- Hides inline bars that weren't placed in the module's latest layout.
function OnQuestModuleEndLayout(module)
    for _, bar in ipairs(bars) do
        if bar.section == "inline" and bar.inlineModule == module
            and (not inlineQuestsActive or bar.inlinePass ~= layoutPass[module]) then
            bar:Hide()
        end
    end
end

function InstallInlineHooks()
    if inlineHooksInstalled then return true end
    if not hooksecurefunc then return false end

    -- Every block mixin that has AddObjective (quest blocks use their own
    -- copy, so hook them all).
    local hooked = 0
    for name, value in pairs(_G) do
        if type(name) == "string" and name:find("BlockMixin$")
            and type(value) == "table" and type(value.AddObjective) == "function" then
            hooksecurefunc(value, "AddObjective", OnAddObjective)
            hooked = hooked + 1
        end
    end

    local modules = 0
    for _, name in ipairs(QUEST_MODULE_NAMES) do
        local module = _G[name]
        if module and module.BeginLayout and module.EndLayout then
            hooksecurefunc(module, "BeginLayout", function(self)
                layoutPass[self] = (layoutPass[self] or 0) + 1
            end)
            hooksecurefunc(module, "EndLayout", OnQuestModuleEndLayout)
            modules = modules + 1
        end
    end

    inlineHooksInstalled = hooked > 0 and modules > 0
    return inlineHooksInstalled
end

function MarkQuestModulesDirty()
    for _, name in ipairs(QUEST_MODULE_NAMES) do
        local module = _G[name]
        if module and module.MarkDirty then
            module:MarkDirty()
        end
    end
end

UpdateInlineQuests = function()
    -- Refresh counts and colors on bars already in place.
    for _, bar in ipairs(bars) do
        if bar.section == "inline" and bar:IsShown() then
            local item = trackedItems[bar.itemKey]
            if item and IsInlineQuestItem(item) and IsShown(item) then
                RefreshBar(bar, item, false)
            else
                bar:Hide()
            end
        end
    end

    -- Ask Blizzard's quest tracker to lay out again only when the set of
    -- bars it should show has changed.
    local keys = {}
    for key, item in pairs(trackedItems) do
        if IsInlineQuestItem(item) and IsShown(item) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    local signature = (inlineQuestsActive and "on:" or "off:") .. table.concat(keys, "|")
    if signature ~= lastInlineSignature then
        local first = lastInlineSignature == nil
        lastInlineSignature = signature
        -- Asking Blizzard's tracker to redraw from addon code can upset it,
        -- so only when inline bars are (or were just) in use.
        if inlineHooksInstalled and not (first and not inlineQuestsActive) then
            MarkQuestModulesDirty()
        end
    end
end

function SetInlineQuests(enabled)
    settings.inlineQuests = enabled
    if enabled and not InstallInlineHooks() then
        DebugPrint("Couldn't hook into the quest tracker on this client; quest bars stay in the BarTab: Quests section.")
        inlineQuestsActive = false
    else
        inlineQuestsActive = enabled
    end
    UpdateBars()
end

-- /bt debug item <part of a name>: saves what the game reports for matching
-- items in your bags (ID, Use effect, full tooltip) to the saved-data file.
function DebugItems(filter)
    filter = string.lower(filter or "")
    settings.debugLog = { "BarTab debug item: " .. filter }
    local function DebugPrint(message)
        Print(message)
        table.insert(settings.debugLog, (message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    end

    local found = 0
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local link = C_Container.GetContainerItemLink(bag, slot)
            local name = link and link:match("%[(.-)%]")
            if name and string.lower(name):find(filter, 1, true) then
                found = found + 1
                local itemID = tonumber(link:match("item:(%d+)"))
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local questInfo = C_Container.GetContainerItemQuestInfo
                    and C_Container.GetContainerItemQuestInfo(bag, slot)
                knownItemIDs[string.lower(name)] = itemID
                DebugPrint(("debug: %s (itemID %s, count %s, Use effect=%s [%s], quest item=%s)"):format(
                    name, tostring(itemID), tostring(info and info.stackCount),
                    tostring(ItemHasUse(name)), tostring(GetItemSpellName(name)),
                    tostring(questInfo and questInfo.isQuestItem)))
                if C_TooltipInfo and C_TooltipInfo.GetBagItem then
                    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
                    if ok and data and data.lines then
                        for _, line in ipairs(data.lines) do
                            if line.leftText and line.leftText ~= "" then
                                DebugPrint("    tooltip: " .. line.leftText
                                    .. ((line.rightText and line.rightText ~= "") and ("  ||  " .. line.rightText) or ""))
                            end
                        end
                    end
                end
            end
        end
    end
    if found == 0 then
        DebugPrint("debug: nothing in your bags matches \"" .. filter .. "\".")
    end
    Print("Debug output saved. Type /reload to write it to disk.")
end
