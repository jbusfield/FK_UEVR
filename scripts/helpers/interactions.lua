local uevrUtils = require('libs/uevr_utils')
local grabbable = require('libs/grabbable')
local ui = require('libs/ui')
local gestures = require('libs/gestures')
local prompts = require('libs/prompts')
local GRIP_PRIORITY = require('helpers/grip_priority')

local M = {}

------------------- Physical item grab -------------------
-- FateKeeper settings for libs/grabbable: a grip on the item the game's hover prompt is on (flowers, mushrooms, herbs and other
-- ItemActors, which the game picks up with Y) flies it into that hand; releasing throws or drops it with real physics. The right
-- hand only grabs with no weapon or torch in it. A grip with no grabbable item under the prompt is not claimed, so main.lua's grip
-- mappings (left Y, right block) handle it as before. libs/grabbable attaches the held copies on main.lua's hand meshes and
-- sockets, and drops an item when a weapon is drawn into its hand. Releasing over the hand's shoulder collects the item into the
-- inventory with ItemActor:PickUp.

-- Owner names of each hand's grip claims, for main.lua's checks of who owns a press.
M.GRIP_OWNERS = {[Handed.Left] = "item_grab", [Handed.Right] = "item_grab_right"}

-- Dev flag:
-- GRAB_TOGGLE_GRIP: the grip toggles (press to grab, the item stays after release, press again to drop), for adjusting
--   attachment transforms hands-free. No throwing in this mode.
local GRAB_TOGGLE_GRIP = false

grabbable.useRealPhysics(true)

local itemActorClass = nil

-- An item still moving under its capsule's physics (thrown, rolling) can be grabbed, e.g. caught in the air: grabbable settles it
-- first, where it is.
-- Items placed in a level with a static root (e.g. the explosive bomb recipe scroll) can't be moved, so the flight, the fall and
-- the release transform would only change their scale; the game's own pickup (Y) handles them instead. (libs/grabbable keeps
-- each hand off the other hand's item and off a hand with a weapon or torch in it.)
local MOVABLE = 2 -- EComponentMobility
local function isGrabbable(actor)
	itemActorClass = itemActorClass or uevrUtils.get_class("Class /Script/SLASHER.ItemActor")
	if itemActorClass == nil or not actor:is_a(itemActorClass) then return false end
	local root = uevrUtils.getValid(actor, {"RootComponent"})
	return root ~= nil and root.Mobility == MOVABLE
end

-- What the game's hover prompt is on: HeroWorldInteraction's focus, which is the item actor itself.
local function getInteractTarget()
	return uevrUtils.getValid(pawn, {"WorldInteractionController", "CurrentFocusedInteractive"})
end

-- Interactive UI (menus, overlays) keeps the grips.
local function canClaim()
	return not ui.isRemapDisabled()
end

-- Either hand grabs; releasing over that hand's shoulder (the left one is the inventory gesture's spot) puts the item in the
-- inventory with the game's own pickup.
local itemGrab = grabbable.new({
	hands = {Handed.Left, Handed.Right},
	names = M.GRIP_OWNERS,
	claimPriority = GRIP_PRIORITY.ITEM_GRAB,
	heldPriority = GRIP_PRIORITY.ITEM_HELD,
	isGrabbable = isGrabbable,
	canClaim = canClaim,
	getInteractTarget = getInteractTarget,
	-- A grip with the hand on an item grabs it; the hover prompt's item is the fallback for items out of reach.
	touch = {enabled = true},
	isCollectGesture = function(state, hand)
		local _, _, _, gripEar = gestures.getHeadGestures(state, hand, true)
		return gripEar
	end,
	-- PickUp adds the item to the inventory, but called from here the game doesn't always remove the actor, so a collected item
	-- is destroyed here; grabbable then sees it gone and removes the copy from the hand. A failed pickup leaves it for grabbable
	-- to drop.
	collectCallback = function(actor)
		local character = uevrUtils.getValid(pawn)
		if character ~= nil and actor:PickUp(character) == true and not actor.bActorIsBeingDestroyed then actor:K2_DestroyActor() end
	end,
	-- A short buzz on the hand once the item is in the inventory.
	collectHaptic = {duration = 0.08, amplitude = 0.5},
	toggleGrip = GRAB_TOGGLE_GRIP,
	keepDropScale = true,
	-- FateKeeper's item meshes (Megascans plants) have no simple collision, so a simulated mesh falls through everything: the item's
	-- InteractionCollider capsule simulates instead (libs/grabbable's managed physics). The capsule's scale must not change while it
	-- simulates (that rebuilds its shape and can drop it through the ground), hence keepDropScale. A capsule on its side rolls like a
	-- rolling pin and damping only slows the roll, so its rotation is locked while it simulates (it falls and slides, keeping its
	-- release angle) and it gets some damping. Mass doesn't help: gravity moves every mass the same.
	physics = {
		getBody = function(actor) return uevrUtils.getValid(actor, {"InteractionCollider"}) end,
		linearDamping = 1,
		angularDamping = 4,
		lockRotation = {roll = true, pitch = true, yaw = true},
	},
	dropWhenHandTaken = true,
})

------------------- Pickup prompt icon -------------------
-- The game's prompt on an item shows its pickup key (Y). For an item a grip would grab, the icon shows that grip instead (libs/
-- prompts puts the game's icon back otherwise): RB while the right hand is targeting (main.lua's setDefaultTargeting) and can
-- grab (no weapon in it), otherwise LB. The prompts are the crosshair's pickup entries (the game builds a new one each time
-- something is hovered); their icon is the Texture parameter of the icon image's material.
local PROMPT_INTERVAL_MS = 100
local PICKUP_ACTION = "IA_Interaction_Primary"
local GRIP_ICONS = {
	[Handed.Left] = "Texture2D /Game/SLASHER/Art/UI/Input/T_Hotkey_LB.T_Hotkey_LB",
	[Handed.Right] = "Texture2D /Game/SLASHER/Art/UI/Input/T_Hotkey_RB.T_Hotkey_RB",
}
local targetingHand = Handed.Right
local promptList = nil

function M.setTargetingHand(hand)
	targetingHand = hand
end

-- The hand whose grip would grab the hovered item, or nil when neither would.
local function getPromptHand(target)
	if not canClaim() then return nil end
	local hand = (targetingHand == Handed.Right and itemGrab:canGrab(target, Handed.Right)) and Handed.Right or Handed.Left
	if itemGrab:canGrab(target, hand) then return hand end
	return nil
end

local function getPromptList()
	local list = uevrUtils.getValid(promptList)
	if list == nil then
		local layout = uevrUtils.find_first_instance("WidgetBlueprintGeneratedClass /Game/SLASHER/Blueprints/UI/WBP_SlasherGameLayout.WBP_SlasherGameLayout_C", false)
		list = uevrUtils.getValid(layout, {"InGameOverlay", "Crosshair", "InteractionContextScrollBox"})
		promptList = list
	end
	return list
end

-- The key icon images of the crosshair's pickup entries.
local function getPickupIcons()
	local list = getPromptList()
	if list == nil then return nil end
	local icons = {}
	for i = 0, list:GetChildrenCount() - 1 do
		local entry = list:GetChildAt(i)
		local action = uevrUtils.getValid(entry, {"InputInfo", "InputAction"})
		local keys = uevrUtils.getValid(entry, {"InputInfo", "DisplayedKeys_HB"})
		if action ~= nil and keys ~= nil and action:get_fname():to_string() == PICKUP_ACTION and keys:GetChildrenCount() > 0 then
			local icon = uevrUtils.getValid(keys:GetChildAt(0), {"InputIcon"})
			if icon ~= nil then icons[#icons + 1] = icon end
		end
	end
	return icons
end

local getIconTexture, setIconTexture = prompts.materialTexture("Texture")
local promptIcon = prompts.new({
	interval = PROMPT_INTERVAL_MS,
	getPrompts = getPickupIcons,
	get = getIconTexture,
	set = setIconTexture,
	getReplacement = function()
		local target = getInteractTarget()
		local hand = target ~= nil and getPromptHand(target) or nil
		return hand ~= nil and prompts.loadAsset(GRIP_ICONS[hand]) or nil
	end,
})
------------------- End pickup prompt icon -------------------

function M.setItemGrabEnabled(value)
	itemGrab:setEnabled(value == true)
	promptIcon:setEnabled(value == true)
end

function M.setGrabToggleGrip(value)
	GRAB_TOGGLE_GRIP = value == true
	itemGrab:setToggleGrip(GRAB_TOGGLE_GRIP)
end

------------------- End physical item grab -------------------

return M
