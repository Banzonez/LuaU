# Combat System

A server-authoritative battlegrounds combat system by BanZonez (GitHub). Credit is required.

## Controls

| Action | Input |
| --- | --- |
| Basic combo | M1; hold to repeat |
| Block | Hold F |
| Dash | Q + WASD; direction follows the camera |
| Uppercut | M1 then jump while grounded, only on the second combo hit |
| Downcut | M1 while falling, only on the second combo hit |
| Abilities | 1, 2, 3, 4 |
| Ultimate | G, after filling the meter |

Abilities and ultimate activate on release. Hold duration changes only their local crack/rebound animation. M1, block, and dash retain immediate/held input. Keyboard uses 1–4 and G; gamepad uses LB/RB/X/Y and D-pad Up, with RT for M1, LT for block and B for dash. The on-screen buttons support touch input. The Training panel spawns blocking, attacking, or mixed dummies in both Studio and published servers. Each player may have three dummies, with twelve total per server; dummies expire after three minutes and are removed when their owner leaves.

## Setup

Sync `default.project.json` with Rojo. The server and client loaders initialize their modules once.

The authored HUD is `StarterGui.CombatInterface`, owned by the Studio place. Edit its objects in Explorer. The current Rojo mapping syncs the scripts. All slots, labels, bars, crack segments, chips, and scales exist in the model. `CombatInterface` creates no GUI objects: it binds input, displays server data, and animates the authored objects. Keep its names/hierarchy when editing.

Each ability/ultimate button groups the glass lines under `Cracks` and the detached pieces under `Fragments`. Keep these groups collapsed when editing the button's text, size, color or outline.

The compact skill slots have no shortcut labels. Each press reveals 161 thin, distributed glass segments in a shuffled order, clipped to the button. Touch controls follow the native jump button; portrait layout raises the hotbar above them. Cooldowns are shown on the ability slots.

Studio's `ServerStorage.MuayThaiAnimationStudy` contains the free [Muay thai animations by InnardCrysis](https://create.roblox.com/store/asset/8297368716) for evaluation. Its sequences use R6 poses, while the current training rig uses R15, so these candidates are not assigned to gameplay slots. One candidate was played on a temporary R6 rig. The study exists only in Studio and requires saving/exporting separately; it is not included in the Rojo build or authored by this project.

Keep animations under `ReplicatedStorage.AnimationsIds.<StyleName>`. Missing style animations fall back to `MuayThai`. Attacks use `hitDelay` by default, independently of animation length. Set `useHitMarker = true` only for an asset authored with a `Hit` marker: its marker opens the window, and a missing marker cancels the hit before recovery ends. Marker mode fails closed; it never fires an earlier timing fallback. `waitForLanding` waits for nearby ground while descending, within the action lifetime.

Downcut and Ability1–4 have editable Studio preview clips inside the Animation slots in ReplicatedStorage.AnimationsIds.MuayThai, with R6 overrides in its R6 folder. Publish each clip under the experience owner and set its slot's AnimationId for use outside Studio. Source models: [Axe kick](https://create.roblox.com/store/asset/4813509054), [R15 Punch](https://create.roblox.com/store/asset/2043684873), [Jumping knee strike](https://create.roblox.com/store/asset/451471588), [Fire spin kick](https://create.roblox.com/store/asset/2224821138), [Ground Slam](https://create.roblox.com/store/asset/93354440157608). The alternate-rig clips were adapted for this project.

DashFront, DashBack, DashLeft, DashRight and Ult still have no dedicated clips. When a published animation is missing, downcut, front dash and ability attacks use their configured M1 fallback.

For training dummies, provide a healthy humanoid rig named `CombatNpc` in ServerStorage. Dummies keep their spawn facing. Attack dummies swing in place, pausing 0.7 seconds after recovery. The R15 block and basic attack clips are adapted from the MuayThai R6 animations; publish the R15 slots for live use. NPC hits grant half the usual ultimate charge. BasicStyle requires 200 charge. It never clones scripts into active dummies.

## Styles

Add a ModuleScript beside `BasicStyle` exposing `new(player, settings)`. Return `StyleName`, partial `Settings`, and `Abilities`. NPCs pass `nil` as the player.

`CombatSetup` resolves partial settings into complete, independent tables. Use `Types.StyleSettingsOverrides` and `Types.AttackSettingsOverrides` for overrides. Each named attack controls its box, local offset, hit timing, recovery, damage, stun, target cap, knockback, guard break, and animation slot.

The BasicStyle kit contains Straight Strike, Knee Rush, Spinning Kick, and Aerial Slam. Each ability stores its settings and may provide an `execute(character)` hook. The common service handles admission, timing, movement, and damage; the optional hook is available for style-specific server behavior.

Ultimate charge comes from damage actually dealt. Its duration, requirement, damage multiplier, and cooldowns are configurable. Frontal blocks stop ordinary damage; rear hits bypass block, and guard-breaking attacks stun the defender.

For a player, obtain the object through `CombatSetup:GetPlayerObj(player)` and change styles through `object:SetStyle(player, styleName, overrides)`. Style changes are rejected during actions and active ultimates.

## Ownership and lifecycle

The client sends action requests and displays server-confirmed cooldowns. Damage, targets, blocking, cooldowns, variants, ultimate charge, NPC limits, and dash speed are decided on the server.

Guard starts at 15. Frontal blocks absorb the hit until guard reaches zero. The breaking hit deals full damage and stuns. After 2.5 seconds without a blocked hit or lost health, guard recovers at 2 points per second. Basic punches cost 1 guard and deal 5 health damage; combo finishers cost 2 and deal 8. The four abilities cost 2, 4, 3 and 6 guard respectively. During ultimate, abilities 2–4 break a full guard immediately. Rear hits bypass guard.

Attacks follow the current root transform during their active window, with at most six intermediate poses between sampled frames. Each humanoid is counted once per attack. Static obstructions block hits; other combatants do not act as walls. State revisions prevent deferred callbacks from cancelling replacement actions.

Character state changes cancel older attacks and movement constraints. Death, removal, and respawn clear character caches and connections. Jumping is disabled during combat states on both server and client, then restored.

`CombatStateHandler.resetCharacter(character)` resets a living combatant, restores movement, invalidates prior actions, and starts a new registration. This is the integration point for an external round system. `acceptTeleport(character)` must be called by trusted server code immediately after an intentional teleport. `authorizeMovement(character, distance)` grants a short displacement allowance for externally applied motion. Combat moves call it themselves. Movement checks reject impossible displacement and reconcile to the previous position; they are not a complete flight or noclip detector. Tune tolerances with actual multiplayer latency before release.

Training dummies attack only their owner, validate ground and free spawn space, retain the three-per-owner/twelve-total caps, and expire after three minutes. Damage and charge remain server-owned; UI snapshots identify the character and action revision.

## Verification

`tests/Combat.spec.luau` runs against the actual server modules in a Studio server play session. It is excluded from the published Rojo tree. Execute it as a temporary server Script, replacing the final `return tests` with:

```luau
local result = tests.run()
print(game:GetService("HttpService"):JSONEncode(result))
```

Remove that temporary Script afterward. The suite creates and removes its own fixtures.

Formatting uses StyLua 2.6.0. Strict analysis uses Luau LSP 1.70.1 with Roblox definitions and the generated sourcemap.

Official references: [spatial queries](https://create.roblox.com/docs/reference/engine/classes/WorldRoot), [animation markers](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack), [mover constraints](https://create.roblox.com/docs/physics/mover-constraints), [client/server validation](https://create.roblox.com/docs/scripting/security/client-server-boundary).

## Targeted style audit

The available history already mixes original and earlier assistant edits; author attribution is uncertain. Public names and module boundaries are preserved. No fake imperfections or narrative banners were added.

| File | Checklist / status | Occurrences and action |
| --- | --- | --- |
| CombatInterface | #28 CONFIRMED | One shared template-style constructor removed, along with the other two layout constructors. All visual objects moved into the authored model. Connected edge-reaching cracks replace isolated strokes. |
| CombatService | #8 CONFIRMED | One misleading helper, `cooldowns`, renamed `sendState`. Removed one obsolete Space request branch. Existing Service suffix retained (#10: existing convention). |
| CombatStateHandler / Types | #23 CONFIRMED | Removed three unused state fields/variants: LastSpacePressed, UltCooldowns and AirFrame. Retained the state/settings contracts used across modules. |
| BasicStyle | #8/#24 SUSPECTED style preference | Replaced one damage formula with the explicit 11/13/15/17 values. Kept the small attack-default factory and existing public setting names. |
| CombatUtil | #18 reviewed; #8 CONFIRMED | Kept two pcalls around animation loading/preloading because asset operations can fail. Removed three occurrences of an unused markerReady field. Kept real cache/constraint cleanup and the disabled Studio-only hitbox visualizer. |
| CombatSetup | #19/#23 reviewed | Kept remote-independent configuration validation and recursive combat-object typing: they protect partial settings and the SetStyle API. Legacy stun/cooldown inputs are resolved once rather than deleted. |
| Loaders / NPC handler | #10/#17 reviewed | Preserved existing module names and direct server references; no server WaitForChild calls or new service layers. |

The matching correctness issues were configuration precedence, the unused input branch, and the earlier timing/cancellation gaps. Naming preferences were not treated as security defects. Existing suffixes and public PascalCase fields are deliberately retained for compatibility.

## Release checks

The integration suite includes reset/re-registration, stale cancellation, malformed vectors, non-frontal dash spoofing, missing markers, occlusion, blocking, target caps and the four abilities. Run it against current sources; historical passes are not proof after edits.

Focused Studio tests with two simulated clients verified HUD initialization, attack cooldowns, malformed requests, frontal blocking, guard break, rear hits, stun cancellation, respawn during an ability, late joining, and disconnect cleanup. Disconnect timing was measured separately: a hit before the player actually leaves is valid; a deliberately long pending hit was cancelled when its owner left. These tests do not replace physical-device or production-server testing.

Before publishing, verify mutual kills, real-world network variation, external round integration, and physical touch/gamepad controls. A focused single-client latency test delivered the configured 11 damage with about 438 ms measured ping; this is one network sample, not broad resilience evidence. Dedicated animations are still needed for the explicit empty/fallback slots.

The warning for asset 203785492 matches a documented Rojo plugin sound-preloading issue, fixed in its unreleased changelog ([Rojo PR #1351](https://github.com/rojo-rbx/rojo/pull/1351)). No reference to that ID was found in the project's scripts or inspected live content properties. Do not replace combat animations to address this tooling warning.

The Rojo Lighting block remains unmanaged: the prior removal is not reversed with deprecated Lighting properties. No match manager, persistence, monetization or publishing is introduced.
