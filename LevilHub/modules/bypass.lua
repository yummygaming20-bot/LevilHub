-- modules/bypass.lua
-- Modul Bypass Anti Cheat & Anti-Hit (GodMode, Humanoid Clone)
-- Porting dari YOKUDO HUB → LevilHub modular system

local function Init(HUB)
    HUB = HUB or _G.LevilHub
    local Notify     = HUB.Notify
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    -- ============================================================
    -- STATE
    -- ============================================================
    local bypassEnabled  = false
    local godModeEnabled = false
    local godModeLoop    = nil   -- RBXScriptConnection / task handle
    local charConn       = nil   -- CharacterAdded connection
    local activeHumanoid = nil   -- humanoid baru hasil clone

    -- ============================================================
    -- HELPERS
    -- ============================================================
    local function safeC(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[LevilHub/bypass] " .. tostring(err)) end
        end
    end

    -- ============================================================
    -- REFRESH CONTROLS & CAMERA  (supaya karakter tetap bisa gerak)
    -- ============================================================
    local function RefreshControls(char)
        local ps = LP:FindFirstChild("PlayerScripts")
        if not ps then return end
        local pm = ps:FindFirstChild("PlayerModule")
        if not pm then return end
        local ok, mod = pcall(function() return require(pm) end)
        if not ok or not mod then return end
        pcall(function()
            local ctrl = mod:GetControls()
            if ctrl then
                ctrl:OnCharacterAdded(char)
                ctrl:UpdateActiveControlModuleEnabled()
            end
        end)
    end

    -- ============================================================
    -- APPLY GOD MODE  (loop-safe, dipanggil dari within bypass)
    -- ============================================================
    local function ApplyGodMode(hum)
        if not hum or not hum.Parent then return end
        pcall(function()
            hum.MaxHealth = math.huge
            hum.Health    = math.huge
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
            hum.BreakJointsOnDeath = false
            hum.RequiresNeck       = false
        end)
    end

    -- ============================================================
    -- CORE: BYPASS (clone humanoid baru)
    -- ============================================================
    local function RunBypass()
        local char = LP.Character
        if not char then return end

        local oldHum = char:FindFirstChildOfClass("Humanoid")
        if not oldHum then return end

        -- Simpan properti penting sebelum destroy
        local jumpPower, jumpHeight, useJumpPower, evalSM
        pcall(function() jumpPower    = oldHum.JumpPower         end)
        pcall(function() jumpHeight   = oldHum.JumpHeight        end)
        pcall(function() useJumpPower = oldHum.UseJumpPower      end)
        pcall(function() evalSM       = oldHum.EvaluateStateMachine end)
        jumpPower  = jumpPower  or 50
        jumpHeight = jumpHeight or 7.2

        -- Clone → pindahkan children → replace
        local newHum = oldHum:Clone()
        if not newHum then return end
        newHum.Name = oldHum.Name

        for _, child in ipairs(oldHum:GetChildren()) do
            local existing = newHum:FindFirstChild(child.Name)
            if existing then pcall(function() existing:Destroy() end) end
            pcall(function() child.Parent = newHum end)
        end

        oldHum:Destroy()
        task.wait()
        newHum.Parent = char
        task.wait()

        -- Restore properti
        pcall(function() newHum.UseJumpPower = useJumpPower end)
        pcall(function() newHum.JumpPower    = jumpPower    end)
        pcall(function() newHum.JumpHeight   = jumpHeight   end)
        pcall(function()
            if evalSM ~= nil then newHum.EvaluateStateMachine = evalSM end
        end)

        activeHumanoid = newHum

        -- GodMode langsung aktif kalau toggle godMode nyala
        if godModeEnabled then
            ApplyGodMode(newHum)

            -- HealthChanged & Died guard
            newHum.HealthChanged:Connect(function(hp)
                if godModeEnabled and hp < newHum.MaxHealth then
                    pcall(function() newHum.Health = newHum.MaxHealth end)
                end
            end)
            newHum.Died:Connect(function()
                if godModeEnabled then
                    pcall(function() newHum.Health = newHum.MaxHealth end)
                end
            end)
        end

        -- Refresh kamera + kontrol
        RefreshControls(char)
        pcall(function()
            local cam = workspace.CurrentCamera
            if cam then cam.CameraSubject = newHum end
        end)

        Notify("Bypass", "Anti-Cheat bypass aktif ✅", "Success", 3)
    end

    -- ============================================================
    -- GOD MODE LOOP (0.1s tick, hanya jalan kalau toggle aktif)
    -- ============================================================
    local function StartGodLoop()
        if godModeLoop then return end   -- sudah jalan
        godModeLoop = task.spawn(function()
            while godModeEnabled and not HUB.dead do
                if activeHumanoid and activeHumanoid.Parent then
                    ApplyGodMode(activeHumanoid)
                end
                task.wait(0.1)
            end
            godModeLoop = nil
        end)
    end

    local function StopGodLoop()
        godModeLoop = nil   -- loop akan exit sendiri di iterasi berikutnya
    end

    -- ============================================================
    -- CHARACTER ADDED HOOK
    -- ============================================================
    local function OnCharacterAdded(char)
        if not bypassEnabled then return end
        task.wait(1)
        RunBypass()
    end

    -- ============================================================
    -- UI: Section di tab Combat
    -- ============================================================
    local Section = HUB.UI.MakeSection("Combat", "Bypass Anti-Cheat")

    -- Toggle utama: aktifkan/nonaktifkan seluruh bypass
    Section:AddToggle({
        Name    = "Bypass Anti-Cheat",
        Desc    = "Clone humanoid untuk bypass deteksi anti-cheat & anti-hit",
        Default = false,
        Flag    = "bypass_anticheat",
        Callback = safeC(function(v)
            bypassEnabled = v
            if v then
                -- Pasang listener CharacterAdded
                if charConn then charConn:Disconnect() end
                charConn = LP.CharacterAdded:Connect(OnCharacterAdded)
                -- Jalankan sekarang juga
                task.spawn(function()
                    task.wait(0.5)
                    RunBypass()
                end)
            else
                -- Lepas listener, matikan god mode loop
                if charConn then charConn:Disconnect(); charConn = nil end
                godModeEnabled = false
                StopGodLoop()
                Notify("Bypass", "Anti-Cheat bypass dinonaktifkan", "Error", 2.5)
            end
        end),
    })

    -- Toggle God Mode (sub-fitur, hanya efektif kalau bypass aktif)
    Section:AddToggle({
        Name    = "God Mode (No Death)",
        Desc    = "Lock HP = ∞ dan disable state Dead. Butuh Bypass aktif dulu.",
        Default = false,
        Flag    = "bypass_godmode",
        Callback = safeC(function(v)
            godModeEnabled = v
            if v then
                if not bypassEnabled then
                    Notify("Bypass", "Aktifkan Bypass Anti-Cheat dulu!", "Error", 3)
                    return
                end
                if activeHumanoid and activeHumanoid.Parent then
                    ApplyGodMode(activeHumanoid)
                end
                StartGodLoop()
                Notify("Bypass", "God Mode aktif — HP dikunci ∞", "Success", 3)
            else
                StopGodLoop()
                -- Kembalikan MaxHealth normal (100) supaya tidak broken
                if activeHumanoid and activeHumanoid.Parent then
                    pcall(function()
                        activeHumanoid.MaxHealth = 100
                        activeHumanoid.Health    = 100
                        activeHumanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
                        activeHumanoid.BreakJointsOnDeath = true
                        activeHumanoid.RequiresNeck       = true
                    end)
                end
                Notify("Bypass", "God Mode dinonaktifkan", "Error", 2.5)
            end
        end),
    })

    -- Tombol manual re-run bypass (berguna kalau karakter respawn/teleport)
    Section:AddButton({
        Name     = "Re-Run Bypass Sekarang",
        Desc     = "Paksa jalankan ulang bypass di karakter saat ini",
        Callback = safeC(function()
            if not bypassEnabled then
                Notify("Bypass", "Aktifkan toggle Bypass dulu!", "Error", 3)
                return
            end
            task.spawn(function()
                task.wait(0.3)
                RunBypass()
                if godModeEnabled then StartGodLoop() end
            end)
        end),
    })

    Section:AddParagraph({
        Title   = "⚠️ Catatan",
        Content = "Clone humanoid bisa disconnect animasi/sounds sebentar.\n"
               .. "God Mode: MaxHealth diset ∞ tiap 0.1 detik.\n"
               .. "Re-run otomatis tiap CharacterAdded saat bypass aktif.",
    })

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload = function()
            bypassEnabled  = false
            godModeEnabled = false
            StopGodLoop()
            if charConn then charConn:Disconnect(); charConn = nil end
            -- Pulihkan humanoid normal kalau masih ada
            if activeHumanoid and activeHumanoid.Parent then
                pcall(function()
                    activeHumanoid.MaxHealth = 100
                    activeHumanoid.Health    = 100
                    activeHumanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
                    activeHumanoid.BreakJointsOnDeath = true
                    activeHumanoid.RequiresNeck       = true
                end)
            end
            activeHumanoid = nil
        end,
        GetState = function()
            return {
                bypassEnabled  = bypassEnabled,
                godModeEnabled = godModeEnabled,
            }
        end,
    }
end

return Init
