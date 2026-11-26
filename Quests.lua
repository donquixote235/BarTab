-- BarTab: fill-up item import, click-to-use buttons (crates), item debug.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

-- Fill-up item import ------------------------------------------------------

fillOptionsCache = {} -- itemID -> options list, or false if none
fillOptionsPending = {} -- itemID -> true while the game is still loading it
fillOptionsTries = {} -- itemID -> how many times it wasn't loaded yet

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

-- True once the game has the item's details (an item never seen before,
-- such as one taken from the mailbox, can have a tooltip without its "Use:"
-- text for a moment).
function IsItemLoaded(itemID)
    if C_Item and C_Item.IsItemDataCachedByID then
        local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
        if ok then return cached and true or false end
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if getInfo then
        local ok, name = pcall(getInfo, itemID)
        return ok and name ~= nil
    end
    return GetItemNameByID(itemID) ~= nil
end

-- A hidden tooltip, for clients whose tooltip data comes back empty.
function GetScanTooltip()
    if not scanTooltip then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "BarTabScanTooltip", nil, "GameTooltipTemplate")
        if ok and tip then scanTooltip = tip end
    end
    return scanTooltip
end

-- The left-hand lines of a bag item's tooltip, and where they came from:
-- the game's tooltip data (unpacked the older way too, if it needs it), or
-- else a hidden tooltip read line by line.
function GetBagItemTooltipLines(bag, slot)
    local lines, source = {}, nil
    local surface = TooltipUtil and TooltipUtil.SurfaceArgs
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        if ok and type(data) == "table" then
            if surface then pcall(surface, data) end
            for _, line in ipairs(data.lines or {}) do
                if surface and not line.leftText then pcall(surface, line) end
                if line.leftText and line.leftText ~= "" then lines[#lines + 1] = line.leftText end
            end
            if #lines > 0 then source = "tooltip data" end
        end
    end
    if #lines == 0 then
        local tip = GetScanTooltip()
        if tip and tip.SetBagItem then
            tip:SetOwner(_G.WorldFrame or UIParent, "ANCHOR_NONE")
            tip:ClearLines()
            if pcall(tip.SetBagItem, tip, bag, slot) then
                for i = 1, (tip.NumLines and tip:NumLines()) or 0 do
                    local text = _G["BarTabScanTooltipTextLeft" .. i]
                    text = text and text:GetText()
                    if text and text ~= "" then lines[#lines + 1] = text end
                end
            end
            tip:Hide()
            if #lines > 0 then source = "hidden tooltip" end
        end
    end
    return lines, source
end

-- The "Use:" text with its list, whether the list is inside that line or
-- on the lines after it.
function FindFillText(lines)
    for i, line in ipairs(lines) do
        if line:find("^Use:") then
            local text = line
            local j = i + 1
            while lines[j] and lines[j]:find("^%s*%-%s*%d") do
                text = text .. "\n" .. lines[j]
                j = j + 1
            end
            return text
        end
    end
end

function GetFillOptions(bag, slot, itemID)
    if fillOptionsCache[itemID] ~= nil then return fillOptionsCache[itemID] end
    local loaded = IsItemLoaded(itemID)
    local lines = GetBagItemTooltipLines(bag, slot)
    if #lines == 0 then return false end
    local options = false
    local useText = FindFillText(lines)
    if useText then
        local parsed = ParseFillOptions(useText)
        if #parsed > 0 then options = parsed end
    end
    fillOptionsTries[itemID] = (fillOptionsTries[itemID] or 0) + 1
    if options or loaded or fillOptionsTries[itemID] > 5 then
        -- Only remember "not a fill-up item" once the item has fully loaded
        -- (or after a few tries; it's looked at again if it loads later).
        fillOptionsCache[itemID] = options
        fillOptionsPending[itemID] = (not options and not loaded) and "gave up" or nil
    else
        fillOptionsPending[itemID] = true
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
        -- In case the load event never comes: look again shortly.
        C_Timer.After(3, function()
            if fillOptionsPending[itemID] == true then
                fillOptionsPending[itemID] = nil
                QueueContainerScan(0)
            end
        end)
    end
    return options
end

function IsContainerTracked(itemID)
    for _, item in pairs(trackedItems) do
        if item.container and item.container.id == itemID then return true end
    end
    return false
end

-- Crates you untrack stay untracked: remembered per character with how many
-- were in your bags. One leaving your bags (used, sold, put in the bank)
-- lowers the count, and once none are left it's forgotten; one coming in
-- (looted, or taken back out of the bank) is tracked again.
-- /bartab item adds one back by hand.
function DismissedContainers()
    settings.dismissedContainers = settings.dismissedContainers or {}
    local key = CharacterKey()
    settings.dismissedContainers[key] = settings.dismissedContainers[key] or {}
    return settings.dismissedContainers[key]
end

function ContainerTotal(itemID)
    return CountWhere(itemID, false, false) -- bags only
end

-- After bars are untracked: crates with no bars left are remembered.
function NoteUntrackedContainers(items)
    for _, item in ipairs(items) do
        local id = item.container and item.container.id
        if id and not IsContainerTracked(id) then
            DismissedContainers()[id] = math.max(1, ContainerTotal(id))
        end
    end
end

function IsContainerDismissed(itemID)
    local mark = DismissedContainers()[itemID]
    return mark ~= nil and ContainerTotal(itemID) <= mark
end

-- On bag changes: a new crate ends the dismissal; fewer lowers it.
function UpdateDismissedContainers()
    local list = DismissedContainers()
    if not next(list) then return end
    -- Bags not readable yet (logging in): leave everything as it is.
    if not next(ScanBags().byID) then return end
    for itemID, mark in pairs(list) do
        local total = ContainerTotal(itemID)
        if total > mark or total <= 0 then
            list[itemID] = nil
        elseif total < mark then
            list[itemID] = total
        end
    end
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
                    if not options and fillOptionsPending[itemID] then
                        Print("The game is still loading " .. name .. (settings.autoItems
                            and "; BarTab will add it once it has." or "; try again in a moment."))
                    elseif not options then
                        Print(name .. " doesn't list anything to fill it with.")
                    elseif IsContainerTracked(itemID) then
                        Print(name .. " is already tracked.")
                    else
                        DismissedContainers()[itemID] = nil
                        ImportContainer(itemID, name, options, true)
                    end
                    return
                elseif options and not IsContainerTracked(itemID) and not IsContainerDismissed(itemID) then
                    ImportContainer(itemID, name, options, true)
                end
            end
        end
    end
    if filter and not matched then
        Print("Nothing in your bags matches \"" .. filter .. "\".")
    end
end

-- Secure click overlays (filling crates) -----------------------------------
--
-- Using an item from an addon needs a secure button, and secure buttons
-- can't be changed during combat. Each crate bar that's ready to use gets an
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

-- /bartab debug item <part of a name>: saves what the game reports for matching
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
                local okData, data = false, nil
                if C_TooltipInfo and C_TooltipInfo.GetBagItem then
                    okData, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
                end
                DebugPrint("    tooltip data: " .. (not (C_TooltipInfo and C_TooltipInfo.GetBagItem) and "not on this client"
                    or not okData and ("error " .. tostring(data))
                    or type(data) ~= "table" and "nothing"
                    or (#(data.lines or {}) .. " line(s)")))
                local lines, source = GetBagItemTooltipLines(bag, slot)
                DebugPrint("    read " .. #lines .. " line(s) from " .. (source or "nowhere"))
                for _, line in ipairs(lines) do
                    DebugPrint("    tooltip: " .. line)
                end
                -- What BarTab makes of it.
                if itemID then
                    fillOptionsCache[itemID], fillOptionsTries[itemID] = nil, nil
                    local options = GetFillOptions(bag, slot, itemID)
                    local parts = {}
                    for _, option in ipairs(options or {}) do parts[#parts + 1] = option.count .. " " .. option.name end
                    DebugPrint("    BarTab reads: " .. (#parts > 0 and ("fill with " .. table.concat(parts, " or "))
                        or "no fill list") .. "; item loaded=" .. tostring(IsItemLoaded(itemID))
                        .. "; tracked=" .. tostring(IsContainerTracked(itemID))
                        .. "; auto-track fill-up items=" .. tostring(settings.autoItems and true or false))
                end
            end
        end
    end
    if found == 0 then
        DebugPrint("debug: nothing in your bags matches \"" .. filter .. "\".")
    end
    Print("Debug output saved. Type /reload to write it to disk.")
end
