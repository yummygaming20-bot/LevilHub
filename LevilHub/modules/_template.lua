local function Init(HUB)
    local Notify = HUB.Notify
  
    local Tab = HUB.UI.Tabs["Auto"] -- ganti sesuai kebutuhan
    local Section = HUB.UI.MakeSection("Auto", "Nama Section")
    local enabled = false

    local function safeC(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[LevilHub/NAMA_MODUL] " .. tostring(err)) end
        end
    end
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
    
        end,
    })

    Section:AddButton({
        Name     = "Contoh Button",
        Primary  = true,
        Callback = safeC(function()
            Notify("NAMA_MODUL", "Button ditekan!", "Info")
        end),
    })

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
