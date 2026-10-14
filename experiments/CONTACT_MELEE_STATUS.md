# Contact melee status — 2026-10-12

Controller melee is not working yet. Do not load the archived prototype into the game.

## Updated DLL validation: PASS (2026-10-13)

The DLL maintainer supplied a new installed bridge, SHA-256 `1EA0AA8A0BC0546A6288F683B8CAEEF2F583F0AB6605A9C01094E39810312442`. The profile log confirms it loaded at 11:12:01. No DLL/source/build changes were made by this agent during validation.

Added a Lua-only `FKContactBridgeCheck` event in main.lua, activated by the user's Reset Scripts. It reads the equipped axe matrix via plugin.getProperty, passes it in a temporary FAbilityShape through plugin.executeFunction(AbilityFunctionLibrary, AddVelocity, shape, zeroVelocity), and compares the returned matrix. No ability is spawned, no owning ability or target is supplied, and no Impact/attack input is called.

Result: PASS, 1 damage entry, 2 target attributes, 2 attribute contributions, 30 matching scalar/reference fields. Three invocations completed successfully because delayed log output initially hid completion; do not repeat this check just because log output is buffered. No further DLL changes are indicated by this test. It establishes reflected payload round-trip correctness, not native curve evaluation, ownership/destruction of a persistent copy, damage application, or controller melee.

The V2 prepare guard now permits the validated contributions without changing their values. It also checks an off-target mesh trace misses and includes the generated limb asset in its single completion log. Bridge error responses now stop the operation explicitly. This Lua revision needs Reset Scripts before FKContactPrepareV2. No Impact has been submitted. Do not reintroduce the native HitInfo-to-UObject copy. Do not edit/build/replace DLLs: report any additional concrete bridge issue to the user for their DLL maintainer.

## Current revision (2026-10-13, not yet activated)

User directed use of `scripts/libs/core/plugin.lua` for containers. The diagnostic now uses the bridge for trace, GenerateHitInfo, and Impact. Removed native HitInfo-to-CausingImpactResult assignment and all writes to the temporary ability's CausingImpactResult. Old event names remain disabled; replacement events are FKContactPrepareV2 / FKContactSubmitV2.

The bridge cannot write FHitResult.Component (WeakObjectProperty). GenerateHitInfo only copies HitBone if that component resolves, but its character/limb lookup separately uses BoneName and TargetActor. V2 requires matching generated target and skeleton, valid target components and HitLimbData, and no redirected bone. It then sets reflected HitBone and TargetObject from the actual mesh trace. No guessed head socket or world impact-point override is used.

The shape payload contains only the authored damage matrix/weapon part, equipped stack ID, and owning ability. Matrix entries must exist and every damage spec must have an explicitly empty AttributeContributions array; curve-bearing contributions fail before construction. This is a diagnostic limitation, not permission to drop damage scaling. V2 still requires a successful dry run and permits at most one Impact per script load. Runtime behavior is unverified; Reset Scripts is required to activate.

Offline crash investigation mapped the fault to destruction of CausingImpactResult.HitInfo.AbilityShape.WeaponDamageMatrix, including nested damage specs/contributions. Exact corruption origin remains unconfirmed. The local bridge DLL hash matches uevrlib_plugin_claude/uevr_utils.dll (C2D5603ED7E4C6725CF4957F28560FC7060C4F1CB1AA37CC6FD4ACCBB587ECED). Its struct-array allocation is uninitialized before reflected fields are written; the UEVR native Lua struct setter uses memcpy. Neither shared project was modified.

## Crash: latest test disabled

After the next Reset Scripts, FKContactPrepare caused the game to exit at 13:29:47 on 2026-10-12. There was no PREPARED completion log. FKContactSubmit was never dispatched. All live calls stopped once the process exit was confirmed. Both diagnostic event handlers now refuse to run, including after restart.

Crash report: `%LOCALAPPDATA%/SLASHER/Saved/Crashes/UECC-Windows-DF4027B24A85FE5F3FFBE09D0EFC5A7E_0000/UEMinidump.dmp`. Offline `.ecxr; k 22` shows access violation at EXE RVA 0x122904a with RCX=0x4448000044850000, through native frames including RVAs 0x5be380f, 0x5be3a6f, 0x5be8c64, 0x5be8e99, 0x5be8a81 and 0x5bedd2f. The stack is not sufficient to establish which preparation operation corrupted state. Native struct copying/lifetime and initialization remain unverified. Do not repeat this test or assume the native handoff is safe.

## Current direct-contact test

`scripts/main.lua` now has explicit `FKContactPrepare` and `FKContactSubmit` events. Preparation does no damage. Submission requires a successful preparation for the same target and is limited to one hit per script load. Neither event calls attack input, BeginAbility, or animation manipulation.

Native code inspection established that UAbility::Impact consumes supplied HitInfo and executes ImpactWeapon stages without checking that the ability has started. The weapon stage merges the supplied shape's WeaponDamageMatrix into the target effect; the final stage passes the hit into native effect application. This route remains unproven in gameplay.

After the user's latest Reset Scripts, preparation successfully loaded the equipped axe's shape/matrix, constructed an unstarted context, and reached GenerateHitInfo. It stopped at the bone-equality assertion. No Impact was submitted. An independent mesh trace returned leg_L2. Native GenerateHitInfo copies HitResult.BoneName into HitInfo.HitBone only when the hit component reference resolves. Table conversion losing that weak reference is the current hypothesis, not yet a confirmed cause.

The on-disk correction keeps the trace, generated HitInfo, and Impact argument as native structs. It stores the native hit in CausingImpactResult and uses the bridge only to populate the authored shape's containers. This also preserves unreflected native hit fields. Aiming socket overrides are disabled on the private module. The corrected script passes Lua syntax checking; another UEVR Reset Scripts is needed before validation. Production melee remains disabled.

The next reset exposed an invalid `UEVR_FName.new('None')` call before the native trace ran. The local UEVR binding has no string constructor exposed on that type. Inspection of its native function argument handling confirms unused out parameters should be empty Lua tables. The trace now uses `{},{},{},hit` for its output arguments, keeping FHitResult native. No hit was submitted in this attempt. This argument correction awaits Reset Scripts.

## Requirement

The VR weapon's swept contact must drive hits and preserve the actual contacted limb. No simulated input, normal attack animation, animation pausing, or speed changes.

## Changes

Removed the gesture-to-input melee implementation and old delayed probes from scripts/main.lua. Gesture melee is currently disabled. The pre-change file is scripts/main.before-contact.lua.bak; it contains the rejected input-based implementation. Current main.lua passes Lua syntax checking and remains hardlinked into the UEVR profile.

## Evidence

- Read all three reference projects. Their useful common pattern is native weapon collision/hit handling; their attack initialization methods cannot simply be copied to Fatekeeper.
- Equipped axe data is available through GetSingleAbilityDataOfTypeInCollection. Its modules include Animation, ImpactWeapon, PlayerFeedback, FX, Cost, TargetSelection, and Effect_Casting.
- The authored ImpactWeapon module uses bUseAimingSocket=true and bUseDefaultAimingSocket=true. Their contribution to the observed head wounds is a hypothesis, not verified.
- A private collision-only asset failed at AbilityComponent.BeginAbility with a caught native access violation.
- Passing equipped AbilityData with only a private ImpactWeapon module failed at the same entry point.
- CanCastAbility returned true for the registered axe asset with animation overridden to null, duration overridden to 0.1 seconds, and collision shapes overridden to empty. BeginAbility with those same arguments still raised SEH 0xC0000005. No synthetic contact test was run.
- These failures do not establish whether the cause is parameter initialization/marshalling, missing native preconditions, or another issue. Earlier assumptions blaming the transient asset were unproven.

## Remaining work

Resolve the native hit/context entry point before further controller integration. Demonstrate one synthetic miss and one synthetic leg contact with no attack animation; confirm the actual hit bone, reaction, damage behavior, and one impact per swing. Only then enable controller-driven sweeps. Do not retry the archived BeginAbility experiments automatically or add a fallback to attack input.

The live script only runs the explicit diagnostic events; automatic melee calls remain disabled.
