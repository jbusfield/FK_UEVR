-- Precedence of the systems that share the VR grips through libs/grip: the claim with the highest number owns a press.
-- Kept in one table so the order is visible and adjustable in one place.
local M = {
	ITEM_HELD = 200,    -- interactions.lua (Physical Item Grab): a press while an item is already flying or held
	HEAD_GESTURE = 90,  -- main.lua: a left grip that starts over the shoulder (inventory) or at the mouth (slot 1)
	ITEM_GRAB = 50,     -- interactions.lua (Physical Item Grab): grab what the game's hover prompt is on
}

return M
