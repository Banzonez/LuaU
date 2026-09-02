# Combat System

A server-authoritative click-combat system for Roblox, created by BanZonez (GitHub), credits requered.

The current version focuses on an M1 combo: animation-driven hits, server-side
damage, target validation, cooldowns, and stun handling for both players and
NPC dummies.

## Requirements

- An \`Events/CombatEvent\` RemoteEvent is created automatically by the server.
- Put each combat style in \`ReplicatedStorage/AnimationsIds\`.
- Each M1 animation must be named \`Click1\`, \`Click2\`, \`Click3\`, and so on.
- Every attack animation needs an Animation Event marker named \`Hit\`.

The \`Hit\` marker must be created in Roblox Studio's Animation Editor. A
keyframe merely named \`Hit\` is not the same thing.