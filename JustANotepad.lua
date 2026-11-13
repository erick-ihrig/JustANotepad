-- Just a Notepad
-- A text box that floats over the UI. A thin header row above it holds the page tabs (left) and small controls
-- (right). Saves as you type. The box, tabs and controls fade away
-- when the notepad isn't hovered or focused, leaving only the text (or nothing, with the eye toggle).
--
-- Data (JustANotepadDB, account-wide):
--   settings              options (DEFAULTS below), window position and size, whether it was open
--   pages                 shared pages: { title, text }
--   characterPages[key]   per-character pages, when that option is on
--
-- Commands: /note (toggle), /note settings, /note reset, /note size N, /note bg N
-- Keybind: Key Bindings > AddOns > Just a Notepad.
-- Sections, in order: data and pages, undo, window and fading, controls, search, tabs, launchers, settings,
-- commands and events.

local ADDON_NAME = ...

local DEFAULTS = {
    perCharacter = false,
    showSearch = true,      -- which corner controls appear
    showUndo = true,
    showLocation = true,
    showEye = true,
    showClose = true,
    fadeText = false,       -- the eye toggle: the text fades with everything else
    fadedTextAlpha = 0,     -- how visible the text stays when it fades (0 = gone)
    fontSize = 14,
    backgroundAlpha = 0.6,
    lock = false,
    reopenAtLogin = true,
    minimapButton = false,
    minimapAngle = 225,
    gameMenuButton = true,
    currentPage = 1,
}

local MAX_PAGES = 12
local MAX_LETTERS = 20000
local MAX_TITLE = 24
local MAX_UNDO = 30
local TYPING_PAUSE = 2      -- seconds without typing before a new undo step starts
local FADE_TIME = 0.2       -- seconds to fade in or out
local FADE_DELAY = 0.6      -- seconds after the mouse leaves before fading out
local PAD = 8               -- the margin around the text; dragging it moves the window
local CONTROL_SIZE = 14
local TAB_HEIGHT = 18
local HEADER = TAB_HEIGHT + 1   -- the row of tabs and controls above the text box
local WHITE = "Interface\\Buttons\\WHITE8x8"

local db
local frame, box, scrollFrame, editBox, thumb, grip
local controls, controlButtons, searchBox, searchResult
local tabBar, tabs, addTab, renameBox = nil, {}, nil, nil
local category
local minimapButton

local function Print(message)
    print("|cffffd100Just a Notepad|r: " .. message)
end

------------------------------------------------------------------------
-- Data and pages
------------------------------------------------------------------------

local function LoadData()
    JustANotepadDB = JustANotepadDB or {}
    JustANotepadDB.settings = JustANotepadDB.settings or {}
    JustANotepadDB.pages = JustANotepadDB.pages or {}
    JustANotepadDB.characterPages = JustANotepadDB.characterPages or {}
    db = JustANotepadDB.settings
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    db.tabSide = nil -- the first build could put the tabs on the bottom or a side
end

-- "Name-Realm". Forever characters also have a surname (UnitName's second value), which is part of the key.
local function CharacterKey()
    local name, surname = UnitName("player")
    if not name or name == "" then return nil end
    if type(surname) == "string" and surname ~= "" then name = name .. " " .. surname end
    return name .. "-" .. (GetRealmName() or "")
end

local function GetPages()
    local list = JustANotepadDB.pages
    local key = db.perCharacter and CharacterKey()
    if key then
        JustANotepadDB.characterPages[key] = JustANotepadDB.characterPages[key] or {}
        list = JustANotepadDB.characterPages[key]
    end
    if #list == 0 then list[1] = { title = "Page 1", text = "" } end
    return list
end

local function IndexOf(page)
    for index, candidate in ipairs(GetPages()) do
        if candidate == page then return index end
    end
end

local function CurrentIndex()
    return math.max(1, math.min(db.currentPage or 1, #GetPages()))
end

local function CurrentPage()
    return GetPages()[CurrentIndex()]
end

local LayoutTabs, UpdateControls -- defined further down

local function ShowPage(index)
    local pages = GetPages()
    db.currentPage = math.max(1, math.min(index, #pages))
    editBox:SetText(pages[db.currentPage].text or "")
    editBox:SetCursorPosition(0)
    scrollFrame:SetVerticalScroll(0)
    LayoutTabs()
end

------------------------------------------------------------------------
-- Undo: typing (one step per burst), inserted text and deleted pages
------------------------------------------------------------------------

local undoStack = {}
local typingStep, lastTypingTime = nil, 0

local function PushUndo(label, undo)
    local step = { label = label, undo = undo }
    undoStack[#undoStack + 1] = step
    if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
    UpdateControls()
    return step
end

local function RestoreText(page, text)
    return function()
        local index = IndexOf(page)
        if not index then return end
        page.text = text
        ShowPage(index)
        editBox:SetCursorPosition(#text)
    end
end

local function RememberTyping(page, before)
    local now = GetTime()
    local top = undoStack[#undoStack]
    local sameBurst = top and top == typingStep and top.page == page and now - lastTypingTime < TYPING_PAUSE
    if not sameBurst then
        typingStep = PushUndo("typing", RestoreText(page, before))
        typingStep.page = page
    end
    lastTypingTime = now
end

local function Undo()
    local step = table.remove(undoStack)
    if not step then return end
    typingStep = nil
    step.undo()
    UpdateControls()
end

-- Text put in by a button or shortcut: saved and undoable like typing.
local function InsertText(text)
    local page = CurrentPage()
    local before = editBox:GetText()
    editBox:SetFocus()
    editBox:Insert(text)
    page.text = editBox:GetText()
    typingStep = nil
    PushUndo("insert", RestoreText(page, before))
end

local function InsertLocation()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo(mapID)
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    local zone = (info and info.name) or GetZoneText() or ""
    if position then
        local x, y = position:GetXY()
        InsertText(string.format("%s (%.1f, %.1f)", zone, x * 100, y * 100))
    else
        InsertText(zone) -- no coordinates indoors
    end
end

------------------------------------------------------------------------
-- Window and fading
------------------------------------------------------------------------

local fade = 1          -- 0 = only the text is left, 1 = everything visible
local lastActive = 0
local holdUntil = 0     -- keeps the window visible while a menu or popup about it is open
local moving = false

local function IsActive()
    if moving or GetTime() < holdUntil then return true end
    if editBox:HasFocus() or searchBox:HasFocus() or renameBox:HasFocus() then return true end
    return frame:IsMouseOver() or (searchBox:IsShown() and searchBox:IsMouseOver())
end

local function ApplyFade()
    box:SetAlpha(fade)
    tabBar:SetAlpha(fade)
    controls:SetAlpha(fade)
    searchBox:SetAlpha(fade)
    grip:SetAlpha(fade)
    thumb:SetAlpha(fade * 0.5)
    if db.fadeText then
        local low = db.fadedTextAlpha or 0
        editBox:SetAlpha(low + (1 - low) * fade)
    else
        editBox:SetAlpha(1)
    end
end

local function OnUpdate(_, elapsed)
    local now = GetTime()
    if IsActive() then lastActive = now end
    local target = (now - lastActive < FADE_DELAY) and 1 or 0
    if fade == target then return end
    local step = elapsed / FADE_TIME
    if target > fade then fade = math.min(1, fade + step) else fade = math.max(0, fade - step) end
    ApplyFade()
end

local function ApplyLook()
    box:SetBackdropColor(0, 0, 0, db.backgroundAlpha)
    box:SetBackdropBorderColor(0.35, 0.35, 0.35, math.min(1, db.backgroundAlpha + 0.3))
    local font, _, flags = ChatFontNormal:GetFont()
    editBox:SetFont(font, db.fontSize, flags)
    ApplyFade()
    LayoutTabs()
end

local function SaveWindow()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
    db.width, db.height = frame:GetSize()
end

local function PlaceWindow()
    frame:ClearAllPoints()
    if db.point and db.x then
        frame:SetPoint(db.point, UIParent, db.relativePoint or db.point, db.x, db.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    frame:SetSize(db.width or 320, db.height or 240)
end

local function ResetWindow()
    db.point, db.relativePoint, db.x, db.y, db.width, db.height = nil, nil, nil, nil, nil, nil
    PlaceWindow()
    frame:Show()
end

local function StartMove()
    if db.lock then return end
    moving = true
    frame:StartMoving()
end

local function StopMove()
    if not moving then return end
    moving = false
    frame:StopMovingOrSizing()
    SaveWindow()
end

local function UpdateThumb()
    local range = scrollFrame:GetVerticalScrollRange() or 0
    local height = scrollFrame:GetHeight() or 0
    if range <= 0.5 or height <= 0 then
        thumb:Hide()
        return
    end
    local size = math.max(16, height * height / (height + range))
    thumb:SetHeight(size)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 5, -(height - size) * (scrollFrame:GetVerticalScroll() / range))
    thumb:Show()
end

local function FocusAtEnd(_, button)
    if button ~= "LeftButton" then return end
    editBox:SetFocus()
    editBox:SetCursorPosition(#editBox:GetText())
end

local SetSearchShown, FindNext -- defined in the search section

local function CreateWindow()
    frame = CreateFrame("Frame", "JustANotepadFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(0, 0, 0, -HEADER) -- keeps room on screen for the search box under the window
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(180, 110, 1000, 800)
    elseif frame.SetMinResize then
        frame:SetMinResize(180, 110)
    end
    frame:EnableMouse(true)
    frame:SetToplevel(true)
    frame:Hide()
    -- Deliberately not in UISpecialFrames: Escape and the game's "close all windows" never close the notepad.

    -- The box: background and thin border, below the header row. It fades; the text (a sibling) doesn't have to.
    box = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    box:SetPoint("TOPLEFT", 0, -HEADER)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })

    -- The margin around the text and the empty part of the header move the window.
    frame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then StartMove() end
    end)
    frame:SetScript("OnMouseUp", StopMove)

    scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", PAD, -(HEADER + PAD))
    scrollFrame:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    scrollFrame:EnableMouse(true)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseDown", FocusAtEnd) -- clicking below the text types at the end
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local target = self:GetVerticalScroll() - delta * db.fontSize * 3
        self:SetVerticalScroll(math.max(0, math.min(range, target)))
    end)

    thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 1)
    thumb:SetWidth(2)
    thumb:Hide()
    scrollFrame:SetScript("OnVerticalScroll", UpdateThumb)
    scrollFrame:SetScript("OnScrollRangeChanged", UpdateThumb)

    editBox = CreateFrame("EditBox", "JustANotepadEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(MAX_LETTERS)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetShadowColor(0, 0, 0, 1) -- keeps the text readable when it floats alone
    editBox:SetShadowOffset(1, -1)
    editBox:SetWidth(200)
    scrollFrame:SetScrollChild(editBox)
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        editBox:SetWidth(width)
        UpdateThumb()
    end)

    local textBefore = ""
    editBox:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        if userInput then
            local page = CurrentPage()
            RememberTyping(page, textBefore)
            page.text = text -- saved as you type
        end
        textBefore = text
    end)
    -- Keeps the cursor in view while typing.
    editBox:SetScript("OnCursorChanged", function(_, _, y, _, cursorHeight)
        local top = -y
        local bottom = top + (cursorHeight or 0)
        local scroll, height = scrollFrame:GetVerticalScroll(), scrollFrame:GetHeight()
        if top < scroll then
            scrollFrame:SetVerticalScroll(math.max(0, top))
        elseif bottom > scroll + height then
            scrollFrame:SetVerticalScroll(bottom - height)
        end
    end)
    -- Escape only ever stops typing.
    editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
    editBox:SetScript("OnKeyDown", function(_, key)
        if not IsControlKeyDown() then return end
        if key == "F" then
            SetSearchShown(true)
        elseif key == "Z" then
            Undo()
        elseif key == "L" then
            InsertLocation()
        end
    end)

    grip = CreateFrame("Button", nil, frame)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function()
        if db.lock then return end
        moving = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", StopMove)

    frame:SetScript("OnSizeChanged", function() LayoutTabs() end)
    frame:SetScript("OnUpdate", OnUpdate)
    frame:SetScript("OnShow", function()
        db.open = true
        lastActive = GetTime() -- visible for a moment when opened, so you can see where it is
        fade = 1
        ApplyFade()
        LayoutTabs()
    end)
    frame:SetScript("OnHide", function()
        db.open = false
        StopMove()
        editBox:ClearFocus()
        SetSearchShown(false)
        renameBox:Hide()
    end)
end

local function Toggle()
    frame:SetShown(not frame:IsShown())
end

------------------------------------------------------------------------
-- Controls: small icons at the right end of the header row, in line with the tabs
------------------------------------------------------------------------

local CONTROL_ORDER = { "Close", "Eye", "Location", "Undo", "Search" } -- right to left

local function CreateControl(texture, tooltip, onClick)
    local button = CreateFrame("Button", nil, controls)
    button:SetSize(CONTROL_SIZE, CONTROL_SIZE)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(texture)
    button.rest = 0.55 -- alpha when the mouse isn't on it
    button.icon:SetAlpha(button.rest)
    button:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(type(tooltip) == "function" and tooltip() or tooltip, 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(self.rest)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(self)
        onClick()
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end -- refresh the tooltip text
    end)
    return button
end

function UpdateControls()
    if not controls then return end
    local anchor, count = nil, 0
    for _, name in ipairs(CONTROL_ORDER) do
        local button = controlButtons[name]
        local shown = db["show" .. name]
        button:SetShown(shown)
        if shown then
            button:ClearAllPoints()
            if anchor then
                button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
            else
                button:SetPoint("RIGHT", controls, "RIGHT", -2, 0)
            end
            anchor = button
            count = count + 1
        end
    end
    controls:SetWidth(math.max(1, count * (CONTROL_SIZE + 4) + 2))
    controls.back:SetShown(count > 0)

    -- The eye is bright while the text stays visible, dim while it fades with the rest.
    local eye = controlButtons.Eye
    eye.rest = db.fadeText and 0.25 or 0.7
    eye.icon:SetDesaturated(db.fadeText)
    if not eye:IsMouseOver() then eye.icon:SetAlpha(eye.rest) end

    local undo = controlButtons.Undo
    undo.rest = (#undoStack > 0) and 0.55 or 0.2
    if not undo:IsMouseOver() then undo.icon:SetAlpha(undo.rest) end

    LayoutTabs() -- the tabs get the room the controls leave
end

local function CreateControls()
    controls = CreateFrame("Frame", nil, frame)
    controls:SetPoint("TOPRIGHT", 0, 0)
    controls:SetHeight(TAB_HEIGHT)
    controls.back = controls:CreateTexture(nil, "BACKGROUND") -- the same shade as an unselected tab
    controls.back:SetAllPoints()

    controlButtons = {
        Close = CreateControl("Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Close (/note opens it again)", function()
            frame:Hide()
        end),
        Eye = CreateControl("Interface\\Icons\\INV_Misc_Eye_01", function()
            if db.fadeText then return "Text fades with the notepad. Click to keep it visible." end
            return "Text stays visible when the notepad fades. Click to let it fade too."
        end, function()
            db.fadeText = not db.fadeText
            UpdateControls()
            ApplyFade()
        end),
        Location = CreateControl("Interface\\Icons\\INV_Misc_Map_01", "Insert your location (Ctrl+L)", InsertLocation),
        Undo = CreateControl("Interface\\Buttons\\UI-RefreshButton", function()
            return (#undoStack > 0) and "Undo (Ctrl+Z)" or "Nothing to undo"
        end, Undo),
        Search = CreateControl("Interface\\Common\\UI-Searchbox-Icon", "Search all pages (Ctrl+F)", function()
            SetSearchShown(not searchBox:IsShown())
        end),
    }
    controlButtons.Eye.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    controlButtons.Location.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

------------------------------------------------------------------------
-- Search all pages: a small box under the bottom-left corner of the window, shown only while searching.
-- Enter finds the next match; Escape closes it.
------------------------------------------------------------------------

function FindNext()
    local query = searchBox:GetText():lower()
    if query == "" then return end
    local pages = GetPages()
    local start = CurrentIndex()
    local from = editBox:GetCursorPosition() + 1
    for step = 0, #pages do -- the last step comes back to the first page searched, from its top
        local index = (start - 1 + step) % #pages + 1
        local first, last = (pages[index].text or ""):lower():find(query, step == 0 and from or 1, true)
        if first then
            if index ~= CurrentIndex() then ShowPage(index) end
            editBox:SetCursorPosition(last)
            editBox:HighlightText(first - 1, last)
            searchResult:SetText("")
            return
        end
    end
    searchResult:SetText("none")
end

function SetSearchShown(shown)
    if not searchBox then return end
    searchBox:SetShown(shown)
    searchResult:SetText("")
    if shown then
        searchBox:SetFocus()
        searchBox:HighlightText()
    else
        searchBox:ClearFocus()
    end
end

local function CreateSearch()
    searchBox = CreateFrame("EditBox", nil, frame)
    searchBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
    searchBox:SetSize(150, TAB_HEIGHT)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(GameFontHighlightSmall)
    searchBox:SetTextInsets(6, 34, 0, 0)
    searchBox:Hide()
    local back = searchBox:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.8)
    searchResult = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchResult:SetPoint("RIGHT", -3, 0)
    searchResult:SetTextColor(1, 0.3, 0.25)
    searchBox:SetScript("OnEnterPressed", FindNext)
    searchBox:SetScript("OnEscapePressed", function() SetSearchShown(false) end)
    searchBox:SetScript("OnTextChanged", function() searchResult:SetText("") end)
end

------------------------------------------------------------------------
-- Page tabs: in the header row above the text box, left of the controls. Right-click for the menu.
------------------------------------------------------------------------

local function AddPage()
    local pages = GetPages()
    if #pages >= MAX_PAGES then
        Print("That's the most pages (" .. MAX_PAGES .. ").")
        return
    end
    pages[#pages + 1] = { title = "Page " .. (#pages + 1), text = "" }
    ShowPage(#pages)
end

local function DeletePage(page)
    local pages = GetPages()
    local index = IndexOf(page)
    if not index then return end
    table.remove(pages, index)
    typingStep = nil
    PushUndo("delete", function()
        local list = GetPages()
        local at = math.min(index, #list + 1)
        table.insert(list, at, page)
        ShowPage(at)
    end)
    ShowPage(math.min(index, #GetPages()))
end

local function MovePage(page, offset)
    local pages = GetPages()
    local index = IndexOf(page)
    local target = index and index + offset
    if not target or target < 1 or target > #pages then return end
    local current = CurrentPage()
    pages[index], pages[target] = pages[target], pages[index]
    db.currentPage = IndexOf(current)
    LayoutTabs()
end

local pendingDelete
StaticPopupDialogs["JUSTANOTEPAD_DELETE"] = {
    text = "Delete the page \"%s\"?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        if pendingDelete then DeletePage(pendingDelete) end
        pendingDelete = nil
    end,
    OnCancel = function() pendingDelete = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function AskToDelete(page)
    if (page.text or "") == "" then
        DeletePage(page) -- nothing to lose
        return
    end
    pendingDelete = page
    holdUntil = GetTime() + 5
    StaticPopup_Show("JUSTANOTEPAD_DELETE", page.title)
end

-- Renaming happens in place, on the tab itself.
local function StartRename(page)
    local tab = tabs[IndexOf(page) or 0]
    if not tab then return end
    renameBox.page = page
    renameBox:ClearAllPoints()
    renameBox:SetAllPoints(tab)
    renameBox:SetText(page.title)
    renameBox:Show()
    renameBox:SetFocus()
    renameBox:HighlightText()
end

local function ShowTabMenu(tab)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local index = tab:GetID()
    local pages = GetPages()
    local page = pages[index]
    local menu = MenuUtil.CreateContextMenu(tab, function(_, root)
        root:CreateTitle(page.title)
        root:CreateButton("Rename", function() StartRename(page) end)
        local back = root:CreateButton("Move Left", function() MovePage(page, -1) end)
        back:SetEnabled(index > 1)
        local forward = root:CreateButton("Move Right", function() MovePage(page, 1) end)
        forward:SetEnabled(index < #pages)
        local delete = root:CreateButton("Delete", function() AskToDelete(page) end)
        delete:SetEnabled(#pages > 1)
    end)
    -- Keep the notepad visible while its menu is open.
    if menu and menu.SetClosedCallback then
        holdUntil = math.huge
        menu:SetClosedCallback(function() holdUntil = GetTime() + FADE_DELAY end)
    else
        holdUntil = GetTime() + 4
    end
end

local function CreateTab()
    local tab = CreateFrame("Button", nil, tabBar)
    tab:SetHeight(TAB_HEIGHT)
    tab.back = tab:CreateTexture(nil, "BACKGROUND")
    tab.back:SetAllPoints()
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tab.text:SetPoint("LEFT", 6, 0)
    tab.text:SetPoint("RIGHT", -6, 0)
    tab.text:SetWordWrap(false)
    tab.text:SetJustifyH("CENTER")
    tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tab:RegisterForDrag("LeftButton") -- dragging a tab moves the window
    tab:SetScript("OnDragStart", StartMove)
    tab:SetScript("OnDragStop", StopMove)
    return tab
end

local function GetTab(index)
    if not tabs[index] then
        local tab = CreateTab()
        tab:SetID(index)
        tab:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                ShowTabMenu(self)
            elseif self:GetID() ~= CurrentIndex() then
                ShowPage(self:GetID())
            end
        end)
        tabs[index] = tab
    end
    return tabs[index]
end

local function StyleTab(tab, selected)
    local alpha = db.backgroundAlpha
    if selected then
        tab.back:SetColorTexture(0, 0, 0, math.min(1, alpha + 0.2))
        tab.text:SetTextColor(1, 1, 1)
    else
        tab.back:SetColorTexture(0, 0, 0, alpha * 0.6)
        tab.text:SetTextColor(0.6, 0.6, 0.6)
    end
end

function LayoutTabs()
    if not tabBar then return end
    local pages = GetPages()
    local count = #pages
    local current = CurrentIndex()
    local addWidth = 20
    local showAdd = count < MAX_PAGES

    -- Room for the tabs: the header's width minus the controls.
    local reserved = controls:GetWidth() + 6
    local available = (frame:GetWidth() or 320) - reserved - (showAdd and addWidth + 1 or 0) - count

    -- Each tab is as wide as its name; when they don't fit, they all shrink evenly.
    local widths, total = {}, 0
    for index, page in ipairs(pages) do
        local tab = GetTab(index)
        tab.text:SetText(page.title)
        widths[index] = math.min(120, math.ceil(tab.text:GetStringWidth() or 40) + 14)
        total = total + widths[index]
    end
    local scale = (total > available and total > 0) and math.max(0, available) / total or 1
    local x = 0
    for index = 1, count do
        local tab = tabs[index]
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", x, 0)
        tab:SetWidth(math.max(12, math.floor(widths[index] * scale)))
        x = x + tab:GetWidth() + 1
    end
    addTab:ClearAllPoints()
    addTab:SetPoint("TOPLEFT", x, 0)
    tabBar:SetSize(math.max(1, x + (showAdd and addWidth or 0)), TAB_HEIGHT)

    for index, tab in ipairs(tabs) do
        tab:SetShown(index <= count)
        if index <= count then StyleTab(tab, index == current) end
    end
    addTab:SetShown(showAdd)
    StyleTab(addTab, false)
    controls.back:SetColorTexture(0, 0, 0, db.backgroundAlpha * 0.6)
end

local function CreateTabs()
    tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", 0, 0)
    tabBar:SetSize(1, TAB_HEIGHT)

    addTab = CreateTab()
    addTab:SetWidth(20)
    addTab.text:SetText("+")
    addTab:SetScript("OnClick", AddPage)
    addTab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("New page", 1, 1, 1)
        GameTooltip:Show()
    end)
    addTab:SetScript("OnLeave", function() GameTooltip:Hide() end)

    renameBox = CreateFrame("EditBox", nil, tabBar)
    renameBox:SetAutoFocus(false)
    renameBox:SetFontObject(GameFontHighlightSmall)
    renameBox:SetMaxLetters(MAX_TITLE)
    renameBox:SetTextInsets(4, 4, 0, 0)
    renameBox:SetFrameLevel(tabBar:GetFrameLevel() + 5)
    renameBox:Hide()
    local back = renameBox:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.1, 0.1, 0.1, 1)
    renameBox:SetScript("OnEnterPressed", function(self)
        local title = strtrim(self:GetText() or "")
        if title ~= "" and self.page then self.page.title = title end
        self:Hide()
        LayoutTabs()
    end)
    renameBox:SetScript("OnEscapePressed", renameBox.Hide)
    renameBox:SetScript("OnEditFocusLost", renameBox.Hide)
end

------------------------------------------------------------------------
-- Launchers: minimap button, Escape-menu button, addon compartment
------------------------------------------------------------------------

local function OpenSettings()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        Print("Settings aren't available on this client. Type /note help for commands.")
    end
end

local function PlaceMinimapButton()
    local angle = math.rad(db.minimapAngle or 225)
    local radius = (Minimap:GetWidth() or 140) / 2 + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
end

local function UpdateMinimapButton()
    if not db.minimapButton then
        if minimapButton then minimapButton:Hide() end
        return
    end
    if not minimapButton then
        minimapButton = CreateFrame("Button", "JustANotepadMinimapButton", Minimap)
        minimapButton:SetSize(32, 32)
        minimapButton:SetFrameLevel(8)
        minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        minimapButton:RegisterForDrag("LeftButton")
        minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER")
        icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local ring = minimapButton:CreateTexture(nil, "OVERLAY")
        ring:SetSize(53, 53)
        ring:SetPoint("TOPLEFT")
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        minimapButton:SetScript("OnClick", function(_, button)
            if button == "RightButton" then OpenSettings() else Toggle() end
        end)
        minimapButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Just a Notepad")
            GameTooltip:AddLine("Left-click: open or close", 1, 1, 1)
            GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
            GameTooltip:Show()
        end)
        minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        minimapButton:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local centerX, centerY = Minimap:GetCenter()
                local cursorX, cursorY = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                db.minimapAngle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
                PlaceMinimapButton()
            end)
        end)
        minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    end
    PlaceMinimapButton()
    minimapButton:Show()
end

local function HookGameMenu()
    if not (GameMenuFrame and GameMenuFrame.InitButtons and GameMenuFrame.AddButton) then return end
    hooksecurefunc(GameMenuFrame, "InitButtons", function(menu)
        if not db.gameMenuButton then return end
        menu:AddButton("Notepad", function()
            HideUIPanel(GameMenuFrame)
            Toggle()
        end)
    end)
end

function JustANotepad_Toggle() Toggle() end -- Bindings.xml

function JustANotepad_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then OpenSettings() else Toggle() end
end

------------------------------------------------------------------------
-- Settings page (Options > AddOns > Just a Notepad)
------------------------------------------------------------------------

local function RegisterOptions()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Just a Notepad")

    local function Register(key, name, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "JustANotepad_" .. key, key, db,
            type(DEFAULTS[key]), name, DEFAULTS[key])
        if onChange then setting:SetValueChangedCallback(onChange) end
        return setting
    end
    -- Each control is built on its own, so one the client lacks doesn't take the others with it.
    local function Try(build)
        local ok, problem = pcall(build)
        if not ok then Print("A setting couldn't be shown (" .. tostring(problem) .. "). /note help lists commands.") end
    end
    local function Header(text)
        Try(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end)
    end
    local function Checkbox(key, name, tooltip, onChange)
        Try(function() Settings.CreateCheckbox(category, Register(key, name, onChange), tooltip) end)
    end
    local function Slider(key, name, tooltip, low, high, step, format, onChange)
        Try(function()
            local options = Settings.CreateSliderOptions(low, high, step)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
            end
            Settings.CreateSlider(category, Register(key, name, onChange), options, tooltip)
        end)
    end
    local function Percent(value) return math.floor(value * 100 + 0.5) .. "%" end

    Header("Pages")
    Checkbox("perCharacter", "Separate Pages per Character",
        "Each character gets their own pages. Off: one set of pages for all characters.",
        function() if frame then ShowPage(1) end end)

    Header("Header Controls")
    Checkbox("showSearch", "Search", "Shows the search control. Ctrl+F works either way.", UpdateControls)
    Checkbox("showUndo", "Undo", "Shows the undo control. Ctrl+Z works either way.", UpdateControls)
    Checkbox("showLocation", "Insert Location", "Shows the location control. Ctrl+L works either way.", UpdateControls)
    Checkbox("showEye", "Text Fade Toggle (Eye)", "Shows the eye control, which switches Fade the Text Too.", UpdateControls)
    Checkbox("showClose", "Close", "Shows the close control. /note and the keybind work either way.", UpdateControls)

    Header("Look")
    Checkbox("fadeText", "Fade the Text Too",
        "When the notepad isn't hovered or focused, the text fades with everything else. Same as the eye control.",
        function() UpdateControls() ApplyFade() end)
    Slider("fadedTextAlpha", "Faded Text Visibility",
        "How visible the text stays when it fades. 0% hides it completely.", 0, 0.9, 0.05, Percent, ApplyFade)
    Slider("backgroundAlpha", "Background", "How solid the box behind the text is.", 0, 1, 0.05, Percent, ApplyLook)
    Slider("fontSize", "Text Size", "The size of the note text.", 8, 28, 1, function(value) return tostring(value) end, ApplyLook)

    Header("Window")
    Checkbox("lock", "Lock Window", "Stops the notepad from being moved or resized.")
    Checkbox("reopenAtLogin", "Reopen at Login", "If the notepad was open when you logged out, it opens again at login.")
    Checkbox("minimapButton", "Minimap Button", "Left-click opens the notepad, right-click opens these settings.",
        UpdateMinimapButton)
    Checkbox("gameMenuButton", "Button in Game Menu", "Adds a Notepad button to the Escape menu.")

    Settings.RegisterAddOnCategory(category)
end

------------------------------------------------------------------------
-- Commands, keybind, events
------------------------------------------------------------------------

BINDING_HEADER_JUSTANOTEPAD = "Just a Notepad"
BINDING_NAME_JUSTANOTEPAD_TOGGLE = "Toggle Notepad"

SLASH_JUSTANOTEPAD1 = "/note"
SLASH_JUSTANOTEPAD2 = "/justanotepad"
SlashCmdList.JUSTANOTEPAD = function(message)
    if not frame then return end
    local command, value = strtrim(message or ""):lower():match("^(%S*)%s*(.-)$")
    if command == "" then
        Toggle()
    elseif command == "settings" or command == "options" or command == "config" then
        OpenSettings()
    elseif command == "reset" then
        ResetWindow()
    elseif command == "size" and tonumber(value) then
        db.fontSize = math.max(8, math.min(28, math.floor(tonumber(value))))
        ApplyLook()
    elseif command == "bg" and tonumber(value) then
        db.backgroundAlpha = math.max(0, math.min(100, tonumber(value))) / 100
        ApplyLook()
    else
        Print("/note opens or closes it. Also: /note settings, /note reset (position and size), "
            .. "/note size 8-28, /note bg 0-100")
    end
end

-- A click anywhere outside the notepad stops typing, so your keys go back to the game.
local function ClearFocusIfClickedOutside()
    if frame:IsShown() and not (frame:IsMouseOver() or (searchBox:IsShown() and searchBox:IsMouseOver())) then
        editBox:ClearFocus()
        searchBox:ClearFocus()
        renameBox:ClearFocus()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GLOBAL_MOUSE_DOWN")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        LoadData()
        local wasOpen = db.open
        CreateWindow()
        CreateControls()
        CreateSearch()
        CreateTabs()
        UpdateControls()
        PlaceWindow()
        ApplyLook()
        ShowPage(CurrentIndex())
        RegisterOptions()
        HookGameMenu()
        UpdateMinimapButton()
        if db.reopenAtLogin and wasOpen then frame:Show() end
        db.open = frame:IsShown()
    elseif event == "GLOBAL_MOUSE_DOWN" and frame then
        C_Timer.After(0, ClearFocusIfClickedOutside) -- next frame, once the click has landed
    end
end)
