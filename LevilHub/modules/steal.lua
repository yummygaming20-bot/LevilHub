-- modules/steal.lua
-- Tab: Auto → SubTab: Auto Steal | Auto Hatch & Plant

local function Init(HUB)
    local Notify     = HUB.Notify
    local AutoTab    = HUB.UI.Tabs["Auto"]   -- ambil dari tab yang sudah dibuat
    local RS         = game:GetService("ReplicatedStorage")
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ProxSvc    = game:GetService("ProximityPromptService")
    local LP         = Players.LocalPlayer

    -- ============================================================
    -- STATE
    -- ============================================================
    local autoStealEnabled  = false
    local autoHatchEnabled  = false
    local autoPlantEnabled  = false
    local rareEggHunter     = true
    local stealBigEggsOnly  = false
    local stealDelay        = 0.75
    local glideSpeed        = 850
    local hatchCheckDelay   = 2.0
    local ignoredEggs       = {}

    local selectedStealRarities = {}
    local selectedStealAreas    = {}
    local selectedMutationTypes = {}

    local RARITY_NAMES = {
        "Common","Uncommon","Rare","Epic","Legendary",
        "Mythic","Cosmic","Secret","Eternal","Divine",
        "Light & Dark","Titan","Transcendent","Superior","Limited",
    }
    local AREA_NAMES = {
        "Forest","Lake","Desert","Jungle","Snow","Volcano",
        "Abyss Ocean","Prehistoric","Cosmic","Cherry Blossom",
        "Titan Temple","Light Dark",
    }
    local MUTATION_FILTERS = { "Rainbow","Gold","Silver","Parasite","Monstrous","Big" }
    local RARITY_SCORE_MAP = {
        ["Light & Dark"]=1300,["Titan"]=1100,["Divine"]=1000,
        ["Eternal"]=900,["Secret"]=800,["Cosmic"]=700,
        ["Mythic"]=600,["Legendary"]=500,["Epic"]=400,
        ["Rare"]=300,["Uncommon"]=200,["Common"]=100,
    }

    -- ============================================================
    -- HELPERS
    -- ============================================================
    local function safeC(fn)
        return function(...) local ok,err=pcall(fn,...) if not ok then warn("[steal] "..tostring(err)) end end
    end

    local function findHRP()
        local c=LP.Character; return c and c:FindFirstChild("HumanoidRootPart")
    end
    local function findHum()
        local c=LP.Character; return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function GetNetRemote(name)
        local net=RS:FindFirstChild("Packages") and RS.Packages:FindFirstChild("Networking")
        local r = net and net:FindFirstChild(name) or RS:FindFirstChild(name,true)
        return r
    end

    -- ============================================================
    -- GAME MODULES
    -- ============================================================
    local EggState, PlotState, EggToolDisplay
    pcall(function() EggState      = require(RS.Client.EggState)             end)
    pcall(function() PlotState     = require(RS.Client.PlotState)            end)
    pcall(function() EggToolDisplay = require(RS.Shared.Eggs.EggToolDisplay) end)

    local AskPlaceEggRemote      = GetNetRemote("RF/EggWorld/AskPlaceEgg")
    local AskFieldEggCarryRemote = GetNetRemote("RF/EggWorld/AskFieldEggCarry")
    local AskHatchRemote         = GetNetRemote("RF/EggWorld/AskHatch")
    local AskFinishHatchRemote   = GetNetRemote("RF/EggWorld/AskFinishHatch")

    -- Speedup proximity prompt
    HUB.Track(ProxSvc.PromptButtonHoldBegan:Connect(function(prompt, player)
        if player==LP and tostring(prompt)=="CarryAreaEgg" then
            prompt.HoldDuration=0
        end
    end))

    -- ============================================================
    -- RARITY / FILTER CHECKS
    -- ============================================================
    local function GetEggRarityInfo(record)
        local rn=tostring(record.Rarity or record.EggRarity or "Common")
        return rn, RARITY_SCORE_MAP[rn] or 100
    end

    local function isAreaOk(areaId, filter)
        if not filter or #filter==0 then return true end
        local aid=tostring(areaId or ""):lower()
        for _,a in ipairs(filter) do if aid:find(tostring(a):lower(),1,true) then return true end end
        return false
    end

    local function isRarityOk(rn, filter)
        if not filter or #filter==0 then return true end
        for _,r in ipairs(filter) do if tostring(r):lower()==rn:lower() then return true end end
        return false
    end

    local function isMutOk(muts, record, filter)
        if not filter or #filter==0 then return true end
        for _,f in ipairs(filter) do
            if f=="Big" and record.AssetScale and tonumber(record.AssetScale)>=1.35 then return true end
            for _,m in ipairs(muts or {}) do
                if tostring(m):lower():find(tostring(f):lower(),1,true) then return true end
            end
        end
        return false
    end

    local function isBig(record)
        return (tonumber(record.AssetScale or 0)>=1.35) or (tonumber(record.NestScale or 0)>=1.0)
    end

    -- ============================================================
    -- GET MATCHING EGGS
    -- ============================================================
    local function GetMatchingFieldEggs()
        if not EggState or not EggState.ReadFieldEggs then return {} end
        local ok,snap=pcall(EggState.ReadFieldEggs)
        if not ok or not snap or not snap.Records then return {} end
        local matched={}
        for _,record in ipairs(snap.Records) do
            if record.State=="Slot" and record.BoundsCFrame and record.Uid then
                local ign=ignoredEggs[record.Uid] and (os.clock()-ignoredEggs[record.Uid]<2.5)
                if not ign and (not stealBigEggsOnly or isBig(record)) then
                    local rn,baseScore=GetEggRarityInfo(record)
                    local muts=record.Mutations or {}
                    if isAreaOk(record.AreaId,selectedStealAreas)
                    and isRarityOk(rn,selectedStealRarities)
                    and isMutOk(muts,record,selectedMutationTypes) then
                        local bonus=0
                        for _,m in ipairs(muts) do
                            if m=="Rainbow" then bonus+=35
                            elseif m=="Gold" or m=="Golden" then bonus+=20
                            elseif m=="Silver" then bonus+=10
                            end
                        end
                        if record.HasParasite or table.find(muts,"Parasite") or table.find(muts,"Monstrous") then bonus+=800 end
                        if isBig(record) then bonus+=600 end
                        table.insert(matched,{record=record,rarity=rn,rarityScore=baseScore+bonus})
                    end
                end
            end
        end
        if #matched>1 and rareEggHunter then
            table.sort(matched,function(a,b) return (a.rarityScore or 0)>(b.rarityScore or 0) end)
        end
        return matched
    end
    HUB.Runtime.GetMatchingFieldEggs = GetMatchingFieldEggs

    -- ============================================================
    -- TRAVEL
    -- ============================================================
    local ROAD_Z=  -364.5
    local SAFE_X=   580
    local SAFE_SPD= 245

    local function MoveToPoint(target,speed)
        local hrp=findHRP(); if not hrp or not target then return false end
        local dist=(target-hrp.Position).Magnitude
        if dist<1.0 then hrp.CFrame=CFrame.new(target.X,math.max(target.Y,70),target.Z); hrp.AssemblyLinearVelocity=Vector3.zero; return true end
        speed=math.clamp(tonumber(speed) or glideSpeed,50,850)
        local t0=os.clock()
        while not HUB.dead do
            local dt=RunService.Heartbeat:Wait()
            local cur=hrp.Position; local toT=target-cur; local rem=toT.Magnitude
            if rem<1.0 then break end
            local step=math.min(speed*dt,rem); local dir=toT.Unit; local nxt=cur+dir*step
            hrp.CFrame=CFrame.lookAt(nxt,nxt+dir)
            hrp.AssemblyLinearVelocity=Vector3.zero; hrp.AssemblyAngularVelocity=Vector3.zero
            if os.clock()-t0>(dist/50+5) then break end
        end
        hrp.CFrame=CFrame.new(target.X,math.max(target.Y,70),target.Z); hrp.AssemblyLinearVelocity=Vector3.zero
        return true
    end

    local function TravelRoadPath(targetPos,speed)
        local hrp=findHRP(); if not hrp or not targetPos then return false end
        local sp=hrp.Position; local sy=math.max(sp.Y,targetPos.Y,70.4)
        local isBase=targetPos.X<560
        if isBase and sp.X>SAFE_X then
            MoveToPoint(Vector3.new(sp.X,sy,ROAD_Z),speed)
            MoveToPoint(Vector3.new(SAFE_X,sy,ROAD_Z),speed)
            MoveToPoint(Vector3.new(targetPos.X,sy,ROAD_Z),SAFE_SPD)
            MoveToPoint(targetPos+Vector3.new(0,1.2,0),SAFE_SPD)
        else
            MoveToPoint(Vector3.new(sp.X,sy,ROAD_Z),speed)
            MoveToPoint(Vector3.new(targetPos.X,sy,ROAD_Z),speed)
            MoveToPoint(targetPos+Vector3.new(0,1.2,0),speed)
        end
        return true
    end
    HUB.Runtime.TravelRoadPath = TravelRoadPath

    -- ============================================================
    -- GET PLOT CENTER
    -- ============================================================
    local function GetPlotCenter()
        local fallback=Vector3.new(464.7,70.4,-364.0)
        if not PlotState or not PlotState.ResolvePlot then return fallback end
        local plotObj; pcall(function() plotObj=PlotState.ResolvePlot() end)
        local pt=plotObj and plotObj.CenterPoint
        if not pt then return fallback end
        if typeof(pt)=="Vector3" then return pt end
        if pt:IsA("BasePart") then return pt.Position end
        return fallback
    end

    -- ============================================================
    -- STEAL ONE EGG
    -- ============================================================
    local function PlantCarriedEggs()
        if not AskPlaceEggRemote then return 0 end
        local count=0; local tools={}
        local function scanTools(c) if not c then return end
            for _,t in ipairs(c:GetChildren()) do if t:IsA("Tool") then
                local uid=t:GetAttribute("Uid") or (EggToolDisplay and EggToolDisplay.GetToolUid and EggToolDisplay.GetToolUid(t))
                if uid then table.insert(tools,uid) end
            end end
        end
        scanTools(LP.Character); scanTools(LP.Backpack)
        for _,uid in ipairs(tools) do
            for _=1,3 do
                local offset=CFrame.new(math.random(-6,6),0,math.random(-6,6))
                local ok=pcall(function()
                    if AskPlaceEggRemote:IsA("RemoteFunction") then AskPlaceEggRemote:InvokeServer(uid,offset)
                    else AskPlaceEggRemote:FireServer(uid,offset) end
                end)
                if ok then count+=1; break end; task.wait(0.1)
            end
        end
        return count
    end

    local function StealEgg(target)
        local hrp=findHRP(); if not hrp then return false end
        local record=target.record; if not record then return false end
        local eggPos=record.BoundsCFrame.Position
        HUB.V44.lockedUid=record.Uid; HUB.V44.lockAt=os.clock()
        TravelRoadPath(eggPos,glideSpeed); task.wait(0.15)
        local ok=false
        if AskFieldEggCarryRemote then
            ok=pcall(function()
                if AskFieldEggCarryRemote:IsA("RemoteFunction") then AskFieldEggCarryRemote:InvokeServer(record.Uid)
                else AskFieldEggCarryRemote:FireServer(record.Uid) end
            end)
        end
        ignoredEggs[record.Uid]=os.clock()
        HUB.V44.lockedUid=nil
        if ok then
            TravelRoadPath(GetPlotCenter(),glideSpeed)
            if autoPlantEnabled then task.wait(0.3); PlantCarriedEggs() end
        end
        return ok
    end

    -- ============================================================
    -- HATCH
    -- ============================================================
    local function HatchAllReadyEggs()
        if not EggState or not EggState.ReadOwnedEggs then return 0 end
        local ok,snap=pcall(EggState.ReadOwnedEggs,LP.UserId)
        if not ok or not snap then return 0 end
        local count=0; local records=snap.Records or snap
        if type(records)~="table" then return 0 end
        for uid,eggData in pairs(records) do
            if type(eggData)=="table" then
                local isReady=(EggState.IsReadyToHatch and EggState.IsReadyToHatch(eggData)) or eggData.Placement~=nil
                if isReady then
                    pcall(function()
                        if AskHatchRemote then
                            if AskHatchRemote:IsA("RemoteFunction") then AskHatchRemote:InvokeServer(uid)
                            else AskHatchRemote:FireServer(uid) end
                        end
                        task.wait(0.05)
                        if AskFinishHatchRemote then
                            if AskFinishHatchRemote:IsA("RemoteFunction") then AskFinishHatchRemote:InvokeServer(uid)
                            else AskFinishHatchRemote:FireServer(uid) end
                        end
                        count+=1
                    end)
                end
            end
        end
        return count
    end

    -- ============================================================
    -- AUTO LOOPS
    -- ============================================================
    local stealBusy=false
    task.spawn(function()
        while not HUB.dead do
            task.wait(stealDelay)
            if HUB.paused or not autoStealEnabled or stealBusy then continue end
            local hum=findHum(); if not hum or hum.Health<=0 then continue end
            local eggs=GetMatchingFieldEggs(); if #eggs==0 then continue end
            stealBusy=true; pcall(StealEgg,eggs[1]); stealBusy=false
        end
    end)

    task.spawn(function()
        while not HUB.dead do
            task.wait(hatchCheckDelay)
            if HUB.paused or not autoHatchEnabled then continue end
            pcall(HatchAllReadyEggs)
        end
    end)

    -- ============================================================
    -- UI — Sub tabs di dalam tab "Auto"
    -- ============================================================
    AutoTab:Section({ Title = "Auto Steal" })
    AutoTab:Section({ Title = "Auto Hatch & Plant" })

    -- Auto Steal SubTab
    AutoTab:Toggle({ Title = "Auto Steal Eggs", Default=false, Flag="steal_auto",
        Callback=safeC(function(v) autoStealEnabled=v; Notify("Auto Steal",v and "Aktif" or "Nonaktif",v and "Success" or "Error") end) })
    AutoTab:Toggle({ Title = "Defend Egg", Default=false, Flag="phuc_defend_egg",
        Callback=function(v) HUB.V44.defendEgg=v==true end })
    AutoTab:Toggle({ Title = "Only Eggs ≥ 100M Money/s", Default=false, Flag="phuc_100m",
        Callback=function(v) HUB.V44.only100m=v==true end })
    AutoTab:Toggle({ Title = "Rare Egg Hunter (Highest Rarity First)", Default=true, Flag="rare_hunter",
        Callback=function(v) rareEggHunter=v end })
    AutoTab:Toggle({ Title = "Big Eggs Only", Default=false, Flag="big_eggs_only",
        Callback=function(v) stealBigEggsOnly=v end })
    AutoTab:Dropdown({ Title = "Filter Rarity", Options=RARITY_NAMES, Default={}, Flag="steal_rarities",
        Callback=function(v) selectedStealRarities=v end })
    AutoTab:Dropdown({ Title = "Filter Area", Options=AREA_NAMES, Default={}, Flag="steal_areas",
        Callback=function(v) selectedStealAreas=v end })
    AutoTab:Dropdown({ Title = "Filter Mutation", Options=MUTATION_FILTERS, Default={}, Flag="steal_muts",
        Callback=function(v) selectedMutationTypes=v end })
    AutoTab:Slider({ Title = "Glide Speed", Value = {Min=150, Max=850, Default=850}, Suffix=" studs/s", Flag="glide_speed",
        Callback=function(v) glideSpeed=math.clamp(tonumber(v) or 850,150,850) end })
    AutoTab:Slider({ Title = "Steal Delay Gap", Value = {Min=0.35, Max=10, Default=0.75}, Suffix="s", Flag="steal_gap",
        Callback=function(v) stealDelay=math.clamp(tonumber(v) or 0.75,0.35,10) end })
    AutoTab:Button({ Title = "Steal Best Egg Once", Primary=true,
        Callback=safeC(function()
            if stealBusy then Notify("Steal","Sedang busy","Info"); return end
            local eggs=GetMatchingFieldEggs()
            if #eggs==0 then Notify("Steal","Tidak ada egg cocok","Info"); return end
            stealBusy=true; local ok=pcall(StealEgg,eggs[1]); stealBusy=false
            Notify("Steal",ok and "Berhasil!" or "Gagal",ok and "Success" or "Error")
        end) })

    -- Auto Hatch & Plant SubTab
    AutoTab:Toggle({ Title = "Auto Hatch Ready Eggs", Default=false, Flag="hatch_auto",
        Callback=safeC(function(v) autoHatchEnabled=v; Notify("Auto Hatch",v and "Aktif" or "Nonaktif",v and "Success" or "Error") end) })
    AutoTab:Toggle({ Title = "Auto Place Egg in Pen (After Steal)", Default=false, Flag="plant_auto",
        Callback=function(v) autoPlantEnabled=v; Notify("Auto Place",v and "Aktif" or "Nonaktif",v and "Success" or "Error") end })
    AutoTab:Slider({ Title = "Hatch Check Delay", Value = {Min=0.5, Max=10, Default=2.0}, Suffix="s", Flag="hatch_gap",
        Callback=function(v) hatchCheckDelay=tonumber(v) or 2.0 end })
    AutoTab:Button({ Title = "Hatch All Ready Eggs Now", Primary=true,
        Callback=safeC(function()
            local count=HatchAllReadyEggs()
            Notify("Hatch","Hatched "..count.." egg(s)","Success")
        end) })
    AutoTab:Button({ Title = "Place Carried Eggs in Pen Now",
        Callback=safeC(function()
            local count=PlantCarriedEggs()
            Notify("Plant","Planted "..count.." egg(s)","Success")
        end) })

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload=function()
            autoStealEnabled=false; autoHatchEnabled=false; autoPlantEnabled=false; stealBusy=false
            HUB.V44.lockedUid=nil
        end,
        GetState=function() return {steal=autoStealEnabled,hatch=autoHatchEnabled,plant=autoPlantEnabled,busy=stealBusy} end,
        GetMatchingEggs=GetMatchingFieldEggs,
        PlantCarriedEggs=PlantCarriedEggs,
        HatchAllNow=HatchAllReadyEggs,
    }
end

return Init
