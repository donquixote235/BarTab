-- BarTab: assign/unassign/untrack and the right-click menus.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

-- Shared actions (used by the right-click menu and slash commands) ---------


-- rangeGiven: the user typed a range with this assignment, so don't resize.
-- Each material + recipe pair is its own bar, keyed "material@recipeID",
-- so one material (Heavy Leather) can be tracked for several recipes.
function RecipeKey(name, recipeID)
    return string.lower(name) .. "@" .. recipeID
end

function AssignRecipe(key, recipeID, rangeGiven)
    local item = trackedItems[key]
    if not item or not recipeID then return end

    local newKey = RecipeKey(item.name, recipeID)
    if newKey ~= key then
        if trackedItems[newKey] then
            Print(item.name .. " is already tracked for that recipe.")
            return
        end
        trackedItems[key] = nil
        trackedItems[newKey] = item
        key = newKey
    end

    -- If the bar is still sized to exactly one craft of the old recipe
    -- (0 to the amount it needed), resize it to one craft of the new recipe.
    -- Custom ranges, including any with a non-zero minimum, are left alone.
    local resized
    local oldRecipeID = item.recipeID
    if not rangeGiven and oldRecipeID and oldRecipeID ~= recipeID
        and item.start == 0 then
        local oldNeed = GetReagentQuantity(oldRecipeID, item.name)
        local newNeed = GetReagentQuantity(recipeID, item.name)
        if oldNeed and item.goal == oldNeed and newNeed and newNeed > 0
            and newNeed ~= oldNeed then
            item.goal = newNeed
            item.countFrom, item.countDone = nil, nil -- a new size starts the countdown over
            resized = true
        end
    end

    item.recipeID = recipeID
    item.profession = GetOpenProfessionName() or LookUpRecipeProfession(recipeID)
    item.label = GetRecipeName(recipeID)
    item.skillLineID = nil
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" and tonumber(info.professionID) and info.professionID > 0 then
            item.skillLineID = info.professionID
        end
    end
    UpdateBars()

    local recipeName = item.label or "the selected recipe"
    local message = "Tracking " .. item.name .. " for " .. recipeName
    if resized then
        message = message .. " (bar resized to 0-" .. item.goal .. ")"
    end
    Print(message .. ".")
end

-- Tracks a material for a recipe: that material's bar for the recipe, sized
-- to one craft unless a range is given. Used by /bartab assign and the BarTab
-- button in the profession window.
function AssignMaterial(name, recipeID, startCount, goal)
    -- This material's bar for this recipe, or else a bar for the material
    -- that has no recipe yet (which becomes this recipe's bar).
    local key, item = RecipeKey(name, recipeID), nil
    item = trackedItems[key]
    if not item then
        for otherKey, other in pairs(trackedItems) do
            -- Only a plain material bar of your own; never a crate bar, or a
            -- bar for another character ("Copper Bar for Vespera").
            if not other.container and not other.recipeID and not other.altNeed and not other.virtual
                and string.lower(other.name) == string.lower(name) then
                key, item = otherKey, other
                break
            end
        end
    end

    if item then
        -- A range given with the assignment resizes the existing bar.
        if goal then
            item.start = startCount
            item.goal = goal
            item.countFrom, item.countDone = nil, nil -- a new size starts the countdown over
        end
    else
        -- New bar: use the given range, else how many one craft needs,
        -- else the item's stack size.
        if not goal then
            local perCraft = GetReagentQuantity(recipeID, name)
            if perCraft and perCraft > 0 then
                startCount, goal = 0, perCraft
            else
                local err
                name, startCount, goal, err = ParseTrackArgs(name)
                if not name then
                    Print(err or "Could not determine the item's stack size.")
                    return
                end
            end
        end

        item = {
            name = name,
            start = startCount,
            goal = goal,
            order = NextOrder()
        }
        trackedItems[key] = item
    end

    AssignRecipe(key, recipeID, goal ~= nil)
end

-- A plain material bar (no recipe). Keeps an existing bar's recipe and place.
-- collect: true puts it in the Items section (Alt-Shift-click); nil keeps
-- the bar's current section.
function TrackMaterial(name, startCount, goal, collect)
    local key = string.lower(name)
    local oldItem = trackedItems[key]
    if collect == nil then collect = oldItem and oldItem.collect end
    trackedItems[key] = {
        itemID = oldItem and oldItem.itemID,
        collect = collect or nil,
        name = name,
        start = startCount,
        goal = goal,
        recipeID = oldItem and oldItem.recipeID,
        profession = oldItem and oldItem.profession,
        order = (oldItem and oldItem.order) or NextOrder()
    }
    UpdateBars()
    Print("Tracking " .. name .. " (" .. startCount .. "-" .. goal .. ").")
end

-- Finds the one bar a typed name refers to, by the name shown on the bar
-- (recipe label) or the material it counts. If more than one bar matches,
-- lists them and returns nil rather than guessing.
function FindKeyByName(text, command)
    local wanted = string.lower(text)
    local function collect(match)
        local keys = {}
        for key, item in pairs(trackedItems) do
            if match(key, item) then keys[#keys + 1] = key end
        end
        return keys
    end

    local keys = collect(function(key, item)
        return key == wanted or string.lower(DisplayName(item)) == wanted
            or string.lower(item.name) == wanted
    end)

    if #keys == 1 then
        return keys[1]
    elseif #keys == 0 then
        Print("That item is not being tracked.")
    else
        local names = {}
        for _, key in ipairs(keys) do
            names[#names + 1] = DisplayName(trackedItems[key])
        end
        table.sort(names)
        Print(text .. " matches several bars: " .. table.concat(names, ", ")
            .. ". Use /bartab " .. command .. " with the recipe name, or right-click the bar.")
    end
end

function UnassignRecipe(key)
    local item = trackedItems[key]
    if not item then
        Print("That item is not being tracked.")
        return
    end
    if not item.recipeID then
        Print(item.name .. " has no recipe assigned.")
        return
    end

    local label = DisplayName(item)
    item.recipeID = nil
    item.profession = nil
    item.label = nil
    UpdateBars()
    Print("Unassigned the recipe from " .. item.name .. " (was " .. label .. ").")
end

function SetItemActive(key, active)
    local item = trackedItems[key]
    if not item then return end

    item.inactive = (not active) or nil
    UpdateBars()
    if active then
        Print("Moved " .. item.name .. " back to active.")
    else
        Print("Moved " .. item.name .. " to Inactive.")
    end
end

function UntrackItem(key)
    local item = trackedItems[key]
    if not item then
        Print("That item is not being tracked.")
        return
    end

    trackedItems[key] = nil
    NoteUntrackedContainers({ item })
    UpdateBars()
    Print("Stopped tracking " .. DisplayName(item) .. ".")
end

-- Right-click menu --------------------------------------------------------


-- Builds a menu from groups: { heading, entries } in order, leaving out
-- empty groups. A group without a heading goes under a plain line.
function GroupedEntries(groups)
    local entries = {}
    for _, group in ipairs(groups) do
        if #group.entries > 0 then
            if group.heading then
                entries[#entries + 1] = { heading = group.heading }
            elseif #entries > 0 then
                entries[#entries + 1] = { divider = true }
            end
            for _, entry in ipairs(group.entries) do entries[#entries + 1] = entry end
        end
    end
    return entries
end

-- Opens a right-click menu: entries are { text, function }; { heading = text }
-- starts a labeled group, { divider = true } draws a line.
function ShowMenu(owner, title, entries)
    -- Modern menu system.
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle(title)
            for _, entry in ipairs(entries) do
                if entry.heading then
                    root:CreateDivider()
                    root:CreateTitle(entry.heading)
                elseif entry.divider then
                    root:CreateDivider()
                elseif entry.choices then
                    -- A submenu of choices, the current one marked.
                    local submenu = root:CreateButton(entry[1])
                    for _, choice in ipairs(entry.choices) do
                        if choice.check then
                            -- A checkbox (on/off) rather than one of the choices.
                            submenu:CreateDivider()
                            -- isSelected reads the live state: a checkbox keeps the
                            -- menu open, so it redraws after each click.
                            submenu:CreateCheckbox(choice[1],
                                function()
                                    if choice.isSelected then return choice.isSelected() end
                                    return choice.selected
                                end,
                                function() choice[2]() end)
                        else
                            submenu:CreateRadio(choice[1],
                                function()
                                    if choice.isSelected then return choice.isSelected() end
                                    return choice.selected
                                end,
                                function() choice[2]() end)
                        end
                    end
                elseif entry.check then
                    root:CreateCheckbox(entry[1],
                        function()
                            if entry.isSelected then return entry.isSelected() end
                            return entry.selected
                        end,
                        function() entry[2]() end)
                else
                    root:CreateButton(entry[1], entry[2])
                end
            end
        end)
        return
    end

    -- Older dropdown menu system.
    if UIDropDownMenu_Initialize and ToggleDropDownMenu then
        legacyMenuFrame = legacyMenuFrame or CreateFrame("Frame",
            "BarTabMenu", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(legacyMenuFrame, function()
            UIDropDownMenu_AddButton({
                text = title, isTitle = true, notCheckable = true
            })
            for _, entry in ipairs(entries) do
                if entry.heading then
                    UIDropDownMenu_AddButton({ text = entry.heading, isTitle = true, notCheckable = true })
                elseif entry.divider then
                    UIDropDownMenu_AddButton({ text = "", disabled = true, notCheckable = true })
                elseif entry.choices then
                    -- No submenus here: list them as "Focus on: X".
                    for _, choice in ipairs(entry.choices) do
                        UIDropDownMenu_AddButton({
                            text = entry[1] .. ": " .. choice[1], func = choice[2],
                            checked = choice.selected,
                        })
                    end
                elseif entry.check then
                    UIDropDownMenu_AddButton({
                        text = entry[1], func = entry[2], checked = entry.selected,
                        isNotRadio = true, keepShownOnClick = false,
                    })
                else
                    UIDropDownMenu_AddButton({
                        text = entry[1], func = entry[2], notCheckable = true
                    })
                end
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, legacyMenuFrame, "cursor", 0, 0)
    end
end

-- "Focus on" submenu for a fill-up item: each material it accepts, plus all.
function FocusMenuEntry(container)
    settings.containerFocus = settings.containerFocus or {}
    local current = settings.containerFocus[container.id]
    local function setFocus(value, label)
        settings.containerFocus[container.id] = value
        UpdateBars()
        Print(container.name .. ": " .. label .. ".")
    end
    local choices = {
        { "All materials", function() setFocus(nil, "showing all materials") end,
          selected = current == nil },
    }
    for _, option in ipairs(container.options or {}) do
        local key = string.lower(option.name)
        choices[#choices + 1] = {
            option.count .. " " .. option.name,
            function() setFocus(key, "focusing on " .. option.name) end,
            selected = current == key,
        }
    end
    return { "Focus on", choices = choices }
end

-- "Focus on" submenu for a recipe with two or more ingredient bars.
function RecipeFocusMenuEntry(recipeID, recipeName)
    local bars = {}
    for _, other in pairs(trackedItems) do
        if other.recipeID == recipeID and not other.container then
            bars[#bars + 1] = other
        end
    end
    if #bars < 2 then return nil end
    table.sort(bars, function(a, b) return (a.order or 0) < (b.order or 0) end)

    settings.recipeFocus = settings.recipeFocus or {}
    local current = settings.recipeFocus[recipeID]
    local function setFocus(value, label)
        settings.recipeFocus[recipeID] = value
        UpdateBars()
        Print(recipeName .. ": " .. label .. ".")
    end
    local choices = {
        { "All ingredients", function() setFocus(nil, "showing all ingredients") end,
          selected = current == nil },
    }
    for _, bar in ipairs(bars) do
        local key = string.lower(bar.name)
        choices[#choices + 1] = {
            bar.name,
            function() setFocus(key, "focusing on " .. bar.name) end,
            selected = current == key,
        }
    end
    return { "Focus on", choices = choices }
end

ShowItemMenu = function(owner, itemKey)
    local item = itemKey and trackedItems[itemKey]
    if not item then return end
    GameTooltip:Hide()

    -- A recipe bar: the menu of the recipe's own bars.
    if item.recBar then
        local real = item.recipes and item.recipes[1]
        if real and trackedItems[real] then ShowItemMenu(owner, real) end
        return
    end
    -- A material bar: its recipes, and switching the display back.
    if item.matBar then
        local entries = {}
        for _, recipe in ipairs(MaterialRecipes(item)) do
            entries[#entries + 1] = { "Open " .. recipe.name, function() OpenBarRecipe(recipe.key) end }
        end
        entries[#entries + 1] = { divider = true }
        entries[#entries + 1] = { "Show each ingredient for " .. item.profession, function()
            SetMaterialMode(item.profession, "ingredient")
        end }
        entries[#entries + 1] = { "Show one bar per recipe for " .. item.profession, function()
            SetMaterialMode(item.profession, "recipe")
        end }
        ShowMenu(owner, item.name, entries)
        return
    end

    -- A bar for another character's needs: only hiding makes sense here.
    if item.altNeed then
        ShowMenu(owner, DisplayName(item), {
            { "Don't show this for " .. item.altName, function()
                settings.altShopHidden = settings.altShopHidden or {}
                settings.altShopHidden[itemKey] = true
                SyncAltNeedBars()
            end },
            { "Turn off shopping for other characters", function()
                SetCharSetting("altShopping", false)
                SyncAltNeedBars()
                Print("Shopping for other characters is off on this character (Shopping tab in /bartab config to turn it on).")
            end },
        })
        return
    end

    -- Only offered while a profession window is open with a recipe selected.
    local selectedRecipeID = GetSelectedRecipeID()

    local top, crafting, rules, bar = {}, {}, {}, {}
    if item.container then
        top[#top + 1] = FocusMenuEntry(item.container)
    elseif item.recipeID then
        local focusEntry = RecipeFocusMenuEntry(item.recipeID, DisplayName(item))
        if focusEntry then top[#top + 1] = focusEntry end
    end
    if item.recipeID and not item.container then
        crafting[#crafting + 1] = { "Open recipe", function() OpenBarRecipe(itemKey) end }
        local craftsEntry = IsOutputBar(item) and GoalCraftsMenuEntry(item) or CraftsMenuEntry(item)
        if craftsEntry then crafting[#crafting + 1] = craftsEntry end
    end
    -- Make missing materials first (always offered here, whatever the
    -- setting says clicks do).
    if item.recipeID and not item.container and not item.notLearned then
        local craftable = GetCraftableCount(item.recipeID) or 0
        local wanted = ChainWanted(item, "max") or CHAIN_MOST
        local plan = PlanChain(item, wanted)
        if plan and plan.crafts > craftable then
            crafting[#crafting + 1] = { ("Craft %d, making materials first"):format(plan.crafts), function()
                TryChainCraft(item, "max", true)
            end }
        elseif craftable < 1 then
            local prep = PlanChain(item, wanted, true)
            if prep and prep.prepOnly then
                crafting[#crafting + 1] = { ("Make materials for %d (vendor items later)"):format(prep.crafts),
                    function() TryChainCraft(item, "max", true) end }
            end
        end
    end
    -- Ingredients the recipe takes that have no bar yet.
    if item.recipeID and not item.container and not IsOutputBar(item) then
        local others = UntrackedIngredients(item.recipeID)
        if #others > 0 then
            local names = {}
            for _, reagent in ipairs(others) do names[#names + 1] = reagent.name end
            crafting[#crafting + 1] = { "Also track its other ingredients (" .. JoinNames(names, 3) .. ")",
                function() TrackOtherIngredients(item.recipeID) end }
        end
    end
    local producer = CanTrackChain(item)
    if producer then
        -- One craft; Alt-click for everything the bar is short of.
        local crafts = ChainShortfallCrafts(item, producer)
        local label = "Also track how to make " .. item.name
        if crafts > 1 then label = label .. " (Alt: " .. crafts .. " crafts)" end
        crafting[#crafting + 1] = { label, function()
            TrackChain(itemKey, IsAltKeyDown())
        end }
    end
    if item.recipeID and not item.container then
        rules[#rules + 1] = AfterCraftMenuEntry(item)
        if not IsOutputBar(item) then
            rules[#rules + 1] = CountdownMenuEntry(item)
        end
        rules[#rules + 1] = StopMenuEntry(item)
    end
    if not item.container then
        rules[#rules + 1] = VendorMenuEntry(item)
    end
    -- Only when the recipe selected in the profession window uses this
    -- material and isn't already this bar's recipe.
    if selectedRecipeID and not item.container
        and selectedRecipeID ~= item.recipeID
        and GetReagentQuantity(selectedRecipeID, item.name) then
        bar[#bar + 1] = {
            "Assign to " .. (GetRecipeName(selectedRecipeID) or "the selected recipe"),
            function() AssignRecipe(itemKey, selectedRecipeID) end,
        }
    end
    if item.recipeID then
        bar[#bar + 1] = { "Unassign", function()
            UnassignRecipe(itemKey)
        end }
    end
    if item.inactive then
        bar[#bar + 1] = { "Move to Active", function() SetItemActive(itemKey, true) end }
    else
        bar[#bar + 1] = { "Move to Inactive", function() SetItemActive(itemKey, false) end }
    end
    if IsShareable(item) then
        bar[#bar + 1] = { "Share this bar", function()
            ShareKeys({ itemKey }, DisplayName(item))
        end }
    end
    bar[#bar + 1] = { "Untrack", function() UntrackItem(itemKey) end }

    local entries = GroupedEntries({
        { entries = top },
        { heading = "Crafting", entries = crafting },
        { heading = "Rules", entries = rules },
        { heading = "This bar", entries = bar },
    })
    ShowMenu(owner, DisplayName(item), entries)
end

-- Untrack all (sections and subsections) ------------------------------------

function GetGroupKeys(section, group)
    local keys, seen = {}, {}
    for _, key in ipairs(GetSectionKeys(section)) do
        local item = trackedItems[key]
        if not group or GetGroup(item) == group then
            -- A material bar stands for the recipe bars behind it.
            local list = item.virtual and item.recipes or { key }
            for _, real in ipairs(list) do
                if not seen[real] and not (trackedItems[real] and trackedItems[real].altNeed) then
                    seen[real] = true
                    keys[#keys + 1] = real
                end
            end
        end
    end
    -- Bars hidden behind material or recipe bars, or for being vendor-bought
    -- (vials), belong to the group too.
    for _, key in ipairs(GetSortedKeys()) do
        local item = trackedItems[key]
        if not seen[key] and not item.virtual and not item.altNeed and GetSection(item) == section
            and (not group or GetGroup(item) == group)
            and (IsMaterialModeBar(item) or HidesVendorMaterial(item)) then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    return keys
end

function UntrackKeys(keys, label)
    local removed = {}
    for _, key in ipairs(keys) do
        removed[#removed + 1] = trackedItems[key]
        trackedItems[key] = nil
    end
    NoteUntrackedContainers(removed)
    UpdateBars()
    Print("Stopped tracking " .. #keys .. " item(s) in " .. label .. ".")
end

-- Asks before removing several bars at once.
function ConfirmUntrackKeys(keys, label)
    if #keys == 0 then return end
    if not (StaticPopupDialogs and StaticPopup_Show) then
        UntrackKeys(keys, label)
        return
    end

    StaticPopupDialogs.BARTAB_UNTRACK_ALL = StaticPopupDialogs.BARTAB_UNTRACK_ALL or {
        text = "Untrack all %s item(s) in %s?",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, data)
            UntrackKeys(data.keys, data.label)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("BARTAB_UNTRACK_ALL", tostring(#keys), label,
        { keys = keys, label = label })
end

function SetKeysActive(keys, active, label)
    for _, key in ipairs(keys) do
        trackedItems[key].inactive = (not active) or nil
    end
    UpdateBars()
    Print("Moved " .. #keys .. " item(s) in " .. label
        .. (active and " back to active." or " to Inactive."))
end

ShowGroupMenu = function(owner, section, group)
    GameTooltip:Hide()
    local label = group and (section .. " - " .. group) or section
    local keys = GetGroupKeys(section, group)
    if #keys == 0 then return end

    local activeKeys, inactiveKeys = {}, {}
    for _, key in ipairs(keys) do
        if trackedItems[key].inactive then
            inactiveKeys[#inactiveKeys + 1] = key
        else
            activeKeys[#activeKeys + 1] = key
        end
    end

    local entries = {}
    -- A profession's subsection: one bar per material, or each ingredient.
    if section == CRAFT_SECTION and group and MaterialMode ~= nil
        and group ~= OTHER_GROUP and group ~= INACTIVE_GROUP and group ~= ALT_GROUP then
        local current = MaterialMode(group)
        for _, mode in ipairs(BAR_MODES) do
            if mode.key ~= current then
                entries[#entries + 1] = { mode.menu, function() SetMaterialMode(group, mode.key) end }
            end
        end
    end
    if #activeKeys > 0 then
        entries[#entries + 1] = { "Move all to Inactive (" .. #activeKeys .. ")", function()
            SetKeysActive(activeKeys, false, label)
        end }
    end
    -- Only offered on the Inactive subsection itself.
    if group == INACTIVE_GROUP and #inactiveKeys > 0 then
        entries[#entries + 1] = { "Move all to Active (" .. #inactiveKeys .. ")", function()
            SetKeysActive(inactiveKeys, true, label)
        end }
    end
    local shareable = 0
    for _, key in ipairs(keys) do
        if IsShareable(trackedItems[key]) then shareable = shareable + 1 end
    end
    if shareable > 0 then
        entries[#entries + 1] = { "Share these bars (" .. shareable .. ")", function()
            ShareKeys(keys, label)
        end }
    end
    entries[#entries + 1] = { "Untrack all (" .. #keys .. ")", function()
        ConfirmUntrackKeys(keys, label)
    end }

    -- A fill-up item's subsection also offers "Focus on".
    local first = trackedItems[keys[1]]
    if group and first and first.container and group == first.container.name then
        table.insert(entries, 1, FocusMenuEntry(first.container))
    end

    ShowMenu(owner, label, entries)
end

-- "Track in BarTab" button in the profession window -----------------------------
--
-- A small BarTab button on the recipe details panel. Clicking it lists the
-- selected recipe's ingredients; picking one tracks it for that recipe, the
-- same as /bartab assign.

-- Check marks on tracked recipes in the profession window's recipe list
-- (settings.recipeListMarks, on unless turned off). Only a texture is added
-- to each row; the rows themselves are left alone.
function RecipeListScrollBox()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local list = page and page.RecipeList
    return list and list.ScrollBox
end

-- The skill-up arrows the profession window draws for each recipe color,
-- noted from its recipe list so bar names can use the very same icons
-- (settings.skillUpIcons[color] = { atlas= } or { file=, coords= }).
function NoteSkillUpIcon(row, recipeInfo)
    local icon = row.SkillUps and (row.SkillUps.Icon or row.SkillUps.icon)
    if not (icon and icon.IsShown and icon:IsShown()) then return end
    local difficulty = recipeInfo.relativeDifficulty
    if difficulty == nil then difficulty = recipeInfo.difficulty end
    local color = difficulty ~= nil and DIFFICULTY_COLORS[difficulty]
    if not color or color == "gray" then return end
    settings.skillUpIcons = settings.skillUpIcons or {}
    local atlas = icon.GetAtlas and icon:GetAtlas()
    if atlas and atlas ~= "" then
        settings.skillUpIcons[color] = { atlas = atlas }
        return
    end
    local file = icon.GetTexture and icon:GetTexture()
    if file then
        local coords = { icon:GetTexCoord() }
        settings.skillUpIcons[color] = { file = file, coords = coords }
    end
end

function MarkRecipeRow(row, elementData)
    if not row then return end
    elementData = elementData or (row.GetElementData and row:GetElementData())
    local data = elementData and elementData.GetData and elementData:GetData()
    local recipeInfo = type(data) == "table" and data.recipeInfo
    local recipeID = type(recipeInfo) == "table" and recipeInfo.recipeID
    if recipeID then pcall(NoteSkillUpIcon, row, recipeInfo) end
    local show = settings.recipeListMarks ~= false and recipeID and IsTrackedRecipe(recipeID) or false
    if show and not row.barTabMark then
        local mark = row:CreateTexture(nil, "OVERLAY")
        mark:SetSize(12, 12)
        mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        -- At the row's right edge: one column down the list, clear of the
        -- skill-up arrows (at the left edge), the name and its "[3]" count,
        -- and inside the row (the list hides anything drawn outside it).
        mark:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.barTabMark = mark
    end
    if row.barTabMark then row.barTabMark:SetShown(show) end
end

function HookRecipeList()
    if recipeListHooked then return end
    local scrollBox = RecipeListScrollBox()
    if not (scrollBox and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback) then return end
    ScrollUtil.AddAcquiredFrameCallback(scrollBox, function(_, row, elementData)
        local ok, err = pcall(MarkRecipeRow, row, elementData)
        if not ok then ReportError("recipe list", err) end
    end, recipeListHookOwner, true)
    recipeListHooked = true
end
recipeListHookOwner = {}

-- /bartab debug recipes: where the parts of the tracked rows sit.
function DebugRecipeList()
    settings.debugLog = { "BarTab debug recipes" }
    local function Line(text)
        Print(text)
        table.insert(settings.debugLog, text)
    end
    local scrollBox = RecipeListScrollBox()
    Line(("hooked=%s open=%s list=%s"):format(tostring(recipeListHooked), tostring(ProfessionsOpen()),
        tostring(scrollBox ~= nil)))
    if not (scrollBox and scrollBox.ForEachFrame) then return end
    local function Edge(region)
        if type(region) ~= "table" or not region.GetLeft then return "none" end
        local ok, left, right = pcall(function() return region:GetLeft(), region:GetRight() end)
        local shown = region.IsShown and region:IsShown()
        if not ok then return "?" end
        return ("%s-%s%s"):format(tostring(left and math.floor(left)), tostring(right and math.floor(right)),
            shown and "" or " hidden")
    end
    local count = 0
    scrollBox:ForEachFrame(function(row)
        local data = row.GetElementData and row:GetElementData()
        data = data and data.GetData and data:GetData()
        local info = type(data) == "table" and data.recipeInfo
        if info and count < 4 and IsTrackedRecipe(info.recipeID) then
            count = count + 1
            local children = {}
            for key, value in pairs(row) do
                if type(key) == "string" and type(value) == "table" and value.GetObjectType then
                    children[#children + 1] = key
                end
            end
            table.sort(children)
            Line(("%s: row %s, label %s, skillups %s, mark %s visible=%s"):format(tostring(info.name),
                Edge(row), Edge(row.Label), Edge(row.SkillUps), Edge(row.barTabMark),
                tostring(row.barTabMark and row.barTabMark.IsVisible and row.barTabMark:IsVisible())))
            Line("  parts: " .. table.concat(children, ", "))
        end
    end)
    if count == 0 then Line("No tracked recipes showing in the list.") end
    Line("Saved for bug reports with /reload.")
end

-- Bars added or removed: update the marks on the rows showing now.
function RefreshRecipeListMarks()
    if not recipeListHooked or not ProfessionsOpen() then return end
    local scrollBox = RecipeListScrollBox()
    if scrollBox and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(function(row) pcall(MarkRecipeRow, row) end)
    end
end

-- How many bars a recipe has (fill-up items aside).
function RecipeBarCount(recipeID)
    if not recipeID then return 0 end
    local count = 0
    for _, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container then count = count + 1 end
    end
    return count
end

function ShowProfessionMenu(owner)
    local recipeID = GetSelectedRecipeID()
    if not recipeID then
        Print("Select a recipe first.")
        return
    end
    local reagents = GetRecipeReagents(recipeID) or {}
    if #reagents == 0 then
        Print("Couldn't read this recipe's ingredients.")
        return
    end

    local track, goals, bars, more = {}, {}, {}, {}
    for _, reagent in ipairs(reagents) do
        local tracked = trackedItems[RecipeKey(reagent.name, recipeID)] ~= nil
        track[#track + 1] = {
            reagent.name .. " (" .. reagent.need .. " per craft)" .. (tracked and "  - tracked" or ""),
            function() AssignMaterial(reagent.name, recipeID) end,
        }
    end
    if #reagents > 1 then
        track[#track + 1] = { "All ingredients", function()
            for _, reagent in ipairs(reagents) do
                AssignMaterial(reagent.name, recipeID)
            end
        end }
    end
    track[#track + 1] = { "With settings...", function()
        TrackWithOptions(recipeID)
    end }

    local outputID = GetRecipeOutput(recipeID)
    local outputName = outputID and GetItemNameByID(outputID)
    if outputName then
        local bar = trackedItems[RecipeKey(outputName, recipeID)]
        goals[#goals + 1] = { "Make until I have... (" .. outputName .. ")", function()
            AskMakeGoal(recipeID, bar and bar.goal)
        end }
    end
    goals[#goals + 1] = { "Make until I reach... (skill level)", function()
        AskSkillGoal(recipeID)
    end }

    -- Once the recipe has bars: the same recipe settings as a bar's
    -- right-click menu, for all of its bars.
    local barKeys, main = {}, nil
    for key, item in pairs(trackedItems) do
        if item.recipeID == recipeID and not item.container then
            barKeys[#barKeys + 1] = key
            if not IsOutputBar(item) and (not main or (item.order or 0) < (main.order or 0)) then
                main = item
            end
        end
    end
    if #barKeys > 0 then
        local item = main or trackedItems[barKeys[1]]
        local craftsEntry = main and CraftsMenuEntry(main) or (IsOutputBar(item) and GoalCraftsMenuEntry(item))
        if craftsEntry then bars[#bars + 1] = craftsEntry end
        bars[#bars + 1] = AfterCraftMenuEntry(item, true)
        if main then
            bars[#bars + 1] = CountdownMenuEntry(main)
        end
        bars[#bars + 1] = StopMenuEntry(item)
        bars[#bars + 1] = { ("Untrack this recipe (%d %s)"):format(#barKeys,
            #barKeys == 1 and "bar" or "bars"), function()
            local removed = {}
            for _, key in ipairs(barKeys) do
                if trackedItems[key] then
                    removed[#removed + 1] = trackedItems[key]
                    trackedItems[key] = nil
                end
            end
            NoteUntrackedContainers(removed)
            UpdateBars()
            Print(("Stopped tracking %s (%d %s)."):format(GetRecipeName(recipeID) or "the recipe",
                #removed, #removed == 1 and "bar" or "bars"))
        end }
    end
    more[#more + 1] = { "What to craft next...", function() ShowCraftNext() end }
    more[#more + 1] = { "Profit calculator...", function() ShowProfitWindow() end }
    local removedCount = #RemovedBars()
    if removedCount > 0 then
        more[#more + 1] = { ("Recently removed (%d)..."):format(removedCount),
            function() ShowRemovedMenu(owner) end }
    end

    local entries = GroupedEntries({
        { heading = "Track", entries = track },
        { heading = "Goals", entries = goals },
        { heading = ("Its bars (%d)"):format(#barKeys), entries = bars },
        { entries = more },
    })
    ShowMenu(owner, "BarTab: " .. (GetRecipeName(recipeID) or "this recipe"), entries)
end

do
    local button

    local function CreateProfessionButton()
        local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
        local form = page and page.SchematicForm
        if button or not form then return end

        button = CreateFrame("Button", "BarTabProfessionButton", form)
        button:SetSize(24, 24)
        -- Just left of Blizzard's favorite star (not on top of it).
        local star = form.FavoriteButton
        if star and star.GetObjectType then
            button:SetPoint("RIGHT", star, "LEFT", -6, 0)
        else
            button:SetPoint("TOPRIGHT", form, "TOPRIGHT", -44, -12)
        end
        button:SetFrameLevel(form:GetFrameLevel() + 20)
        button:SetNormalTexture("Interface\\AddOns\\BarTab\\Media\\icon")
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(self) ShowProfessionMenu(self) end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Track in BarTab")
            local count = RecipeBarCount(GetSelectedRecipeID())
            if count > 0 then
                GameTooltip:AddLine(("Tracked: %d %s. Click for its settings."):format(count,
                    count == 1 and "bar" or "bars"), 0.4, 1, 0.4, true)
            else
                GameTooltip:AddLine("Pick one of this recipe's ingredients to track as a bar.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)

        -- A check mark on the button while the selected recipe has bars
        -- (checked a few times a second while the window is open).
        local mark = button:CreateTexture(nil, "OVERLAY")
        mark:SetSize(14, 14)
        mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
        mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        mark:Hide()
        button.trackedMark = mark
        -- Blizzard's "Track Recipe" checkbox, optionally tracking in BarTab.
        local box = form.TrackRecipeCheckbox
        if box and box.Checkbox then box = box.Checkbox end
        local boxLabel = form.TrackRecipeCheckbox and (form.TrackRecipeCheckbox.text
            or form.TrackRecipeCheckbox.Text or (box and (box.text or box.Text)))
        local originalLabel = boxLabel and boxLabel.GetText and boxLabel:GetText()
        -- While BarTab is in charge, a button laid over the checkbox (and its
        -- label) takes the clicks, so the game's own tracking never runs.
        local cover
        if box then
            local outer = form.TrackRecipeCheckbox
            cover = CreateFrame("Button", nil, form)
            cover:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
            if boxLabel and boxLabel.GetRight then
                cover:SetPoint("BOTTOMRIGHT", boxLabel, "BOTTOMRIGHT", 2, -2)
            elseif outer and outer ~= box then
                cover:SetAllPoints(outer)
            else
                cover:SetAllPoints(box)
            end
            cover:SetFrameLevel((box:GetFrameLevel() or 1) + 10)
            cover:RegisterForClicks("LeftButtonUp")
            cover:SetScript("OnClick", function()
                Safe("track checkbox", function()
                    local recipeID = GetSelectedRecipeID()
                    if not recipeID then return end
                    local name = GetRecipeName(recipeID) or "the recipe"
                    if IsTrackedRecipe(recipeID) then
                        UntrackRecipe(recipeID)
                        Print("Stopped tracking " .. name .. ".")
                    else
                        -- The "Track with settings" window: ingredients,
                        -- crafts and rules, chosen up front.
                        TrackWithOptions(recipeID)
                    end
                    box:SetChecked(IsTrackedRecipe(recipeID))
                end)()
            end)
            cover:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Track in BarTab")
                GameTooltip:AddLine("Opens BarTab's Track with settings window for this recipe, or untracks its bars if it has some. Change this in BarTab's settings (Recipes tab).", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            cover:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cover:Hide()
        end

        local elapsedSince = 1
        button:SetScript("OnUpdate", function(_, elapsed)
            elapsedSince = elapsedSince + (elapsed or 0)
            if elapsedSince < 0.25 then return end
            elapsedSince = 0
            local ok, count = pcall(RecipeBarCount, GetSelectedRecipeID())
            mark:SetShown(ok and count > 0)
            -- The checkbox shows BarTab's tracking while it's in charge.
            if cover then cover:SetShown(settings.trackCheckboxBarTab and box:IsVisible() or false) end
            if box and settings.trackCheckboxBarTab then
                box:SetChecked(ok and count > 0)
                if boxLabel and boxLabel.SetText then boxLabel:SetText("Track in BarTab") end
            elseif boxLabel and originalLabel and boxLabel.GetText and boxLabel:GetText() ~= originalLabel then
                boxLabel:SetText(originalLabel)
                if box and C_TradeSkillUI and C_TradeSkillUI.IsRecipeTracked then
                    local recipeID = GetSelectedRecipeID()
                    local okTracked, tracked = pcall(C_TradeSkillUI.IsRecipeTracked, recipeID, false)
                    if recipeID and okTracked then box:SetChecked(tracked and true or false) end
                end
            end
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- The profession window is its own Blizzard addon, loaded on first use.
    local watcher = CreateFrame("Frame")
    watcher.barTabOwn = true -- never muted by BarTab's silent profession loads
    watcher:RegisterEvent("ADDON_LOADED")
    pcall(watcher.RegisterEvent, watcher, "TRADE_SKILL_SHOW")
    watcher:SetScript("OnEvent", function(_, event, arg1)
        if event ~= "ADDON_LOADED" or arg1 == "Blizzard_Professions" then
            pcall(CreateProfessionButton)
            pcall(HookRecipeList)
        end
    end)
    pcall(CreateProfessionButton) -- never let this stop BarTab from loading
    pcall(HookRecipeList)
end


-- Alt-Shift-click an item (bags, bank, chat links, loot, ...) -------------
-- (Not in the auction house window: there that click opens the listings.)
-- Fill-up items get their bars right away; anything else asks for a goal,
-- with a button to track it for the open recipe when that recipe uses it.

-- "20" -> 0, 20; "5-20" -> 5, 20; otherwise nil.
function ParseRangeText(text)
    local low, high = (text or ""):match("^%s*(%d+)%s*%-%s*(%d+)%s*$")
    if low then return tonumber(low), tonumber(high) end
    high = (text or ""):match("^%s*(%d+)%s*$")
    if high then return 0, tonumber(high) end
end

function GetLinkFillOptions(link, itemID)
    if fillOptionsCache[itemID] ~= nil then return fillOptionsCache[itemID] end
    local lines = {}
    local surface = TooltipUtil and TooltipUtil.SurfaceArgs
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and type(data) == "table" then
            if surface then pcall(surface, data) end
            for _, line in ipairs(data.lines or {}) do
                if surface and not line.leftText then pcall(surface, line) end
                if line.leftText and line.leftText ~= "" then lines[#lines + 1] = line.leftText end
            end
        end
    end
    if #lines == 0 then
        -- Tooltip data came back empty: read a hidden tooltip instead.
        local tip = GetScanTooltip()
        if tip and tip.SetHyperlink then
            tip:SetOwner(_G.WorldFrame or UIParent, "ANCHOR_NONE")
            tip:ClearLines()
            if pcall(tip.SetHyperlink, tip, link) then
                for i = 1, (tip.NumLines and tip:NumLines()) or 0 do
                    local text = _G["BarTabScanTooltipTextLeft" .. i]
                    text = text and text:GetText()
                    if text and text ~= "" then lines[#lines + 1] = text end
                end
            end
            tip:Hide()
        end
    end
    local useText = FindFillText(lines)
    local parsed = useText and ParseFillOptions(useText)
    if parsed and #parsed > 0 then
        fillOptionsCache[itemID] = parsed
        return parsed
    end
    return false -- not cached: the tooltip may not have loaded yet
end

-- The Track dialog: pick Items, Crafting, or the open recipe, and a goal.
TRACK_MODES = {
    { key = "items", label = "Item (Items section)" },
    { key = "crafting", label = "Crafting material" },
    { key = "recipe", label = "For " },
}

function RangeText(startCount, goal)
    if (startCount or 0) > 0 then return startCount .. "-" .. goal end
    return tostring(goal)
end

-- The goal box's starting text for a mode: the bar's current range if
-- there is one, else one craft (recipe) or a stack.
function DefaultGoalText(data, mode)
    if mode == "recipe" then
        local bar = trackedItems[RecipeKey(data.name, data.recipeID)]
        if bar then return RangeText(bar.start, bar.goal) end
        local perCraft = GetReagentQuantity(data.recipeID, data.name)
        if perCraft and perCraft > 0 then return tostring(perCraft) end
    end
    local bar = trackedItems[string.lower(data.name)]
    if bar and not bar.container then
        return RangeText(bar.start, bar.goal)
    end
    return tostring(GetStackSize(data.name) or 20)
end

function TrackFromDialog(data, mode, text)
    local startCount, goal = ParseRangeText(text)
    if not goal then
        Print("Enter a goal like 20 or a range like 5-20.")
        return false
    end
    if goal <= startCount then
        Print("Max must be greater than min.")
        return false
    end
    local key
    if mode == "recipe" then
        AssignMaterial(data.name, data.recipeID, startCount, goal)
        key = RecipeKey(data.name, data.recipeID)
    else
        TrackMaterial(data.name, startCount, goal, mode == "items")
        key = string.lower(data.name)
    end
    -- The link said exactly which item this is.
    if data.itemID and trackedItems[key] then trackedItems[key].itemID = data.itemID end
    return true
end

-- Switching type swaps the goal for that type's default, unless you typed one.
function SetTrackMode(frame, mode)
    local box = frame.goalBox
    if frame.mode and box:GetText() == DefaultGoalText(frame.data, frame.mode) then
        box:SetText(DefaultGoalText(frame.data, mode))
    end
    frame.mode = mode
    for _, radio in ipairs(frame.radios) do
        radio:SetChecked(radio.mode == mode)
    end
end

function CreateTrackDialog()
    local ok, frame = pcall(CreateFrame, "Frame", "BarTabTrackFrame", UIParent,
        "BasicFrameTemplateWithInset")
    if not ok then
        frame = CreateFrame("Frame", "BarTabTrackFrame", UIParent, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    frame:SetSize(300, 200)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -135)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "BarTabTrackFrame") -- Escape closes it

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -6)
    title:SetText("Track in BarTab")

    frame.itemText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.itemText:SetPoint("TOPLEFT", 16, -32)
    frame.itemText:SetPoint("RIGHT", -16, 0)
    frame.itemText:SetJustifyH("LEFT")

    frame.radios = {}
    for i, info in ipairs(TRACK_MODES) do
        -- Round radio buttons; a checkbox if this client lacks the template.
        local made, radio = pcall(CreateFrame, "CheckButton", nil, frame, "UIRadioButtonTemplate")
        if made and radio then
            radio:SetSize(16, 16)
            radio:SetPoint("TOPLEFT", 18, -54 - (i - 1) * 24)
        else
            radio = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
            radio:SetSize(24, 24)
            radio:SetPoint("TOPLEFT", 14, -50 - (i - 1) * 24)
        end
        radio.mode = info.key
        radio.label = radio:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        radio.label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
        radio.label:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
        radio.label:SetJustifyH("LEFT")
        radio.label:SetWordWrap(false)
        radio.label:SetText(info.label)
        radio:SetScript("OnClick", function(self) SetTrackMode(frame, self.mode) end)
        frame.radios[i] = radio
    end

    frame.goalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.goalLabel:SetText("Goal (like 20, or 5-20):")

    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetSize(70, 20)
    box:SetPoint("LEFT", frame.goalLabel, "RIGHT", 10, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(12)
    frame.goalBox = box

    local function accept()
        if TrackFromDialog(frame.data, frame.mode, box:GetText()) then
            frame:Hide()
        end
    end
    box:SetScript("OnEnterPressed", accept)
    box:SetScript("OnEscapePressed", function() frame:Hide() end)

    local track = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    track:SetSize(100, 22)
    track:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 12)
    track:SetText("Track")
    track:SetScript("OnClick", accept)

    local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancel:SetSize(100, 22)
    cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 12)
    cancel:SetText(CANCEL or "Cancel")
    cancel:SetScript("OnClick", function() frame:Hide() end)

    frame:Hide()
    return frame
end

function ShowTrackDialog(name, itemID)
    -- Offer the recipe in the profession window, if it uses this item.
    local recipeID = GetSelectedRecipeID()
    local recipeName
    if recipeID and GetReagentQuantity(recipeID, name) then
        recipeName = GetRecipeName(recipeID) or "the open recipe"
    else
        recipeID = nil
    end
    local data = { name = name, itemID = itemID, recipeID = recipeID }

    trackDialog = trackDialog or CreateTrackDialog()
    local frame = trackDialog
    frame.data = data
    frame.mode = nil
    frame.itemText:SetText(name)

    -- The recipe choice only when there is one; the goal row moves up to fit.
    local rows = recipeID and 3 or 2
    frame.radios[3]:SetShown(recipeID ~= nil)
    frame.radios[3].label:SetText("For " .. (recipeName or ""))
    frame.goalLabel:ClearAllPoints()
    frame.goalLabel:SetPoint("TOPLEFT", 18, -58 - rows * 24)
    frame:SetHeight(rows * 24 + 128)

    -- Start on: the bar's current section, else the open recipe, else Items.
    local bar = trackedItems[string.lower(name)]
    local mode
    if bar and not bar.container then
        mode = bar.collect and "items" or "crafting"
    elseif recipeID then
        mode = "recipe"
    else
        mode = "items"
    end

    frame:Show()
    frame.goalBox:SetText(DefaultGoalText(data, mode))
    SetTrackMode(frame, mode)
    frame.goalBox:SetFocus()
    frame.goalBox:HighlightText()
end

function TrackFromLink(link)
    if type(link) ~= "string" then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    local name = link:match("%[(.-)%]")
    if not itemID or not name or name == "" then return end

    local options = GetLinkFillOptions(link, itemID)
    if options then
        if IsContainerTracked(itemID) then
            Print(name .. " is already tracked.")
        elseif CountWhere(itemID, false, false) == 0 then
            if CountWhere(itemID, true, false) > 0 then
                Print("Move " .. name .. " to your bags, then Alt-Shift-click it if it doesn't track automatically.")
            else
                Print("BarTab only tracks crates that are in your bags.")
            end
        else
            DismissedContainers()[itemID] = nil
            ImportContainer(itemID, name, options, true)
        end
        return
    end
    if TrackRecipeItem(name) then return end
    ShowTrackDialog(name, itemID)
end

lastLinkClick = { link = nil, time = 0 }
if hooksecurefunc and HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not (IsAltKeyDown() and IsShiftKeyDown()) or IsControlKeyDown() then return end
        -- Some windows pass the same click through twice.
        local now = GetTime()
        if lastLinkClick.link == link and now - lastLinkClick.time < 0.3 then return end
        lastLinkClick.link, lastLinkClick.time = link, now
        pcall(TrackFromLink, link)
        -- Shift also opens the bag's "how many" box; close it right after.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if StackSplitFrame and StackSplitFrame:IsShown() then
                    StackSplitFrame:Hide()
                end
            end)
        end
    end)
end

-- Sharing bar setups as text -----------------------------------------------
-- "BarTab1:" then one entry per bar, separated by ";":
--   name,start,goal,recipeID,profession,label,flags,stop (skill level or color),itemID
--   (flags: c = Items section; u / n = untrack / move to Inactive after crafting;
--    a = ask before a stop rule removes it; v = not bought at vendors;
--    d / k = count down as you craft, on / off)
-- Text fields escape % , ; | and line breaks as %XX. Fill-up bars
-- aren't shared; they come from your own bags.
SHARE_PREFIX = "BarTab1:"

function EscapeField(text)
    return (tostring(text or ""):gsub("[%%,;|\r\n]", function(c)
        return ("%%%02X"):format(c:byte())
    end))
end

function UnescapeField(text)
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function IsShareable(item)
    return item and not item.container and not item.altNeed and not item.virtual
end

function ExportKeys(keys)
    local items = {}
    for _, key in ipairs(keys) do
        local item = trackedItems[key]
        if IsShareable(item) then items[#items + 1] = item end
    end
    table.sort(items, function(a, b) return (a.order or 0) < (b.order or 0) end)
    local entries = {}
    for _, item in ipairs(items) do
        entries[#entries + 1] = table.concat({
            EscapeField(item.name), item.start or 0, item.goal,
            item.recipeID or "", EscapeField(item.profession), EscapeField(item.label),
            (item.collect and "c" or "") .. (item.afterCraft == "untrack" and "u"
                or item.afterCraft == "inactive" and "n" or "") .. (item.stopAsk and "a" or "")
                .. (item.noVendor and "v" or "")
                .. (item.countDown == true and "d" or item.countDown == false and "k" or ""),
            item.untilSkill or item.untilColor or "",
            ItemIDFor(item) or "",
        }, ",")
    end
    if #entries == 0 then return nil end
    return SHARE_PREFIX .. table.concat(entries, ";"), #entries
end

-- Adds the shared bars; ones you already have get the shared range.
function ImportText(text)
    -- Line breaks are never part of the string (they're escaped), so any
    -- in the paste came from wrapping; drop them.
    text = (text or ""):gsub("[\r\n]", "")
    text = Trim(text)
    local body = text:match("BarTab1:(.*)$")
    if not body then
        Print("That isn't a BarTab bar string (they start with " .. SHARE_PREFIX .. ").")
        return false
    end
    local added, updated, bad = 0, 0, 0
    for entry in body:gmatch("[^;]+") do
        local fields = {}
        for field in (entry .. ","):gmatch("([^,]*),") do fields[#fields + 1] = field end
        local name = Trim(UnescapeField(fields[1] or ""))
        local startCount, goal = tonumber(fields[2]), tonumber(fields[3])
        local recipeID = tonumber(fields[4] or "")
        if name == "" or not startCount or not goal or goal <= startCount or startCount < 0 then
            bad = bad + 1
        else
            local key = recipeID and RecipeKey(name, recipeID) or string.lower(name)
            local item = trackedItems[key]
            if item then
                item.start, item.goal = startCount, goal
                item.countFrom, item.countDone = nil, nil -- a new size starts the countdown over
                updated = updated + 1
            else
                local profession = UnescapeField(fields[5] or "")
                local label = UnescapeField(fields[6] or "")
                trackedItems[key] = {
                    name = name,
                    start = startCount,
                    goal = goal,
                    recipeID = recipeID,
                    profession = recipeID and (profession ~= "" and profession
                        or LookUpRecipeProfession(recipeID)) or nil,
                    label = recipeID and (label ~= "" and label or GetRecipeName(recipeID)) or nil,
                    collect = (not recipeID and (fields[7] or ""):find("c")) and true or nil,
                    afterCraft = recipeID and (((fields[7] or ""):find("u") and "untrack")
                        or ((fields[7] or ""):find("n") and "inactive")) or nil,
                    untilSkill = recipeID and tonumber(fields[8] or "") or nil,
                    untilColor = recipeID and COLOR_RANK[fields[8] or ""] and fields[8] or nil,
                    stopAsk = (recipeID and (fields[7] or ""):find("a")) and true or nil,
                    noVendor = (fields[7] or ""):find("v") and true or nil,
                    countDown = recipeID and (((fields[7] or ""):find("d") and true)
                        or ((fields[7] or ""):find("k") and false)) or nil,
                    itemID = tonumber(fields[9] or ""),
                    order = NextOrder(),
                }
                added = added + 1
            end
        end
    end
    UpdateBars()
    local message = ("Imported bars: %d added, %d updated"):format(added, updated)
    if bad > 0 then message = message .. (", %d skipped (damaged)"):format(bad) end
    Print(message .. ".")
    return added + updated > 0
end

function CreateShareWindow()
    local ok, frame = pcall(CreateFrame, "Frame", "BarTabShareFrame", UIParent,
        "BasicFrameTemplateWithInset")
    if not ok then
        frame = CreateFrame("Frame", "BarTabShareFrame", UIParent, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    frame:SetSize(460, 280)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "BarTabShareFrame")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -6)

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.hint:SetPoint("TOPLEFT", 16, -32)
    frame.hint:SetPoint("RIGHT", -16, 0)
    frame.hint:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -56)
    scroll:SetPoint("BOTTOMRIGHT", -36, 44)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    box:SetWidth(400)
    box:SetMaxLetters(0)
    box:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Export text stays as it is, so a stray key can't spoil the copy.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and frame.exportText then
            self:SetText(frame.exportText)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(box)
    frame.box = box

    -- Clicking the empty area below short text still focuses the box.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)

    frame.importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.importButton:SetSize(100, 22)
    frame.importButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 12)
    frame.importButton:SetText("Import")
    frame.importButton:SetScript("OnClick", function()
        if ImportText(box:GetText()) then frame:Hide() end
    end)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeButton:SetSize(100, 22)
    frame.closeButton:SetText(CLOSE or "Close")
    frame.closeButton:SetScript("OnClick", function() frame:Hide() end)

    frame:Hide()
    return frame
end

function ShowShareWindow(text, count, label)
    shareWindow = shareWindow or CreateShareWindow()
    local frame = shareWindow
    frame.closeButton:ClearAllPoints()
    if text then
        frame.exportText = text
        frame.title:SetText("Share BarTab bars")
        frame.hint:SetText(("%d bar(s) from %s. Press Ctrl-C to copy, then paste it anywhere.")
            :format(count, label))
        frame.importButton:Hide()
        frame.closeButton:SetPoint("BOTTOM", 0, 12)
    else
        frame.exportText = nil
        frame.title:SetText("Import BarTab bars")
        frame.hint:SetText("Paste a bar string with Ctrl-V, then click Import.")
        frame.importButton:Show()
        frame.closeButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 12)
    end
    frame:Show()
    frame.box:SetText(text or "")
    frame.box:SetFocus()
    frame.box:HighlightText()
end

function ShareKeys(keys, label)
    local text, count = ExportKeys(keys)
    if not text then
        Print("Nothing to share there (fill-up bars aren't shared).")
        return
    end
    ShowShareWindow(text, count, label)
end

function ShareAll()
    local keys = {}
    for key in pairs(trackedItems) do keys[#keys + 1] = key end
    ShareKeys(keys, "all your bars")
end
