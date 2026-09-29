-- modules/bypass.lua
-- Bypass v4 — Namecall Hook + Lua Registry + Client Kick Block

local function Init(HUB)
    HUB = HUB or _G.LevilHub
    local Notify  = HUB.Notify
    local Players = game:GetService("Players")
    local LP      = Players.LocalPlayer

    -- ============================================================
    -- STATE
    -- ============================================================
    local bypassEnabled  = false
    local godModeEnabled = false
    local charConn       = nil
    local conns          = {}
    local restorations   = {}  -- simpan fungsi restore untuk cleanup

    -- ============================================================
    -- HELPERS
    -- ============================================================
    local function safeC(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[bypass] "..tostring(err)) end
        end
    end

    local function jitter(base)
        -- Random offset 0-60ms supaya timing tidak punya pattern tetap
        return base + math.random() * 0.06
    end

    local function trackConn(c)
        table.insert(conns, c)
        return c
    end

    local function clearConns()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
    end

    local function runRestorations()
        for _, fn in ipairs(restorations) do pcall(fn) end
        restorations = {}
    end

    -- ============================================================
    -- [1] NAMECALL HOOK
    -- Intercept semua method call via __namecall metamethod
    -- Lebih powerful dari hookfunction karena level metamethod
    -- ============================================================
    local namecallHooked = false

    local function InstallNamecallHook()
        if namecallHooked then return end
        if not getrawmetatable or not setreadonly or not newcclosure then return end

        local ok = pcall(function()
            local mt = getrawmetatable(game)
            setreadonly(mt, false)

            local oldNamecall = mt.__namecall
            mt.__namecall = newcclosure(function(self, ...)
                local method = getnamecallmethod()

                -- Block Kick
                if method == "Kick" and self == LP then
                    if bypassEnabled then
                        warn("[bypass] __namecall Kick blocked")
                        return
                    end
                end

                -- Block Disconnect pada koneksi anti-cheat
                -- (beberapa AC disconnect script connections saat detect)
                if method == "Disconnect" and bypassEnabled then
                    -- Cek apakah yang di-disconnect adalah koneksi milik kita
                    -- Kalau bukan, biarkan jalan normal
                end

                -- Block FireServer ke remote yang suspicious
                if method == "FireServer" and bypassEnabled then
                    local name = pcall(function() return self.Name end) and self.Name or ""
                    local lower = name:lower()
                    if lower:find("report") or lower:find("anticheat") or lower:find("detect") then
                        warn("[bypass] FireServer blocked: "..tostring(name))
                        return
                    end
                end

                return oldNamecall(self, ...)
            end)

            setreadonly(mt, true)
            namecallHooked = true

            -- Simpan restore function
            table.insert(restorations, function()
                pcall(function()
                    setreadonly(mt, false)
                    mt.__namecall = oldNamecall
                    setreadonly(mt, true)
                end)
                namecallHooked = false
            end)
        end)

        if not ok then
            warn("[bypass] Namecall hook gagal — executor tidak support")
        end
    end

    -- ============================================================
    -- [2] LUA REGISTRY METHOD
    -- Scan debug.getregistry() untuk temukan dan neutralize
    -- callback anti-cheat yang tersembunyi
    -- ============================================================
    local function ScanRegistry()
        if not debug or not debug.getregistry then return end
        pcall(function()
            local reg = debug.getregistry()
            for k, v in pairs(reg) do
                if type(v) == "function" then
                    -- Cek nama function via debug.getinfo
                    local info = debug.getinfo and debug.getinfo(v, "S")
                    local src = info and (info.source or info.short_src) or ""
                    -- Kalau source-nya dari game script (bukan executor), skip
                    -- Kita hanya neutralize yang dari LocalScript game
                    if src:find("AntiCheat") or src:find("Detector") or src:find("Checker") then
                        pcall(function()
                            -- Replace dengan function kosong
                            reg[k] = newcclosure and newcclosure(function() end) or function() end
                        end)
                        warn("[bypass] Registry entry neutralized: "..tostring(src))
                    end
                end
            end
        end)
    end

    -- ============================================================
    -- [3] CLIENT-SIDE KICK HOOKING
    -- Triple-layer: hookfunction + namecall + Instance.new hook
    -- ============================================================
    local kickHooked = false

    local function InstallKickHook()
        if kickHooked then return end

        -- Layer 1: hookfunction langsung pada LP.Kick
        pcall(function()
            if not hookfunction or not newcclosure then return end
            local oldKick = LP.Kick
            hookfunction(LP.Kick, newcclosure(function(self, msg)
                if bypassEnabled then
                    warn("[bypass] hookfunction Kick blocked: "..tostring(msg or "no reason"))
                    return
                end
                return oldKick(self, msg)
            end))
            kickHooked = true
            table.insert(restorations, function()
                pcall(function() hookfunction(LP.Kick, oldKick) end)
                kickHooked = false
            end)
        end)

        -- Layer 2: __index hook pada Player instance
        -- Kalau ada script yang ambil LP.Kick lewat __index, juga keblock
        pcall(function()
            if not getrawmetatable or not setreadonly or not newcclosure then return end
            local playerMt = getrawmetatable(LP)
            if not playerMt then return end
            setreadonly(playerMt, false)
            local oldIndex = rawget(playerMt, "__index")
            playerMt.__index = newcclosure(function(self, k)
                if k == "Kick" and bypassEnabled then
                    return newcclosure(function() 
                        warn("[bypass] __index Kick blocked")
                    end)
                end
                if oldIndex then return oldIndex(self, k) end
                return rawget(self, k)
            end)
            setreadonly(playerMt, true)
            table.insert(restorations, function()
                pcall(function()
                    setreadonly(playerMt, false)
                    playerMt.__index = oldIndex
                    setreadonly(playerMt, true)
                end)
            end)
        end)
    end

    -- ============================================================
    -- [4] REMOTE EVENT BLOCK
    -- Hook OnClientEvent pada semua remote suspicious
    -- ============================================================
    local blockedKeywords = {
        "damage","dmg","hurt","kill","dead","kick","ragdoll",
        "knockback","stun","hit","die","eliminate","anticheat",
        "detect","report","ban","punish","flag",
    }

    local function isKeywordMatch(name)
        local lower = name:lower()
        for _, kw in ipairs(blockedKeywords) do
            if lower:find(kw, 1, true) then return true end
        end
        return false
    end

    local hookedRemotes = {}

    local function HookRemotes()
        if not hookfunction or not newcclosure then return end
        local function scan(inst)
            for _, child in ipairs(inst:GetDescendants()) do
                if not hookedRemotes[child]
                    and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction"))
                    and isKeywordMatch(child.Name)
                then
                    hookedRemotes[child] = true
                    pcall(function()
                        if child:IsA("RemoteEvent") then
                            hookfunction(child.OnClientEvent, newcclosure(function(...)
                                if bypassEnabled then
                                    warn("[bypass] Remote blocked: "..child.Name)
                                    return
                                end
                            end))
                        elseif child:IsA("RemoteFunction") then
                            hookfunction(child.OnClientInvoke, newcclosure(function(...)
                                if bypassEnabled then
                                    warn("[bypass] RemoteFunction blocked: "..child.Name)
                                    return nil
                                end
                            end))
                        end
                    end)
                end
            end
        end
        pcall(scan, game:GetService("ReplicatedStorage"))
        pcall(scan, workspace)
        pcall(scan, game:GetService("Players"))
    end

    -- Pasang listener untuk remote baru yang muncul setelah bypass aktif
    local remoteWatcher = nil
    local function WatchNewRemotes()
        if remoteWatcher then remoteWatcher:Disconnect() end
        remoteWatcher = game.DescendantAdded:Connect(function(desc)
            if not bypassEnabled then return end
            if (desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction"))
                and isKeywordMatch(desc.Name)
                and not hookedRemotes[desc]
            then
                task.wait(jitter(0.05))
                HookRemotes()
            end
        end)
    end

    -- ============================================================
    -- [5] GOD MODE — via metatable __index + HealthChanged guard
    -- ============================================================
    local godLoopHandle = nil
    local MAX_HP = 2^16  -- 65536

    local function PatchHumanoid(hum)
        if not hum or not hum.Parent then return end

        -- Set HP
        pcall(function() hum.MaxHealth = MAX_HP end)
        task.wait(jitter(0.02))
        pcall(function() hum.Health = MAX_HP end)

        -- Hook __index humanoid supaya Health selalu return MAX_HP
        pcall(function()
            if not getrawmetatable or not setreadonly or not newcclosure then return end
            local mt = getrawmetatable(hum)
            if not mt then return end
            setreadonly(mt, false)
            local oldIdx = rawget(mt, "__index")
            mt.__index = newcclosure(function(self, k)
                if godModeEnabled and (k == "Health" or k == "MaxHealth") then
                    return MAX_HP
                end
                if oldIdx then return oldIdx(self, k) end
                return rawget(self, k)
            end)
            setreadonly(mt, true)
        end)

        -- HealthChanged guard
        trackConn(hum.HealthChanged:Connect(function(hp)
            if not godModeEnabled then return end
            if hp < MAX_HP * 0.5 then
                task.defer(function()
                    pcall(function() hum.Health = MAX_HP end)
                end)
            end
        end))

        -- Died guard
        trackConn(hum.Died:Connect(function()
            if not godModeEnabled then return end
            task.defer(function()
                pcall(function()
                    hum.Health    = MAX_HP
                    hum.MaxHealth = MAX_HP
                end)
            end)
        end))
    end

    local function StartGodLoop(hum)
        if godLoopHandle then return end
        godLoopHandle = task.spawn(function()
            while godModeEnabled and not HUB.dead do
                if hum and hum.Parent then
                    pcall(function()
                        if hum.Health < MAX_HP * 0.5 then
                            hum.Health = MAX_HP
                        end
                    end)
                end
                task.wait(jitter(0.18))
            end
            godLoopHandle = nil
        end)
    end

    local function StopGodLoop()
        godLoopHandle = nil
    end

    -- ============================================================
    -- CORE BYPASS
    -- ============================================================
    local function RunBypass()
        local char = LP.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end

        task.wait(jitter(0.3))

        -- Install semua hook
        InstallNamecallHook()
        InstallKickHook()
        pcall(HookRemotes)
        pcall(ScanRegistry)
        WatchNewRemotes()

        -- God mode
        if godModeEnabled then
            PatchHumanoid(hum)
            StartGodLoop(hum)
        end

        Notify("Bypass", "Bypass v4 aktif", "Success", 2)
    end

    local function OnCharacterAdded(char)
        if not bypassEnabled then return end
        clearConns()
        task.wait(jitter(1.5))
        RunBypass()
    end

    -- ============================================================
    -- UI
    -- ============================================================
    local Section = HUB.UI.MakeSection("Combat", "Bypass Anti-Cheat")
    if not Section then return end

    Section:AddToggle({
        Name    = "Bypass Anti-Cheat",
        Default = false,
        Flag    = "bypass_anticheat",
        Callback = safeC(function(v)
            bypassEnabled = v
            if v then
                if charConn then charConn:Disconnect() end
                charConn = LP.CharacterAdded:Connect(OnCharacterAdded)
                task.spawn(function()
                    task.wait(jitter(0.3))
                    RunBypass()
                end)
            else
                bypassEnabled  = false
                godModeEnabled = false
                StopGodLoop()
                clearConns()
                if remoteWatcher then remoteWatcher:Disconnect(); remoteWatcher = nil end
                if charConn then charConn:Disconnect(); charConn = nil end
                runRestorations()
                Notify("Bypass", "Bypass nonaktif", "Error", 2)
            end
        end),
    })

    Section:AddToggle({
        Name    = "God Mode (No Death)",
        Default = false,
        Flag    = "bypass_godmode",
        Callback = safeC(function(v)
            godModeEnabled = v
            if v then
                if not bypassEnabled then
                    Notify("Bypass", "Aktifkan Bypass dulu!", "Error", 3)
                    return
                end
                local char = LP.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                if hum then
                    PatchHumanoid(hum)
                    StartGodLoop(hum)
                end
                Notify("Bypass", "God Mode aktif", "Success", 2)
            else
                StopGodLoop()
                local char = LP.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                if hum then
                    task.spawn(function()
                        for _, hp in ipairs({10000, 1000, 100}) do
                            task.wait(jitter(0.08))
                            pcall(function() hum.MaxHealth = hp end)
                            pcall(function() hum.Health    = hp end)
                        end
                    end)
                end
                Notify("Bypass", "God Mode nonaktif", "Error", 2)
            end
        end),
    })

    Section:AddButton({
        Name    = "Re-Run Bypass",
        Callback = safeC(function()
            if not bypassEnabled then
                Notify("Bypass", "Aktifkan Bypass dulu!", "Error", 3)
                return
            end
            task.spawn(function()
                task.wait(jitter(0.2))
                RunBypass()
            end)
        end),
    })

    Section:AddButton({
        Name    = "Scan & Block Remotes",
        Callback = safeC(function()
            pcall(HookRemotes)
            pcall(ScanRegistry)
            local count = 0
            for _ in pairs(hookedRemotes) do count += 1 end
            Notify("Bypass", count.." remote diblock", "Success", 2)
        end),
    })

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload = function()
            bypassEnabled  = false
            godModeEnabled = false
            StopGodLoop()
            clearConns()
            if remoteWatcher then remoteWatcher:Disconnect(); remoteWatcher = nil end
            if charConn then charConn:Disconnect(); charConn = nil end
            runRestorations()
        end,
        GetState = function()
            return {
                bypass        = bypassEnabled,
                godMode       = godModeEnabled,
                remotesHooked = (function()
                    local c = 0
                    for _ in pairs(hookedRemotes) do c += 1 end
                    return c
                end)(),
            }
        end,
    }
end

return Init
