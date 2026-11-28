-- BarTab: settings window and minimap button.
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

do
-- Settings window (/bartab config) -------------------------------------------------

configRefreshers = {}

function RefreshConfig()
    for _, refresh in ipairs(configRefreshers) do refresh() end
end

function AddTooltip(widget, title, text)
    if not text then return end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A gray explanatory line (wraps), returns the next y.
function AddNote(parent, y, text)
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 24, y)
    note:SetWidth(350)
    note:SetJustifyH("LEFT")
    note:SetTextColor(0.7, 0.7, 0.7)
    note:SetText(text)
    local height = note:GetStringHeight()
    if not height or height < 12 then height = 24 end
    return y - height - 6
end

-- Marks settings each character keeps for itself.
CHARACTER_TAG_TEXT = "|cff66ccff(this character)|r"
CHARACTER_TAG = "  " .. CHARACTER_TAG_TEXT

-- A tab's one-line summary at the top, in soft gold; returns the next y.
function AddIntro(parent, y, text)
    local intro = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 18, y - 4)
    intro:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
    intro:SetJustifyH("LEFT")
    intro:SetTextColor(1, 0.9, 0.6)
    intro:SetText(text)
    local height = intro:GetStringHeight()
    if not height or height < 12 then height = 14 end
    return y - height - 10
end

-- The "(this character)" tag beside a button.
function AddCharacterTag(parent, widget)
    local tag = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tag:SetPoint("LEFT", widget, "RIGHT", 8, 0)
    tag:SetText(CHARACTER_TAG_TEXT)
    return tag
end

-- A section heading, with a faint line running from it to the right edge.
function AddHeading(parent, y, text)
    local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 16, y)
    heading:SetText(text)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.2)
    rule:SetHeight(1)
    rule:SetPoint("LEFT", heading, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    return y - 22
end

function AddCheck(parent, y, label, tooltip, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 20, y)
    if type(check.Text) == "table" then check.Text:SetText("") end
    local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        RefreshConfig()
    end)
    AddTooltip(check, label, tooltip)
    table.insert(configRefreshers, function() check:SetChecked(get() and true or false) end)
    return y - 26
end

function AddStepper(parent, y, label, tooltip, minValue, maxValue, get, set, step)
    step = step or 1
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 24, y - 4)
    text:SetText(label)

    local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("TOPLEFT", 190, y)
    minus:SetText("-")
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    value:SetWidth(28)
    local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plus:SetSize(24, 22)
    plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
    plus:SetText("+")

    minus:SetScript("OnClick", function()
        set(math.max(minValue, get() - step)); RefreshConfig()
    end)
    plus:SetScript("OnClick", function()
        set(math.min(maxValue, get() + step)); RefreshConfig()
    end)
    AddTooltip(minus, label, tooltip)
    AddTooltip(plus, label, tooltip)
    table.insert(configRefreshers, function() value:SetText(tostring(get())) end)
    return y - 28
end

function AddButton(parent, x, y, width, label, tooltip, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    AddTooltip(button, label, tooltip)
    return button
end

function SetSectionShown(section, shown)
    settings.hiddenSections = settings.hiddenSections or {}
    settings.hiddenSections[section] = (not shown) or nil
    UpdateBars()
end

function BuildConfigFrame()
    local ok, frame = pcall(CreateFrame, "Frame", "BarTabConfigFrame", UIParent,
        "BasicFrameTemplateWithInset")
    if not ok or not frame then
        frame = CreateFrame("Frame", "BarTabConfigFrame", UIParent, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    frame:SetSize(620, 580)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    tinsert(UISpecialFrames, "BarTabConfigFrame") -- Escape closes it

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -6)
    title:SetText("BarTab Settings")

    -- The user's guide, from the title bar.
    local guideButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    guideButton:SetSize(110, 18)
    guideButton:SetPoint("TOPLEFT", 8, -3)
    guideButton:SetText("User's guide")
    guideButton:SetFrameLevel(frame:GetFrameLevel() + 5)
    guideButton:SetScript("OnClick", function() ShowGuide() end)
    AddTooltip(guideButton, "User's guide", "Every BarTab feature explained, section by section (/bartab guide).")

    -- Tabs along the top; each shows one page of settings.
    local TABS = {
        { key = "general", name = "General" },
        { key = "alerts", name = "Alerts" },
        { key = "crafting", name = "Crafting" },
        { key = "shopping", name = "Shopping" },
        { key = "characters", name = "Characters" },
        { key = "recipes", name = "Recipes" },
        { key = "display", name = "Display" },
    }
    local pages, tabButtons = {}, {}
    local function ShowTab(key)
        if key == "quests" or key == "items" then key = "general" end -- tabs that moved
        if not pages[key] then key = "general" end
        for pageKey, tabPage in pairs(pages) do tabPage:SetShown(pageKey == key) end
        for _, button in ipairs(tabButtons) do
            if button.key == key then button:LockHighlight() else button:UnlockHighlight() end
        end
        settings.configTab = key
    end
    for index, tab in ipairs(TABS) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(80, 22)
        button:SetPoint("TOPLEFT", 16 + (index - 1) * 84, -30)
        button:SetText(tab.name)
        button.key = tab.key
        button:SetScript("OnClick", function() ShowTab(tab.key) end)
        tabButtons[index] = button
        local tabPage = CreateFrame("Frame", nil, frame)
        tabPage:SetPoint("TOPLEFT", 0, -56)
        tabPage:SetSize(620, 520)
        tabPage:Hide()
        pages[tab.key] = tabPage
    end
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 0.82, 0, 0.35)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 16, -56)
    divider:SetPoint("TOPRIGHT", -16, -56)

    local page, y

    -- General ------------------------------------------------------------
    page, y = pages.general, -4
    y = AddIntro(page, y, "Which sections show, fill-up items, and a few odds and ends.")
    y = AddHeading(page, y - 6, "Sections")
    y = AddNote(page, y, "A section only appears in the objective tracker when it has "
        .. "something to show. For example, BarTab: Items stays hidden until a fill-up "
        .. "item is in your bags or you collect something there.")
    y = AddCheck(page, y, "Show BarTab: Crafting", "Material and recipe bars.",
        function() return not settings.hiddenSections[CRAFT_SECTION] end,
        function(v) SetSectionShown(CRAFT_SECTION, v) end)
    y = AddCheck(page, y, "Show BarTab: Items", "Fill-up items such as Waylaid Crates.",
        function() return not settings.hiddenSections[ITEM_SECTION] end,
        function(v) SetSectionShown(ITEM_SECTION, v) end)


    y = AddHeading(page, y - 6, "Fill-up items")
    y = AddCheck(page, y, "Track fill-up items automatically",
        "Adds bars when an item like a Waylaid Crate reaches your bags. (/bartab autoitems)",
        function() return settings.autoItems end,
        function(v) settings.autoItems = v end)
    y = AddCheck(page, y, "Combine stacks automatically",
        "Merges split stacks so one click can fill the crate.",
        function() return settings.autoStack ~= false end,
        function(v) settings.autoStack = v end)


    y = AddHeading(page, y - 6, "Behavior")
    y = AddCheck(page, y, "Inactive areas start collapsed",
        "Applies until you expand or collapse an Inactive area yourself.",
        function() return settings.inactiveCollapsed ~= false end,
        function(v) settings.inactiveCollapsed = v; UpdateBars() end)
    y = AddCheck(page, y, "Show bank and alt counts in tooltips",
        "Adds where else you have a bar's item: your bank and other characters (once you've logged into them).",
        function() return settings.storageCounts ~= false end,
        function(v) settings.storageCounts = v end)
    y = AddCheck(page, y, "Mention the guide at every login",
        "A line in chat at login about /bartab guide and /bartab help. BarTab always mentions it once when it's new, and after an update.",
        function() return settings.loginTip end,
        function(v) settings.loginTip = v or nil end)
    y = AddCheck(page, y, "Show minimap button",
        "A BarTab button on the edge of the minimap: click to open these settings, drag to move it around the minimap.",
        function() return settings.minimapButton ~= false end,
        function(v) settings.minimapButton = v; UpdateMinimapButton() end)
    y = AddCheck(page, y, "Sum up the last session at login",
        "At login, a few lines in chat on your last session on this character: crafts, skill gained, materials gathered, gold spent. /bartab session shows the current one.",
        function() return settings.sessionAtLogin ~= false end,
        function(v) settings.sessionAtLogin = (not v) and false or nil end)


    y = AddHeading(page, y - 6, "Data")
    AddButton(page, 24, y, 112, "Reset sections", "Expands every section and subsection again.", function()
        settings.collapsed = {}
        for _, module in pairs(sectionModules) do
            if module.SetCollapsed then pcall(module.SetCollapsed, module, false) end
        end
        UpdateBars()
        Print("Section collapse states reset.")
    end)
    AddButton(page, 142, y, 112, "Untrack all", "Removes every bar (asks first).", function()
        local keys = {}
        for key in pairs(trackedItems) do keys[#keys + 1] = key end
        ConfirmUntrackKeys(keys, "BarTab")
    end)
    y = y - 30
    AddButton(page, 24, y, 112, "Share bars", "A text string of all your bars, to paste to a friend or another account.", function()
        ShareAll()
    end)
    AddButton(page, 142, y, 112, "Import bars", "Add bars from a string someone shared.", function()
        ShowShareWindow(nil)
    end)


    -- Alerts -------------------------------------------------------------
    page, y = pages.alerts, -4
    y = AddIntro(page, y, "What BarTab tells you when a bar fills, and how.")
    y = AddHeading(page, y - 6, "Alerts")
    y = AddCheck(page, y, "Alert when a bar reaches its goal",
        "A chat message when a material bar fills or a crate bundle is ready.",
        function() return settings.goalAlerts ~= false end,
        function(v) settings.goalAlerts = v end)
    y = AddCheck(page, y, "Alert when you can make the rest",
        "When the materials in your bags are enough to make the rest of a bar's item with your own recipes (8 / 10 Thick Leather, and Heavy Leather for 2 more). The bar also shows a lighter stretch for what you could make.",
        function() return settings.makeableAlerts ~= false end,
        function(v) settings.makeableAlerts = v end)
    y = AddCheck(page, y, "Warn when my bags are nearly full",
        "A chat message when your bags get down to 2 free slots, and when they're full. Crafting from a bar with no room for what it makes says so instead of trying.",
        function() return settings.bagSpaceWarn ~= false end,
        function(v) settings.bagSpaceWarn = v end)
    y = AddCheck(page, y, "Play a sound",
        "Plays a short chime with the alert.",
        function() return settings.alertSound ~= false end,
        function(v) settings.alertSound = v end)
    -- On-screen style: cycles Off -> Top of screen -> Raid warning.
    local styles = {
        { key = "top", name = "Top of screen" },
        { key = "raid", name = "Raid warning (large, center)" },
        { key = "off", name = "Off (chat only)" },
    }
    local function CurrentStyle()
        return settings.alertStyle or (settings.alertScreen == false and "off" or "top")
    end
    local styleButton = AddButton(page, 24, y, 350, "",
        "Click to switch how the alert shows on screen.", function()
            local index = 1
            for i, style in ipairs(styles) do
                if style.key == CurrentStyle() then index = i end
            end
            settings.alertStyle = styles[index % #styles + 1].key
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        for _, style in ipairs(styles) do
            if style.key == CurrentStyle() then
                styleButton:SetText("On screen: " .. style.name)
            end
        end
    end)
    y = y - 30
    AddButton(page, 24, y, 112, "Test alert", "Plays an example alert with your current choices.", function()
        PlayGoalAlert("Light Leather: 20 / 20, goal reached (test)")
    end)
    y = y - 30


    -- Crafting -----------------------------------------------------------
    page, y = pages.crafting, -4
    y = AddIntro(page, y, "What clicking a recipe bar does, making materials first, and shared materials.")
    y = AddHeading(page, y - 6, "Clicking a recipe bar")
    for _, modifier in ipairs(CLICK_MODIFIERS) do
        local button = AddButton(page, 24, y, 350, "", "Click to change what this does.", function()
            local current, index = GetClickAction(modifier.key), 1
            for i, action in ipairs(CLICK_ACTIONS) do
                if action.key == current then index = i end
            end
            settings.clickActions = settings.clickActions or {}
            settings.clickActions[modifier.key] = CLICK_ACTIONS[index % #CLICK_ACTIONS + 1].key
            RefreshConfig()
        end)
        table.insert(configRefreshers, function()
            local current = GetClickAction(modifier.key)
            for _, action in ipairs(CLICK_ACTIONS) do
                if action.key == current then
                    button:SetText(modifier.label .. ": " .. action.name)
                end
            end
        end)
        y = y - 26
    end
    y = y - 4

    y = AddHeading(page, y - 6, "Making materials first")
    local chainButton = AddButton(page, 24, y, 350, "",
        "When you click a recipe bar and you're short of a material one of your recipes makes (Thick Leather for an Ammo Pouch, from Heavy Leather), BarTab can make it first, then the recipe, several steps deep. Make them automatically, ask with the steps first, or only from a bar's right-click menu (\"Craft N, making materials first\").",
        function()
            local current, index = settings.chainCraft or "auto", 1
            for i, mode in ipairs(CHAIN_MODES) do
                if mode.key == current then index = i end
            end
            settings.chainCraft = CHAIN_MODES[index % #CHAIN_MODES + 1].key
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local current = settings.chainCraft or "auto"
        for _, mode in ipairs(CHAIN_MODES) do
            if mode.key == current then chainButton:SetText(mode.name) end
        end
    end)
    y = y - 28
    y = AddCheck(page, y, "Use my other professions too",
        "Also make materials with another of your professions: smelt Copper Bars with Mining for a Blacksmithing recipe, or Bolts of Cloth with Tailoring. BarTab switches professions between steps. Open each profession once so BarTab knows its recipes.",
        function() return settings.chainOtherProfessions end,
        function(v) settings.chainOtherProfessions = v or nil end)

    y = AddHeading(page, y - 6, "While crafting")
    y = AddCheck(page, y, "Count down as you craft",
        "Each craft takes one craft's worth off a recipe's bars (8/32 becomes 4/28), so a bar shows what's left to make. When the count runs out, the recipe's After crafting rule applies (with \"keep the bar\", the bars move to Inactive at full size). Change it per recipe on a bar's right-click menu; this is for recipes you haven't set.",
        function() return settings.countDownDefault end,
        function(v) settings.countDownDefault = v or nil end)

    y = AddHeading(page, y - 6, "Shared materials")
    local sharedModes = {
        { key = "share", name = "Share out in list order" },
        { key = "warn", name = "Count all, warn in tooltip" },
        { key = "off", name = "Count all, no warning" },
    }
    local sharedButton = AddButton(page, 24, y, 350, "",
        "When several bars count the same material: share it out (bars higher in the list claim it first), or let each bar count all of it.",
        function()
            local current, index = settings.sharedMaterials or "share", 1
            for i, mode in ipairs(sharedModes) do
                if mode.key == current then index = i end
            end
            settings.sharedMaterials = sharedModes[index % #sharedModes + 1].key
            UpdateBars()
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local current = settings.sharedMaterials or "share"
        for _, mode in ipairs(sharedModes) do
            if mode.key == current then sharedButton:SetText("Shared: " .. mode.name) end
        end
    end)
    y = y - 30


    -- Shopping ------------------------------------------------------------
    page, y = pages.shopping, -4
    y = AddIntro(page, y, "Getting what your own bars are short of: vendors, your bank, the auction house.")
    y = AddHeading(page, y - 6, "Vendors")
    local vendorButton = AddButton(page, 24, y, 350, "",
        "At a vendor that sells something your Crafting bars are short of (thread, dye, vials...): ask with a list and the cost, buy it straight away, or do nothing.",
        function()
            local current, index = settings.vendorBuy or "ask", 1
            for i, mode in ipairs(VENDOR_MODES) do
                if mode.key == current then index = i end
            end
            settings.vendorBuy = VENDOR_MODES[index % #VENDOR_MODES + 1].key
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local current = settings.vendorBuy or "ask"
        for _, mode in ipairs(VENDOR_MODES) do
            if mode.key == current then vendorButton:SetText(mode.name) end
        end
    end)
    y = y - 30

    y = AddCheck(page, y, "Only buy for crafts your bars cover",
        "Buys a recipe's vendor materials only for the crafts its tracked bars already cover. For example, tracking 10 Heavy Leather for Heavy Armor Kits (5 a kit) with 8 in your bags buys thread for 1 kit, not 2. Ingredients without a bar don't hold it up.",
        function() return settings.vendorWhenReady end,
        function(v) settings.vendorWhenReady = v or nil end)

    -- Most BarTab will spend at one vendor visit (asking or not).
    local limitLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    limitLabel:SetPoint("TOPLEFT", 24, y - 4)
    limitLabel:SetText("Spend at most, per visit:")
    local limitBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    limitBox:SetSize(80, 20)
    limitBox:SetPoint("LEFT", limitLabel, "RIGHT", 12, 0)
    limitBox:SetAutoFocus(false)
    limitBox:SetMaxLetters(14)
    local function saveLimit(self)
        local copper = ParseMoney(self:GetText())
        if copper and copper > 0 then
            settings.vendorLimit = copper
        elseif Trim(self:GetText()) == "" then
            settings.vendorLimit = nil -- back to the default
        else
            Print("Enter an amount like 1g, 50s or 2g 50s.")
        end
        self:SetText(MoneyText(GetVendorLimit()))
        self:ClearFocus()
    end
    limitBox:SetScript("OnEnterPressed", saveLimit)
    limitBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() ~= MoneyText(GetVendorLimit()) then saveLimit(self) end
    end)
    limitBox:SetScript("OnEscapePressed", function(self)
        self:SetText(MoneyText(GetVendorLimit()))
        self:ClearFocus()
    end)
    AddTooltip(limitBox, "Spend limit",
        "The most BarTab will spend at one vendor visit, even if you click Buy. Anything over it is left out, and BarTab says what. Type an amount like 1g, 50s or 2g 50s; empty for the default (1g).")
    table.insert(configRefreshers, function()
        if not limitBox:HasFocus() then limitBox:SetText(MoneyText(GetVendorLimit())) end
    end)
    y = y - 30

    local sellButton = AddButton(page, 24, y, 350, "",
        "At a vendor: things you made with your recipes (skill-up crafts like daggers, bags and bandages) that no bar uses and your other characters don't need. A window lists them; untick what to keep (remembered) or change amounts. Food, potions, bandages and crafting tools (Arclight Spanner, enchanting rods) start unticked. Crafting materials are never offered. /bartab sell offers again. This character only.",
        function()
            local current, index = CharSetting("vendorSell") or "ask", 1
            for i, mode in ipairs(SELL_MODES) do
                if mode.key == current then index = i end
            end
            SetCharSetting("vendorSell", SELL_MODES[index % #SELL_MODES + 1].key)
            RefreshConfig()
        end)
    AddCharacterTag(page, sellButton)
    table.insert(configRefreshers, function()
        local current = CharSetting("vendorSell") or "ask"
        for _, mode in ipairs(SELL_MODES) do
            if mode.key == current then sellButton:SetText(mode.name) end
        end
    end)
    y = y - 30
    y = AddCheck(page, y, "Also offer green and better crafts for sale",
        "Off: only common and poor quality crafts are offered, so uncommon (green) and better ones are left for disenchanting or your enchanter. On: those are offered too.",
        function() return settings.sellCraftedBetter end,
        function(v) settings.sellCraftedBetter = v or nil end)
    y = AddCheck(page, y, "Keep a stack of each when selling",
        "Selling crafts keeps a full stack of each stackable item (20 bandages, say) and offers only the rest. The same as the checkbox in the sell window.",
        function() return settings.sellKeepStack end,
        function(v) settings.sellKeepStack = v or nil end)

    y = AddHeading(page, y - 6, "Bank")
    local bankButton = AddButton(page, 24, y, 350, "",
        "At your bank, when it holds something your Crafting bars are short of in your bags: ask with a window where you can untick items or change amounts, take it out straight away, or do nothing. /bartab bank asks again while the bank is open.",
        function()
            local current, index = settings.bankWithdraw or "ask", 1
            for i, mode in ipairs(BANK_MODES) do
                if mode.key == current then index = i end
            end
            settings.bankWithdraw = BANK_MODES[index % #BANK_MODES + 1].key
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local current = settings.bankWithdraw or "ask"
        for _, mode in ipairs(BANK_MODES) do
            if mode.key == current then bankButton:SetText(mode.name) end
        end
    end)
    y = y - 30
    local depositButton = AddButton(page, 24, y, 350, "",
        "At your bank, after taking out what you need: crafting materials in your bags (ore, herbs, cloth, leather, parts) that none of your bars use, active or Inactive, can go into the bank. Anything your other characters are short of, and vendor-bought things like thread and vials, stay in your bags. The window lets you untick items or change amounts; what you untick is remembered for next time. /bartab bank put offers again. This character only.",
        function()
            local current, index = CharSetting("bankDeposit") or "ask", 1
            for i, mode in ipairs(DEPOSIT_MODES) do
                if mode.key == current then index = i end
            end
            SetCharSetting("bankDeposit", DEPOSIT_MODES[index % #DEPOSIT_MODES + 1].key)
            RefreshConfig()
        end)
    AddCharacterTag(page, depositButton)
    table.insert(configRefreshers, function()
        local current = CharSetting("bankDeposit") or "ask"
        for _, mode in ipairs(DEPOSIT_MODES) do
            if mode.key == current then depositButton:SetText(mode.name) end
        end
    end)
    y = y - 30

    y = AddHeading(page, y - 6, "Auction house")
    y = AddCheck(page, y, "Add a BarTab tab beside the auction house",
        "A tab on the auction house's right edge (beside any other addons' tabs) that opens a list of what your bars are short of, each with a Search button. Stays open while you browse results.",
        function() return settings.auctionList ~= false end,
        function(v)
            settings.auctionList = v
            if not v and auctionTab then
                if auctionPanel and auctionPanel:IsShown() then SetAuctionPanelOpen(false) end
                auctionTab:Hide()
            end
        end)
    y = AddCheck(page, y, "Include Inactive bars in the list",
        "Also list what your Inactive bars are short of (recipes you've shelved or haven't learned yet), so you can stock up while you're at the auction house.",
        function() return settings.auctionInactive end,
        function(v)
            settings.auctionInactive = v or nil
            if auctionPanel and auctionPanel:IsShown() then Safe("auction", UpdateAuctionPanel)() end
        end)

    -- Characters ----------------------------------------------------------
    page, y = pages.characters, -4
    y = AddIntro(page, y, "Gathering, banking and mailing for your other characters. Settings marked "
        .. CHARACTER_TAG_TEXT .. " are kept for each character on its own: on for your gatherers, off for your mains.")
    y = AddHeading(page, y - 6, "Shopping for others")
    y = AddCheck(page, y, "Show what my other characters need" .. CHARACTER_TAG,
        "A \"For your other characters\" subsection under BarTab: Crafting, with a bar for each material your other characters' bars are short of (\"Copper Ore for [Alt]\") that this character can get: gather with its own skills, make with its own recipes, or already has some of. Bars fill as you gather. Your own bars claim what you carry first. Mail them at a mailbox. Right-click a bar to hide it. This character only: each character keeps its own choice (turn it on for your gatherers, off for your mains).",
        function() return CharSetting("altShopping") end,
        function(v)
            SetCharSetting("altShopping", v and true or false)
            Safe("alt shopping", SyncAltNeedBars)()
        end)
    local unhideButton = AddButton(page, 24, y, 350, "",
        "Bars and recipes you chose not to shop for (right-click a \"For your other characters\" bar): show them all again.",
        function()
            ResetAltShopHidden()
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local count = AltShopHiddenCount()
        unhideButton:SetText(count > 0 and ("Shop for the hidden ones again (" .. count .. ")") or "Nothing hidden")
        if unhideButton.SetEnabled then unhideButton:SetEnabled(count > 0) end
    end)
    y = y - 30

    y = AddHeading(page, y - 6, "Mailbox")
    local mailButton = AddButton(page, 24, y, 350, "",
        "At a mailbox: offer to mail your other characters (same realm and faction) what their bars are short of and you have spare after your own bars' goals. Their needs come from their bars and their last saved bags and bank. /bartab mail asks again. This character only: each character keeps its own choice.",
        function()
            local current, index = CharSetting("mailSend") or "ask", 1
            for i, mode in ipairs(MAIL_MODES) do
                if mode.key == current then index = i end
            end
            SetCharSetting("mailSend", MAIL_MODES[index % #MAIL_MODES + 1].key)
            RefreshConfig()
        end)
    AddCharacterTag(page, mailButton)
    table.insert(configRefreshers, function()
        local current = CharSetting("mailSend") or "ask"
        for _, mode in ipairs(MAIL_MODES) do
            if mode.key == current then mailButton:SetText(mode.name) end
        end
    end)
    y = y - 30

    local collectButton = AddButton(page, 24, y, 350, "",
        "At a mailbox: letters your other characters sent with BarTab (subject \"BarTab: materials\") are offered to take in one go, or taken straight away. Other mail is left alone. This character only: each character keeps its own choice.",
        function()
            local current, index = CharSetting("mailCollect") or "ask", 1
            for i, mode in ipairs(COLLECT_MODES) do
                if mode.key == current then index = i end
            end
            SetCharSetting("mailCollect", COLLECT_MODES[index % #COLLECT_MODES + 1].key)
            RefreshConfig()
        end)
    AddCharacterTag(page, collectButton)
    table.insert(configRefreshers, function()
        local current = CharSetting("mailCollect") or "ask"
        for _, mode in ipairs(COLLECT_MODES) do
            if mode.key == current then collectButton:SetText(mode.name) end
        end
    end)
    y = y - 30

    y = AddCheck(page, y, "Send letters in one press",
        "Clicking Mail in BarTab's prompt sends the first letter right away, and at an open mailbox your BarTab craft key (or /bartab craft) sends the next one, or mails what's ticked while BarTab's prompt is showing (otherwise it crafts as usual). The game allows one letter per click or key press, so each letter still needs one.",
        function() return settings.mailAutoSend end,
        function(on) settings.mailAutoSend = on or nil end)
    y = AddCheck(page, y, "Start the mail prompt with \"Mail all I have of each\"",
        "The mail prompt starts with everything you have spare of each material (after your own bars' goals), not just what the other character is short. The checkbox in the prompt changes it for that time only; this is what it starts as. You can still change each amount.",
        function() return settings.mailAll end,
        function(v) settings.mailAll = v or nil end)

    y = AddCheck(page, y, "Send crafted greens to my enchanter" .. CHARACTER_TAG,
        "The mail prompt also offers gear you made with your recipes, uncommon (green) or better, that no bar uses, to your character with Enchanting to disenchant. Selling at a vendor leaves these out unless you ask for them there. This character only.",
        function() return CharSetting("mailDisenchant") ~= false end,
        function(v) SetCharSetting("mailDisenchant", v and true or false) end)
    local enchanterButton = AddButton(page, 24, y, 350, "",
        "Which character gets crafts to disenchant. Automatic: the first of your characters (same realm and faction) BarTab has seen with Enchanting; open their Enchanting window once so BarTab knows. Click to switch.",
        function()
            local choices = { false }
            for _, key in ipairs(EnchanterCharacters()) do choices[#choices + 1] = key end
            choices[#choices + 1] = "none"
            local current, index = settings.enchanter or false, 1
            for i, choice in ipairs(choices) do
                if choice == current then index = i end
            end
            settings.enchanter = choices[index % #choices + 1] or nil
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local choice = settings.enchanter
        local text
        if choice == "none" then
            text = "Enchanter: nobody (don't send crafts)"
        elseif choice then
            text = "Enchanter: " .. CharacterName(choice)
        else
            local auto = EnchanterCharacter()
            text = "Enchanter: automatic (" .. (auto and CharacterName(auto) or "none seen yet") .. ")"
        end
        enchanterButton:SetText(text)
    end)
    y = y - 30

    y = AddHeading(page, y - 6, "Bank")
    y = AddCheck(page, y, "Also take out what my other characters need" .. CHARACTER_TAG,
        "At the bank, also offers what your other characters' bars are short of and your bank holds, so you can mail it to them: only what you don't keep for yourself, and only with the mailbox offer on. This character only.",
        function() return CharSetting("bankForAlts") ~= false end,
        function(v) SetCharSetting("bankForAlts", v and true or false) end)

    -- Recipes -------------------------------------------------------------
    page, y = pages.recipes, -4
    y = AddIntro(page, y, "The profession window, favorite recipes, and appearances you haven't collected.")
    y = AddHeading(page, y - 6, "Professions")
    y = AddCheck(page, y, "Mark tracked recipes in the profession window",
        "A check mark beside each recipe you have bars for, in the profession window's recipe list.",
        function() return settings.recipeListMarks ~= false end,
        function(v)
            settings.recipeListMarks = v
            RefreshRecipeListMarks()
        end)
    y = AddCheck(page, y, "Training reminders",
        "Tells you when a profession reaches its limit (75, 150, 225) and needs the next rank, and when recipes you saw at a trainer but couldn't learn yet are within reach. A profession at its limit also shows its skill in orange.",
        function() return settings.trainingReminders ~= false end,
        function(v) settings.trainingReminders = v end)
    y = AddCheck(page, y, "\"Track Recipe\" tracks in BarTab",
        "The Track Recipe checkbox under a recipe in the profession window, and Track Recipe on the recipe list's right-click menu, track in BarTab instead of the game's own recipe tracking: the Track with settings window (pick the ingredients, crafts and rules), or for a profession shown one bar per recipe, every ingredient straight away; unticking it untracks the recipe's bars. The checkbox then shows whether the recipe has BarTab bars.",
        function() return settings.trackCheckboxBarTab end,
        function(v) settings.trackCheckboxBarTab = v or nil end)

    y = AddHeading(page, y - 6, "Favorite recipes")
    AddButton(page, 24, y, 170, "Import favorites",
        "With a profession open: bars for its starred recipes that aren't tracked yet (one craft each). A window lets you track the main ingredients or all of them, or choose for each. (/bartab favorites)",
        function() Safe("favorites", ImportFavoriteRecipes)() end)
    y = y - 30
    y = AddCheck(page, y, "Track recipes when you favorite them",
        "Clicking the star beside a recipe in the profession window asks which of its ingredients to track.",
        function() return settings.autoFavorites end,
        function(v) settings.autoFavorites = v or nil end)

    y = AddHeading(page, y - 6, "Appearances")
    y = AddCheck(page, y, "Track recipes for appearances you haven't collected",
        "When you learn a recipe, or open a profession, recipes that make gear with an appearance this character can collect but hasn't get bars for one craft, untracked after crafting. Each recipe is offered once, and skipped if you already have one crafted. Equip or disenchant the result to collect it. (/bartab appearances)",
        function() return settings.appearanceRecipes end,
        function(v)
            settings.appearanceRecipes = v
            if v then
                appearanceSnoozed = nil
                Safe("appearances", ScanAppearanceRecipes)()
            end
        end)
    local appearanceButton = AddButton(page, 24, y, 350, "",
        "Which of a recipe's ingredients get bars. Ask: a window lists them, with the main one (the one it needs most) ticked. Main: just that one. Every: all of them, thread and dye included.",
        function()
            local current, index = settings.appearanceBars or "ask", 1
            for i, mode in ipairs(APPEARANCE_MODES) do
                if mode.key == current then index = i end
            end
            settings.appearanceBars = APPEARANCE_MODES[index % #APPEARANCE_MODES + 1].key
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local current = settings.appearanceBars or "ask"
        for _, mode in ipairs(APPEARANCE_MODES) do
            if mode.key == current then appearanceButton:SetText(mode.name) end
        end
    end)
    y = y - 30
    y = AddCheck(page, y, "Add appearance bars to Inactive",
        "New appearance bars start in the profession's Inactive area, out of the way until you move one up to craft it.",
        function() return settings.appearanceInactive end,
        function(v) settings.appearanceInactive = v or nil end)
    y = AddCheck(page, y, "Include recipes that no longer give skill",
        "Also green and gray recipes. Off: only orange and yellow ones.",
        function() return settings.appearanceAllColors end,
        function(v) settings.appearanceAllColors = v end)

    -- Display ------------------------------------------------------------
    page, y = pages.display, -4
    y = AddIntro(page, y, "How the bars look, and where they show.")
    y = AddHeading(page, y - 6, "Look")
    y = AddStepper(page, y, "Bar height", "Height of every bar, in pixels.", 12, 32,
        function() return settings.barHeight or 20 end,
        function(v) settings.barHeight = v; UpdateBars() end)
    y = AddStepper(page, y, "Bar text size", "Size of the text on the bars.", 8, 18,
        function() return settings.textSize or 12 end,
        function(v) settings.textSize = v; UpdateBars() end)

    local colors = AddButton(page, 24, y, 350, "", "Click to switch color sets.", function()
        local index = 1
        for i, palette in ipairs(PALETTES) do
            if palette.key == settings.palette then index = i end
        end
        local nextPalette = PALETTES[index % #PALETTES + 1]
        settings.palette = nextPalette.key
        ApplyPalette(nextPalette.key)
        UpdateBars()
        RefreshConfig()
    end)
    table.insert(configRefreshers, function()
        local name = "?"
        for _, palette in ipairs(PALETTES) do
            if palette.key == settings.palette then name = palette.name end
        end
        colors:SetText("Colors: " .. name)
    end)
    y = y - 30

    local materialButton = AddButton(page, 24, y, 350, "",
        "How recipe bars show: a bar for each ingredient of each recipe; one bar per material for all of a profession's tracked recipes (\"Peacebloom 2 / 3\"; click it to pick a recipe to craft, Shift-click for the first that's ready, Alt-click for everything ready); or one bar per recipe (\"Minor Mana Potion: 1 / 3 materials\", filling as you gather any of them). This is the default; right-click a profession's heading to choose for that profession.",
        function()
            local current, index = MaterialMode("default-profession"), 1
            for i, mode in ipairs(BAR_MODES) do
                if mode.key == current then index = i end
            end
            settings.materialModeDefault = BAR_MODES[index % #BAR_MODES + 1].key
            UpdateBars()
            Safe("material bars", RefreshTracker)(true)
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local current = MaterialMode("default-profession")
        for _, mode in ipairs(BAR_MODES) do
            if mode.key == current then materialButton:SetText("Recipe bars: " .. mode.name) end
        end
    end)
    y = y - 30

    y = AddCheck(page, y, "Show vendor-bought materials on recipe bars",
        "Off: ingredients you buy from vendors (vials, thread, flux) get no bar of their own and aren't counted on material or recipe bars. BarTab still buys them for you at vendors, and crafting still needs them.",
        function() return settings.showVendorMats end,
        function(on)
            settings.showVendorMats = on or nil
            UpdateBars()
            Safe("material bars", RefreshTracker)(true)
        end)

    local markButton = AddButton(page, 24, y, 350, "",
        "How a recipe bar's name shows the recipe's difficulty: skill-up arrows like the profession window (3 orange, 2 yellow, 1 green, none gray), the name in the recipe's color, or no marking.",
        function()
            local current, index = settings.difficultyMark or "arrows", 1
            for i, mode in ipairs(DIFFICULTY_MARKS) do
                if mode.key == current then index = i end
            end
            settings.difficultyMark = DIFFICULTY_MARKS[index % #DIFFICULTY_MARKS + 1].key
            UpdateBars()
            Safe("difficulty", RefreshTracker)(true)
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local current = settings.difficultyMark or "arrows"
        for _, mode in ipairs(DIFFICULTY_MARKS) do
            if mode.key == current then markButton:SetText("Difficulty: " .. mode.name) end
        end
    end)
    y = y - 30

    y = AddCheck(page, y, "Show BarTab lines on item tooltips",
        "Hovering an item you track (in bags, the auction house, loot, chat links...) adds lines like \"BarTab: 4/5 for Hillman's Cloak\".",
        function() return settings.itemTooltips ~= false end,
        function(v) settings.itemTooltips = v end)


    y = AddHeading(page, y - 6, "BarTab window")
    -- Where the bars show: the objective tracker, or BarTab's own window
    -- (needed when another addon such as Questie replaces the tracker).
    local displayButton = AddButton(page, 24, y, 350, "",
        "Some addons replace the objective tracker with their own and hide it, along with BarTab's sections. "
        .. "The first choice shows BarTab in its own window whenever the objective tracker is hidden. Drag a section heading to move the window.",
        function()
            local current, index = settings.displayMode or "auto", 1
            for i, mode in ipairs(DISPLAY_MODES) do
                if mode.key == current then index = i end
            end
            settings.displayMode = DISPLAY_MODES[index % #DISPLAY_MODES + 1].key
            UpdateBars()
            RefreshConfig()
        end)
    table.insert(configRefreshers, function()
        local current = settings.displayMode or "auto"
        for _, mode in ipairs(DISPLAY_MODES) do
            if mode.key == current then displayButton:SetText("Show in: " .. mode.name) end
        end
    end)
    y = y - 26
    AddButton(page, 24, y, 170, "Reset window position",
        "Puts BarTab's own window back at its starting spot.",
        function() ResetPanelPosition() end)
    -- Lock: a checkbox on the same row as the Reset button.
    local lock = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    lock:SetSize(24, 24)
    lock:SetPoint("TOPLEFT", 206, y + 1)
    if type(lock.Text) == "table" then lock.Text:SetText("") end
    local lockText = lock:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lockText:SetPoint("LEFT", lock, "RIGHT", 4, 0)
    lockText:SetText("Lock window")
    lock:SetScript("OnClick", function(self)
        settings.panelLocked = self:GetChecked() and true or nil
    end)
    AddTooltip(lock, "Lock window", "Stops BarTab's own window from being dragged by its section headings.")
    table.insert(configRefreshers, function() lock:SetChecked(settings.panelLocked and true or false) end)
    y = y - 30
    y = AddStepper(page, y, "Window width", "Width of BarTab's own window, in pixels.",
        PANEL_WIDTH_MIN, PANEL_WIDTH_MAX,
        function() return PanelWidth() end,
        function(v) settings.panelWidth = v; UpdateBars() end, 10)


    ShowTab(settings.configTab or "general")

    frame:SetScript("OnShow", RefreshConfig)
    return frame
end

ToggleConfig = function()
    configFrame = configFrame or BuildConfigFrame()
    configFrame:SetShown(not configFrame:IsShown())
end

-- Also listed under Options -> AddOns, with a button that opens the window.
RegisterOptionsPage = function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local page = CreateFrame("Frame")
    page.name = "BarTab"
    local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("BarTab's settings open in their own window (also /bartab config).")
    local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    button:SetSize(180, 24)
    button:SetPoint("TOPLEFT", 16, -40)
    button:SetText("Open BarTab Settings")
    button:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        configFrame = configFrame or BuildConfigFrame()
        configFrame:Show()
    end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, page, "BarTab")
    if ok and category then
        pcall(Settings.RegisterAddOnCategory, category)
    end
end

-- The addon button by the minimap (named in BarTab.toc).
-- Minimap button ------------------------------------------------------------


function PositionMinimapButton()
    local angle = math.rad(settings.minimapAngle or 225)
    local radius = (Minimap:GetWidth() / 2) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

function CreateMinimapButton()
    local button = CreateFrame("Button", "BarTabMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\BarTab\\Media\\icon")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then ShowGuide() else ToggleConfig() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("BarTab")
        GameTooltip:AddLine("Click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right-click: user's guide", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Dragging moves it around the minimap's edge.
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local mx, my = Minimap:GetCenter()
            settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PositionMinimapButton()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    minimapButton = button
    PositionMinimapButton()
end

UpdateMinimapButton = function()
    if not Minimap then return end
    if settings.minimapButton == false then
        if minimapButton then minimapButton:Hide() end
        return
    end
    if not minimapButton then CreateMinimapButton() end
    minimapButton:Show()
end

_G.BarTab_OnAddonCompartmentClick = function()
    ToggleConfig()
end
end
