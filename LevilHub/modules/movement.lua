-- modules/movement.lua
-- Modul Movement: WalkSpeed, JumpPower, Infinite Jump, Fly, Anti-AFK, Area/Plot/Player Travel
-- Porting dari LevilHub_Steal_An_Egg.lua bagian Movement (baris ~8751-8950)

local function Init(HUB)
    local Window      = HUB.Window
    local Notify      = HUB.Notify
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")
    local Lighting    = game:GetService("Lighting")
    local VirtualUser = game:GetService("VirtualUser")
    local LP          = Players.LocalPlayer

    -- ============================================================
    -- STATE
    -- ============================================================
    local walkSpeedEnabled   = false
    local walkSpeedValue     = 24
    local originalWalkSpeed  = nil
    local jumpPowerEnabled   = false
    local jumpPowerValue     = 50
    local infiniteJump       = false
    local flyEnabled         = false
    local flySpeed           = 80
    local antiAFKEnabled     = true
    local fullbrightEnabled  = false
    local stopFlyFn          = nil
    local afkAt              = 0

    local AREA_COORDINATES = {
        ["Base / Plot"]    = Vector3.new(491.7,  70.4, -364.4),
        ["Stands & Shops"] = Vector3.new(539.5,  68.0, -364.5),
        ["Forest"]         = Vector3.new(596.0,  68.0, -328.0),
        ["Lake"]           = Vector3.new(744.0,  68.5, -408.0),
        ["Desert"]         = Vector3.new(948.0,  69.5, -323.0),
        ["Jungle"]         = Vector3.new(1188.0, 68.5, -408.0),
        ["Snow"]           = Vector3.new(1492.0, 69.0, -315.0),
        ["Volcano"]        = Vector3.new(1882.0, 68.0, -398.0),
        ["Abyss Ocean"]    = Vector3.new(2280.0, 68.0, -326.0),
        ["Prehistoric"]    = Vector3.new(2812.0, 69.0, -398.0),
        ["Cosmic"]         = Vector3.new(3390.0, 68.0, -324.0),
        ["Cherry Blossom"] = Vector3.new(4028.0, 68.5, -396.0),
        ["Titan Temple"]   = Vector3.new(4796.0, 69.5, -328.0),
        ["Light Dark"]     = Vector3.new(5660.0, 70.0, -331.0),
        ["Dragon Event"]   = Vector3.new(539.5,  68.0, -318.0),
    }
    local AREA_KEYS = {}
    for k in pairs(AREA_COORDINATES) do table.insert(AREA_KEYS, k) end
    table.sort(AREA_KEYS)

    local MAIN_ROAD_Z    = -364.5
    local SAFE_BOUNDARY_X = 580
    local SAFE_ZONE_SPEED = 245

    -- ============================================================
    -- HELPERS
    -- ============================================================
    local function safeCallback(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[LevilHub/movement] " .. tostring(err)) end
        end
    end

    local function findHRP()
        local c = LP.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function findHum()
        local c = LP.Character
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    -- ============================================================
    -- WALKSPEED / JUMPPOWER
    -- ============================================================
    local function ApplyWalkSpeed(v)
        if not walkSpeedEnabled then return end
        local hum = findHum()
        if hum then hum.WalkSpeed = tonumber(v) or walkSpeedValue end
    end
    HUB.Runtime.ApplyWalkSpeed = ApplyWalkSpeed

    local function ApplyJumpPower(v)
        if not jumpPowerEnabled then return end
        local hum = findHum()
        if hum then
            pcall(function() hum.JumpPower  = tonumber(v) or jumpPowerValue end)
            pcall(function() hum.JumpHeight = tonumber(v) or jumpPowerValue end)
        end
    end

    HUB.Track(LP.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if walkSpeedEnabled then ApplyWalkSpeed(walkSpeedValue) end
        if jumpPowerEnabled  then ApplyJumpPower(jumpPowerValue) end
    end))

    -- ============================================================
    -- INFINITE JUMP
    -- ============================================================
    HUB.Track(UserInputService.JumpRequest:Connect(function()
        if not infiniteJump then return end
        local hum = findHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))

    -- ============================================================
    -- SMOOTH FLY (WASD + Space/Shift)
    -- ============================================================
    local function StartFly()
        if stopFlyFn then stopFlyFn(); stopFlyFn = nil end
        local running = true
        local flyConn
        flyConn = RunService.RenderStepped:Connect(function(dt)
            if not running or HUB.dead then flyConn:Disconnect(); return end
            local hrp = findHRP()
            local hum = findHum()
            if not hrp or not hum then return end

            hum.PlatformStand = true
            local camera = Workspace.CurrentCamera
            if not camera then return end

            local camLook = camera.CFrame.LookVector
            local camRight = camera.CFrame.RightVector
            local moveVec = Vector3.new(0, 0, 0)
            local speed = flySpeed * dt

            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                moveVec = moveVec + camLook
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                moveVec = moveVec - camLook
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                moveVec = moveVec - camRight
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                moveVec = moveVec + camRight
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                moveVec = moveVec + Vector3.new(0,1,0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                moveVec = moveVec - Vector3.new(0,1,0)
            end

            if moveVec.Magnitude > 0 then
                hrp.CFrame = hrp.CFrame + moveVec.Unit * speed
            end
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)

        stopFlyFn = function()
            running = false
            local hum = findHum()
            if hum then hum.PlatformStand = false end
        end
    end

    local function StopFly()
        if stopFlyFn then stopFlyFn(); stopFlyFn = nil end
    end

    -- ============================================================
    -- ANTI-AFK
    -- ============================================================
    local function SetAntiAFK(enabled)
        antiAFKEnabled = enabled
    end
    HUB.Runtime.SetAntiAFK = SetAntiAFK

    HUB.Track(RunService.Heartbeat:Connect(function()
        if HUB.dead or not antiAFKEnabled then return end
        local now = os.clock()
        if now - afkAt >= 210 then
            afkAt = now
            pcall(function() VirtualUser:CaptureController() end)
            pcall(function() VirtualUser:ClickButton2(Vector2.new()) end)
        end
    end))

    -- ============================================================
    -- FULLBRIGHT
    -- ============================================================
    local origAmbient, origOutdoor, origBrightness
    local function SetFullbright(enabled)
        fullbrightEnabled = enabled
        if enabled then
            origAmbient    = Lighting.Ambient
            origOutdoor    = Lighting.OutdoorAmbient
            origBrightness = Lighting.Brightness
            Lighting.Ambient       = Color3.fromRGB(255,255,255)
            Lighting.OutdoorAmbient = Color3.fromRGB(255,255,255)
            Lighting.Brightness    = 2
        else
            if origAmbient    then Lighting.Ambient        = origAmbient    end
            if origOutdoor    then Lighting.OutdoorAmbient = origOutdoor    end
            if origBrightness then Lighting.Brightness     = origBrightness end
        end
    end

    -- ============================================================
    -- TRAVEL FUNCTIONS
    -- ============================================================
    local function MoveToPoint(target, speed)
        local hrp = findHRP()
        if not hrp or not target then return false end
        local start = hrp.Position
        local dist = (target - start).Magnitude
        if dist < 1.0 then
            hrp.CFrame = CFrame.new(target.X, math.max(target.Y, 70.0), target.Z)
            hrp.AssemblyLinearVelocity = Vector3.zero
            return true
        end
        speed = math.clamp(tonumber(speed) or 500, 50, 850)
        local t0 = os.clock()
        while not HUB.dead do
            local dt = RunService.Heartbeat:Wait()
            local cur = hrp.Position
            local toT = target - cur
            local rem = toT.Magnitude
            if rem < 1.0 then break end
            local step = math.min(speed * dt, rem)
            local dir  = toT.Unit
            local next = cur + dir * step
            hrp.CFrame = CFrame.lookAt(next, next + dir)
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            if os.clock() - t0 > (dist / 50 + 5) then break end
        end
        hrp.CFrame = CFrame.new(target.X, math.max(target.Y, 70.0), target.Z)
        hrp.AssemblyLinearVelocity = Vector3.zero
        return true
    end

    local function TravelRoadPath(targetPos, speed)
        local hrp = findHRP()
        if not hrp or not targetPos then return false end
        local startPos = hrp.Position
        local safeY    = math.max(startPos.Y, targetPos.Y, 70.4)
        local isBase   = targetPos.X < 560

        if isBase and startPos.X > SAFE_BOUNDARY_X then
            MoveToPoint(Vector3.new(startPos.X,  safeY, MAIN_ROAD_Z), speed)
            MoveToPoint(Vector3.new(SAFE_BOUNDARY_X, safeY, MAIN_ROAD_Z), speed)
            MoveToPoint(Vector3.new(targetPos.X, safeY, MAIN_ROAD_Z), SAFE_ZONE_SPEED)
            MoveToPoint(targetPos + Vector3.new(0,1.2,0), SAFE_ZONE_SPEED)
        else
            MoveToPoint(Vector3.new(startPos.X,  safeY, MAIN_ROAD_Z), speed)
            MoveToPoint(Vector3.new(targetPos.X, safeY, MAIN_ROAD_Z), speed)
            MoveToPoint(targetPos + Vector3.new(0,1.2,0), speed)
        end
        return true
    end
    HUB.Runtime.TravelRoadPath = TravelRoadPath

    -- ============================================================
    -- TAB UI
    -- ============================================================
    local Tab = HUB.UI.Tabs["Player"]
    -- Player Tab dari main

    -- Movement
    local MoveSub = Tab:AddSubTab("Movement")
    HUB.UI.MoveSub = MoveSub

    MoveSub:AddToggle({
        Name = "Enable WalkSpeed", Default = false, Flag = "speed_enabled",
        Callback = safeCallback(function(v)
            walkSpeedEnabled = v
            local hum = findHum()
            if hum then
                if v then
                    originalWalkSpeed = hum.WalkSpeed
                    hum.WalkSpeed = walkSpeedValue
                else
                    hum.WalkSpeed = originalWalkSpeed or 16
                end
            end
            Notify("WalkSpeed", v and "Aktif" or "Nonaktif", v and "Success" or "Error")
        end)
    })
    MoveSub:AddSlider({
        Name = "WalkSpeed Value", Min = 16, Max = 500, Default = 60,
        Suffix = " studs/s", Flag = "speed_val",
        Callback = function(v)
            walkSpeedValue = tonumber(v) or 60
            ApplyWalkSpeed(walkSpeedValue)
        end
    })
    MoveSub:AddToggle({
        Name = "Enable JumpPower", Default = false, Flag = "jump_enabled",
        Callback = safeCallback(function(v)
            jumpPowerEnabled = v
            if v then ApplyJumpPower(jumpPowerValue) end
        end)
    })
    MoveSub:AddSlider({
        Name = "JumpPower Value", Min = 50, Max = 500, Default = 100,
        Flag = "jump_val",
        Callback = function(v)
            jumpPowerValue = tonumber(v) or 100
            ApplyJumpPower(jumpPowerValue)
        end
    })
    MoveSub:AddToggle({
        Name = "Infinite Jump", Default = false, Flag = "phuc_infinite_jump",
        Callback = function(v) infiniteJump = v end
    })
    MoveSub:AddToggle({
        Name = "Smooth Fly (WASD + Space/Shift)", Default = false, Flag = "fly_enabled",
        Callback = safeCallback(function(v)
            flyEnabled = v
            if v then StartFly() else StopFly() end
            Notify("Fly", v and "Aktif" or "Nonaktif", v and "Success" or "Error")
        end)
    })
    MoveSub:AddSlider({
        Name = "Fly Speed", Min = 20, Max = 500, Default = 80,
        Flag = "fly_speed",
        Callback = function(v) flySpeed = tonumber(v) or 80 end
    })
    MoveSub:AddToggle({
        Name = "Anti-AFK (Bypass 20min Kick)", Default = true, Flag = "anti_afk",
        Callback = function(v) SetAntiAFK(v) end
    })

    -- Area Travel
    local AreaTpSub = Tab:AddSubTab("Area Travel")
    local selectedAreaTp = "Base / Plot"

    AreaTpSub:AddDropdown({
        Name = "Select Area", Options = AREA_KEYS, Default = "Base / Plot", Flag = "tele_area",
        Callback = function(v) selectedAreaTp = v end
    })
    AreaTpSub:AddButton({
        Name = "Travel to Selected Area", Primary = true,
        Callback = safeCallback(function()
            local pos = AREA_COORDINATES[selectedAreaTp]
            if not pos then Notify("Travel", "Area tidak ditemukan", "Error"); return end
            Notify("Travel", "Menuju " .. selectedAreaTp, "Info")
            task.spawn(function() TravelRoadPath(pos, 700) end)
        end)
    })

    -- Plot Travel
    local PlotSub = Tab:AddSubTab("Plot Travel")

    PlotSub:AddButton({
        Name = "My Plot", Primary = true,
        Callback = safeCallback(function()
            local RS = game:GetService("ReplicatedStorage")
            local PlotState
            pcall(function() PlotState = require(RS.Client.PlotState) end)
            local plotObj = PlotState and PlotState.ResolvePlot and PlotState.ResolvePlot()
            local pt = plotObj and plotObj.CenterPoint
            local pos = pt and (typeof(pt) == "Vector3" and pt
                or (pt:IsA("BasePart") and pt.Position))
                or Vector3.new(464.7, 70.4, -364.0)
            Notify("Travel", "Menuju plot kamu", "Info")
            task.spawn(function() TravelRoadPath(pos, 500) end)
        end)
    })

    -- Player Travel
    local PlayerSub = Tab:AddSubTab("Player Travel")
    local selectedPlayer = nil
    local playerNames    = {}

    local function refreshPlayers()
        playerNames = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then table.insert(playerNames, p.Name) end
        end
        if #playerNames == 0 then playerNames = {"(no other players)"} end
        return playerNames
    end
    refreshPlayers()

    local playerDropdown = PlayerSub:AddDropdown({
        Name = "Select Player", Options = playerNames, Default = playerNames[1], Flag = "tp_player",
        Callback = function(v) selectedPlayer = v end
    })
    PlayerSub:AddButton({
        Name = "Refresh Player List",
        Callback = safeCallback(function()
            refreshPlayers()
            if playerDropdown.SetOptions then playerDropdown:SetOptions(playerNames) end
            Notify("Travel", "List diperbarui", "Info")
        end)
    })
    PlayerSub:AddButton({
        Name = "Travel to Player", Primary = true,
        Callback = safeCallback(function()
            if not selectedPlayer or selectedPlayer == "(no other players)" then
                Notify("Travel", "Pilih player dulu", "Info"); return
            end
            local target = Players:FindFirstChild(selectedPlayer)
            local hrpT   = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            if not hrpT then Notify("Travel", "Player tidak ditemukan", "Error"); return end
            Notify("Travel", "Menuju " .. selectedPlayer, "Info")
            task.spawn(function() TravelRoadPath(hrpT.Position, 700) end)
        end)
    })

    -- Visuals
    local VisSub = Tab:AddSubTab("Visuals & Performance")
    VisSub:AddToggle({
        Name = "Fullbright (Daylight Visuals)", Default = false, Flag = "fullbright",
        Callback = safeCallback(function(v)
            SetFullbright(v)
            Notify("Fullbright", v and "Aktif" or "Nonaktif", v and "Success" or "Error")
        end)
    })
    VisSub:AddButton({
        Name = "Delete Own Pet Renders (FPS Boost)",
        Callback = safeCallback(function()
            local count = 0
            for _, container in ipairs({Workspace:FindFirstChild("Pets"), Workspace:FindFirstChild("RenderedPets")}) do
                if container then
                    for _, child in ipairs(container:GetChildren()) do
                        if child:IsA("Model") or child:IsA("BasePart") then
                            pcall(function() child:Destroy(); count += 1 end)
                        end
                    end
                end
            end
            Notify("Performance", "Dihapus " .. count .. " model pet", "Success")
        end)
    })

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload = function()
            StopFly()
            SetFullbright(false)
            walkSpeedEnabled = false
            jumpPowerEnabled = false
            infiniteJump     = false
            antiAFKEnabled   = false
        end,
        GetState = function()
            return {
                walkSpeed = walkSpeedEnabled,
                jumpPower = jumpPowerEnabled,
                fly       = flyEnabled,
                antiAFK   = antiAFKEnabled,
            }
        end,
    }
end

return Init
