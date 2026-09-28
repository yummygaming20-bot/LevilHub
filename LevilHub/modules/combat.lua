-- modules/combat.lua
-- Modul Combat: Bat Aura, Anti-Trap, Anti-Ragdoll, No-Knockback
-- Porting dari LevilHub_Steal_An_Egg.lua bagian Combat (baris ~6185-6200, 8692-8748)

local function Init(HUB)
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
    local BatSub = Tab:AddSubTab("Bat & Slap Aura")
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
    local GuardSub = Tab:AddSubTab("Defense & Guards")
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

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload = function()
            batAuraEnabled     = false
            avoidTrapsEnabled  = false
            noKnockbackEnabled = false
            antiRagdollEnabled = false
        end,
        GetState = function()
            return {
                batAura    = batAuraEnabled,
                trapImmune = avoidTrapsEnabled,
                noKnockback = noKnockbackEnabled,
                antiRagdoll = antiRagdollEnabled,
            }
        end,
    }
end

return Init
