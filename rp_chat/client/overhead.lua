--[[
    RP Chat - /me au-dessus des têtes (option du joueur, onglet "Paramètres" du MDC)
    -------------------------------------------------------------------------------
    Visible uniquement par le joueur qui a choisi cette option : ses /me et ceux des
    autres (reçus dans le rayon de 100 m) s'affichent au-dessus de la tête du joueur
    concerné au lieu du chat. Même vert pâle que dans le chat, sans fond, en plus grand.
    La taille suit la distance entre la caméra et le joueur : elle grandit quand on
    s'approche et diminue quand on recule (bornée pour rester lisible), et tient
    compte du zoom de la caméra (visée, jumelles…).

    Performance : la boucle d'affichage (Wait(0), nécessaire pour dessiner du texte en 3D)
    ne tourne QUE pendant qu'un /me est affiché, puis s'arrête d'elle-même.
]]

local Config = ChatConfig
local COLOR = { 168, 230, 161 }   -- vert pâle : même couleur que /me dans le chat (#a8e6a1)
local HEAD_BONE = 31086           -- SKEL_Head
local LINE_CHARS = 36             -- retour à la ligne automatique
local LINE_SPACING = 0.065        -- hauteur d'une ligne (fraction de l'écran) pour une taille de texte de 1.0
local REFERENCE_DISTANCE = 4.0    -- distance (m) à laquelle le texte a la taille ChatConfig.OverheadScale
local REFERENCE_FOV = 50.0        -- champ de vision de la caméra "normale"

local entries = {}                -- { sender, lines, expires }
local running = false

--- Découpe un texte en lignes d'environ LINE_CHARS caractères (sans couper les mots)
local function wrap(text)
    local lines, line = {}, ''
    for word in text:gmatch('%S+') do
        if line ~= '' and utf8.len(line) + 1 + utf8.len(word) > LINE_CHARS then
            lines[#lines + 1] = line
            line = word
        else
            line = line == '' and word or (line .. ' ' .. word)
        end
    end
    if line ~= '' then lines[#lines + 1] = line end
    return lines
end

local function pedOf(sender)
    if sender == GetPlayerServerId(PlayerId()) then return PlayerPedId() end
    local player = GetPlayerFromServerId(sender)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    return ped ~= 0 and ped or nil
end

local function drawLine(text, x, y, scale)
    SetTextScale(0.0, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(COLOR[1], COLOR[2], COLOR[3], 255)
    SetTextOutline()                 -- lisible sans fond
    SetTextDropShadow()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

--- Taille du texte selon la distance caméra -> tête : inversement proportionnelle à la distance
--- (comme un objet réel), corrigée par le zoom de la caméra et bornée pour rester lisible.
local function textScale(distance)
    local factor = (REFERENCE_DISTANCE * 2.0) / (math.max(distance, 0.5) + REFERENCE_DISTANCE)
    factor = factor * (REFERENCE_FOV / math.max(GetFinalRenderedCamFov(), 1.0))
    factor = math.min(math.max(factor, Config.OverheadMinScale), Config.OverheadMaxScale)
    return Config.OverheadScale * factor
end

--- Dessine les /me d'un joueur : le plus récent juste au-dessus de la tête, les anciens au-dessus
local function drawFor(ped, list, camCoords)
    local head = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.0, 0.0)
    local distance = #(head - camCoords)
    if distance > Config.MeDistance then return end
    local onScreen, x, y = GetScreenCoordFromWorldCoord(head.x, head.y, head.z + 0.35)
    if not onScreen then return end

    local scale = textScale(distance)
    local step = LINE_SPACING * scale
    for i = #list, 1, -1 do
        local lines = list[i].lines
        for j = #lines, 1, -1 do
            y = y - step
            drawLine(lines[j], x, y, scale)
        end
        y = y - step * 0.35 -- petit espace entre deux /me
    end
end

local function loop()
    running = true
    CreateThread(function()
        while true do
            local now = GetGameTimer()
            for i = #entries, 1, -1 do
                if entries[i].expires <= now then table.remove(entries, i) end
            end
            if #entries == 0 then break end

            -- Regroupement par joueur (ordre d'arrivée conservé)
            local bySender, order = {}, {}
            for _, entry in ipairs(entries) do
                if not bySender[entry.sender] then
                    bySender[entry.sender] = {}
                    order[#order + 1] = entry.sender
                end
                local list = bySender[entry.sender]
                list[#list + 1] = entry
            end

            local camCoords = GetFinalRenderedCamCoord()
            for _, sender in ipairs(order) do
                local ped = pedOf(sender)
                if ped then drawFor(ped, bySender[sender], camCoords) end
            end
            Wait(0)
        end
        running = false
    end)
end

RPChatOverhead = {}

--- Affiche un /me au-dessus de la tête du joueur `sender` (id serveur)
function RPChatOverhead.add(sender, text)
    if type(sender) ~= 'number' or type(text) ~= 'string' or text == '' then return end
    -- Durée : de base + un peu plus pour les longs messages (15 s max)
    local duration = math.min(Config.OverheadDuration + utf8.len(text) * 40, 15000)
    entries[#entries + 1] = { sender = sender, lines = wrap(text), expires = GetGameTimer() + duration }

    -- Nombre de /me affichés par joueur limité : les plus anciens disparaissent
    local count = 0
    for i = #entries, 1, -1 do
        if entries[i].sender == sender then
            count = count + 1
            if count > Config.OverheadMaxLines then table.remove(entries, i) end
        end
    end

    if not running then loop() end
end
