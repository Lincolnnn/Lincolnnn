--[[
    RP Ganghunt - client : menu (NUI), commande
    -------------------------------------------
    /ganghunt : menu (faction, vagues et ennemis par vague, armes et pourcentages ou aléatoire, véhicules,
    hélicoptère, silencieux, grenades, musique, neutres, arrivée des vagues) ;
    /ganghunt stop : arrête la chasse en cours. (Volontairement absent du MDC et du /tuto.)
    Aucune boucle : le menu ne tourne que pendant qu'il est ouvert (NUI), Échap le ferme sans ouvrir la carte.
]]

local Config = GanghuntConfig
local open = false

--- Échap : le jeu ne doit pas ouvrir le menu pause juste après la fermeture du menu
local function blockPause()
    CreateThread(function()
        local untilTime, extra = GetGameTimer() + 3000, 10
        while extra > 0 and GetGameTimer() < untilTime and not open do
            for _, c in ipairs({ 199, 200, 322 }) do DisableControlAction(0, c, true) end
            if IsPauseMenuActive() then SetPauseMenuActive(false) end
            if not (IsDisabledControlPressed(0, 200) or IsDisabledControlPressed(0, 322)) then extra = extra - 1 end
            Wait(0)
        end
    end)
end

local function closeMenu()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    blockPause()
end

--- Nom du véhicule affiché dans le jeu (ex. « Police Cruiser »), sinon le nom du modèle
local function vehicleLabel(model)
    local label = GetLabelText(GetDisplayNameFromVehicleModel(GetHashKey(model)))
    if not label or label == '' or label == 'NULL' then return model end
    return label
end

--- Ce que le menu affiche : catégories, factions (véhicules, hélicoptère), armes, limites
local menuData = nil
local function buildMenuData()
    if menuData then return menuData end
    local categories = {}
    for _, category in ipairs(Config.Categories) do
        local factions = {}
        for _, key in ipairs(category.factions) do
            local f = Config.Factions[key]
            if f then
                local vehicles = {}
                for _, model in ipairs(f.vehicles or {}) do vehicles[#vehicles + 1] = { model = model, label = vehicleLabel(model) } end
                factions[#factions + 1] = { key = key, label = f.label, vehicles = vehicles, heli = f.heli,
                    heliLabel = f.heli and vehicleLabel(f.heli) or nil, armour = f.armour or Config.Armour or 0 }
            end
        end
        categories[#categories + 1] = { key = category.key, label = category.label, factions = factions }
    end
    local weapons = {}
    for _, w in ipairs(Config.Weapons) do
        weapons[#weapons + 1] = { name = w.name, label = w.label, handgun = w.handgun == true, special = w.special == true }
    end
    menuData = { categories = categories, weapons = weapons, maxWaves = Config.MaxWaves or 10,
        waveSize = Config.WaveSize or 10, maxWaveSize = Config.MaxWaveSize or 30, maxWeapons = Config.MaxWeapons or 10,
        waveTimer = Config.WaveTimer or { Default = 60, Min = 15, Max = 600, Step = 15 },
        sidearm = Config.DefaultSidearm or 'WEAPON_COMBATPISTOL' }
    return menuData
end

local function openMenu()
    if open then return end
    open = true
    SetNuiFocus(true, true)
    local data = buildMenuData()
    local s = GH.session()
    SendNUIMessage({ action = 'open', data = { config = data, active = GH.active(),
        current = s and { faction = s.faction.label, wave = s.wave, waves = s.waves } or nil } })
end

RegisterCommand(Config.Command or 'ganghunt', function(_, args)
    if (args[1] or ''):lower() == 'stop' then
        if not GH.active() then return GH.notify('Aucune chasse en cours.') end
        closeMenu()
        return GH.stop('Chasse arrêtée.')
    end
    if open then closeMenu() else openMenu() end
end, false)
TriggerEvent('chat:addSuggestion', '/' .. (Config.Command or 'ganghunt'), 'Vagues d\'ennemis qui vous traquent', {
    { name = 'stop', help = 'facultatif : « stop » arrête la chasse en cours' },
})

-- =========================================================================
-- CALLBACKS NUI
-- =========================================================================
RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closeMenu()
end)

RegisterNUICallback('start', function(data, cb)
    data = type(data) == 'table' and data or {}
    local weapons = nil
    if not data.random then
        weapons = {}
        local total = 0
        for _, w in ipairs(type(data.weapons) == 'table' and data.weapons or {}) do
            local pct = math.floor(tonumber(w.pct) or 0)
            if type(w.name) == 'string' and pct > 0 then
                weapons[#weapons + 1] = { name = w.name, pct = pct }
                total = total + pct
            end
        end
        if #weapons == 0 then return cb({ ok = false, error = 'Choisissez au moins une arme (ou « Aléatoire »).' }) end
        if #weapons > (Config.MaxWeapons or 10) then
            return cb({ ok = false, error = ('%d armes au plus.'):format(Config.MaxWeapons or 10) })
        end
        if total ~= 100 then return cb({ ok = false, error = ('Les pourcentages font %d %% (il faut 100 %%).'):format(total) }) end
    end
    local ok, err = GH.start({ faction = data.faction, waves = data.waves, waveSize = data.waveSize, weapons = weapons,
        vehicles = data.vehicles == true, heli = data.heli == true, silencer = data.silencer == true,
        grenades = data.grenades == true, music = data.music == true, passive = data.passive == true,
        waveMode = data.waveMode, waveTimer = data.waveTimer })
    cb({ ok = ok, error = err })
    if ok then closeMenu() end
end)

RegisterNUICallback('stop', function(_, cb)
    cb({ ok = true })
    closeMenu()
    GH.stop('Chasse arrêtée.')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)
