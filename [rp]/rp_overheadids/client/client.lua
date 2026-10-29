--[[
    RP Overhead IDs (client)
    ------------------------
    Touche maintenue (OverheadConfig.Key, raccourci FiveM « +numeros ») : au-dessus de la tête des joueurs proches, leur
    NOM RP (/nomrp) en gros et, en dessous, leur numéro sur le serveur (ID) ; relâchée : ils disparaissent.
    Performance : RIEN tant que la touche n'est pas maintenue (raccourci FiveM, aucune boucle) ; pendant l'appui, liste
    des joueurs proches revue toutes les 250 ms et textes dessinés à chaque image.
]]

local C = OverheadConfig
local held = false
local HEAD = 31086 -- os de la tête

--- Nom RP (/nomrp : état du joueur, partagé par rp_chat et le MDC) et numéro serveur
local function label(player)
    local id = GetPlayerServerId(player)
    local name = Player(id).state[C.NameState or 'rpName']
    name = type(name) == 'string' and name:gsub('~[%w_]-~', ''):gsub('~', ''):gsub('^%s+', ''):gsub('%s+$', '') or '' -- codes couleur retirés
    return name, tostring(id)
end

--- Joueurs à afficher : proches, visibles (LineOfSight), avec leur texte
local function nearby()
    local me = PlayerPedId()
    local myPos = GetEntityCoords(me)
    local list = {}
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        local isMe = ped == me
        if ped ~= 0 and DoesEntityExist(ped) and (not isMe or C.ShowSelf ~= false) and IsEntityVisible(ped) then
            local d = #(GetEntityCoords(ped) - myPos)
            if d <= (C.Distance or 25.0)
                and (isMe or C.LineOfSight == false or HasEntityClearLosToEntity(me, ped, 17)) then
                local name, id = label(player)
                list[#list + 1] = { ped = ped, player = player, name = name, id = id, distance = d }
            end
        end
    end
    return list
end

local function drawText(text, x, y, scale, color, font)
    SetTextScale(scale, scale)
    SetTextFont(font or 4)
    SetTextProportional(true)
    SetTextColour(color[1], color[2], color[3], 235)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function draw(entry)
    local p = GetPedBoneCoords(entry.ped, HEAD, 0.0, 0.0, 0.0)
    local z = p.z + (C.Height or 0.38)
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(p.x, p.y, z)
    if not onScreen then return end
    local scale = math.max(0.34, 0.66 - entry.distance * 0.012)
    local talking = MumbleIsPlayerTalking(entry.player) or NetworkIsPlayerTalking(entry.player)
    if entry.name ~= '' then
        -- nom RP en gros, numéro en dessous, plus petit
        drawText(entry.name, sx, sy, scale, talking and C.TalkingColor or C.NameColor, 4)
        drawText(entry.id, sx, sy + scale * 0.06, scale * 0.66, C.IdColor, 4)
    else
        drawText(entry.id, sx, sy, scale * 0.8, talking and C.TalkingColor or C.IdColor, 4)
    end
end

local function showLoop()
    CreateThread(function()
        local list, nextScan = {}, 0
        while held do
            local now = GetGameTimer()
            if now >= nextScan then
                nextScan = now + 250
                list = nearby()
            end
            for _, entry in ipairs(list) do
                if DoesEntityExist(entry.ped) then draw(entry) end
            end
            Wait(0)
        end
    end)
end

RegisterCommand('+' .. C.Command, function()
    if held then return end
    held = true
    showLoop()
end, false)

RegisterCommand('-' .. C.Command, function()
    held = false
end, false)

RegisterKeyMapping('+' .. C.Command, 'Afficher les noms RP et numéros des joueurs (maintenir)', 'keyboard', C.Key or 'HOME')
