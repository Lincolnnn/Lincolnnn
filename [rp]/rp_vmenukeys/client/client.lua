--[[
    RP vMenu Keys (client) : /vmenutouches affiche les réglages de vMenu reçus du serveur. Aucune boucle.
]]

local C = VMKConfig

if C.CheckCommand and C.CheckCommand ~= '' then
    RegisterCommand(C.CheckCommand, function()
        local id = GetConvar('vmenu_keymapping_id', '')
        local text = ('vMenu : touche %s, noclip %s, raccourci « vMenu:%s:MenuToggle ». Si V ouvre encore vMenu : Échap > Paramètres > Raccourcis clavier > FiveM > « vMenu Toggle Button ».')
            :format(GetConvar('vmenu_menu_toggle_key', '?'), GetConvar('vmenu_noclip_toggle_key', '?'), id ~= '' and id or 'Default')
        print(text)
        TriggerEvent('chat:addMessage', { args = { 'vMenu', text } })
    end, false)
end
