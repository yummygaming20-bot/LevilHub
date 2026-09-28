-- modules/esp.lua
-- Modul Egg ESP / Tracker
-- Porting dari LevilHub_Steal_An_Egg.lua bagian ESP (baris ~6576-6780)

local function Init(HUB)
    local Window  = HUB.Window
    local Notify  = HUB.Notify
    local RS      = game:GetService("ReplicatedStorage")
    local Players = game:GetService("Players")
    local LP      = Players.LocalPlayer
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")

    -- ============================================================
    -- STATE ESP
    -- ============================================================
    local esp = {
        enabled      = false,
        showPetIcons = true,
        traps        = false,
        rareEggsOnly = false,
        maxDistance  = 800,
    }
    HUB.ESP = esp

    local espBillboards  = {}
    local espHighlights  = {}
    local espContainer   = nil
    local espTrapHighlights = {}

    -- ============================================================
    -- REFERENSI GAME
    -- ============================================================
    local EggState, AssetsData
    pcall(function() EggState   = require(RS.Client.EggState)  end)
    pcall(function() AssetsData = require(RS.Data.Assets)       end)

    -- ============================================================
    -- HELPERS
    -- ============================================================
    local RARITY_COLORS = {
        ["Divine"]      = Color3.fromRGB(244, 63,  94),
        ["Eternal"]     = Color3.fromRGB(217, 70, 239),
        ["Secret"]      = Color3.fromRGB(249,115,  22),
        ["Cosmic"]      = Color3.fromRGB(  6,182, 212),
        ["Mythic"]      = Color3.fromRGB(139, 92, 246),
        ["Legendary"]   = Color3.fromRGB(251,191,  36),
        ["Epic"]        = Color3.fromRGB(168, 85, 247),
        ["Rare"]        = Color3.fromRGB( 59,130, 246),
        ["Uncommon"]    = Color3.fromRGB( 34,197,  94),
        ["Common"]      = Color3.fromRGB(148,163, 184),
    }

    local function safeCallback(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[LevilHub/esp] " .. tostring(err)) end
        end
    end

    local function getEspContainer()
        if espContainer and espContainer.Parent then return espContainer end
        local c = Instance.new("Folder")
        c.Name   = "LevilHub_ESP"
        c.Parent = Workspace
        espContainer = c
        table.insert(HUB.highlights, c) -- auto-cleanup on unload
        return c
    end

    local function getRarityColor(rarityName)
        return RARITY_COLORS[rarityName] or Color3.fromRGB(200, 200, 200)
    end

    local function imageId(icon)
        if not icon or icon == "" then return "" end
        local text = tostring(icon)
        local digits = text:match("(%d%d%d%d%d+)")
        if digits then return "rbxassetid://" .. digits end
        if text:sub(1,4) == "http" then return text end
        return text
    end

    local function getAssetIcon(category)
        if not AssetsData or not category then return "" end
        local ok, info = pcall(function()
            local dir = AssetsData.Directory or AssetsData
            return dir[category] or dir[tostring(category)]
        end)
        if not ok or type(info) ~= "table" then return "" end
        local icon = info.Icon or info.Image or info.Thumbnail
            or (type(info.Egg)    == "table" and (info.Egg.Icon    or info.Egg.Image))
            or (type(info.Pet)    == "table" and (info.Pet.Icon    or info.Pet.Image))
        return imageId(icon or "")
    end

    -- ============================================================
    -- BILLBOARD UPDATE
    -- ============================================================
    local function updateBillboard(key, pos, record, rarityName, moneyValue, distStuds)
        local bb = espBillboards[key]

        if not bb or not bb.part or not bb.part.Parent then
            -- Criar billboard
            local holder = getEspContainer()
            local part = Instance.new("Part")
            part.Name              = "LSS_EspAnchor"
            part.Size              = Vector3.new(1,1,1)
            part.Transparency      = 1
            part.Anchored          = true
            part.CanCollide        = false
            part.CanQuery          = false
            part.CanTouch          = false
            part.CFrame            = CFrame.new(pos)
            part.Parent            = holder

            local gui = Instance.new("BillboardGui")
            gui.Name              = "LSS_EggCard"
            gui.Adornee           = part
            gui.Size              = UDim2.fromOffset(200, 84)
            gui.StudsOffset       = Vector3.new(0, 3.5, 0)
            gui.AlwaysOnTop       = true
            gui.LightInfluence    = 0
            gui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
            gui.Parent            = part

            local frame = Instance.new("Frame")
            frame.Name                  = "Card"
            frame.Size                  = UDim2.fromScale(1,1)
            frame.BackgroundColor3      = Color3.fromRGB(5,12,30)
            frame.BackgroundTransparency = 0.14
            frame.BorderSizePixel       = 0
            frame.Parent                = gui
            Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

            local stroke = Instance.new("UIStroke")
            stroke.Color            = Color3.fromRGB(225,230,238)
            stroke.Thickness        = 1.5
            stroke.Transparency     = 0.05
            stroke.ApplyStrokeMode  = Enum.ApplyStrokeMode.Border
            stroke.Parent           = frame

            -- Icon box
            local iconBox = Instance.new("Frame")
            iconBox.Name                  = "IconBox"
            iconBox.Size                  = UDim2.fromOffset(52,52)
            iconBox.Position              = UDim2.fromOffset(8,14)
            iconBox.BackgroundColor3      = Color3.fromRGB(3,8,22)
            iconBox.BackgroundTransparency = 0.08
            iconBox.BorderSizePixel       = 0
            iconBox.Parent                = frame
            Instance.new("UICorner", iconBox).CornerRadius = UDim.new(0,8)

            local icon = Instance.new("ImageLabel")
            icon.Name                  = "Icon"
            icon.Size                  = UDim2.fromScale(0.82,0.82)
            icon.Position              = UDim2.fromScale(0.5,0.5)
            icon.AnchorPoint           = Vector2.new(0.5,0.5)
            icon.BackgroundTransparency = 1
            icon.Image                 = ""
            icon.ScaleType             = Enum.ScaleType.Fit
            icon.Parent                = iconBox

            local function makeLabel(name, posY, size12, bold)
                local lbl = Instance.new("TextLabel")
                lbl.Name                  = name
                lbl.Size                  = UDim2.new(1,-70,0,16)
                lbl.Position              = UDim2.fromOffset(68, posY)
                lbl.BackgroundTransparency = 1
                lbl.Font                  = bold and Enum.Font.GothamBlack or Enum.Font.GothamSemibold
                lbl.TextSize              = size12 or 10
                lbl.TextXAlignment        = Enum.TextXAlignment.Left
                lbl.TextColor3            = Color3.fromRGB(255,255,255)
                lbl.TextTruncate          = Enum.TextTruncate.AtEnd
                lbl.Parent                = frame
                return lbl
            end

            local titleLbl    = makeLabel("Title",   6, 12, true)
            local rarityLbl   = makeLabel("Rarity", 22,  9, false)
            local moneyLbl    = makeLabel("Money",  36,  9, false)
            local distLbl     = makeLabel("Dist",   52,  9, false)
            distLbl.TextColor3 = Color3.fromRGB(181,188,210)

            bb = { part=part, gui=gui, frame=frame, icon=icon, title=titleLbl,
                   rarity=rarityLbl, money=moneyLbl, dist=distLbl }
            espBillboards[key] = bb
        end

        -- Update posisi dan teks
        pcall(function()
            bb.part.CFrame  = CFrame.new(pos)
            local cat = tostring(record.AssetCategory or record.Name or "Egg")
            local iconImg = getAssetIcon(cat)
            if esp.showPetIcons and iconImg ~= "" then
                bb.icon.Image = iconImg
            else
                bb.icon.Image = ""
            end
            bb.title.Text  = cat
            bb.rarity.Text = rarityName or "?"
            bb.rarity.TextColor3 = getRarityColor(rarityName)
            local mStr = moneyValue and moneyValue > 0
                and ("$" .. string.format("%.0f", moneyValue) .. "/s") or ""
            bb.money.Text = mStr
            bb.dist.Text  = distStuds and (string.format("%.0f", distStuds) .. " studs") or ""
        end)
    end

    local function removeBillboard(key)
        local bb = espBillboards[key]
        if bb then
            pcall(function() bb.part:Destroy() end)
            espBillboards[key] = nil
        end
    end

    -- ============================================================
    -- TRAP ESP (Highlight)
    -- ============================================================
    local function updateTrapHighlights()
        local debris = Workspace:FindFirstChild("__DEBRIS")
        local active = {}
        if debris then
            for _, d in ipairs(debris:GetChildren()) do
                if d.Name == "PlayerTrap" and d:GetAttribute("Owner") ~= LP.Name then
                    active[d] = true
                    if not espTrapHighlights[d] then
                        local hl = Instance.new("SelectionBox")
                        hl.Adornee         = d
                        hl.Color3          = Color3.fromRGB(255,60,60)
                        hl.LineThickness   = 0.05
                        hl.SurfaceColor3   = Color3.fromRGB(255,60,60)
                        hl.SurfaceTransparency = 0.6
                        hl.Parent          = Workspace
                        espTrapHighlights[d] = hl
                        table.insert(HUB.highlights, hl)
                    end
                end
            end
        end
        for obj, hl in pairs(espTrapHighlights) do
            if not active[obj] then
                pcall(function() hl:Destroy() end)
                espTrapHighlights[obj] = nil
            end
        end
    end

    local function clearTrapHighlights()
        for _, hl in pairs(espTrapHighlights) do
            pcall(function() hl:Destroy() end)
        end
        espTrapHighlights = {}
    end

    -- ============================================================
    -- MAIN ESP LOOP
    -- ============================================================
    HUB.Track(RunService.Heartbeat:Connect(function()
        if HUB.dead then return end

        -- Trap ESP
        if esp.traps then
            pcall(updateTrapHighlights)
        else
            if next(espTrapHighlights) then clearTrapHighlights() end
        end

        if not esp.enabled then
            -- Bersihkan billboard yang ada
            if next(espBillboards) then
                for k in pairs(espBillboards) do removeBillboard(k) end
            end
            return
        end

        -- Egg ESP
        if not EggState or not EggState.ReadFieldEggs then return end
        local ok, snapshot = pcall(EggState.ReadFieldEggs)
        if not ok or not snapshot or not snapshot.Records then return end

        local char = LP.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local myPos = hrp and hrp.Position or Vector3.new(0,0,0)

        local seen = {}
        for _, record in ipairs(snapshot.Records) do
            if record.BoundsCFrame and record.Uid then
                local pos = record.BoundsCFrame.Position
                local dist = (pos - myPos).Magnitude

                if dist <= esp.maxDistance then
                    local rarityName = tostring(record.Rarity or record.EggRarity or "Common")
                    local isMutated  = record.Mutations and #record.Mutations > 0
                    local isRare     = rarityName ~= "Common" and rarityName ~= "Uncommon"

                    if not esp.rareEggsOnly or isRare or isMutated then
                        local moneyVal = 0
                        if HUB.Runtime and HUB.Runtime.phucEggMoney then
                            pcall(function()
                                moneyVal = HUB.Runtime.phucEggMoney(record) or 0
                            end)
                        end
                        seen[record.Uid] = true
                        pcall(updateBillboard, record.Uid, pos, record, rarityName, moneyVal, dist)
                    end
                end
            end
        end

        -- Hapus billboard yang tidak ada lagi
        for k in pairs(espBillboards) do
            if not seen[k] then removeBillboard(k) end
        end
    end))

    -- ============================================================
    -- TAB UI
    -- ============================================================
    local Tab = HUB.UI.Tabs["ESP"]
    local EspSub  = Tab:AddSection("Egg Tracker ESP")
    -- subtab ESP

    local safeC = safeCallback

    EspSub:AddToggle({
        Name = "Egg ESP Enabled", Default = false, Flag = "esp_eggs_enabled",
        Callback = safeC(function(v)
            esp.enabled = v
            Notify("Egg ESP", v and "Aktif" or "Nonaktif", v and "Success" or "Error")
        end)
    })
    EspSub:AddToggle({
        Name = "Show 3D Pet Image Badges", Default = true, Flag = "esp_pet_icons",
        Callback = function(v) esp.showPetIcons = v end
    })
    EspSub:AddToggle({
        Name = "Trap ESP (Highlights Enemy Traps)", Default = false, Flag = "esp_traps",
        Callback = safeC(function(v)
            esp.traps = v
            if not v then clearTrapHighlights() end
            Notify("Trap ESP", v and "Aktif" or "Nonaktif", v and "Success" or "Error")
        end)
    })
    EspSub:AddToggle({
        Name = "Show Mutated / Rare Eggs Only", Default = false, Flag = "esp_eggs_rare_only",
        Callback = function(v) esp.rareEggsOnly = v end
    })
    EspSub:AddSlider({
        Name = "Max ESP Distance", Min = 400, Max = 9999, Default = 800,
        Suffix = " studs", Flag = "esp_max_dist",
        Callback = function(v) esp.maxDistance = tonumber(v) or 800 end
    })

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload = function()
            esp.enabled = false
            esp.traps   = false
            for k in pairs(espBillboards) do removeBillboard(k) end
            clearTrapHighlights()
            if espContainer and espContainer.Parent then
                pcall(function() espContainer:Destroy() end)
            end
        end,
        GetState = function() return esp end,
    }
end

return Init
