local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local ContentProvider = game:GetService("ContentProvider")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local coreGui = game:GetService("CoreGui")

pcall(function()
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

local oldGui = coreGui:FindFirstChild("HorrorPrank")
if oldGui then
    oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HorrorPrank"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 999999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = coreGui

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
bg.BackgroundTransparency = 0
bg.BorderSizePixel = 0
bg.ZIndex = 1
bg.Parent = screenGui

local vignette = Instance.new("ImageLabel")
vignette.Name = "Vignette"
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.Image = "rbxassetid://5700609574"
vignette.ImageTransparency = 0.85
vignette.ScaleType = Enum.ScaleType.Stretch
vignette.ZIndex = 5
vignette.Parent = screenGui

local ghostImages = {
    "rbxassetid://5270095529",
    "rbxassetid://1440961961",
    "rbxassetid://84004216446762",
}

local ghostLayer = Instance.new("Frame")
ghostLayer.Name = "GhostLayer"
ghostLayer.Size = UDim2.fromScale(1, 1)
ghostLayer.BackgroundTransparency = 1
ghostLayer.BorderSizePixel = 0
ghostLayer.ClipsDescendants = true
ghostLayer.ZIndex = 10
ghostLayer.Parent = screenGui

local validImages = {}

for _, assetId in ipairs(ghostImages) do
    local test = Instance.new("ImageLabel")
    test.Size = UDim2.fromScale(1, 1)
    test.BackgroundTransparency = 1
    test.Image = assetId
    test.Visible = false
    test.Parent = ghostLayer

    local loaded = false

    pcall(function()
        ContentProvider:PreloadAsync({test})
        loaded = test.IsLoaded
    end)

    if loaded then
        table.insert(validImages, assetId)
    end

    test:Destroy()
end

if #validImages == 0 then
    bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bg.BackgroundTransparency = 0
else
    bg.BackgroundColor3 = Color3.fromRGB(30, 0, 0)
    bg.BackgroundTransparency = 0.75
end

local sounds = {
    "rbxassetid://9043345732",
    "rbxassetid://9043345730",
    "rbxassetid://4745539237",
}

local jumpscareSound = "rbxassetid://314678645"

local function playSound(assetId, volume)
    local sound = Instance.new("Sound")
    sound.SoundId = assetId
    sound.Volume = volume or 1
    sound.Parent = screenGui

    pcall(function()
        sound:Play()
    end)

    task.delay(10, function()
        if sound then
            sound:Destroy()
        end
    end)

    return sound
end

local creepyWords = {
    "tolong",
    "help",
    "dia ada",
    "lari",
    "jangan lihat",
    "matamu",
    "aku lapar",
    "sudah terlambat",
    "kau mati",
    "aku di sini",
    "jangan tidur",
    "darah",
}

local bloodTexts = {
    "KAU TIDAK SENDIRIAN",
    "SAYA MELIHATMU",
    "JANGAN LIHAT",
    "DIA ADA DI SINI",
    "SUDAH TERLAMBAT",
    "JANGAN TIDUR",
    "AKU DI BELAKANGMU",
    "KAU TIDAK BISA LARI",
}

local function showText(text, duration)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.9, 0, 0.15, 0)
    label.Position = UDim2.new(0.05, 0, 0.42, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.ZIndex = 100
    label.Parent = screenGui
    label.TextTransparency = 1

    TweenService:Create(
        label,
        TweenInfo.new(0.25),
        {TextTransparency = 0}
    ):Play()

    task.wait(duration or 2)

    TweenService:Create(
        label,
        TweenInfo.new(0.3),
        {TextTransparency = 1}
    ):Play()

    task.wait(0.35)

    if label then
        label:Destroy()
    end
end

local function showGhost(assetId, duration)
    local img = Instance.new("ImageLabel")
    img.Name = "HorrorImage"
    img.Size = UDim2.fromScale(1, 1)
    img.Position = UDim2.fromScale(0, 0)
    img.BackgroundTransparency = 1
    img.BorderSizePixel = 0
    img.Image = assetId
    img.ImageColor3 = Color3.fromRGB(255, 255, 255)
    img.ImageTransparency = 1
    img.ScaleType = Enum.ScaleType.Fit
    img.ZIndex = 20
    img.Parent = ghostLayer

    TweenService:Create(
        img,
        TweenInfo.new(0.08),
        {ImageTransparency = 0}
    ):Play()

    task.wait(duration or 1)

    if img then
        TweenService:Create(
            img,
            TweenInfo.new(0.15),
            {ImageTransparency = 1}
        ):Play()

        task.wait(0.2)
        img:Destroy()
    end
end

local function flash()
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    frame.BackgroundTransparency = 0
    frame.BorderSizePixel = 0
    frame.ZIndex = 200
    frame.Parent = screenGui

    TweenService:Create(
        frame,
        TweenInfo.new(0.15),
        {BackgroundTransparency = 1}
    ):Play()

    task.wait(0.2)

    if frame then
        frame:Destroy()
    end
end

local function shakeCamera(duration, intensity)
    local camera = workspace.CurrentCamera

    if not camera then
        return
    end

    local start = os.clock()

    while os.clock() - start < duration do
        local offset = Vector3.new(
            (math.random() - 0.5) * intensity,
            (math.random() - 0.5) * intensity,
            (math.random() - 0.5) * intensity
        )

        camera.CFrame = camera.CFrame * CFrame.new(offset)

        task.wait(0.03)
    end
end

local function sendChatMessage(message)
    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local textChannels = TextChatService:FindFirstChild("TextChannels")

            if textChannels then
                local channel = textChannels:FindFirstChild("RBXGeneral")

                if channel then
                    channel:SendAsync(message)
                end
            end
        end
    end)
end

local function horrorEvent()
    flash()

    if #validImages > 0 then
        local assetId = validImages[math.random(1, #validImages)]
        task.spawn(showGhost, assetId, 1.2)
    end

    playSound(jumpscareSound, 2)

    task.spawn(shakeCamera, 1.2, 0.25)

    local text = bloodTexts[math.random(1, #bloodTexts)]
    task.spawn(showText, text, 1.5)

    task.wait(1.5)

    local creepy = creepyWords[math.random(1, #creepyWords)]
    task.spawn(showText, creepy, 1.5)
end

for _, soundId in ipairs(sounds) do
    task.spawn(function()
        playSound(soundId, 1)
    end)

    task.wait(0.5)
end

task.wait(1)

horrorEvent()

task.spawn(function()
    while true do
        task.wait(math.random(5, 10))
        horrorEvent()
    end
end)

while true do
    local part = Instance.new("Part")
    part.Size = Vector3.new(1, 1, 1)
    part.Position = Vector3.new(0, i * 2, 0)
    part.Anchored = true
    part.Parent = workspace
end