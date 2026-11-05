--[[
    RP Interact - Combat : arme à feu en main
    -----------------------------------------
    - Pas de corps à corps avec une arme à feu (NoFirearmMelee) : plus de coup de crosse ni de coup donné dans le
      vide (attaque légère, lourde, alternative). Recharger, viser et tirer restent possibles.
    - Pas de roulade (NoCombatRoll) : saut bloqué pendant la visée (c'est saut + visée qui fait la roulade).
    Mains nues ou arme blanche (couteau, matraque…) : rien ne change.

    Performance : une vérification toutes les 250 ms (arme en main) ; à chaque image SEULEMENT tant qu'une arme à
    feu est en main, à pied.
]]

local Config = InteractConfig

local MELEE = { 140, 141, 142, 263, 264 } -- attaques au corps à corps (légère, lourde, alternative, 1, 2)
local JUMP = 22
local AIM = 25
local FIREARM = 4 -- IsPedArmed : armes à feu

local running = false

local function firearmInHand(ped)
    return IsPedArmed(ped, FIREARM) and not IsPedInAnyVehicle(ped, false)
end

local function frameLoop()
    if running then return end
    running = true
    CreateThread(function()
        local player = PlayerId()
        while true do
            local ped = PlayerPedId()
            if not firearmInHand(ped) then break end
            if Config.NoFirearmMelee ~= false then
                for _, control in ipairs(MELEE) do DisableControlAction(0, control, true) end
            end
            if Config.NoCombatRoll ~= false and (IsPlayerFreeAiming(player) or IsControlPressed(0, AIM)
                or IsDisabledControlPressed(0, AIM)) then
                DisableControlAction(0, JUMP, true)
            end
            Wait(0)
        end
        running = false
    end)
end

CreateThread(function()
    if Config.NoFirearmMelee == false and Config.NoCombatRoll == false then return end
    while true do
        if not running and firearmInHand(PlayerPedId()) then frameLoop() end
        Wait(250)
    end
end)
