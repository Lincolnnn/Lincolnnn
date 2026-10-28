--[[
    RP Interact - météo et heure (client) : appliquées d'après le serveur (GlobalState rpWeather / rpClock)
    ------------------------------------------------------------------------------------------------------
    L'heure du jeu est tenue par ce script (horloge du jeu en pause) : fixe, de base ou réaliste, calculée à partir
    de l'ancre du serveur (minute + heure du serveur) avec l'heure « cloud » du jeu : la même pour tout le monde.
    Météo : changement en douceur (TransitionSeconds) ; ré-appliquée si un autre script la modifie.
    Performance : une mise à jour de l'heure par seconde (une native), rien d'autre.
]]

local W = InteractConfig.Weather or {}
if W.Enabled == false then return end

local clock = GlobalState.rpClock
local weather = GlobalState.rpWeather
local applied = nil -- météo appliquée

--- Minute (avec fraction) du jeu actuelle, d'après l'ancre du serveur
local function minutesNow()
    if type(clock) ~= 'table' then return nil end
    local base = tonumber(clock.minutes) or 720
    local ms = tonumber(clock.ms) or 0
    if ms <= 0 then return base end
    local elapsed = GetCloudTimeAsInt() - (tonumber(clock.epoch) or GetCloudTimeAsInt())
    return (base + math.max(0, elapsed) * 1000 / ms) % 1440
end
RPIWeather = { minutesNow = minutesNow } -- pour les tests

local function applyWeather(instant)
    if type(weather) ~= 'table' or type(weather.weather) ~= 'string' then return end
    local w = weather.weather
    if applied == w and not instant then return end
    if instant or not applied then
        SetWeatherTypeNowPersist(w)
    else
        SetWeatherTypeOvertimePersist(w, (W.TransitionSeconds or 30) + 0.0)
    end
    SetRainLevel(-1.0) -- la pluie suit la météo
    applied = w
end

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
    weather = value
    applyWeather(false)
end)
AddStateBagChangeHandler('rpClock', 'global', function(_, _, value) clock = value end)

CreateThread(function()
    applyWeather(true)
    while true do
        local m = minutesNow()
        if m then
            PauseClock(true)
            local whole = math.floor(m)
            NetworkOverrideClockTime(whole // 60, whole % 60, math.floor((m - whole) * 60))
        end
        -- un autre script (ou le jeu) a changé la météo : la nôtre revient
        if applied and type(weather) == 'table' and GetPrevWeatherTypeHashName() ~= GetHashKey(weather.weather)
            and GetNextWeatherTypeHashName() ~= GetHashKey(weather.weather) then
            applyWeather(true)
        end
        Wait(1000)
    end
end)
