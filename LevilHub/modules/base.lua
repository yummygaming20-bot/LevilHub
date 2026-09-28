-- modules/base.lua
-- Modul Base/Plot: Auto Upgrade, Pets, Auto Sell, Rewards, Treadmill
-- Porting dari LevilHub_Steal_An_Egg.lua bagian Base (baris ~8570-8690)

local function Init(HUB)
    local Window  = HUB.Window
    local Notify  = HUB.Notify
    local RS      = game:GetService("ReplicatedStorage")
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local LP       = Players.LocalPlayer

    -- ============================================================
    -- STATE
    -- ============================================================
    local autoUpgradeBase      = false
    local autoUpgradeTreadmill = false
    local autoBuyTrails        = false
    local autoSellPets         = false
    local autoSellEggs         = false
    local autoClaimRewards     = false
    local autoEquipPets        = false

    local selectedSellPetRarities = {}
    local selectedSellEggRarities = {}

    local RARITY_NAMES = {
        "Common","Uncommon","Rare","Epic","Legendary",
        "Mythic","Cosmic","Secret","Eternal","Divine",
        "Light & Dark","Titan","Transcendent","Superior","Limited",
    }

    local SELL_REQUEST_DELAY = 0.15

    -- ============================================================
    -- HELPERS
    -- ============================================================
    local function safeCallback(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[LevilHub/base] " .. tostring(err)) end
        end
    end

    local SaveModule, EggState
    pcall(function() SaveModule = require(RS.Shared.Save)          end)
    pcall(function() EggState   = require(RS.Client.EggState)      end)

    local function GetNetRemote(name)
        local net = RS:FindFirstChild("Packages")
            and RS.Packages:FindFirstChild("Networking")
        return net and net:FindFirstChild(name)
    end

    local function isRarityAllowed(rarityName, filter)
        if not filter or #filter == 0 then return true end
        for _, r in ipairs(filter) do
            if tostring(r):lower() == tostring(rarityName):lower() then return true end
        end
        return false
    end

    local function GetEggRarityName(eggData)
        return tostring(eggData.Rarity or eggData.EggRarity or "Common")
    end

    -- ============================================================
    -- UPGRADE FUNCTIONS
    -- ============================================================
    local function UpgradeHomesteadBase()
        local re1 = GetNetRemote("RE/Homestead/AskNearbyPurchase")
        if re1 then pcall(function() re1:FireServer() end) end
        local re2 = GetNetRemote("RE/Homestead/AskBaseTierRaise")
        if re2 then pcall(function() re2:FireServer() end) end
    end

    local function UpgradeTreadmillTier()
        local rf = GetNetRemote("RF/Treadmill/AskTierRaise")
        if rf then pcall(function() rf:InvokeServer() end) end
    end

    local function EquipBestPets()
        local rf = GetNetRemote("RF/Haul/WearBest")
            or GetNetRemote("RF/PenRoster/ConfirmEquipBestBadge")
        if rf then pcall(function() rf:InvokeServer() end) end
    end

    -- ============================================================
    -- SELL FUNCTIONS
    -- ============================================================
    local function SellSelectedPets()
        local re = GetNetRemote("RE/PetSatchel/SellPet")
        if not re or not SaveModule then return end
        local save
        pcall(function() save = SaveModule.Get and SaveModule.Get() end)
        local inv = save and save.Inventory
        if type(inv) ~= "table" then return end
        for uid, petData in pairs(inv) do
            if type(petData) == "table" and not petData.Locked then
                local rName = petData.Rarity or "Common"
                if isRarityAllowed(rName, selectedSellPetRarities) then
                    pcall(function() re:FireServer(uid) end)
                    task.wait(SELL_REQUEST_DELAY)
                end
            end
        end
    end

    local function SellSelectedEggs()
        if not SaveModule then return end
        local save
        pcall(function() save = SaveModule.Get and SaveModule.Get() end)
        if not save then return end
        local inv = save.EggInventory
        if type(inv) ~= "table" then return end
        local wear = GetNetRemote("RF/EggWorld/AskWearTool")
        local sell = GetNetRemote("RE/PetSatchel/SellPet")
        if not wear or not sell then return end
        for uid, eggData in pairs(inv) do
            if type(eggData) == "table" and not eggData.Placement and not eggData.Locked then
                local rName = GetEggRarityName(eggData)
                if isRarityAllowed(rName, selectedSellEggRarities) then
                    pcall(function() wear:InvokeServer(uid) end)
                    pcall(function() sell:FireServer({uid}) end)
                    task.wait(SELL_REQUEST_DELAY)
                end
            end
        end
    end

    -- ============================================================
    -- REWARDS / CLAIM
    -- ============================================================
    local function ClaimAllAvailableRewards()
        pcall(function()
            local rf1 = GetNetRemote("RF/AwayEarnings/AskCollect")
            if rf1 then rf1:InvokeServer() end
        end)
        pcall(function()
            local rf2 = GetNetRemote("RF/Codex/AskRedeemAll")
            if rf2 then rf2:InvokeServer() end
        end)
        pcall(function()
            local rf3 = GetNetRemote("RF/GroupPerk/RedeemPerk")
            if rf3 then rf3:InvokeServer() end
        end)
    end

    -- ============================================================
    -- AUTO LOOPS
    -- ============================================================
    local lastUpgradeAt     = 0
    local lastSellAt        = 0
    local lastClaimAt       = 0
    local lastEquipAt       = 0

    HUB.Track(RunService.Heartbeat:Connect(function()
        if HUB.dead or HUB.paused then return end
        local now = os.clock()

        if autoUpgradeBase and now - lastUpgradeAt >= 30 then
            lastUpgradeAt = now
            pcall(UpgradeHomesteadBase)
        end
        if autoUpgradeTreadmill and now - lastUpgradeAt >= 30 then
            pcall(UpgradeTreadmillTier)
        end
        if (autoSellPets or autoSellEggs) and now - lastSellAt >= 10 then
            lastSellAt = now
            if autoSellPets then pcall(SellSelectedPets) end
            if autoSellEggs then pcall(SellSelectedEggs) end
        end
        if autoClaimRewards and now - lastClaimAt >= 60 then
            lastClaimAt = now
            pcall(ClaimAllAvailableRewards)
        end
        if autoEquipPets and now - lastEquipAt >= 15 then
            lastEquipAt = now
            pcall(EquipBestPets)
        end
    end))

    -- ============================================================
    -- TAB UI
    -- ============================================================
    local Tab = HUB.UI.Tabs["Auto"]
    HUB.UI.BaseTab = Tab

    -- Homestead & Treadmill
    Tab:AddSection("Homestead & Treadmill")

    Tab:AddToggle({
        Name = "Auto Upgrade Base / Plot", Default = false, Flag = "up_base_auto",
        Callback = function(v) autoUpgradeBase = v end
    })
    Tab:AddToggle({
        Name = "Auto Upgrade Treadmill Tier", Default = false, Flag = "up_tread_auto",
        Callback = function(v) autoUpgradeTreadmill = v end
    })
    Tab:AddToggle({
        Name = "Auto Buy Speed Trails", Default = false, Flag = "auto_buy_trails",
        Callback = function(v) autoBuyTrails = v end
    })
    Tab:AddButton({
        Name = "Upgrade Base Now", Primary = true,
        Callback = safeCallback(function()
            UpgradeHomesteadBase()
            Notify("Base Upgrade", "Requested base upgrade", "Success")
        end)
    })
    Tab:AddButton({
        Name = "Upgrade Treadmill Now",
        Callback = safeCallback(function()
            UpgradeTreadmillTier()
            Notify("Treadmill Upgrade", "Requested treadmill upgrade", "Success")
        end)
    })

    -- Pets & Satchel
    Tab:AddSection("Pets & Satchel")

    Tab:AddToggle({
        Name = "Auto Equip Best Pets", Default = false, Flag = "auto_equip_pets",
        Callback = function(v) autoEquipPets = v end
    })
    Tab:AddButton({
        Name = "Equip Best Pets Now", Primary = true,
        Callback = safeCallback(function()
            EquipBestPets()
            Notify("Pets", "Equipped best pets", "Success")
        end)
    })

    -- Auto Sell
    Tab:AddSection("Auto Sell")

    Tab:AddToggle({
        Name = "Auto Sell Low-Tier Pets", Default = false, Flag = "auto_sell_pets",
        Callback = function(v) autoSellPets = v end
    })
    Tab:AddMultiDropdown({
        Name = "Filter Pet Sell Rarities", Options = RARITY_NAMES, Default = {}, Flag = "sell_pet_rarities",
        Callback = function(selectedList) selectedSellPetRarities = selectedList end
    })
    Tab:AddToggle({
        Name = "Auto Sell Low-Tier Eggs", Default = false, Flag = "auto_sell_eggs",
        Callback = function(v) autoSellEggs = v end
    })
    Tab:AddMultiDropdown({
        Name = "Filter Egg Sell Rarities", Options = RARITY_NAMES, Default = {}, Flag = "sell_egg_rarities",
        Callback = function(selectedList) selectedSellEggRarities = selectedList end
    })
    Tab:AddButton({
        Name = "Sell Selected Pets Now", Primary = true,
        Callback = safeCallback(function()
            SellSelectedPets()
            Notify("Sales", "Sold matching pets", "Success")
        end)
    })
    Tab:AddButton({
        Name = "Sell Selected Eggs Now",
        Callback = safeCallback(function()
            SellSelectedEggs()
            Notify("Sales", "Sold matching eggs", "Success")
        end)
    })

    -- Claim Rewards
    Tab:AddSection("Claim Rewards")

    Tab:AddToggle({
        Name = "Auto Claim Away Earnings & Codex", Default = false, Flag = "claim_auto_rewards",
        Callback = function(v) autoClaimRewards = v end
    })
    Tab:AddButton({
        Name = "Claim Away Earnings & Codex Now", Primary = true,
        Callback = safeCallback(function()
            ClaimAllAvailableRewards()
            Notify("Rewards", "Claimed all ready rewards and earnings", "Success")
        end)
    })

    -- ============================================================
    -- RETURN
    -- ============================================================
    return {
        Unload = function()
            autoUpgradeBase      = false
            autoUpgradeTreadmill = false
            autoBuyTrails        = false
            autoSellPets         = false
            autoSellEggs         = false
            autoClaimRewards     = false
            autoEquipPets        = false
        end,
        GetState = function()
            return {
                upgradeBase  = autoUpgradeBase,
                sellPets     = autoSellPets,
                sellEggs     = autoSellEggs,
                claimRewards = autoClaimRewards,
            }
        end,
    }
end

return Init
