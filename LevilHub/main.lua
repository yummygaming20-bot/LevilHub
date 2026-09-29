
if not game then error("[LevilHub] Harus dijalankan di Roblox.") end

local BASE_URL       = "https://raw.githubusercontent.com/yummygaming20-bot/LevilHub/main/LevilHub/"
local WindUI_VERSION = "1.6.66"

local TAB_DEFS = {
    { key="Auto",     name="Auto",     icon="zap"             },
    { key="ESP",      name="ESP",      icon="scan-eye"        },
    { key="Combat",   name="Combat",   icon="sword"           },
    { key="Player",   name="Player",   icon="person-standing" },
    { key="Settings", name="Settings", icon="settings"        },
}

local MODULE_LIST = {
    { path="modules/esp.lua",      label="ESP"         },
    { path="modules/combat.lua",   label="Combat"      },
    { path="modules/movement.lua", label="Movement"    },
    { path="modules/base.lua",     label="Base / Plot" },
    { path="modules/config.lua",   label="Settings"    },
}

do
    local prev = _G.LevilHub
    if prev and type(prev.Unload)=="function" then pcall(prev.Unload) end
end

local HUB = {
    conns={}, drawings={}, highlights={},
    dead=false, paused=false,
    UI={ Tabs={} },
    Runtime={}, Modules={},
    V44={
        only100m=false, lockedUid=nil, lockAt=0,
        droneFollow=false, droneTarget=nil, droneAt=0,
        autoPlaceBusy=false, hatchBusy=false,
        afkAt=0, defendEgg=false,
    },
}
_G.LevilHub = HUB

function HUB.Track(conn) table.insert(HUB.conns,conn); return conn end

function HUB.Unload()
    HUB.dead=true
    for _,c in ipairs(HUB.conns)      do pcall(function() c:Disconnect() end) end
    for _,d in ipairs(HUB.drawings)   do pcall(function() d:Remove()     end) end
    for _,h in ipairs(HUB.highlights) do pcall(function() h:Destroy()    end) end
    for _,mod in pairs(HUB.Modules) do
        if type(mod.Unload)=="function" then pcall(mod.Unload) end
    end
    _G.LevilHub=nil
end

function HUB.Notify(title,body,_,duration)
    pcall(function()
        HUB.WindUI:Notify({
            Title=tostring(title or "LevilHub"),
            Content=tostring(body or ""),
            Duration=duration or 3,
        })
    end)
end

local BootPanel={}
do
    local function getParent()
        local p
        pcall(function() if type(gethui)=="function" then p=gethui() end end)
        if p then return p end
        pcall(function()
            local lp=game:GetService("Players").LocalPlayer
            p=lp and (lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui",5))
        end)
        if p then return p end
        pcall(function() p=game:GetService("CoreGui") end)
        return p
    end
    local sg,barFill,titleLabel,bodyLabel
    function BootPanel.Init()
        local parent=getParent(); if not parent then return end
        sg=Instance.new("ScreenGui")
        sg.Name="LevilHub_Boot"; sg.ResetOnSpawn=false
        sg.IgnoreGuiInset=true; sg.ZIndexBehavior=Enum.ZIndexBehavior.Global
        pcall(function() sg.DisplayOrder=999999 end)
        sg.Parent=parent
        local bg=Instance.new("Frame")
        bg.Size=UDim2.fromScale(1,1); bg.BackgroundColor3=Color3.fromRGB(15,15,18)
        bg.BorderSizePixel=0; bg.Parent=sg
        local card=Instance.new("Frame")
        card.AnchorPoint=Vector2.new(.5,.5); card.Position=UDim2.fromScale(.5,.5)
        card.Size=UDim2.fromOffset(360,160); card.BackgroundColor3=Color3.fromRGB(28,28,32)
        card.BorderSizePixel=0; card.Parent=sg
        Instance.new("UICorner",card).CornerRadius=UDim.new(0,8)
        local stroke=Instance.new("UIStroke")
        stroke.Color=Color3.fromRGB(60,60,68); stroke.Thickness=1; stroke.Parent=card
        titleLabel=Instance.new("TextLabel")
        titleLabel.BackgroundTransparency=1; titleLabel.Position=UDim2.new(0,0,0,20)
        titleLabel.Size=UDim2.new(1,0,0,22); titleLabel.Font=Enum.Font.GothamBold
        titleLabel.TextSize=16; titleLabel.TextColor3=Color3.fromRGB(235,235,235)
        titleLabel.TextXAlignment=Enum.TextXAlignment.Center
        titleLabel.Text="LevilHub"; titleLabel.Parent=card
        bodyLabel=Instance.new("TextLabel")
        bodyLabel.BackgroundTransparency=1; bodyLabel.Position=UDim2.new(0,0,0,52)
        bodyLabel.Size=UDim2.new(1,0,0,16); bodyLabel.Font=Enum.Font.Gotham
        bodyLabel.TextSize=12; bodyLabel.TextColor3=Color3.fromRGB(140,140,148)
        bodyLabel.TextXAlignment=Enum.TextXAlignment.Center
        bodyLabel.Text="Initializing..."; bodyLabel.Parent=card
        local barTrack=Instance.new("Frame")
        barTrack.Position=UDim2.new(0,24,0,84); barTrack.Size=UDim2.new(1,-48,0,3)
        barTrack.BackgroundColor3=Color3.fromRGB(50,50,56); barTrack.BorderSizePixel=0
        barTrack.Parent=card
        barFill=Instance.new("Frame")
        barFill.Size=UDim2.new(0,0,1,0); barFill.BackgroundColor3=Color3.fromRGB(255,255,255)
        barFill.BorderSizePixel=0; barFill.Parent=barTrack
    end
    function BootPanel.Set(title,body,progress)
        pcall(function()
            if titleLabel then titleLabel.Text=tostring(title or "LevilHub") end
            if bodyLabel  then bodyLabel.Text=tostring(body or "")           end
            if barFill and progress then barFill.Size=UDim2.new(math.clamp(progress,0,1),0,1,0) end
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

local function fetchRaw(path)
    local ok,result=pcall(function() return game:HttpGet(BASE_URL..path) end)
    if not ok or type(result)~="string" or #result<10 then error("Gagal fetch: "..path) end
    return result
end

local function compileModule(path,src)
    local chunk,err=loadstring(src,"@"..path)
    if not chunk then error("Compile error: "..path..": "..tostring(err)) end
    return chunk
end

BootPanel.Init()
BootPanel.Set("LevilHub","Memuat WindUI...",0.05)

local WindUI
do
    local urls={
        "https://github.com/Footagesus/WindUI/releases/download/"..WindUI_VERSION.."/main.lua",
        "https://raw.githubusercontent.com/Footagesus/WindUI/refs/heads/main/src/init.lua",
    }
    for _,url in ipairs(urls) do
        local ok,result=pcall(function() return loadstring(game:HttpGet(url))() end)
        if ok and result then WindUI=result; break end
    end
    if not WindUI then
        BootPanel.Error("Gagal load WindUI")
        error("[LevilHub] Gagal load WindUI")
    end
end
pcall(function() WindUI:SetNotificationLower(true) end)
HUB.WindUI=WindUI

BootPanel.Set("LevilHub","Membangun interface...",0.12)

local Window
do
    
    local methods={"CreateWindow","new","Init","Load"}
    for _,m in ipairs(methods) do
        if type(WindUI[m])=="function" then
            local ok,result=pcall(WindUI[m],WindUI,{
                Title="LevilHub", Icon="egg",
                Author="levilstore.my.id",
                Folder="LevilHub",
                Size=UDim2.fromOffset(580,460),
                Transparent=true, Theme="Dark",
                NewElements=true, 
                DisableRayfieldLoader=true,
                KeySystem=false,
            })
            if ok and result then Window=result; break end
        end
    end
    if not Window then
        BootPanel.Error("Gagal buat Window WindUI")
        error("[LevilHub] Window nil")
    end
end
HUB.Window=Window

BootPanel.Set("LevilHub","Membangun tabs...",0.18)

local function makeTab(def)
    local ok,tab=pcall(function()
        return Window:Tab({
            Title = def.name,
            Icon  = def.icon,
        })
    end)
    if not ok or not tab then
        warn("[LevilHub] Gagal buat tab "..def.name..": "..tostring(tab))
        return nil
    end
    
    if not tab.AddParagraph then
        tab.AddParagraph=function(self,o)
            o=o or {}
            return self:Paragraph({ Title=o.Title or o.Name or "", Desc=o.Content or o.Desc })
        end
    end
    return tab
end

for _,def in ipairs(TAB_DEFS) do
    local tab=makeTab(def)
    if tab then HUB.UI.Tabs[def.key]=tab end
end

local function wrapContainer(c)
    local W={ Raw=c }
    function W:AddToggle(o)
        o=o or {}
        return c:Toggle({ Title=o.Name, Desc=o.Desc, Value=o.Default==true, Flag=o.Flag, Callback=o.Callback })
    end
    function W:AddSlider(o)
        o=o or {}
        return c:Slider({
            Title=o.Name, Desc=o.Desc, Flag=o.Flag, Step=o.Step,
            Value={ Min=o.Min or 0, Max=o.Max or 100, Default=o.Default or o.Min or 0 },
            Callback=o.Callback,
        })
    end
    function W:AddButton(o)
        o=o or {}
        return c:Button({ Title=o.Name, Desc=o.Desc, Callback=o.Callback })
    end
    local function dropdown(o,multi)
        o=o or {}
        local el=c:Dropdown({
            Title=o.Name, Desc=o.Desc, Flag=o.Flag,
            Values=o.Options or {}, Value=o.Default, Multi=multi,
            AllowNone=multi and true or nil,
            Callback=o.Callback,
        })
        if el and not el.SetOptions and type(el.Refresh)=="function" then
            el.SetOptions=function(_,v) el:Refresh(v) end
        end
        return el
    end
    function W:AddDropdown(o)      return dropdown(o,false) end
    function W:AddMultiDropdown(o) return dropdown(o,true)  end
    function W:AddParagraph(o)
        o=o or {}
        return c:Paragraph({ Title=o.Title or o.Name or "", Desc=o.Content or o.Desc })
    end
    
    for _,name in ipairs({"AddToggle","AddSlider","AddButton","AddDropdown","AddMultiDropdown","AddParagraph"}) do
        local raw=W[name]
        W[name]=function(self,o)
            local ok,res=pcall(raw,self,o)
            if not ok then
                warn("[LevilHub] "..name.." gagal ("..tostring(o and (o.Name or o.Title)).."): "..tostring(res))
                return nil
            end
            HUB.UI.ElementCount=HUB.UI.ElementCount+1
            return res
        end
    end
    return W
end

HUB.UI.ElementCount = 0

function HUB.UI.MakeSection(tabKey, sectionName)
    local tab=HUB.UI.Tabs[tabKey]
    if not tab then warn("[LevilHub] Tab tidak ditemukan: "..tostring(tabKey)); return nil end

    local ok,sec=pcall(function()
        return tab:Section({
            Title     = tostring(sectionName),
            Box       = true,
            BoxBorder = true,
            Opened    = true,
        })
    end)
    if not ok or not sec then
        warn("[LevilHub] Gagal buat section '"..tostring(sectionName).."': "..tostring(sec))
        sec=tab 
    end
    return wrapContainer(sec)
end

_G.LevilHub      = HUB
_G.LH_MakeSection = function(tabKey, sectionName)
    return HUB.UI.MakeSection(tabKey, sectionName)
end
_G.LH_Tabs       = HUB.UI.Tabs
_G.LH_Notify     = function(...) return HUB.Notify(...) end
_G.LH_Track      = function(...) return HUB.Track(...) end
_G.LH_Window     = HUB.Window

local total=#MODULE_LIST
for i,modInfo in ipairs(MODULE_LIST) do
    local progress=0.22+(0.75*(i-1)/total)
    BootPanel.Set("LevilHub","Memuat: "..modInfo.label.." ("..i.."/"..total..")",progress)

    local src
    do
        local ok,result=pcall(fetchRaw,modInfo.path)
        if not ok then
            BootPanel.Error("Gagal fetch: "..modInfo.label.."\n"..tostring(result))
            error("[LevilHub] "..tostring(result))
        end
        src=result
    end

    local chunk
    do
        local ok,result=pcall(compileModule,modInfo.path,src)
        if not ok then
            BootPanel.Error("Compile error: "..modInfo.label.."\n"..tostring(result))
            error("[LevilHub] "..tostring(result))
        end
        chunk=result
    end

    local ok,result=xpcall(function()
        return chunk(HUB)
    end,function(msg)
        return debug and debug.traceback and debug.traceback(tostring(msg),2) or tostring(msg)
    end)
    if not ok then
        BootPanel.Error("Error di modul: "..modInfo.label.."\n"..tostring(result))
        error("[LevilHub] Modul "..modInfo.label.." error:\n"..tostring(result))
    end
    
    if type(result)=="function" then
        local ok2,res2=xpcall(function()
            return result(HUB)
        end,function(msg)
            return debug and debug.traceback and debug.traceback(tostring(msg),2) or tostring(msg)
        end)
        if not ok2 then
            BootPanel.Error("Error di modul: "..modInfo.label.."\n"..tostring(res2))
            error("[LevilHub] Modul "..modInfo.label.." error:\n"..tostring(res2))
        end
        result=res2
    end
    if type(result)=="table" then
        HUB.Modules[modInfo.label]=result
    end
    task.wait()
end

pcall(function() local first=HUB.UI.Tabs[TAB_DEFS[1].key]; if first then first:Select() end end)
BootPanel.Set("LevilHub","Selesai!",1.0)
task.wait(0.4)
BootPanel.Close()
HUB.Notify("LevilHub","Script loaded — levilstore.my.id","Success",3.5)
