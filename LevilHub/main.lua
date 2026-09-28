-- LevilHub Main
-- Di-load oleh loader.lua via loadstring

if not game then error("[LevilHub] Harus dijalankan di Roblox.") end

-- ============================================================
-- KONSTANTA
-- ============================================================
local BASE_URL       = "https://raw.githubusercontent.com/yummygaming20-bot/LevilHub/refs/heads/main/"
local WindUI_VERSION = "1.6.66"

-- Tab dibuat di main, dioper ke modul lewat HUB.Tabs
-- Urutan: Auto, ESP, Combat, Player, Settings
local TAB_DEFS = {
    { key = "Auto",     name = "Auto",     icon = "zap"              },
    { key = "ESP",      name = "ESP",       icon = "scan-eye"         },
    { key = "Combat",   name = "Combat",    icon = "sword"            },
    { key = "Player",   name = "Player",    icon = "person-standing"  },
    { key = "Settings", name = "Settings",  icon = "settings"         },
}

-- Daftar modul
local MODULE_LIST = {
    { path = "modules/steal.lua",    label = "Auto Steal"   },
    { path = "modules/esp.lua",      label = "ESP"          },
    { path = "modules/combat.lua",   label = "Combat"       },
    { path = "modules/movement.lua", label = "Movement"     },
    { path = "modules/base.lua",     label = "Base / Plot"  },
    { path = "modules/config.lua",   label = "Settings"     },
}

-- ============================================================
-- UNLOAD INSTANCE LAMA
-- ============================================================
do
    local prev = _G.LevilHub
    if prev and type(prev.Unload) == "function" then pcall(prev.Unload) end
end

-- ============================================================
-- HUB GLOBAL
-- ============================================================
local HUB = {
    conns      = {},
    drawings   = {},
    highlights = {},
    dead       = false,
    paused     = false,
    UI         = { Tabs = {}, SubTabs = {} },
    Runtime    = {},
    Modules    = {},
    V44 = {
        only100m          = false,
        lockedUid         = nil,
        lockAt            = 0,
        droneFollow       = false,
        droneTarget       = nil,
        droneAt           = 0,
        droneSwingAt      = 0,
        autoPlaceBusy     = false,
        hatchBusy         = false,
        afkAt             = 0,
        lastIdleAt        = 0,
        defendEgg         = false,
        droneGuardReached = false,
    },
}
_G.LevilHub = HUB

function HUB.Track(conn)
    table.insert(HUB.conns, conn)
    return conn
end

function HUB.Unload()
    HUB.dead = true
    for _, c in ipairs(HUB.conns) do pcall(function() c:Disconnect() end) end
    for _, d in ipairs(HUB.drawings)   do pcall(function() d:Remove()  end) end
    for _, h in ipairs(HUB.highlights) do pcall(function() h:Destroy() end) end
    for _, mod in pairs(HUB.Modules) do
        if type(mod.Unload) == "function" then pcall(mod.Unload) end
    end
    _G.LevilHub = nil
end

function HUB.Notify(title, body, notifType, duration)
    pcall(function()
        HUB.WindUI:Notify({
            Title    = tostring(title or "LevilHub"),
            Content  = tostring(body  or ""),
            Duration = duration or 3,
        })
    end)
end

-- ============================================================
-- BOOT PANEL
-- ============================================================
local BootPanel = {}
do
    local function getParent()
        local p
        pcall(function() if type(gethui)=="function" then p=gethui() end end)
        if p then return p end
        pcall(function()
            local lp = game:GetService("Players").LocalPlayer
            p = lp and (lp:FindFirstChildOfClass("PlayerGui")
                    or lp:WaitForChild("PlayerGui",5))
        end)
        if p then return p end
        pcall(function() p = game:GetService("CoreGui") end)
        return p
    end

    local sg, barFill, titleLabel, bodyLabel

    function BootPanel.Init()
        local parent = getParent()
        if not parent then return end

        sg = Instance.new("ScreenGui")
        sg.Name="LevilHub_Boot"; sg.ResetOnSpawn=false
        sg.IgnoreGuiInset=true; sg.ZIndexBehavior=Enum.ZIndexBehavior.Global
        pcall(function() sg.DisplayOrder=999999 end)
        sg.Parent = parent

        local bg = Instance.new("Frame")
        bg.Size=UDim2.fromScale(1,1); bg.BackgroundColor3=Color3.fromRGB(15,15,18)
        bg.BorderSizePixel=0; bg.ZIndex=0; bg.Parent=sg

        local card = Instance.new("Frame")
        card.AnchorPoint=Vector2.new(.5,.5); card.Position=UDim2.fromScale(.5,.5)
        card.Size=UDim2.fromOffset(360,160); card.BackgroundColor3=Color3.fromRGB(28,28,32)
        card.BorderSizePixel=0; card.ZIndex=1; card.Parent=sg
        Instance.new("UICorner",card).CornerRadius=UDim.new(0,8)

        local stroke=Instance.new("UIStroke")
        stroke.Color=Color3.fromRGB(60,60,68); stroke.Thickness=1; stroke.Parent=card

        titleLabel=Instance.new("TextLabel")
        titleLabel.BackgroundTransparency=1; titleLabel.Position=UDim2.new(0,0,0,20)
        titleLabel.Size=UDim2.new(1,0,0,22); titleLabel.Font=Enum.Font.GothamBold
        titleLabel.TextSize=16; titleLabel.TextColor3=Color3.fromRGB(235,235,235)
        titleLabel.TextXAlignment=Enum.TextXAlignment.Center
        titleLabel.Text="LevilHub"; titleLabel.ZIndex=2; titleLabel.Parent=card

        bodyLabel=Instance.new("TextLabel")
        bodyLabel.BackgroundTransparency=1; bodyLabel.Position=UDim2.new(0,0,0,52)
        bodyLabel.Size=UDim2.new(1,0,0,16); bodyLabel.Font=Enum.Font.Gotham
        bodyLabel.TextSize=12; bodyLabel.TextColor3=Color3.fromRGB(140,140,148)
        bodyLabel.TextXAlignment=Enum.TextXAlignment.Center
        bodyLabel.Text="Initializing..."; bodyLabel.ZIndex=2; bodyLabel.Parent=card

        local barTrack=Instance.new("Frame")
        barTrack.Position=UDim2.new(0,24,0,84); barTrack.Size=UDim2.new(1,-48,0,3)
        barTrack.BackgroundColor3=Color3.fromRGB(50,50,56); barTrack.BorderSizePixel=0
        barTrack.ZIndex=2; barTrack.Parent=card

        barFill=Instance.new("Frame")
        barFill.Size=UDim2.new(0,0,1,0); barFill.BackgroundColor3=Color3.fromRGB(255,255,255)
        barFill.BorderSizePixel=0; barFill.ZIndex=3; barFill.Parent=barTrack

        local dotsFrame=Instance.new("Frame")
        dotsFrame.BackgroundTransparency=1; dotsFrame.Position=UDim2.new(.5,-18,0,104)
        dotsFrame.Size=UDim2.fromOffset(36,8); dotsFrame.ZIndex=2; dotsFrame.Parent=card

        local dots={}
        for i=1,3 do
            local dot=Instance.new("Frame")
            dot.Size=UDim2.fromOffset(5,5); dot.Position=UDim2.fromOffset((i-1)*13,0)
            dot.BackgroundColor3=Color3.fromRGB(100,100,108); dot.BorderSizePixel=0
            dot.ZIndex=3; dot.Parent=dotsFrame
            Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
            dots[i]=dot
        end

        task.spawn(function()
            local RS=game:GetService("RunService"); local started=os.clock()
            while sg and sg.Parent do
                local t=os.clock()-started
                for i,dot in ipairs(dots) do
                    local phase=(t*2-(i-1)*.35)%(math.pi*2)
                    local bright=(math.sin(phase)+1)*.5
                    pcall(function()
                        local v=math.floor(80+bright*130)
                        dot.BackgroundColor3=Color3.fromRGB(v,v,v+8)
                    end)
                end
                RS.Heartbeat:Wait()
            end
        end)
    end

    function BootPanel.Set(title, body, progress)
        pcall(function()
            if titleLabel then titleLabel.Text=tostring(title or "LevilHub") end
            if bodyLabel  then bodyLabel.Text=tostring(body or "")           end
            if barFill and progress then
                barFill.Size=UDim2.new(math.clamp(progress,0,1),0,1,0)
            end
        end)
    end

    function BootPanel.Error(msg)
        pcall(function()
            if titleLabel then titleLabel.Text="LevilHub ERROR"; titleLabel.TextColor3=Color3.fromRGB(230,80,80) end
            if bodyLabel  then bodyLabel.Text=tostring(msg):sub(1,200) end
            if barFill    then barFill.BackgroundColor3=Color3.fromRGB(200,60,60); barFill.Size=UDim2.new(1,0,1,0) end
        end)
    end

    function BootPanel.Close()
        pcall(function() if sg then sg:Destroy() end end)
    end
end

-- ============================================================
-- FETCH & COMPILE
-- ============================================================
local function fetchRaw(path)
    local ok, result = pcall(function() return game:HttpGet(BASE_URL..path) end)
    if not ok or type(result)~="string" or #result<10 then
        error("Gagal fetch: "..path)
    end
    return result
end

local function compileModule(path, src)
    local chunk, err = loadstring(src, "@"..path)
    if not chunk then error("Compile error di "..path..": "..tostring(err)) end
    return chunk
end

-- ============================================================
-- BOOT
-- ============================================================
BootPanel.Init()
BootPanel.Set("LevilHub","Memuat WindUI...",0.05)

-- Load WindUI
local WindUI
do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(
            "https://github.com/Footagesus/WindUI/releases/download/"
            ..WindUI_VERSION.."/main.lua"
        ))()
    end)
    if not ok or not result then
        BootPanel.Error("Gagal load WindUI "..WindUI_VERSION)
        error("[LevilHub] Gagal load WindUI: "..tostring(result))
    end
    WindUI = result
end
pcall(function() WindUI:SetNotificationLower(true) end)
HUB.WindUI = WindUI

BootPanel.Set("LevilHub","Membangun interface...",0.12)

-- Buat Window
local Window = WindUI:CreateWindow({
    Title        = "LevilHub",
    Icon         = "egg",
    Author       = "levilstore.my.id",
    Folder       = "LevilHub",
    Size         = UDim2.fromOffset(580,460),
    Transparent  = true,
    Theme        = "Dark",
    DisableRayfieldLoader = true,
    KeySystem    = false,
})
HUB.Window = Window

-- Buat semua Tab di sini, sebelum modul diload
-- Modul tinggal ambil dari HUB.UI.Tabs[key]
BootPanel.Set("LevilHub","Membangun tabs...",0.18)
for _, def in ipairs(TAB_DEFS) do
    local tab = Window:Tab({ Title=def.name, Icon=def.icon })
    HUB.UI.Tabs[def.key] = tab
end

-- ============================================================
-- LOAD MODUL
-- ============================================================
local total = #MODULE_LIST
local BASE_P = 0.22
local MOD_P  = 0.75

for i, modInfo in ipairs(MODULE_LIST) do
    local progress = BASE_P + (MOD_P * (i-1) / total)
    BootPanel.Set("LevilHub","Memuat: "..modInfo.label.." ("..i.."/"..total..")", progress)

    local src
    do
        local ok, result = pcall(fetchRaw, modInfo.path)
        if not ok then
            BootPanel.Error("Gagal fetch modul: "..modInfo.label.."\n"..tostring(result))
            error("[LevilHub] "..tostring(result))
        end
        src = result
    end

    local chunk
    do
        local ok, result = pcall(compileModule, modInfo.path, src)
        if not ok then
            BootPanel.Error("Compile error: "..modInfo.label.."\n"..tostring(result))
            error("[LevilHub] "..tostring(result))
        end
        chunk = result
    end

    local modResult
    do
        local ok, result = xpcall(function()
            return chunk(HUB)
        end, function(msg)
            return debug and debug.traceback and debug.traceback(tostring(msg),2) or tostring(msg)
        end)
        if not ok then
            BootPanel.Error("Error di modul: "..modInfo.label.."\n"..tostring(result))
            error("[LevilHub] Modul "..modInfo.label.." error:\n"..tostring(result))
        end
        modResult = result
    end

    if type(modResult)=="table" then
        HUB.Modules[modInfo.label] = modResult
    end
    task.wait()
end

-- ============================================================
-- SELESAI
-- ============================================================
BootPanel.Set("LevilHub","Selesai!",1.0)
task.wait(0.4)
BootPanel.Close()
HUB.Notify("LevilHub","Script loaded — levilstore.my.id","Success",3.5)
