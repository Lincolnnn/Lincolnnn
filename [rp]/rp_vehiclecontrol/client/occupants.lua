--[[
    Vehicle Control - ce que ressentent les occupants lors d'un gros choc (client, CHAQUE joueur à bord)
    ---------------------------------------------------------------------------------------------------
    Gros choc (violence d'au moins Occupants.Min : perte de vitesse ou secousse ; pas un piéton ni un plot) :
      - BLESSURE (Injury) : points de vie perdus selon la violence, bien moins avec la ceinture ; ce script ne tue
        jamais (jamais sous MinHealth) ;
      - VUE TROUBLÉE (Effects) : flash blanc sur un très gros choc, vue floue et caméra qui tangue quelques secondes
        (plus longtemps sans ceinture), qui s'estompent peu à peu ;
      - SONNÉ (Stun) : sur un choc très violent, plus de volant ni de pédales pendant 1,5 à 3,5 s (moins avec la
        ceinture) : le véhicule continue sur sa lancée ;
      - VUE À LA PREMIÈRE PERSONNE (FirstPerson) : la tête part avec le choc.
    Éjecté à travers le pare-brise (seatbelt.lua) : seulement les blessures du jeu.
    Performance : rien en dehors d'un choc ; une boucle à chaque image seulement pendant les effets.
]]

local Config = VCConfig.Occupants or {}
local Bodywork = VCConfig.Bodywork or {}

local lastAt = -100000
local effectUntil, stunUntil = 0, 0
local running = false

--- Violence d'un choc pour les occupants (MPH)
function VC.occupantSeverity(drop, jolt)
    return math.max(drop or 0.0, (jolt or 0.0) * (Bodywork.JoltFactor or 1.0))
end

--- Points de vie perdus (0 si choc trop faible)
function VC.injuryAmount(sev, belted)
    local I = Config.Injury or {}
    if I.Enabled == false or sev < (Config.Min or 28.0) then return 0 end
    local amount = (sev - (Config.Min or 28.0)) * (I.Factor or 1.3)
    if belted then amount = amount * (I.Belted or 0.35) end
    return math.floor(math.min(amount, I.Max or 70))
end

--- Durée de la vue troublée (ms) et du temps sonné (ms)
function VC.dazeTimes(sev, belted)
    local E, S = Config.Effects or {}, Config.Stun or {}
    local daze = 0
    if E.Enabled ~= false and sev >= (Config.Min or 28.0) then
        daze = math.min((sev - (Config.Min or 28.0)) * (E.Duration or 160), E.MaxDuration or 9000)
        if belted then daze = daze * (E.Belted or 0.6) end
    end
    local stun = 0
    if S.Enabled ~= false and sev >= (S.Min or 50.0) then
        local t = S.Time or { 1500, 3500 }
        local k = math.min(1.0, (sev - (S.Min or 50.0)) / 30.0)
        stun = (t[1] + (t[2] - t[1]) * k) * (belted and (S.Belted or 0.5) or 1.0)
    end
    return math.floor(daze), math.floor(stun)
end

local function injure(ped, amount)
    if amount <= 0 or IsEntityDead(ped) then return end
    local floor = (Config.Injury or {}).MinHealth or 115
    local health = GetEntityHealth(ped)
    if health <= floor then return end
    SetEntityHealth(ped, math.max(floor, health - amount))
end

--- Effets à chaque image tant qu'ils durent : vue qui s'éclaircit, volant et pédales coupés si sonné
local function runEffects(total)
    if running then return end
    running = true
    local E = Config.Effects or {}
    CreateThread(function()
        if E.Blur then SetExtraTimecycleModifier(E.Blur) end
        if E.Shake then ShakeGameplayCam(E.Shake, E.ShakeAmp or 0.8) end
        while true do
            local now = GetGameTimer()
            if now >= effectUntil and now >= stunUntil then break end
            local left = math.max(0, effectUntil - now)
            local k = math.min(1.0, left / math.max(1, total))
            if E.Blur then SetExtraTimecycleModifierStrength(k) end
            if E.Shake then SetGameplayCamShakeAmplitude((E.ShakeAmp or 0.8) * k) end
            if now < stunUntil then
                for _, control in ipairs({ 59, 60, 63, 64, 71, 72, 76 }) do DisableControlAction(0, control, true) end
            end
            Wait(0)
        end
        if E.Blur then ClearExtraTimecycleModifier() end
        if E.Shake then StopGameplayCamShaking(false) end
        running = false
    end)
end

--- Vue à la première personne : la tête part dans le sens du choc
local function headKick(sev)
    local F = Config.FirstPerson or {}
    if F.Enabled == false or GetFollowVehicleCamViewMode() ~= 4 then return end
    local k = math.min(1.0, sev / 60.0) * (F.Kick or 9.0)
    SetGameplayCamRelativePitch(GetGameplayCamRelativePitch() - k, 1.0)
    SetGameplayCamRelativeHeading(GetGameplayCamRelativeHeading() + (math.random() * 2.0 - 1.0) * k)
end

VC.on('impact', function(vehicle, _, drop, _, hit, jolt)
    if Config.Enabled == false or (Config.SkipClasses or {})[GetVehicleClass(vehicle)] then return end
    if hit and hit.severity == 'light' then return end
    local sev = VC.occupantSeverity(drop, jolt)
    local now = GetGameTimer()
    if sev < (Config.Min or 28.0) or now - lastAt < (Config.Cooldown or 1500) then return end
    lastAt = now
    local belted = VC.isBuckled and VC.isBuckled() or false
    CreateThread(function()
        Wait(150) -- éjecté à travers le pare-brise ? (seatbelt.lua) : seulement les blessures du jeu
        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) ~= vehicle or IsEntityDead(ped) then return end
        injure(ped, VC.injuryAmount(sev, belted))
        local E = Config.Effects or {}
        if E.Enabled ~= false and E.Flash and sev >= E.Flash then AnimpostfxPlay('ExplosionJosh3', 0, false) end
        headKick(sev)
        local daze, stun = VC.dazeTimes(sev, belted)
        if daze <= 0 and stun <= 0 then return end
        local t = GetGameTimer()
        effectUntil = math.max(effectUntil, t + daze)
        stunUntil = math.max(stunUntil, t + stun)
        runEffects(math.max(daze, 1))
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not running then return end
    ClearExtraTimecycleModifier()
    StopGameplayCamShaking(false)
end)
