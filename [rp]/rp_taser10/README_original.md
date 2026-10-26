
## Install

1. Put the `axon_taser10` folder in your server resources folder.
Add `ensure axon_taser10` to `server.cfg`.
Make sure `ox_target` starts before `axon_taser10`.

## Default controls

| Input | Action |
| --- | --- |
| `B` | Switch between SAFE and ARMED; move SAFE then ARMED quickly to reactivate connected prongs |
| Left click | Fire one probe while ARMED |
| `R` | Play the warning alert and strobe the flashlight |
| `G` | Selector-down input used for stealth and function test |
| `/reloadtaser` | Refill the 10 cartridges; a fully depleted battery is also replaced |
| `/removeprongs [server ID]` | Remove every embedded prong from the aimed-at or nearest tracked player/NPC; a nearby player server ID is optional |

`Config.Keys` controls the defaults for players who have not changed the binding.


## SAFE mode

The taser starts in SAFE.

Press `B` while ARMED to switch back to SAFE. SAFE turns off the laser and flashlight and stops active player cycles started by your taser.

Holstering an ARMED taser also returns it to SAFE.

After three minutes in SAFE, the script breaks the active electrical connection. Embedded prongs remain.

## ARMED mode

Equip a taser and press `B` while SAFE.

ARMED mode plays the selector click and `arming.mp3`. It enables the green laser dot and the flashlight unless stealth mode is active.

## Laser dot settings

`DotSize` changes the size of the dot. The default is `0.01`. Try `0.00` for smaller or `0.04` for larger.

`StartForwardOffset`, `StartRightOffset`, and `StartUpOffset` move the origin point used for the laser dot projection. I recommend not to touch though

Laser transparency is controlled with:

```lua
Transparency = 0.18
```

`0.0` is fully opaque. `1.0` is fully invisible.

## Firing and connections

Two successful probe hits from the same taser must hit the same target to establish a connection.

The first successful hit immediately attaches its prong prop and draws one cord back to the shooter's TASER. A second hit on the same target adds the second prong and cord and changes the state from PARTIAL to CONNECTED.

A successful connection plays the connection sound, starts the stun cycle for `Config.CycleTime`, and ragdolls the victim for `Config.RagdollTime`.

Every successful hit creates a persistent `prong.ydr` object on the nearest body bone. Prongs follow walking, animations, falls, and ragdolls. They stay embedded after distance breaks, weapon switches, new deployments, and shooter disconnects.

The connection states are `DISCONNECTED`, `PARTIAL`, `CONNECTED`, and `BROKEN`. One hit is `PARTIAL`. Only the newest two hits on the same target become `CONNECTED`. A new deployment removes the previous cords and electrical state while keeping every old embedded prong.

The probe shot range uses `Config.MaxRange`. This is separate from the laser range.

## Warning Alert

Press `R` while ARMED. This plays `warning.mp3`.

`R` strobes the flashlight for `Config.Flashlight.StrobeDuration`.

`R` does not fire a cartridge and does not reactivate connected prongs.

## Reactivating connected prongs

While the TASER is equipped and ARMED, press `B` to move the selector to SAFE and press `B` again within `Config.Prongs.SelectorReactivationWindow` to move it back to ARMED. Reactivation only works when the newest active pair is attached, the victim is valid, and the wire is in range `Config.Prongs.MaxWireDistance`.

The SAFE-to-ARMED selector movement reuses the existing prongs and cords. It does not fire a projectile, use a cartridge, or create duplicate cartridges. A successful reactivation starts the existing stun cycle again and uses `Config.BatteryDrain` battery.

The selector must return to ARMED within the configured window. Both the client and server enforce `Config.Prongs.ReactivationCooldown`.

## Stealth mode

When in SAFE mode, press `G` three times. Keep each release within 1 second of the last press

Press `B` to arm after preparing stealth mode.

Stealth mode dims the CID and disables the flashlight. The green laser stays on

Firing a cart exits stealth mode. Returning to SAFE also exits stealth mode

## Function test

In SAFE mode hold `G` for three seconds and release it. The display runs through the loading screen
Then will show the firmware version. Its just fake information used for realism of the script unless I find later use for it

Press `B` to arm, then press `B` again to return to SAFE. The display shows `selector_switch_passed_the_function_test` until you press either `B` or `G` to return to the normal SAFE cartridge display.

The function test does not fire a probe or consume a cartridge.

## Reloading

Keep the taser equipped

```
/reloadtaser
```

If the taser is ARMED, reload switches it to SAFE first.

Reload restores `Config.Cartridges`, breaks the active electrical connection, and stops active player cycles. The cumulative battery shot count remains in place across cartridge reloads so its 15-, 25-, and 30-shot stages can be reached. Reloading after full depletion replaces the battery and resets its shot count. Embedded prongs remain.

The CID shows the current cartridge count whenever the TASER is equipped and outside function-test mode. Firing a cart updates the image immediately, including the empty state after the tenth shot.

The CID battery indicator is selected from the cumulative number of shots spent. The cartridge images already contain the full battery, so no second image is placed over them from 0 through 14 shots. At 15 shots, `half.png` appears; at 25 shots, `low.png` appears; and at 30 shots, `depleted-battery-animation.gif` appears and firing is blocked. Reload after depletion to return to the full battery state.

## Removing prongs


```
/removeprongs
```

The server confirms the target owns the prong IDs and that the requester is within `Config.RemoveProngs.Distance` before removing anything.

Players with embedded prongs also can use a ox-target option named **Remove Taser Prongs**. The command and ox-target option are the same. Configure access with `Config.RemoveProngs`.

Removal deletes all persistent prong props from that player. If those IDs belong to an active connection, its cords and selector reactivation are stopped first. The victim entity is never deleted.

Set `RequirePermission = true` to restrict removal. Then accepts either the configured ACE or a job name listed in `AllowedJobs`. Job checks read the player's `state.job` value. An ACE example is:

```
add_ace group.admin axon_taser10.removeprongs allow
```

## Nearby sounds

TASER sounds are sent to players near the person using the taser

`Config.SoundVolume` sets the source volume.

`Config.SoundDistance` sets the maximum hearing distance in metres. Volume fades with distance and reaches zero at the edge of the configured range.

## Lighting and laser configuration

All current laser and flashlight visual values are in `config.lua`.

### Laser

| Setting | Default | Purpose |
| --- | ---: | --- |
| `Config.Laser.Enabled` | `true` | Enables the green laser dot |
| `Config.Laser.Range` | `12.192` | Maximum laser distance in metres, 40 feet |
| `Config.Laser.MuzzleBone` | `gun_muzzle` | Weapon bone used as the laser origin |
| `Config.Laser.DotSize` | `0.02` | Size of the green laser dot. Lower is smaller, higher is larger |
| `Config.Laser.StartForwardOffset` | `0.015` | Moves the laser origin forward from the muzzle |
| `Config.Laser.StartRightOffset` | `0.0` | Moves the laser origin right or left |
| `Config.Laser.StartUpOffset` | `0.0` | Moves the laser origin up or down |
| `Config.Laser.Color.r` | `0` | Red channel |
| `Config.Laser.Color.g` | `255` | Green channel |
| `Config.Laser.Color.b` | `80` | Blue channel |
| `Config.Laser.Transparency` | `0.18` | Laser dot transparency. `0.0` opaque, `1.0` invisible |

Laser dot color uses the RGB values, and transparency uses `Config.Laser.Transparency`.

### Prongs and wires

| Setting | Default | Purpose |
| --- | ---: | --- |
| `Config.Prongs.Model` | `prong` | Streamed prong model name |
| `Config.Prongs.Models` | two `prong` entries | Per-prong model names; change the second entry if a separate second model is added later |
| `Config.Prongs.ModelLoadTimeout` | `3000` | Maximum model load time in milliseconds |
| `Config.Prongs.MaxWireDistance` | `8.0` | Hard physical cord limit in metres |
| `Config.Prongs.CordBreakTolerance` | `0.15` | Server validation allowance around the hard client limit |
| `Config.Prongs.ReactivationCooldown` | `2000` | Minimum milliseconds between successful reactivations |
| `Config.Prongs.SelectorReactivationWindow` | `1500` | Time allowed between moving the selector to SAFE and back to ARMED |
| `Config.Prongs.BreakOnWeaponSwitch` | `true` | Break when the shooter switches away from the TASER |
| `Config.Prongs.BreakOnDeath` | `true` | Break when the shooter or victim dies |
| `Config.Prongs.BreakOnLineOfSight` | `false` | Optionally break when world geometry blocks line of sight |
| `Config.Prongs.KeepAfterConnectionBreak` | `true` | Preserve embedded prongs after ordinary cord cleanup |
| `Config.Prongs.KeepAfterWeaponSwitch` | `true` | Preserve embedded prongs when switching weapons |
| `Config.Prongs.KeepAfterNewShot` | `true` | Preserve old prongs when starting a new deployment |
| `Config.Prongs.BoneIds` | body bone list | Bones considered when choosing the nearest impact attachment |
| `Config.Prongs.AttachmentOffsets` | Y `0.1500` | Per-prong position adjustment for the current model |
| `Config.Prongs.AttachmentRotation` | pitch `-90.0`, yaw `20.0` | Rotation adjustment for `prong.ydr` |
| `Config.Wire.Thickness` | `0.0025` | Thin cord ribbon width |
| `Config.Wire.Segments` | `32` | Segments used to draw the hanging and curled cord smoothly |
| `Config.Wire.Sag` | `0.055` | Base downward curve in metres |
| `Config.Wire.Gravity` | `0.035` | Additional distance-based center drop |
| `Config.Wire.Damping` | `0.22` | Endpoint smoothing amount per update |
| `Config.Wire.Stiffness` | `1.0` | Higher values reduce sag |
| `Config.Wire.CurlSize` | `0.018` | Width of each small cord curl in metres |
| `Config.Wire.CurlCount` | `6.0` | Number of curls between the TASER and each prong |
| `Config.Wire.UpdateRate` | `0` | Active cord update delay in milliseconds |
| `Config.Wire.Color` | off-white | Non-particle RGBA cord color |
| `Config.Wire.WeaponForwardOffset` | `0.0` | Muzzle-side forward adjustment |
| `Config.Wire.WeaponRightOffset` | `0.0` | Muzzle-side horizontal adjustment |
| `Config.Wire.WeaponUpOffset` | `0.0` | Muzzle-side vertical adjustment |
| `Config.Wire.ProbeSpacing` | `0.006` | Separation between both cords at the TASER |

`stream/prong.ytyp` is registered by the resource manifest DONT TOUCH IT ARL Keep both `prong.ydr` and `prong.ytyp` inside the `stream` folder.

### Flashlight

| Setting | Default | Purpose |
| --- | ---: | --- |
| `Config.Flashlight.Enabled` | `true` | Enables the flashlight effect |
| `Config.Flashlight.DirectionRight` | `0.0` | Optional horizontal flashlight alignment correction |
| `Config.Flashlight.DirectionUp` | `0.0` | Optional vertical flashlight alignment correction |
| `Config.Flashlight.StartForwardOffset` | `0.015` | Moves the flashlight origin forward |
| `Config.Flashlight.StartRightOffset` | `0.0` | Moves the flashlight origin right or left |
| `Config.Flashlight.StartUpOffset` | `0.0` | Moves the flashlight origin up or down |
| `Config.Flashlight.Color.r` | `255` | Red channel |
| `Config.Flashlight.Color.g` | `255` | Green channel |
| `Config.Flashlight.Color.b` | `235` | Blue channel |
| `Config.Flashlight.Distance` | `20.0` | Spotlight distance |
| `Config.Flashlight.Brightness` | `8.0` | Normal brightness |
| `Config.Flashlight.Hardness` | `1.0` | Spotlight hardness |
| `Config.Flashlight.Radius` | `18.0` | Spotlight radius |
| `Config.Flashlight.Falloff` | `1.0` | Spotlight falloff |
| `Config.Flashlight.LowBatteryThreshold` | `20.0` | Battery level that switches to low brightness |
| `Config.Flashlight.LowBatteryBrightness` | `4.0` | Brightness below the battery threshold |
| `Config.Flashlight.StrobeDuration` | `1500` | Strobe duration in milliseconds |
| `Config.Flashlight.StrobeInterval` | `180` | Full strobe interval in milliseconds |
| `Config.Flashlight.StrobeOnTime` | `90` | On portion of each strobe interval |
| `Config.Flashlight.StrobeBrightness` | `20.0` | Brightness while the strobe is on |

## Other configuration

| Setting | Default | Purpose |
| --- | ---: | --- |
| `Config.Cartridges` | `10` | Cartridges restored by reload |
| `Config.CycleTime` | `5000` | Stun cycle length in milliseconds |
| `Config.RagdollTime` | `8000` | Victim ragdoll length in milliseconds |
| `Config.MaxRange` | `13.7` | Probe shot range in metres |
| `Config.SoundVolume` | `0.6` | Maximum local and nearby sound volume |
| `Config.SoundDistance` | `15.0` | Nearby sound hearing distance in metres |
| `Config.BatteryDrain` | `0.4` | Battery percentage used by supported energized actions |
| `Config.DebugMode` | `false` | Enables prong, connection, distance, cord, and removal logging |
| `Config.RemoveProngs.Command` | `removeprongs` | Remove-prongs command name |
| `Config.RemoveProngs.Distance` | `2.5` | Server-validated command/removal distance |
| `Config.RemoveProngs.OxTargetDistance` | `2.0` | ox_target interaction distance |
| `Config.RemoveProngs.AllowedJobs` | `{}` | Jobs allowed when removal permission is required |
| `Config.RemoveProngs.RequirePermission` | `false` | Require an allowed job or ACE permission |
| `Config.RemoveProngs.PermissionAce` | `axon_taser10.removeprongs` | ACE checked when permission is required |
| `Config.ReloadCommand` | `reloadtaser` | Reload command name |

## Client exports

Idk what you would make with these but here they are ig

```
exports.axon_taser10:toggleSafety()
exports.axon_taser10:pressSelectorUp()
local state = exports.axon_taser10:getTaserState()
```
Dm me if you need me to add more

`getTaserState()` returns `armed`, `stealth`, `cartridges`, `battery`, `deployed`, `connected`, and `connectionState`.
