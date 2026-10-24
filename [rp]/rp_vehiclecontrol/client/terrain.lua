--[[
    Vehicle Control - comportement selon le sol (client, calculé par le CONDUCTEUR)
    --------------------------------------------------------------------------------
    Toutes les Terrain.Interval ms en roulant, le sol sous le véhicule est lu (code de matière du jeu, rayon vers le
    bas). Sur l'herbe, la terre, le gravier, le sable, la boue (Terrain.Surfaces) :
      - moins de puissance (Power) : le véhicule peine, accélère moins ;
      - au-dessus de MaxSpeed MPH, il est freiné peu à peu (le sol meuble le retient) ;
      - adhérence réduite (Grip) : il glisse davantage (gravier, sable, boue).
    Sol détrempé (pluie) : effet x Rain. Type de véhicule (ClassFactor) : tout-terrain, SUV, militaires presque pas
    gênés ; sportives, supercars davantage. Sur la route : rien ne change.
    Performance : un rayon vers le bas toutes les Interval ms en roulant ; rien à l'arrêt ni à pied.
]]

local Config = VCConfig.Terrain or {}
local MPH = 2.236936

local byMaterial = {} -- [code de matière] = nom de la surface
for name, surface in pairs(Config.Surfaces or {}) do
    for _, hash in ipairs(surface.Materials or {}) do byMaterial[hash] = name end
end

local current = { vehicle = 0, surface = nil, grip = false, at = 0, material = nil }
VC.terrainPower = 1.0

local function skip(vehicle)
    return Config.Enabled == false or VC.seat ~= -1 or (Config.SkipClasses or {})[GetVehicleClass(vehicle)]
end

--- Code de matière du sol sous le véhicule (nil : rien touché)
local function materialUnder(vehicle)
    local p = GetEntityCoords(vehicle)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(p.x, p.y, p.z + 0.5, p.x, p.y, p.z - 3.0, 1, vehicle, 7)
    local _, hit, _, _, material = GetShapeTestResultIncludingMaterial(ray)
    if hit ~= 1 and hit ~= true then return nil end
    return material
end
VC.materialUnder = materialUnder

--- Part de l'effet du sol subie par ce véhicule (type de véhicule, pluie)
local function strength(vehicle)
    local k = (Config.ClassFactor or {})[GetVehicleClass(vehicle)] or 1.0
    if GetRainLevel() >= (Config.RainLevel or 0.25) then k = k * (Config.Rain or 1.35) end
    return k
end

--- Effet d'une surface pour ce véhicule : puissance, vitesse maximale (MPH), adhérence réduite
function VC.terrainEffect(vehicle, name)
    local s = name and (Config.Surfaces or {})[name]
    if not s then return 1.0, nil, false end
    local k = strength(vehicle)
    local power = math.max(0.2, 1.0 - (1.0 - (s.Power or 1.0)) * k)
    local maxSpeed = s.MaxSpeed and k > 0.0 and (s.MaxSpeed / math.max(k, 0.05)) or nil -- plus gêné : plus lent
    return power, maxSpeed, s.Grip == true and k >= 0.5
end

local function setGrip(vehicle, on)
    if current.grip == on then return end
    current.grip = on
    SetVehicleReduceGrip(vehicle, on)
end

local function reset(vehicle)
    VC.terrainPower = 1.0
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and current.grip then SetVehicleReduceGrip(vehicle, false) end
    current = { vehicle = 0, surface = nil, grip = false, at = 0, material = nil }
end

VC.on('tick', function(_, vehicle, dt)
    if skip(vehicle) then
        if current.vehicle ~= 0 then reset(current.vehicle) end
        return
    end
    if current.vehicle ~= vehicle then reset(current.vehicle); current.vehicle = vehicle end
    local speed = GetEntitySpeed(vehicle) * MPH
    local now = GetGameTimer()
    if speed < (Config.MinSpeed or 8.0) or not IsVehicleOnAllWheels(vehicle) then
        -- à l'arrêt ou en l'air : sol inchangé (pas de rayon)
        if speed < 1.0 then VC.terrainPower = 1.0 end
        return
    end
    if now - current.at >= (Config.Interval or 250) then
        current.at = now
        current.material = materialUnder(vehicle)
        current.surface = current.material and byMaterial[current.material] or nil
    end
    local power, maxSpeed, grip = VC.terrainEffect(vehicle, current.surface)
    VC.terrainPower = power
    setGrip(vehicle, grip)
    -- sol meuble : freiné peu à peu au-dessus de la vitesse que le sol permet
    if maxSpeed and speed > maxSpeed then
        local v = GetEntityVelocity(vehicle)
        local f = math.max(0.9, 1.0 - 0.6 * (dt or 0.1) * math.min(1.0, (speed - maxSpeed) / 15.0))
        SetEntityVelocity(vehicle, v.x * f, v.y * f, v.z)
    end
end)

VC.on('leave', function(vehicle, _, info)
    reset(not (info and info.gone) and vehicle or nil)
end)

if Config.Debug then
    RegisterCommand('vcsurface', function()
        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        if vehicle == 0 then return VC.chat('Montez dans un véhicule.') end
        local material = materialUnder(vehicle)
        VC.chat(('Sol sous le véhicule : %s (%s).'):format(tostring(material), material and byMaterial[material] or 'route / non classé'))
    end, false)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and current.vehicle ~= 0 then reset(current.vehicle) end
end)
