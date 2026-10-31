--[[
    RP Interact - météo et heure du serveur (Menu Interaction > Configuration > Météo)
    ---------------------------------------------------------------------------------
    Réglées dans le menu, les mêmes pour tout le monde, gardées après un redémarrage (data/weather.json) :
      - MÉTÉO : le temps actuel (Config.Weather.Types) et son DÉFILEMENT :
          fixe (ne change plus) ; beau temps (passe d'un temps clair à un autre : FairCycle) ;
          pluvieux (pluie, orage, brumeux, brouillard : RainyCycle), un nouveau temps toutes les CycleMinutes minutes ;
      - HEURE : à la minute près, et son DÉFILEMENT : fixe (l'heure ne bouge plus), de base (rapide : 2 s par minute
        du jeu, comme GTA), réaliste (Config.Weather.RealisticMs par minute du jeu, 40 000 ms par défaut), personnalisé
        (secondes réelles par minute du jeu, choisies dans le menu) ;
      - COUPURE DE COURANT (blackout : éclairage de la ville éteint, phares des véhicules gardés) et NEIGE AU SOL (avec
        n'importe quel temps ; automatique avec Noël et les temps de neige) ;
      - ACCÈS PUBLIC : un administrateur peut ouvrir le réglage à tout le monde (fermé par défaut).
    UNE SEULE AUTORITÉ : vMenu a sa propre synchro de la météo et de l'heure (convars vmenu_enable_weather_sync /
    vmenu_enable_time_sync) : les deux scripts se contredisaient (temps et heure qui « sautent »). Avec
    Config.Weather.TakeOverVMenu, ce script coupe la synchro de vMenu (convars répliqués : les menus Météo / Heure de
    vMenu disparaissent aussi) ; vaut pour les joueurs qui se connectent ensuite.
    Publiées dans GlobalState (rpWeather, rpClock) : le serveur tient l'heure (minute exacte, avec ses fractions) et la
    republie toutes les SyncSeconds secondes ; chaque client avance à partir de la dernière valeur reçue avec sa propre
    horloge (aucune dépendance à l'heure de la machine du serveur ou du joueur) : même heure pour tout le monde.
    Qui peut régler : Config.Permissions (section « weather ») ou la permission ACE Config.Weather.Ace.
    Performance : une minuterie seulement pour le défilement de la météo (rien sinon).
]]

local Config = InteractConfig
local W = Config.Weather or {}
if W.Enabled == false then return end

local RES = GetCurrentResourceName()
local FILE = 'data/weather.json'
local SPEED = { fixed = 0, base = W.BaseMs or 2000, realistic = W.RealisticMs or 40000, custom = true }
local CUSTOM_MIN, CUSTOM_MAX = 100, 600000 -- personnalisé : de 0,1 s à 10 min réelles par minute du jeu
local CYCLES = { fair = W.FairCycle or { 'EXTRASUNNY', 'CLEAR', 'CLOUDS' }, rainy = W.RainyCycle or { 'RAIN', 'THUNDER', 'SMOG', 'FOGGY' } }

local TYPES = {}
for _, t in ipairs(W.Types or {}) do TYPES[t.id] = t end

local state = { weather = W.Default or 'CLEAR', weatherMode = 'fixed', timeMode = 'base', minutes = 12 * 60, at = GetGameTimer(),
    customMs = W.CustomMs or 10000, blackout = false, snow = false, public = false }

--- ms réelles par minute du jeu (0 : heure fixe)
local function msPerMinute()
    if state.timeMode == 'custom' then return state.customMs end
    local ms = SPEED[state.timeMode]
    return type(ms) == 'number' and ms or 0
end

--- vMenu : sa synchro météo / heure est coupée (une seule autorité) ; ses menus Météo / Heure disparaissent
local function takeOverVMenu()
    if W.TakeOverVMenu == false then return end
    SetConvarReplicated('vmenu_enable_weather_sync', 'false')
    SetConvarReplicated('vmenu_enable_dynamic_weather', 'false')
    SetConvarReplicated('vmenu_enable_time_sync', 'false')
    print('^5[RP Interact]^0 Météo / heure : synchro de vMenu coupée (Weather.TakeOverVMenu). Les joueurs déjà connectés '
        .. 'avant le démarrage de rp_interact doivent se reconnecter une fois.')
end
local cycleTimer = 0 -- identifiant de la minuterie de défilement en cours (une seule active)

--- Minute du jeu actuelle, avec ses fractions (0 à 1440), d'après l'ancre (horloge du serveur, en ms)
local function exactMinutes()
    local ms = msPerMinute()
    if ms <= 0 then return state.minutes end
    return (state.minutes + (GetGameTimer() - state.at) / ms) % 1440
end
local function currentMinutes() return math.floor(exactMinutes()) end

--- Météo publiée seulement quand elle change ; heure : la minute exacte du moment (les clients avancent de là)
local function publishWeather()
    GlobalState.rpWeather = { weather = state.weather, mode = state.weatherMode, blackout = state.blackout, snow = state.snow }
end
local function publishClock()
    GlobalState.rpClock = { minutes = exactMinutes(), ms = msPerMinute(), mode = state.timeMode }
end
local function publish() publishWeather() publishClock() end

local function save()
    local copy = { weather = state.weather, weatherMode = state.weatherMode, timeMode = state.timeMode, minutes = currentMinutes(),
        customMs = state.customMs, blackout = state.blackout, snow = state.snow, public = state.public }
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
        publishWeather()
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
        local ms = tonumber(saved.customMs)
        if ms and ms >= CUSTOM_MIN and ms <= CUSTOM_MAX then state.customMs = math.floor(ms) end
        state.blackout, state.snow, state.public = saved.blackout == true, saved.snow == true, saved.public == true
    end
    state.at = GetGameTimer()
    takeOverVMenu()
    publish()
    scheduleCycle()
end

-- L'heure republiée régulièrement (rattrape les petits écarts des clients) ; gardée de temps en temps
CreateThread(function()
    local n = 0
    while true do
        Wait(math.floor((W.SyncSeconds or 15) * 1000))
        if msPerMinute() > 0 then publishClock() end
        n = n + 1
        if n % 20 == 0 then save() end
    end
end)

--- Administrateur de la météo : permission ACE ou Permissions (section weather)
local function admin(src)
    if W.Ace and IsPlayerAceAllowed(src, W.Ace) then return true end
    return RPIServer.hasPermission(src, 'weather') == true
end
--- Peut régler : administrateur, ou tout le monde quand l'accès public est ouvert
local function allowed(src) return admin(src) or state.public end

local function view(src)
    local m = currentMinutes()
    return { ok = true, allowed = allowed(src), admin = admin(src), weather = state.weather, weatherMode = state.weatherMode,
        timeMode = state.timeMode, hour = m // 60, minute = m % 60, customSeconds = state.customMs / 1000,
        blackout = state.blackout, snow = state.snow, public = state.public }
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
    local customMs = state.customMs
    if p.customSeconds ~= nil then
        local sec = tonumber(p.customSeconds)
        if not sec or sec * 1000 < CUSTOM_MIN or sec * 1000 > CUSTOM_MAX then
            return { ok = false, error = 'Vitesse personnalisée : de 0,1 à 600 secondes par minute du jeu.' }
        end
        customMs = math.floor(sec * 1000 + 0.5)
    end
    local blackout = p.blackout == nil and state.blackout or p.blackout == true
    local snow = p.snow == nil and state.snow or p.snow == true
    local public = state.public
    if p.public ~= nil and (p.public == true) ~= state.public then
        if not admin(src) then return { ok = false, error = 'Réservé aux administrateurs : accès public.' } end
        public = p.public == true
    end
    local weatherChanged = weather ~= state.weather or weatherMode ~= state.weatherMode
    local extrasChanged = blackout ~= state.blackout or snow ~= state.snow
    state.weather, state.weatherMode, state.timeMode = weather, weatherMode, timeMode
    state.customMs, state.blackout, state.snow, state.public = customMs, blackout, snow, public
    state.minutes, state.at = math.floor(hour) * 60 + math.floor(minute), GetGameTimer()
    publishClock()
    if weatherChanged or extrasChanged then publishWeather() end
    save()
    if weatherChanged then scheduleCycle() end -- le défilement repart de maintenant
    print(('^5[RP Interact]^0 Météo réglée par %s : %s (%s), %02d:%02d (%s), coupure %s, neige %s, accès public %s')
        :format(GetPlayerName(src) or src, weather, weatherMode, hour, minute, timeMode, tostring(blackout), tostring(snow),
        tostring(public)))
    return view(src)
end)

-- Arrêt de la ressource : l'heure en cours est gardée
AddEventHandler('onResourceStop', function(resource) if resource == RES then save() end end)
