--[[
    RP Interact - météo et heure du serveur (Menu Interaction > Configuration > Météo)
    ---------------------------------------------------------------------------------
    Réglées dans le menu, les mêmes pour tout le monde, gardées après un redémarrage (data/weather.json) :
      - MÉTÉO : le temps actuel (Config.Weather.Types) et son DÉFILEMENT :
          fixe (ne change plus) ; beau temps (passe d'un temps clair à un autre : FairCycle) ;
          pluvieux (pluie, orage, brumeux, brouillard : RainyCycle), un nouveau temps toutes les CycleMinutes minutes ;
      - HEURE : à la minute près, et son DÉFILEMENT : fixe (l'heure ne bouge plus), de base (rapide : 2 s par minute
        du jeu, comme GTA), réaliste (Config.Weather.RealisticMs par minute du jeu, 40 000 ms par défaut).
    Publiées dans GlobalState (rpWeather, rpClock) : chaque client calcule l'heure lui-même à partir de l'ancre
    (minute + heure du serveur + vitesse), sans boucle réseau. L'ancre est remise à jour à chaque changement.
    Qui peut régler : Config.Permissions (section « weather ») ou la permission ACE Config.Weather.Ace.
    Performance : une minuterie seulement pour le défilement de la météo (rien sinon).
]]

local Config = InteractConfig
local W = Config.Weather or {}
if W.Enabled == false then return end

local RES = GetCurrentResourceName()
local FILE = 'data/weather.json'
local SPEED = { fixed = 0, base = W.BaseMs or 2000, realistic = W.RealisticMs or 40000 }
local CYCLES = { fair = W.FairCycle or { 'EXTRASUNNY', 'CLEAR', 'CLOUDS' }, rainy = W.RainyCycle or { 'RAIN', 'THUNDER', 'SMOG', 'FOGGY' } }

local TYPES = {}
for _, t in ipairs(W.Types or {}) do TYPES[t.id] = t end

local state = { weather = W.Default or 'CLEAR', weatherMode = 'fixed', timeMode = 'base', minutes = 12 * 60, epoch = os.time() }
local cycleTimer = 0 -- identifiant de la minuterie de défilement en cours (une seule active)

--- Minute du jeu actuelle (0-1439), d'après l'ancre
local function currentMinutes()
    local ms = SPEED[state.timeMode] or 0
    if ms <= 0 then return state.minutes end
    return math.floor(state.minutes + (os.time() - state.epoch) * 1000 / ms) % 1440
end

local function publish()
    GlobalState.rpWeather = { weather = state.weather, mode = state.weatherMode }
    GlobalState.rpClock = { minutes = state.minutes, epoch = state.epoch, ms = SPEED[state.timeMode] or 0, mode = state.timeMode }
end

local function save()
    local copy = { weather = state.weather, weatherMode = state.weatherMode, timeMode = state.timeMode,
        minutes = currentMinutes(), epoch = os.time() }
    SaveResourceFile(RES, FILE, json.encode(copy), -1)
end

local function pickNext()
    local list = CYCLES[state.weatherMode]
    if not list or #list == 0 then return nil end
    if #list == 1 then return list[1] end
    local next
    repeat next = list[math.random(1, #list)] until next ~= state.weather
    return next
end

--- Défilement de la météo : un nouveau temps de la liste toutes les CycleMinutes minutes
local function scheduleCycle()
    cycleTimer = cycleTimer + 1
    local mine = cycleTimer
    if not CYCLES[state.weatherMode] then return end
    SetTimeout(math.floor((W.CycleMinutes or 20) * 60000), function()
        if mine ~= cycleTimer then return end
        state.weather = pickNext() or state.weather
        publish()
        save()
        scheduleCycle()
    end)
end

-- Chargement (data/weather.json), sinon les valeurs par défaut
do
    local ok, saved = pcall(json.decode, LoadResourceFile(RES, FILE) or '')
    if ok and type(saved) == 'table' then
        if TYPES[saved.weather] then state.weather = saved.weather end
        if saved.weatherMode == 'fixed' or CYCLES[saved.weatherMode] then state.weatherMode = saved.weatherMode end
        if SPEED[saved.timeMode] then state.timeMode = saved.timeMode end
        if tonumber(saved.minutes) then state.minutes = math.floor(tonumber(saved.minutes)) % 1440 end
    end
    state.epoch = os.time()
    publish()
    scheduleCycle()
end

local function allowed(src)
    if W.Ace and IsPlayerAceAllowed(src, W.Ace) then return true end
    return RPIServer.hasPermission(src, 'weather')
end

local function view(src)
    local m = currentMinutes()
    return { ok = true, allowed = allowed(src), weather = state.weather, weatherMode = state.weatherMode,
        timeMode = state.timeMode, hour = m // 60, minute = m % 60 }
end

RPIServer.on('getWeather', function(src) return view(src) end)

--- { weather, weatherMode, timeMode, hour, minute } : tout est vérifié ; heure appliquée telle quelle
RPIServer.on('setWeather', function(src, p)
    if not allowed(src) then return { ok = false, error = 'Réservé : vous ne pouvez pas régler la météo.' } end
    local weather = type(p.weather) == 'string' and p.weather or state.weather
    if not TYPES[weather] then return { ok = false, error = 'Météo inconnue.' } end
    local weatherMode = p.weatherMode == 'fixed' and 'fixed' or (CYCLES[p.weatherMode] and p.weatherMode) or state.weatherMode
    local timeMode = SPEED[p.timeMode] and p.timeMode or state.timeMode
    local hour, minute = tonumber(p.hour), tonumber(p.minute)
    if not hour or not minute or hour < 0 or hour > 23 or minute < 0 or minute > 59 then
        return { ok = false, error = 'Heure invalide (00:00 à 23:59).' }
    end
    local weatherChanged = weather ~= state.weather or weatherMode ~= state.weatherMode
    state.weather, state.weatherMode, state.timeMode = weather, weatherMode, timeMode
    state.minutes, state.epoch = math.floor(hour) * 60 + math.floor(minute), os.time()
    publish()
    save()
    if weatherChanged then scheduleCycle() end -- le défilement repart de maintenant
    print(('^5[RP Interact]^0 Météo réglée par %s : %s (%s), %02d:%02d (%s)'):format(GetPlayerName(src) or src,
        weather, weatherMode, hour, minute, timeMode))
    return view(src)
end)

-- Arrêt de la ressource : l'heure en cours est gardée
AddEventHandler('onResourceStop', function(resource) if resource == RES then save() end end)
