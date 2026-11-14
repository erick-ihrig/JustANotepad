-- Just a Notepad
-- A text box that floats over the UI. A thin header row above it holds the page tabs (left) and small controls
-- (right). Saves as you type. The box, tabs and controls fade away when the notepad isn't hovered or focused,
-- leaving only the text (or nothing, with the eye toggle).
--
-- Data (JustANotepadDB, account-wide):
--   settings              options (DEFAULTS below), window position and size, whether it was open
--   pages                 pages every character sees
--   characterPages[key]   pages only that character sees
-- A page is { title, blocks }. A block is a stretch of text { text } or a to-do line { todo = true, text, done }.
-- To-dos can sit anywhere between text; a page always ends with a text block, and two text blocks are never
-- neighbours (they're merged).
--
-- Commands: /note (toggle), /note settings, /note reset, /note size N, /note bg N, /note welcome
-- Keybind: Key Bindings > AddOns > Just a Notepad.
-- Sections, in order: data and pages, undo, window and fading, page content (text and to-do blocks), controls,
-- search, tabs, launchers, settings, commands and events.

local ADDON_NAME = ...

local DEFAULTS = {
    showSearch = true,      -- which controls appear
    showUndo = true,
    showTodo = true,
    showEye = true,
    showClose = true,
    fadeText = false,       -- the eye toggle: the text fades with everything else
    keepBorder = false,     -- a faint outline of the box stays when everything else fades
    fadedTextAlpha = 0,     -- how visible the text stays when it fades (0 = gone)
    fontSize = 14,
    backgroundAlpha = 0.6,
    lock = false,
    moveKeysExit = true,    -- holding a movement key while typing leaves the notepad and takes the letters back
    reopenAtLogin = true,
    minimapButton = false,
    minimapAngle = 225,
    gameMenuButton = true,
    currentPage = 1,
}

local MAX_PAGES = 12
local MAX_LETTERS = 20000
local MAX_TODO_LETTERS = 500
local MAX_TITLE = 24
local MAX_UNDO = 30
local TYPING_PAUSE = 2      -- seconds without typing before a new undo step starts
local FADE_TIME = 0.2       -- seconds to fade in or out
local HOLD_TIME = 0.5        -- seconds a movement key is held before it counts as trying to move
local FAINT_BORDER = 0.3     -- how much of the border stays with Keep a Faint Border on
local FADE_DELAY = 0.6      -- seconds after the mouse leaves before fading out
local PAD = 8               -- the margin around the text; dragging it moves the window
local CONTROL_SIZE = 14
local TAB_HEIGHT = 18
local HEADER = TAB_HEIGHT + 1   -- the row of tabs and controls above the text box
local BLOCK_GAP = 2         -- between a to-do line and its neighbours
local TODO_INDENT = 34      -- checkbox, then the delete circle, then the to-do's text
local WHITE = "Interface\\Buttons\\WHITE8x8"

local db
local frame, box, outline, scrollFrame, content, thumb, grip, measure
local controls, controlButtons, searchBar, searchBox, searchResult
local tabBar, tabs, addTab, renameBox = nil, {}, nil, nil
local category
local minimapButton

local function Print(message)
    print("|cffffd100Just a Notepad|r: " .. message)
end

------------------------------------------------------------------------
-- Data and pages
------------------------------------------------------------------------

local function NewPage(title)
    return { title = title, blocks = { { text = "" } } }
end

-- What a new install opens with: how to use and set up the notepad. It's an ordinary page, free to edit or delete.
local function WelcomePage()
    return { title = "Welcome", blocks = {
        { text = "Welcome to Just a Notepad!\n"
            .. "Click anywhere in here and type. Everything saves as you go, and you can delete all of this.\n\n"
            .. "A few things to try:" },
        { todo = true, text = "Tick this box to mark a to-do as done" },
        { todo = true, text = "Hover a to-do and click the red circle to delete it" },
        { todo = true, text = "Add your own with the checkmark button above, or Ctrl+T" },
        { text = "Pages: left-click + to add a page for all your characters, or right-click + for a page only this "
            .. "character sees. Right-click a tab to rename, move, convert or delete it.\n\n"
            .. "Search: the magnifier under the bottom-left corner, or Ctrl+F.\n\n"
            .. "Fading: move the mouse away and click somewhere else, and everything but the text fades out. "
            .. "The eye button makes the text fade too.\n\n"
            .. "Moving: drag a tab, the edge of the box or any empty space in it. Resize from the bottom-right "
            .. "corner.\n\n"
            .. "Settings: type /note settings to choose which buttons show, the text size, the background and more. "
            .. "/note opens and closes the notepad. Escape only stops typing; it never closes it." },
    } }
end

-- Puts a page's blocks in order: text neighbours merged, empty text dropped (except at the end), text at the end.
local function Normalize(page)
    local blocks = {}
    for _, block in ipairs(page.blocks or {}) do
        local last = blocks[#blocks]
        block.text = block.text or ""
        if block.todo then
            blocks[#blocks + 1] = block
        elseif last and not last.todo then
            last.text = last.text .. "\n" .. block.text
        else
            blocks[#blocks + 1] = block
        end
    end
    for index = #blocks - 1, 1, -1 do
        if not blocks[index].todo and blocks[index].text == "" then table.remove(blocks, index) end
    end
    if #blocks == 0 or blocks[#blocks].todo then blocks[#blocks + 1] = { text = "" } end
    page.blocks = blocks
end

local function PrepareList(list)
    for _, page in ipairs(list) do
        if not page.blocks then -- the first builds kept one text field per page
            page.blocks = { { text = page.text or "" } }
            page.text = nil
        end
        Normalize(page)
    end
end

local function LoadData()
    local fresh = JustANotepadDB == nil
    JustANotepadDB = JustANotepadDB or {}
    JustANotepadDB.settings = JustANotepadDB.settings or {}
    JustANotepadDB.pages = JustANotepadDB.pages or {}
    JustANotepadDB.characterPages = JustANotepadDB.characterPages or {}
    db = JustANotepadDB.settings
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    -- Settings from earlier builds that are gone now.
    db.tabSide, db.perCharacter, db.showLocation = nil, nil, nil
    if fresh then JustANotepadDB.pages[1] = WelcomePage() end
    PrepareList(JustANotepadDB.pages)
    for _, list in pairs(JustANotepadDB.characterPages) do PrepareList(list) end
end

-- "Name-Realm". Forever characters also have a surname (UnitName's second value), which is part of the key.
local function CharacterKey()
    local name, surname = UnitName("player")
    if not name or name == "" then return nil end
    if type(surname) == "string" and surname ~= "" then name = name .. " " .. surname end
    return name .. "-" .. (GetRealmName() or "")
end

local function CharacterList(create)
    local key = CharacterKey()
    if not key then return nil end
    if create then JustANotepadDB.characterPages[key] = JustANotepadDB.characterPages[key] or {} end
    return JustANotepadDB.characterPages[key]
end

-- Every page this character sees, in tab order: the account-wide pages, then this character's own.
-- Each entry is { page, list (the saved list the page is in), scope ("account" or "character") }.
local function AllPages()
    local account, character = JustANotepadDB.pages, CharacterList()
    if #account == 0 and not (character and #character > 0) then account[1] = NewPage("Page 1") end
    local all = {}
    for _, page in ipairs(account) do all[#all + 1] = { page = page, list = account, scope = "account" } end
    for _, page in ipairs(character or {}) do all[#all + 1] = { page = page, list = character, scope = "character" } end
    return all
end

local function IndexOf(page)
    for index, entry in ipairs(AllPages()) do
        if entry.page == page then return index end
    end
end

local function CurrentIndex()
    return math.max(1, math.min(db.currentPage or 1, #AllPages()))
end

local function CurrentPage()
    return AllPages()[CurrentIndex()].page
end

local function CopyBlocks(blocks)
    local copy = {}
    for index, block in ipairs(blocks) do
        copy[index] = { text = block.text, todo = block.todo, done = block.done }
    end
    return copy
end

local LayoutTabs, UpdateControls, RenderPage, FocusBlock -- defined further down

local function ShowPage(index)
    db.currentPage = math.max(1, math.min(index, #AllPages()))
    RenderPage()
    scrollFrame:SetVerticalScroll(0)
    LayoutTabs()
end

------------------------------------------------------------------------
-- Undo: typing (one step per burst), to-do changes and deleted pages
------------------------------------------------------------------------

local undoStack = {}
local typingStep, lastTypingTime = nil, 0
local snapshot      -- the open page's blocks as they were before the latest keystroke
local focused       -- the text block or to-do row being typed in

local function PushUndo(undo)
    local step = { undo = undo }
    undoStack[#undoStack + 1] = step
    if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
    UpdateControls()
    return step
end

local function RestoreBlocks(page, blocks)
    return function()
        local index = IndexOf(page)
        if not index then return end
        page.blocks = CopyBlocks(blocks)
        ShowPage(index)
    end
end

-- Call before adding, removing or converting a block, so the change can be undone.
local function RememberPage(page)
    typingStep = nil
    PushUndo(RestoreBlocks(page, CopyBlocks(page.blocks)))
end

local function RememberTyping(page)
    local now = GetTime()
    local top = undoStack[#undoStack]
    local sameBurst = top and top == typingStep and top.page == page and now - lastTypingTime < TYPING_PAUSE
    if not sameBurst then
        typingStep = PushUndo(RestoreBlocks(page, snapshot or page.blocks))
        typingStep.page = page
    end
    lastTypingTime = now
end

local function Undo()
    local step = table.remove(undoStack)
    if not step then return end
    -- Typing carries on from the same block afterwards, so Ctrl+Z can be pressed again.
    local position
    if focused then
        for index, block in ipairs(CurrentPage().blocks) do
            if block == focused.block then position = index end
        end
    end
    typingStep = nil
    step.undo()
    UpdateControls()
    if position then
        local blocks = CurrentPage().blocks
        local block = blocks[math.min(position, #blocks)]
        FocusBlock(block, #block.text)
    end
end

------------------------------------------------------------------------
-- Window and fading
------------------------------------------------------------------------

local fade = 1          -- 0 = only the text is left, 1 = everything visible
local lastActive = 0
local holdUntil = 0     -- keeps the window visible while a menu or popup about it is open
local moving = false

-- The mouse is on the window, or on the search icon or box that hang under its bottom-left corner.
local function IsHovered()
    return frame:IsMouseOver() or (searchBar:IsShown() and searchBar:IsMouseOver())
        or (searchBox:IsShown() and searchBox:IsMouseOver())
end

local function IsActive()
    if moving or GetTime() < holdUntil then return true end
    if focused or searchBox:HasFocus() or renameBox:HasFocus() then return true end
    return IsHovered()
end

local function ApplyFade()
    box:SetAlpha(fade)
    outline:SetAlpha(db.keepBorder and (FAINT_BORDER + (1 - FAINT_BORDER) * fade) or fade)
    tabBar:SetAlpha(fade)
    controls:SetAlpha(fade)
    searchBar:SetAlpha(fade)
    searchBox:SetAlpha(fade)
    grip:SetAlpha(fade)
    thumb:SetAlpha(fade * 0.5)
    if db.fadeText then
        local low = db.fadedTextAlpha or 0
        content:SetAlpha(low + (1 - low) * fade)
    else
        content:SetAlpha(1)
    end
end

local CheckCursor, CheckHeldKey -- defined with the page content

local function OnUpdate(_, elapsed)
    CheckCursor()
    CheckHeldKey()
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
    -- With the faint border kept, it has to be solid enough to still show at a fraction of itself.
    local edge = math.min(1, db.backgroundAlpha + 0.3)
    outline:SetBackdropBorderColor(0.35, 0.35, 0.35, db.keepBorder and math.max(0.8, edge) or edge)
    RenderPage() -- the text size
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

local SetSearchShown, FindNext, AddTodo, ResizeBlocks, OpenMenu -- defined further down

local function CreateWindow()
    frame = CreateFrame("Frame", "JustANotepadFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(0, 0, 0, -HEADER) -- keeps room on screen for the search icon and box under the window
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
    box:SetBackdrop({ bgFile = WHITE })
    -- The border is its own frame, so it can stay faintly visible when the background has faded out.
    outline = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    outline:SetAllPoints(box)
    outline:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })

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
    -- Empty space in the page (below the text, around a to-do's checkbox): a click types at the end of the page,
    -- click-and-hold drags the window. Done by watching the mouse while the button is down, not with
    -- RegisterForDrag: that also takes drags that start on the text inside, which stops text selection.
    local dragged = false
    scrollFrame:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        dragged = false
        local startX, startY = GetCursorPosition()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            if math.abs(x - startX) + math.abs(y - startY) > 6 then
                dragged = true
                self:SetScript("OnUpdate", nil)
                StartMove()
            end
        end)
    end)
    scrollFrame:SetScript("OnMouseUp", function(self, button)
        self:SetScript("OnUpdate", nil)
        StopMove()
        if button ~= "LeftButton" or dragged then return end
        local blocks = CurrentPage().blocks
        FocusBlock(blocks[#blocks], #blocks[#blocks].text)
    end)
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

    -- The page: its text blocks and to-do rows are stacked inside this.
    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(200, 1)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function() ResizeBlocks() end)
    measure = content:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall") -- measures to-do text, never shown
    measure:Hide()

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
        if focused then focused.edit:ClearFocus() end
        SetSearchShown(false)
        renameBox:Hide()
    end)
end

local function Toggle()
    frame:SetShown(not frame:IsShown())
end

------------------------------------------------------------------------
-- Page content: text blocks (multi-line edit boxes) and to-do rows, stacked top to bottom
------------------------------------------------------------------------

local textPool, todoPool, active = {}, {}, {}   -- spare widgets, and the ones showing the open page
local fontFile, fontFlags
local searchWidget  -- the edit box showing the latest search match

local function BlockIndex(page, block)
    for index, candidate in ipairs(page.blocks) do
        if candidate == block then return index end
    end
end

local function WidgetFor(block)
    for _, widget in ipairs(active) do
        if widget.block == block then return widget end
    end
end

function FocusBlock(block, cursor)
    local widget = block and WidgetFor(block)
    if not widget then return end
    widget.edit:SetFocus()
    widget.edit:SetCursorPosition(cursor or 0)
end

-- Keeps the page's height (and so the scroll range) in step with its blocks.
local sizing = false
local function Relayout()
    if sizing then return end
    sizing = true
    local total = 0
    for index, widget in ipairs(active) do
        -- An empty block still needs a line to click on and type in. A to-do row is as tall as its (wrapped) text.
        local edit = widget.edit
        if (edit:GetHeight() or 0) < db.fontSize then edit:SetHeight(db.fontSize + 2) end
        if widget.isTodo then widget:SetHeight(edit:GetHeight()) end
        total = total + (widget:GetHeight() or 0) + (index > 1 and BLOCK_GAP or 0)
    end
    content:SetHeight(math.max(1, total))
    sizing = false
    UpdateThumb()
end

-- The width of each line a to-do's text wraps into, worked out word by word the way the game wraps it.
local function LineWidths(text, maxWidth)
    local widths, line = {}, ""
    local function Close()
        measure:SetText((line:gsub("%s+$", "")))
        widths[#widths + 1] = math.min(measure:GetStringWidth() or 0, maxWidth)
    end
    for word, space in text:gmatch("(%S+)(%s*)") do
        measure:SetText(line .. word)
        if line ~= "" and (measure:GetStringWidth() or 0) > maxWidth then
            Close()
            line = word .. space
        else
            line = line .. word .. space
        end
    end
    if line ~= "" then Close() end
    return widths
end

-- Ticked to-dos are grey with a line through each line of their text.
local function UpdateTodoLook(row)
    local block = row.block
    if not block then return end
    row.mark:SetShown(block.done and true or false)
    local shade = block.done and 0.5 or 1
    row.edit:SetTextColor(shade, shade, shade)
    local widths = {}
    if block.done and block.text ~= "" then
        measure:SetFont(fontFile, db.fontSize, fontFlags)
        widths = LineWidths(block.text, row.textWidth or 100)
    end
    local height = row.edit:GetHeight() or 0
    local lineHeight = (#widths > 0 and height >= db.fontSize) and height / #widths or db.fontSize + 2
    for index, width in ipairs(widths) do
        local strike = row.strikes[index]
        if not strike then
            strike = row.edit:CreateTexture(nil, "OVERLAY")
            strike:SetColorTexture(0.6, 0.6, 0.6, 1)
            strike:SetHeight(1)
            row.strikes[index] = strike
        end
        strike:ClearAllPoints()
        strike:SetPoint("TOPLEFT", 0, -math.floor((index - 0.5) * lineHeight))
        strike:SetWidth(math.max(1, width))
        strike:Show()
    end
    for index = #widths + 1, #row.strikes do row.strikes[index]:Hide() end
end

-- How far down the page a block starts, from the blocks above it.
local function OffsetInPage(widget)
    local offset = 0
    for index, candidate in ipairs(active) do
        if candidate == widget then return offset + (index > 1 and BLOCK_GAP or 0) end
        offset = offset + (candidate:GetHeight() or 0) + (index > 1 and BLOCK_GAP or 0)
    end
    return offset
end

-- Scrolls only when the line being typed on (or just found) is outside the box, and only far enough to bring
-- it back in: typing past the bottom moves the page up one line. Never scrolls past the end of the page.
-- `top` and `bottom` are measured from the page's top.
local function KeepInView(top, bottom)
    local height = scrollFrame:GetHeight() or 0
    local range = math.max(0, (content:GetHeight() or 0) - height)
    local scroll = scrollFrame:GetVerticalScroll() or 0
    local target = scroll
    if bottom > scroll + height then target = bottom - height end
    if top < target then target = top end
    target = math.max(0, math.min(range, target))
    if math.abs(target - scroll) > 0.5 then scrollFrame:SetVerticalScroll(target) end
end

-- The cursor moved: noted here and looked at on the next frame, once the text has taken its new height.
local cursorMoved
function CheckCursor()
    local moved = cursorMoved
    if not moved then return end
    cursorMoved = nil
    if not moved.widget.block then return end
    Relayout()
    local top = OffsetInPage(moved.widget) - moved.y
    KeepInView(top, top + moved.height)
end

-- Removes the block at `index` and joins the text around it. Returns the block and cursor position to type at next.
local function RemoveBlock(page, index)
    local blocks = page.blocks
    local before, after = blocks[index - 1], blocks[index + 1]
    table.remove(blocks, index)
    if before and not before.todo and after and not after.todo then
        local cursor = #before.text + 1
        before.text = before.text .. "\n" .. after.text
        table.remove(blocks, index)
        return before, cursor
    elseif after and not after.todo then
        return after, 0
    elseif before and not before.todo then
        before.text = before.text .. "\n" -- a new line under the text above, before the next to-do
        return before, #before.text
    end
    table.insert(blocks, index, { text = "" })
    return blocks[index], 0
end

local function DeleteTodo(block)
    local page = CurrentPage()
    local index = BlockIndex(page, block)
    if not index then return end
    RememberPage(page)
    table.remove(page.blocks, index)
    Normalize(page)
    RenderPage()
end

-- Adds a to-do line: under the line being typed on (splitting the text there), under the to-do being typed in,
-- or at the end of the page.
function AddTodo()
    local page = CurrentPage()
    local blocks = page.blocks
    local todo = { todo = true, text = "" }
    local index = focused and BlockIndex(page, focused.block)
    RememberPage(page)
    if index and blocks[index].todo then
        table.insert(blocks, index + 1, todo)
    elseif index then
        local text = blocks[index].text
        local lineEnd = text:find("\n", focused.edit:GetCursorPosition() + 1, true)
        local above = lineEnd and text:sub(1, lineEnd - 1) or text
        local below = lineEnd and text:sub(lineEnd + 1) or ""
        if above:sub(-1) == "\n" then above = above:sub(1, -2) end -- typing on an empty line: the to-do takes its place
        blocks[index].text = above
        table.insert(blocks, index + 1, todo)
        table.insert(blocks, index + 2, { text = below })
    else
        table.insert(blocks, #blocks + 1, todo)
    end
    Normalize(page)
    RenderPage()
    FocusBlock(todo, 0)
end

-- Enter in a to-do: a new to-do under it. Enter in an empty to-do: back to ordinary text.
local function TodoEnter(row)
    local page = CurrentPage()
    local index = BlockIndex(page, row.block)
    if not index then return end
    RememberPage(page)
    if row.block.text == "" then
        local block, cursor = RemoveBlock(page, index)
        RenderPage()
        FocusBlock(block, cursor)
    else
        local todo = { todo = true, text = "" }
        table.insert(page.blocks, index + 1, todo)
        RenderPage()
        FocusBlock(todo, 0)
    end
end

-- Up and Down step from one block to the next at a block's first and last position.
local function StepFocus(widget, key)
    local page = CurrentPage()
    local index = BlockIndex(page, widget.block)
    if not index then return end
    local edit = widget.edit
    local cursor = edit:GetCursorPosition()
    if key == "UP" and cursor == 0 and page.blocks[index - 1] then
        FocusBlock(page.blocks[index - 1], #page.blocks[index - 1].text)
    elseif key == "DOWN" and cursor >= #edit:GetText() and page.blocks[index + 1] then
        FocusBlock(page.blocks[index + 1], 0)
    end
end

-- Scripts every block's edit box shares. `widget` is the text block itself, or the to-do row around the edit box.
-- Holding a movement key while typing means you're trying to move, not write "wwwwww". The page is noted as it
-- was when the key went down; if the key is still down after HOLD_TIME (or has already repeated), the page is
-- put back (the held letters go, and any selected text they replaced comes back) and typing stops. The key
-- has to be released and pressed again to move: the game ignores a key that was already down, and addons
-- can't start movement.
local MOVE_COMMANDS = { "MOVEFORWARD", "MOVEBACKWARD", "STRAFELEFT", "STRAFERIGHT", "TURNLEFT", "TURNRIGHT" }
local MOVE_DEFAULTS = { W = true, A = true, S = true, D = true, Q = true, E = true }
local heldKey

-- Letter keys bound to movement (arrow keys are left alone: in a text box they move the cursor).
local function IsMovementKey(key)
    if #key ~= 1 or not key:find("%a") then return false end
    if not GetBindingKey then return MOVE_DEFAULTS[key] or false end
    for _, command in ipairs(MOVE_COMMANDS) do
        local first, second = GetBindingKey(command)
        if first == key or second == key then return true end
    end
    return false
end

local function WatchMovementKey(widget, key)
    if not db.moveKeysExit or not IsKeyDown then return end
    if heldKey and heldKey.key == key then return end -- the same press, repeating
    heldKey = nil
    if IsAltKeyDown and IsAltKeyDown() then return end
    if not IsMovementKey(key) then return end
    local page = CurrentPage()
    heldKey = { key = key, at = GetTime(), widget = widget, page = page, blocks = CopyBlocks(page.blocks),
        undo = #undoStack, count = 0 }
end

function CheckHeldKey()
    local held = heldKey
    if not held then return end
    if not IsKeyDown(held.key) or focused ~= held.widget then
        heldKey = nil -- released, or typing moved elsewhere: it was ordinary typing
        return
    end
    if GetTime() - held.at < HOLD_TIME and held.count < 3 then return end
    heldKey = nil
    if held.page ~= CurrentPage() then return end
    held.page.blocks = held.blocks
    for _ = held.undo + 1, #undoStack do table.remove(undoStack) end -- the held letters aren't an undo step
    typingStep = nil
    RenderPage() -- shows the page as it was, and stops typing
    UpdateControls()
end

-- What's highlighted in an edit box, as (start, length) in its text, or nil. The game has no call for this, so
-- the selection is found by letting a marker replace it for a moment and comparing; the text, cursor and
-- highlight are put back straight away.
local MARKER = "<<@jan@>>"
local probing = false

local function GetSelection(edit)
    local before = edit:GetText()
    local cursor = edit:GetCursorPosition()
    probing = true
    edit:Insert(MARKER)
    local after = edit:GetText()
    edit:SetText(before)
    edit:SetCursorPosition(cursor)
    probing = false
    local length = #before - (#after - #MARKER)
    if length <= 0 then return nil end
    local from = 1
    while true do
        local at = after:find(MARKER, from, true)
        if not at then return nil end
        local start = at - 1
        if before:sub(1, start) == after:sub(1, start) and before:sub(start + length + 1) == after:sub(at + #MARKER) then
            edit:HighlightText(start, start + length)
            return start, length
        end
        from = at + 1
    end
end

-- Turns the highlighted part of a text block into to-dos: one for each line that was ended with Enter
-- (lines the box only wrapped stay together). The text before and after stays where it was.
local function ConvertSelection(widget, start, length)
    local page = CurrentPage()
    local index = BlockIndex(page, widget.block)
    if not index or widget.block.todo then return end
    local text = widget.block.text
    local above, picked, below = text:sub(1, start), text:sub(start + 1, start + length), text:sub(start + length + 1)
    local todos = {}
    for line in (picked .. "\n"):gmatch("(.-)\n") do
        line = strtrim(line)
        if line ~= "" then todos[#todos + 1] = { todo = true, text = line } end
    end
    if #todos == 0 then return end
    RememberPage(page)
    if above:sub(-1) == "\n" then above = above:sub(1, -2) end
    if below:sub(1, 1) == "\n" then below = below:sub(2) end
    widget.block.text = above
    for offset, todo in ipairs(todos) do table.insert(page.blocks, index + offset, todo) end
    table.insert(page.blocks, index + #todos + 1, { text = below })
    Normalize(page)
    RenderPage()
end

local enterAt = 0 -- when Enter was last handled in a to-do, so one key press isn't handled twice

local function SetUpEdit(edit, widget)
    widget.edit = edit
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetShadowColor(0, 0, 0, 1) -- keeps the text readable when it floats alone
    edit:SetShadowOffset(1, -1)
    edit:SetScript("OnTextChanged", function(self, userInput)
        local block = widget.block
        if not block or probing then return end
        if userInput then
            local page = CurrentPage()
            local text = self:GetText()
            RememberTyping(page)
            if block.todo and text:find("\n", 1, true) then
                -- A to-do is one paragraph. A single new line is the Enter key; pasted lines are joined.
                local _, count = text:gsub("\n", "")
                block.text = (text:gsub("%s*\n%s*", count == 1 and "" or " "))
                snapshot = CopyBlocks(page.blocks)
                if count == 1 and GetTime() - enterAt > 0.05 then
                    enterAt = GetTime()
                    TodoEnter(widget)
                else
                    self:SetText(block.text)
                end
                return
            end
            block.text = text -- saved as you type
            snapshot = CopyBlocks(page.blocks)
        end
        if block.todo then UpdateTodoLook(widget) end
        Relayout()
    end)
    -- Keeps the line being typed on (or a search match) in view (CheckCursor).
    edit:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
        if self ~= (focused and focused.edit) and self ~= searchWidget then return end
        cursorMoved = { widget = widget, y = y or 0, height = cursorHeight or 0 }
    end)
    edit:SetScript("OnEscapePressed", edit.ClearFocus) -- Escape only ever stops typing
    edit:SetScript("OnEditFocusGained", function()
        focused = widget
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if focused == widget then focused = nil end
        self:HighlightText(0, 0) -- clicking away (or Escape) also drops any selection
    end)
    edit:SetScript("OnChar", function(_, char)
        if heldKey and char:upper() == heldKey.key then heldKey.count = heldKey.count + 1 end
    end)
    edit:SetScript("OnKeyDown", function(_, key)
        if not IsControlKeyDown() then
            WatchMovementKey(widget, key)
            return
        end
        if key == "F" then
            SetSearchShown(true)
        elseif key == "Z" then
            Undo()
        elseif key == "T" then
            AddTodo()
        end
    end)
    if edit:HasScript("OnArrowPressed") then
        edit:SetScript("OnArrowPressed", function(_, key) StepFocus(widget, key) end)
    end
end

local function CreateTextBlock()
    local edit = CreateFrame("EditBox", nil, content)
    edit:SetMaxLetters(MAX_LETTERS)
    SetUpEdit(edit, edit)
    edit:SetScript("OnSizeChanged", Relayout)
    -- Right-click with text highlighted: a menu to turn it into to-dos.
    edit:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" or not self.block then return end
        local start, length = GetSelection(self)
        if not start then return end
        OpenMenu(self, function(_, root)
            root:CreateButton("Convert into to-do", function() ConvertSelection(self, start, length) end)
        end)
    end)
    return edit
end

local function CreateTodoRow()
    local row = CreateFrame("Frame", nil, content)
    row.isTodo = true
    row.strikes = {}

    -- The checkbox: a small dark square with a thin edge, and a check mark when ticked.
    local check = CreateFrame("Button", nil, row)
    check:SetSize(13, 13)
    row.check = check -- placed beside the first line of text when the page is drawn
    local edge = check:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.6, 0.6, 0.6, 0.9)
    local inside = check:CreateTexture(nil, "BORDER")
    inside:SetPoint("TOPLEFT", 1, -1)
    inside:SetPoint("BOTTOMRIGHT", -1, 1)
    inside:SetColorTexture(0, 0, 0, 0.9)
    row.mark = check:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("CENTER")
    row.mark:SetSize(18, 18)
    row.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetScript("OnClick", function()
        if not row.block then return end
        RememberPage(CurrentPage())
        row.block.done = not row.block.done or nil
        snapshot = CopyBlocks(CurrentPage().blocks)
        UpdateTodoLook(row)
    end)

    -- The delete circle: shows next to the checkbox while the mouse is on the row.
    local delete = CreateFrame("Button", nil, row)
    delete:SetSize(13, 13)
    delete:SetPoint("LEFT", check, "RIGHT", 3, 0)
    delete:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    delete:SetAlpha(0)
    delete:SetScript("OnClick", function()
        if row.block then DeleteTodo(row.block) end
    end)
    row:SetScript("OnUpdate", function(self)
        delete:SetAlpha(self:IsMouseOver() and 1 or 0)
    end)

    -- The text wraps inside its own indented column, so every line starts where the first one does.
    local edit = CreateFrame("EditBox", nil, row)
    edit:SetPoint("TOPLEFT", TODO_INDENT, 0)
    edit:SetMaxLetters(MAX_TODO_LETTERS)
    SetUpEdit(edit, row)
    edit:SetScript("OnEnterPressed", function()
        if GetTime() - enterAt <= 0.05 then return end
        enterAt = GetTime()
        TodoEnter(row)
    end)
    edit:SetScript("OnSizeChanged", function()
        UpdateTodoLook(row) -- the strike lines follow the wrapping
        Relayout()
    end)
    return row
end

-- Rebuilds the open page from its blocks. Only for opening a page and for adding or removing blocks: typing
-- never comes through here (it would take the cursor away).
function RenderPage()
    if not content then return end
    local page = CurrentPage()
    for _, widget in ipairs(active) do
        widget.block = nil
        widget.edit:ClearFocus()
        widget:Hide()
        local pool = widget.isTodo and todoPool or textPool
        pool[#pool + 1] = widget
    end
    active = {}
    searchWidget = nil

    local _
    fontFile, _, fontFlags = ChatFontNormal:GetFont()
    local width = math.max(40, scrollFrame:GetWidth() or 200)
    content:SetWidth(width)
    local above
    for _, block in ipairs(page.blocks) do
        local widget
        if block.todo then
            widget = table.remove(todoPool) or CreateTodoRow()
            widget.textWidth = width - TODO_INDENT
            widget.edit:SetWidth(widget.textWidth)
            widget.check:ClearAllPoints()
            widget.check:SetPoint("TOPLEFT", 1, -math.max(0, math.floor((db.fontSize - 11) / 2)))
        else
            widget = table.remove(textPool) or CreateTextBlock()
        end
        widget.block = block
        widget:ClearAllPoints()
        if above then
            widget:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -BLOCK_GAP)
        else
            widget:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        end
        widget:SetWidth(width)
        widget.edit:SetFont(fontFile, db.fontSize, fontFlags)
        widget.edit:SetTextColor(1, 1, 1)
        widget:Show()
        active[#active + 1] = widget
        widget.edit:SetText(block.text)
        widget.edit:SetCursorPosition(0)
        if block.todo then UpdateTodoLook(widget) end
        above = widget
    end
    snapshot = CopyBlocks(page.blocks)
    Relayout()
end

-- The window was resized: the blocks follow its width.
function ResizeBlocks()
    if not content then return end
    local width = math.max(40, scrollFrame:GetWidth() or 200)
    content:SetWidth(width)
    for _, widget in ipairs(active) do
        widget:SetWidth(width)
        if widget.isTodo then
            widget.textWidth = width - TODO_INDENT
            widget.edit:SetWidth(widget.textWidth)
            UpdateTodoLook(widget)
        end
    end
    Relayout()
end

------------------------------------------------------------------------
-- Controls: small icons at the right end of the header row, in line with the tabs.
-- The search icon sits on its own under the bottom-left corner of the window.
------------------------------------------------------------------------

local CONTROL_ORDER = { "Close", "Eye", "Todo", "Undo" } -- right to left

local function CreateControl(texture, tooltip, onClick, parent)
    local button = CreateFrame("Button", nil, parent or controls)
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

    -- The search box pops out to the right of the search icon (or sits in its place when the icon is hidden).
    searchBar:SetShown(db.showSearch)
    searchBox:ClearAllPoints()
    if db.showSearch then
        searchBox:SetPoint("LEFT", searchBar, "RIGHT", 1, 0)
    else
        searchBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
    end

    LayoutTabs() -- the tabs get the room the controls leave
end

local function CreateControls()
    controls = CreateFrame("Frame", nil, frame)
    controls:SetPoint("TOPRIGHT", 0, 0)
    controls:SetHeight(TAB_HEIGHT)
    controls.back = controls:CreateTexture(nil, "BACKGROUND") -- the same shade as an unselected tab
    controls.back:SetAllPoints()

    searchBar = CreateFrame("Frame", nil, frame)
    searchBar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
    searchBar:SetSize(TAB_HEIGHT, TAB_HEIGHT)
    searchBar.back = searchBar:CreateTexture(nil, "BACKGROUND")
    searchBar.back:SetAllPoints()

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
        Todo = CreateControl("Interface\\Buttons\\UI-CheckBox-Check", "Add a to-do line (Ctrl+T)", function() AddTodo() end),
        Undo = CreateControl("Interface\\Buttons\\UI-RefreshButton", function()
            return (#undoStack > 0) and "Undo (Ctrl+Z)" or "Nothing to undo"
        end, Undo),
        Search = CreateControl("Interface\\Common\\UI-Searchbox-Icon", "Search all pages (Ctrl+F)", function()
            SetSearchShown(not searchBox:IsShown())
        end, searchBar),
    }
    controlButtons.Search:SetPoint("CENTER")
    controlButtons.Eye.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

------------------------------------------------------------------------
-- Search all pages: the search icon sits under the bottom-left corner of the window; the box pops out to its right.
-- Enter finds the next match; Escape closes it.
------------------------------------------------------------------------

local searchAt -- where the latest match ended: { page, block, position }

function FindNext()
    local query = searchBox:GetText():lower()
    if query == "" then return end
    local all = AllPages()
    local start = CurrentIndex()
    local startBlock, startPosition = 1, 1
    if searchAt and searchAt.page == all[start].page then
        startBlock = BlockIndex(searchAt.page, searchAt.block) or 1
        startPosition = searchAt.position + 1
    end
    if searchWidget then searchWidget:HighlightText(0, 0) end
    for step = 0, #all do -- the last step comes back to the first page searched, from its top
        local index = (start - 1 + step) % #all + 1
        local page = all[index].page
        for blockIndex = (step == 0 and startBlock or 1), #page.blocks do
            local block = page.blocks[blockIndex]
            local from = (step == 0 and blockIndex == startBlock) and startPosition or 1
            local first, last = block.text:lower():find(query, from, true)
            if first then
                if index ~= CurrentIndex() then ShowPage(index) end
                searchAt = { page = page, block = block, position = last }
                local widget = WidgetFor(block)
                if widget then
                    searchWidget = widget.edit
                    widget.edit:SetCursorPosition(last)
                    widget.edit:HighlightText(first - 1, last)
                end
                searchResult:SetText("")
                return
            end
        end
    end
    searchAt = nil
    searchResult:SetText("none")
end

function SetSearchShown(shown)
    if not searchBox then return end
    searchBox:SetShown(shown)
    searchResult:SetText("")
    searchAt = nil
    if shown then
        searchBox:SetFocus()
        searchBox:HighlightText()
    else
        searchBox:ClearFocus()
        if searchWidget then searchWidget:HighlightText(0, 0) end
    end
end

local function CreateSearch()
    searchBox = CreateFrame("EditBox", nil, frame)
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
    searchBox:SetScript("OnTextChanged", function(_, userInput)
        searchResult:SetText("")
        if userInput then searchAt = nil end
    end)
end

------------------------------------------------------------------------
-- Page tabs: in the header row above the text box, left of the controls. Account-wide pages come first, then
-- this character's own (tinted in the class color). Right-click a tab for its menu.
------------------------------------------------------------------------

local function CharacterName()
    return UnitName("player") or "this character"
end

local function CharacterColor()
    local class = UnitClass and select(2, UnitClass("player"))
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
    return 0.55, 0.8, 1
end

local function AddPage(scope)
    if #AllPages() >= MAX_PAGES then
        Print("That's the most pages (" .. MAX_PAGES .. ").")
        return
    end
    local list = scope == "character" and CharacterList(true) or JustANotepadDB.pages
    local page = NewPage("Page " .. (#list + 1))
    list[#list + 1] = page
    ShowPage(IndexOf(page))
end

local function DeletePage(page)
    local index = IndexOf(page)
    local all = AllPages()
    if not index or #all <= 1 then return end
    local list = all[index].list
    local position
    for at, candidate in ipairs(list) do
        if candidate == page then position = at end
    end
    table.remove(list, position)
    typingStep = nil
    PushUndo(function()
        table.insert(list, math.min(position, #list + 1), page)
        ShowPage(IndexOf(page) or 1)
    end)
    ShowPage(math.min(index, #AllPages()))
end

-- Switches a page between "all characters" and "this character only". It goes to the end of its new group.
local function ConvertPage(page)
    local all = AllPages()
    local index = IndexOf(page)
    if not index then return end
    local from = all[index].list
    local to = all[index].scope == "character" and JustANotepadDB.pages or CharacterList(true)
    if not to then return end
    local current = CurrentPage()
    for at, candidate in ipairs(from) do
        if candidate == page then table.remove(from, at) break end
    end
    to[#to + 1] = page
    db.currentPage = IndexOf(current) or 1
    LayoutTabs()
end

-- Whether a page can move one place left or right: only among the pages of its own kind.
local function CanMove(page, offset)
    local all = AllPages()
    local index = IndexOf(page)
    local target = index and all[index + offset]
    return target ~= nil and target.list == all[index].list, index, all
end

local function MovePage(page, offset)
    local ok, index, all = CanMove(page, offset)
    if not ok then return end
    local current = CurrentPage()
    local list, other = all[index].list, all[index + offset].page
    for at, candidate in ipairs(list) do
        if candidate == page then list[at] = other elseif candidate == other then list[at] = page end
    end
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

local function IsEmpty(page)
    for _, block in ipairs(page.blocks) do
        if block.todo or block.text ~= "" then return false end
    end
    return true
end

local function AskToDelete(page)
    if IsEmpty(page) then
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

-- Opens a menu on `owner` and keeps the notepad visible while it's open.
function OpenMenu(owner, build)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
    local menu = MenuUtil.CreateContextMenu(owner, build)
    if menu and menu.SetClosedCallback then
        holdUntil = math.huge
        menu:SetClosedCallback(function() holdUntil = GetTime() + FADE_DELAY end)
    else
        holdUntil = GetTime() + 4
    end
    return true
end

local function ShowTabMenu(tab)
    local all = AllPages()
    local entry = all[tab:GetID()]
    if not entry then return end
    local page = entry.page
    OpenMenu(tab, function(_, root)
        root:CreateTitle(page.title .. (entry.scope == "character" and (" (" .. CharacterName() .. " only)")
            or " (all characters)"))
        root:CreateButton("Rename", function() StartRename(page) end)
        local back = root:CreateButton("Move Left", function() MovePage(page, -1) end)
        back:SetEnabled((CanMove(page, -1)))
        local forward = root:CreateButton("Move Right", function() MovePage(page, 1) end)
        forward:SetEnabled((CanMove(page, 1)))
        root:CreateButton(entry.scope == "character" and "Make It for All Characters"
            or ("Make It for " .. CharacterName() .. " Only"), function() ConvertPage(page) end)
        local delete = root:CreateButton("Delete", function() AskToDelete(page) end)
        delete:SetEnabled(#all > 1)
    end)
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

local function StyleTab(tab, selected, scope)
    local alpha = db.backgroundAlpha
    local r, g, b = 1, 1, 1
    if scope == "character" then r, g, b = CharacterColor() end
    if selected then
        tab.back:SetColorTexture(0, 0, 0, math.min(1, alpha + 0.2))
        tab.text:SetTextColor(r, g, b)
    else
        tab.back:SetColorTexture(0, 0, 0, alpha * 0.6)
        tab.text:SetTextColor(r * 0.6, g * 0.6, b * 0.6)
    end
end

function LayoutTabs()
    if not tabBar then return end
    local all = AllPages()
    local count = #all
    local current = CurrentIndex()
    local addWidth = 20
    local showAdd = count < MAX_PAGES

    -- Room for the tabs: the header's width minus the controls.
    local reserved = controls:GetWidth() + 6
    local available = (frame:GetWidth() or 320) - reserved - (showAdd and addWidth + 1 or 0) - count

    -- Each tab is as wide as its name; when they don't fit, they all shrink evenly.
    local widths, total = {}, 0
    for index, entry in ipairs(all) do
        local tab = GetTab(index)
        tab.text:SetText(entry.page.title)
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
        if index <= count then StyleTab(tab, index == current, all[index].scope) end
    end
    addTab:SetShown(showAdd)
    StyleTab(addTab, false)
    controls.back:SetColorTexture(0, 0, 0, db.backgroundAlpha * 0.6)
    searchBar.back:SetColorTexture(0, 0, 0, db.backgroundAlpha * 0.6)
end

local function CreateTabs()
    tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", 0, 0)
    tabBar:SetSize(1, TAB_HEIGHT)

    addTab = CreateTab()
    addTab:SetWidth(20)
    addTab.text:SetText("+")
    -- Left-click: a page for all characters. Right-click: a page for this character only.
    addTab:SetScript("OnClick", function(_, button)
        AddPage(button == "RightButton" and "character" or "account")
    end)
    addTab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("New page")
        GameTooltip:AddLine("Left-click: for all characters", 1, 1, 1)
        GameTooltip:AddLine("Right-click: for " .. CharacterName() .. " only", 1, 1, 1)
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

    Header("Controls")
    Checkbox("showTodo", "Add To-Do", "Shows the control that adds a to-do line. Ctrl+T works either way.", UpdateControls)
    Checkbox("showUndo", "Undo", "Shows the undo control. Ctrl+Z works either way.", UpdateControls)
    Checkbox("showEye", "Text Fade Toggle (Eye)", "Shows the eye control, which switches Fade the Text Too.", UpdateControls)
    Checkbox("showClose", "Close", "Shows the close control. /note and the keybind work either way.", UpdateControls)
    Checkbox("showSearch", "Search", "Shows the search control under the bottom-left corner. Ctrl+F works either way.",
        UpdateControls)

    Header("Look")
    Checkbox("fadeText", "Fade the Text Too",
        "When the notepad isn't hovered or focused, the text fades with everything else. Same as the eye control.",
        function() UpdateControls() ApplyFade() end)
    Checkbox("keepBorder", "Keep a Faint Border",
        "When the notepad fades, a faint outline of the box stays so you can see where it is and how big it is.",
        ApplyLook)
    Slider("fadedTextAlpha", "Faded Text Visibility",
        "How visible the text stays when it fades. 0% hides it completely.", 0, 0.9, 0.05, Percent, ApplyFade)
    Slider("backgroundAlpha", "Background", "How solid the box behind the text is.", 0, 1, 0.05, Percent, ApplyLook)
    Slider("fontSize", "Text Size", "The size of the note text.", 8, 28, 1, function(value) return tostring(value) end,
        ApplyLook)

    Header("Window")
    Checkbox("lock", "Lock Window", "Stops the notepad from being moved or resized.")
    Checkbox("moveKeysExit", "Movement Keys Leave the Notepad",
        "Holding a movement key (such as W, A, S or D) while typing stops typing and takes back the letters it typed. "
        .. "Release the key and press it again to move. Tapping the keys still types as normal.")
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
    elseif command == "welcome" then
        if #AllPages() >= MAX_PAGES then
            Print("That's the most pages (" .. MAX_PAGES .. "). Delete one to see the welcome page again.")
            return
        end
        local page = WelcomePage()
        table.insert(JustANotepadDB.pages, page)
        frame:Show()
        ShowPage(IndexOf(page))
    else
        Print("/note opens or closes it. Also: /note settings, /note reset (position and size), "
            .. "/note size 8-28, /note bg 0-100, /note welcome (adds the welcome page again)")
    end
end

-- A click anywhere outside the notepad stops typing, so your keys go back to the game.
local function ClearFocusIfClickedOutside()
    if frame:IsShown() and not IsHovered() then
        if focused then focused.edit:ClearFocus() end
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
