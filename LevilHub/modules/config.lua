-- modules/config.lua
-- Modul Config: Save/Load config, Unload script
-- Porting dari LevilHub_Steal_An_Egg.lua bagian Config (baris ~539-713)

local function Init(HUB)
    local Window     = HUB.Window
    local Notify     = HUB.Notify
    local HttpService = game:GetService("HttpService")

    -- ============================================================
    -- CONFIG SYSTEM
    -- ============================================================
    local CFG = {
        file      = "LevilHub_Config.json",
        data      = {},
        controls  = {},
        restoring = false,
        autoSave  = true,
        pending   = false,
    }
    HUB.CFG = CFG

    -- Baca config dari file
    local function cfgRead()
        if type(readfile) ~= "function" then return nil end
        local ok, result = pcall(function()
            return HttpService:JSONDecode(readfile(CFG.file))
        end)
        return ok and type(result) == "table" and result or nil
    end

    -- Tulis config ke file
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

    -- Debounce auto-save
    local function cfgMarkDirty()
        if CFG.restoring or not CFG.autoSave or CFG.pending then return end
        CFG.pending = true
        task.delay(1.0, function()
            CFG.pending = false
            if not HUB.dead then cfgWrite() end
        end)
    end
    HUB.CFG.MarkDirty = cfgMarkDirty

    -- Saat startup, load nilai yang sudah tersimpan
    local savedCfg = cfgRead()
    if savedCfg then
        CFG.data    = type(savedCfg.values)   == "table"   and savedCfg.values or {}
        CFG.autoSave = type(savedCfg.autoSave) == "boolean" and savedCfg.autoSave or true
    end

    -- ============================================================
    -- CONFIG OPTION WRAPPER
    -- Wrap opts agar callback otomatis save
    -- ============================================================
    function HUB.CFG.Option(opts, kind)
        opts = opts or {}
        local key = opts.Flag or (kind .. ":" .. tostring(opts.Name or "?"))
        local saved = CFG.data[key]

        -- Restore nilai tersimpan ke Default
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

    -- Restore semua nilai tersimpan ke kontrol UI
    function HUB.CFG.RestoreAll()
        CFG.restoring = true
        for key, control in pairs(CFG.controls) do
            local value = CFG.data[key]
            if value == nil then value = control.default end
            if value ~= nil then pcall(control.apply, value) end
        end
        CFG.restoring = false
    end

    -- ============================================================
    -- HELPERS
    -- ============================================================
    local function safeCallback(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[LevilHub/config] " .. tostring(err)) end
        end
    end

    -- ============================================================
    -- TAB UI
    -- ============================================================
    local Tab = HUB.UI.Tabs["Settings"]
    HUB.UI.SettingsTab = Tab

    Tab:Section({ Title = "Configuration" })

    Tab:Toggle({
        Title = "Auto Save Config", Default = true, Flag = "settings_autosave",
        Callback = function(v) CFG.autoSave = v == true end
    })

    Tab:Button({
        Title = "Save Config Now", Primary = true,
        Callback = safeCallback(function()
            local ok = cfgWrite()
            Notify("Config", ok and "Config tersimpan!" or "Gagal simpan (executor tidak support writefile)", ok and "Success" or "Error")
        end)
    })

    Tab:Button({
        Title = "Load Config",
        Callback = safeCallback(function()
            local saved = cfgRead()
            if not saved then
                Notify("Config", "File config tidak ditemukan", "Error"); return
            end
            CFG.data    = type(saved.values) == "table" and saved.values or {}
            CFG.autoSave = type(saved.autoSave) == "boolean" and saved.autoSave or true
            HUB.CFG.RestoreAll()
            Notify("Config", "Config dimuat!", "Success")
        end)
    })

    Tab:Button({
        Title = "Reset Config",
        Callback = safeCallback(function()
            CFG.data = {}
            cfgWrite()
            Notify("Config", "Config direset. Restart script untuk efek penuh.", "Info")
        end)
    })

    -- Unloader
    Tab:Section({ Title = "Unload" })

    Tab:Button({
        Title = "Unload LevilHub", Primary = true,
        Callback = safeCallback(function()
            Notify("LevilHub", "Unloading...", "Info", 2)
            task.delay(0.5, function()
                if type(HUB.Unload) == "function" then
                    pcall(HUB.Unload)
                end
            end)
        end)
    })

    Tab:Toggle({
        Title = "Auto Resume on Rejoin", Default = true, Flag = "settings_resume",
        Callback = safeCallback(function(v)
            -- Queue resume script di executor
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
                    if type(qot) == "function" then
                        qot(resumeCode)
                    end
                end)
            end
        end)
    })

    -- Version info
    Tab:Paragraph({
        Title   = "LevilHub Info",
        Content = "Version modular — levilstore.my.id\nBuild: " .. tostring(os.date and os.date("%Y-%m-%d") or "2025")
    })

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload = function()
            -- Final save saat unload
            pcall(cfgWrite)
        end,
        GetState = function()
            return { autoSave = CFG.autoSave }
        end,
    }
end

return Init
