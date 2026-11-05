--[[
    Vehicle Control - roues qui se détachent hors des chocs (client, calculé par le CONDUCTEUR)
    -----------------------------------------------------------------------------------------
    - VIRAGE BEAUCOUP TROP VIOLENT (Wheels.Turn) : à au moins Turn.MinSpeed MPH, une accélération latérale d'au moins
      Turn.Accel m/s² (virage serré à trop haute vitesse) ou une glissade latérale d'au moins Turn.Slide m/s : la
      roue avant du côté extérieur peut se détacher (Turn.Chance toutes les 100 ms, selon l'excès).
    - TROTTOIR PERCUTÉ TRÈS FORT (Wheels.Curb) : à au moins Curb.MinSpeed MPH, une secousse brutale vers le haut
      (Curb.Jolt m/s d'un coup) avec un coup sur le côté ou vers l'arrière (Curb.Kick m/s), roues au sol juste avant
      (pas un atterrissage) : la roue qui a tapé (la suspension la plus écrasée) éclate (Curb.Burst) ou se détache
      (Curb.Detach), selon la violence.
    Une roue perdue revient à la réparation. Pas de motos, vélos, bateaux, aéronefs, trains (SkipClasses).
    Performance : une lecture de la vitesse par image à bord (déjà faite par la boucle), le reste toutes les 100 ms.
]]

-- Riven Impact Dynamics installé : c'est lui qui gère les roues (config.lua : Riven)
if VC.riven then return end

local Config = VCConfig.Wheels or {}
local Turn, Curb = Config.Turn or {}, Config.Curb or {}
local MPH = 2.236936

local last = { vel = nil, grounded = 0, cooldown = 0 }

local function skip(vehicle)
    return Config.Enabled == false or VC.seat ~= -1 or (Config.SkipClasses or {})[GetVehicleClass(vehicle)]
end

local function wheelByIndex(index)
    for _, w in ipairs(VC.WHEELS or {}) do if w.index == index then return w end end
    return nil
end

--- Roue qui vient de taper : suspension la plus écrasée (roues avant d'abord sans cette information)
local function struckWheel(vehicle)
    local best, bestValue = nil, -1.0
    for _, w in ipairs(VC.WHEELS or {}) do
        local ok, value = pcall(GetVehicleWheelSuspensionCompression, vehicle, w.index)
        value = ok and tonumber(value) or (w.front and 0.5 or 0.0)
        if value > bestValue and not (VC.lostWheels[vehicle] or {})[w.index] then best, bestValue = w, value end
    end
    return best
end

-- Trottoir : chaque image (secousse brutale entre deux images)
VC.on('frame', function(_, vehicle)
    if skip(vehicle) or Curb.Enabled == false then last.vel = nil return end
    local now = GetGameTimer()
    local v = GetEntityVelocity(vehicle)
    local prev = last.vel
    last.vel = v
    local grounded = now - last.grounded <= 300 -- au sol juste AVANT cette image (pas un atterrissage)
    if IsVehicleOnAllWheels(vehicle) then last.grounded = now end
    if not prev or now < last.cooldown then return end
    local speed = math.sqrt(prev.x * prev.x + prev.y * prev.y) * MPH
    if speed < (Curb.MinSpeed or 35.0) or not grounded then return end
    local up = v.z - prev.z
    local kick = math.sqrt((v.x - prev.x) ^ 2 + (v.y - prev.y) ^ 2)
    if up < (Curb.Jolt or 3.0) or kick < (Curb.Kick or 2.0) then return end
    last.cooldown = now + 1500
    local w = struckWheel(vehicle)
    if not w then return end
    local violence = math.min(2.0, up / (Curb.Jolt or 3.0)) * math.min(1.5, speed / (Curb.MinSpeed or 35.0))
    local r = math.random()
    if r < (Curb.Detach or 0.15) * violence then
        VC.breakWheel(vehicle, w)
    elseif r < (Curb.Burst or 0.45) * violence and not IsVehicleTyreBurst(vehicle, w.tyre, false) then
        SetVehicleTyreBurst(vehicle, w.tyre, false, 1000.0)
    end
end)

-- Virage beaucoup trop violent : toutes les 100 ms
VC.on('tick', function(_, vehicle)
    if skip(vehicle) or Turn.Enabled == false or not IsVehicleOnAllWheels(vehicle) then return end
    local speedMs = GetEntitySpeed(vehicle)
    if speedMs * MPH < (Turn.MinSpeed or 60.0) or GetGameTimer() < last.cooldown then return end
    local f = GetEntityForwardVector(vehicle)
    local vel = GetEntityVelocity(vehicle)
    local slide = vel.x * f.y - vel.y * f.x -- glissade vers la droite du véhicule (m/s)
    local yaw = GetEntityRotationVelocity(vehicle).z -- rad/s
    local accel = math.abs(yaw) * speedMs -- accélération latérale (m/s²)
    local excess = math.max(accel / (Turn.Accel or 16.0), math.abs(slide) / (Turn.Slide or 12.0))
    if excess < 1.0 or math.random() >= (Turn.Chance or 0.03) * math.min(2.0, excess) then return end
    -- roue avant extérieure : du côté où le véhicule est poussé (glissade, ou opposé au sens du virage)
    local outerRight
    if math.abs(slide) >= 2.0 then outerRight = slide > 0 else outerRight = yaw > 0 end -- yaw > 0 : tourne à gauche
    local w = wheelByIndex(outerRight and 1 or 0)
    if w and VC.breakWheel(vehicle, w) then last.cooldown = GetGameTimer() + 5000 end
end)

VC.on('leave', function() last.vel = nil end)
