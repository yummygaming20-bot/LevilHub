local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local State = {
    ActiveTab = "ALL",
    SelectedEntry = nil,
    SearchQuery = "",
    IsMinimized = false,
    IsClosed = false,
    CallCounters = {},
    MonitoredRemotes = {},
    Connections = {},
    History = {},
    TabEntries = {
        ["ALL"] = {},
        ["REMOTE EVENT"] = {},
        ["REMOTE FUNCTION"] = {},
        ["HISTORY"] = {}
    }
}

local Settings = {
    AutoScroll = true,
    ShowTimestamp = true,
    ShowFullPath = true,
    MaxHistory = 500
}

local DefaultSettings = {
    AutoScroll = true,
    ShowTimestamp = true,
    ShowFullPath = true,
    MaxHistory = 500
}

local UI = {
    ScreenGui = nil,
    MainWindow = nil,
    FloatingBtn = nil,
    Header = nil,
    SearchBox = nil,
    DetailPanel = nil,
    DetailText = nil,
    DetailScroll = nil,
    TabButtons = {},
    TabFrames = {}
}

local ExecutorAPIs = {
    HasGetConnections = typeof(getconnections) == "function",
    HasNamecallHook = typeof(hookmetamethod) == "function",
    HasNamecallMethod = typeof(getnamecallmethod) == "function",
    HasClipboard = typeof(setclipboard) == "function" or typeof(toclipboard) == "function"
}

local HookState = {
    Installed = false,
    OldNamecall = nil,
    WrappedInvoke = {}
}

local function SafeSetClipboard(text)
    if typeof(setclipboard) == "function" then
        local ok = pcall(setclipboard, text)
        return ok
    end

    if typeof(toclipboard) == "function" then
        local ok = pcall(toclipboard, text)
        return ok
    end

    return false
end

local function GetTimestamp()
    local date = os.date("*t")
    return string.format(
        "%02d:%02d:%02d",
        date.hour,
        date.min,
        date.sec
    )
end

local function GetFullPath(instance)
    if not instance or typeof(instance) ~= "Instance" then
        return "Unknown"
    end

    local ok, result = pcall(function()
        return instance:GetFullName()
    end)

    if ok then
        return result
    end

    return tostring(instance)
end

local function TrackConnection(connection)
    if connection and typeof(connection) == "RBXScriptConnection" then
        table.insert(State.Connections, connection)
    end

    return connection
end

local FormatValue

local function FormatTableRecursive(tbl, indent, depth, visited)
    indent = indent or ""
    depth = depth or 1
    visited = visited or {}

    if depth > 5 then
        return indent .. "[MAX DEPTH]"
    end

    if visited[tbl] then
        return indent .. "[CIRCULAR REFERENCE]"
    end

    visited[tbl] = true

    local keys = {}

    for key in pairs(tbl) do
        table.insert(keys, key)
    end

    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    local lines = {}

    for index, key in ipairs(keys) do
        local value = tbl[key]
        local last = index == #keys

        local branch = last and "└── " or "├── "
        local nextIndent = indent .. (last and "    " or "│   ")

        local keyText = tostring(key)

        if type(key) == "number" then
            keyText = "[" .. keyText .. "]"
        end

        if type(value) == "table" then
            table.insert(
                lines,
                indent .. branch .. keyText
            )

            table.insert(
                lines,
                FormatTableRecursive(
                    value,
                    nextIndent,
                    depth + 1,
                    visited
                )
            )
        else
            table.insert(
                lines,
                indent
                    .. branch
                    .. keyText
                    .. " = "
                    .. FormatValue(
                        value,
                        nextIndent,
                        depth + 1,
                        visited,
                        true
                    )
            )
        end
    end

    visited[tbl] = nil

    if #lines == 0 then
        return indent .. "{}"
    end

    return table.concat(lines, "\n")
end

FormatValue = function(value, indent, depth, visited)
    indent = indent or ""
    depth = depth or 1
    visited = visited or {}

    local valueType = typeof(value)

    if valueType == "string" then
        return string.format("%q", value)
    end

    if valueType == "number" then
        return tostring(value)
    end

    if valueType == "boolean" then
        return tostring(value)
    end

    if valueType == "nil" then
        return "nil"
    end

    if valueType == "Instance" then
        return GetFullPath(value)
    end

    if valueType == "Vector2" then
        return string.format(
            "Vector2.new(%.3f, %.3f)",
            value.X,
            value.Y
        )
    end

    if valueType == "Vector3" then
        return string.format(
            "Vector3.new(%.3f, %.3f, %.3f)",
            value.X,
            value.Y,
            value.Z
        )
    end

    if valueType == "CFrame" then
        local position = value.Position

        return string.format(
            "CFrame.new(%.3f, %.3f, %.3f)",
            position.X,
            position.Y,
            position.Z
        )
    end

    if valueType == "Color3" then
        return string.format(
            "Color3.fromRGB(%d, %d, %d)",
            math.floor(value.R * 255 + 0.5),
            math.floor(value.G * 255 + 0.5),
            math.floor(value.B * 255 + 0.5)
        )
    end

    if valueType == "BrickColor" then
        return string.format(
            "BrickColor.new(%q)",
            value.Name
        )
    end

    if valueType == "EnumItem" then
        return tostring(value)
    end

    if valueType == "UDim2" then
        return string.format(
            "UDim2.new(%.3f, %d, %.3f, %d)",
            value.X.Scale,
            value.X.Offset,
            value.Y.Scale,
            value.Y.Offset
        )
    end

    if valueType == "Ray" then
        return "Ray.new("
            .. tostring(value.Origin)
            .. ", "
            .. tostring(value.Direction)
            .. ")"
    end

    if valueType == "table" then
        return "Table\n"
            .. FormatTableRecursive(
                value,
                indent,
                depth,
                visited
            )
    end

    return "[" .. valueType .. "] " .. tostring(value)
end

local function FormatArgsList(args)
    if not args or #args == 0 then
        return "None"
    end

    local result = {}

    for index, value in ipairs(args) do
        table.insert(
            result,
            string.format(
                "[%d] %s\n%s",
                index,
                typeof(value),
                FormatValue(value)
            )
        )
    end

    return table.concat(result, "\n\n")
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RemoteEventMonitor"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

UI.ScreenGui = ScreenGui

local FloatingBtn = Instance.new("TextButton")
FloatingBtn.Name = "FloatingReopenBtn"
FloatingBtn.Size = UDim2.new(0, 125, 0, 40)
FloatingBtn.Position = UDim2.new(0, 16, 0.5, -20)
FloatingBtn.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
FloatingBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatingBtn.Font = Enum.Font.GothamBold
FloatingBtn.TextSize = 12
FloatingBtn.Text = "[ REMOTE MONITOR ]"
FloatingBtn.Visible = false
FloatingBtn.ZIndex = 100
FloatingBtn.Parent = ScreenGui

UI.FloatingBtn = FloatingBtn

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(0, 8)
FloatCorner.Parent = FloatingBtn

local FloatStroke = Instance.new("UIStroke")
FloatStroke.Color = Color3.fromRGB(70, 75, 95)
FloatStroke.Thickness = 1
FloatStroke.Transparency = 0.3
FloatStroke.Parent = FloatingBtn

local FloatGrad = Instance.new("UIGradient")
FloatGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(
        0,
        Color3.fromRGB(40, 43, 54)
    ),
    ColorSequenceKeypoint.new(
        1,
        Color3.fromRGB(20, 22, 28)
    )
})
FloatGrad.Rotation = 45
FloatGrad.Parent = FloatingBtn

local MainWindow = Instance.new("Frame")
MainWindow.Name = "MainWindow"
MainWindow.Size = UDim2.new(0, 780, 0, 500)
MainWindow.Position = UDim2.new(0.5, -390, 0.5, -250)
MainWindow.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
MainWindow.BorderSizePixel = 0
MainWindow.ClipsDescendants = true
MainWindow.Parent = ScreenGui

UI.MainWindow = MainWindow

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 11)
MainCorner.Parent = MainWindow

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(65, 69, 85)
MainStroke.Thickness = 1
MainStroke.Transparency = 0.35
MainStroke.Parent = MainWindow

local MainGrad = Instance.new("UIGradient")
MainGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(
        0,
        Color3.fromRGB(25, 27, 34)
    ),
    ColorSequenceKeypoint.new(
        1,
        Color3.fromRGB(15, 16, 20)
    )
})
MainGrad.Rotation = 90
MainGrad.Parent = MainWindow

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 44)
Header.BackgroundColor3 = Color3.fromRGB(29, 31, 40)
Header.BorderSizePixel = 0
Header.Parent = MainWindow

UI.Header = Header

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 11)
HeaderCorner.Parent = Header

local HeaderTitle = Instance.new("TextLabel")
HeaderTitle.Size = UDim2.new(1, -145, 1, 0)
HeaderTitle.Position = UDim2.new(0, 15, 0, 0)
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.Font = Enum.Font.GothamBold
HeaderTitle.TextSize = 14
HeaderTitle.TextColor3 = Color3.fromRGB(245, 245, 250)
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
HeaderTitle.Text = "REMOTE EVENT MONITOR"
HeaderTitle.Parent = Header

local HeaderStatus = Instance.new("TextLabel")
HeaderStatus.Size = UDim2.new(0, 95, 1, 0)
HeaderStatus.Position = UDim2.new(1, -175, 0, 0)
HeaderStatus.BackgroundTransparency = 1
HeaderStatus.Font = Enum.Font.GothamMedium
HeaderStatus.TextSize = 9
HeaderStatus.TextColor3 = Color3.fromRGB(110, 220, 145)
HeaderStatus.TextXAlignment = Enum.TextXAlignment.Right
HeaderStatus.Text = "● MONITORING"
HeaderStatus.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 30, 0, 28)
CloseBtn.Position = UDim2.new(1, -38, 0, 8)
CloseBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 70)
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.Text = "×"
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

local MinBtn = Instance.new("TextButton")
MinBtn.Name = "MinBtn"
MinBtn.Size = UDim2.new(0, 30, 0, 28)
MinBtn.Position = UDim2.new(1, -74, 0, 8)
MinBtn.BackgroundColor3 = Color3.fromRGB(47, 50, 62)
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 15
MinBtn.Text = "−"
MinBtn.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinBtn

local NavFrame = Instance.new("Frame")
NavFrame.Name = "NavFrame"
NavFrame.Size = UDim2.new(1, -20, 0, 34)
NavFrame.Position = UDim2.new(0, 10, 0, 52)
NavFrame.BackgroundTransparency = 1
NavFrame.Parent = MainWindow

local NavLayout = Instance.new("UIListLayout")
NavLayout.FillDirection = Enum.FillDirection.Horizontal
NavLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
NavLayout.Padding = UDim.new(0, 5)
NavLayout.Parent = NavFrame

local SearchBox = Instance.new("TextBox")
SearchBox.Name = "SearchBox"
SearchBox.Size = UDim2.new(1, -20, 0, 34)
SearchBox.Position = UDim2.new(0, 10, 0, 92)
SearchBox.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
SearchBox.TextColor3 = Color3.fromRGB(240, 240, 245)
SearchBox.PlaceholderColor3 = Color3.fromRGB(125, 130, 145)
SearchBox.PlaceholderText = "Search remote, path, class, arguments..."
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 11
SearchBox.ClearTextOnFocus = false
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.Parent = MainWindow

UI.SearchBox = SearchBox

local SearchCorner = Instance.new("UICorner")
SearchCorner.CornerRadius = UDim.new(0, 7)
SearchCorner.Parent = SearchBox

local SearchPadding = Instance.new("UIPadding")
SearchPadding.PaddingLeft = UDim.new(0, 11)
SearchPadding.PaddingRight = UDim.new(0, 11)
SearchPadding.Parent = SearchBox

local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -290, 1, -144)
ContentArea.Position = UDim2.new(0, 10, 0, 134)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainWindow

local DetailPanel = Instance.new("Frame")
DetailPanel.Name = "DetailPanel"
DetailPanel.Size = UDim2.new(0, 270, 1, -144)
DetailPanel.Position = UDim2.new(1, -280, 0, 134)
DetailPanel.BackgroundColor3 = Color3.fromRGB(23, 25, 32)
DetailPanel.BorderSizePixel = 0
DetailPanel.Parent = MainWindow

UI.DetailPanel = DetailPanel

local DetailCorner = Instance.new("UICorner")
DetailCorner.CornerRadius = UDim.new(0, 8)
DetailCorner.Parent = DetailPanel

local DetailHeader = Instance.new("TextLabel")
DetailHeader.Size = UDim2.new(1, -20, 0, 28)
DetailHeader.Position = UDim2.new(0, 10, 0, 7)
DetailHeader.BackgroundTransparency = 1
DetailHeader.Font = Enum.Font.GothamBold
DetailHeader.TextSize = 12
DetailHeader.TextColor3 = Color3.fromRGB(250, 250, 255)
DetailHeader.TextXAlignment = Enum.TextXAlignment.Left
DetailHeader.Text = "REMOTE DETAILS"
DetailHeader.Parent = DetailPanel

local DetailSubHeader = Instance.new("TextLabel")
DetailSubHeader.Size = UDim2.new(1, -20, 0, 18)
DetailSubHeader.Position = UDim2.new(0, 10, 0, 30)
DetailSubHeader.BackgroundTransparency = 1
DetailSubHeader.Font = Enum.Font.Gotham
DetailSubHeader.TextSize = 9
DetailSubHeader.TextColor3 = Color3.fromRGB(120, 125, 140)
DetailSubHeader.TextXAlignment = Enum.TextXAlignment.Left
DetailSubHeader.Text = "Select a remote"
DetailSubHeader.Parent = DetailPanel

local DetailScroll = Instance.new("ScrollingFrame")
DetailScroll.Name = "DetailScroll"
DetailScroll.Size = UDim2.new(1, -18, 1, -92)
DetailScroll.Position = UDim2.new(0, 9, 0, 51)
DetailScroll.BackgroundTransparency = 1
DetailScroll.BorderSizePixel = 0
DetailScroll.ScrollBarThickness = 4
DetailScroll.ScrollBarImageColor3 = Color3.fromRGB(70, 74, 90)
DetailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
DetailScroll.Parent = DetailPanel

UI.DetailScroll = DetailScroll

local DetailText = Instance.new("TextLabel")
DetailText.Name = "DetailContent"
DetailText.Size = UDim2.new(1, -8, 0, 0)
DetailText.Position = UDim2.new(0, 4, 0, 0)
DetailText.BackgroundTransparency = 1
DetailText.Font = Enum.Font.Gotham
DetailText.TextSize = 10
DetailText.TextColor3 = Color3.fromRGB(210, 215, 225)
DetailText.TextXAlignment = Enum.TextXAlignment.Left
DetailText.TextYAlignment = Enum.TextYAlignment.Top
DetailText.TextWrapped = true
DetailText.Text = "Select an event from the list to view its complete details."
DetailText.Parent = DetailScroll

UI.DetailText = DetailText

local ActionBtnFrame = Instance.new("Frame")
ActionBtnFrame.Size = UDim2.new(1, -18, 0, 34)
ActionBtnFrame.Position = UDim2.new(0, 9, 1, -42)
ActionBtnFrame.BackgroundTransparency = 1
ActionBtnFrame.Parent = DetailPanel

local ActionLayout = Instance.new("UIListLayout")
ActionLayout.FillDirection = Enum.FillDirection.Horizontal
ActionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
ActionLayout.Padding = UDim.new(0, 5)
ActionLayout.Parent = ActionBtnFrame

local function CreateActionButton(name, text)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = UDim2.new(0.31, 0, 1, 0)
    button.BackgroundColor3 = Color3.fromRGB(39, 43, 55)
    button.TextColor3 = Color3.fromRGB(240, 240, 245)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 8
    button.Text = text
    button.AutoButtonColor = false
    button.Parent = ActionBtnFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = button

    return button
end

local CopyNameBtn = CreateActionButton(
    "CopyNameBtn",
    "COPY NAME"
)

local CopyPathBtn = CreateActionButton(
    "CopyPathBtn",
    "COPY PATH"
)

local CopyReqBtn = CreateActionButton(
    "CopyReqBtn",
    "COPY REQ"
)

local TabList = {
    "ALL",
    "REMOTE EVENT",
    "REMOTE FUNCTION",
    "HISTORY",
    "SETTINGS"
}

for _, tabName in ipairs(TabList) do
    local tabButton = Instance.new("TextButton")
    tabButton.Name = tabName .. "_Btn"
    tabButton.Size = UDim2.new(0, 114, 1, 0)
    tabButton.BackgroundColor3 =
        tabName == State.ActiveTab
        and Color3.fromRGB(49, 53, 69)
        or Color3.fromRGB(28, 30, 38)
    tabButton.TextColor3 = Color3.fromRGB(240, 240, 250)
    tabButton.Font = Enum.Font.GothamBold
    tabButton.TextSize = 9
    tabButton.Text = tabName
    tabButton.AutoButtonColor = false
    tabButton.Parent = NavFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = tabButton

    UI.TabButtons[tabName] = tabButton

    local tabFrame = Instance.new("ScrollingFrame")
    tabFrame.Name = tabName .. "_Frame"
    tabFrame.Size = UDim2.new(1, 0, 1, 0)
    tabFrame.BackgroundTransparency = 1
    tabFrame.BorderSizePixel = 0
    tabFrame.ScrollBarThickness = 5
    tabFrame.ScrollBarImageColor3 = Color3.fromRGB(65, 69, 84)
    tabFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabFrame.Visible = tabName == State.ActiveTab
    tabFrame.Parent = ContentArea

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = tabFrame

    layout:GetPropertyChangedSignal(
        "AbsoluteContentSize"
    ):Connect(function()
        tabFrame.CanvasSize = UDim2.new(
            0,
            0,
            0,
            layout.AbsoluteContentSize.Y + 12
        )
    end)

    UI.TabFrames[tabName] = tabFrame
end

local function CreateSettingToggleRow(title, defaultValue, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 40)
    row.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
    row.Parent = UI.TabFrames["SETTINGS"]

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = row

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextColor3 = Color3.fromRGB(230, 230, 240)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = title
    label.Parent = row

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 64, 0, 26)
    toggle.Position = UDim2.new(1, -76, 0.5, -13)
    toggle.BackgroundColor3 =
        defaultValue
        and Color3.fromRGB(50, 150, 80)
        or Color3.fromRGB(65, 68, 80)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 10
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.Text = defaultValue and "ON" or "OFF"
    toggle.AutoButtonColor = false
    toggle.Parent = row

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 5)
    toggleCorner.Parent = toggle

    local current = defaultValue

    toggle.MouseButton1Click:Connect(function()
        current = not current

        toggle.Text = current and "ON" or "OFF"

        TweenService:Create(
            toggle,
            TweenInfo.new(0.15),
            {
                BackgroundColor3 =
                    current
                    and Color3.fromRGB(50, 150, 80)
                    or Color3.fromRGB(65, 68, 80)
            }
        ):Play()

        callback(current)
    end)

    return {
        Set = function(value)
            current = value
            toggle.Text = value and "ON" or "OFF"
            toggle.BackgroundColor3 =
                value
                and Color3.fromRGB(50, 150, 80)
                or Color3.fromRGB(65, 68, 80)
        end
    }
end

local SettingsScroll = UI.TabFrames["SETTINGS"]

local AutoScrollRow = CreateSettingToggleRow(
    "Auto Scroll to New Events",
    Settings.AutoScroll,
    function(value)
        Settings.AutoScroll = value
    end
)

local TimestampRow = CreateSettingToggleRow(
    "Show Timestamps on Cards",
    Settings.ShowTimestamp,
    function(value)
        Settings.ShowTimestamp = value
    end
)

local FullPathRow = CreateSettingToggleRow(
    "Show Full Path on Cards",
    Settings.ShowFullPath,
    function(value)
        Settings.ShowFullPath = value
    end
)

local MaxHistoryRow = Instance.new("Frame")
MaxHistoryRow.Size = UDim2.new(1, -8, 0, 40)
MaxHistoryRow.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
MaxHistoryRow.Parent = SettingsScroll

local MaxHistoryCorner = Instance.new("UICorner")
MaxHistoryCorner.CornerRadius = UDim.new(0, 6)
MaxHistoryCorner.Parent = MaxHistoryRow

local MaxHistoryLabel = Instance.new("TextLabel")
MaxHistoryLabel.Size = UDim2.new(0.65, 0, 1, 0)
MaxHistoryLabel.Position = UDim2.new(0, 12, 0, 0)
MaxHistoryLabel.BackgroundTransparency = 1
MaxHistoryLabel.Font = Enum.Font.Gotham
MaxHistoryLabel.TextSize = 11
MaxHistoryLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
MaxHistoryLabel.TextXAlignment = Enum.TextXAlignment.Left
MaxHistoryLabel.Text = "Max History Limit"
MaxHistoryLabel.Parent = MaxHistoryRow

local MaxHistoryInput = Instance.new("TextBox")
MaxHistoryInput.Size = UDim2.new(0, 76, 0, 26)
MaxHistoryInput.Position = UDim2.new(1, -88, 0.5, -13)
MaxHistoryInput.BackgroundColor3 = Color3.fromRGB(38, 42, 54)
MaxHistoryInput.TextColor3 = Color3.fromRGB(255, 255, 255)
MaxHistoryInput.Font = Enum.Font.GothamBold
MaxHistoryInput.TextSize = 10
MaxHistoryInput.Text = tostring(Settings.MaxHistory)
MaxHistoryInput.ClearTextOnFocus = false
MaxHistoryInput.Parent = MaxHistoryRow

local MaxHistoryInputCorner = Instance.new("UICorner")
MaxHistoryInputCorner.CornerRadius = UDim.new(0, 5)
MaxHistoryInputCorner.Parent = MaxHistoryInput

MaxHistoryInput.FocusLost:Connect(function()
    local number = tonumber(MaxHistoryInput.Text)

    if number and number >= 10 and number <= 2000 then
        Settings.MaxHistory = math.floor(number)
    else
        MaxHistoryInput.Text = tostring(Settings.MaxHistory)
    end
end)

local function CreateSettingsButton(text, color, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -8, 0, 36)
    button.BackgroundColor3 = color
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 10
    button.Text = text
    button.AutoButtonColor = false
    button.Parent = SettingsScroll

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button

    button.MouseButton1Click:Connect(callback)

    return button
end

local function UpdateDetailPanel(entry)
    State.SelectedEntry = entry

    if not entry then
        DetailSubHeader.Text = "Select a remote"

        DetailText.Text =
            "Select an event from the list to view its complete details."

        DetailScroll.CanvasSize =
            UDim2.new(0, 0, 0, 0)

        return
    end

    DetailSubHeader.Text =
        entry.Class .. "  •  " .. entry.Name

    local lines = {}

    table.insert(lines, "NAME\n")
    table.insert(lines, entry.Name)
    table.insert(lines, "\n\n")

    table.insert(lines, "CLASS\n")
    table.insert(lines, entry.Class)
    table.insert(lines, "\n\n")

    table.insert(lines, "PATH\n")
    table.insert(lines, entry.Path)
    table.insert(lines, "\n\n")

    table.insert(lines, "CALL COUNT\n")
    table.insert(lines, tostring(entry.CallCount or 1))
    table.insert(lines, "\n\n")

    table.insert(lines, "TIMESTAMP\n")
    table.insert(lines, entry.Timestamp or "Unknown")
    table.insert(lines, "\n\n")

    table.insert(lines, "REQUEST\n\n")
    table.insert(lines, FormatArgsList(entry.Args))

    if entry.Class == "RemoteFunction" then
        table.insert(lines, "\n\nRETURN\n\n")

        if entry.ReturnValue ~= nil then
            table.insert(
                lines,
                FormatValue(entry.ReturnValue)
            )
        else
            table.insert(lines, "None")
        end
    end

    local fullText = table.concat(lines)

    DetailText.Text = fullText

    task.defer(function()
        local width = math.max(
            100,
            DetailScroll.AbsoluteSize.X - 14
        )

        local bounds = TextService:GetTextSize(
            fullText,
            10,
            Enum.Font.Gotham,
            Vector2.new(width, 100000)
        )

        DetailText.Size =
            UDim2.new(1, -8, 0, bounds.Y + 10)

        DetailScroll.CanvasSize =
            UDim2.new(0, 0, 0, bounds.Y + 20)
    end)
end

CopyNameBtn.MouseButton1Click:Connect(function()
    if State.SelectedEntry then
        SafeSetClipboard(
            State.SelectedEntry.Name
        )
    end
end)

CopyPathBtn.MouseButton1Click:Connect(function()
    if State.SelectedEntry then
        SafeSetClipboard(
            State.SelectedEntry.Path
        )
    end
end)

CopyReqBtn.MouseButton1Click:Connect(function()
    if State.SelectedEntry then
        SafeSetClipboard(
            FormatArgsList(
                State.SelectedEntry.Args
            )
        )
    end
end)

local function CreateRemoteCard(entry, parent)
    local card = Instance.new("TextButton")
    card.Name = "Card"
    card.Size = UDim2.new(1, -6, 0, 82)
    card.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
    card.Text = ""
    card.AutoButtonColor = false
    card.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 7)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(55, 59, 73)
    stroke.Transparency = 0.6
    stroke.Thickness = 1
    stroke.Parent = card

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.PaddingTop = UDim.new(0, 7)
    padding.PaddingBottom = UDim.new(0, 7)
    padding.Parent = card

    local classLabel = Instance.new("TextLabel")
    classLabel.Size = UDim2.new(0.6, 0, 0, 16)
    classLabel.BackgroundTransparency = 1
    classLabel.Font = Enum.Font.GothamBold
    classLabel.TextSize = 10
    classLabel.TextXAlignment = Enum.TextXAlignment.Left
    classLabel.TextColor3 =
        entry.Class == "RemoteEvent"
        and Color3.fromRGB(75, 165, 245)
        or Color3.fromRGB(245, 165, 75)

    classLabel.Text =
        entry.Class
        .. "  •  "
        .. tostring(entry.CallCount or 1)
        .. " calls"

    classLabel.Parent = card

    local timeLabel = Instance.new("TextLabel")
    timeLabel.Size = UDim2.new(0.4, 0, 0, 16)
    timeLabel.Position = UDim2.new(0.6, 0, 0, 0)
    timeLabel.BackgroundTransparency = 1
    timeLabel.Font = Enum.Font.Gotham
    timeLabel.TextSize = 9
    timeLabel.TextColor3 = Color3.fromRGB(135, 140, 155)
    timeLabel.TextXAlignment = Enum.TextXAlignment.Right
    timeLabel.Text =
        Settings.ShowTimestamp
        and entry.Timestamp
        or ""

    timeLabel.Parent = card

    local pathLabel = Instance.new("TextLabel")
    pathLabel.Size = UDim2.new(1, 0, 0, 17)
    pathLabel.Position = UDim2.new(0, 0, 0, 19)
    pathLabel.BackgroundTransparency = 1
    pathLabel.Font = Enum.Font.GothamMedium
    pathLabel.TextSize = 10
    pathLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
    pathLabel.TextXAlignment = Enum.TextXAlignment.Left
    pathLabel.TextTruncate = Enum.TextTruncate.AtEnd

    pathLabel.Text =
        Settings.ShowFullPath
        and entry.Path
        or entry.Name

    pathLabel.Parent = card

    local argsLabel = Instance.new("TextLabel")
    argsLabel.Size = UDim2.new(1, 0, 0, 27)
    argsLabel.Position = UDim2.new(0, 0, 0, 40)
    argsLabel.BackgroundTransparency = 1
    argsLabel.Font = Enum.Font.Gotham
    argsLabel.TextSize = 9
    argsLabel.TextColor3 = Color3.fromRGB(155, 160, 175)
    argsLabel.TextXAlignment = Enum.TextXAlignment.Left
    argsLabel.TextTruncate = Enum.TextTruncate.AtEnd

    if #entry.Args == 0 then
        argsLabel.Text = "Request: None"
    else
        local preview = {}

        for index, value in ipairs(entry.Args) do
            local valueText

            if typeof(value) == "string" then
                valueText = string.format(
                    "%q",
                    value
                )
            else
                valueText = tostring(value)
            end

            table.insert(
                preview,
                string.format(
                    "[%d] %s",
                    index,
                    valueText
                )
            )

            if index >= 3 then
                table.insert(preview, "...")
                break
            end
        end

        argsLabel.Text =
            "Request: "
            .. table.concat(preview, "  ")
    end

    argsLabel.Parent = card

    card.MouseEnter:Connect(function()
        TweenService:Create(
            card,
            TweenInfo.new(0.12),
            {
                BackgroundColor3 =
                    Color3.fromRGB(31, 34, 44)
            }
        ):Play()
    end)

    card.MouseLeave:Connect(function()
        TweenService:Create(
            card,
            TweenInfo.new(0.12),
            {
                BackgroundColor3 =
                    Color3.fromRGB(24, 26, 33)
            }
        ):Play()
    end)

    card.MouseButton1Click:Connect(function()
        UpdateDetailPanel(entry)

        TweenService:Create(
            DetailPanel,
            TweenInfo.new(
                0.12,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            ),
            {
                BackgroundColor3 =
                    Color3.fromRGB(27, 29, 37)
            }
        ):Play()

        task.delay(0.14, function()
            TweenService:Create(
                DetailPanel,
                TweenInfo.new(0.12),
                {
                    BackgroundColor3 =
                        Color3.fromRGB(23, 25, 32)
                }
            ):Play()
        end)
    end)

    return card
end

local function PassesFilter(entry, query)
    if not query or query == "" then
        return true
    end

    query = string.lower(query)

    if string.find(
        string.lower(entry.Name),
        query,
        1,
        true
    ) then
        return true
    end

    if string.find(
        string.lower(entry.Path),
        query,
        1,
        true
    ) then
        return true
    end

    if string.find(
        string.lower(entry.Class),
        query,
        1,
        true
    ) then
        return true
    end

    for _, argument in ipairs(entry.Args) do
        local value = string.lower(
            tostring(argument)
        )

        local argumentType = string.lower(
            typeof(argument)
        )

        if string.find(
            value,
            query,
            1,
            true
        ) then
            return true
        end

        if string.find(
            argumentType,
            query,
            1,
            true
        ) then
            return true
        end
    end

    return false
end

local function ClearCards(frame)
    if not frame then
        return
    end

    for _, child in ipairs(frame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
end

local function RebuildTabUI(tabName)
    local frame = UI.TabFrames[tabName]

    if not frame or tabName == "SETTINGS" then
        return
    end

    ClearCards(frame)

    local entries

    if tabName == "HISTORY" then
        entries = State.History
    else
        entries = State.TabEntries[tabName]
    end

    if not entries then
        return
    end

    for _, entry in ipairs(entries) do
        if PassesFilter(
            entry,
            State.SearchQuery
        ) then
            CreateRemoteCard(
                entry,
                frame
            )
        end
    end

    task.defer(function()
        local layout =
            frame:FindFirstChildOfClass(
                "UIListLayout"
            )

        if not layout then
            return
        end

        frame.CanvasSize =
            UDim2.new(
                0,
                0,
                0,
                layout.AbsoluteContentSize.Y + 12
            )

        if Settings.AutoScroll
            and tabName == State.ActiveTab then

            frame.CanvasPosition =
                Vector2.new(
                    0,
                    math.max(
                        0,
                        layout.AbsoluteContentSize.Y
                            - frame.AbsoluteSize.Y
                            + 20
                    )
                )
        end
    end)
end

local function RefreshAllTabs()
    RebuildTabUI("ALL")
    RebuildTabUI("REMOTE EVENT")
    RebuildTabUI("REMOTE FUNCTION")
    RebuildTabUI("HISTORY")
end

local function RecordEvent(
    instance,
    classType,
    args,
    returnValue
)
    if not instance then
        return
    end

    local path = GetFullPath(instance)
    local name = instance.Name

    State.CallCounters[instance] =
        (State.CallCounters[instance] or 0) + 1

    local entry = {
        Instance = instance,
        Name = name,
        Class = classType,
        Path = path,
        Timestamp = GetTimestamp(),
        CallCount = State.CallCounters[instance],
        Args = args or {},
        ReturnValue = returnValue
    }

    table.insert(
        State.History,
        entry
    )

    if #State.History > Settings.MaxHistory then
        table.remove(
            State.History,
            1
        )
    end

    table.insert(
        State.TabEntries["ALL"],
        entry
    )

    if #State.TabEntries["ALL"]
        > Settings.MaxHistory then

        table.remove(
            State.TabEntries["ALL"],
            1
        )
    end

    if classType == "RemoteEvent" then
        table.insert(
            State.TabEntries["REMOTE EVENT"],
            entry
        )

        if #State.TabEntries["REMOTE EVENT"]
            > Settings.MaxHistory then

            table.remove(
                State.TabEntries["REMOTE EVENT"],
                1
            )
        end

    elseif classType == "RemoteFunction" then
        table.insert(
            State.TabEntries["REMOTE FUNCTION"],
            entry
        )

        if #State.TabEntries["REMOTE FUNCTION"]
            > Settings.MaxHistory then

            table.remove(
                State.TabEntries["REMOTE FUNCTION"],
                1
            )
        end
    end

    if PassesFilter(
        entry,
        State.SearchQuery
    ) then

        local activeTab =
            State.ActiveTab

        local shouldShow =
            activeTab == "ALL"
            or activeTab == "HISTORY"
            or (
                activeTab == "REMOTE EVENT"
                and classType == "RemoteEvent"
            )
            or (
                activeTab == "REMOTE FUNCTION"
                and classType == "RemoteFunction"
            )

        if shouldShow then
            local frame =
                UI.TabFrames[activeTab]

            if frame then
                CreateRemoteCard(
                    entry,
                    frame
                )

                task.defer(function()
                    if not Settings.AutoScroll then
                        return
                    end

                    local layout =
                        frame:FindFirstChildOfClass(
                            "UIListLayout"
                        )

                    if layout then
                        frame.CanvasPosition =
                            Vector2.new(
                                0,
                                math.max(
                                    0,
                                    layout.AbsoluteContentSize.Y
                                        - frame.AbsoluteSize.Y
                                        + 20
                                )
                            )
                    end
                end)
            end
        end
    end
end

CreateSettingsButton(
    "Clear All History",
    Color3.fromRGB(145, 45, 52),
    function()
        table.clear(State.History)
        table.clear(State.TabEntries["ALL"])
        table.clear(State.TabEntries["REMOTE EVENT"])
        table.clear(State.TabEntries["REMOTE FUNCTION"])

        RefreshAllTabs()

        UpdateDetailPanel(nil)
    end
)

CreateSettingsButton(
    "Clear Current Tab",
    Color3.fromRGB(130, 85, 45),
    function()
        if State.ActiveTab == "SETTINGS" then
            return
        end

        if State.ActiveTab == "HISTORY" then
            table.clear(State.History)
        elseif State.TabEntries[State.ActiveTab] then
            table.clear(
                State.TabEntries[State.ActiveTab]
            )
        end

        RebuildTabUI(
            State.ActiveTab
        )

        UpdateDetailPanel(nil)
    end
)

CreateSettingsButton(
    "Reset Settings to Default",
    Color3.fromRGB(48, 52, 68),
    function()
        Settings.AutoScroll =
            DefaultSettings.AutoScroll

        Settings.ShowTimestamp =
            DefaultSettings.ShowTimestamp

        Settings.ShowFullPath =
            DefaultSettings.ShowFullPath

        Settings.MaxHistory =
            DefaultSettings.MaxHistory

        AutoScrollRow.Set(
            Settings.AutoScroll
        )

        TimestampRow.Set(
            Settings.ShowTimestamp
        )

        FullPathRow.Set(
            Settings.ShowFullPath
        )

        MaxHistoryInput.Text =
            tostring(Settings.MaxHistory)

        RefreshAllTabs()
    end
)

local SearchThread

SearchBox:GetPropertyChangedSignal(
    "Text"
):Connect(function()
    State.SearchQuery =
        SearchBox.Text

    if SearchThread then
        task.cancel(SearchThread)
    end

    SearchThread = task.delay(
        0.18,
        function()
            RebuildTabUI(
                State.ActiveTab
            )
        end
    )
end)

local function SwitchTab(tabName)
    State.ActiveTab = tabName

    for name, frame in pairs(
        UI.TabFrames
    ) do
        frame.Visible =
            name == tabName
    end

    for name, button in pairs(
        UI.TabButtons
    ) do
        local target =
            name == tabName
            and Color3.fromRGB(49, 53, 69)
            or Color3.fromRGB(28, 30, 38)

        TweenService:Create(
            button,
            TweenInfo.new(0.15),
            {
                BackgroundColor3 = target
            }
        ):Play()
    end

    if tabName ~= "SETTINGS" then
        RebuildTabUI(tabName)
    end
end

local function AttachPressAnimation(button)
    button.InputBegan:Connect(function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
            or input.UserInputType
            == Enum.UserInputType.Touch then

            TweenService:Create(
                button,
                TweenInfo.new(0.08),
                {
                    BackgroundTransparency = 0.2
                }
            ):Play()
        end
    end)

    button.InputEnded:Connect(function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
            or input.UserInputType
            == Enum.UserInputType.Touch then

            TweenService:Create(
                button,
                TweenInfo.new(0.12),
                {
                    BackgroundTransparency = 0
                }
            ):Play()
        end
    end)
end

for name, button in pairs(
    UI.TabButtons
) do
    AttachPressAnimation(button)

    button.MouseButton1Click:Connect(function()
        SwitchTab(name)
    end)
end

AttachPressAnimation(CloseBtn)
AttachPressAnimation(MinBtn)
AttachPressAnimation(FloatingBtn)

local isDragging = false
local dragStart
local frameStart

Header.InputBegan:Connect(function(input)
    if input.UserInputType
        ~= Enum.UserInputType.MouseButton1
        and input.UserInputType
        ~= Enum.UserInputType.Touch then

        return
    end

    isDragging = true
    dragStart = input.Position
    frameStart = MainWindow.Position

    local connection

    connection = input.Changed:Connect(function()
        if input.UserInputState
            == Enum.UserInputState.End then

            isDragging = false

            if connection then
                connection:Disconnect()
            end
        end
    end)
end)

TrackConnection(
    UserInputService.InputChanged:Connect(function(input)
        if not isDragging then
            return
        end

        if input.UserInputType
            ~= Enum.UserInputType.MouseMovement
            and input.UserInputType
            ~= Enum.UserInputType.Touch then

            return
        end

        local delta =
            input.Position - dragStart

        MainWindow.Position =
            UDim2.new(
                frameStart.X.Scale,
                frameStart.X.Offset + delta.X,
                frameStart.Y.Scale,
                frameStart.Y.Offset + delta.Y
            )
    end)
)

local OriginalSize =
    MainWindow.Size

local function AnimateWindowOpen()
    State.IsClosed = false

    FloatingBtn.Visible = false
    MainWindow.Visible = true

    if State.IsMinimized then
        State.IsMinimized = false
    end

    MainWindow.Size =
        UDim2.new(
            0,
            OriginalSize.X.Offset * 0.88,
            0,
            OriginalSize.Y.Offset * 0.88
        )

    MainWindow.BackgroundTransparency = 1

    TweenService:Create(
        MainWindow,
        TweenInfo.new(
            0.25,
            Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out
        ),
        {
            Size = OriginalSize,
            BackgroundTransparency = 0
        }
    ):Play()
end

local function AnimateWindowClose()
    State.IsClosed = true

    local tween =
        TweenService:Create(
            MainWindow,
            TweenInfo.new(
                0.2,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.In
            ),
            {
                Size =
                    UDim2.new(
                        0,
                        OriginalSize.X.Offset * 0.88,
                        0,
                        OriginalSize.Y.Offset * 0.88
                    ),
                BackgroundTransparency = 1
            }
        )

    tween:Play()

    tween.Completed:Connect(function()
        if State.IsClosed then
            MainWindow.Visible = false
            FloatingBtn.Visible = true
        end
    end)
end

CloseBtn.MouseButton1Click:Connect(
    AnimateWindowClose
)

FloatingBtn.MouseButton1Click:Connect(
    AnimateWindowOpen
)

MinBtn.MouseButton1Click:Connect(function()
    State.IsMinimized =
        not State.IsMinimized

    local targetHeight =
        State.IsMinimized
        and 44
        or OriginalSize.Y.Offset

    TweenService:Create(
        MainWindow,
        TweenInfo.new(
            0.22,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        ),
        {
            Size =
                UDim2.new(
                    0,
                    OriginalSize.X.Offset,
                    0,
                    targetHeight
                )
        }
    ):Play()
end)

local function SafeRecord(
    instance,
    classType,
    args,
    returnValue
)
    if not instance then
        return
    end

    task.spawn(function()
        pcall(function()
            RecordEvent(
                instance,
                classType,
                args or {},
                returnValue
            )
        end)
    end)
end

local function HookRemoteInstance(instance)
    if not instance then
        return
    end

    if State.MonitoredRemotes[instance] then
        return
    end

    if not (
        instance:IsA("RemoteEvent")
        or instance:IsA("RemoteFunction")
    ) then
        return
    end

    State.MonitoredRemotes[instance] = true

    if instance:IsA("RemoteEvent") then
        local ok, connection =
            pcall(function()
                return instance.OnClientEvent:Connect(
                    function(...)
                        SafeRecord(
                            instance,
                            "RemoteEvent",
                            {...},
                            nil
                        )
                    end
                )
            end)

        if ok and connection then
            TrackConnection(connection)
        end
    end

    if instance:IsA("RemoteFunction") then
        pcall(function()
            local original =
                instance.OnClientInvoke

            if typeof(original) ~= "function" then
                return
            end

            if HookState.WrappedInvoke[instance] then
                return
            end

            HookState.WrappedInvoke[instance] = true

            instance.OnClientInvoke =
                function(...)
                    local args = {...}

                    local packed =
                        table.pack(
                            original(...)
                        )

                    local returnValue

                    if packed.n == 0 then
                        returnValue = nil
                    elseif packed.n == 1 then
                        returnValue = packed[1]
                    else
                        returnValue = {}

                        for i = 1, packed.n do
                            returnValue[i] =
                                packed[i]
                        end
                    end

                    SafeRecord(
                        instance,
                        "RemoteFunction",
                        args,
                        returnValue
                    )

                    return table.unpack(
                        packed,
                        1,
                        packed.n
                    )
                end
        end)
    end
end

local function InstallNamecallMonitor()
    if HookState.Installed then
        return true
    end

    if not ExecutorAPIs.HasNamecallHook
        or not ExecutorAPIs.HasNamecallMethod then

        return false
    end

    local success, old =
        pcall(function()
            return hookmetamethod(
                game,
                "__namecall",
                function(self, ...)
                    local method =
                        getnamecallmethod()

                    local isRemote =
                        typeof(self)
                        == "Instance"
                        and (
                            self:IsA("RemoteEvent")
                            or self:IsA("RemoteFunction")
                        )

                    if isRemote then
                        if method == "FireServer" then
                            SafeRecord(
                                self,
                                "RemoteEvent",
                                {...},
                                nil
                            )
                        elseif method == "InvokeServer" then
                            local args = {...}

                            local packed =
                                table.pack(
                                    old(
                                        self,
                                        ...
                                    )
                                )

                            local returnValue

                            if packed.n == 0 then
                                returnValue = nil
                            elseif packed.n == 1 then
                                returnValue = packed[1]
                            else
                                returnValue = {}

                                for i = 1, packed.n do
                                    returnValue[i] =
                                        packed[i]
                                end
                            end

                            SafeRecord(
                                self,
                                "RemoteFunction",
                                args,
                                returnValue
                            )

                            return table.unpack(
                                packed,
                                1,
                                packed.n
                            )
                        end
                    end

                    return old(
                        self,
                        ...
                    )
                end
            )
        end)

    if not success or not old then
        return false
    end

    HookState.OldNamecall = old
    HookState.Installed = true

    return true
end

local function ScanAndObserve(container)
    if not container then
        return
    end

    pcall(function()
        for _, descendant in ipairs(
            container:GetDescendants()
        ) do
            if descendant:IsA("RemoteEvent")
                or descendant:IsA("RemoteFunction") then

                HookRemoteInstance(
                    descendant
                )
            end
        end

        local connection =
            container.DescendantAdded:Connect(
                function(descendant)
                    if descendant:IsA("RemoteEvent")
                        or descendant:IsA("RemoteFunction") then

                        HookRemoteInstance(
                            descendant
                        )
                    end
                end
            )

        TrackConnection(connection)
    end)
end

local function Cleanup()
    for _, connection in ipairs(
        State.Connections
    ) do
        if connection
            and typeof(connection)
            == "RBXScriptConnection" then

            pcall(function()
                connection:Disconnect()
            end)
        end
    end

    table.clear(
        State.Connections
    )

    table.clear(
        State.History
    )

    table.clear(
        State.MonitoredRemotes
    )

    table.clear(
        State.CallCounters
    )

    table.clear(
        HookState.WrappedInvoke
    )

    for _, entries in pairs(
        State.TabEntries
    ) do
        table.clear(entries)
    end
end

ScreenGui.Destroying:Connect(
    Cleanup
)

local HookInstalled =
    InstallNamecallMonitor()

ScanAndObserve(
    ReplicatedStorage
)

pcall(function()
    ScanAndObserve(
        game:GetService("JointsService")
    )
end)

pcall(function()
    if Players.LocalPlayer then
        ScanAndObserve(
            Players.LocalPlayer
        )
    end
end)

local StatusNotice = Instance.new("TextLabel")
StatusNotice.Name = "StatusNotice"
StatusNotice.Size = UDim2.new(1, -8, 0, 44)
StatusNotice.BackgroundColor3 =
    HookInstalled
    and Color3.fromRGB(25, 55, 38)
    or Color3.fromRGB(60, 45, 20)
StatusNotice.TextColor3 =
    HookInstalled
    and Color3.fromRGB(120, 220, 155)
    or Color3.fromRGB(240, 200, 100)
StatusNotice.Font = Enum.Font.GothamMedium
StatusNotice.TextSize = 10
StatusNotice.TextWrapped = true
StatusNotice.Text =
    HookInstalled
    and "Monitor active • FireServer / InvokeServer + incoming remotes"
    or "Outgoing monitor unavailable • OnClientEvent / OnClientInvoke observer active"
StatusNotice.Parent = SettingsScroll

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusNotice

SwitchTab("ALL")
AnimateWindowOpen()