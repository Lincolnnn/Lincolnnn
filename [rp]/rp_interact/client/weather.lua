--[[
    RP Interact - météo et heure (client) : appliquées d'après le serveur (GlobalState rpWeather / rpClock)
    ------------------------------------------------------------------------------------------------------
    HEURE : le serveur publie la minute exacte (et la republie toutes les SyncSeconds secondes) ; ce client avance à
    partir de là avec sa propre horloge (GetGameTimer), horloge du jeu en pause : fixe, de base ou réaliste, la même
    pour tout le monde. Un petit écart à la mise à jour suivante est rattrapé en douceur (jamais de saut en arrière).
    MÉTÉO : changement en douceur (TransitionSeconds), puis le temps est fixé (comme vSync) ; vérifié toutes les
    5 s : s'il a été changé par le jeu ou un autre script, il revient. Jamais ré-appliqué pendant une transition.
    COUPURE DE COURANT : éclairage de la ville éteint (phares des véhicules gardés). NEIGE AU SOL : sol enneigé, traces
    des véhicules et des pas (cochée dans le menu, ou automatique avec Noël et les temps de neige).
    Performance : une mise à jour de l'heure par seconde (une native), une vérification de la météo toutes les 5 s.
]]

local W = InteractConfig.Weather or {}
if W.Enabled == false then return end

--- Empreinte sur 32 bits non signés (les natives de météo la renvoient tantôt signée, tantôt non)
local function u32(h) return (math.tointeger(h) or math.floor(tonumber(h) or 0)) & 0xFFFFFFFF end

local clock = nil    -- { base = minute reçue, at = GetGameTimer() à la réception, ms = ms par minute du jeu }
local weather = nil  -- météo voulue (nom)
local applied = nil  -- météo appliquée
local transitionUntil = 0
local extras = { blackout = false, snow = false } -- voulus (serveur)
local appliedExtras = { blackout = nil, snow = nil }
local SNOWY = { XMAS = true, SNOW = true, BLIZZARD = true, SNOWLIGHT = true }

--- Coupure de courant et neige au sol : appliquées seulement quand elles changent (et ré-imposées toutes les 5 s)
local function applyExtras(force)
    local blackout = extras.blackout == true
    if force or appliedExtras.blackout ~= blackout then
        appliedExtras.blackout = blackout
        SetArtificialLightsState(blackout)
        SetArtificialLightsStateAffectsVehicles(false) -- les phares restent allumés
    end
    local snow = extras.snow == true or (weather and SNOWY[weather]) or false
    if force or appliedExtras.snow ~= snow then
        appliedExtras.snow = snow
        ForceSnowPass(snow)
        SetForceVehicleTrails(snow)
        SetForcePedFootstepsTracks(snow)
        if snow then RequestNamedPtfxAsset('core_snow') else RemoveNamedPtfxAsset('core_snow') end
    end
end

--- Minute (avec fraction) du jeu actuelle
local function minutesNow()
    if not clock then return nil end
    if clock.ms <= 0 then return clock.base end
    return (clock.base + (GetGameTimer() - clock.at) / clock.ms) % 1440
end

--- Heure reçue du serveur ; un écart de moins de 3 minutes (latence, arrondis) n'est pas un saut : on garde notre
--- avance et on se recale en douceur
local function setClock(value)
    if type(value) ~= 'table' then return end
    local base, ms = tonumber(value.minutes) or 720, tonumber(value.ms) or 0
    local now = minutesNow()
    if clock and now and clock.ms == ms and ms > 0 then
        local diff = (base - now + 720) % 1440 - 720
        if math.abs(diff) < 3 then
            -- recalage doux : l'écart est rattrapé sur la minute du jeu suivante
            clock = { base = now + diff * 0.5, at = GetGameTimer(), ms = ms }
            return
        end
    end
    clock = { base = base, at = GetGameTimer(), ms = ms }
end

--- Fixe la météo tout de suite (comme vSync) : plus de cycle du jeu
local function fixWeather(w)
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetWeatherTypePersist(w)
    SetWeatherTypeNow(w)
    SetWeatherTypeNowPersist(w)
    SetRainLevel(-1.0) -- la pluie suit la météo
end

local function applyWeather(instant)
    if type(weather) ~= 'string' or weather == '' then return end
    local w = weather
    if applied == w and not instant then return end
    if instant or not applied then
        fixWeather(w)
        transitionUntil = 0
    else
        local seconds = (W.TransitionSeconds or 30) + 0.0
        SetWeatherTypeOvertimePersist(w, seconds)
        transitionUntil = GetGameTimer() + math.floor(seconds * 1000) + 500
        SetTimeout(math.floor(seconds * 1000) + 500, function() if weather == w then fixWeather(w) end end)
    end
    applied = w
end

--- Météo publiée par le serveur : temps, coupure de courant, neige au sol
local function readWeather(value)
    weather = type(value) == 'table' and value.weather or nil
    extras.blackout = type(value) == 'table' and value.blackout == true
    extras.snow = type(value) == 'table' and value.snow == true
end

RPIWeather = { minutesNow = minutesNow, setClock = setClock, u32 = u32, readWeather = readWeather, -- pour les tests
    applyExtras = applyExtras }

-- Menu Interaction > Configuration > Météo
RegisterNUICallback('weatherGet', function(_, cb)
    RPI.request('getWeather', {}, function(res)
        if res then res.types = W.Types or {} end
        cb(res or { ok = false })
    end)
end)
RegisterNUICallback('weatherSet', function(data, cb)
    RPI.request('setWeather', type(data) == 'table' and data or {}, function(res) cb(res or { ok = false }) end)
end)

AddStateBagChangeHandler('rpWeather', 'global', function(_, _, value)
    readWeather(value)
    applyWeather(false)
    applyExtras(false)
end)
AddStateBagChangeHandler('rpClock', 'global', function(_, _, value) setClock(value) end)

CreateThread(function()
    setClock(GlobalState.rpClock)
    readWeather(GlobalState.rpWeather)
    applyWeather(true)
    applyExtras(true)
    local nextCheck = 0
    while true do
        local m = minutesNow()
        if m then
            PauseClock(true)
            local whole = math.floor(m)
            NetworkOverrideClockTime(whole // 60, whole % 60, math.floor((m - whole) * 60))
        end
        local now = GetGameTimer()
        if weather and now >= nextCheck and now >= transitionUntil then
            nextCheck = now + 5000
            -- changée par le jeu ou un autre script (empreintes comparées sous la même forme) : la nôtre revient
            local want = u32(GetHashKey(weather))
            if u32(GetPrevWeatherTypeHashName()) ~= want or u32(GetNextWeatherTypeHashName()) ~= want then
                fixWeather(weather)
            end
            applyExtras(true) -- un autre script (ou le jeu) a pu les changer
        end
        Wait(1000)
    end
end)
