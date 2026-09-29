local function Init(HUB)
    HUB = HUB or _G.LevilHub
    local Window      = HUB.Window
    local Notify      = HUB.Notify
    local HttpService = game:GetService("HttpService")

    local CFG = {
        file      = "LevilHub_Config.json",
        data      = {},
        controls  = {},
        restoring = false,
        autoSave  = true,
        pending   = false,
    }

    -- Expose via _G supaya tidak hilang setelah obfuscate
    _G.LH_CFG = CFG

    local function cfgRead()
        if type(readfile) ~= "function" then return nil end
        local ok, result = pcall(function()
            return HttpService:JSONDecode(readfile(CFG.file))
        end)
        return ok and type(result) == "table" and result or nil
    end

    local function cfgWrite()
        if type(writefile) ~= "function" then return false end
        local ok = pcall(function()
            writefile(CFG.file, HttpService:JSONEncode({
                version  = 1,
                autoSave = CFG.autoSave,
                values   = CFG.data,
            }))
        end)
        return ok
    end

    local function cfgMarkDirty()
        if CFG.restoring or not CFG.autoSave or CFG.pending then return end
        CFG.pending = true
        task.delay(1.0, function()
            CFG.pending = false
            local hub = _G.LevilHub
            if hub and not hub.dead then cfgWrite() end
        end)
    end
    CFG.MarkDirty = cfgMarkDirty
    _G.LH_CFG = CFG

    local savedCfg = cfgRead()
    if savedCfg then
        CFG.data     = type(savedCfg.values)   == "table"   and savedCfg.values   or {}
        CFG.autoSave = type(savedCfg.autoSave) == "boolean" and savedCfg.autoSave or true
    end

    CFG.Option = function(opts, kind)
        opts = opts or {}
        local key   = opts.Flag or (kind .. ":" .. tostring(opts.Name or "?"))
        local saved = CFG.data[key]
        if kind == "toggle" and type(saved) == "boolean" then
            opts.Default = saved
        elseif kind == "slider" and type(saved) == "number" then
            opts.Default = math.clamp(saved, tonumber(opts.Min) or 0, tonumber(opts.Max) or 100)
        elseif kind == "dropdown" and type(saved) == "string" then
            opts.Default = saved
        elseif kind == "multi" and type(saved) == "table" then
            opts.Default = saved
        end
        local userCb = opts.Callback
        opts.Callback = function(value, ...)
            if not CFG.restoring then
                local safe = value
                if type(value) == "table" then
                    safe = {}
                    for k, v in pairs(value) do safe[k] = v end
                end
                CFG.data[key] = safe
                cfgMarkDirty()
            end
            if userCb then return userCb(value, ...) end
        end
        return opts, key
    end

    CFG.RestoreAll = function()
        CFG.restoring = true
        for key, control in pairs(CFG.controls) do
            local value = CFG.data[key]
            if value == nil then value = control.default end
            if value ~= nil then pcall(control.apply, value) end
        end
        CFG.restoring = false
    end

    -- Juga pasang ke HUB supaya modul lain bisa akses via HUB.CFG
    HUB.CFG = CFG

    local function safeCallback(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[LevilHub/config] " .. tostring(err)) end
        end
    end

    local Tab    = HUB.UI.Tabs["Settings"]
    local CfgSub = HUB.UI.MakeSection("Settings", "Configuration")

    CfgSub:AddToggle({
        Name = "Auto Save Config", Default = true, Flag = "settings_autosave",
        Callback = function(v) CFG.autoSave = v == true end
    })

    CfgSub:AddButton({
        Name = "Save Config Now", Primary = true,
        Callback = safeCallback(function()
            local ok = cfgWrite()
            Notify("Config", ok and "Config tersimpan!" or "Gagal simpan", ok and "Success" or "Error")
        end)
    })

    CfgSub:AddButton({
        Name = "Load Config",
        Callback = safeCallback(function()
            local saved = cfgRead()
            if not saved then Notify("Config", "File config tidak ditemukan", "Error"); return end
            CFG.data     = type(saved.values)   == "table"   and saved.values   or {}
            CFG.autoSave = type(saved.autoSave) == "boolean" and saved.autoSave or true
            CFG.RestoreAll()
            Notify("Config", "Config dimuat!", "Success")
        end)
    })

    CfgSub:AddButton({
        Name = "Reset Config",
        Callback = safeCallback(function()
            CFG.data = {}
            cfgWrite()
            Notify("Config", "Config direset. Restart script untuk efek penuh.", "Info")
        end)
    })

    local UnloadSub = HUB.UI.MakeSection("Settings", "Unload")

    UnloadSub:AddButton({
        Name = "Unload LevilHub", Primary = true,
        Callback = safeCallback(function()
            Notify("LevilHub", "Unloading...", "Info", 2)
            task.delay(0.5, function()
                local hub = _G.LevilHub
                if hub and type(hub.Unload) == "function" then
                    pcall(hub.Unload)
                end
            end)
        end)
    })

    UnloadSub:AddToggle({
        Name = "Auto Resume on Rejoin", Default = true, Flag = "settings_resume",
        Callback = safeCallback(function(v)
            if v and type(writefile) == "function" then
                local resumeCode = [[
if not game:IsLoaded() then game.Loaded:Wait() end
local lp = game:GetService("Players").LocalPlayer
if not lp then game:GetService("Players"):GetPropertyChangedSignal("LocalPlayer"):Wait() end
if type(readfile) == "function" and type(loadstring) == "function" then
    local ok, src = pcall(readfile, "LevilHub_loader.lua")
    if ok and type(src) == "string" then
        local fn = loadstring(src)
        if fn then fn() end
    end
end
]]
                pcall(function()
                    writefile("LevilHub_Resume.lua", resumeCode)
                    local qot = queue_on_teleport or queueonteleport
                    if type(qot) == "function" then qot(resumeCode) end
                end)
            end
        end)
    })

    Tab:AddParagraph({
        Title   = "LevilHub Info",
        Content = "Version modular — levilstore.my.id\nBuild: " .. tostring(os.date and os.date("%Y-%m-%d") or "2025")
    })

    return {
        Unload = function() pcall(cfgWrite) end,
        GetState = function() return { autoSave = CFG.autoSave } end,
    }
end

return Init
