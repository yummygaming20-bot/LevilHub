--[[
    Remote Event Monitor & Logger GUI
    Target Environment: Roblox Executor (CoreGui & getconnections API)
    Mode: Read-Only / Passive Debugger & Argument Inspector
    Author: DX-Mark-0.2
--]]

-- ============================================================================
-- 1. SERVICES
-- ============================================================================
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

-- ============================================================================
-- 2. VARIABLES & STATE
-- ============================================================================
local Connections = {}
local HistoryData = {}
local RemoteStats = {}
local ActiveTab = "ALL"
local CurrentDetail = nil
local SearchQuery = ""

local SettingsState = {
    AutoScroll = true,
    ShowTimestamp = true,
    ShowFullPath = true,
    MaxHistory = 500
}

local UIReferences = {
    Cards = {},
    TabButtons = {},
    TabFrames = {},
    CardsByTab = {
        ["ALL"] = {},
        ["REMOTE EVENT"] = {},
        ["REMOTE FUNCTION"] = {},
        ["HISTORY"] = {}
    }
}

-- ============================================================================
-- 3. EXECUTOR API DETECTION
-- ============================================================================
local HasGetConnections = (typeof(getconnections) == "function")
local HasClipboard = (typeof(setclipboard) == "function") or (typeof(toclipboard) == "function")

local function SafeSetClipboard(text)
    pcall(function()
        if typeof(setclipboard) == "function" then
            setclipboard(text)
        elseif typeof(toclipboard) == "function" then
            toclipboard(text)
        end
    end)
end

-- ============================================================================
-- 4. UTILITY FUNCTIONS
-- ============================================================================
local function GetCurrentTimestamp()
    local date = os.date("*t")
    return string.format("%02d:%02d:%02d", date.hour, date.min, date.sec)
end

local function GetInstanceFullPath(instance)
    if not instance or typeof(instance) ~= "Instance" then
        return "Unknown"
    end
    local success, result = pcall(function()
        return instance:GetFullName()
    end)
    return success and result or tostring(instance)
end

-- ============================================================================
-- 5. ARGUMENT FORMATTER (RECURSIVE TREE)
-- ============================================================================
local FormatValue
local function FormatTableRecursive(tbl, indent, depth, visited)
    if depth > 5 then
        return indent .. "[Depth Limit Reached]"
    end
    if visited[tbl] then
        return indent .. "[Circular Reference]"
    end
    visited[tbl] = true

    local lines = {}
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    local total = #keys
    for i, k in ipairs(keys) do
        local v = tbl[k]
        local isLast = (i == total)
        local branch = isLast and "└── " or "├── "
        local nextIndent = indent .. (isLast and "    " or "│   ")
        local keyStr = tostring(k)
        if type(k) == "number" then
            keyStr = "[" .. keyStr .. "]"
        end

        if type(v) == "table" then
            table.insert(lines, indent .. branch .. keyStr)
            table.insert(lines, FormatTableRecursive(v, nextIndent, depth + 1, visited))
        else
            table.insert(lines, indent .. branch .. keyStr .. " = " .. FormatValue(v, nextIndent, depth + 1, visited, true))
        end
    end
    visited[tbl] = nil
    return table.concat(lines, "\n")
end

FormatValue = function(val, indent, depth, visited, skipTableRoot)
    indent = indent or ""
    depth = depth or 1
    visited = visited or {}
    local vType = typeof(val)

    if vType == "string" then
        return string.format("%q", val)
    elseif vType == "number" or vType == "boolean" or vType == "nil" then
        return tostring(val)
    elseif vType == "Instance" then
        return GetInstanceFullPath(val)
    elseif vType == "Vector2" then
        return string.format("Vector2.new(%.2f, %.2f)", val.X, val.Y)
    elseif vType == "Vector3" then
        return string.format("Vector3.new(%.2f, %.2f, %.2f)", val.X, val.Y, val.Z)
    elseif vType == "CFrame" then
        local x, y, z = val.Position.X, val.Position.Y, val.Position.Z
        return string.format("CFrame.new(%.2f, %.2f, %.2f)", x, y, z)
    elseif vType == "Color3" then
        return string.format("Color3.fromRGB(%d, %d, %d)", math.floor(val.R * 255), math.floor(val.G * 255), math.floor(val.B * 255))
    elseif vType == "BrickColor" then
        return string.format("BrickColor.new(%q)", val.Name)
    elseif vType == "EnumItem" then
        return tostring(val)
    elseif vType == "UDim2" then
        return string.format("UDim2.new(%.2f, %d, %.2f, %d)", val.X.Scale, val.X.Offset, val.Y.Scale, val.Y.Offset)
    elseif vType == "Ray" then
        return string.format("Ray.new(%s, %s)", tostring(val.Origin), tostring(val.Direction))
    elseif vType == "table" then
        if skipTableRoot then
            return "Table\n" .. FormatTableRecursive(val, indent, depth, visited)
        else
            return "Table\n" .. FormatTableRecursive(val, indent, depth, visited)
        end
    else
        return string.format("[%s: %s]", vType, tostring(val))
    end
end

local function FormatArgumentsList(args)
    if not args or #args == 0 then
        return "None"
    end
    local lines = {}
    for i, arg in ipairs(args) do
        local t = typeof(arg)
        local formatted = FormatValue(arg)
        table.insert(lines, string.format("[%d]\nType: %s\nValue: %s", i, t, formatted))
    end
    return table.concat(lines, "\n\n")
end

-- ============================================================================
-- 6. GUI CREATION
-- ============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RemoteEventMonitor"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = CoreGui

-- Floating Reopen Button
local FloatingButton = Instance.new("TextButton")
FloatingButton.Name = "FloatingOpenButton"
FloatingButton.Size = UDim2.new(0, 110, 0, 36)
FloatingButton.Position = UDim2.new(0, 20, 0.5, -18)
FloatingButton.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
FloatingButton.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatingButton.Font = Enum.Font.GothamBold
FloatingButton.TextSize = 13
FloatingButton.Text = "[ REMOTE ]"
FloatingButton.Visible = false
FloatingButton.ZIndex = 100
FloatingButton.Parent = ScreenGui

local FloatingCorner = Instance.new("UICorner")
FloatingCorner.CornerRadius = UDim.new(0, 8)
FloatingCorner.Parent = FloatingButton

local FloatingGrad = Instance.new("UIGradient")
FloatingGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 38, 48)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 24, 28))
})
FloatingGrad.Rotation = 90
FloatingGrad.Parent = FloatingButton

-- Main Window
local MainWindow = Instance.new("Frame")
MainWindow.Name = "MainWindow"
MainWindow.Size = UDim2.new(0, 720, 0, 460)
MainWindow.Position = UDim2.new(0.5, -360, 0.5, -230)
MainWindow.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
MainWindow.BorderSizePixel = 0
MainWindow.ClipsDescendants = true
MainWindow.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainWindow

local MainGrad = Instance.new("UIGradient")
MainGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 26, 32)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 16, 20))
})
MainGrad.Rotation = 45
MainGrad.Parent = MainWindow

-- Header
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 42)
Header.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
Header.BorderSizePixel = 0
Header.Parent = MainWindow

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, -120, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextColor3 = Color3.fromRGB(240, 240, 240)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "REMOTE EVENT MONITOR"
Title.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseButton"
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0, 7)
CloseBtn.BackgroundColor3 = Color3.fromRGB(235, 75, 75)
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.Text = "X"
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

local MinBtn = Instance.new("TextButton")
MinBtn.Name = "MinButton"
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -68, 0, 7)
MinBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 14
MinBtn.Text = "-"
MinBtn.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinBtn

-- Navigation Tabs
local NavFrame = Instance.new("Frame")
NavFrame.Name = "Navigation"
NavFrame.Size = UDim2.new(1, -20, 0, 36)
NavFrame.Position = UDim2.new(0, 10, 0, 48)
NavFrame.BackgroundTransparency = 1
NavFrame.Parent = MainWindow

local NavLayout = Instance.new("UIListLayout")
NavLayout.FillDirection = Enum.FillDirection.Horizontal
NavLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
NavLayout.Padding = UDim.new(0, 6)
NavLayout.Parent = NavFrame

-- Search Bar
local SearchBox = Instance.new("TextBox")
SearchBox.Name = "SearchBox"
SearchBox.Size = UDim2.new(1, -20, 0, 32)
SearchBox.Position = UDim2.new(0, 10, 0, 88)
SearchBox.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
SearchBox.TextColor3 = Color3.fromRGB(240, 240, 240)
SearchBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
SearchBox.PlaceholderText = "Search by Name, Path, Class, or Argument..."
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 12
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = MainWindow

local SearchCorner = Instance.new("UICorner")
SearchCorner.CornerRadius = UDim.new(0, 6)
SearchCorner.Parent = SearchBox

local SearchPadding = Instance.new("UIPadding")
SearchPadding.PaddingLeft = UDim.new(0, 10)
SearchPadding.PaddingRight = UDim.new(0, 10)
SearchPadding.Parent = SearchBox

-- Content Container
local ContentContainer = Instance.new("Frame")
ContentContainer.Name = "ContentContainer"
ContentContainer.Size = UDim2.new(1, -270, 1, -130)
ContentContainer.Position = UDim2.new(0, 10, 0, 124)
ContentContainer.BackgroundTransparency = 1
ContentContainer.Parent = MainWindow

-- Details Side Panel
local DetailPanel = Instance.new("Frame")
DetailPanel.Name = "DetailPanel"
DetailPanel.Size = UDim2.new(0, 240, 1, -130)
DetailPanel.Position = UDim2.new(1, -250, 0, 124)
DetailPanel.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
DetailPanel.BorderSizePixel = 0
DetailPanel.Parent = MainWindow

local DetailCorner = Instance.new("UICorner")
DetailCorner.CornerRadius = UDim.new(0, 8)
DetailCorner.Parent = DetailPanel

local DetailTitle = Instance.new("TextLabel")
DetailTitle.Name = "DetailTitle"
DetailTitle.Size = UDim2.new(1, -16, 0, 28)
DetailTitle.Position = UDim2.new(0, 8, 0, 4)
DetailTitle.BackgroundTransparency = 1
DetailTitle.Font = Enum.Font.GothamBold
DetailTitle.TextSize = 12
DetailTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
DetailTitle.TextXAlignment = Enum.TextXAlignment.Left
DetailTitle.Text = "REMOTE DETAILS"
DetailTitle.Parent = DetailPanel

local DetailScroll = Instance.new("ScrollingFrame")
DetailScroll.Name = "DetailScroll"
DetailScroll.Size = UDim2.new(1, -16, 1, -80)
DetailScroll.Position = UDim2.new(0, 8, 0, 32)
DetailScroll.BackgroundTransparency = 1
DetailScroll.ScrollBarThickness = 4
DetailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
DetailScroll.Parent = DetailPanel

local DetailContentText = Instance.new("TextLabel")
DetailContentText.Name = "DetailContentText"
DetailContentText.Size = UDim2.new(1, -6, 0, 0)
DetailContentText.Position = UDim2.new(0, 0, 0, 0)
DetailContentText.BackgroundTransparency = 1
DetailContentText.Font = Enum.Font.Gotham
DetailContentText.TextSize = 11
DetailContentText.TextColor3 = Color3.fromRGB(200, 200, 200)
DetailContentText.TextXAlignment = Enum.TextXAlignment.Left
DetailContentText.TextYAlignment = Enum.TextYAlignment.Top
DetailContentText.TextWrapped = true
DetailContentText.Text = "Select an event card to inspect details."
DetailContentText.Parent = DetailScroll

local DetailActionFrame = Instance.new("Frame")
DetailActionFrame.Name = "DetailActionFrame"
DetailActionFrame.Size = UDim2.new(1, -16, 0, 36)
DetailActionFrame.Position = UDim2.new(0, 8, 1, -42)
DetailActionFrame.BackgroundTransparency = 1
DetailActionFrame.Parent = DetailPanel

local CopyActionLayout = Instance.new("UIListLayout")
CopyActionLayout.FillDirection = Enum.FillDirection.Horizontal
CopyActionLayout.Padding = UDim.new(0, 4)
CopyActionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
CopyActionLayout.Parent = DetailActionFrame

local function CreateDetailActionButton(name, labelText)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0, 72, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.Text = labelText
    btn.Parent = DetailActionFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = btn

    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), {BackgroundColor3 = Color3.fromRGB(58, 58, 70)}):Play()
    end)
    btn.MouseButton1Up:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), {BackgroundColor3 = Color3.fromRGB(38, 38, 46)}):Play()
    end)
    return btn
end

local CopyNameBtn = CreateDetailActionButton("CopyName", "COPY NAME")
local CopyPathBtn = CreateDetailActionButton("CopyPath", "COPY PATH")
local CopyReqBtn = CreateDetailActionButton("CopyReq", "COPY REQUEST")

-- Tab Setup
local TabNames = {"ALL", "REMOTE EVENT", "REMOTE FUNCTION", "HISTORY", "SETTINGS"}
for _, tabName in ipairs(TabNames) do
    local btn = Instance.new("TextButton")
    btn.Name = tabName .. "_Btn"
    btn.Size = UDim2.new(0, 110, 1, 0)
    btn.BackgroundColor3 = (tabName == ActiveTab) and Color3.fromRGB(48, 48, 58) or Color3.fromRGB(28, 28, 34)
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Text = tabName
    btn.Parent = NavFrame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn

    UIReferences.TabButtons[tabName] = btn

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = tabName .. "_Frame"
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.Position = UDim2.new(0, 0, 0, 0)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 5
    scroll.Visible = (tabName == ActiveTab)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = ContentContainer

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = scroll

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
    end)

    UIReferences.TabFrames[tabName] = scroll
end

-- ============================================================================
-- 7. DRAG SYSTEM (MOUSE & TOUCH FRIENDLY)
-- ============================================================================
local dragging = false
local dragInput, dragStart, startPos

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainWindow.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

Header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainWindow.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

-- ============================================================================
-- 8. ANIMATION SYSTEM & WINDOW CONTROLS
-- ============================================================================
local isMinimized = false
local originalSize = MainWindow.Size

local function ToggleWindowVisibility(visible)
    if visible then
        MainWindow.Visible = true
        MainWindow.Size = UDim2.new(0, originalSize.X.Offset * 0.85, 0, originalSize.Y.Offset * 0.85)
        MainWindow.BackgroundTransparency = 1
        FloatingButton.Visible = false

        local tween = TweenService:Create(MainWindow, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = originalSize,
            BackgroundTransparency = 0
        })
        tween:Play()
    else
        local tween = TweenService:Create(MainWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
            Size = UDim2.new(0, originalSize.X.Offset * 0.85, 0, originalSize.Y.Offset * 0.85),
            BackgroundTransparency = 1
        })
        tween:Play()
        tween.Completed:Connect(function()
            MainWindow.Visible = false
            FloatingButton.Visible = true
        end)
    end
end

CloseBtn.MouseButton1Click:Connect(function()
    ToggleWindowVisibility(false)
end)

FloatingButton.MouseButton1Click:Connect(function()
    ToggleWindowVisibility(true)
end)

MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local targetHeight = isMinimized and 42 or originalSize.Y.Offset
    TweenService:Create(MainWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, originalSize.X.Offset, 0, targetHeight)
    }):Play()
end)

-- ============================================================================
-- 9. TAB SYSTEM
-- ============================================================================
local function SwitchTab(tabName)
    ActiveTab = tabName
    for name, frame in pairs(UIReferences.TabFrames) do
        frame.Visible = (name == tabName)
    end
    for name, btn in pairs(UIReferences.TabButtons) do
        local targetColor = (name == tabName) and Color3.fromRGB(48, 48, 58) or Color3.fromRGB(28, 28, 34)
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = targetColor}):Play()
    end
end

for tabName, btn in pairs(UIReferences.TabButtons) do
    btn.MouseButton1Click:Connect(function()
        SwitchTab(tabName)
    end)
end

-- ============================================================================
-- 10. DETAIL PANEL & CLIPBOARD
-- ============================================================================
local function UpdateDetailView(entry)
    CurrentDetail = entry
    if not entry then
        DetailContentText.Text = "Select an event card to inspect details."
        DetailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        return
    end

    local text = string.format(
        "REMOTE DETAILS\n\nName:\n%s\n\nClass:\n%s\n\nPath:\n%s\n\nCalls:\n%d\n\nLast Called:\n%s\n\nArguments:\n%s",
        entry.Name,
        entry.Class,
        entry.Path,
        entry.CallCount or 1,
        entry.Timestamp,
        FormatArgumentsList(entry.Args)
    )

    if entry.Class == "RemoteFunction" and entry.ReturnValue ~= nil then
        text = text .. "\n\nRETURN:\n" .. FormatValue(entry.ReturnValue)
    end

    DetailContentText.Text = text
    local bounds = TextService:GetTextSize(text, 11, Enum.Font.Gotham, Vector2.new(DetailScroll.AbsoluteSize.X - 10, 5000))
    DetailScroll.CanvasSize = UDim2.new(0, 0, 0, bounds.Y + 20)
end

CopyNameBtn.MouseButton1Click:Connect(function()
    if CurrentDetail then
        SafeSetClipboard(CurrentDetail.Name)
    end
end)

CopyPathBtn.MouseButton1Click:Connect(function()
    if CurrentDetail then
        SafeSetClipboard(CurrentDetail.Path)
    end
end)

CopyReqBtn.MouseButton1Click:Connect(function()
    if CurrentDetail and CurrentDetail.Args then
        SafeSetClipboard(FormatArgumentsList(CurrentDetail.Args))
    end
end)

-- ============================================================================
-- 11. HISTORY MANAGER & CARD CREATION
-- ============================================================================
local function MatchesSearch(entry, query)
    if query == "" then return true end
    query = string.lower(query)
    if string.find(string.lower(entry.Name), query, 1, true) then return true end
    if string.find(string.lower(entry.Path), query, 1, true) then return true end
    if string.find(string.lower(entry.Class), query, 1, true) then return true end
    if entry.ArgsString and string.find(string.lower(entry.ArgsString), query, 1, true) then return true end
    return false
end

local function BuildCard(entry, parentFrame)
    local card = Instance.new("TextButton")
    card.Name = "Card_" .. entry.Name
    card.Size = UDim2.new(1, -6, 0, 72)
    card.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    card.Text = ""
    card.AutoButtonColor = false
    card.Parent = parentFrame

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local cardPad = Instance.new("UIPadding")
    cardPad.PaddingLeft = UDim.new(0, 8)
    cardPad.PaddingRight = UDim.new(0, 8)
    cardPad.PaddingTop = UDim.new(0, 6)
    cardPad.PaddingBottom = UDim.new(0, 6)
    cardPad.Parent = card

    local classLabel = Instance.new("TextLabel")
    classLabel.Size = UDim2.new(0.6, 0, 0, 16)
    classLabel.BackgroundTransparency = 1
    classLabel.Font = Enum.Font.GothamBold
    classLabel.TextSize = 11
    classLabel.TextColor3 = (entry.Class == "RemoteEvent") and Color3.fromRGB(80, 160, 240) or Color3.fromRGB(240, 160, 80)
    classLabel.TextXAlignment = Enum.TextXAlignment.Left
    classLabel.Text = entry.Class .. (entry.CallCount and (" (" .. tostring(entry.CallCount) .. ")") or "")
    classLabel.Parent = card

    local timeLabel = Instance.new("TextLabel")
    timeLabel.Size = UDim2.new(0.4, 0, 0, 16)
    timeLabel.Position = UDim2.new(0.6, 0, 0, 0)
    timeLabel.BackgroundTransparency = 1
    timeLabel.Font = Enum.Font.Gotham
    timeLabel.TextSize = 10
    timeLabel.TextColor3 = Color3.fromRGB(140, 140, 150)
    timeLabel.TextXAlignment = Enum.TextXAlignment.Right
    timeLabel.Text = SettingsState.ShowTimestamp and entry.Timestamp or ""
    timeLabel.Parent = card

    local pathLabel = Instance.new("TextLabel")
    pathLabel.Size = UDim2.new(1, 0, 0, 14)
    pathLabel.Position = UDim2.new(0, 0, 0, 18)
    pathLabel.BackgroundTransparency = 1
    pathLabel.Font = Enum.Font.GothamMedium
    pathLabel.TextSize = 11
    pathLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
    pathLabel.TextXAlignment = Enum.TextXAlignment.Left
    pathLabel.TextTruncate = Enum.TextTruncate.AtEnd
    pathLabel.Text = SettingsState.ShowFullPath and entry.Path or entry.Name
    pathLabel.Parent = card

    local previewLabel = Instance.new("TextLabel")
    previewLabel.Size = UDim2.new(1, 0, 0, 24)
    previewLabel.Position = UDim2.new(0, 0, 0, 34)
    previewLabel.BackgroundTransparency = 1
    previewLabel.Font = Enum.Font.Gotham
    previewLabel.TextSize = 10
    previewLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
    previewLabel.TextXAlignment = Enum.TextXAlignment.Left
    previewLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local previewText = "Args: "
    if #entry.Args == 0 then
        previewText = previewText .. "None"
    else
        for i, a in ipairs(entry.Args) do
            previewText = previewText .. string.format("[%d] %s  ", i, typeof(a))
            if i >= 3 then
                previewText = previewText .. "..."
                break
            end
        end
    end
    previewLabel.Text = previewText
    previewLabel.Parent = card

    card.MouseButton1Click:Connect(function()
        UpdateDetailView(entry)
    end)

    return card
end

local function RegisterEntry(entry)
    entry.ArgsString = FormatArgumentsList(entry.Args)

    table.insert(HistoryData, entry)
    if #HistoryData > SettingsState.MaxHistory then
        table.remove(HistoryData, 1)
    end

    local function AddToTargetTab(targetTab)
        local frame = UIReferences.TabFrames[targetTab]
        if not frame then return end
        local card = BuildCard(entry, frame)
        card.Visible = MatchesSearch(entry, SearchQuery)
        table.insert(UIReferences.CardsByTab[targetTab], {Card = card, Entry = entry})

        if #UIReferences.CardsByTab[targetTab] > SettingsState.MaxHistory then
            local oldest = table.remove(UIReferences.CardsByTab[targetTab], 1)
            if oldest and oldest.Card then
                oldest.Card:Destroy()
            end
        end

        if SettingsState.AutoScroll and ActiveTab == targetTab then
            frame.CanvasPosition = Vector2.new(0, math.max(0, frame.CanvasSize.Y.Offset - frame.AbsoluteSize.Y))
        end
    end

    AddToTargetTab("ALL")
    AddToTargetTab("HISTORY")
    if entry.Class == "RemoteEvent" then
        AddToTargetTab("REMOTE EVENT")
    elseif entry.Class == "RemoteFunction" then
        AddToTargetTab("REMOTE FUNCTION")
    end
end

-- ============================================================================
-- 12. SEARCH SYSTEM
-- ============================================================================
local function RefreshSearchFilter()
    for tabName, cardList in pairs(UIReferences.CardsByTab) do
        for _, item in ipairs(cardList) do
            item.Card.Visible = MatchesSearch(item.Entry, SearchQuery)
        end
    end
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    SearchQuery = SearchBox.Text
    RefreshSearchFilter()
end)

-- ============================================================================
-- 13. SETTINGS TAB INTERFACE
-- ============================================================================
local SettingsFrame = UIReferences.TabFrames["SETTINGS"]

local function CreateSettingToggle(title, defaultVal, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -10, 0, 36)
    frame.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
    frame.Parent = SettingsFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = title
    label.Parent = frame

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 60, 0, 26)
    toggle.Position = UDim2.new(1, -70, 0.5, -13)
    toggle.BackgroundColor3 = defaultVal and Color3.fromRGB(60, 140, 70) or Color3.fromRGB(60, 60, 70)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 11
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.Text = defaultVal and "ON" or "OFF"
    toggle.Parent = frame

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 4)
    toggleCorner.Parent = toggle

    local current = defaultVal
    toggle.MouseButton1Click:Connect(function()
        current = not current
        toggle.Text = current and "ON" or "OFF"
        TweenService:Create(toggle, TweenInfo.new(0.2), {
            BackgroundColor3 = current and Color3.fromRGB(60, 140, 70) or Color3.fromRGB(60, 60, 70)
        }):Play()
        callback(current)
    end)
end

CreateSettingToggle("Auto Scroll", SettingsState.AutoScroll, function(v)
    SettingsState.AutoScroll = v
end)

CreateSettingToggle("Timestamp Display", SettingsState.ShowTimestamp, function(v)
    SettingsState.ShowTimestamp = v
end)

CreateSettingToggle("Full Path Display", SettingsState.ShowFullPath, function(v)
    SettingsState.ShowFullPath = v
end)

local function CreateActionButton(text, color, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -10, 0, 36)
    btn.BackgroundColor3 = color
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Text = text
    btn.Parent = SettingsFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(callback)
    return btn
end

local function ClearTab(tabName)
    local cardList = UIReferences.CardsByTab[tabName]
    if cardList then
        for _, item in ipairs(cardList) do
            if item.Card then item.Card:Destroy() end
        end
        UIReferences.CardsByTab[tabName] = {}
    end
end

CreateActionButton("Clear Current Tab", Color3.fromRGB(140, 80, 45), function()
    if ActiveTab ~= "SETTINGS" then
        ClearTab(ActiveTab)
    end
end)

CreateActionButton("Clear History", Color3.fromRGB(140, 45, 45), function()
    table.clear(HistoryData)
    for tab, _ in pairs(UIReferences.CardsByTab) do
        ClearTab(tab)
    end
    UpdateDetailView(nil)
end)

CreateActionButton("Reset Settings", Color3.fromRGB(60, 60, 70), function()
    SettingsState.AutoScroll = true
    SettingsState.ShowTimestamp = true
    SettingsState.ShowFullPath = true
    SettingsState.MaxHistory = 500
end)

-- Status Indicator for Executor API
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -10, 0, 24)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 10
StatusLabel.TextColor3 = HasGetConnections and Color3.fromRGB(100, 220, 100) or Color3.fromRGB(220, 100, 100)
StatusLabel.Text = HasGetConnections and "Monitoring API: Active (getconnections available)" or "Monitoring API: Passive (getconnections unavailable)"
StatusLabel.Parent = SettingsFrame

-- ============================================================================
-- 14. MONITORING ENGINE (EVENT-DRIVEN & COMPATIBLE)
-- ============================================================================
local function HookRemote(instance)
    if not instance or typeof(instance) ~= "Instance" then return end

    if instance:IsA("RemoteEvent") then
        local fullPath = GetInstanceFullPath(instance)
        RemoteStats[fullPath] = (RemoteStats[fullPath] or 0)

        local conn
        local success, err = pcall(function()
            conn = instance.OnClientEvent:Connect(function(...)
                local args = {...}
                RemoteStats[fullPath] = (RemoteStats[fullPath] or 0) + 1
                RegisterEntry({
                    Name = instance.Name,
                    Class = "RemoteEvent",
                    Path = fullPath,
                    Timestamp = GetCurrentTimestamp(),
                    CallCount = RemoteStats[fullPath],
                    Args = args
                })
            end)
        end)
        if success and conn then
            table.insert(Connections, conn)
        end
    elseif instance:IsA("RemoteFunction") then
        local fullPath = GetInstanceFullPath(instance)
        RemoteStats[fullPath] = (RemoteStats[fullPath] or 0)

        pcall(function()
            local originalCallback = instance.OnClientInvoke
            instance.OnClientInvoke = function(...)
                local args = {...}
                RemoteStats[fullPath] = (RemoteStats[fullPath] or 0) + 1
                local retVal = nil
                if originalCallback then
                    retVal = originalCallback(...)
                end
                RegisterEntry({
                    Name = instance.Name,
                    Class = "RemoteFunction",
                    Path = fullPath,
                    Timestamp = GetCurrentTimestamp(),
                    CallCount = RemoteStats[fullPath],
                    Args = args,
                    ReturnValue = retVal
                })
                return retVal
            end
        end)
    end
end

-- ============================================================================
-- 15. INITIALIZATION & CLEANUP
-- ============================================================================
local function ScanAndBind(root)
    pcall(function()
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
                HookRemote(descendant)
            end
        end
    end)
end

-- Bind existing and incoming remotes in relevant services
local TargetServices = {
    game:GetService("ReplicatedStorage"),
    game:GetService("Players"),
    game:GetService("Lighting")
}

for _, svc in ipairs(TargetServices) do
    ScanAndBind(svc)
    local addedConn = svc.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
            HookRemote(descendant)
        end
    end)
    table.insert(Connections, addedConn)
end

-- Cleanup handler
ScreenGui.Destroying:Connect(function()
    for _, conn in ipairs(Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    table.clear(Connections)
    table.clear(HistoryData)
    table.clear(RemoteStats)
    table.clear(UIReferences.CardsByTab)
end)
