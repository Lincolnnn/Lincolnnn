Config = {}

Config.DebugMode = false

Config.ConflictingTaserResources = {
    'fivem_taser_rebuilt'
}

Config.Weapon = `WEAPON_STUNGUN`
Config.Weapons = {
    `WEAPON_STUNGUN`,
    `WEAPON_STUNGUN_MP`
}

Config.Cartridges = 10
Config.CycleTime = 5000
Config.RagdollTime = 8000
Config.MaxRange = 13.7
Config.RequireAiming = true -- Set to false to allow firing without aiming.

Config.BatteryDisplay = {
    StartImage = 'imgs/full_battery.png',
    HalfImage = 'imgs/half.png',
    LowImage = 'imgs/low.png',
    DepletedImage = 'imgs/depleted-battery-animation.gif',
    HalfThresholdShotsSpent = 15,
    LowThresholdShotsSpent = 25,
    DepletedThresholdShotsSpent = 30
}

-- Green laser settings.
-- Range is in metres. 12.192 metres = 40 feet.
Config.Laser = {
    Enabled = true,
    Range = 12.192,
    MuzzleBone = 'gun_muzzle',

    -- Size of the green endpoint dot. Try 0.02 for smaller or 0.06 for larger.
    DotSize = 0.01,

    StartForwardOffset = 0.015,
    StartRightOffset = 0.0,
    StartUpOffset = 0.0,

    -- Green Color, Change to  Color = {r = 255, g = 0, b = 0} for red
    Color = {
        r = 0,
        g = 255,
        b = 80
    },

    Transparency = 0.10 -- Transparency uses 0.0 for fully opaque and 1.0 for fully invisible.
}

-- Flashlight / spotlight settings.
Config.Flashlight = {
    Enabled = true,

    -- Independent fine alignment for the flashlight cone.
    DirectionRight = 0.0,
    DirectionUp = 0.0,
    StartForwardOffset = 0.015,
    StartRightOffset = 0.0,
    StartUpOffset = 0.0,

    Color = {
        r = 255,
        g = 255,
        b = 235
    },

    Distance = 7.0,
    Brightness = 3.0,
    Hardness = 0.3,
    Radius = 10.0,
    Falloff = 1.0,

    LowBatteryThreshold = 20.0,
    LowBatteryBrightness = 4.0,

    StrobeDuration = 1500,
    StrobeInterval = 180,
    StrobeOnTime = 90,
    StrobeBrightness = 20.0
}

-- Nearby TASER sound settings
-- Volume is clamped between 0.0 and 1.0.
-- Distance is measured in metres and fades linearly to zero at the edge.
Config.SoundVolume = 0.6
Config.SoundDistance = 15.0

Config.Prongs = {
    Model = 'prong',
    Models = { 'prong', 'prong' },
    ModelLoadTimeout = 3000,
    MaxWireDistance = 8.0,
    CordBreakTolerance = 0.15,
    ReactivationCooldown = 2000,
    SelectorReactivationWindow = 1500,
    BreakOnWeaponSwitch = true,
    BreakOnDeath = true,
    BreakOnLineOfSight = false,
    KeepAfterConnectionBreak = true,
    KeepAfterWeaponSwitch = true,
    KeepAfterNewShot = true,
-- Do not change
    BoneIds = {
        11816, 23553, 24816, 24817, 24818,
        45509, 61163, 40269, 28252,
        58271, 63931, 51826, 36864
    },
-- Do not change
    AttachmentOffsets = {
        { x = 0.0, y = 0.1500, z = 0.0 },
        { x = 0.012, y = 0.1500, z = 0.0 }
    },
-- Do not change
    AttachmentRotation = { x = -90.0, y = 0.0, z = 20.0 }
}

Config.Wire = {
    Thickness = 0.0015,
    Segments = 32,
    Sag = 0.055,
    Gravity = 0.035,
    Damping = 0.22,
    Stiffness = 1.0,
    CurlSize = 0.018,
    CurlCount = 6.0,
    UpdateRate = 0,
    Color = { r = 40, g = 40, b = 40 },
    WeaponForwardOffset = 0.0,
    WeaponRightOffset = 0.0,
    WeaponUpOffset = 0.0,
    ProbeSpacing = 0.006
}

Config.BatteryDrain = 0.4
Config.ReloadCommand = 'reloadtaser'

Config.DischargeWebhook = {
    Url = '', -- Paste the Discord webhook URL here to log a fully discharged TASER.
    Username = 'Axon Ecosystem'
}

Config.RemoveProngs = {
    Command = 'removeprongs',
    Distance = 2.5,
    TargetDistance = 2.0, -- œil de rp_interact (Alt) : distance maximale pour « Retirer les sondes du Taser »
    AllowedJobs = {},
    RequirePermission = false,
    PermissionAce = 'axon_taser10.removeprongs'
}

-- Œil de rp_interact (Alt) : options ajoutées (rp_interact/config.lua : TargetProviders contient 'rp_taser10')
Config.Target = {
    RemoveLabel = 'Retirer les sondes du Taser', -- sur un joueur ou un PNJ qui a des sondes plantées (+ nombre)
    Reload = true,                               -- sur soi-même, Taser en main : « Recharger le Taser »
    ReloadLabel = 'Recharger le Taser',
    -- Taser en main, en visant n'importe où : « Poser le Taser au sol ». Les sondes déjà tirées restent dans le
    -- suspect et reliées (le fil part du Taser posé, distance comptée depuis lui) ; « Reprendre le Taser » (œil,
    -- son propriétaire seulement) : il marche comme avant (réactivation des sondes). Pas de mise en veille au sol.
    Drop = true,
}

Config.Keys = {
    safety = 'B',
    selectorUp = 'R',
    selectorDown = 'G'
}
