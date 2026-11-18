--[[
    TOUCHES PERSONNALISÉES (/modiftouche du chat écrit, rp_chat) - garde de touche (client)
    ------------------------------------------------------------------------------------------
    Fichier identique dans chaque script qui a des touches (RegisterKeyMapping), chargé AVANT ses autres scripts
    client. Quand un joueur déplace une touche avec /modiftouche, l'ANCIENNE touche ne doit plus rien faire : chaque
    commande de ce script demande donc au chat (export keyAllowed) si elle peut partir. Sans rp_chat démarré, ou sans
    touche déplacée : tout part normalement. Aucune boucle ; une seule vérification quand la commande est lancée.
]]

local registerCommand = RegisterCommand

local function keyAllowed(name)
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if chat == GetCurrentResourceName() then
        return not RPChatKeys or RPChatKeys.allowed(name) ~= false
    end
    if GetResourceState(chat) ~= 'started' then return true end
    local ok, res = pcall(function() return exports[chat]:keyAllowed(name) end)
    return not ok or res ~= false
end

RegisterCommand = function(name, handler, restricted)
    if type(name) == 'string' and type(handler) == 'function' then
        local inner = handler
        handler = function(...)
            if keyAllowed(name) then return inner(...) end
        end
    end
    return registerCommand(name, handler, restricted)
end
