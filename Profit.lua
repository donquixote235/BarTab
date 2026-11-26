-- BarTab: the profit window (/bartab profit). Which of the open profession's
-- recipes earn the most when you sell what they make, to a vendor or at the
-- auction house, with your
-- choice of how to count materials you have and ones you'd have to get.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

PROFIT_MINE = {
    { key = "free", name = "free" },
    { key = "auction", name = "at auction price" },
    { key = "vendor", name = "at vendor price" },
}
PROFIT_MISSING = {
    { key = "make", name = "buy or make, cheaper" },
    { key = "buy", name = "buy at auction" },
    { key = "skip", name = "leave recipe out" },
}
PROFIT_SORTS = {
    { key = "craft", name = "profit per craft" },
    { key = "hour", name = "profit per hour" },
    { key = "total", name = "total you can make" },
    { key = "point", name = "cheapest skill-up" },
    { key = "pointtime", name = "fastest skill-up" },
}
-- Leveling: skill points a craft gives, on average, by the recipe's color.
-- Orange always gives one (some give more); yellow about 3 crafts in 4,
-- green about 1 in 4 (the chance falls as the recipe nears gray); gray none.
SKILL_CHANCE = { orange = 1, yellow = 0.75, green = 0.25, gray = 0 }
SKILL_CHANCE_TEXT = {
    orange = "every craft gives a point",
    yellow = "about 3 crafts in 4 give a point",
    green = "about 1 craft in 4 gives a point",
    gray = "no more points",
}

function IsLevelingSort(sort)
    return sort == "point" or sort == "pointtime"
end
PROFIT_SELL = {
    { key = "best", name = "whichever pays more" },
    { key = "vendor", name = "a vendor" },
    { key = "auction", name = "the auction house" },
}
PROFIT_ROWS = 14
AUCTION_CUT = 0.05 -- the auction house keeps 5% of the sale

-- The window's choices, kept between sessions (settings.profitWindow).
function ProfitOptions()
    settings.profitWindow = settings.profitWindow or {}
    local options = settings.profitWindow
    options.mine = options.mine or "free"
    options.missing = options.missing or "make"
    options.sort = options.sort or "craft"
    options.sell = options.sell or "best"
    if options.gray == nil then options.gray = true end
    if options.gather == nil then options.gather = true end
    -- Materials you've asked to always price, even when you have them
    -- (Elemental Earth isn't free just because some is in your bags).
    -- Per material, your choice: "own" (count it as yours) or "buy" (price
    -- it like something you'd buy); none: decided by the settings. Replaces
    -- the earlier "Always price" ticks (options.priced).
    options.itemMode = options.itemMode or {}
    if options.priced then
        for itemID in pairs(options.priced) do options.itemMode[itemID] = options.itemMode[itemID] or "buy" end
        options.priced = nil
    end
    return options
end

function ChoiceName(list, key)
    for _, choice in ipairs(list) do
        if choice.key == key then return choice.name end
    end
    return list[1].name
end

function NextChoice(list, key)
    for index, choice in ipairs(list) do
        if choice.key == key then return list[index % #list + 1].key end
    end
    return list[1].key
end

-- Plain-text money with a sign: "1g 2s", "-35s".
function ProfitMoney(copper)
    copper = math.floor(copper + 0.5)
    if copper < 0 then return "-" .. MoneyText(-copper) end
    return MoneyText(copper)
end

-- Your gathering skills, lower case: { skinning = true, ... }.
GATHER_SUBCLASSES = { mining = 7, herbalism = 9 } -- trade goods: metal & stone, herb

-- What Skinning gives. The leather category also holds things that only drop
-- (murloc and whelp scales, Deviate Scale), so skinning goes by this list,
-- plus anything in that category named "... Leather" or "... Hide".
SKINNED_ITEMS = {
    [2934] = true, [2318] = true, [783] = true, [2319] = true, [4232] = true, -- scraps, light, medium
    [4234] = true, [4235] = true, [4304] = true, [8169] = true, -- heavy, thick
    [8170] = true, [8171] = true, [8167] = true, [8154] = true, [8165] = true, -- rugged, turtle, scorpid, worn dragonscale
    [15412] = true, [15414] = true, [15415] = true, [15416] = true, -- green, red, blue, black dragonscale
    [15417] = true, [15419] = true, [15422] = true, [15423] = true, [17012] = true, -- devilsaur, warbear, frostsaber, chimera, core
}
function GatherSkills()
    local skills = {}
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            local ok, name = pcall(GetProfessionInfo, index)
            if ok and name then skills[string.lower(name)] = true end
        end
    end
    return skills
end

-- Whether you could gather the item yourself: leather and hides with
-- Skinning, ore and stone with Mining, herbs with Herbalism. Not things
-- made with a bought ingredient (Cured Heavy Hide needs salt), which are
-- priced as made; Heavy Leather, skinned or made from Medium Leather,
-- still counts.
function CanGather(itemID, itemName, skills)
    if not (itemID and C_Item and C_Item.GetItemInfoInstant) then return false end
    local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
    if not ok or classID ~= 7 then return false end
    local mine = settings.producers and settings.producers[CharacterKey()]
    local producer = (mine and mine[itemID]) or FindProducer(itemName)
    if producer and producer.recipeID then
        for _, reagent in ipairs(GetRecipeReagents(producer.recipeID) or {}) do
            if VendorBuyPrice(reagent.itemID) then return false end
        end
    end
    if skills.skinning and (SKINNED_ITEMS[itemID] or (subclassID == 6 and itemName
        and (itemName:find(" Leather$") or itemName:find(" Hide$")))) then
        return "Skinning"
    end
    for skill, subclass in pairs(GATHER_SUBCLASSES) do
        if skills[skill] and subclassID == subclass then
            return skill == "mining" and "Mining" or "Herbalism"
        end
    end
    return false
end

-- One recipe under the window's options: a row, "loading", or nil plus why
-- it was left out ("unpriced", "skipped" or "noauction").
function ProfitRow(recipeID, options, state)
    local outputID, made = GetRecipeOutput(recipeID)
    if not outputID then return nil end
    local sell = VendorSellPrice(outputID)
    if sell == nil then return "loading" end
    made = made or 1
    -- What it fetches: from a vendor, and at auction after the house's cut.
    local vendorIncome = sell > 0 and sell * made or nil
    local auctionEach = AuctionPrice(outputID)
    local auctionIncome = auctionEach and auctionEach * made * (1 - AUCTION_CUT) or nil
    local income, soldAt
    if options.sell == "vendor" then
        income, soldAt = vendorIncome, "vendor"
    elseif options.sell == "auction" then
        income, soldAt = auctionIncome, "auction"
        if not income and vendorIncome then return nil, "noauction" end
    elseif auctionIncome and (not vendorIncome or auctionIncome > vendorIncome) then
        income, soldAt = auctionIncome, "auction"
    else
        income, soldAt = vendorIncome, "vendor"
    end
    if not income then return nil end
    local cost, lines = 0, {}
    local leftOut
    state.visiting[outputID] = true
    for _, reagent in ipairs(GetRecipeReagents(recipeID) or {}) do
        local each, how
        local vendor = VendorBuyPrice(reagent.itemID)
        local mode = options.itemMode[reagent.itemID]
        if vendor then
            each, how = vendor, "vendor"
        elseif mode == "own" or (mode == nil and reagent.have >= reagent.need) then
            -- Your own: enough for a craft, or you chose to count it as yours.
            if options.mine == "auction" then
                each = AuctionPrice(reagent.itemID)
                how = "yours, at auction price"
                if not each then each, how = 0, "yours (no auction price)" end
            elseif options.mine == "vendor" then
                each, how = VendorSellPrice(reagent.itemID) or 0, "yours, at vendor price"
            else
                each, how = 0, "yours"
            end
        elseif mode == nil and options.gather
            and CanGather(reagent.itemID, reagent.name, state.skills) then
            each, how = 0, "from your " .. CanGather(reagent.itemID, reagent.name, state.skills)
        elseif mode == nil and options.missing == "skip" then
            leftOut = "skipped"
            break
        elseif options.missing ~= "buy" then
            local ownMade, from
            each, ownMade, from = BestCost(reagent.itemID, reagent.name, state, 1)
            how = ownMade and ("made from " .. from) or "bought at auction"
        else
            each, how = AuctionPrice(reagent.itemID), "bought at auction"
        end
        if not each then
            leftOut = "unpriced"
            break
        end
        cost = cost + each * reagent.need
        lines[#lines + 1] = { name = reagent.name, itemID = reagent.itemID, need = reagent.need,
            cost = each * reagent.need, how = how }
    end
    state.visiting[outputID] = nil
    if leftOut then return nil, leftOut end
    local profit = income - cost
    local seconds = CraftSeconds(recipeID)
    -- Leveling: points a craft gives on average, and what a point costs
    -- (after selling what you make; negative: it earns) and takes.
    local color = GetRecipeColor(recipeID)
    local points = color and SKILL_CHANCE[color] or nil
    if points and color == "orange" and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        local ups = ok and type(info) == "table" and tonumber(info.numSkillUps)
        if ups and ups > 1 then points = ups end
    end
    local canMake = GetCraftableCount(recipeID) or 0
    return {
        recipeID = recipeID, outputID = outputID,
        name = GetRecipeName(recipeID) or GetItemNameByID(outputID) or ("recipe " .. recipeID),
        made = made, income = income, cost = cost, profit = profit, lines = lines,
        vendorIncome = vendorIncome, auctionIncome = auctionIncome, soldAt = soldAt,
        auctionAge = auctionIncome and AuctionAge(outputID) or nil,
        perHour = (seconds and seconds > 0) and (profit * 3600 / seconds) or nil,
        canMake = canMake, total = profit * canMake, seconds = seconds,
        color = color, points = points,
        perPoint = (points and points > 0) and (-profit / points) or nil,
        secondsPerPoint = (points and points > 0 and seconds) and (seconds / points) or nil,
    }
end

function RunProfitSearch(keepOffset)
    local frame = profitWindow
    if not frame then return end
    local profession = LoadedProfession()
    if not profession or not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then
        frame.results, frame.offset = {}, 0
        frame.status:SetText("Open a profession window first: BarTab checks the recipes of the profession that's open.")
        RefreshProfitRows()
        return
    end
    local options = ProfitOptions()
    local state = { memo = {}, visiting = {}, skills = GatherSkills() }
    if options.gather then
        state.gathered = function(itemID, itemName)
            local mode = options.itemMode[itemID]
            if mode == "buy" then return false end
            if mode == "own" then return options.mine == "free" end
            return CanGather(itemID, itemName, state.skills)
        end
    end
    local results, loading, unpriced, skipped, noAuction = {}, 0, 0, 0, 0
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(info) == "table" and info.learned
            and (options.gray or GetRecipeColor(recipeID) ~= "gray") then
            local row, why = ProfitRow(recipeID, options, state)
            if row == "loading" then
                loading = loading + 1
            elseif row then
                local wanted = not options.canCraft or row.canMake >= 1
                -- Leveling: only recipes that can still give a point.
                if IsLevelingSort(options.sort) and not (row.points and row.points > 0) then wanted = false end
                if wanted then results[#results + 1] = row end
            elseif why == "unpriced" then
                unpriced = unpriced + 1
            elseif why == "skipped" then
                skipped = skipped + 1
            elseif why == "noauction" then
                noAuction = noAuction + 1
            end
        end
    end
    local function Key(row)
        if options.sort == "hour" then return row.perHour or -math.huge end
        if options.sort == "total" then return row.total end
        if options.sort == "point" then return -(row.perPoint or math.huge) end
        if options.sort == "pointtime" then return -(row.secondsPerPoint or math.huge) end
        return row.profit
    end
    table.sort(results, function(a, b)
        local ka, kb = Key(a), Key(b)
        if ka ~= kb then return ka > kb end
        return a.profit > b.profit
    end)
    frame.sortUsed = options.sort
    frame.results, frame.offset = results, keepOffset and frame.offset or 0
    -- Keep the recipe you last picked in view, wherever a change moved it.
    if keepOffset and frame.selected then
        for index, row in ipairs(results) do
            if row.recipeID == frame.selected then
                local offset = frame.offset or 0
                if index <= offset or index > offset + PROFIT_ROWS then
                    frame.offset = math.max(0, index - math.floor(PROFIT_ROWS / 2))
                end
                break
            end
        end
    end
    UpdateChoicesButton()
    frame.title:SetText("BarTab: profit, " .. profession)
    local notes = { #results .. (#results == 1 and " recipe" or " recipes") }
    if unpriced > 0 then notes[#notes + 1] = unpriced .. " left out (no auction price for an ingredient)" end
    if skipped > 0 then notes[#notes + 1] = skipped .. " left out (missing materials)" end
    if noAuction > 0 then notes[#notes + 1] = noAuction .. " with no auction price yet" end
    if loading > 0 then notes[#notes + 1] = loading .. " still loading: search again in a moment" end
    frame.status:SetText(table.concat(notes, "  ·  "))
    RefreshProfitRows()
end

function RefreshProfitRows()
    local frame = profitWindow
    if not frame then return end
    local results = frame.results or {}
    local maxOffset = math.max(0, #results - PROFIT_ROWS)
    frame.offset = math.max(0, math.min(frame.offset or 0, maxOffset))
    for index, row in ipairs(frame.rows) do
        local result = results[frame.offset + index]
        row.result = result
        if result then
            -- Named in the recipe's color (orange, yellow, green, gray).
            local name = result.name .. (result.made > 1 and (" (x" .. result.made .. ")") or "")
            if result.color and COLOR_CODES[result.color] then
                name = "|c" .. COLOR_CODES[result.color] .. name .. "|r"
            end
            row.cells.name:SetText(name)
            row.cells.vendor:SetText(result.vendorIncome and ProfitMoney(result.vendorIncome) or "—")
            row.cells.auction:SetText(result.auctionIncome and ProfitMoney(result.auctionIncome) or "—")
            -- The price the profit uses is bright; the other is dimmed.
            local vendorUsed = result.soldAt == "vendor"
            row.cells.vendor:SetTextColor(vendorUsed and 1 or 0.5, vendorUsed and 1 or 0.5, vendorUsed and 1 or 0.5)
            row.cells.auction:SetTextColor(vendorUsed and 0.5 or 1, vendorUsed and 0.5 or 1, vendorUsed and 0.5 or 1)
            row.cells.cost:SetText(ProfitMoney(result.cost))
            row.cells.profit:SetText(ProfitMoney(result.profit))
            if result.profit >= 0 then
                row.cells.profit:SetTextColor(0.3, 1, 0.3)
            else
                row.cells.profit:SetTextColor(1, 0.35, 0.35)
            end
            if frame.sortUsed == "point" then
                -- What a skill point costs; green "+" when it earns.
                if not result.perPoint then
                    row.cells.hour:SetText("")
                elseif result.perPoint > 0 then
                    row.cells.hour:SetText(ProfitMoney(result.perPoint))
                else
                    row.cells.hour:SetText("|cff4dff4d+" .. ProfitMoney(-result.perPoint) .. "|r")
                end
            elseif frame.sortUsed == "pointtime" then
                row.cells.hour:SetText(result.secondsPerPoint
                    and (FormatDuration(result.secondsPerPoint):gsub("^about ", "")) or "")
            else
                row.cells.hour:SetText(result.perHour and ProfitMoney(result.perHour) or "")
            end
            row.cells.make:SetText(tostring(result.canMake))
            row.picked:SetShown(result.recipeID == frame.selected)
            row:Show()
        else
            row:Hide()
        end
    end
    if frame.hourHeader then
        frame.hourHeader:SetText(IsLevelingSort(frame.sortUsed) and "A point" or "An hour")
    end
    if #results > PROFIT_ROWS then
        frame.pageText:SetText(("%d-%d of %d"):format(frame.offset + 1,
            math.min(frame.offset + PROFIT_ROWS, #results), #results))
    else
        frame.pageText:SetText("")
    end
end

function ScrollProfitRows(delta)
    local frame = profitWindow
    if not frame then return end
    frame.offset = (frame.offset or 0) - delta * 3
    RefreshProfitRows()
end

function ShowProfitRowTooltip(row)
    local result = row.result
    if not result then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(result.name)
    GameTooltip:AddDoubleLine("Sells to a vendor for",
        result.vendorIncome and ProfitMoney(result.vendorIncome) or "can't be sold", 0.8, 0.8, 0.8, 1, 1, 1)
    if result.auctionIncome then
        GameTooltip:AddDoubleLine("At auction, after the 5% cut", ProfitMoney(result.auctionIncome),
            0.8, 0.8, 0.8, 1, 1, 1)
        local age = result.auctionAge
        if age then
            GameTooltip:AddLine(age == 0 and "Auction price seen today"
                or ("Auction price last seen %d day%s ago"):format(age, age == 1 and "" or "s"), 0.6, 0.6, 0.6)
        end
    else
        GameTooltip:AddDoubleLine("At auction", "no price yet", 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
    end
    for _, line in ipairs(result.lines) do
        GameTooltip:AddDoubleLine(("%d %s (%s)"):format(line.need, line.name, line.how),
            line.cost > 0 and ("-" .. ProfitMoney(line.cost)) or "free", 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local good = result.profit >= 0
    GameTooltip:AddDoubleLine(result.soldAt == "auction" and "Profit a craft, at auction"
        or "Profit a craft, at a vendor", ProfitMoney(result.profit), 1, 0.82, 0,
        good and 0.3 or 1, good and 1 or 0.35, good and 0.3 or 0.35)
    if result.seconds then
        local takes = FormatDuration(result.seconds):gsub("^about ", "")
        GameTooltip:AddDoubleLine("A craft takes", takes, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if result.color then
        local chance = SKILL_CHANCE_TEXT[result.color] or ""
        if result.color == "orange" and result.points and result.points > 1 then
            chance = ("every craft gives %d points"):format(result.points)
        end
        GameTooltip:AddDoubleLine("Skill-ups (" .. result.color .. ")", chance, 0.8, 0.8, 0.8, 1, 1, 1)
        if result.perPoint then
            GameTooltip:AddDoubleLine("A skill point costs",
                result.perPoint > 0 and ProfitMoney(result.perPoint) or ("nothing (earns " .. ProfitMoney(-result.perPoint) .. ")"),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
        if result.secondsPerPoint then
            GameTooltip:AddDoubleLine("A skill point takes",
                (FormatDuration(result.secondsPerPoint):gsub("^about ", "")), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    GameTooltip:AddLine("Click: show it in the profession window", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Shift-click: search for it at the auction house", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: track it, or choose how to count its materials", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

-- A material's submenu: Automatic, Use my own, Buy it. Picking one
-- recalculates the list straight away.
function MaterialChoiceEntry(itemID, name)
    local options = ProfitOptions()
    local function Choose(mode)
        return function()
            options.itemMode[itemID] = mode
            Safe("profit", RunProfitSearch)(true)
        end
    end
    local current = options.itemMode[itemID]
    local function Is(mode) return function() return options.itemMode[itemID] == mode end end
    return { name, choices = {
        { "Automatic (from your settings)", Choose(nil), selected = current == nil, isSelected = Is(nil) },
        { "Use my own", Choose("own"), selected = current == "own", isSelected = Is("own") },
        { "Buy it", Choose("buy"), selected = current == "buy", isSelected = Is("buy") },
    } }
end

function CountMaterialChoices()
    local count = 0
    for _ in pairs(ProfitOptions().itemMode) do count = count + 1 end
    return count
end

function UpdateChoicesButton()
    local frame = profitWindow
    if frame and frame.choicesButton then
        frame.choicesButton:SetText(("Material choices (%d)"):format(CountMaterialChoices()))
    end
end

-- Every material you've set, to switch or reset.
function ShowMaterialChoices(owner)
    local options = ProfitOptions()
    local list = {}
    for itemID, mode in pairs(options.itemMode) do
        local name = GetItemNameByID(itemID)
        if not name and C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
        list[#list + 1] = { itemID = itemID, name = name or ("item " .. itemID), mode = mode }
    end
    if #list == 0 then
        Print("No material choices yet. Right-click a recipe in the list to count one of its materials as your own or as bought.")
        return
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    local entries = {}
    for _, material in ipairs(list) do
        local entry = MaterialChoiceEntry(material.itemID, material.name)
        entry[1] = material.name .. (material.mode == "own" and " (use my own)" or " (buy it)")
        entries[#entries + 1] = entry
    end
    local reset = { { "Reset all to automatic", function()
        for itemID in pairs(options.itemMode) do options.itemMode[itemID] = nil end
        Safe("profit", RunProfitSearch)(true)
        Print("All materials are counted automatically again.")
    end } }
    ShowMenu(owner, "Material choices", GroupedEntries({ { entries = entries }, { entries = reset } }))
end

function ProfitRowClicked(row, button)
    local result = row.result
    if not result then return end
    profitWindow.selected = result.recipeID
    RefreshProfitRows()
    if button == "RightButton" then
        local entries = {
            { "Track with settings...", function() TrackWithOptions(result.recipeID) end },
            { "Make until I have...", function() AskMakeGoal(result.recipeID) end },
            { "Make until I reach a skill level...", function() AskSkillGoal(result.recipeID) end },
        }
        -- Materials that aren't vendor items: how to count each one, here
        -- and in every other recipe; the list updates straight away.
        local materials = {}
        for _, reagent in ipairs(GetRecipeReagents(result.recipeID) or {}) do
            local itemID = reagent.itemID
            if itemID and not VendorBuyPrice(itemID) then
                materials[#materials + 1] = MaterialChoiceEntry(itemID, reagent.name)
            end
        end
        ShowMenu(row, result.name, GroupedEntries({
            { entries = entries },
            { heading = "Count materials as", entries = materials },
        }))
    elseif IsShiftKeyDown() then
        -- Look the item up at the auction house, to check the going price.
        local name = (result.outputID and GetItemNameByID(result.outputID))
            or (result.name:gsub(" %(x%d+%)$", ""))
        if AuctionHouseOpen() then
            SearchAuctionHouse(name)
        else
            Print("Open the auction house first, then Shift-click to search for " .. name .. ".")
        end
    elseif ProfessionsOpen() then
        SelectRecipeInWindow(result.recipeID)
    elseif C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
        pcall(C_TradeSkillUI.OpenRecipe, result.recipeID)
        C_Timer.After(0.3, function() SelectRecipeInWindow(result.recipeID) end)
    end
end

function CreateProfitWindow()
    local ok, frame = pcall(CreateFrame, "Frame", "BarTabProfitFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        frame = CreateFrame("Frame", "BarTabProfitFrame", UIParent, "BackdropTemplate")
        if frame.SetBackdrop then
            frame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    frame:SetSize(680, 526)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "BarTabProfitFrame") -- Escape closes it

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -6)
    frame.title:SetText("BarTab: profit")

    local options = ProfitOptions()
    local function Cycle(x, y, width, label, list, field)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetPoint("TOPLEFT", x, y)
        local function Label() button:SetText(label .. ": " .. ChoiceName(list, options[field])) end
        button:SetScript("OnClick", function()
            options[field] = NextChoice(list, options[field])
            Label()
        end)
        Label()
        button.Refresh = Label
        return button
    end
    local function Check(x, y, label, field)
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", x, y)
        if type(check.Text) == "table" then check.Text:SetText("") end
        local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 4, 0)
        text:SetText(label)
        check:SetChecked(options[field] and true or false)
        check:SetScript("OnClick", function(self) options[field] = self:GetChecked() and true or false end)
        return check
    end
    frame.mineButton = Cycle(14, -32, 320, "Your materials", PROFIT_MINE, "mine")
    frame.missingButton = Cycle(14, -58, 320, "Missing", PROFIT_MISSING, "missing")
    frame.sortButton = Cycle(14, -84, 320, "Sort by", PROFIT_SORTS, "sort")
    frame.sellButton = Cycle(346, -32, 320, "Sell to", PROFIT_SELL, "sell")
    frame.canCheck = Check(346, -57, "Only recipes I can craft now", "canCraft")
    frame.grayCheck = Check(346, -80, "Include gray recipes", "gray")

    local search = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    search:SetSize(120, 24)
    search:SetPoint("TOPLEFT", 14, -112)
    search:SetText("Search")
    search:SetScript("OnClick", function() Safe("profit", RunProfitSearch)() end)
    frame.searchButton = search

    local choices = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    choices:SetSize(160, 24)
    choices:SetPoint("LEFT", search, "RIGHT", 8, 0)
    choices:SetScript("OnClick", function(self) Safe("profit", ShowMaterialChoices)(self) end)
    frame.choicesButton = choices
    frame.gatherCheck = Check(346, -103, "Free: items from my gathering skills", "gather")

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.status:SetPoint("TOPLEFT", 16, -142)
    frame.status:SetPoint("RIGHT", -16, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetText("Choose how to count materials, then click Search.")

    -- Columns: name, then money columns right-aligned.
    local COLUMNS = {
        { key = "name", label = "Recipe", x = 18, width = 196, justify = "LEFT" },
        { key = "vendor", label = "Vendor for", x = 216, width = 66, justify = "RIGHT" },
        { key = "auction", label = "Auction for", x = 286, width = 66, justify = "RIGHT" },
        { key = "cost", label = "Cost", x = 356, width = 66, justify = "RIGHT" },
        { key = "profit", label = "Profit", x = 426, width = 72, justify = "RIGHT" },
        { key = "hour", label = "An hour", x = 502, width = 80, justify = "RIGHT" },
        { key = "make", label = "Can make", x = 590, width = 72, justify = "RIGHT" },
    }
    for _, column in ipairs(COLUMNS) do
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", column.x, -162)
        header:SetWidth(column.width)
        header:SetJustifyH(column.justify)
        header:SetText(column.label)
        if column.key == "hour" then frame.hourHeader = header end
    end

    frame.rows = {}
    for index = 1, PROFIT_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(652, 22)
        row:SetPoint("TOPLEFT", 14, -176 - (index - 1) * 22)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        -- The recipe you last clicked, so you can find it after the list
        -- reorders.
        row.picked = row:CreateTexture(nil, "BORDER")
        row.picked:SetAllPoints()
        row.picked:SetColorTexture(0.3, 1, 0.3, 0.18)
        row.picked:Hide()
        if index % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            stripe:SetColorTexture(1, 1, 1, 0.03)
        end
        row.cells = {}
        for _, column in ipairs(COLUMNS) do
            local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetPoint("LEFT", row, "LEFT", column.x - 14, 0)
            cell:SetWidth(column.width)
            cell:SetJustifyH(column.justify)
            if cell.SetWordWrap then cell:SetWordWrap(false) end
            row.cells[column.key] = cell
        end
        row:SetScript("OnEnter", ShowProfitRowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", ProfitRowClicked)
        row:Hide()
        frame.rows[index] = row
    end

    frame.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.pageText:SetPoint("BOTTOMRIGHT", -18, 14)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 18, 14)
    hint:SetText("Scroll for more. Vendor items are priced once seen at a vendor; auction prices are from your last scan.")
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) ScrollProfitRows(delta) end)

    frame.results, frame.offset = {}, 0
    frame:Hide()
    return frame
end

-- Your professions that have recipes: { { name=, skillLine= }, ... }.
NO_RECIPES = { herbalism = true, skinning = true, fishing = true }
function CraftingProfessions()
    local list = {}
    if GetProfessions and GetProfessionInfo then
        local indexes = { GetProfessions() }
        for i = 1, 6 do
            if indexes[i] then
                local ok, name, _, _, _, _, _, skillLine = pcall(GetProfessionInfo, indexes[i])
                if ok and name and skillLine and not NO_RECIPES[string.lower(name)] then
                    list[#list + 1] = { name = name, skillLine = skillLine }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Opens a profession's window, then runs then() once it has loaded.
function OpenProfessionThen(profession, andThen)
    if InCombatLockdown and InCombatLockdown() then
        Print("Can't open " .. profession.name .. " in combat.")
        return
    end
    if not (C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill)
        or not pcall(C_TradeSkillUI.OpenTradeSkill, profession.skillLine) then
        Print("Couldn't open " .. profession.name .. ". Open it yourself, then try again.")
        return
    end
    local tries = 0
    local function Wait()
        tries = tries + 1
        local loaded = LoadedProfession()
        if loaded and string.lower(loaded) == string.lower(profession.name) then
            andThen()
        elseif tries < 20 then
            C_Timer.After(0.2, Wait)
        end
    end
    C_Timer.After(0.2, Wait)
end

-- "What to craft next": the profit window sorted by what a skill point
-- costs, searched straight away. With no profession open, opens yours
-- (asking which, if you have several; /bartab next <profession> picks).
function ShowCraftNext(which)
    local function Run()
        ShowProfitWindow()
        local options = ProfitOptions()
        if not IsLevelingSort(options.sort) then options.sort = "point" end
        if profitWindow.sortButton.Refresh then profitWindow.sortButton.Refresh() end
        RunProfitSearch()
    end
    local loaded = LoadedProfession()
    which = which and which ~= "" and string.lower(which) or nil
    if loaded and (not which or string.lower(loaded):find(which, 1, true)) then
        Run()
        return
    end
    local professions, matches = CraftingProfessions(), {}
    for _, profession in ipairs(professions) do
        if not which or string.lower(profession.name):find(which, 1, true) then
            matches[#matches + 1] = profession
        end
    end
    if #matches == 0 then
        if which then
            Print("You don't have a profession called " .. which .. " with recipes.")
        else
            Print("Open a profession window first: BarTab checks the recipes of the profession that's open.")
        end
        return
    end
    if #matches == 1 then
        OpenProfessionThen(matches[1], Run)
        return
    end
    local entries = {}
    for _, profession in ipairs(matches) do
        entries[#entries + 1] = { profession.name, function() OpenProfessionThen(profession, Run) end }
    end
    ShowMenu(UIParent, "What to craft next: which profession?", entries)
end

function ShowProfitWindow()
    if not profitWindow then profitWindow = CreateProfitWindow() end
    UpdateChoicesButton()
    profitWindow:Show()
    profitWindow:Raise()
end
