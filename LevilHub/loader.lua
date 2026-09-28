-- LevilHub Loader
-- Jalankan file ini di executor kamu

if not game then
    error("[LevilHub] Jalankan di Roblox executor, bukan Lua editor.")
end

local BASE_URL = "https://raw.githubusercontent.com/yummygaming20-bot/LevilHub/refs/heads/main/LevilHub"

local function fetch(path)
    local ok, result = pcall(function()
        return game:HttpGet(BASE_URL .. path)
    end)
    if not ok or type(result) ~= "string" or #result < 10 then
        error("[LevilHub] Gagal fetch: " .. path .. "\n" .. tostring(result))
    end
    return result
end

local function loadModule(path)
    local src = fetch(path)
    local chunk, err = loadstring(src, "@" .. path)
    if not chunk then
        error("[LevilHub] Gagal compile: " .. path .. "\n" .. tostring(err))
    end
    return chunk
end

-- Load dan jalankan main
local ok, err = xpcall(function()
    loadModule("main.lua")()
end, function(msg)
    if debug and debug.traceback then
        return debug.traceback(tostring(msg), 2)
    end
    return tostring(msg)
end)

if not ok then
    -- Coba tampilkan error di screen kalau main belum sempat setup UI
    warn("[LevilHub LOADER ERROR]\n" .. tostring(err))
    pcall(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "LevilHub_LoaderError"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Global
        pcall(function() sg.DisplayOrder = 999999 end)

        local parent
        pcall(function()
            if type(gethui) == "function" then parent = gethui() end
        end)
        if not parent then
            pcall(function()
                parent = game:GetService("Players").LocalPlayer
                    and game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
            end)
        end
        if not parent then
            pcall(function() parent = game:GetService("CoreGui") end)
        end
        if not parent then return end
        sg.Parent = parent

        local bg = Instance.new("Frame")
        bg.Size = UDim2.fromScale(1, 1)
        bg.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        bg.BackgroundTransparency = 0.3
        bg.BorderSizePixel = 0
        bg.Parent = sg

        local card = Instance.new("Frame")
        card.AnchorPoint = Vector2.new(0.5, 0.5)
        card.Position = UDim2.fromScale(0.5, 0.5)
        card.Size = UDim2.fromOffset(420, 120)
        card.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
        card.BorderSizePixel = 0
        card.Parent = bg
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(200, 60, 60)
        stroke.Thickness = 1
        stroke.Parent = card

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 30)
        title.Position = UDim2.fromOffset(0, 10)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 14
        title.TextColor3 = Color3.fromRGB(230, 80, 80)
        title.Text = "LevilHub — Loader Error"
        title.TextXAlignment = Enum.TextXAlignment.Center
        title.Parent = card

        local body = Instance.new("TextLabel")
        body.Size = UDim2.new(1, -20, 0, 70)
        body.Position = UDim2.fromOffset(10, 44)
        body.BackgroundTransparency = 1
        body.Font = Enum.Font.Gotham
        body.TextSize = 11
        body.TextColor3 = Color3.fromRGB(180, 180, 185)
        body.TextWrapped = true
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.Text = tostring(err):sub(1, 300)
        body.Parent = card

        task.delay(12, function() pcall(function() sg:Destroy() end) end)
    end)
end
