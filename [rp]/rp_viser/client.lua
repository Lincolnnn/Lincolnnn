--[[
    RP Viser - client
    -----------------
    Mode « maintenir » : rien n'est modifié (visée du jeu).
    Mode « appuyer » : arme à feu en main, à pied, le clic droit du jeu est neutralisé et lu ici : un appui verrouille la
    visée (SetPlayerForcedAim), un nouvel appui la relâche. Relâchée aussi : arme rangée / changée, véhicule, à terre,
    mort, menotté, interface avec la souris ouverte, menu pause.
    Performance : mode « maintenir » ou sans arme à feu : une vérification toutes les 250 ms ; arme à feu en main en mode
    « appuyer » : lecture du clic droit à chaque image (comme le jeu).
]]

local C = ViserConfig
local KVP = 'rp_viser_mode'
local AIM = C.AimControl or 25
local UNARMED = GetHashKey('WEAPON_UNARMED')
local MODES = { hold = 'Maintenir pour viser', toggle = 'Appuyer pour viser' }

local mode = GetResourceKvpString(KVP)
if not MODES[mode] then mode = MODES[C.Default] and C.Default or 'hold' end
local locked = false

-- ---- Messages privés dans le chat (rp_chat), sinon chat d'origine ----
local function notify(text)
    local chat = GlobalState.rpChatResource
    if type(chat) == 'string' and GetResourceState(chat) == 'started'
        and pcall(function() exports[chat]:addPrivate({ title = C.ChatTitle or 'Visée', text = text }) end) then return end
    TriggerEvent('chat:addMessage', { args = { C.ChatTitle or 'Visée', text } })
end

local function setLocked(on)
    on = on == true
    if on == locked then return end
    locked = on
    SetPlayerForcedAim(PlayerId(), on)
end

--- Arme à feu en main, à pied, rien qui empêche de viser
local function canAim(ped)
    local weapon = GetSelectedPedWeapon(ped)
    if weapon == 0 or weapon == UNARMED or not IsPedArmed(ped, 4) then return false end -- 4 : armes à feu
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedCuffed(ped) then return false end
    if IsPedSwimming(ped) or IsPedClimbing(ped) or IsPedFalling(ped) then return false end
    return true
end

local function blocked()
    return IsPauseMenuActive() or IsNuiFocused()
end

CreateThread(function()
    while true do
        if mode ~= 'toggle' then
            setLocked(false)
            Wait(250)
        else
            local ped = PlayerPedId()
            if not canAim(ped) then
                setLocked(false)
                Wait(250)
            else
                -- clic droit du jeu neutralisé : c'est ce script qui décide de la visée
                DisableControlAction(0, AIM, true)
                if blocked() then
                    setLocked(false)
                elseif IsDisabledControlJustPressed(0, AIM) then
                    setLocked(not locked)
                end
                Wait(0)
            end
        end
    end
end)
RPViser = { mode = function() return mode end, locked = function() return locked end } -- pour les tests

local function setMode(new)
    mode = new
    SetResourceKvp(KVP, mode)
    setLocked(false)
    notify(('Mode de visée : %s.%s'):format(MODES[mode], mode == 'toggle'
        and ' Clic droit une fois pour viser, encore une fois pour arrêter.' or ' Maintenez le clic droit pour viser.'))
end

RegisterCommand(C.Command or 'viser', function(_, args)
    local arg = tostring(args[1] or ''):lower()
    if arg == 'maintenir' or arg == 'hold' then return setMode('hold') end
    if arg == 'appuyer' or arg == 'toggle' then return setMode('toggle') end
    if arg ~= '' then return notify('Usage : /viser (changer), /viser maintenir, /viser appuyer.') end
    setMode(mode == 'toggle' and 'hold' or 'toggle')
end, false)

-- Proposée dans le chat (rp_chat) en tapant « / », sans nom RP
local function sendCommands()
    TriggerEvent('rp_chat:client:addCommands', GetCurrentResourceName(), {
        { name = C.Command or 'viser', usage = '/' .. (C.Command or 'viser') .. ' [maintenir | appuyer]',
            desc = 'Visée : maintenir le clic droit ou appuyer une fois', noName = true },
    })
end
CreateThread(function() Wait(2000) sendCommands() end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == GlobalState.rpChatResource then SetTimeout(1000, sendCommands) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and locked then SetPlayerForcedAim(PlayerId(), false) end
end)
