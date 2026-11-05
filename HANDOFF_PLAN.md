# Physical Item Grab: hands, handoff, touch and catching — plan and status

Status (2026-11-04), all done and tested in FK unless noted:
- Step 1: attachments grip update callbacks with priorities and per-hand fall-through (mesh/socket from the first callback that
  gives one).
- Step 2a: grabbable attaches its own held copies (its own grip callback at priority -10); opt-in `dropWhenHandTaken`.
- Step 2b: two-hand grabbable via `hands` (FK uses it); hand argument passed to the game's callbacks.
- Step 3: hand-to-hand handoff (`handoffDistance`, default 12 cm), implemented as designed below with no attachments.lua change.
  The attachments stale-entry fix below is still not implemented (not needed by FK).
- Touch grab (`touch = {enabled = true}`, 15 cm, one overlap across all object types on the press frame; prompt target is the
  fallback) and catching moving items (`stopPhysics`; FK settles its capsule early). FK uses both.
- Not done: Hogwarts touch/catch (needs a live check that its items have overlappable collision), step 4 (`ownsPress`), held-grip
  catch window, defaults flip (two hands / touch), SN2 migration.

The design notes below are the original step 3 plan and later sections; where they say "not implemented" they predate the
status above.

## Goal

With the two-hand grabbable (`hands = {Left, Right}`), gripping the item held in one hand with the other, free hand moves it to
the free hand instantly (no flight): the mesh copy re-attaches to the new hand and the hold (release/throw/collect) belongs to
the new hand from then on. Generic in grabbable; FK needs no game code for it (at most a distance option).

Behavior:
- Receiving hand: empty, not busy (game's grip callback has nothing in it, e.g. no weapon/torch), grip press *starts* within
  `handoffDistance` (default ~12 cm) of the other hand's held copy (world location of the copy vs the receiving controller).
- Only an item fully in the hand (not one still flying) can be handed off.
- The item keeps its copy; it snaps to the new hand's configured attachment transform (left hand config is the mirrored one;
  no flight, so no scale sign-flip handling is involved).
- Receiving hand gets the existing arriveHaptic buzz.
- Giving hand: its grip may still be held; that press stays owned/hidden; releasing it later does nothing (it holds nothing).
- Releasing the receiving grip throws/drops/collects as any held item, with the receiving hand's velocity and its shoulder
  collect gesture.
- Toggle-grip (dev) mode: a press of the free hand near the item transfers it; the item then stays in the new hand.

## grabbable.lua changes

### Single-hand instance (opt-in hook, only used by the two-hand wrapper)
- New internal option, e.g. `getHandoff = function(state) -> source|nil`: returns the other hand's instance when a handoff is
  possible for this hand right now. Absent (all existing single-hand users, e.g. Hogwarts): no change.
- Grip claim (`grip.registerClaim(self.name, ...)`): order becomes
  1. flight or held -> heldPriority (unchanged)
  2. `getHandoff(state)` returns a source -> `handoffPriority` (new option, default = claimPriority + a little, e.g. FK
     ITEM_HANDOFF = 150: above head gestures (90) and item grab (50), below ITEM_HELD (200))
  3. claim target -> claimPriority (unchanged)
  Using the instance's own claim (same claim name) means main.lua's existing `grip.isOwner(hand, GRIP_OWNERS[hand])` checks
  (no Y / no block / no BACK / no DPAD_DOWN) keep working for handoff presses with no FK change.
- onInput, on the press start frame when this instance owns the press and the handoff source is still valid: perform the
  transfer (below) instead of starting a flight; latch the press (gripLatched/gripWasPressed true) so its release releases the
  item.

### Transfer (wrapper-level function, moves the hold record between the two instances)
From giving instance A to receiving instance B, no destroy / no unhide / no physics:
- B takes A's: copy, held (= copy), heldActor, heldMesh, heldCollision, heldScale.
- B: flight nil, handSamples fresh, collectDeadline nil, atCollect nil, gripWasPressed/gripLatched true (current press).
- A: flight/held/copy/heldActor/heldMesh/heldCollision/heldScale nil, handSamples fresh. A's `falling` list untouched (items it
  dropped earlier keep easing). A's current press stays latched so it does nothing.
- `attachments.forceGripUpdate()`: grabbable's own grip callback (priority -10) now returns the copy for B's hand and nothing for
  A's, so attachments detaches it from A and attaches it to B on that same update.
- Fire B's arriveHaptic.
- Optional dev log (bounded) during testing only.

### Two-hand wrapper
- Supplies each instance's `getHandoff`: the other instance if it has `held` (not flight), this hand is empty and not busy
  (`attachments.getCurrentGrippedAttachment(hand) == nil`), the game's canClaim(state, hand) allows it, and the receiving
  controller is within handoffDistance of the other instance's copy (`controllers.getControllerLocation(hand)` vs
  `copy:K2_GetComponentLocation()`).
- New options: `handoffDistance` (cm, default ~12; 0 or false disables handoff), `handoffPriority`.
- `canGrab(actor, hand)` unchanged (prompt icon is about world items).

### Things that already work and need no change
- Attaching: grabbable's grip callback iterates instances by hand, so after the record moves the copy goes to the new hand;
  each hand's mesh/socket fall through from the game's callback (FK: arm_L2 / arm_R2).
- dropWhenHandTaken: B's check compares what B's hand grips with B's copy; A no longer holds anything.
- Re-showing the copy after hand rebuilds (attachment change callback) checks `self.held`, which moves with the record.

## attachments.lua: is a change needed?

### The stale-entry problem (recap)
Each grip attachment is tracked as `meshAttachmentList[meshName].attachments[attachmentName] = {..., gripHand}`.
`detachGripAttachments(hand)` detaches every entry with that gripHand. If one grip update moves component C from hand A to
hand B **and gives hand A a different attachment in that same update**, then with separate hand parents (Forearms hands, no
hands with controller components, raw controller), attaching A's new attachment runs `detachGripAttachments(A)`, finds C's old
A entry and detaches C from B. With IK arms (one mesh for both hands) the entry key is shared, but `attachToMesh`'s
"already tracked and parented to this mesh -> return true" check ignores the hand, so a move would not reach B's socket.

### Why FK's handoff does not hit it
The grip update first detaches every hand that gets *nothing* ("detach them first so switching left to right isnt affected"),
which removes C's old entry before B attaches it — in every hands mode, IK included (the entry is removed, so the early return
does not trigger). The problem only occurs if the giving hand gets something else in the same update. In FK:
- left gives -> FK's callback returns nothing for the left hand, ever;
- right gives -> FK returns the weapon/torch for the right only if one is drawn, and drawing one while holding drops the item
  (dropWhenHandTaken), so the right can't be holding an item and get a weapon in the same update.
So **FK's handoff should need no attachments.lua change.** Verify during testing (Forearms and IK modes) before adding one.

### The fix, if a game needs it later (e.g. a game whose giving hand gets its weapon back immediately)
All new paths run only when an attachment is attached under a different grip hand than it is tracked under; everything else
(same-hand attaches, rebuilt hands, every current project) stays on today's code.
1. `attachToMesh` early return ("already tracked under this mesh and parented to it"): also require the tracked entry's
   gripHand to equal the requested gripHand, so an IK move between hands re-sockets. Same-hand behavior unchanged.
2. Extract `clearGripHand(gripHand)` from `detachAndCleanup` (destroy laser and scope for the hand, clear its grip animation,
   fire the "attachment changed to nil" callback). Pure refactor; `detachAndCleanup` calls it.
3. New local `takeFromOtherHand(attachment, attachmentName, gripHand)`, called by `attachToMesh` before
   `detachGripAttachments(gripHand)` and by `attachToRawController` before it detaches its hand's raw entry:
   - for every tracked entry of this attachment whose gripHand is non-nil and different from the requested one: remove the
     entry **without detaching**, run `clearGripHand(oldHand)`, and if the old entry was RAW_CONTROLLER remove the attachment's
     motion controller state (otherwise UEVR keeps driving it to the old controller);
   - entries for the same hand are left alone (rebuilt hands keep today's detach-then-attach);
   - returns the removed entry.
4. Origin carry-over: when the new entry records where to return on release (reattachToOriginOnRelease), use the removed
   entry's parent / parentSocketName / originalTransform instead of the attachment's current parent (which is the old hand).
5. Weight spring arm (Melee + Weight in the attachments UI): the removed entry's spring arm is destroyed after the attachment
   is off it — in `attachToMesh` after a successful attach; in `attachToRawController` after `DetachFromParent(keep world)`.
   On a failed attach nothing more is done (same as today's failure path).
- Test matrix if implemented: Forearms, IK arms, no hands (controller components), raw controller; giving hand regains a
  weapon in the same update; an item with a configured weight; a weapon (reattachToOriginOnRelease) moved then released returns
  to its original holster, not the old hand.

## FK changes for step 3
- Probably none beyond an optional `handoffDistance` / `handoffPriority` (e.g. add ITEM_HANDOFF = 150 to
  helpers/grip_priority.lua) in the `grabbable.new({hands = ...})` options in helpers/interactions.lua.
- Note: `isGrabbable` / prompt icon logic don't change; handoff targets the held copy, not world items.

## Test plan (FK)
1. Left holds item, right (no weapon) grips near it -> moves to right; release throws from right; right shoulder collects.
2. Right holds item, left grips near it -> moves to left; left shoulder collects (inventory).
3. Right holds weapon -> left item can't be taken by the right (busy); left can take from right.
4. Grip far from the held item -> normal behavior (prompt grab or Y/block).
5. Release the giving grip after a handoff -> nothing happens (no Y, no drop).
6. Forearms and IK hands modes; switch modes while holding after a handoff.
7. Hogwarts: unchanged (single-hand, no getHandoff).

## Open decisions for step 3
- Reach test: distance only (copy location to receiving controller, ~12 cm), or also require the receiving palm to face the
  item (like pointing mode's cone). Start with distance only; add the cone if accidental handoffs happen when hands are close
  (e.g. two-handed weapon poses).
- Distance measured to the copy's origin. Long items (sticks, daggers) may want a larger radius or a distance to the copy's
  bounds; start with origin + option.
- Swap (both hands full, grip one near the other's item): not planned. The receiving hand must be empty.
- Handoff while the item is still flying to the giving hand: ignored (wait until it lands). Simpler and avoids two flights.
- Haptics: reuse arriveHaptic on the receiving hand; maybe a lighter buzz on the giving hand too (option, default off).

## Later: two hands by default
- Plan: when neither `hand` nor `hands` is given, default to both hands; `hand = X` keeps meaning one hand.
- Hogwarts passes `hand = Handed.Left` explicitly (HL_UEVR/scripts/helpers/interactions.lua:153), so flipping that default would
  not change Hogwarts. Check any other future users for an omitted `hand` before flipping (they currently get the left hand).
- With two hands, the default "busy" check (game's grip callback has something in the hand) is what keeps e.g. a wand hand from
  grabbing; a game whose wand can be stowed (Hogwarts) would then also want its own canClaim(state, hand) rule. That is the
  reason Hogwarts stays one-handed for now.

## Step 4 (later): FK's "is this a grab press" checks in main.lua
Today main.lua's own button mappings (left grip -> Y, inventory BACK, slot DPAD_UP; right grip -> block LB, ear DPAD_DOWN) run in
a pre-input callback (priority 5) on the raw state, so each mapping checks `grip.isOwner(hand, GRIP_OWNERS[hand])` to skip
presses Physical Item Grab owns. grip.lua already hides owned presses from the *game* (post-input), but not from these mappings.
Options:
- A. grip.Hide.Systems for grabbable's claims (grip.lua clears an owned grip right after deciding the owner, so every later
  pre-input callback, including main.lua's mappings, sees it released). Blocker: grabbable itself reads the grip from the state
  in its own input callback (would see it released; fixable with grip.isPressed(hand), which reports the press before hiding),
  and its collect gesture goes through gestures.getHeadGestures(state), which also reads the grip from the state (would never
  see the ear grip while carrying). Fixing that needs a gestures entry point that takes "is gripped" from the caller — a
  gestures.lua change. More invasive; only worth it if more mappings appear.
- B. Keep the checks but shrink them to one call per hand: e.g. `itemGrab:ownsPress(hand)` (true when either hand's grab or a
  handoff owns that hand's press). FK's checks become one line each, no knowledge of claim names. Small, no lib behavior change.
- Recommendation: B now; A only if several systems need the same hiding.

## SN2 migration outline (when you get back to SN2_UEVR)
SN2_UEVR/scripts/main.lua has its own two-hand grab (status.grabItem[hand], gripResourceItem, isItemGrippedByOtherHand,
releaseGrabItem, overlap-based targeting via collision labels, worldpop proxy actors, physics-handle option, its grip callback
returning grabbed items: right only without a tool, left always). Mapping onto the shared pieces:
- `grabbable.new({hands = {Left, Right}, ...})` replaces the per-hand grab state, the other-hand exclusion and the "right only
  without a tool" rule (busy check), and its grip callback replaces SN2's returning of grabbed items.
- SN2's targeting is by hand overlap (collision components), not a game prompt: either `getInteractTarget(state, hand)` returning
  the overlapped item for that hand, or grabbable's pointing mode. SN2's proxy spawning (worldpop actors) stays game code
  inside isGrabbable/getInteractTarget or a new "prepare actor" callback (to be decided).
- Differences to check: SN2 attaches the real component (or a spawned proxy) rather than a mesh copy, and has a physics-handle
  grip option. grabbable always holds a copy; SN2 may need an option to hold the actor's own component, or keep using proxies.
