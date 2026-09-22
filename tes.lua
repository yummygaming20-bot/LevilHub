local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

-- ============================================================
-- STATE
-- ============================================================

local Settings = {
    AutoScroll = true,
    ShowTimestamp = true,
    ShowFullPath = true,
    MaxHistory = 500,
    DebugMode = false,
}

local DefaultSettings = {
    AutoScroll = true,
    ShowTimestamp = true,
    ShowFullPath = true,
    MaxHistory = 500,
    DebugMode = false,
}

local State = {
    ActiveTab = "ALL",
    SelectedPath = nil,
    SearchQuery = "",
    IsMinimized = false,
    IsClosed = false,
    IsMobile = false,
    ShowingDetail = false,
    Connections = {},
    History = {},
}

-- RemoteRegistry[fullPath] = { Instance, Name, Class, Path, DetectedAt, CallCount, LastTimestamp, LastArgs, LastReturn, Status }
local RemoteRegistry = {}

-- CardRefs[fullPath] = { card, refs... } for each tab
local CardRefs = {}

local HookedInstances = {}
local HookState = {
    Installed = false,
    OldNamecall = nil,
    WrappedInvoke = {},
}

local UI = {
    ScreenGui = nil,
    MainWindow = nil,
    FloatingBtn = nil,
    Header = nil,
    SearchBox = nil,
    ContentArea = nil,
    DetailPanel = nil,
    DetailText = nil,
    DetailScroll = nil,
    DetailSubHeader = nil,
    TabButtons = {},
    TabFrames = {},
    EmptyLabels = {},
    StatusLabel = nil,
    BackBtn = nil,
    CopyNameBtn = nil,
    CopyPathBtn = nil,
    CopyReqBtn = nil,
}

-- ============================================================
-- UTILITY
-- ============================================================

local function DebugLog(...)
    if Settings.DebugMode then
        local ok, msg = pcall(tostring, ...)
        if ok then print("[RemMon]", msg) end
    end
end

local function TrackConnection(conn)
    if conn and typeof(conn) == "RBXScriptConnection" then
        table.insert(State.Connections, conn)
    end
    return conn
end

local function SafeSetClipboard(text)
    for _, fn in ipairs({"setclipboard", "toclipboard", "set_clipboard"}) do
        local f = rawget(_G, fn) or (typeof(getfenv) == "function" and getfenv()[fn])
        if typeof(f) == "function" then
            local ok = pcall(f, text)
            if ok then return true end
        end
    end
    if typeof(Clipboard) == "table" and typeof(Clipboard.set) == "function" then
        local ok = pcall(Clipboard.set, Clipboard, text)
        if ok then return true end
    end
    return false
end

local function GetTimestamp()
    local ok, d = pcall(os.date, "*t")
    if ok and d then
        return string.format("%02d:%02d:%02d", d.hour, d.min, d.sec)
    end
    return "??:??:??"
end

local function GetFullPath(instance)
    if not instance or typeof(instance) ~= "Instance" then return "Unknown" end
    local ok, result = pcall(function() return instance:GetFullName() end)
    if ok then return result end
    return tostring(instance)
end

local function IsDestroyed(instance)
    if typeof(instance) ~= "Instance" then return true end
    local ok = pcall(function() return instance.Parent end)
    return not ok
end

-- ============================================================
-- FORMAT
-- ============================================================

local FormatValue

local function FormatTableRecursive(tbl, indent, depth, visited)
    indent = indent or ""
    depth = depth or 1
    visited = visited or {}
    if depth > 5 then return indent .. "[MAX DEPTH]" end
    if visited[tbl] then return indent .. "[CIRCULAR REF]" end
    visited[tbl] = true
    local keys = {}
    local ok = pcall(function()
        for k in pairs(tbl) do table.insert(keys, k) end
    end)
    if not ok then return indent .. "[TABLE ERROR]" end
    local sorted = pcall(table.sort, keys, function(a, b) return tostring(a) < tostring(b) end)
    local lines = {}
    for i, key in ipairs(keys) do
        local value
        local readOk = pcall(function() value = tbl[key] end)
        if not readOk then value = "[ERROR]" end
        local last = i == #keys
        local branch = last and "└── " or "├── "
        local nextIndent = indent .. (last and "    " or "│   ")
        local keyText = type(key) == "number" and ("[" .. tostring(key) .. "]") or tostring(key)
        if type(value) == "table" then
            table.insert(lines, indent .. branch .. keyText)
            table.insert(lines, FormatTableRecursive(value, nextIndent, depth + 1, visited))
        else
            table.insert(lines, indent .. branch .. keyText .. " = " .. FormatValue(value, nextIndent, depth + 1, visited, true))
        end
    end
    visited[tbl] = nil
    if #lines == 0 then return indent .. "{}" end
    return table.concat(lines, "\n")
end

FormatValue = function(value, indent, depth, visited)
    indent = indent or ""
    depth = depth or 1
    visited = visited or {}
    local t = typeof(value)
    if t == "nil" then return "nil" end
    if t == "string" then return string.format("%q", value) end
    if t == "number" then return tostring(value) end
    if t == "boolean" then return tostring(value) end
    if t == "Instance" then return GetFullPath(value) end
    if t == "Vector2" then return string.format("Vector2(%.3f, %.3f)", value.X, value.Y) end
    if t == "Vector3" then return string.format("Vector3(%.3f, %.3f, %.3f)", value.X, value.Y, value.Z) end
    if t == "CFrame" then local p = value.Position; return string.format("CFrame(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z) end
    if t == "Color3" then return string.format("Color3(%d, %d, %d)", math.floor(value.R*255+0.5), math.floor(value.G*255+0.5), math.floor(value.B*255+0.5)) end
    if t == "BrickColor" then return string.format("BrickColor(%q)", value.Name) end
    if t == "EnumItem" then return tostring(value) end
    if t == "UDim2" then return string.format("UDim2(%.3f,%d, %.3f,%d)", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset) end
    if t == "Ray" then return "Ray(" .. tostring(value.Origin) .. ", " .. tostring(value.Direction) .. ")" end
    if t == "table" then
        return "table\n" .. FormatTableRecursive(value, indent, depth, visited)
    end
    return "[" .. t .. "] " .. tostring(value)
end

local function FormatArgsList(args)
    if not args or #args == 0 then return "(none)" end
    local result = {}
    for i, v in ipairs(args) do
        table.insert(result, string.format("[%d] %s\n  %s", i, typeof(v), FormatValue(v)))
    end
    return table.concat(result, "\n\n")
end

local function ArgPreview(args)
    if not args or #args == 0 then return "no args" end
    local parts = {}
    for i = 1, math.min(3, #args) do
        local v = args[i]
        local s
        if typeof(v) == "string" then
            s = string.format("%q", string.sub(v, 1, 20))
        else
            s = tostring(v)
        end
        table.insert(parts, string.format("[%d]%s", i, s))
    end
    if #args > 3 then table.insert(parts, "...") end
    return table.concat(parts, "  ")
end

-- ============================================================
-- MOBILE DETECTION
-- ============================================================

local function DetectMobile()
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    return viewport.X < 700
end

-- ============================================================
-- BUILD UI
-- ============================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RemoteEventMonitor_v3"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
local ok_parent = pcall(function() ScreenGui.Parent = CoreGui end)
if not ok_parent then
    ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end
UI.ScreenGui = ScreenGui

-- Mobile detection
State.IsMobile = DetectMobile()
local WIN_W = State.IsMobile and 360 or 780
local WIN_H = State.IsMobile and 550 or 500

-- Floating reopen button
local FloatingBtn = Instance.new("TextButton")
FloatingBtn.Name = "FloatingReopenBtn"
FloatingBtn.Size = UDim2.new(0, 130, 0, 40)
FloatingBtn.Position = UDim2.new(0, 12, 0.5, -20)
FloatingBtn.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
FloatingBtn.TextColor3 = Color3.fromRGB(200, 205, 220)
FloatingBtn.Font = Enum.Font.GothamBold
FloatingBtn.TextSize = 11
FloatingBtn.Text = "[ REMOTE MON ]"
FloatingBtn.Visible = false
FloatingBtn.ZIndex = 100
FloatingBtn.AutoButtonColor = false
FloatingBtn.Parent = ScreenGui
UI.FloatingBtn = FloatingBtn

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = FloatingBtn
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(70,75,95); s.Thickness = 1; s.Transparency = 0.3; s.Parent = FloatingBtn
end

-- Main window
local MainWindow = Instance.new("Frame")
MainWindow.Name = "MainWindow"
MainWindow.Size = UDim2.new(0, WIN_W, 0, WIN_H)
MainWindow.Position = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2)
MainWindow.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
MainWindow.BorderSizePixel = 0
MainWindow.ClipsDescendants = true
MainWindow.Parent = ScreenGui
UI.MainWindow = MainWindow

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,11); c.Parent = MainWindow
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(65,69,85); s.Thickness = 1; s.Transparency = 0.35; s.Parent = MainWindow
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(25,27,34)), ColorSequenceKeypoint.new(1, Color3.fromRGB(15,16,20))})
    g.Rotation = 90; g.Parent = MainWindow
end

-- Header
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 44)
Header.BackgroundColor3 = Color3.fromRGB(29, 31, 40)
Header.BorderSizePixel = 0
Header.Parent = MainWindow
UI.Header = Header

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,11); c.Parent = Header
end

local HeaderTitle = Instance.new("TextLabel")
HeaderTitle.Size = UDim2.new(1, -160, 1, 0)
HeaderTitle.Position = UDim2.new(0, 12, 0, 0)
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.Font = Enum.Font.GothamBold
HeaderTitle.TextSize = 13
HeaderTitle.TextColor3 = Color3.fromRGB(245,245,250)
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
HeaderTitle.Text = "● REMOTE MONITOR"
HeaderTitle.Parent = Header

local HeaderStatus = Instance.new("TextLabel")
HeaderStatus.Name = "HeaderStatus"
HeaderStatus.Size = UDim2.new(0, 110, 1, 0)
HeaderStatus.Position = UDim2.new(1, -190, 0, 0)
HeaderStatus.BackgroundTransparency = 1
HeaderStatus.Font = Enum.Font.GothamMedium
HeaderStatus.TextSize = 9
HeaderStatus.TextColor3 = Color3.fromRGB(110, 220, 145)
HeaderStatus.TextXAlignment = Enum.TextXAlignment.Right
HeaderStatus.Text = "MONITOR ACTIVE"
HeaderStatus.Parent = Header
UI.StatusLabel = HeaderStatus

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 26)
CloseBtn.Position = UDim2.new(1, -36, 0, 9)
CloseBtn.BackgroundColor3 = Color3.fromRGB(215, 58, 68)
CloseBtn.TextColor3 = Color3.fromRGB(255,255,255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.Text = "×"
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = Header
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = CloseBtn end

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 28, 0, 26)
MinBtn.Position = UDim2.new(1, -70, 0, 9)
MinBtn.BackgroundColor3 = Color3.fromRGB(47, 50, 62)
MinBtn.TextColor3 = Color3.fromRGB(255,255,255)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 16
MinBtn.Text = "−"
MinBtn.AutoButtonColor = false
MinBtn.Parent = Header
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = MinBtn end

-- Nav tabs
local NavFrame = Instance.new("Frame")
NavFrame.Name = "NavFrame"
NavFrame.Size = UDim2.new(1, -20, 0, 32)
NavFrame.Position = UDim2.new(0, 10, 0, 50)
NavFrame.BackgroundTransparency = 1
NavFrame.Parent = MainWindow

local NavLayout = Instance.new("UIListLayout")
NavLayout.FillDirection = Enum.FillDirection.Horizontal
NavLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
NavLayout.Padding = UDim.new(0, 4)
NavLayout.Parent = NavFrame

-- Search
local SearchBox = Instance.new("TextBox")
SearchBox.Name = "SearchBox"
SearchBox.Size = UDim2.new(1, -20, 0, 30)
SearchBox.Position = UDim2.new(0, 10, 0, 88)
SearchBox.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
SearchBox.TextColor3 = Color3.fromRGB(240,240,245)
SearchBox.PlaceholderColor3 = Color3.fromRGB(120,125,140)
SearchBox.PlaceholderText = "Search name, path, class, args..."
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 11
SearchBox.ClearTextOnFocus = false
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.Parent = MainWindow
UI.SearchBox = SearchBox
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = SearchBox
    local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,10); p.PaddingRight = UDim.new(0,10); p.Parent = SearchBox
end

-- Content area (list pane)
local listW = State.IsMobile and 1 or 0.62
local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(listW, State.IsMobile and 0 or -14, 1, -130)
ContentArea.Position = UDim2.new(0, 10, 0, 125)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainWindow
UI.ContentArea = ContentArea

-- Detail panel
local detailX = State.IsMobile and 0 or 0.62
local detailW = State.IsMobile and 1 or 0.38
local DetailPanel = Instance.new("Frame")
DetailPanel.Name = "DetailPanel"
DetailPanel.Size = UDim2.new(detailW, State.IsMobile and 0 or -4, 1, -130)
DetailPanel.Position = UDim2.new(detailX, State.IsMobile and 0 or 4, 0, 125)
DetailPanel.BackgroundColor3 = Color3.fromRGB(22, 24, 31)
DetailPanel.BorderSizePixel = 0
DetailPanel.Visible = not State.IsMobile
DetailPanel.Parent = MainWindow
UI.DetailPanel = DetailPanel
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = DetailPanel
end

local DetailHeaderLabel = Instance.new("TextLabel")
DetailHeaderLabel.Size = UDim2.new(1, -20, 0, 24)
DetailHeaderLabel.Position = UDim2.new(0, 10, 0, 7)
DetailHeaderLabel.BackgroundTransparency = 1
DetailHeaderLabel.Font = Enum.Font.GothamBold
DetailHeaderLabel.TextSize = 11
DetailHeaderLabel.TextColor3 = Color3.fromRGB(250,250,255)
DetailHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
DetailHeaderLabel.Text = "REMOTE DETAILS"
DetailHeaderLabel.Parent = DetailPanel

local DetailSubHeader = Instance.new("TextLabel")
DetailSubHeader.Name = "DetailSubHeader"
DetailSubHeader.Size = UDim2.new(1, -20, 0, 16)
DetailSubHeader.Position = UDim2.new(0, 10, 0, 28)
DetailSubHeader.BackgroundTransparency = 1
DetailSubHeader.Font = Enum.Font.Gotham
DetailSubHeader.TextSize = 9
DetailSubHeader.TextColor3 = Color3.fromRGB(115, 120, 135)
DetailSubHeader.TextXAlignment = Enum.TextXAlignment.Left
DetailSubHeader.Text = "Select a remote"
DetailSubHeader.Parent = DetailPanel
UI.DetailSubHeader = DetailSubHeader

-- Back button (mobile only)
local BackBtn = Instance.new("TextButton")
BackBtn.Name = "BackBtn"
BackBtn.Size = UDim2.new(0, 70, 0, 22)
BackBtn.Position = UDim2.new(1, -82, 0, 6)
BackBtn.BackgroundColor3 = Color3.fromRGB(40, 43, 56)
BackBtn.TextColor3 = Color3.fromRGB(200, 205, 220)
BackBtn.Font = Enum.Font.GothamBold
BackBtn.TextSize = 10
BackBtn.Text = "◀ BACK"
BackBtn.AutoButtonColor = false
BackBtn.Visible = State.IsMobile
BackBtn.Parent = DetailPanel
UI.BackBtn = BackBtn
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = BackBtn end

local DetailScroll = Instance.new("ScrollingFrame")
DetailScroll.Name = "DetailScroll"
DetailScroll.Size = UDim2.new(1, -10, 1, -100)
DetailScroll.Position = UDim2.new(0, 5, 0, 50)
DetailScroll.BackgroundTransparency = 1
DetailScroll.BorderSizePixel = 0
DetailScroll.ScrollBarThickness = 4
DetailScroll.ScrollBarImageColor3 = Color3.fromRGB(70,74,90)
DetailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
DetailScroll.Parent = DetailPanel
UI.DetailScroll = DetailScroll

local DetailText = Instance.new("TextLabel")
DetailText.Name = "DetailContent"
DetailText.Size = UDim2.new(1, -6, 0, 0)
DetailText.Position = UDim2.new(0, 3, 0, 0)
DetailText.BackgroundTransparency = 1
DetailText.Font = Enum.Font.Gotham
DetailText.TextSize = 10
DetailText.TextColor3 = Color3.fromRGB(210,215,225)
DetailText.TextXAlignment = Enum.TextXAlignment.Left
DetailText.TextYAlignment = Enum.TextYAlignment.Top
DetailText.TextWrapped = true
DetailText.Text = "Select a remote from the list."
DetailText.Parent = DetailScroll
UI.DetailText = DetailText

-- Copy buttons at bottom of detail
local ActionBtnFrame = Instance.new("Frame")
ActionBtnFrame.Size = UDim2.new(1, -10, 0, 30)
ActionBtnFrame.Position = UDim2.new(0, 5, 1, -38)
ActionBtnFrame.BackgroundTransparency = 1
ActionBtnFrame.Parent = DetailPanel

local ActionLayout = Instance.new("UIListLayout")
ActionLayout.FillDirection = Enum.FillDirection.Horizontal
ActionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
ActionLayout.Padding = UDim.new(0, 4)
ActionLayout.Parent = ActionBtnFrame

local function CreateActionBtn(text)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 70, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(38, 41, 53)
    btn.TextColor3 = Color3.fromRGB(210, 215, 230)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.Text = text
    btn.AutoButtonColor = false
    btn.Parent = ActionBtnFrame
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = btn
    return btn
end

local CopyNameBtn = CreateActionBtn("COPY NAME")
local CopyPathBtn = CreateActionBtn("COPY PATH")
local CopyReqBtn  = CreateActionBtn("COPY ARGS")
UI.CopyNameBtn = CopyNameBtn
UI.CopyPathBtn = CopyPathBtn
UI.CopyReqBtn  = CopyReqBtn

local function FlashBtn(btn, success)
    local original = btn.Text
    btn.Text = success and "COPIED!" or "UNAVAIL"
    local col = success and Color3.fromRGB(40,130,70) or Color3.fromRGB(120,45,45)
    btn.BackgroundColor3 = col
    task.delay(1.1, function()
        if btn and btn.Parent then
            btn.Text = original
            btn.BackgroundColor3 = Color3.fromRGB(38, 41, 53)
        end
    end)
end

-- ============================================================
-- CREATE TAB BUTTON + FRAME
-- ============================================================

local TabNames = {"ALL", "REMOTE EVENT", "REMOTE FUNCTION", "HISTORY", "SETTINGS"}

for _, tabName in ipairs(TabNames) do
    local btn = Instance.new("TextButton")
    local isActive = tabName == "ALL"
    btn.Name = "Tab_" .. tabName
    btn.Size = UDim2.new(0, (tabName == "REMOTE FUNCTION" or tabName == "REMOTE EVENT") and 90 or 60, 1, 0)
    btn.BackgroundColor3 = isActive and Color3.fromRGB(49,53,69) or Color3.fromRGB(28,30,38)
    btn.TextColor3 = Color3.fromRGB(230,232,245)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 8
    btn.Text = tabName
    btn.AutoButtonColor = false
    btn.Parent = NavFrame
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = btn end
    UI.TabButtons[tabName] = btn

    local frame = Instance.new("ScrollingFrame")
    frame.Name = "Tab_" .. tabName
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.ScrollBarThickness = 5
    frame.ScrollBarImageColor3 = Color3.fromRGB(65,69,84)
    frame.CanvasSize = UDim2.new(0, 0, 0, 0)
    frame.Visible = isActive
    frame.Parent = ContentArea
    UI.TabFrames[tabName] = frame

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 5)
    layout.Parent = frame

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 4)
    pad.Parent = frame

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        frame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
    end)
end

-- ============================================================
-- EMPTY STATE LABELS
-- ============================================================

local EmptyMessages = {
    ["ALL"]             = "NO REMOTES DETECTED\nWaiting for remote activity...",
    ["REMOTE EVENT"]    = "NO REMOTE EVENTS\nWaiting for RemoteEvent...",
    ["REMOTE FUNCTION"] = "NO REMOTE FUNCTIONS\nWaiting for RemoteFunction...",
    ["HISTORY"]         = "NO ACTIVITY YET\nEvents will appear here.",
    ["SETTINGS"]        = "",
}

for _, tabName in ipairs(TabNames) do
    if tabName == "SETTINGS" then continue end
    local frame = UI.TabFrames[tabName]
    local lbl = Instance.new("TextLabel")
    lbl.Name = "EmptyLabel"
    lbl.Size = UDim2.new(1, -20, 0, 60)
    lbl.Position = UDim2.new(0, 10, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextColor3 = Color3.fromRGB(90, 95, 110)
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.TextWrapped = true
    lbl.Text = EmptyMessages[tabName] or ""
    lbl.Visible = true
    lbl.ZIndex = 2
    lbl.Parent = frame
    UI.EmptyLabels[tabName] = lbl
end

-- ============================================================
-- SETTINGS TAB CONTENT
-- ============================================================

local SettingsFrame = UI.TabFrames["SETTINGS"]

local function MakeToggleRow(parent, label, initial, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 40)
    row.BackgroundColor3 = Color3.fromRGB(26,28,36)
    row.Parent = parent
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = row end

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.7, 0, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextColor3 = Color3.fromRGB(225,228,240)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = label
    lbl.Parent = row

    local tog = Instance.new("TextButton")
    tog.Size = UDim2.new(0, 60, 0, 24)
    tog.Position = UDim2.new(1, -72, 0.5, -12)
    tog.BackgroundColor3 = initial and Color3.fromRGB(50,150,80) or Color3.fromRGB(65,68,80)
    tog.Font = Enum.Font.GothamBold
    tog.TextSize = 10
    tog.TextColor3 = Color3.fromRGB(255,255,255)
    tog.Text = initial and "ON" or "OFF"
    tog.AutoButtonColor = false
    tog.Parent = row
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = tog end

    local cur = initial
    tog.MouseButton1Click:Connect(function()
        cur = not cur
        tog.Text = cur and "ON" or "OFF"
        TweenService:Create(tog, TweenInfo.new(0.15), {BackgroundColor3 = cur and Color3.fromRGB(50,150,80) or Color3.fromRGB(65,68,80)}):Play()
        callback(cur)
    end)

    return {
        Set = function(v)
            cur = v
            tog.Text = v and "ON" or "OFF"
            tog.BackgroundColor3 = v and Color3.fromRGB(50,150,80) or Color3.fromRGB(65,68,80)
        end
    }
end

local ToggleAutoScroll    = MakeToggleRow(SettingsFrame, "Auto Scroll to New Events", Settings.AutoScroll, function(v) Settings.AutoScroll = v end)
local ToggleTimestamp     = MakeToggleRow(SettingsFrame, "Show Timestamps on Cards",  Settings.ShowTimestamp,  function(v) Settings.ShowTimestamp = v end)
local ToggleFullPath      = MakeToggleRow(SettingsFrame, "Show Full Path on Cards",   Settings.ShowFullPath,  function(v) Settings.ShowFullPath = v end)
local ToggleDebug         = MakeToggleRow(SettingsFrame, "Debug Mode",                Settings.DebugMode,     function(v) Settings.DebugMode = v end)

-- Max history row
local MHRow = Instance.new("Frame")
MHRow.Size = UDim2.new(1, -8, 0, 40)
MHRow.BackgroundColor3 = Color3.fromRGB(26,28,36)
MHRow.Parent = SettingsFrame
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = MHRow end

local MHLabel = Instance.new("TextLabel")
MHLabel.Size = UDim2.new(0.65, 0, 1, 0)
MHLabel.Position = UDim2.new(0, 12, 0, 0)
MHLabel.BackgroundTransparency = 1
MHLabel.Font = Enum.Font.Gotham
MHLabel.TextSize = 11
MHLabel.TextColor3 = Color3.fromRGB(225,228,240)
MHLabel.TextXAlignment = Enum.TextXAlignment.Left
MHLabel.Text = "Max History Limit"
MHLabel.Parent = MHRow

local MHInput = Instance.new("TextBox")
MHInput.Size = UDim2.new(0, 72, 0, 24)
MHInput.Position = UDim2.new(1, -84, 0.5, -12)
MHInput.BackgroundColor3 = Color3.fromRGB(38,42,54)
MHInput.TextColor3 = Color3.fromRGB(255,255,255)
MHInput.Font = Enum.Font.GothamBold
MHInput.TextSize = 10
MHInput.Text = tostring(Settings.MaxHistory)
MHInput.ClearTextOnFocus = false
MHInput.Parent = MHRow
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = MHInput end

MHInput.FocusLost:Connect(function()
    local n = tonumber(MHInput.Text)
    if n and n >= 10 and n <= 2000 then
        Settings.MaxHistory = math.floor(n)
    else
        MHInput.Text = tostring(Settings.MaxHistory)
    end
end)

local function MakeSettingsBtn(label, color, fn)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -8, 0, 34)
    btn.BackgroundColor3 = color
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.Text = label
    btn.AutoButtonColor = false
    btn.Parent = SettingsFrame
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = btn end
    btn.MouseButton1Click:Connect(fn)
    return btn
end

-- Status notice in settings
local StatusNotice = Instance.new("TextLabel")
StatusNotice.Name = "StatusNotice"
StatusNotice.Size = UDim2.new(1, -8, 0, 44)
StatusNotice.BackgroundColor3 = Color3.fromRGB(25, 55, 38)
StatusNotice.TextColor3 = Color3.fromRGB(120, 220, 155)
StatusNotice.Font = Enum.Font.GothamMedium
StatusNotice.TextSize = 10
StatusNotice.TextWrapped = true
StatusNotice.Text = "Monitor initializing..."
StatusNotice.Parent = SettingsFrame
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = StatusNotice end

-- ============================================================
-- DETAIL PANEL UPDATE
-- ============================================================

local function UpdateDetailPanel(path)
    State.SelectedPath = path

    if not path then
        UI.DetailSubHeader.Text = "Select a remote"
        UI.DetailText.Text = "Select a remote from the list."
        UI.DetailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        return
    end

    local reg = RemoteRegistry[path]
    if not reg then
        UI.DetailSubHeader.Text = "Remote not found"
        UI.DetailText.Text = "(Data unavailable)"
        return
    end

    UI.DetailSubHeader.Text = reg.Class .. "  •  " .. reg.Name

    local lines = {}
    local function L(s) table.insert(lines, s) end

    L("NAME\n" .. reg.Name)
    L("\nCLASS\n" .. reg.Class)
    L("\nPATH\n" .. reg.Path)
    L("\nSTATUS\n" .. (reg.Status or "DETECTED"))
    L("\nDETECTED AT\n" .. (reg.DetectedAt or "?"))
    L("\nLAST ACTIVITY\n" .. (reg.LastTimestamp or "None"))
    L("\nCALL COUNT\n" .. tostring(reg.CallCount or 0))

    if reg.CallCount and reg.CallCount > 0 then
        L("\n\nLAST ARGS\n\n" .. FormatArgsList(reg.LastArgs or {}))
        if reg.Class == "RemoteFunction" and reg.LastReturn ~= nil then
            L("\n\nLAST RETURN\n\n" .. FormatValue(reg.LastReturn))
        end
    end

    local fullText = table.concat(lines, "")
    UI.DetailText.Text = fullText

    task.defer(function()
        if not UI.DetailScroll or not UI.DetailScroll.Parent then return end
        local w = math.max(100, UI.DetailScroll.AbsoluteSize.X - 12)
        local ok2, bounds = pcall(TextService.GetTextSize, TextService, fullText, 10, Enum.Font.Gotham, Vector2.new(w, 100000))
        if ok2 then
            UI.DetailText.Size = UDim2.new(1, -6, 0, bounds.Y + 10)
            UI.DetailScroll.CanvasSize = UDim2.new(0, 0, 0, bounds.Y + 20)
        end
    end)
end

-- ============================================================
-- CARD MANAGEMENT
-- ============================================================

-- CardRefs[path] = { card, classLabel, timeLabel, pathLabel, argsLabel, stroke }

local function UpdateEmptyState(tabName)
    if tabName == "SETTINGS" then return end
    local lbl = UI.EmptyLabels[tabName]
    if not lbl then return end

    local hasCards = false
    local frame = UI.TabFrames[tabName]
    if frame then
        for _, ch in ipairs(frame:GetChildren()) do
            if ch:IsA("TextButton") then
                hasCards = true
                break
            end
        end
    end
    lbl.Visible = not hasCards
end

local function UpdateStatusBar()
    local total = 0
    local events = 0
    local funcs = 0
    for _, reg in pairs(RemoteRegistry) do
        total += 1
        if reg.Class == "RemoteEvent" then events += 1
        elseif reg.Class == "RemoteFunction" then funcs += 1 end
    end
    if UI.StatusLabel then
        UI.StatusLabel.Text = string.format("Remotes: %d  Events: %d  Funcs: %d", total, events, funcs)
    end
end

local function PassesFilter(reg, query)
    if not query or query == "" then return true end
    query = string.lower(query)
    if string.find(string.lower(reg.Name or ""), query, 1, true) then return true end
    if string.find(string.lower(reg.Path or ""), query, 1, true) then return true end
    if string.find(string.lower(reg.Class or ""), query, 1, true) then return true end
    if reg.LastArgs then
        for _, arg in ipairs(reg.LastArgs) do
            if string.find(string.lower(tostring(arg)), query, 1, true) then return true end
            if string.find(string.lower(typeof(arg)), query, 1, true) then return true end
        end
    end
    return false
end

local function GetCardColor(class)
    if class == "RemoteEvent" then
        return Color3.fromRGB(75, 165, 245)
    else
        return Color3.fromRGB(245, 165, 75)
    end
end

local function GetStatusBadgeColor(status)
    if status == "ACTIVE" then return Color3.fromRGB(50, 180, 100) end
    return Color3.fromRGB(100, 105, 125)
end

local function MakeCardForPath(path, parentFrame)
    local reg = RemoteRegistry[path]
    if not reg then return end

    local card = Instance.new("TextButton")
    card.Name = "Card_" .. path
    card.Size = UDim2.new(1, -6, 0, 76)
    card.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
    card.Text = ""
    card.AutoButtonColor = false
    card.Parent = parentFrame

    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,7); c.Parent = card
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)
        pad.PaddingTop = UDim.new(0,7); pad.PaddingBottom = UDim.new(0,7)
        pad.Parent = card
    end

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(55,59,73)
    stroke.Transparency = 0.6
    stroke.Thickness = 1
    stroke.Parent = card

    -- Class badge
    local classLabel = Instance.new("TextLabel")
    classLabel.Size = UDim2.new(0.55, 0, 0, 14)
    classLabel.BackgroundTransparency = 1
    classLabel.Font = Enum.Font.GothamBold
    classLabel.TextSize = 9
    classLabel.TextXAlignment = Enum.TextXAlignment.Left
    classLabel.TextColor3 = GetCardColor(reg.Class)
    classLabel.Text = reg.Class:upper()
    classLabel.Parent = card

    -- Count badge
    local countLabel = Instance.new("TextLabel")
    countLabel.Name = "CountLabel"
    countLabel.Size = UDim2.new(0.2, 0, 0, 14)
    countLabel.Position = UDim2.new(0.55, 0, 0, 0)
    countLabel.BackgroundTransparency = 1
    countLabel.Font = Enum.Font.GothamBold
    countLabel.TextSize = 9
    countLabel.TextXAlignment = Enum.TextXAlignment.Center
    countLabel.TextColor3 = Color3.fromRGB(200, 175, 90)
    countLabel.Text = reg.CallCount and reg.CallCount > 0 and ("×" .. reg.CallCount) or ""
    countLabel.Parent = card

    -- Time label
    local timeLabel = Instance.new("TextLabel")
    timeLabel.Name = "TimeLabel"
    timeLabel.Size = UDim2.new(0.25, 0, 0, 14)
    timeLabel.Position = UDim2.new(0.75, 0, 0, 0)
    timeLabel.BackgroundTransparency = 1
    timeLabel.Font = Enum.Font.Gotham
    timeLabel.TextSize = 9
    timeLabel.TextXAlignment = Enum.TextXAlignment.Right
    timeLabel.TextColor3 = Color3.fromRGB(115, 120, 135)
    timeLabel.Text = (Settings.ShowTimestamp and reg.LastTimestamp) and reg.LastTimestamp or ""
    timeLabel.Parent = card

    -- Path / name
    local pathLabel = Instance.new("TextLabel")
    pathLabel.Name = "PathLabel"
    pathLabel.Size = UDim2.new(1, 0, 0, 16)
    pathLabel.Position = UDim2.new(0, 0, 0, 17)
    pathLabel.BackgroundTransparency = 1
    pathLabel.Font = Enum.Font.GothamMedium
    pathLabel.TextSize = 10
    pathLabel.TextColor3 = Color3.fromRGB(240,240,245)
    pathLabel.TextXAlignment = Enum.TextXAlignment.Left
    pathLabel.TextTruncate = Enum.TextTruncate.AtEnd
    pathLabel.Text = Settings.ShowFullPath and reg.Path or reg.Name
    pathLabel.Parent = card

    -- Status badge
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(0.3, 0, 0, 14)
    statusLabel.Position = UDim2.new(0, 0, 0, 36)
    statusLabel.BackgroundColor3 = GetStatusBadgeColor(reg.Status)
    statusLabel.BackgroundTransparency = 0.4
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 8
    statusLabel.TextColor3 = Color3.fromRGB(240,245,255)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Center
    statusLabel.Text = reg.Status or "DETECTED"
    statusLabel.Parent = card
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = statusLabel end

    -- Args preview
    local argsLabel = Instance.new("TextLabel")
    argsLabel.Name = "ArgsLabel"
    argsLabel.Size = UDim2.new(1, 0, 0, 20)
    argsLabel.Position = UDim2.new(0, 0, 0, 54)
    argsLabel.BackgroundTransparency = 1
    argsLabel.Font = Enum.Font.Gotham
    argsLabel.TextSize = 9
    argsLabel.TextColor3 = Color3.fromRGB(145, 150, 165)
    argsLabel.TextXAlignment = Enum.TextXAlignment.Left
    argsLabel.TextTruncate = Enum.TextTruncate.AtEnd
    argsLabel.Text = reg.LastArgs and #reg.LastArgs > 0 and ("Args: " .. ArgPreview(reg.LastArgs)) or "Args: (none yet)"
    argsLabel.Parent = card

    -- Hover
    card.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(31,34,44)}):Play()
    end)
    card.MouseLeave:Connect(function()
        if State.SelectedPath ~= path then
            TweenService:Create(card, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(24,26,33)}):Play()
        end
    end)

    card.MouseButton1Click:Connect(function()
        State.SelectedPath = path
        -- highlight
        for _, ch in ipairs(parentFrame:GetChildren()) do
            if ch:IsA("TextButton") then
                local s2 = ch:FindFirstChildOfClass("UIStroke")
                TweenService:Create(ch, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(24,26,33)}):Play()
                if s2 then s2.Color = Color3.fromRGB(55,59,73); s2.Transparency = 0.6 end
            end
        end
        TweenService:Create(card, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(34,37,50)}):Play()
        stroke.Color = Color3.fromRGB(80, 130, 200)
        stroke.Transparency = 0.1

        UpdateDetailPanel(path)

        if State.IsMobile then
            ContentArea.Visible = false
            DetailPanel.Visible = true
            State.ShowingDetail = true
        end
    end)

    return {
        card = card,
        countLabel = countLabel,
        timeLabel = timeLabel,
        pathLabel = pathLabel,
        argsLabel = argsLabel,
        statusLabel = statusLabel,
    }
end

-- CardRefs per tab: CardRefs[tabName][path] = refs
for _, t in ipairs(TabNames) do
    CardRefs[t] = {}
end

local function RefreshCardVisibility(tabName)
    local refs = CardRefs[tabName]
    if not refs then return end
    for path, r in pairs(refs) do
        local reg = RemoteRegistry[path]
        if reg and r.card and r.card.Parent then
            r.card.Visible = PassesFilter(reg, State.SearchQuery)
        end
    end
    UpdateEmptyState(tabName)
end

local function UpdateCardForPath(path)
    local reg = RemoteRegistry[path]
    if not reg then return end

    for _, tabName in ipairs({"ALL", "REMOTE EVENT", "REMOTE FUNCTION"}) do
        local refs = CardRefs[tabName]
        if refs[path] then
            local r = refs[path]
            if r.card and r.card.Parent then
                -- Update labels in-place
                if r.countLabel then
                    r.countLabel.Text = reg.CallCount and reg.CallCount > 0 and ("×" .. reg.CallCount) or ""
                end
                if r.timeLabel then
                    r.timeLabel.Text = (Settings.ShowTimestamp and reg.LastTimestamp) and reg.LastTimestamp or ""
                end
                if r.argsLabel then
                    r.argsLabel.Text = reg.LastArgs and #reg.LastArgs > 0 and ("Args: " .. ArgPreview(reg.LastArgs)) or "Args: (none yet)"
                end
                if r.statusLabel then
                    r.statusLabel.Text = reg.Status or "DETECTED"
                    r.statusLabel.BackgroundColor3 = GetStatusBadgeColor(reg.Status)
                end
                if r.pathLabel then
                    r.pathLabel.Text = Settings.ShowFullPath and reg.Path or reg.Name
                end
            end
        end
    end

    -- Update detail panel if this is selected
    if State.SelectedPath == path then
        UpdateDetailPanel(path)
    end
end

local function AddCardForNewRemote(path)
    local reg = RemoteRegistry[path]
    if not reg then return end

    local classTab = reg.Class == "RemoteEvent" and "REMOTE EVENT" or "REMOTE FUNCTION"
    local targetTabs = {"ALL", classTab}

    for _, tabName in ipairs(targetTabs) do
        if not CardRefs[tabName][path] then
            local frame = UI.TabFrames[tabName]
            if frame then
                local refs = MakeCardForPath(path, frame)
                if refs then
                    CardRefs[tabName][path] = refs
                    refs.card.Visible = PassesFilter(reg, State.SearchQuery)
                end
            end
        end
        UpdateEmptyState(tabName)
    end

    UpdateStatusBar()

    if Settings.AutoScroll and (State.ActiveTab == "ALL" or State.ActiveTab == classTab) then
        local frame = UI.TabFrames[State.ActiveTab]
        if frame then
            task.defer(function()
                local layout = frame:FindFirstChildOfClass("UIListLayout")
                if layout then
                    frame.CanvasPosition = Vector2.new(0, math.max(0, layout.AbsoluteContentSize.Y - frame.AbsoluteSize.Y + 20))
                end
            end)
        end
    end
end

-- ============================================================
-- HISTORY CARDS (separate from registry cards)
-- ============================================================

local function AddHistoryCard(histEntry)
    local frame = UI.TabFrames["HISTORY"]
    if not frame then return end

    local reg = histEntry

    local card = Instance.new("TextButton")
    card.Name = "HistCard"
    card.Size = UDim2.new(1, -6, 0, 60)
    card.BackgroundColor3 = Color3.fromRGB(22, 24, 31)
    card.Text = ""
    card.AutoButtonColor = false
    card.Parent = frame

    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = card
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)
        pad.PaddingTop = UDim.new(0,6); pad.PaddingBottom = UDim.new(0,6)
        pad.Parent = card
    end

    local row1 = Instance.new("TextLabel")
    row1.Size = UDim2.new(0.7, 0, 0, 14)
    row1.BackgroundTransparency = 1
    row1.Font = Enum.Font.GothamBold
    row1.TextSize = 9
    row1.TextXAlignment = Enum.TextXAlignment.Left
    row1.TextColor3 = GetCardColor(histEntry.Class)
    row1.Text = histEntry.Class:upper()
    row1.Parent = card

    local tsLabel = Instance.new("TextLabel")
    tsLabel.Size = UDim2.new(0.3, 0, 0, 14)
    tsLabel.Position = UDim2.new(0.7, 0, 0, 0)
    tsLabel.BackgroundTransparency = 1
    tsLabel.Font = Enum.Font.Gotham
    tsLabel.TextSize = 9
    tsLabel.TextXAlignment = Enum.TextXAlignment.Right
    tsLabel.TextColor3 = Color3.fromRGB(115, 120, 135)
    tsLabel.Text = histEntry.Timestamp or ""
    tsLabel.Parent = card

    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(1, 0, 0, 14)
    nameL.Position = UDim2.new(0, 0, 0, 17)
    nameL.BackgroundTransparency = 1
    nameL.Font = Enum.Font.GothamMedium
    nameL.TextSize = 10
    nameL.TextColor3 = Color3.fromRGB(235,238,245)
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.TextTruncate = Enum.TextTruncate.AtEnd
    nameL.Text = histEntry.Path or histEntry.Name
    nameL.Parent = card

    local argsL = Instance.new("TextLabel")
    argsL.Size = UDim2.new(1, 0, 0, 14)
    argsL.Position = UDim2.new(0, 0, 0, 34)
    argsL.BackgroundTransparency = 1
    argsL.Font = Enum.Font.Gotham
    argsL.TextSize = 9
    argsL.TextColor3 = Color3.fromRGB(140, 145, 160)
    argsL.TextXAlignment = Enum.TextXAlignment.Left
    argsL.TextTruncate = Enum.TextTruncate.AtEnd
    argsL.Text = histEntry.Args and #histEntry.Args > 0 and ArgPreview(histEntry.Args) or "(no args)"
    argsL.Parent = card

    card.Visible = PassesFilter(histEntry, State.SearchQuery)

    card.MouseButton1Click:Connect(function()
        State.SelectedPath = histEntry.Path
        UpdateDetailPanel(histEntry.Path)
        if State.IsMobile then
            ContentArea.Visible = false
            DetailPanel.Visible = true
            State.ShowingDetail = true
        end
    end)

    UpdateEmptyState("HISTORY")

    if Settings.AutoScroll and State.ActiveTab == "HISTORY" then
        task.defer(function()
            local layout = frame:FindFirstChildOfClass("UIListLayout")
            if layout then
                frame.CanvasPosition = Vector2.new(0, math.max(0, layout.AbsoluteContentSize.Y - frame.AbsoluteSize.Y + 20))
            end
        end)
    end

    -- enforce history limit
    local children = {}
    for _, ch in ipairs(frame:GetChildren()) do
        if ch:IsA("TextButton") then
            table.insert(children, ch)
        end
    end
    while #children > Settings.MaxHistory do
        local oldest = table.remove(children, 1)
        if oldest and oldest.Parent then
            pcall(oldest.Destroy, oldest)
        end
    end
end

-- ============================================================
-- RECORD EVENT
-- ============================================================

local function RecordActivity(instance, classType, args, returnValue)
    if not instance then return end

    local path = GetFullPath(instance)
    local reg = RemoteRegistry[path]

    if not reg then
        -- Create registry entry on first activity
        reg = {
            Instance = instance,
            Name = instance.Name,
            Class = classType,
            Path = path,
            DetectedAt = GetTimestamp(),
            CallCount = 0,
            LastTimestamp = nil,
            LastArgs = nil,
            LastReturn = nil,
            Status = "DETECTED",
        }
        RemoteRegistry[path] = reg
        AddCardForNewRemote(path)
    end

    reg.CallCount = (reg.CallCount or 0) + 1
    reg.LastTimestamp = GetTimestamp()
    reg.LastArgs = args or {}
    reg.LastReturn = returnValue
    reg.Status = "ACTIVE"

    UpdateCardForPath(path)

    -- History
    local histEntry = {
        Name = reg.Name,
        Class = classType,
        Path = path,
        Timestamp = reg.LastTimestamp,
        Args = args or {},
        ReturnValue = returnValue,
    }
    table.insert(State.History, histEntry)
    if #State.History > Settings.MaxHistory then
        table.remove(State.History, 1)
    end

    AddHistoryCard(histEntry)
    UpdateStatusBar()
end

local function SafeRecord(instance, classType, args, returnValue)
    if not instance then return end
    task.spawn(function()
        pcall(RecordActivity, instance, classType, args or {}, returnValue)
    end)
end

-- ============================================================
-- HOOK REMOTE INSTANCE
-- ============================================================

local function RegisterRemoteDetected(instance)
    if not instance then return end
    local ok1 = pcall(function()
        if not (instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction")) then
            return
        end
    end)
    if not ok1 then return end

    local path = GetFullPath(instance)
    if RemoteRegistry[path] then return end

    -- Register as DETECTED even before any activity
    local class = "RemoteEvent"
    pcall(function()
        if instance:IsA("RemoteFunction") then class = "RemoteFunction" end
    end)

    RemoteRegistry[path] = {
        Instance = instance,
        Name = instance.Name,
        Class = class,
        Path = path,
        DetectedAt = GetTimestamp(),
        CallCount = 0,
        LastTimestamp = nil,
        LastArgs = nil,
        LastReturn = nil,
        Status = "DETECTED",
    }

    AddCardForNewRemote(path)
    DebugLog("Registered: " .. path)
end

local function HookRemoteInstance(instance)
    if not instance then return end
    if HookedInstances[instance] then return end

    local isRemote = false
    pcall(function()
        isRemote = instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction")
    end)
    if not isRemote then return end

    HookedInstances[instance] = true

    RegisterRemoteDetected(instance)

    local isEvent = false
    pcall(function() isEvent = instance:IsA("RemoteEvent") end)

    if isEvent then
        local ok, conn = pcall(function()
            return instance.OnClientEvent:Connect(function(...)
                SafeRecord(instance, "RemoteEvent", {...}, nil)
            end)
        end)
        if ok and conn then TrackConnection(conn) end
    else
        -- RemoteFunction: try to hook OnClientInvoke safely
        pcall(function()
            if HookState.WrappedInvoke[instance] then return end

            local existingCb = instance.OnClientInvoke
            if typeof(existingCb) ~= "function" then
                -- No existing callback; set a safe passthrough
                HookState.WrappedInvoke[instance] = true
                instance.OnClientInvoke = function(...)
                    local args = {...}
                    SafeRecord(instance, "RemoteFunction", args, nil)
                    -- return nothing (safe default)
                end
            else
                -- Wrap existing callback
                HookState.WrappedInvoke[instance] = true
                instance.OnClientInvoke = function(...)
                    local args = {...}
                    local packed = table.pack(pcall(existingCb, ...))
                    local success = table.remove(packed, 1)
                    packed.n = packed.n - 1

                    local retVal
                    if packed.n == 1 then
                        retVal = packed[1]
                    elseif packed.n > 1 then
                        retVal = {}
                        for i = 1, packed.n do retVal[i] = packed[i] end
                    end

                    SafeRecord(instance, "RemoteFunction", args, success and retVal or nil)

                    if success then
                        return table.unpack(packed, 1, packed.n)
                    end
                end
            end
        end)

        -- Update status note if wrapping not possible
        local path = GetFullPath(instance)
        local reg = RemoteRegistry[path]
        if reg and not HookState.WrappedInvoke[instance] then
            reg.Status = "DETECTED (no hook)"
            UpdateCardForPath(path)
        end
    end
end

-- ============================================================
-- NAMECALL HOOK (outgoing FireServer/InvokeServer)
-- ============================================================

local function InstallNamecallMonitor()
    if HookState.Installed then return true end

    local hasHook = typeof(rawget(_G, "hookmetamethod")) == "function"
    local hasMethod = typeof(rawget(_G, "getnamecallmethod")) == "function"
    if not hasHook or not hasMethod then return false end

    local hmm = rawget(_G, "hookmetamethod")
    local gnm = rawget(_G, "getnamecallmethod")

    local success, old = pcall(hmm, game, "__namecall", function(self, ...)
        local method = gnm()
        local isRemote = false
        pcall(function()
            isRemote = typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction"))
        end)

        if isRemote then
            if method == "FireServer" then
                SafeRecord(self, "RemoteEvent", {...}, nil)
            elseif method == "InvokeServer" then
                local args = {...}
                local packed = table.pack(old(self, ...))
                local retVal
                if packed.n == 1 then retVal = packed[1]
                elseif packed.n > 1 then retVal = {}; for i = 1, packed.n do retVal[i] = packed[i] end
                end
                SafeRecord(self, "RemoteFunction", args, retVal)
                return table.unpack(packed, 1, packed.n)
            end
        end

        return old(self, ...)
    end)

    if not success or not old then return false end

    HookState.OldNamecall = old
    HookState.Installed = true
    return true
end

-- ============================================================
-- SCAN CONTAINERS
-- ============================================================

local function ScanContainer(container)
    if not container then return end
    pcall(function()
        for _, desc in ipairs(container:GetDescendants()) do
            pcall(HookRemoteInstance, desc)
        end

        local conn = container.DescendantAdded:Connect(function(desc)
            pcall(HookRemoteInstance, desc)
        end)
        TrackConnection(conn)
    end)
end

-- ============================================================
-- TAB SWITCHING
-- ============================================================

local function SwitchTab(tabName)
    State.ActiveTab = tabName

    for name, frame in pairs(UI.TabFrames) do
        frame.Visible = (name == tabName)
    end

    for name, btn in pairs(UI.TabButtons) do
        local isActive = (name == tabName)
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = isActive and Color3.fromRGB(49,53,69) or Color3.fromRGB(28,30,38)
        }):Play()
    end

    -- Refresh filter visibility for this tab
    if tabName ~= "SETTINGS" then
        if tabName == "HISTORY" then
            local frame = UI.TabFrames["HISTORY"]
            if frame then
                for _, ch in ipairs(frame:GetChildren()) do
                    if ch:IsA("TextButton") then
                        ch.Visible = true
                    end
                end
            end
            UpdateEmptyState("HISTORY")
        else
            RefreshCardVisibility(tabName)
        end
    end
end

-- ============================================================
-- SEARCH
-- ============================================================

local SearchThread

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    State.SearchQuery = SearchBox.Text
    if SearchThread then pcall(task.cancel, SearchThread) end
    SearchThread = task.delay(0.15, function()
        RefreshCardVisibility(State.ActiveTab)
        -- also refresh history manually
        if State.ActiveTab == "HISTORY" then
            local frame = UI.TabFrames["HISTORY"]
            if frame then
                for _, ch in ipairs(frame:GetChildren()) do
                    if ch:IsA("TextButton") then
                        ch.Visible = true
                    end
                end
            end
        end
    end)
end)

-- ============================================================
-- COPY BUTTONS
-- ============================================================

CopyNameBtn.MouseButton1Click:Connect(function()
    local reg = State.SelectedPath and RemoteRegistry[State.SelectedPath]
    if reg then FlashBtn(CopyNameBtn, SafeSetClipboard(reg.Name))
    else FlashBtn(CopyNameBtn, false) end
end)

CopyPathBtn.MouseButton1Click:Connect(function()
    local reg = State.SelectedPath and RemoteRegistry[State.SelectedPath]
    if reg then FlashBtn(CopyPathBtn, SafeSetClipboard(reg.Path))
    else FlashBtn(CopyPathBtn, false) end
end)

CopyReqBtn.MouseButton1Click:Connect(function()
    local reg = State.SelectedPath and RemoteRegistry[State.SelectedPath]
    if reg then FlashBtn(CopyReqBtn, SafeSetClipboard(FormatArgsList(reg.LastArgs or {})))
    else FlashBtn(CopyReqBtn, false) end
end)

-- ============================================================
-- SETTINGS BUTTONS
-- ============================================================

MakeSettingsBtn("Clear All History", Color3.fromRGB(140,42,50), function()
    table.clear(State.History)
    -- Clear history tab cards
    local frame = UI.TabFrames["HISTORY"]
    if frame then
        for _, ch in ipairs(frame:GetChildren()) do
            if ch:IsA("TextButton") then
                pcall(ch.Destroy, ch)
            end
        end
    end
    UpdateEmptyState("HISTORY")
    UpdateDetailPanel(nil)
end)

MakeSettingsBtn("Clear Current Tab", Color3.fromRGB(120,80,40), function()
    local tab = State.ActiveTab
    if tab == "SETTINGS" or tab == "HISTORY" then
        if tab == "HISTORY" then
            table.clear(State.History)
            local frame = UI.TabFrames["HISTORY"]
            if frame then
                for _, ch in ipairs(frame:GetChildren()) do
                    if ch:IsA("TextButton") then pcall(ch.Destroy, ch) end
                end
            end
            UpdateEmptyState("HISTORY")
        end
        return
    end
    -- Clear cards in this tab and remove from CardRefs
    local refs = CardRefs[tab]
    if refs then
        for path, r in pairs(refs) do
            if r.card and r.card.Parent then pcall(r.card.Destroy, r.card) end
        end
        table.clear(refs)
    end
    UpdateEmptyState(tab)
    UpdateDetailPanel(nil)
end)

MakeSettingsBtn("Reset Settings to Default", Color3.fromRGB(45,50,65), function()
    for k, v in pairs(DefaultSettings) do Settings[k] = v end
    ToggleAutoScroll.Set(Settings.AutoScroll)
    ToggleTimestamp.Set(Settings.ShowTimestamp)
    ToggleFullPath.Set(Settings.ShowFullPath)
    ToggleDebug.Set(Settings.DebugMode)
    MHInput.Text = tostring(Settings.MaxHistory)
end)

-- ============================================================
-- DRAG
-- ============================================================

local isDragging = false
local dragStart, frameStart

Header.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
    and input.UserInputType ~= Enum.UserInputType.Touch then return end

    isDragging = true
    dragStart = input.Position
    frameStart = MainWindow.Position

    local endConn
    endConn = input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            isDragging = false
            if endConn then endConn:Disconnect() end
        end
    end)
end)

TrackConnection(UserInputService.InputChanged:Connect(function(input)
    if not isDragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
    and input.UserInputType ~= Enum.UserInputType.Touch then return end

    local delta = input.Position - dragStart
    local newX = frameStart.X.Offset + delta.X
    local newY = frameStart.Y.Offset + delta.Y

    -- Clamp inside viewport
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    newX = math.clamp(newX, -(WIN_W * 0.5), vp.X - WIN_W * 0.5)
    newY = math.clamp(newY, -(WIN_H * 0.5), vp.Y - WIN_H * 0.5)

    MainWindow.Position = UDim2.new(frameStart.X.Scale, newX, frameStart.Y.Scale, newY)
end))

-- Floating button drag
local floatDragging = false
local floatDragStart, floatPosStart

FloatingBtn.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
    and input.UserInputType ~= Enum.UserInputType.Touch then return end
    floatDragging = true
    floatDragStart = input.Position
    floatPosStart = FloatingBtn.Position

    local endConn
    endConn = input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            floatDragging = false
            if endConn then endConn:Disconnect() end
        end
    end)
end)

TrackConnection(UserInputService.InputChanged:Connect(function(input)
    if not floatDragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
    and input.UserInputType ~= Enum.UserInputType.Touch then return end

    local delta = input.Position - floatDragStart
    FloatingBtn.Position = UDim2.new(
        floatPosStart.X.Scale,
        floatPosStart.X.Offset + delta.X,
        floatPosStart.Y.Scale,
        floatPosStart.Y.Offset + delta.Y
    )
end))

-- ============================================================
-- OPEN / CLOSE / MINIMIZE
-- ============================================================

local OriginalSize = MainWindow.Size

local function AnimateWindowOpen()
    State.IsClosed = false
    FloatingBtn.Visible = false
    MainWindow.Visible = true
    if State.IsMinimized then State.IsMinimized = false end
    MainWindow.Size = UDim2.new(0, OriginalSize.X.Offset * 0.88, 0, OriginalSize.Y.Offset * 0.88)
    MainWindow.BackgroundTransparency = 1
    TweenService:Create(MainWindow, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = OriginalSize,
        BackgroundTransparency = 0
    }):Play()
end

local function AnimateWindowClose()
    State.IsClosed = true
    local tween = TweenService:Create(MainWindow, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        Size = UDim2.new(0, OriginalSize.X.Offset * 0.88, 0, OriginalSize.Y.Offset * 0.88),
        BackgroundTransparency = 1
    })
    tween:Play()
    tween.Completed:Connect(function()
        if State.IsClosed then
            MainWindow.Visible = false
            FloatingBtn.Visible = true
        end
    end)
end

CloseBtn.MouseButton1Click:Connect(AnimateWindowClose)
FloatingBtn.MouseButton1Click:Connect(AnimateWindowOpen)

MinBtn.MouseButton1Click:Connect(function()
    State.IsMinimized = not State.IsMinimized
    local targetH = State.IsMinimized and 44 or OriginalSize.Y.Offset
    TweenService:Create(MainWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, OriginalSize.X.Offset, 0, targetH)
    }):Play()
end)

-- Mobile back button
BackBtn.MouseButton1Click:Connect(function()
    if State.IsMobile then
        DetailPanel.Visible = false
        ContentArea.Visible = true
        State.ShowingDetail = false
        State.SelectedPath = nil
    end
end)

-- Tab buttons
for name, btn in pairs(UI.TabButtons) do
    btn.MouseButton1Click:Connect(function()
        SwitchTab(name)
    end)

    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            TweenService:Create(btn, TweenInfo.new(0.07), {BackgroundTransparency = 0.2}):Play()
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0}):Play()
        end
    end)
end

-- ============================================================
-- CLEANUP
-- ============================================================

local function Cleanup()
    for _, conn in ipairs(State.Connections) do
        if conn and typeof(conn) == "RBXScriptConnection" then
            pcall(conn.Disconnect, conn)
        end
    end
    table.clear(State.Connections)
    table.clear(State.History)
    table.clear(HookedInstances)
    table.clear(HookState.WrappedInvoke)
    table.clear(RemoteRegistry)
    for k in pairs(CardRefs) do table.clear(CardRefs[k]) end
end

ScreenGui.Destroying:Connect(Cleanup)

-- ============================================================
-- INITIALIZE
-- ============================================================

-- Hook namecall first
local hookInstalled = InstallNamecallMonitor()

-- Scan containers
ScanContainer(ReplicatedStorage)

pcall(function()
    ScanContainer(Lighting)
end)

pcall(function()
    if Players.LocalPlayer then
        ScanContainer(Players.LocalPlayer)
    end
end)

-- Update status notice
local statusText = hookInstalled
    and "● MONITOR ACTIVE — FireServer / InvokeServer + OnClientEvent / OnClientInvoke intercepted."
    or  "● PARTIAL MONITOR — Outgoing (FireServer/InvokeServer) not hooked. Incoming events and detected remotes still shown."

StatusNotice.Text = statusText
StatusNotice.BackgroundColor3 = hookInstalled and Color3.fromRGB(22,52,34) or Color3.fromRGB(55,42,18)
StatusNotice.TextColor3 = hookInstalled and Color3.fromRGB(110, 215, 150) or Color3.fromRGB(235, 195, 95)

UpdateStatusBar()
SwitchTab("ALL")
AnimateWindowOpen()
