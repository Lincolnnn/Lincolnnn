--[[
    RP vMenu Keys (serveur)
    -----------------------
    vMenu lit sa touche d'ouverture (vmenu_menu_toggle_key), celle du noclip (vmenu_noclip_toggle_key) et le nom de
    ses raccourcis (vmenu_keymapping_id) dans des convars répliquées, au moment où le joueur se connecte. Une mise à
    jour automatique qui remet un ancien permissions.cfg (touches en numéros de contrôle : 244, 289) les fausse, et
    vMenu s'ouvre sur V. Ce script les impose depuis config.lua, quel que soit le fichier de vMenu :
      - au démarrage de ce script, puis une image plus tard (lignes de server.cfg exécutées après lui) ;
      - quand vMenu (re)démarre ;
      - à chaque connexion d'un joueur (avant que son vMenu ne démarre).
    Une valeur remise par un autre fichier est signalée une fois dans la console.
    Performance : aucune boucle (événements seulement).
]]

local C = VMKConfig
local warned = {}

local function wanted()
    return {
        { 'vmenu_menu_toggle_key', C.MenuKey },
        { 'vmenu_noclip_toggle_key', C.NoClipKey },
        { 'vmenu_keymapping_id', C.MappingId },
    }
end

--- Impose les convars ; `report` : signale une valeur remise par un autre fichier (une fois par convar)
local function apply(report)
    for _, item in ipairs(wanted()) do
        local name, value = item[1], item[2]
        if type(value) == 'string' and value ~= '' then
            local current = GetConvar(name, '')
            if current ~= value then
                SetConvarReplicated(name, value)
                if report and not warned[name] then
                    warned[name] = true
                    print(('^3[rp_vmenukeys] %s avait été remis à "%s" (un autre fichier .cfg ?) : "%s" imposé.^7')
                        :format(name, current, value))
                end
            end
        end
    end
end

-- Démarrage : valeurs trouvées (permissions.cfg de vMenu) puis imposées
do
    local before = {}
    for _, item in ipairs(wanted()) do before[#before + 1] = ('%s="%s"'):format(item[1], GetConvar(item[1], '')) end
    apply(false)
    print(('[rp_vmenukeys] vMenu : ouverture %s, noclip %s, raccourcis vMenu:%s:* (avant : %s)')
        :format(C.MenuKey, C.NoClipKey, C.MappingId, table.concat(before, ', ')))
end
CreateThread(function()
    Wait(0)
    apply(true)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource:lower() == (C.VMenuResource or 'vMenu'):lower() then apply(true) end
end)

AddEventHandler('playerConnecting', function()
    apply(true)
end)
