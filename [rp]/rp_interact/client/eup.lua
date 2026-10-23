--[[
    RP Interact - Menu des tenues /eup (client)
    -------------------------------------------
    Ouvert par la commande /eup (chat écrit, même sans nom RP) ou par Menu Interaction > Équipements >
    "Accéder aux tenues". Tenues de data/outfits.json (lues par le serveur), classées :
      Washington State Patrol (WSP) / King County Sheriff Office (KCSO) (+ autres polices du fichier) ; Civil.
    Seules les tenues du personnage (homme / femme, personnage multijoueur) sont listées.
    Menu au CLAVIER, sans la souris (le joueur peut continuer à bouger), touches lues par client/kbmenu.lua :
      flèches haut / bas (maintenues : défilement), Entrée ou flèche droite : ouvrir / mettre la tenue,
      Retour arrière ou flèche gauche : revenir, Échap : fermer.
    L'affichage et la navigation sont dans le NUI (html/script.js).
    Aucune boucle dans ce fichier.
]]

local Config = InteractConfig
local E = Config.Eup or {}
local MALE, FEMALE = GetHashKey('mp_m_freemode_01'), GetHashKey('mp_f_freemode_01')

local open = false
local loading = false

local function gender()
    local model = GetEntityModel(PlayerPedId())
    if model == MALE then return 'male' end
    if model == FEMALE then return 'female' end
    return nil
end

local function close()
    if not open then return end
    open = false
    RPI.kbClose('eup')
    SendNUIMessage({ action = 'eup', data = { open = false } })
end

function RPI.openEup()
    if open or loading then return end
    local sex = gender()
    if not sex then
        return RPI.notify('Tenues disponibles uniquement avec un personnage multijoueur (homme / femme).', 'error')
    end
    loading = true
    RPI.request('eupList', {}, function(res)
        loading = false
        if not res or not res.ok then return RPI.notify(res and res.error or 'Tenues indisponibles.', 'error') end
        local list = {}
        for _, o in ipairs(res.outfits or {}) do
            if o.gender == nil or o.gender == sex then
                list[#list + 1] = { index = o.index, name = o.name, cate = o.cate, group = o.group }
            end
        end
        open = true
        RPI.kbOpen('eup', close) -- ferme le Menu Interaction s'il est ouvert
        SendNUIMessage({ action = 'eup', data = {
            open = true, outfits = list, gender = sex, policeLocked = res.policeLocked == true,
        } })
    end)
end

--- Met la tenue (pièces envoyées par le serveur : { n°, modèle, texture }, déjà comptées à partir de 0)
local function wear(outfit)
    local ped = PlayerPedId()
    for _, c in ipairs(outfit.components or {}) do
        SetPedComponentVariation(ped, c[1], c[2], c[3], 0)
    end
    for _, p in ipairs(outfit.props or {}) do
        if p[2] < 0 then ClearPedProp(ped, p[1]) else SetPedPropIndex(ped, p[1], p[2], p[3], true) end
    end
end

RegisterNUICallback('eupWear', function(data, cb)
    cb({ ok = true })
    if not open then return end
    local index = type(data) == 'table' and tonumber(data.index) or nil
    if not index then return end
    RPI.request('eupWear', { index = index }, function(res)
        if not res or not res.ok or type(res.outfit) ~= 'table' then
            return RPI.notify(res and res.error or 'Tenue indisponible.', 'error')
        end
        if res.outfit.gender and res.outfit.gender ~= gender() then
            return RPI.notify('Cette tenue n\'est pas faite pour ce personnage.', 'error')
        end
        wear(res.outfit)
        RPI.notify(('Tenue : %s'):format(res.outfit.name), 'success')
    end)
end)

RegisterNUICallback('eupClose', function(_, cb)
    cb({ ok = true })
    close()
end)

RegisterCommand(E.Command or 'eup', function()
    if open then close() else RPI.openEup() end
end, false)
