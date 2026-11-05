local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local configui = require("libs/configui")
local reticule = require("libs/reticule")
local hands = require('libs/hands')
local attachments = require('libs/attachments')
local input = require('libs/input')
local pawnModule = require('libs/pawn')
local animation = require('libs/animation')
local montage = require('libs/montage')
local interaction = require('libs/interaction')
local ui = require('libs/ui')
local remap = require('libs/remap')
local gestures = require('libs/gestures')
local ik = require('libs/ik')
local mathLib = require('libs/core/math_lib')
--local handsAnimation = require('libs/hands_animation')
local mouse = require('libs/mouse')
--local tArray = require("libs/core/tarray")
local plugin = require("libs/core/plugin")
local keyboard = require("libs/keyboard")
local melee = require('helpers/melee')
local grip = require('libs/grip')
local GRIP_PRIORITY = require('helpers/grip_priority')
local interactions = require('helpers/interactions')

--uevrUtils.setLogLevel(LogLevel.Warning)
--attachments.setLogLevel(LogLevel.Debug)
--input.setLogLevel(LogLevel.Debug)


--plugin.showDebug = true

--uevrUtils.setDeveloperMode(true)
--hands.enableConfigurationTool()

ui.init()
montage.init()
interaction.init()
attachments.init()
attachments.setGripUpdateTimeout(400)
reticule.init()
pawnModule.init()
remap.init()
input.init()
input.preventPawnSettingsResetOnDisable(true)
ik.init()
hands.setAutoCreateHands(false)
ik.setAutoCreateArms(false)
gestures.init()
gestures.setUseRawControllers(true)

uevrUtils.set_decoupled_pitch_adjust_ui(false)

local status = {}

local HandsType = {
	None = 0,
	Forearms = 1,
	IKArms = 2,
	-- None = 1,
	-- Forearms = 2,
	-- IKArms = 3,
}

local isDeveloperMode = false
if uevrUtils.getDeveloperMode() ~= nil then
	isDeveloperMode = uevrUtils.getDeveloperMode() or false
end

local versionTxt = "v1.0.4"
local title = "FateKeeper, First Person Mod " .. versionTxt
local configDefinition = {
	{
		panelLabel = "FateKeeper Config",
		saveFile = "fatekeeper_config",
		layout = spliceableInlineArray
		{
			{ widgetType = "text", id = "title", label = title },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Control" }, { widgetType = "begin_rect", },
                 {
                    widgetType = "combo",
                    id = "hands_type",
                    label = "Hands Type",
                    --selections = {"None", "Forearms", "IK Arms"},
                    selections = {"Forearms", "IK Arms"},
                    initialValue = 1,
                },
                {
                    widgetType = "checkbox",
                    id = "physical_item_grab",
                    label = "Physical Item Grab",
                    initialValue = true
                },
                {
                    widgetType = "checkbox",
                    id = "left_hand_palm_aim",
                    label = "Left Hand Palm Aim",
                    initialValue = false
                },
                { widgetType = "indent", width = 20 },
                    {
                        widgetType = "drag_float3",
                        id = "palm_aim_offset",
                        label = "Palm Aim Offset",
                        speed = 1,
                        range = {-360, 360},
                        initialValue = {0,0,0},
                        isHidden = false,
                    },
                { widgetType = "unindent", width = 20 },
 			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "UI" }, { widgetType = "begin_rect", },
				expandArray(ui.getConfigurationWidgets, {{id="uevr_ui_reduceMotionSickness",isHidden=true}}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Overlay" }, { widgetType = "begin_rect", },
                {
                    widgetType = "drag_float2",
                    id = "overlay_scale",
                    label = "Scale",
                    speed = .01,
                    range = {0.01, 2},
                    initialValue = {1, 1}
                },
            { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Input" }, { widgetType = "begin_rect", },
				expandArray(input.getConfigurationWidgets, {{id="uevr_input_config_pawnRotationMode",isHidden=true}}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },

			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Controller Mapping" }, { widgetType = "begin_rect", },
                { widgetType = "indent", width = 10 },
				{ widgetType = "text", wrapped = true, label = "Attack: Physically swing right controller", },
				{ widgetType = "text", wrapped = true, label = "Heavy Attack: Hold Right Trigger while swinging", },
				{ widgetType = "text", wrapped = true, label = "Kick: Right Stick press down", },
				{ widgetType = "text", wrapped = true, label = "Block: Hold Right Grip", },
				{ widgetType = "text", wrapped = true, label = "Cast Spell: Left Trigger", },
				--{ widgetType = "text", wrapped = true, label = "Run: Left Stick press down (toggles run)", },
				{ widgetType = "text", wrapped = true, label = "Jump: Right Stick Forward", },
				{ widgetType = "text", wrapped = true, label = "Dodge: Right Stick Backward + Left Stick direction", },
				{ widgetType = "text", wrapped = true, label = "Physical Item Grab: Grip a hovered item with an empty hand. Release over your shoulder to put it in your inventory, release elsewhere to drop it", },
				{ widgetType = "text", wrapped = true, label = "Cancel/Exit: B button", },
				{ widgetType = "text", wrapped = true, label = "Change Weapon: Right Grab with your hand over your right shoulder", },
				{ widgetType = "text", wrapped = true, label = "Weapon/Spell Wheel: X button", },
				{ widgetType = "text", wrapped = true, label = "Use Slot 1: Left Grip near mouth", },
				{ widgetType = "text", wrapped = true, label = "Menu: Press left Menu button", },
				{ widgetType = "text", wrapped = true, label = "Inventory: Hold left Menu button (2 seconds) OR Left Grip with your hand over your left shoulder", },
               {widgetType = "unindent", width = 10 },
            { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },

			{ widgetType = "begin_group", id = "dev_group", isHidden = not isDeveloperMode },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Developer" }, { widgetType = "begin_rect", },
				{
					widgetType = "checkbox",
					id = "grab_toggle_grip",
					label = "Grab Toggle Grip",
					initialValue = false,
				},
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "end_group" },
			{ widgetType = "new_line" },
		}
	}
}
local options = {
	{label = "Default", shape=ui.ShapeEnum.Flat, headLockedUISize = 2.0, headLockedUIPosition = {X=0, Y=0, Z=2.0}},
	{label = "Helmet", shape=ui.ShapeEnum.Cylinder, headLockedUISize = 0.53, headLockedUIPosition = {X=-0.03, Y=0, Z=0.34}}
}
ui.setHeadLockedUIOptions(options)

local function cleanup()
    melee.finish()
    local widget = status.cursorWidget
    if widget ~= nil and uevrUtils.getValid(widget) ~= nil then
        widget:RemoveFromParent()
    end
    status = {}
end

local function regenerateHands(value)
    hands.setAutoCreateHands(value == HandsType.Forearms)
    ik.setAutoCreateArms(value == HandsType.IKArms)

    hands.destroyHands()
    ik.destroyAll()
end

ik.registerOnDestroyCallback(function(ikInstance)
    if status.currentWeapon ~= nil then
        status.currentWeapon:SetVisibility(false, false)
    end
    attachments.detachAllAttachments()
end)

hands.registerOnDestroyCallback(function()
    if status.currentWeapon ~= nil then
        status.currentWeapon:SetVisibility(false, false)
    end
    attachments.detachAllAttachments()
end)

hands.onCreatedCallback(function(hand, component, name)
end)

ik.registerOnMeshCreatedCallback(function(meshComponentList, ikInstance)
end)

local function getHandComponents()
    local rightHandComponent = nil
   	local leftHandComponent = nil
    if configui.getValue("hands_type") == HandsType.None then
        rightHandComponent = controllers.getController(Handed.Right)
        leftHandComponent = controllers.getController(Handed.Left)
    elseif configui.getValue("hands_type") == HandsType.Forearms then
        rightHandComponent = hands.getHandComponent(Handed.Right)
        leftHandComponent = hands.getHandComponent(Handed.Left)
    elseif configui.getValue("hands_type") == HandsType.IKArms then
        rightHandComponent = ik.getCurrentMesh()
		leftHandComponent = ik.getCurrentMesh()
    end

    return rightHandComponent, leftHandComponent
end

local defaultAttachOptions = {
	detachFromOriginOnGrip = false,
	maintainWorldPositionOnDetachFromOrigin = true,
	detachFromParentOnRelease = true,
	maintainWorldPositionOnDetachFromParent = true,
	reattachToOriginOnRelease = true,
	restoreTransformToOriginOnReattach = true,
	restoreSocketToOriginOnReattach = true,
	useZeroTransformOnReattach = false,
	allowChildVisibilityHandling = false,
	allowChildHiddenInGameHandling = false,
	allowRenderInMainPassHandling = false,
    useCurrentAttachedSocketName = false
}



local function checkCastingWeapons()
    local pawn = pawnModule.getPawn() or uevr.api:get_local_pawn(0)
    if pawn == nil or pawn.Mesh == nil or pawn.Mesh.AttachChildren == nil then
        return nil
    end
    for _, child in ipairs(pawn.Mesh.AttachChildren) do
        child = uevrUtils.getValid(child)
        if child ~= nil then
            local fullName = child:get_full_name()
            if fullName ~= nil then
                if fullName:find("NiagaraComponent", 1, true) and (child.AttachSocketName:to_string() == "arm_L2" or child.AttachSocketName:to_string() == "Socket_Cast_L") then
                    controllers.attachComponentToController(Handed.Left, child)
                    --print("Found casting effect, attaching to left hand")
                end
                if (fullName:find("Ring.L.0", 1, true) or fullName:find("Ring.L.1", 1, true) or fullName:find("Ring.L.2", 1, true) or fullName:find("Ring.L.3", 1, true)) and child.StaticMesh ~= nil then
                    local rightHandComponent, leftHandComponent = getHandComponents()
                    attachments.attachToMesh(child, leftHandComponent, child.AttachSocketName, nil, defaultAttachOptions)
                end
                if (fullName:find("Ring.R.0", 1, true) or fullName:find("Ring.R.1", 1, true) or fullName:find("Ring.R.2", 1, true) or fullName:find("Ring.R.3", 1, true)) and child.StaticMesh ~= nil then
                    local rightHandComponent, leftHandComponent = getHandComponents()
                    attachments.attachToMesh(child, rightHandComponent, child.AttachSocketName, nil, defaultAttachOptions)
                end
            end
        end
    end
end
setInterval(200,checkCastingWeapons)

local function getWeaponMesh()
    local pawn = pawnModule.getPawn() or uevr.api:get_local_pawn(0)
    if pawn == nil then
        return nil
    end

    -- A gripped weapon is parented to the VR hand, so it is no longer in
    -- pawn.Mesh.AttachChildren. Keep it while its slot still holds a weapon.
    -- Reset Scripts reattaches it to the Hero mesh (attachments.detachAllAttachments),
    -- where the scan below finds it again.
    local current = uevrUtils.getValid(status.currentWeapon)
    if current ~= nil and current.StaticMesh ~= nil then
        local assetName = current.StaticMesh:get_full_name()
        if assetName:find('/Weapons/', 1, true) then
            status.currentWeaponStaticMeshName = assetName
            current:SetVisibility(true, false)
            return current
        end
    end

    if pawn.Mesh == nil or pawn.Mesh.AttachChildren == nil then
        return nil
    end

    for _, child in ipairs(pawn.Mesh.AttachChildren) do
        child = uevrUtils.getValid(child)
        if child ~= nil then
            local fullName = child:get_full_name()

            if fullName ~= nil and fullName:find("NiagaraComponent", 1, true) and (child.AttachSocketaName == "arm_L2" or child.AttachSocketaName == "Socket_Cast_L") then
                controllers.attachComponentToController(Handed.Left, child)
            end

            if fullName ~= nil
                and fullName:find("EquipmentSlot.Hand.R", 1, true)
                and (
                    (child.StaticMesh ~= nil and child.StaticMesh:get_full_name():find("/Weapons/", 1, true))
                    or
                    (child.SkeletalMesh ~= nil and child.SkeletalMesh:get_full_name():find("/Weapons/", 1, true))
                )
            then
                status.currentWeapon = child
                status.currentWeaponStaticMeshName = child.StaticMesh:get_full_name()
                status.currentWeapon:SetVisibility(true, false)
                return child
            end
            if fullName ~= nil
                and fullName:find("Hand.R.Torch", 1, true)
                and (
                    (child.StaticMesh ~= nil and child.StaticMesh:get_full_name():find("/Weapons/", 1, true))
                    or
                    (child.SkeletalMesh ~= nil and child.SkeletalMesh:get_full_name():find("/Weapons/", 1, true))
                )
            then
                status.currentWeapon = child
                status.currentWeaponStaticMeshName = child.StaticMesh:get_full_name()
                --print("New weapon", status.currentWeaponStaticMeshName)
                status.currentWeapon:SetVisibility(true, false)
                return child
            end

        end
    end

    return nil
end

attachments.registerOnGripUpdateCallback(function()
    local weaponMesh = getWeaponMesh()
	if weaponMesh ~= status.currentWeapon then
		status.currentWeapon = weaponMesh
    end

    local rightHandComponent, leftHandComponent = getHandComponents()
    local weaponAttachSocket = "arm_R2" --"Socket_HandR" --"ToolSocket" --"hand_rSocket" --"RightItemSocket" --"middle_03_r"
	--return rightHandComponent and weaponMesh, rightHandComponent, weaponMesh and weaponMesh.AttachSocketName or nil, nil, nil, nil, defaultAttachOptions
	-- Held items (helpers/interactions) are attached by libs/grabbable's own grip callback, below this one, on these hand meshes and
	-- sockets; a weapon drawn into a hand holding one takes the hand, and the item is dropped. The left hand only holds items.
	return rightHandComponent and weaponMesh, rightHandComponent, weaponAttachSocket, nil, leftHandComponent, "arm_L2", defaultAttachOptions
end)

function getCustomIKComponent(rigID)
    local path = "Pawn"
    return {{descriptor = path .. ".Mesh"}, {descriptor = path .. ".Mesh(Chest_Hero)", animation = "Arms", optional = true}}
end

--not a good indicator of ready state in this game
function on_level_change(level)
    print(level:get_full_name())
end

attachments.registerAttachmentChangeCallback(function(id, hand, attachment)
    if hand==Handed.Right then melee.resetWeapon() end
	-- Reduces processing when no melee weapon is equipped
    local isRightMelee = attachments.isActiveAttachmentMelee(Handed.Right)
    local isLeftMelee = attachments.isActiveAttachmentMelee(Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWING, isRightMelee, Handed.Right)

    if status.currentWeapon ~= nil then
        status.currentWeapon:SetVisibility(true, false)
    end
end)

local function setDefaultTargeting(handed, offset)
	interactions.setTargetingHand(handed) -- the pickup prompt shows the targeting hand's grip
	if handed == Handed.Left then
		input.setAimMethod(input.AimMethod.LEFT_CONTROLLER)
        if configui.getValue("left_hand_palm_aim") then
            local palmOffset = configui.getValue("palm_aim_offset")
            if palmOffset then
                input.setAimRotationOffset({Pitch=palmOffset.X, Yaw=palmOffset.Y, Roll=palmOffset.Z})
            else
                input.setAimRotationOffset({Pitch=-20, Yaw=60, Roll=0})
            end
        else
            input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
        end
        --input.setAimRotationOffset({Pitch=-20, Yaw=60, Roll=0})
        --input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
	else
		input.setAimMethod(input.AimMethod.RIGHT_CONTROLLER)
        input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
	end
end

--won't callback unless an updateDeferral hasnt been called in the last 1000ms
uevrUtils.createDeferral("melee_attack", 1000, function()
    input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
end)

local function setMeleeOffset(hand)
    local offset = attachments.getActiveAttachmentMeleeRotationOffset(hand)
    if offset then
        input.setAimRotationOffset(offset)
        uevrUtils.updateDeferral("melee_attack")
    end
end

gestures.registerSwingBeginCallback(function(strength, hand)
    if hand ~= Handed.Right or not attachments.isActiveAttachmentMelee(Handed.Right) or ui.isRemapDisabled() then return end
    melee.beginSwing()
    setDefaultTargeting(Handed.Right)
    setMeleeOffset(Handed.Right)
end, true, false)

gestures.registerSwingEndCallback(function(strength, hand)
    if hand == Handed.Right then melee.endSwing() end
end, true, false)



local function executeIsArmBonesHiddenCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_arms_bones_hidden", table.unpack({...}))
end


--if montages chose to show th arm bones then show the head bone too
local function checkBonesHidden()
	if uevrUtils.getValid(pawn) == nil then return end
	local isHidden, priority = executeIsArmBonesHiddenCallback()
	if isHidden == false and not status.isPlayingCinematicMontage then
        pawn.Mesh:UnHideBoneByName(uevrUtils.fname_from_string("head1"))
    else
        pawn.Mesh:HideBoneByName(uevrUtils.fname_from_string("head1"), 0)
    end
end

local attackMontages = {
	AM_Hero_1HAxe_Attack_Light_01 = true,
    AM_Hero_1HAxe_Attack_Light_02 = true,
    AM_Hero_1HAxe_Attack_Light_03 = true,
    AM_Hero_1HAxe_Attack_Light_04 = true,
    AM_Hero_1HAxe_Attack_Heavy_01_Start = true,
    AM_Hero_1HAxe_Attack_Heavy_02_Start = true,
    AM_Hero_1HAxe_Attack_Heavy_03_Start = true,
    AM_Hero_1HAxe_Attack_Heavy_01_Hold = true,
    AM_Hero_1HAxe_Attack_Heavy_02_Hold = true,
    AM_Hero_1HAxe_Attack_Heavy_03_Hold = true,
    AM_Hero_1HAxe_Attack_Heavy_01_Execute = true,
    AM_Hero_1HAxe_Attack_Heavy_02_Execute = true,
    AM_Hero_1HAxe_Attack_Heavy_03_Execute = true,

    AM_Hero_2HSword_Attack_Light_01 = true,
    AM_Hero_2HSword_Attack_Light_02 = true,
    AM_Hero_2HSword_Attack_Light_03 = true,
    AM_Hero_2HSword_Attack_Light_04 = true,
    AM_Hero_2HSword_Attack_Heavy_01_Start = true,
    AM_Hero_2HSword_Attack_Heavy_02_Start = true,
    AM_Hero_2HSword_Attack_Heavy_03_Start = true,
    AM_Hero_2HSword_Attack_Heavy_01_Hold = true,
    AM_Hero_2HSword_Attack_Heavy_02_Hold = true,
    AM_Hero_2HSword_Attack_Heavy_03_Hold = true,
    AM_Hero_2HSword_Attack_Heavy_01_Execute = true,
    AM_Hero_2HSword_Attack_Heavy_02_Execute = true,
    AM_Hero_2HSword_Attack_Heavy_03_Execute = true,

    AM_Hero_1HDagger_Attack_Light_01 = true,
    AM_Hero_1HDagger_Attack_Light_02 = true,
    AM_Hero_1HDagger_Attack_Light_03 = true,
    AM_Hero_1HDagger_Attack_Light_04 = true,
    AM_Hero_1HDagger_Attack_Heavy_01_Start = true,
    AM_Hero_1HDagger_Attack_Heavy_02_Start = true,
    AM_Hero_1HDagger_Attack_Heavy_03_Start = true,
    AM_Hero_1HDagger_Attack_Heavy_01_Hold = true,
    AM_Hero_1HDagger_Attack_Heavy_02_Hold = true,
    AM_Hero_1HDagger_Attack_Heavy_03_Hold = true,
    AM_Hero_1HDagger_Attack_Heavy_01_Execute = true,
    AM_Hero_1HDagger_Attack_Heavy_02_Execute = true,
    AM_Hero_1HDagger_Attack_Heavy_03_Execute = true,

    AM_Hero_Unarmed_Fight_Attack_Light_01 = true,
    AM_Hero_Unarmed_Fight_Attack_Light_02 = true,
    AM_Hero_Unarmed_Fight_Attack_Light_03 = true,
    AM_Hero_Unarmed_Fight_Attack_Light_04 = true,
    AM_Hero_Unarmed_Fight_Attack_Heavy_01_Start = true,
    AM_Hero_Unarmed_Fight_Attack_Heavy_02_Start = true,
    AM_Hero_Unarmed_Fight_Attack_Heavy_03_Start = true,
    AM_Hero_Unarmed_Fight_Attack_Heavy_01_Hold = true,
    AM_Hero_Unarmed_Fight_Attack_Heavy_02_Hold = true,
    AM_Hero_Unarmed_Fight_Attack_Heavy_03_Hold = true,
    AM_Hero_Unarmed_Fight_Attack_Heavy_01_Execute = true,
    AM_Hero_Unarmed_Fight_Attack_Heavy_02_Execute = true,
    AM_Hero_Unarmed_Fight_Attack_Heavy_03_Execute = true,

}
local cinematicMontages = {
    AM_Hero_Cinematic_FirstRuneDeviceInteraction = true,
    AM_Hero_Cinematic_TutorialPostPortal = true,
    AM_Hero_EAIntroductionDialogue = true
}
montage.registerMontageChangeCallback(function(montageObject, montageName, label)
	--print("Montage changed callback:", montageName, label)
	if montageName ~= "" and label == "Pawn" then
		-- local knownAttackMontage = attackMontages[montageName]
		-- if knownAttackMontage == true then
        --     if pawn ~= nil then
        --         status.isPlayingAttackMontage = true
        --     end
		-- end

        local knownCinematicMontage = cinematicMontages[montageName]
		if knownCinematicMontage == true then
            -- --print("Known cinematic montage detected")
            -- uevrUtils.setUEVRParam("VR_CameraForwardOffset", -15)
            -- uevrUtils.setUEVRParam("VR_CameraUpOffset", 20)
            uevrUtils.setIsInCutsceneOverride(true)
            -- The cave walk heads along world yaw 0. Face the pawn and controller there, then
            -- resetView so input.lua re-reads its view yaw from the pawn on the next tick (the
            -- view follows decoupledYaw, not the forced body yaw), and hold the body at 0.
            if montageName == "AM_Hero_EAIntroductionDialogue" then
                local currentPawn = uevrUtils.getValid(pawn)
                if currentPawn ~= nil and currentPawn.Controller ~= nil then
                    currentPawn.Controller:SetControlRotation(uevrUtils.rotator(0, 0, 0))
                    currentPawn:K2_SetActorRotation(uevrUtils.rotator(0, 0, 0), false)
                end
            end
            input.resetView()
            input.setForcedBodyYaw(0)

            status.isPlayingCinematicMontage = true
		end
	end
    if (montageName == nil or montageName == "") then
        --status.isPlayingAttackMontage = false
        uevrUtils.setIsInCutsceneOverride(nil)
        if status.isPlayingCinematicMontage == true then
            input.setForcedBodyYaw(nil)
            -- uevrUtils.setUEVRParam("VR_CameraForwardOffset", 0)
            -- uevrUtils.setUEVRParam("VR_CameraUpOffset", 0)
        end
        status.isPlayingCinematicMontage = false
    end

    -- if montageName contains "_Equip" then hide the equipped weapon
    -- makes the transition look nicer
    if montageName ~= "" and montageName:find("_Equip", 1, true) then
        local previousName = status.currentWeaponStaticMeshName
        local weaponMesh = getWeaponMesh()
        if weaponMesh ~= nil and status.currentWeaponStaticMeshName ~= previousName then
            weaponMesh:SetVisibility(false, false)
        end
    end

    checkBonesHidden()
end)


local STICK_DEADZONE = 22000

local screenWidgets = {}
local function getTopLevelWidgetsOnScreen(widgetNames)
    local result = {}

    status.gameInstance = status.gameInstance or Statics:GetGameInstance(uevrUtils.getWorld())
    if status.gameInstance ~= nil and status.gameInstance.GameLayout ~= nil then
        local layout = status.gameInstance.GameLayout
        for _, widgetName in pairs(widgetNames) do
            local widget = layout[widgetName]
             if widget ~= nil and ((widget:IsVisible() and widget.WidgetTree.RootWidget:GetVisibility() == 0) or (widget:IsVisible() and widget:GetVisibility() == 4 and widget.WidgetTree.RootWidget:GetVisibility() == 4)) then
                table.insert(result, {name = widgetName, widget = widget})
            end
        end
        local radialMenu = layout.InGameOverlay and layout.InGameOverlay.RadialMenuWidget
        if radialMenu ~= nil and layout.InGameOverlay:IsVisible() and radialMenu:IsVisible() then
            layout.InGameOverlay.BlackBackground:SetVisibility(1)
            table.insert(result, {name = "RadialMenuWidget", widget = radialMenu})
        end
     end
    return result
end
getTopLevelWidgetsOnScreen = uevrUtils.profiler:wrap('main.getTopLevelWidgetsOnScreen', getTopLevelWidgetsOnScreen)

local function updateScreenWidgets()
    local widgetNames = {
        "EmptyScreen",
        "StartScreen",
        "ShaderCompileScreen",
        "MainMenu",
        "LoadingScreen",
        "EndScreen",
        "InGameOverlay",
        "CutsceneOverlay",
        "CharacterScreen",
        "DeathScreen",
        "ExitLevelScreen",
        "SaveScreen",
        "AlchemyPanel",
        "TravelMapPanel",
        "SubtitleAndFlavorContainerWidget",
        "ConfirmationScreen"
    }

	local widgets = getTopLevelWidgetsOnScreen(widgetNames)
    local currentWidgets = {}
	for i, widgetInfo in ipairs(widgets) do
		local widget = widgetInfo.widget
		local widgetKey = tostring(widget) --keys look like sol.uevr::API::UObject*: 00000233A4B9FEA8
		local isShown = true --widget:IsShown()
		currentWidgets[widgetKey] = {widget = widget, isShown = isShown}

		-- Check if this is a new widget or state changed
		local previousState = screenWidgets[widgetKey]
		if previousState == nil or previousState.isShown ~= isShown then
			-- State changed - update viewport accordingly
			if isShown then
				ui.addViewportWidget(widget)
			else
				ui.removeViewportWidget(widget)
			end
		end
	end

	-- Check for removed widgets and clean up
	for widgetKey, widgetData in pairs(screenWidgets) do
		if currentWidgets[widgetKey] == nil then
			-- Widget was removed - remove from viewport if it was shown
			if widgetData.isShown then
				ui.removeViewportWidget(widgetData.widget)
			end
		end
	end

	-- Update the tracked widgets
	screenWidgets = currentWidgets
end

ui.registerWidgetChangeCallback("WBP_CutsceneOverlay_C", function(active)
    checkBonesHidden()
    --input.setCurrentProfileByLabel(active and "Cinematic" or "Default")
end)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
    if user_index ~= 0 then return end

    melee.setHeavyInput(state.Gamepad.bRightTrigger > 0 and not ui.isRemapDisabled())

    local handed = Handed.Right
	local isEating, isGrabbingGlasses, gripHead, isGrabbingEar, triggerMouth, isScratchingEyes, triggerHead, isScratchingEar = gestures.getHeadGestures(state, 1-handed, true)
	local isEatingRight, isGrabbingGlassesRight, gripHeadRight, isGrabbingEarRight, triggerMouthRight, isScratchingEyesRight, triggerHeadRight, isScratchingEarRight = gestures.getHeadGestures(state, handed, false)

    if ui.isRemapDisabled() == true then
        return
    end

    -- A press owned by Physical Item Grab (helpers/interactions) is left as it is: grabbable reads the grip after this callback
    -- and grip.lua hides it from the game, so a left one must not become Y, open the inventory or use slot 1, and a right one
    -- must not block or press DPAD_DOWN.
    local isItemGrabPress = grip.isOwner(Handed.Left, interactions.GRIP_OWNERS[Handed.Left])
    local isRightItemGrabPress = grip.isOwner(Handed.Right, interactions.GRIP_OWNERS[Handed.Right])

    if isGrabbingEar and not isItemGrabPress then
        uevrUtils.pressButton(state, XINPUT_GAMEPAD_BACK)
    end

    if isGrabbingEarRight and not isRightItemGrabPress then
        uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_DOWN)
    end
    -- if isScratchingEarRight then
    --     uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_DOWN)
    -- end

    local isPressingRightShoulder = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
    local isPressingLeftShoulder = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
    local isPressingLeftTrigger = state.Gamepad.bLeftTrigger > 0
    local isPressingRightTrigger = state.Gamepad.bRightTrigger > 0
    local isRightStickDown = state.Gamepad.sThumbRY < -STICK_DEADZONE
    local isRightStickUp = state.Gamepad.sThumbRY > STICK_DEADZONE
    local isLeftStickPressed = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_THUMB)

    -- prevent annoying accidental snap turn when jumping
    --TODO make sure input module isnt executing first
    local jumpTurnDeadzone = 32000
	if state.Gamepad.sThumbRY >= jumpTurnDeadzone or state.Gamepad.sThumbRY <= -jumpTurnDeadzone then
		state.Gamepad.sThumbRX = 0
	end

    --left trigger casts spells
    state.Gamepad.bRightTrigger = (isPressingLeftTrigger and not isEating) and 255 or 0
    state.Gamepad.bLeftTrigger = 0

    if isPressingLeftShoulder and not isItemGrabPress then
        uevrUtils.pressButton(state, XINPUT_GAMEPAD_Y)
        uevrUtils.unpressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
    end

    --block
    if isPressingRightShoulder and not isRightItemGrabPress then
        uevrUtils.pressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
        uevrUtils.unpressButton(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
    end

    if isEating and not isItemGrabPress then
        uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_UP)
    end

    --state.Gamepad.bRightTrigger = 0
    if uevrUtils.isButtonPressed(state,XINPUT_GAMEPAD_A) then
        setDefaultTargeting(Handed.Right)
    else
        if isPressingRightTrigger or isPressingRightShoulder then
            setDefaultTargeting(Handed.Right)
        elseif isPressingLeftTrigger or isPressingLeftShoulder then
            setDefaultTargeting(Handed.Left)
        end
    end

end, 5) --increased priority to get values before remap occurs

-- Grip arbitration (libs/grip): a left grip that starts over the shoulder (inventory) or at the mouth (slot 1) belongs to that
-- gesture, so Physical Item Grab doesn't grab the hovered item; an item already in the hand keeps the grip (see helpers/grip_priority).
-- The game still sees these presses as before.
grip.registerClaim("head_gesture", function(hand, state)
	if hand ~= Handed.Left then return nil end
	local gripMouth, _, _, gripEar = gestures.getHeadGestures(state, Handed.Left, true)
	if gripMouth or gripEar then return GRIP_PRIORITY.HEAD_GESTURE end
	return nil
end, {hide = grip.Hide.None})

-- In this game, on_level_change is not a good indicator that re-initialization is ready
-- So we use PlayState as the indicator instead, and re-initialize when the state changes to Playing
local function onPlayStateChanged(isPlaying)
    print("Play state changed. Is playing:", isPlaying)
    if isPlaying then
        delay(500, function()
            cleanup()
            pawnModule.reset()
            pawn.Mesh:HideBoneByName(uevrUtils.fname_from_string("head1"), 0)
            hands.setAutoCreateHands(configui.getValue("hands_type") == 1)
            ik.setAutoCreateArms(configui.getValue("hands_type") == 2)
            input.reset()
            input.setDisabled(false)
            uevrUtils.setUEVRParam("VR_CameraForwardOffset", 0)
            uevrUtils.setUEVRParam("VR_CameraUpOffset", 0)
            --initializeInputMappings()
            -- ui.setCustomState("fadeCamera", nil)
            -- ui.setCustomState("viewLocked", nil)

        end)
    else
        hands.setAutoCreateHands(false)
        ik.setAutoCreateArms(false)
        hands.destroyHands()
        ik.destroyAll()
        input.setDisabled(true)
        -- ui.setCustomState("fadeCamera", true, 2)
        -- ui.setCustomState("viewLocked", true, 2)
    end
end

local playState = {} --dont use status because we need this to persist when cleanup() is called
local function checkPlayState()
    local isPlaying = uevr.api:get_player_controller(0) ~= nil and uevr.api:get_player_controller(0).StateName:to_string() == "Playing"
    if playState.isPlaying ~= isPlaying then
        playState.isPlaying = isPlaying
        onPlayStateChanged(isPlaying)
    end
end

-- The game fades its 2D view to and from black (leaving the main menu, the start of cutscenes) while the controller
-- stays Playing, by animating the alpha of an Image named Fade in its root layout (WBP_SlasherGameLayout_C's FadeIn and
-- FadeOut animations). In VR that image only covers the UI, leaving the world around it visible, so the camera fade
-- follows its alpha. ui.lua's own camera fade (the fadeCamera state, set while not Playing) takes precedence.
-- The image itself is hidden (RenderOpacity 0; the animations drive its ColorAndOpacity, which is still read), so only
-- the camera fade shows. The camera fade blends the scene in linear color before tonemapping, so the same amount looks
-- much lighter than the image's on-screen blend (at 0.65 the world stayed bright); the image's remaining brightness is
-- raised to LAYOUT_FADE_GAMMA to compensate (tuned by eye).
local LAYOUT_FADE_MIN_ALPHA = 0.01 -- the image idles just above 0 during gameplay
local LAYOUT_FADE_GAMMA = 15
local layoutFade = {} -- dont use status because we need this to persist when cleanup() is called

local function getLayout()
    local layout = uevrUtils.getValid(layoutFade.layout)
    if layout == nil then
        layout = uevrUtils.find_first_instance("WidgetBlueprintGeneratedClass /Game/SLASHER/Blueprints/UI/WBP_SlasherGameLayout.WBP_SlasherGameLayout_C", false)
        layoutFade.layout = layout
    end
    return layout
end

-- The image isn't a property of the layout, so it is found once by name among its widget tree's objects.
local function getLayoutFadeImage(layout)
    local image = uevrUtils.getValid(layoutFade.image)
    if image ~= nil then return image end
    layoutFade.image = nil
    local tree = uevrUtils.getValid(layout, {"WidgetTree"})
    if tree == nil or tree:get_address() == layoutFade.searchedTree then return nil end
    layoutFade.searchedTree = tree:get_address()
    for _, candidate in ipairs(uevrUtils.find_all_of("Class /Script/UMG.Image", false) or {}) do
        local outer = candidate:get_outer()
        if outer ~= nil and outer:get_address() == layoutFade.searchedTree and candidate:get_fname():to_string() == "Fade" then
            layoutFade.image = candidate
            return candidate
        end
    end
    return nil
end

-- The loading screen is a page of the layout's switcher, not a top-level widget. Once the level has loaded behind it
-- (the controller is Playing again while it waits for Press to Start), the world shows around it in VR.
local function isLoadingScreenActive(layout)
    local switcher = uevrUtils.getValid(layout, {"GameLayoutSwitcher"})
    local loadingScreen = uevrUtils.getValid(layout, {"LoadingScreen"})
    if switcher == nil or loadingScreen == nil then return false end
    local active = switcher:GetActiveWidget()
    return active ~= nil and active:get_address() == loadingScreen:get_address()
end

local function updateLayoutFade()
    local layout = getLayout()
    local image = getLayoutFadeImage(layout)
    if image ~= nil and image.RenderOpacity ~= 0 then image:SetRenderOpacity(0) end
    if ui.isFadeCameraEnabled() then
        layoutFade.alpha = nil -- reapply once ui.lua's fade ends
        return
    end
    local alpha = image ~= nil and image.ColorAndOpacity.A or 0
    if alpha < LAYOUT_FADE_MIN_ALPHA then alpha = 0 end
    local isLoadingScreen = isLoadingScreenActive(layout)
    ui.setCustomState("viewLocked", isLoadingScreen == true and true or nil, 2)
    if isLoadingScreen then alpha = 1 end
    local cameraManager = uevrUtils.getValid(uevr.api:get_player_controller(0), {"PlayerCameraManager"})
    if cameraManager == nil then return end
    -- A new camera manager (after a level load) starts without the fade, so it gets the current alpha too.
    if alpha == layoutFade.alpha and cameraManager:get_address() == layoutFade.cameraManager then return end
    if alpha == 0 then
        cameraManager:StopCameraFade()
    else
        cameraManager:SetManualCameraFade(1 - (1 - alpha) ^ LAYOUT_FADE_GAMMA, color_from_rgba(0.0, 0.0, 0.0, 1.0, true), false)
    end
    layoutFade.alpha = alpha
    layoutFade.cameraManager = cameraManager:get_address()
end

-- The layout outlives the scripts, so the game's own fade image is shown again when they reload or unload.
uevr.params.sdk.callbacks.on_script_reset(function()
    local image = uevrUtils.getValid(layoutFade.image)
    if image ~= nil then image:SetRenderOpacity(1) end
end)

uevrUtils.registerUEVRCallback("ui_state_change_remapEnabled", function(state, priority)
    print("Remap enabled changed to " .. tostring(state) .. " with priority " .. tostring(priority))
    local cursorWidgetList = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/SLASHER/Blueprints/UI/InGameOverlay/Crosshair/WBP_CrossHair_01.WBP_CrossHair_01_C", false)
    if cursorWidgetList ~= nil then
        for i, widget in ipairs(cursorWidgetList) do
            if widget.CenterDot ~= nil then
                widget.CenterDot:SetVisibility(state == false and 0 or 1)
            end
        end
    end
end)

uevrUtils.registerUEVRCallback("widget_change_WBP_MainMenu_C", function(isInViewport)
    if isInViewport and not uevrUtils.isGamePaused() then
        uevrUtils.setUEVRParam("VR_CameraForwardOffset", 350)
        input.setDisabled(true)
        delay(500, function()
            status.wasRemapDisabled = nil
        end)
    else
        uevrUtils.setUEVRParam("VR_CameraForwardOffset", 0)
        input.setDisabled(false)
    end
end)

uevrUtils.registerUEVRCallback("widget_change_WBP_CharacterScreen_C", function(isInViewport)
    if not isInViewport then
        hands.destroyHands()
        ik.destroyAll()
    end
end)


local function setOverlayScale()
    local widget = uevrUtils.find_first_instance("WidgetBlueprintGeneratedClass /Game/SLASHER/Blueprints/UI/WBP_SlasherGameLayout.WBP_SlasherGameLayout_C", false)
    if widget ~= nil then
        print("Changing main widget layout")
        local customScale = uevrUtils.getNativeValue(configui.getValue("overlay_scale"))
        customScale = {X = customScale[1], Y = customScale[2]}
        uevrUtils.setWidgetLayout(widget, status.isInInteractiveUI and {1.0, 1.0} or {customScale.X, customScale.Y}, status.isInInteractiveUI and {0.0, 0.0} or {1 - customScale.X, 1 - customScale.Y})
    end
end

-- Draws the game's arrow at the mouse position while the controller mouse is active, because the
-- game's cursor doesn't show during VR controller play. This is our own copy of the cursor widget,
-- whose class is always loaded. It fills the viewport with the arrow anchored at its center, which
-- makes the translation relative to the viewport center.
local function updateCursorIndicator(isControllerMouseActive)
    local widget = status.cursorWidget
    if not isControllerMouseActive then
        if widget ~= nil and uevrUtils.getValid(widget) ~= nil then
            widget:RemoveFromParent()
        end
        status.cursorWidget = nil
        return
    end

    if widget == nil or uevrUtils.getValid(widget) == nil then
        widget = uevrUtils.createWidget("WidgetBlueprintGeneratedClass /Game/SLASHER/Blueprints/UI/Inventory/WBP_DefaultCursor.WBP_DefaultCursor_C")
        if widget == nil or uevrUtils.getValid(widget, {"UICrosshair", "CenterDot"}) == nil then
            status.cursorWidget = nil
            return
        end
        widget:SetVisibility(3) -- HitTestInvisible
        widget:AddToViewport(10000)
        -- A new copy starts with the crosshair's interaction prompt showing, so leave only the arrow
        widget.UICrosshair.CenterDot:SetVisibility(0)
        widget.UICrosshair.InteractionContextScrollBox:SetVisibility(1)
        widget.UICrosshair.ObjectName_Overlay:SetVisibility(1)
        status.cursorWidget = widget
    end

    if widget == nil or WidgetLayoutLibrary == nil then return end
    local world = uevrUtils.getWorld()
    local mousePosition = WidgetLayoutLibrary:GetMousePositionOnViewport(world)
    local viewportSize = WidgetLayoutLibrary:GetViewportSize(world)
    local viewportScale = WidgetLayoutLibrary:GetViewportScale(world)
    if mousePosition ~= nil and viewportSize ~= nil and viewportScale ~= nil and viewportScale > 0 then
        widget:SetRenderTranslation(uevrUtils.vector_2(mousePosition.X - viewportSize.X / 2 / viewportScale, mousePosition.Y - viewportSize.Y / 2 / viewportScale, true))
    end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    checkPlayState()
    updateLayoutFade()
    melee.update(pawnModule.getPawn() or uevr.api:get_local_pawn(0),
        attachments.getCurrentGrippedAttachment(Handed.Right), delta,
        attachments.isActiveAttachmentMelee(Handed.Right) and not ui.isRemapDisabled())
    --the game somehow messes with the poseable mesh's root bone rotation after an animation, possiblly
    --because it has a shared skeleton with the source skeletal mesh component, so this compensates 
    --for that by resetting it every tick
    hands.setRootBoneRotation(uevrUtils.rotator(0, 180, 0))
    ik.setRootBoneRotation(uevrUtils.rotator(0, 0, 0))

    -- When paused or in main menu, the right controller controls the mouse cursor
    local isInInteractiveUI = ui.isRemapDisabled()
    if status.isInInteractiveUI ~= isInInteractiveUI then
        status.isInInteractiveUI = isInInteractiveUI
        --mouse.enable(isInInteractiveUI)
        setOverlayScale()
    end
    updateCursorIndicator(ui.isControllerMouseEnabledWithPriority() == true)
end)

-- uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
--     if uevrUtils.getValid(pawn,{"Mesh"}) ~= nil then
--         if status.isPlayingAttackMontage then
--             local controllerRotation = controllers.getControllerRotation(Handed.Right)
--             local rootRotation = pawn.RootComponent:K2_GetComponentRotation()
--             if controllerRotation ~= nil then
--                 local hitOffset = configui.getValue("hit_offset")
--                 if hitOffset ~= nil then
--                     pawn.Mesh.RelativeRotation.Pitch = -mathLib.normalizeDeg180((-controllerRotation.Pitch + hitOffset.X))
--                     pawn.Mesh.RelativeRotation.Yaw = controllerRotation.Yaw - rootRotation.Yaw - 90 + hitOffset.Y --+ offset.Pitch
--                     pawn.Mesh.RelativeRotation.Roll = hitOffset.Z ---controllerRotation.Pitch - 60
--                 end
--             end
--         else--if not status.isPlayingCinematicMontage then
--             pawn.Mesh.RelativeRotation.Pitch = 0
--             pawn.Mesh.RelativeRotation.Yaw = -90
--             pawn.Mesh.RelativeRotation.Roll = 10
--         end

--         --pawn.AttributeComponent:FullHealAllResources()
--     end
-- end)

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
    if uevrUtils.getValid(pawn,{"Mesh"}) ~= nil then
        pawn.Mesh.RelativeRotation.Pitch = 0
        pawn.Mesh.RelativeRotation.Yaw = -90
        -- The cutscene camera hangs off the mesh's CameraSpine bone, so the VR body roll would tilt it.
        --pawn.Mesh.RelativeRotation.Roll = input.isDisabled() and 0 or 10
        pawn.Mesh.RelativeRotation.Roll = status.isPlayingCinematicMontage and 0 or 15
    end
end)

configui.onCreateOrUpdate("physical_item_grab", function(value)
    interactions.setItemGrabEnabled(value)
end)

configui.onCreateOrUpdate("grab_toggle_grip", function(value)
    interactions.setGrabToggleGrip(value)
end)

configui.onUpdate("hands_type", function(value)
    regenerateHands(value)
end)

configui.onCreateOrUpdate("control_rotation_type", function(value)
    configui.setHidden("control_rotation", value ~= 2)
end)

configui.onCreateOrUpdate("camera_rotation_type", function(value)
    configui.setHidden("camera_rotation", value ~= 2)
end)

configui.onCreateOrUpdate("vr_camera_rotation_type", function(value)
    configui.setHidden("vr_camera_rotation_offset", value ~= 2)
end)

configui.onCreateOrUpdate("overlay_scale", function(value)
    setOverlayScale()
end)

configui.onCreateOrUpdate("left_hand_palm_aim", function(value)
    configui.setHidden("palm_aim_offset", value ~= true)
end)

configui.create(configDefinition)


setInterval(1000, updateScreenWidgets)

uevr.params.sdk.callbacks.on_script_reset(function()
	cleanup()
end)

-- local isPaused = false
-- register_key_bind("F2", function()
--     isPaused = not isPaused
-- 	uevrUtils.pauseGame(isPaused)
--     print("Game paused: " .. tostring(isPaused))
-- end)
