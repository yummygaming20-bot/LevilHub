local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local Camera = Workspace.CurrentCamera

local Connections = {}
local HistoryData = {}
local RemoteStats = {}
local ActiveTab = "ALL"
local CurrentDetail = nil
local CurrentSelectedCard = nil
local SearchQuery = ""
local IsMobileLayout = false

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

local function SafeSetClipboard(text)
    if not text then return false end
    local success = false
    pcall(function()
        if typeof(setclipboard) == "function" then
            setclipboard(tostring(text))
            success = true
        elseif typeof(toclipboard) == "function" then
            toclipboard(tostring(text))
            success = true
        elseif typeof(set_clipboard) == "function" then
            set_clipboard(tostring(text))
            success = true
        elseif Clipboard and typeof(Clipboard.set) == "function" then
            Clipboard.set(tostring(text))
            success = true
        end
    end)
    return success
end

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
        return "Table\n" .. FormatTableRecursive(val, indent, depth, visited)
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
        table.insert(lines, string.format("[%d] (%s):\n%s", i, t, formatted))
    end
    return table.concat(lines, "\n\n")
end

local function GetCurrentViewport()
    local vp = Camera and Camera.ViewportSize or Vector2.new(800, 600)
    if vp.X < 50 or vp.Y < 50 then
        return Vector2.new(800, 600)
    end
    return vp
end

local function CalculateWindowSize(vp)
    local w = math.clamp(vp.X - 16, 280, 560)
    local h = math.clamp(vp.Y - 24, 220, 320)
    return Vector2.new(w, h)
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RemoteEventMonitor"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = CoreGui

local FloatingButton = Instance.new("TextButton")
FloatingButton.Name = "FloatingOpenButton"
FloatingButton.Size = UDim2.new(0, 95, 0, 32)
FloatingButton.Position = UDim2.new(0, 15, 0.5, -16)
FloatingButton.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
FloatingButton.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatingButton.Font = Enum.Font.GothamBold
FloatingButton.TextSize = 11
FloatingButton.Text = "[ REMOTE ]"
FloatingButton.Visible = false
FloatingButton.ZIndex = 100
FloatingButton.Active = true
FloatingButton.Parent = ScreenGui

local FloatingCorner = Instance.new("UICorner")
FloatingCorner.CornerRadius = UDim.new(0, 8)
FloatingCorner.Parent = FloatingButton

local FloatingStroke = Instance.new("UIStroke")
FloatingStroke.Color = Color3.fromRGB(60, 60, 80)
FloatingStroke.Thickness = 1
FloatingStroke.Parent = FloatingButton

local initVp = GetCurrentViewport()
local initSize = CalculateWindowSize(initVp)

local MainWindow = Instance.new("Frame")
MainWindow.Name = "MainWindow"
MainWindow.Size = UDim2.new(0, initSize.X, 0, initSize.Y)
MainWindow.Position = UDim2.new(0.5, -initSize.X / 2, 0.5, -initSize.Y / 2)
MainWindow.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
MainWindow.BorderSizePixel = 0
MainWindow.ClipsDescendants = true
MainWindow.Active = true
MainWindow.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = MainWindow

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(45, 45, 55)
MainStroke.Thickness = 1
MainStroke.Parent = MainWindow

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 34)
Header.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
Header.BorderSizePixel = 0
Header.Active = true
Header.Parent = MainWindow

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 8)
HeaderCorner.Parent = Header

local DragArea = Instance.new("Frame")
DragArea.Name = "DragArea"
DragArea.Size = UDim2.new(1, -64, 1, 0)
DragArea.Position = UDim2.new(0, 0, 0, 0)
DragArea.BackgroundTransparency = 1
DragArea.Active = true
DragArea.Parent = Header

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, -10, 1, 0)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 12
Title.TextColor3 = Color3.fromRGB(240, 240, 240)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "REMOTE MONITOR"
Title.Parent = DragArea

local MinBtn = Instance.new("TextButton")
MinBtn.Name = "MinButton"
MinBtn.Size = UDim2.new(0, 24, 0, 24)
MinBtn.Position = UDim2.new(1, -56, 0, 5)
MinBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 12
MinBtn.Text = "-"
MinBtn.ZIndex = 5
MinBtn.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 4)
MinCorner.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseButton"
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.Position = UDim2.new(1, -28, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.Text = "X"
CloseBtn.ZIndex = 5
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 4)
CloseCorner.Parent = CloseBtn

local NavScroll = Instance.new("ScrollingFrame")
NavScroll.Name = "NavScroll"
NavScroll.Size = UDim2.new(1, -12, 0, 28)
NavScroll.Position = UDim2.new(0, 6, 0, 38)
NavScroll.BackgroundTransparency = 1
NavScroll.ScrollBarThickness = 0
NavScroll.ScrollingDirection = Enum.ScrollingDirection.Horizontal
NavScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
NavScroll.Parent = MainWindow

local NavLayout = Instance.new("UIListLayout")
NavLayout.FillDirection = Enum.FillDirection.Horizontal
NavLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
NavLayout.Padding = UDim.new(0, 4)
NavLayout.Parent = NavScroll

NavLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    NavScroll.CanvasSize = UDim2.new(0, NavLayout.AbsoluteContentSize.X + 8, 0, 0)
end)

local SearchBox = Instance.new("TextBox")
SearchBox.Name = "SearchBox"
SearchBox.Size = UDim2.new(1, -12, 0, 26)
SearchBox.Position = UDim2.new(0, 6, 0, 70)
SearchBox.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
SearchBox.TextColor3 = Color3.fromRGB(240, 240, 240)
SearchBox.PlaceholderColor3 = Color3.fromRGB(110, 110, 120)
SearchBox.PlaceholderText = "Search by Name, Path, or Arguments..."
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 11
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = MainWindow

local SearchCorner = Instance.new("UICorner")
SearchCorner.CornerRadius = UDim.new(0, 5)
SearchCorner.Parent = SearchBox

local SearchPadding = Instance.new("UIPadding")
SearchPadding.PaddingLeft = UDim.new(0, 8)
SearchPadding.PaddingRight = UDim.new(0, 8)
SearchPadding.Parent = SearchBox

local ContentContainer = Instance.new("Frame")
ContentContainer.Name = "ContentContainer"
ContentContainer.Size = UDim2.new(1, -195, 1, -104)
ContentContainer.Position = UDim2.new(0, 6, 0, 100)
ContentContainer.BackgroundTransparency = 1
ContentContainer.ClipsDescendants = true
ContentContainer.Parent = MainWindow

local DetailPanel = Instance.new("Frame")
DetailPanel.Name = "DetailPanel"
DetailPanel.Size = UDim2.new(0, 180, 1, -104)
DetailPanel.Position = UDim2.new(1, -186, 0, 100)
DetailPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
DetailPanel.BorderSizePixel = 0
DetailPanel.ZIndex = 10
DetailPanel.Parent = MainWindow

local DetailCorner = Instance.new("UICorner")
DetailCorner.CornerRadius = UDim.new(0, 6)
DetailCorner.Parent = DetailPanel

local DetailHeader = Instance.new("Frame")
DetailHeader.Name = "DetailHeader"
DetailHeader.Size = UDim2.new(1, 0, 0, 24)
DetailHeader.BackgroundTransparency = 1
DetailHeader.Parent = DetailPanel

local DetailBackBtn = Instance.new("TextButton")
DetailBackBtn.Name = "DetailBackBtn"
DetailBackBtn.Size = UDim2.new(0, 36, 0, 20)
DetailBackBtn.Position = UDim2.new(0, 4, 0, 2)
DetailBackBtn.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
DetailBackBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
DetailBackBtn.Font = Enum.Font.GothamBold
DetailBackBtn.TextSize = 9
DetailBackBtn.Text = "< BACK"
DetailBackBtn.Visible = false
DetailBackBtn.ZIndex = 11
DetailBackBtn.Parent = DetailHeader

local DetailBackCorner = Instance.new("UICorner")
DetailBackCorner.CornerRadius = UDim.new(0, 4)
DetailBackCorner.Parent = DetailBackBtn

local DetailTitle = Instance.new("TextLabel")
DetailTitle.Name = "DetailTitle"
DetailTitle.Size = UDim2.new(1, -10, 1, 0)
DetailTitle.Position = UDim2.new(0, 5, 0, 0)
DetailTitle.BackgroundTransparency = 1
DetailTitle.Font = Enum.Font.GothamBold
DetailTitle.TextSize = 10
DetailTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
DetailTitle.TextXAlignment = Enum.TextXAlignment.Left
DetailTitle.TextTruncate = Enum.TextTruncate.AtEnd
DetailTitle.Text = "DETAILS"
DetailTitle.ZIndex = 11
DetailTitle.Parent = DetailHeader

local DetailScroll = Instance.new("ScrollingFrame")
DetailScroll.Name = "DetailScroll"
DetailScroll.Size = UDim2.new(1, -10, 1, -54)
DetailScroll.Position = UDim2.new(0, 5, 0, 24)
DetailScroll.BackgroundTransparency = 1
DetailScroll.ScrollBarThickness = 3
DetailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
DetailScroll.ZIndex = 11
DetailScroll.Parent = DetailPanel

local DetailContentText = Instance.new("TextLabel")
DetailContentText.Name = "DetailContentText"
DetailContentText.Size = UDim2.new(1, -4, 0, 0)
DetailContentText.Position = UDim2.new(0, 0, 0, 0)
DetailContentText.BackgroundTransparency = 1
DetailContentText.Font = Enum.Font.Gotham
DetailContentText.TextSize = 10
DetailContentText.TextColor3 = Color3.fromRGB(190, 190, 200)
DetailContentText.TextXAlignment = Enum.TextXAlignment.Left
DetailContentText.TextYAlignment = Enum.TextYAlignment.Top
DetailContentText.TextWrapped = true
DetailContentText.Text = "Select an event card to inspect details."
DetailContentText.ZIndex = 11
DetailContentText.Parent = DetailScroll

local DetailActionFrame = Instance.new("Frame")
DetailActionFrame.Name = "DetailActionFrame"
DetailActionFrame.Size = UDim2.new(1, -8, 0, 24)
DetailActionFrame.Position = UDim2.new(0, 4, 1, -27)
DetailActionFrame.BackgroundTransparency = 1
DetailActionFrame.ZIndex = 11
DetailActionFrame.Parent = DetailPanel

local CopyActionLayout = Instance.new("UIListLayout")
CopyActionLayout.FillDirection = Enum.FillDirection.Horizontal
CopyActionLayout.Padding = UDim.new(0, 3)
CopyActionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
CopyActionLayout.Parent = DetailActionFrame

local function CreateDetailActionButton(name, labelText)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0, 54, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 8
    btn.Text = labelText
    btn.ZIndex = 12
    btn.Parent = DetailActionFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = btn

    return btn
end

local CopyNameBtn = CreateDetailActionButton("CopyName", "NAME")
local CopyPathBtn = CreateDetailActionButton("CopyPath", "PATH")
local CopyReqBtn = CreateDetailActionButton("CopyReq", "REQUEST")

local TabDefs = {
    {"ALL", 65},
    {"REMOTE EVENT", 95},
    {"REMOTE FUNCTION", 110},
    {"HISTORY", 65},
    {"SETTINGS", 70}
}

for _, def in ipairs(TabDefs) do
    local tabName = def[1]
    local tabWidth = def[2]

    local btn = Instance.new("TextButton")
    btn.Name = tabName .. "_Btn"
    btn.Size = UDim2.new(0, tabWidth, 1, 0)
    btn.BackgroundColor3 = (tabName == ActiveTab) and Color3.fromRGB(42, 42, 54) or Color3.fromRGB(24, 24, 30)
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.Text = tabName
    btn.Parent = NavScroll

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 5)
    btnCorner.Parent = btn

    UIReferences.TabButtons[tabName] = btn

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = tabName .. "_Frame"
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.Position = UDim2.new(0, 0, 0, 0)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 3
    scroll.Visible = (tabName == ActiveTab)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = ContentContainer

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = scroll

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end)

    UIReferences.TabFrames[tabName] = scroll
end

local function UpdateDetailView(entry)
    CurrentDetail = entry
    if not entry then
        DetailTitle.Text = "DETAILS"
        DetailContentText.Text = "Select an event card to inspect details."
        DetailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        return
    end

    DetailTitle.Text = string.upper(entry.Name)

    local text = string.format(
        "Name: %s\nClass: %s\nPath: %s\nTimestamp: %s\nCalls: %d\n\nArguments:\n%s",
        entry.Name,
        entry.Class,
        entry.Path,
        entry.Timestamp,
        entry.CallCount or 1,
        FormatArgumentsList(entry.Args)
    )

    if entry.Class == "RemoteFunction" and entry.ReturnValue ~= nil then
        text = text .. "\n\nReturn Value:\n" .. FormatValue(entry.ReturnValue)
    end

    DetailContentText.Text = text
    local actualWidth = DetailScroll.AbsoluteSize.X
    local targetWidth = (actualWidth > 20) and (actualWidth - 8) or 160
    local bounds = TextService:GetTextSize(text, 10, Enum.Font.Gotham, Vector2.new(targetWidth, 10000))
    DetailContentText.Size = UDim2.new(1, -4, 0, bounds.Y + 14)
    DetailScroll.CanvasSize = UDim2.new(0, 0, 0, bounds.Y + 28)
end

local function ApplyLayout()
    local vp = GetCurrentViewport()
    local mwSize = MainWindow.AbsoluteSize
    local isMobile = (vp.X < 540) or (mwSize.X < 450)
    IsMobileLayout = isMobile

    if isMobile then
        ContentContainer.Size = UDim2.new(1, -12, 1, -104)
        DetailPanel.Size = UDim2.new(1, -12, 1, -104)
        DetailPanel.Position = UDim2.new(0, 6, 0, 100)
        DetailBackBtn.Visible = true
        DetailTitle.Position = UDim2.new(0, 44, 0, 0)
        DetailTitle.Size = UDim2.new(1, -48, 1, 0)
        DetailPanel.Visible = (CurrentDetail ~= nil)
    else
        ContentContainer.Size = UDim2.new(1, -195, 1, -104)
        DetailPanel.Size = UDim2.new(0, 180, 1, -104)
        DetailPanel.Position = UDim2.new(1, -186, 0, 100)
        DetailBackBtn.Visible = false
        DetailTitle.Position = UDim2.new(0, 5, 0, 0)
        DetailTitle.Size = UDim2.new(1, -10, 1, 0)
        DetailPanel.Visible = true
    end

    if CurrentDetail then
        task.defer(function()
            UpdateDetailView(CurrentDetail)
        end)
    end
end

DetailBackBtn.Activated:Connect(function()
    if IsMobileLayout then
        DetailPanel.Visible = false
    end
end)

local function SetupDrag(dragHandle, targetFrame)
    local isDragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            dragStart = input.Position
            startPos = targetFrame.Position

            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    isDragging = false
                    if conn then conn:Disconnect() end
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and isDragging then
            local delta = input.Position - dragStart
            local vp = GetCurrentViewport()
            local frameSize = targetFrame.AbsoluteSize
            local rawX = startPos.X.Offset + delta.X
            local rawY = startPos.Y.Offset + delta.Y
            local clampedX = math.clamp(rawX, 0, math.max(0, vp.X - frameSize.X))
            local clampedY = math.clamp(rawY, 0, math.max(0, vp.Y - frameSize.Y))
            targetFrame.Position = UDim2.new(0, clampedX, 0, clampedY)
        end
    end)
end

SetupDrag(DragArea, MainWindow)

local floatDragging = false
local floatActiveInput = nil
local floatDragStart = nil
local floatStartPos = nil
local floatMovedDistance = 0

FloatingButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        floatDragging = true
        floatActiveInput = input
        floatDragStart = input.Position
        floatStartPos = FloatingButton.Position
        floatMovedDistance = 0

        local conn
        conn = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                if floatDragging and (input == floatActiveInput) then
                    floatDragging = false
                    if floatMovedDistance <= 9 then
                        MainWindow.Visible = true
                        FloatingButton.Visible = false
                        ApplyLayout()
                        TweenService:Create(MainWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                            BackgroundTransparency = 0
                        }):Play()
                    end
                end
                if conn then conn:Disconnect() end
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if floatDragging and (input == floatActiveInput or input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - floatDragStart
        floatMovedDistance = Vector2.new(delta.X, delta.Y).Magnitude
        local vp = GetCurrentViewport()
        local btnSize = FloatingButton.AbsoluteSize
        local rawX = floatStartPos.X.Offset + delta.X
        local rawY = floatStartPos.Y.Offset + delta.Y
        local clampedX = math.clamp(rawX, 0, math.max(0, vp.X - btnSize.X))
        local clampedY = math.clamp(rawY, 0, math.max(0, vp.Y - btnSize.Y))
        FloatingButton.Position = UDim2.new(0, clampedX, 0, clampedY)
    end
end)

local isMinimized = false
local function ToggleWindow(visible)
    if visible then
        MainWindow.Visible = true
        FloatingButton.Visible = false
        ApplyLayout()
        TweenService:Create(MainWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0
        }):Play()
    else
        local tween = TweenService:Create(MainWindow, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
            BackgroundTransparency = 1
        })
        tween:Play()
        tween.Completed:Connect(function()
            MainWindow.Visible = false
            FloatingButton.Visible = true
        end)
    end
end

CloseBtn.Activated:Connect(function()
    ToggleWindow(false)
end)

MinBtn.Activated:Connect(function()
    isMinimized = not isMinimized
    local vp = GetCurrentViewport()
    local winSize = CalculateWindowSize(vp)
    local targetHeight = isMinimized and 34 or winSize.Y
    TweenService:Create(MainWindow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, winSize.X, 0, targetHeight)
    }):Play()
end)

local function SwitchTab(tabName)
    ActiveTab = tabName
    for name, frame in pairs(UIReferences.TabFrames) do
        frame.Visible = (name == tabName)
    end
    for name, btn in pairs(UIReferences.TabButtons) do
        local targetColor = (name == tabName) and Color3.fromRGB(42, 42, 54) or Color3.fromRGB(24, 24, 30)
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = targetColor}):Play()
    end
end

for tabName, btn in pairs(UIReferences.TabButtons) do
    btn.Activated:Connect(function()
        SwitchTab(tabName)
    end)
end

local function TriggerCopyFeedback(button, originalText, success)
    if success then
        button.Text = "COPIED!"
        button.TextColor3 = Color3.fromRGB(100, 255, 120)
    else
        button.Text = "UNAVAILABLE"
        button.TextColor3 = Color3.fromRGB(255, 100, 100)
    end
    task.delay(1.2, function()
        button.Text = originalText
        button.TextColor3 = Color3.fromRGB(240, 240, 240)
    end)
end

CopyNameBtn.Activated:Connect(function()
    if CurrentDetail and CurrentDetail.Name then
        local ok = SafeSetClipboard(CurrentDetail.Name)
        TriggerCopyFeedback(CopyNameBtn, "NAME", ok)
    else
        TriggerCopyFeedback(CopyNameBtn, "NAME", false)
    end
end)

CopyPathBtn.Activated:Connect(function()
    if CurrentDetail and CurrentDetail.Path then
        local ok = SafeSetClipboard(CurrentDetail.Path)
        TriggerCopyFeedback(CopyPathBtn, "PATH", ok)
    else
        TriggerCopyFeedback(CopyPathBtn, "PATH", false)
    end
end)

CopyReqBtn.Activated:Connect(function()
    if CurrentDetail and CurrentDetail.Args then
        local rawArgs = FormatArgumentsList(CurrentDetail.Args)
        local ok = SafeSetClipboard(rawArgs)
        TriggerCopyFeedback(CopyReqBtn, "REQUEST", ok)
    else
        TriggerCopyFeedback(CopyReqBtn, "REQUEST", false)
    end
end)

local function MatchesSearch(entry, query)
    if not query or query == "" then return true end
    query = string.lower(query)
    if string.find(string.lower(entry.Name or ""), query, 1, true) then return true end
    if string.find(string.lower(entry.Path or ""), query, 1, true) then return true end
    if string.find(string.lower(entry.Class or ""), query, 1, true) then return true end
    if entry.ArgsString and string.find(string.lower(entry.ArgsString), query, 1, true) then return true end
    return false
end

local function SelectCard(card, entry)
    if CurrentSelectedCard and CurrentSelectedCard.Parent then
        CurrentSelectedCard.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    end
    CurrentSelectedCard = card
    card.BackgroundColor3 = Color3.fromRGB(36, 36, 50)
    UpdateDetailView(entry)
    if IsMobileLayout then
        DetailPanel.Visible = true
    end
end

local function BuildCard(entry, parentFrame)
    local card = Instance.new("TextButton")
    card.Name = "Card_" .. tostring(entry.Name)
    card.Size = UDim2.new(1, -4, 0, 56)
    card.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    card.Text = ""
    card.AutoButtonColor = false
    card.Active = true
    card.Parent = parentFrame

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 5)
    cardCorner.Parent = card

    local cardPad = Instance.new("UIPadding")
    cardPad.PaddingLeft = UDim.new(0, 6)
    cardPad.PaddingRight = UDim.new(0, 6)
    cardPad.PaddingTop = UDim.new(0, 4)
    cardPad.PaddingBottom = UDim.new(0, 4)
    cardPad.Parent = card

    local classLabel = Instance.new("TextLabel")
    classLabel.Size = UDim2.new(0.55, 0, 0, 14)
    classLabel.BackgroundTransparency = 1
    classLabel.Font = Enum.Font.GothamBold
    classLabel.TextSize = 10
    classLabel.TextColor3 = (entry.Class == "RemoteEvent") and Color3.fromRGB(75, 155, 235) or Color3.fromRGB(235, 155, 75)
    classLabel.TextXAlignment = Enum.TextXAlignment.Left
    classLabel.Text = entry.Class .. (entry.CallCount and (" (" .. tostring(entry.CallCount) .. ")") or "")
    classLabel.Parent = card

    local timeLabel = Instance.new("TextLabel")
    timeLabel.Size = UDim2.new(0.45, 0, 0, 14)
    timeLabel.Position = UDim2.new(0.55, 0, 0, 0)
    timeLabel.BackgroundTransparency = 1
    timeLabel.Font = Enum.Font.Gotham
    timeLabel.TextSize = 9
    timeLabel.TextColor3 = Color3.fromRGB(130, 130, 140)
    timeLabel.TextXAlignment = Enum.TextXAlignment.Right
    timeLabel.Text = SettingsState.ShowTimestamp and entry.Timestamp or ""
    timeLabel.Parent = card

    local pathLabel = Instance.new("TextLabel")
    pathLabel.Size = UDim2.new(1, 0, 0, 14)
    pathLabel.Position = UDim2.new(0, 0, 0, 15)
    pathLabel.BackgroundTransparency = 1
    pathLabel.Font = Enum.Font.GothamMedium
    pathLabel.TextSize = 10
    pathLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
    pathLabel.TextXAlignment = Enum.TextXAlignment.Left
    pathLabel.TextTruncate = Enum.TextTruncate.AtEnd
    pathLabel.Text = SettingsState.ShowFullPath and entry.Path or entry.Name
    pathLabel.Parent = card

    local previewLabel = Instance.new("TextLabel")
    previewLabel.Size = UDim2.new(1, 0, 0, 16)
    previewLabel.Position = UDim2.new(0, 0, 0, 30)
    previewLabel.BackgroundTransparency = 1
    previewLabel.Font = Enum.Font.Gotham
    previewLabel.TextSize = 9
    previewLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
    previewLabel.TextXAlignment = Enum.TextXAlignment.Left
    previewLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local previewText = "Args: "
    if #entry.Args == 0 then
        previewText = previewText .. "None"
    else
        for i, a in ipairs(entry.Args) do
            previewText = previewText .. string.format("[%d] %s  ", i, typeof(a))
            if i >= 2 then
                if #entry.Args > 2 then previewText = previewText .. "..." end
                break
            end
        end
    end
    previewLabel.Text = previewText
    previewLabel.Parent = card

    card.Activated:Connect(function()
        SelectCard(card, entry)
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
                if CurrentSelectedCard == oldest.Card then
                    CurrentSelectedCard = nil
                end
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

local function RefreshSearchFilter()
    for _, cardList in pairs(UIReferences.CardsByTab) do
        for _, item in ipairs(cardList) do
            item.Card.Visible = MatchesSearch(item.Entry, SearchQuery)
        end
    end
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    SearchQuery = SearchBox.Text
    RefreshSearchFilter()
end)

local SettingsFrame = UIReferences.TabFrames["SETTINGS"]

local function CreateSettingToggle(title, defaultVal, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -6, 0, 30)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    frame.Parent = SettingsFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 10
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = title
    label.Parent = frame

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 48, 0, 20)
    toggle.Position = UDim2.new(1, -54, 0.5, -10)
    toggle.BackgroundColor3 = defaultVal and Color3.fromRGB(50, 130, 65) or Color3.fromRGB(55, 55, 65)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 9
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.Text = defaultVal and "ON" or "OFF"
    toggle.Parent = frame

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 4)
    toggleCorner.Parent = toggle

    local current = defaultVal
    toggle.Activated:Connect(function()
        current = not current
        toggle.Text = current and "ON" or "OFF"
        TweenService:Create(toggle, TweenInfo.new(0.15), {
            BackgroundColor3 = current and Color3.fromRGB(50, 130, 65) or Color3.fromRGB(55, 55, 65)
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
    btn.Size = UDim2.new(1, -6, 0, 28)
    btn.BackgroundColor3 = color
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.Text = text
    btn.Parent = SettingsFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = btn

    btn.Activated:Connect(callback)
    return btn
end

local function ClearTab(tabName)
    local cardList = UIReferences.CardsByTab[tabName]
    if cardList then
        for _, item in ipairs(cardList) do
            if item.Card then
                if CurrentSelectedCard == item.Card then
                    CurrentSelectedCard = nil
                end
                item.Card:Destroy()
            end
        end
        UIReferences.CardsByTab[tabName] = {}
    end
end

CreateActionButton("Clear Current Tab", Color3.fromRGB(130, 75, 40), function()
    if ActiveTab ~= "SETTINGS" then
        ClearTab(ActiveTab)
    end
end)

CreateActionButton("Clear History", Color3.fromRGB(130, 40, 40), function()
    table.clear(HistoryData)
    for tab, _ in pairs(UIReferences.CardsByTab) do
        ClearTab(tab)
    end
    CurrentSelectedCard = nil
    UpdateDetailView(nil)
    if IsMobileLayout then
        DetailPanel.Visible = false
    end
end)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -6, 0, 20)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 9
StatusLabel.TextColor3 = Color3.fromRGB(90, 210, 140)
StatusLabel.Text = "Status: Client-Side Listener Active (OnClientEvent & OnClientInvoke)"
StatusLabel.Parent = SettingsFrame

local HookedInstances = {}

local function HookRemote(instance)
    if not instance or typeof(instance) ~= "Instance" then return end
    if HookedInstances[instance] then return end
    HookedInstances[instance] = true

    if instance:IsA("RemoteEvent") then
        local fullPath = GetInstanceFullPath(instance)
        RemoteStats[fullPath] = (RemoteStats[fullPath] or 0)

        local conn
        local success, _ = pcall(function()
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

local function ScanAndBind(root)
    pcall(function()
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
                HookRemote(descendant)
            end
        end
    end)
end

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

local function OnViewportChanged()
    local vp = GetCurrentViewport()
    local targetSize = CalculateWindowSize(vp)
    if not isMinimized then
        MainWindow.Size = UDim2.new(0, targetSize.X, 0, targetSize.Y)
    else
        MainWindow.Size = UDim2.new(0, targetSize.X, 0, 34)
    end
    local currentPos = MainWindow.Position
    local clampedX = math.clamp(currentPos.X.Offset, 0, math.max(0, vp.X - targetSize.X))
    local clampedY = math.clamp(currentPos.Y.Offset, 0, math.max(0, vp.Y - (isMinimized and 34 or targetSize.Y)))
    MainWindow.Position = UDim2.new(0, clampedX, 0, clampedY)
    ApplyLayout()
end

if Camera then
    local vpConn = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(OnViewportChanged)
    table.insert(Connections, vpConn)
end

ApplyLayout()

ScreenGui.Destroying:Connect(function()
    for _, conn in ipairs(Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    table.clear(Connections)
    table.clear(HistoryData)
    table.clear(RemoteStats)
    table.clear(HookedInstances)
    table.clear(UIReferences.CardsByTab)
    table.clear(UIReferences.TabButtons)
    table.clear(UIReferences.TabFrames)
end)
