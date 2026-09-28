-- modules/_template.lua
-- Template modul LevilHub
-- Salin file ini untuk bikin modul baru

local function Init(HUB)
    local Notify = HUB.Notify

    -- ============================================================
    -- AMBIL TAB DARI MAIN
    -- Key: "Auto" | "ESP" | "Combat" | "Player" | "Settings"
    -- ============================================================
    local Tab = HUB.UI.Tabs["Auto"] -- ganti sesuai kebutuhan

    -- ============================================================
    -- TAMBAH SUBTAB DI DALAM TAB
    -- ============================================================
    local Section = Tab:AddSection("Nama SubTab")

    -- ============================================================
    -- STATE
    -- ============================================================
    local enabled = false

    -- ============================================================
    -- HELPER
    -- ============================================================
    local function safeC(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[LevilHub/NAMA_MODUL] " .. tostring(err)) end
        end
    end

    -- ============================================================
    -- UI CONTROLS
    -- ============================================================
    Section:AddToggle({
        Name     = "Contoh Toggle",
        Default  = false,
        Flag     = "nama_flag_unik",
        Callback = safeC(function(v)
            enabled = v
            Notify("NAMA_MODUL", v and "Aktif" or "Nonaktif", v and "Success" or "Error")
        end),
    })

    Section:AddSlider({
        Name     = "Contoh Slider",
        Min      = 1, Max = 100, Default = 50,
        Suffix   = "x",
        Flag     = "nama_slider_flag",
        Callback = function(v)
            -- gunakan nilai v
        end,
    })

    Section:AddButton({
        Name     = "Contoh Button",
        Primary  = true,
        Callback = safeC(function()
            Notify("NAMA_MODUL", "Button ditekan!", "Info")
        end),
    })

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload = function()
            enabled = false
        end,
        GetState = function()
            return { enabled = enabled }
        end,
    }
end

return Init
