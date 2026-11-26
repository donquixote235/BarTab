-- BarTab: the user's guide window (/bartab guide), and the one-time tip at
-- login (first install, or after an update).
-- Shares BarTab's private namespace; see the top of BarTab.lua.
local _, ns = ...
setfenv(1, ns)

local function H(text) return "|cffffd100" .. text .. "|r" end   -- a heading
local function C(text) return "|cff80c0ff" .. text .. "|r" end   -- a command or click
local B = "  - "                                                   -- a bullet

-- Each page: a title for the list on the left, and its text. Paragraphs are
-- separated by a blank line. Keep this in step with the README.
GUIDE_PAGES = {
    {
        title = "What's new",
        text = H("New in 1.60.1.8") .. "\n\n"
            .. B .. "This guide (" .. C("/bartab guide") .. "), with a section for each part of BarTab.\n"
            .. B .. "Recipe difficulty next to bar names: the profession window's skill-up arrows, or the name in the recipe's color (Display settings).\n"
            .. B .. "The profession window's Track Recipe checkbox can open BarTab's Track with settings window instead of the game's own tracking (Recipes settings).\n"
            .. B .. "\"Only buy for crafts your bars cover\" counts what chain crafting could make, too, so the vendor offers thread for the whole batch.\n\n"
            .. H("New in 1.60.1.7") .. "\n\n"
            .. B .. "Chain crafting: a click makes missing materials first, then the recipe.\n"
            .. B .. "A lighter \"could make\" stretch on material bars, with an alert when your bags hold enough for the rest.\n"
            .. B .. "Bank withdraw, and a Shopping tab in the settings.\n\n"
            .. "The full list of changes is in CHANGELOG.md in the addon's folder.",
    },
    {
        title = "Getting started",
        text = "BarTab shows what you're collecting as progress bars in the objective tracker, in two sections:\n\n"
            .. B .. H("BarTab: Crafting") .. " - materials, usually tied to a recipe you can craft straight from the bar. One subsection per profession, then Other and Inactive.\n"
            .. B .. H("BarTab: Items") .. " - fill-up items like Waylaid Crates, and anything else you're collecting.\n\n"
            .. H("Your first bar") .. "\n\n"
            .. "Open a profession, select a recipe, and click the BarTab button beside the favorite star. Under Track, pick one of its ingredients, All ingredients, or With settings... to set the recipe up in one window. A bar appears, sized for one craft.\n\n"
            .. "You can also Alt-Shift-click any item (in your bags, the bank, chat links or loot) to track it, or type " .. C("/bartab track Light Leather 20") .. ".\n\n"
            .. H("Getting help") .. "\n\n"
            .. C("/bartab help") .. " gives quick tips in chat; this guide has the details. Settings are in " .. C("/bartab config") .. ", the minimap button, or Options > AddOns > BarTab.",
    },
    {
        title = "Reading a bar",
        text = "A recipe bar is headed with what you're making and counts one of its materials: " .. C("Hillman's Cloak") .. ", " .. C("3 / 5 Heavy Leather | Crafts: 0") .. ".\n\n"
            .. B .. "Blue blocks are crafts you can make now; orange blocks are crafts held back by another ingredient. A line marks where each craft ends.\n"
            .. B .. "A lighter stretch after what you have shows how much more the materials in your bags could make (Heavy Leather that could become Thick Leather, for example).\n"
            .. B .. "Arrows by the name show the recipe's difficulty, like the profession window: three for orange, two for yellow, one for green.\n"
            .. B .. "\"Make until I have...\" bars count what the recipe makes instead, with a lighter stretch for what your materials would make.\n\n"
            .. H("The tooltip") .. "\n\n"
            .. "Hover a bar for the recipe's whole shopping list, your bank and alt counts, what you've gained this session and how fast, how long the crafts will take, and what each click will do.\n\n"
            .. "Hovering an item you track anywhere in the game adds a line like " .. C("BarTab: 4/5 for Hillman's Cloak") .. ".",
    },
    {
        title = "Crafting from bars",
        text = "Click a recipe bar to craft, even with the profession window closed (BarTab loads the profession quietly when you hover a bar).\n\n"
            .. B .. C("Click") .. ": craft 1.\n"
            .. B .. C("Shift-click") .. ": craft as many as fit the bar.\n"
            .. B .. C("Alt-click") .. ": craft all you can.\n\n"
            .. "Change what each click does in the settings (Crafting tab). " .. C("/bartab craft") .. ", or a key binding (Key Bindings > AddOns), crafts the next bar that's ready.\n\n"
            .. H("Shared materials") .. "\n\n"
            .. "When several bars count the same material, it's shared out in list order, so the bar higher up claims it first. Ctrl-drag bars to reorder them, or change this in the settings.\n\n"
            .. H("Count down as you craft") .. "\n\n"
            .. "With Count down on (a bar's right-click menu, or a default in the settings), each craft takes one craft's worth off the recipe's bars, so the bar shows what's left to make.",
    },
    {
        title = "Chain crafting",
        text = "When you click a recipe bar and you're short of a material one of your recipes makes, BarTab makes that first, then the recipe: " .. C("Making 2 Thick Leather first, then 1 Thick Leather Ammo Pouch") .. ".\n\n"
            .. B .. "It goes several steps deep: Medium Leather into Heavy, Heavy into Thick, then the Ammo Pouch.\n"
            .. B .. "It does one step at a time, waiting for each batch to finish. Click a bar again to stop after the current craft.\n"
            .. B .. "Only vendor items missing (thread, dye)? It makes the rest now and tells you what to buy; the vendor prompt offers it when you visit one.\n"
            .. B .. "Not enough for even one craft? It makes what it can toward the bar.\n"
            .. B .. "Nothing can be made? It says what's missing, one step down the chain: " .. C("missing Heavy Leather (10/24, to get)") .. ".\n\n"
            .. H("Settings (Crafting tab)") .. "\n\n"
            .. "Make materials first automatically, ask first with the steps, or only from a bar's right-click menu (" .. C("Craft N, making materials first") .. "). Tick \"Use my other professions too\" to let a chain switch profession, such as smelting bars with Mining for Blacksmithing. Open each profession once so BarTab knows its recipes.",
    },
    {
        title = "Goals and rules",
        text = H("Make until I have...") .. "\n\n"
            .. "Crafts a recipe until you have a set number of what it makes (" .. C("/bartab make 52") .. ", or Goals on the BarTab button). The bar counts what you're making; clicks craft only what's still missing, and a batch stops at the target.\n\n"
            .. H("Make until I reach...") .. "\n\n"
            .. "Levels a profession to a skill level. The bars are sized at one craft per skill point still needed, shrink only when a craft gives you a point, and clear when you get there.\n\n"
            .. H("On a bar's right-click menu") .. "\n\n"
            .. B .. C("Crafts") .. ": size the recipe's bars for 1, 5 or 10 crafts, the crafts to your next skill tier, a full stack, all of a material you have, or any number. It also switches a recipe between ingredient bars, a goal for what it makes, and a skill level.\n"
            .. B .. C("After crafting") .. ": keep the bars, move them to Inactive, or untrack them once you've crafted the recipe.\n"
            .. B .. C("Stop tracking") .. ": untrack at a skill level, or when the recipe turns yellow, green or gray (optionally asking first).\n\n"
            .. H("Training reminders") .. "\n\n"
            .. "BarTab tells you when a profession reaches its limit (75, 150, 225) and which rank to learn next, and the skill on its heading turns orange until you train. Trainers you visit are remembered, and BarTab lets you know when recipes you couldn't learn there yet come within reach.",
    },
    {
        title = "Profit and leveling",
        text = H("The profit window") .. "\n\n"
            .. C("/bartab profit") .. " (or Profit calculator on the BarTab button), with a profession open, lists what each of its recipes earns: sold to a vendor, or at the auction house after its cut, whichever pays more.\n\n"
            .. B .. "Choose how to count materials you have (free, at auction price, or at vendor price), and materials you're missing (buy them, buy or make them when cheaper, or leave those recipes out).\n"
            .. B .. "Items from your gathering skills (leather you can skin, ore, herbs) can count as free.\n"
            .. B .. "Sort by profit per craft, per hour, or in total for what you can make now.\n"
            .. B .. "Hover a row for its cost breakdown; click to show the recipe; Shift-click to search for it at the auction house; right-click to track it, or to count one of its materials as your own or as bought.\n\n"
            .. "Auction prices come from your auction addon, if you use one, as of your last scan.\n\n"
            .. H("What to craft next") .. "\n\n"
            .. C("/bartab next") .. " ranks your recipes by what a skill point costs after selling what you make (or by how long a point takes). Recipe colors give the odds of a point: orange every craft, yellow about 3 in 4, green about 1 in 4.",
    },
    {
        title = "Shopping",
        text = H("Vendors") .. "\n\n"
            .. "At a vendor that sells something your Crafting bars are short of (thread, dye, vials), BarTab lists it with the cost and offers to buy it. It never spends more than your per-visit limit (1g unless you change it). Untick \"Buy materials at vendors\" on a bar's right-click menu to leave that recipe out.\n\n"
            .. H("Your bank") .. "\n\n"
            .. "At your bank, BarTab offers to take out what your bars are short of, moving only as much as you need. " .. C("/bartab bank") .. " asks again while the bank is open.\n\n"
            .. H("Your other characters") .. "\n\n"
            .. "At a mailbox, BarTab offers to mail your other characters (same realm and faction) what their bars are short of and you have spare after your own bars' goals: ore for your blacksmith, leather for your leatherworker. It sends exact amounts, one letter per character. " .. C("/bartab mail") .. " asks again. Their needs come from their bars and their last saved bags and bank.\n\n"
            .. H("The auction house") .. "\n\n"
            .. "A BarTab tab on the auction house's right edge opens a list of what your bars are short of, each with a Search button.\n\n"
            .. "All of these can ask first, act automatically, or be turned off in the settings (Shopping tab).",
    },
    {
        title = "Fill-up items",
        text = "Fill-up items like Waylaid Crates are added to BarTab: Items when they reach your bags, with one bar per bundle the crate accepts (" .. C("20 Light Leather") .. ", " .. C("40 Linen Cloth") .. ").\n\n"
            .. B .. "Split stacks are combined for you.\n"
            .. B .. "When a bar says Ready, click it to fill the crate (not in combat).\n"
            .. B .. C("Focus on") .. " (right-click) shows just one bundle.\n"
            .. B .. C("/bartab item Waylaid Crate") .. " adds one by hand.\n\n"
            .. "Alt-Shift-click anything else (a potion, a reagent) to collect it here with a goal.",
    },
    {
        title = "Managing bars",
        text = H("Menus") .. "\n\n"
            .. B .. "Right-click a bar: Crafting (open recipe, Crafts, chain crafting), Rules (after crafting, count down, stop tracking) and This bar (assign, move to Inactive, share, untrack).\n"
            .. B .. "Right-click a heading: move all to Inactive, share, untrack all.\n"
            .. B .. "Ctrl-drag a bar to reorder; Ctrl-click a recipe bar to open its recipe.\n\n"
            .. H("Undo") .. "\n\n"
            .. "Bars removed by a rule, a goal or Untrack are remembered. " .. C("/bartab undo") .. " brings back the last ones, " .. C("/bartab undo list") .. " shows the last 10, and the BarTab button has Recently removed too.\n\n"
            .. H("Characters and sharing") .. "\n\n"
            .. "Each character has its own bars. " .. C("/bartab copy <character>") .. " copies another character's; " .. C("/bartab share") .. " and " .. C("/bartab import") .. " pass bars as text to a friend or another account.\n\n"
            .. H("Its own window") .. "\n\n"
            .. "If another addon hides the objective tracker, BarTab shows its sections in its own window (" .. C("/bartab window") .. ").",
    },
    {
        title = "Settings",
        text = C("/bartab config") .. ", the minimap button, or Options > AddOns > BarTab. Hover any setting for a full description.\n\n"
            .. B .. H("General") .. ": which sections show, bank and alt counts, the minimap button, alerts, reset, share and import.\n"
            .. B .. H("Crafting") .. ": what each click does, making materials first, count down, shared materials.\n"
            .. B .. H("Shopping") .. ": vendors, the bank, the mailbox, the auction house tab.\n"
            .. B .. H("Recipes") .. ": recipe list check marks, training reminders, Track Recipe in BarTab, favorites, appearances.\n"
            .. B .. H("Items") .. ": fill-up item tracking, stack combining.\n"
            .. B .. H("Display") .. ": bar size and text, color sets (color-blind friendly), recipe difficulty marks, tooltip lines, BarTab's own window.",
    },
    {
        title = "Commands",
        text = "Every command starts with " .. C("/bartab") .. " or " .. C("/btab") .. ".\n\n"
            .. B .. C("help [topic]") .. " - quick tips: crafting, goals, profit, shopping, items, bars\n"
            .. B .. C("guide") .. " - this guide\n"
            .. B .. C("config") .. " - settings\n"
            .. B .. C("track <item> [max]") .. " - track an item\n"
            .. B .. C("assign <item>") .. " - track a material for the selected recipe\n"
            .. B .. C("make <count>") .. " - craft the selected recipe until you have that many\n"
            .. B .. C("craft") .. " - craft the next ready bar\n"
            .. B .. C("profit") .. " / " .. C("next") .. " - the profit window / what to craft next\n"
            .. B .. C("bank") .. " - offer again to take materials out of the bank\n"
            .. B .. C("mail") .. " - offer again to mail your other characters what their bars need\n"
            .. B .. C("undo [list | number]") .. " - bring back removed bars\n"
            .. B .. C("untrack <name>") .. ", " .. C("unassign <name>") .. " - by name\n"
            .. B .. C("copy <character>") .. ", " .. C("share") .. ", " .. C("import") .. " - copy and share bars\n"
            .. B .. C("favorites") .. ", " .. C("trainer") .. ", " .. C("appearances on|off") .. " - more ways to track recipes\n"
            .. B .. C("item <name>") .. ", " .. C("autoitems on|off") .. " - fill-up items\n"
            .. B .. C("window") .. " - BarTab's own window\n"
            .. B .. C("refresh") .. ", " .. C("errors") .. " - if the tracker stops updating, and for bug reports",
    },
}

GUIDE_WIDTH, GUIDE_HEIGHT, GUIDE_NAV = 700, 500, 170

function CreateGuideWindow()
    local ok, frame = pcall(CreateFrame, "Frame", "BarTabGuideFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not frame then
        frame = CreateFrame("Frame", "BarTabGuideFrame", UIParent, "BackdropTemplate")
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
    frame:SetSize(GUIDE_WIDTH, GUIDE_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "BarTabGuideFrame") -- Escape closes it

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -6)
    frame.title:SetText("BarTab: user's guide")

    -- The page list on the left.
    frame.navButtons = {}
    for index, page in ipairs(GUIDE_PAGES) do
        local button = CreateFrame("Button", nil, frame)
        button:SetSize(GUIDE_NAV - 16, 22)
        button:SetPoint("TOPLEFT", 12, -32 - (index - 1) * 24)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("LEFT", 8, 0)
        button.text:SetText(page.title)
        button.selected = button:CreateTexture(nil, "BACKGROUND")
        button.selected:SetAllPoints()
        button.selected:SetColorTexture(1, 0.82, 0, 0.18)
        button.selected:Hide()
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        button:SetScript("OnClick", function() ShowGuidePage(index) end)
        frame.navButtons[index] = button
    end
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 0.82, 0, 0.3)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", GUIDE_NAV, -30)
    divider:SetPoint("BOTTOMLEFT", GUIDE_NAV, 12)

    -- The page itself, scrolling.
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", GUIDE_NAV + 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 14)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(GUIDE_WIDTH - GUIDE_NAV - 56, 10)
    scroll:SetScrollChild(child)
    frame.page = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.page:SetPoint("TOPLEFT", 0, 0)
    frame.page:SetWidth(GUIDE_WIDTH - GUIDE_NAV - 60)
    frame.page:SetJustifyH("LEFT")
    frame.page:SetJustifyV("TOP")
    if frame.page.SetSpacing then frame.page:SetSpacing(3) end
    frame.scroll, frame.child = scroll, child

    frame:Hide()
    return frame
end

function ShowGuidePage(index)
    local frame = guideWindow
    if not frame then return end
    local page = GUIDE_PAGES[index] or GUIDE_PAGES[1]
    for i, button in ipairs(frame.navButtons) do
        button.selected:SetShown(i == index)
        button.text:SetFontObject(i == index and "GameFontHighlight" or "GameFontNormal")
    end
    frame.page:SetText(page.text)
    frame.child:SetHeight(math.max(10, (frame.page:GetStringHeight() or 0) + 12))
    if frame.scroll.SetVerticalScroll then frame.scroll:SetVerticalScroll(0) end
    settings.guidePage = index
end

-- topic: a page title (or the start of one), e.g. /bartab guide chain.
function ShowGuide(topic)
    guideWindow = guideWindow or CreateGuideWindow()
    local index = settings.guidePage or 1
    if topic and topic ~= "" then
        local wanted = string.lower(topic)
        for i, page in ipairs(GUIDE_PAGES) do
            if string.lower(page.title):find(wanted, 1, true) then index = i break end
        end
    end
    guideWindow:Show()
    guideWindow:Raise()
    ShowGuidePage(index)
end

-- At login: a line about the guide on first install, and after an update
-- (opening on What's new); every login only with settings.loginTip.
function ShowLoginTip()
    local version = ADDON_VERSION
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata("BarTab", "Version") or version
    elseif GetAddOnMetadata then
        version = GetAddOnMetadata("BarTab", "Version") or version
    end
    local seen = settings.guideSeenVersion
    -- New here: no saved settings at all when BarTab loaded (someone who
    -- used BarTab before the guide existed gets the update line instead).
    if not seen and brandNewInstall then
        Print("New here? Type " .. C("/bartab guide") .. " for the user's guide, or " .. C("/bartab help") .. " for quick tips.")
        settings.guidePage = 2 -- Getting started
    elseif version and seen ~= version then
        Print("Updated to " .. version .. ". Type " .. C("/bartab guide") .. " to see what's new.")
        settings.guidePage = 1 -- What's new
    elseif settings.loginTip then
        Print("Type " .. C("/bartab guide") .. " for the user's guide, or " .. C("/bartab help") .. " for quick tips.")
    end
    settings.guideSeenVersion = version or seen or "?"
end
