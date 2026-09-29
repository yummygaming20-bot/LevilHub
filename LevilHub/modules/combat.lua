-- modules/combat.lua
-- Modul Combat: Bat Aura, Anti-Trap, Anti-Ragdoll, No-Knockback, Auto Attack
-- Porting dari LevilHub_Steal_An_Egg.lua bagian Combat (baris ~6185-6200, 8692-8748)

local function Init(HUB)
    HUB = HUB or _G.LevilHub
    local Window     = HUB.Window
    local Notify     = HUB.Notify
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local LP         = Players.LocalPlayer

    -- ============================================================
    -- STATE
    -- ============================================================
    local batAuraEnabled    = false
    local batAuraRadius     = 20
    local batAuraDelay      = 0.2
    local avoidTrapsEnabled = true
    local noKnockbackEnabled = true
    local antiRagdollEnabled = true
    local lastBatSwing      = 0

    -- Auto Attack state
    local autoEquipEnabled  = false
    local autoHitEnabled    = false
    local autoHitRange      = 60
    local autoHitInterval   = 0.01
    local autoEquipConn     = nil
    local autoHitConn       = nil
    local autoHitLastFire   = 0
    local autoHitTraceSeq   = 0
    local charAddedConn     = nil
    local Backpack          = LP:WaitForChild("Backpack")

    -- Auto Hit Thief state
    local autoHitThiefEnabled = false
    local thiefHitRange       = 25
    local thiefHitInterval    = 0.01
    local thiefHitConn        = nil
    local thiefHitLastFire    = 0
    local thiefHitTraceSeq    = 0

    -- ============================================================
    -- HELPERS
    -- ============================================================
    local function safeCallback(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[LevilHub/combat] " .. tostring(err)) end
        end
    end

    local function findHRP()
        local char = LP.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function findHum()
        local char = LP.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function GetNetRemote(name)
        local net = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
            and game:GetService("ReplicatedStorage").Packages:FindFirstChild("Networking")
        return net and net:FindFirstChild(name)
    end

    -- ============================================================
    -- ANTI-TRAP: Neutralize enemy traps di Workspace
    -- ============================================================
    local function NeutralizeTraps()
        local debris = Workspace:FindFirstChild("__DEBRIS")
        if not debris then return end
        for _, d in ipairs(debris:GetChildren()) do
            if d.Name == "PlayerTrap" and d:GetAttribute("Owner") ~= LP.Name then
                if d:IsA("BasePart") then
                    d.CanTouch = false
                    d.CanQuery = false
                end
                for _, c in ipairs(d:GetChildren()) do
                    if c:IsA("BasePart") then
                        c.CanTouch = false
                        c.CanQuery = false
                        if c.Name == "Hitbox" then
                            c.CFrame = CFrame.new(0, -999, 0)
                        end
                    end
                end
                local tt = d:FindFirstChildWhichIsA("TouchTransmitter", true)
                if tt then pcall(function() tt:Destroy() end) end
            end
        end
    end

    -- Pasang trap-neutralizer setiap 2 detik saat enabled
    HUB.Track(RunService.Heartbeat:Connect(function()
        if HUB.dead then return end
        if avoidTrapsEnabled then
            pcall(NeutralizeTraps)
        end
    end))

    -- ============================================================
    -- NO KNOCKBACK: Disconnect RigSync
    -- ============================================================
    local function SetNoKnockback(enabled)
        noKnockbackEnabled = enabled
        if enabled then
            pcall(function()
                local rigSync = GetNetRemote("RE/RigSync/Refresh")
                if rigSync and getconnections then
                    for _, conn in ipairs(getconnections(rigSync.OnClientEvent)) do
                        pcall(function() conn:Disconnect() end)
                    end
                end
            end)
        end
    end

    -- ============================================================
    -- ANTI-RAGDOLL
    -- ============================================================
    HUB.Track(RunService.Heartbeat:Connect(function()
        if HUB.dead or not antiRagdollEnabled then return end
        local hum = findHum()
        if hum and hum:GetState() == Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end))

    -- ============================================================
    -- BAT AURA
    -- ============================================================
    HUB.Track(RunService.Heartbeat:Connect(function()
        if HUB.dead or not batAuraEnabled then return end
        local now = os.clock()
        if now - lastBatSwing < batAuraDelay then return end

        local hrp = findHRP()
        if not hrp then return end

        -- Cari player terdekat dalam radius
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                local enemyHRP = plr.Character:FindFirstChild("HumanoidRootPart")
                if enemyHRP then
                    local dist = (enemyHRP.Position - hrp.Position).Magnitude
                    if dist <= batAuraRadius then
                        -- Fire bat swing remote
                        pcall(function()
                            local re = GetNetRemote("RE/BatSwing/Trigger")
                            if re then re:FireServer() end
                        end)
                        lastBatSwing = now
                        break
                    end
                end
            end
        end
    end))

    -- ============================================================
    -- AUTO ATTACK: helpers
    -- ============================================================
    local function FindBatTool()
        for _, tool in ipairs(Backpack:GetChildren()) do
            if tool:IsA("Tool") and (tool.ToolTip == "Bat" or tool.Name:find("Bat")) then
                return tool
            end
        end
        local char = LP.Character
        if char then
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") and (tool.ToolTip == "Bat" or tool.Name:find("Bat")) then
                    return tool
                end
            end
        end
        return nil
    end

    local function GetBatSwingRemote()
        local ok, remote = pcall(function()
            return game:GetService("ReplicatedStorage").Packages.Networking["RE/BatSwing/Trigger"]
        end)
        return ok and remote or nil
    end

    local function EquipBat()
        local bat = FindBatTool()
        if not bat then return end
        local hum = findHum()
        if bat.Parent == Backpack and hum then
            hum:EquipTool(bat)
        end
    end

    local function FindClosestPlayerInRange(range)
        local hrp = findHRP()
        if not hrp then return nil end
        local closest, closestDist = nil, range
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                local hum  = plr.Character:FindFirstChildOfClass("Humanoid")
                local root = plr.Character:FindFirstChild("HumanoidRootPart")
                if hum and root and hum.Health > 0 then
                    local dist = (root.Position - hrp.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closest = plr
                    end
                end
            end
        end
        return closest
    end

    -- Auto Equip loop
    local function StartAutoEquip()
        if autoEquipConn then return end
        autoEquipConn = RunService.Heartbeat:Connect(function()
            if not autoEquipEnabled then return end
            local bat = FindBatTool()
            if bat and bat.Parent == Backpack then EquipBat() end
        end)
        EquipBat()
    end

    local function StopAutoEquip()
        if autoEquipConn then autoEquipConn:Disconnect(); autoEquipConn = nil end
    end

    -- Auto Hit loop
    local function StartAutoHit()
        if autoHitConn then return end
        autoHitConn = RunService.Heartbeat:Connect(function()
            if not autoHitEnabled then return end
            local now = tick()
            if now - autoHitLastFire < autoHitInterval then return end
            autoHitLastFire = now

            local target = FindClosestPlayerInRange(autoHitRange)
            if not target then return end

            local remote = GetBatSwingRemote()
            if not remote then return end

            autoHitTraceSeq = autoHitTraceSeq + 1
            local traceId = tostring(LP.UserId) .. ":" .. autoHitTraceSeq
                         .. ":" .. tostring(math.floor(workspace:GetServerTimeNow() * 1000))
            pcall(function() remote:FireServer(target, traceId) end)
        end)
    end

    local function StopAutoHit()
        if autoHitConn then autoHitConn:Disconnect(); autoHitConn = nil end
    end

    -- Cari player yang lagi bawa egg (HasEgg attribute / carrying state)
    local function FindEggThief()
        local hrp = findHRP()
        if not hrp then return nil end
        local RS = game:GetService("ReplicatedStorage")
        local closest, closestDist = nil, thiefHitRange

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                local hum  = plr.Character:FindFirstChildOfClass("Humanoid")
                local root = plr.Character:FindFirstChild("HumanoidRootPart")
                if hum and root and hum.Health > 0 then
                    -- Cek apakah player ini lagi bawa egg:
                    -- 1) Attribute "CarryingEgg" / "HasEgg" di character
                    -- 2) Ada Tool bernama "Egg" di character
                    local isThief = false
                    pcall(function()
                        isThief = plr.Character:GetAttribute("CarryingEgg") == true
                            or plr.Character:GetAttribute("HasEgg") == true
                    end)
                    if not isThief then
                        for _, obj in ipairs(plr.Character:GetChildren()) do
                            if obj:IsA("Tool") and (obj.Name:find("Egg") or obj.Name:find("egg")) then
                                isThief = true; break
                            end
                        end
                    end
                    if isThief then
                        local dist = (root.Position - hrp.Position).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closest = plr
                        end
                    end
                end
            end
        end
        return closest
    end

    local function StartAutoHitThief()
        if thiefHitConn then return end
        thiefHitConn = RunService.Heartbeat:Connect(function()
            if not autoHitThiefEnabled then return end
            local now = tick()
            if now - thiefHitLastFire < thiefHitInterval then return end
            thiefHitLastFire = now

            local target = FindEggThief()
            if not target then return end

            local remote = GetBatSwingRemote()
            if not remote then return end

            thiefHitTraceSeq = thiefHitTraceSeq + 1
            local traceId = tostring(LP.UserId) .. ":" .. thiefHitTraceSeq
                         .. ":" .. tostring(math.floor(workspace:GetServerTimeNow() * 1000))
            pcall(function() remote:FireServer(target, traceId) end)
        end)
    end

    local function StopAutoHitThief()
        if thiefHitConn then thiefHitConn:Disconnect(); thiefHitConn = nil end
    end

    -- Re-equip saat CharacterAdded
    charAddedConn = LP.CharacterAdded:Connect(function()
        if autoEquipEnabled then
            task.wait(1)
            EquipBat()
        end
    end)
    HUB.Track(charAddedConn)

    -- ============================================================
    -- AUTO-INIT saat pertama load
    -- ============================================================
    pcall(function() if avoidTrapsEnabled then NeutralizeTraps() end end)
    pcall(function() if noKnockbackEnabled then SetNoKnockback(true) end end)

    -- ============================================================
    -- TAB UI
    -- ============================================================
    local Tab = HUB.UI.Tabs["Combat"]
    -- Combat Tab dari main

    -- Bat & Slap Aura
    local BatSub = HUB.UI.MakeSection("Combat", "Bat & Slap Aura")
    HUB.UI.BatSub = BatSub

    BatSub:AddToggle({
        Name = "Bat / Slap Aura", Default = false, Flag = "bat_aura_enabled",
        Callback = safeCallback(function(v)
            batAuraEnabled = v
            Notify("Bat Aura", v and "Aktif" or "Nonaktif", v and "Success" or "Error")
        end)
    })
    BatSub:AddSlider({
        Name = "Aura Radius", Min = 5, Max = 50, Default = 20,
        Suffix = " studs", Flag = "bat_radius",
        Callback = function(v) batAuraRadius = tonumber(v) or 20 end
    })
    BatSub:AddSlider({
        Name = "Swing Delay", Min = 0.05, Max = 1.0, Default = 0.2,
        Suffix = "s", Flag = "bat_delay",
        Callback = function(v) batAuraDelay = tonumber(v) or 0.2 end
    })
    BatSub:AddButton({
        Name = "Swing Bat Once (Manual)", Primary = true,
        Callback = safeCallback(function()
            local re = GetNetRemote("RE/BatSwing/Trigger")
            if re then re:FireServer() end
            Notify("Bat", "Swing triggered", "Info")
        end)
    })

    -- Defense & Guards
    local GuardSub = HUB.UI.MakeSection("Combat", "Defense & Guards")
    HUB.UI.GuardSub = GuardSub

    GuardSub:AddToggle({
        Name = "Anti-Trap (Full Immunity / Destroy Hitboxes)", Default = true, Flag = "avoid_traps",
        Callback = safeCallback(function(v)
            avoidTrapsEnabled = v
            if v then pcall(NeutralizeTraps) end
            Notify("Anti-Trap", v and "Immunity aktif" or "Nonaktif", v and "Success" or "Error")
        end)
    })
    GuardSub:AddToggle({
        Name = "No Knockback / Ragdoll Immunity", Default = true, Flag = "no_knockback",
        Callback = safeCallback(function(v)
            SetNoKnockback(v)
            Notify("Knockback", v and "Immunity aktif" or "Enabled kembali", v and "Success" or "Error")
        end)
    })
    GuardSub:AddToggle({
        Name = "Anti-Ragdoll (Quick Standup)", Default = true, Flag = "anti_ragdoll",
        Callback = function(v) antiRagdollEnabled = v end
    })

    -- Auto Attack
    local AutoAttackSub = HUB.UI.MakeSection("Combat", "Auto Attack")

    AutoAttackSub:AddToggle({
        Name = "Auto Equip Bat", Default = false, Flag = "autoattack_equip",
        Desc = "Otomatis equip bat dari backpack setiap saat",
        Callback = safeCallback(function(v)
            autoEquipEnabled = v
            if v then StartAutoEquip() else StopAutoEquip() end
            Notify("Auto Equip", v and "Aktif" or "Nonaktif", v and "Success" or "Error")
        end)
    })

    AutoAttackSub:AddToggle({
        Name = "Auto Hit (Fire Remote)", Default = false, Flag = "autoattack_hit",
        Desc = "Fire BatSwing remote ke player terdekat dalam range",
        Callback = safeCallback(function(v)
            autoHitEnabled = v
            if v then StartAutoHit() else StopAutoHit() end
            Notify("Auto Hit", v and "Aktif" or "Nonaktif", v and "Success" or "Error")
        end)
    })

    AutoAttackSub:AddSlider({
        Name = "Attack Range", Min = 10, Max = 150, Default = 60,
        Suffix = " studs", Flag = "autoattack_range",
        Callback = function(v) autoHitRange = tonumber(v) or 60 end
    })

    AutoAttackSub:AddSlider({
        Name = "Fire Interval", Min = 0.01, Max = 1.0, Default = 0.01,
        Suffix = "s", Flag = "autoattack_interval",
        Callback = function(v) autoHitInterval = tonumber(v) or 0.01 end
    })

    -- Auto Hit Thief
    local ThiefSub = HUB.UI.MakeSection("Combat", "Auto Hit Egg Thief")

    ThiefSub:AddToggle({
        Name = "Auto Hit Egg Thief", Default = false, Flag = "autohit_thief",
        Desc = "Otomatis pukul player yang lagi bawa egg dalam range",
        Callback = safeCallback(function(v)
            autoHitThiefEnabled = v
            if v then
                StartAutoHitThief()
                -- Auto equip bat juga kalau belum
                if not autoEquipEnabled then EquipBat() end
            else
                StopAutoHitThief()
            end
            Notify("Hit Thief", v and "Aktif — memukul egg thief!" or "Nonaktif", v and "Success" or "Error")
        end)
    })

    ThiefSub:AddSlider({
        Name = "Thief Hit Range", Min = 5, Max = 100, Default = 25,
        Suffix = " studs", Flag = "thief_hit_range",
        Callback = function(v) thiefHitRange = tonumber(v) or 25 end
    })

    ThiefSub:AddSlider({
        Name = "Thief Fire Interval", Min = 0.01, Max = 1.0, Default = 0.01,
        Suffix = "s", Flag = "thief_hit_interval",
        Callback = function(v) thiefHitInterval = tonumber(v) or 0.01 end
    })

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload = function()
            batAuraEnabled      = false
            avoidTrapsEnabled   = false
            noKnockbackEnabled  = false
            antiRagdollEnabled  = false
            autoEquipEnabled    = false
            autoHitEnabled      = false
            autoHitThiefEnabled = false
            StopAutoEquip()
            StopAutoHit()
            StopAutoHitThief()
        end,
        GetState = function()
            return {
                batAura         = batAuraEnabled,
                trapImmune      = avoidTrapsEnabled,
                noKnockback     = noKnockbackEnabled,
                antiRagdoll     = antiRagdollEnabled,
                autoEquip       = autoEquipEnabled,
                autoHit         = autoHitEnabled,
                autoHitThief    = autoHitThiefEnabled,
            }
        end,
    }
end

return Init
