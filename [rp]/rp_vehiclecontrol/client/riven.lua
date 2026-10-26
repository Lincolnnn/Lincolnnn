--[[
    Vehicle Control - liaison avec Riven Impact Dynamics (client)
    -------------------------------------------------------------
    riven/bridge.lua est chargé DANS la ressource de Riven (une ligne dans son fxmanifest, voir README) : il lit ici
    ses réglages (config.lua : Riven) et renvoie ici les notifications de Riven, traduites en français, affichées en
    message privé du chat comme les nôtres (VC.chat).
    Performance : aucune boucle.
]]

local R = VCConfig.Riven or {}

exports('rivenSettings', function()
    return {
        Lamps = R.Lamps ~= false,
        HideLamps = type(R.HideLamps) == 'table' and R.HideLamps or { 'belt' },
        Notify = R.Notify ~= false,
        MuteBelt = R.MuteBelt ~= false,
    }
end)

AddEventHandler('rp_vehiclecontrol:rivenNotify', function(text)
    if type(text) == 'string' and text ~= '' then VC.chat(text) end
end)
