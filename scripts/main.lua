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
local tArray = require("libs/core/tarray")
local keyboard = require("libs/keyboard")

--uevrUtils.setLogLevel(LogLevel.Debug)
--attachments.setLogLevel(LogLevel.Debug)
--input.setLogLevel(LogLevel.Debug)


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

uevrUtils.set_decoupled_pitch_adjust_ui(false)
local inputSettings = uevrUtils.find_default_instance("Class /Script/Engine.InputSettings")

local status = {}

local HandsType = {
	None = 0,
	Forearms = 1,
	IKArms = 2,
	-- None = 1,
	-- Forearms = 2,
	-- IKArms = 3,
}

local versionTxt = "v1.0.0"
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
                    widgetType = "drag_float3",
                    id = "hit_offset",
                    label = "Hit Offset",
                    speed = 1,
                    range = {-360, 360},
                    initialValue = {0,0,0},
                    isHidden = true,
                },
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
				{ widgetType = "text", wrapped = true, label = "Cast Spell: Left Grip", },
				{ widgetType = "text", wrapped = true, label = "Run: Left Stick press down (toggles run)", },
				{ widgetType = "text", wrapped = true, label = "Jump: Right Stick Forward", },
				{ widgetType = "text", wrapped = true, label = "Dodge: Right Stick Backward", },
				{ widgetType = "text", wrapped = true, label = "Pick up/Interact: A button", },
				{ widgetType = "text", wrapped = true, label = "Cancel/Exit: B button", },
				{ widgetType = "text", wrapped = true, label = "Change Weapon: X button OR Right Trigger with your hand over your right shoulder", },
				{ widgetType = "text", wrapped = true, label = "Change Spell: Y button", },
				{ widgetType = "text", wrapped = true, label = "Torch: Long press X button", },
				{ widgetType = "text", wrapped = true, label = "Use Slot Items: D-Pad + Left Stick Up/Down/Left/Right", },
				{ widgetType = "text", wrapped = true, label = "Use Slot 1 specifically: Left Trigger near mouth", },
				{ widgetType = "text", wrapped = true, label = "Menu: Press left Menu button", },
				{ widgetType = "text", wrapped = true, label = "Inventory: Hold left Menu button (2 seconds) OR Light Trigger with your hand over your left shoulder", },
				{ widgetType = "text", wrapped = true, label = "Interact with overlay screens: Right Trigger", },
				{ widgetType = "text", wrapped = true, label = "H key in overlay screens: DPad + Left Stick Down", },
                {widgetType = "unindent", width = 10 },
            { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
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
    if status.currentWeapon ~= nil and uevrUtils.getValid(status.currentWeapon) ~= nil and status.currentWeapon.StaticMesh ~= nil and status.currentWeaponStaticMeshName == status.currentWeapon.StaticMesh:get_full_name() then
        return status.currentWeapon
    end

    --print("Switching weapon")
    local pawn = pawnModule.getPawn() or uevr.api:get_local_pawn(0)
    if pawn == nil or pawn.Mesh == nil or pawn.Mesh.AttachChildren == nil then
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
                pawn.EquipmentComponent.CurrentWeaponSpeed = 5
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
	return rightHandComponent and weaponMesh, rightHandComponent, weaponAttachSocket, nil, nil, nil, defaultAttachOptions
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
	-- Reduces processing when no melee weapon is equipped
    local isRightMelee = attachments.isActiveAttachmentMelee(Handed.Right)
    local isLeftMelee = attachments.isActiveAttachmentMelee(Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isRightMelee, Handed.Right)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isRightMelee, Handed.Right)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isLeftMelee, Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isLeftMelee, Handed.Left)

    if status.currentWeapon ~= nil then
        status.currentWeapon:SetVisibility(true, false)
    end
end)

local function setDefaultTargeting(handed, offset)
	if handed == Handed.Left then
		input.setAimMethod(input.AimMethod.LEFT_CONTROLLER)
        input.setAimRotationOffset({Pitch=0, Yaw=60, Roll=0})
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

gestures.registerSwipeRightCallback(function(strength, hand)
	--print("Swipe Right detected for right hand")
    if hand == Handed.Right then
    	status["hasSwipeRight"] = true
        setDefaultTargeting(Handed.Right)
        setMeleeOffset(Handed.Right)
    else
        status["hasSwipeLeft"] = true
        setDefaultTargeting(Handed.Left)
        setMeleeOffset(Handed.Left)
    end
end, true, true)

gestures.registerSwipeLeftCallback(function(strength, hand)
	--print("Swipe Left detected for right hand")
    if hand == Handed.Right then
    	status["hasSwipeRight"] = true
        setDefaultTargeting(Handed.Right)
        setMeleeOffset(Handed.Right)
    else
        status["hasSwipeLeft"] = true
        setDefaultTargeting(Handed.Left)
        setMeleeOffset(Handed.Left)
    end
end, true, true)

local function executeIsArmBonesHiddenCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_arms_bones_hidden", table.unpack({...}))
end

--if montages chose to show th arm bones then show the head bone too
local function checkBonesHidden()
	if uevrUtils.getValid(pawn) == nil then return end
	local isHidden, priority = executeIsArmBonesHiddenCallback()
	if isHidden == false then
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
    --AM_Hero_Cinematic_FirstRuneDeviceInteraction = true,
    --AM_Hero_Cinematic_TutorialPostPortal = true,
    AM_Hero_EAIntroductionDialogue = true
}
montage.registerMontageChangeCallback(function(montageObject, montageName, label)
	--print("Montage changed callback:", montageName, label)
	if montageName ~= "" and label == "Pawn" then
		local knownAttackMontage = attackMontages[montageName]
		if knownAttackMontage == true then
            --print("Known attack montage detected, increasing playback rate")
			montage.setPlaybackRate(montageObject, label, 3.0)
            if pawn ~= nil then
                pawn.Mesh.GlobalAnimRateScale = 2
                status.isPlayingAttackMontage = true
            end
		end

        local knownCinematicMontage = cinematicMontages[montageName]
		if knownCinematicMontage == true then
            --print("Known cinematic montage detected")
            uevrUtils.setUEVRParam("VR_CameraForwardOffset", -15)
            uevrUtils.setUEVRParam("VR_CameraUpOffset", 20)
            status.isPlayingCinematicMontage = true
		end
	end
    if (montageName == nil or montageName == "") then
        if status.isPlayingAttackMontage == true then
            if pawn ~= nil then
                pawn.Mesh.GlobalAnimRateScale = 1
            end
        end
        status.isPlayingAttackMontage = false

        if status.isPlayingCinematicMontage == true then
            uevrUtils.setUEVRParam("VR_CameraForwardOffset", 0)
            uevrUtils.setUEVRParam("VR_CameraUpOffset", 0)
        end
        status.isPlayingCinematicMontage = false
    end

    -- if montageName contains "_Unequip" then hide the equipped weapon
    -- makes the transition look nicer
    if montageName ~= "" and montageName:find("_Equip", 1, true) then
        --print("Unequip montage detected, hiding weapon")
        if status.currentWeapon ~= nil then
            status.currentWeapon:SetVisibility(false, false)
        end
    end

    checkBonesHidden()
end)

local inputMappings = {}
local inputMappingLookup = {
    LeftMouseButton = "LCLICK",
    RightMouseButton = "RCLICK",
    LeftAlt = "ALT",
    RightAlt = "ALT",
    One = "1",
    Two = "2",
    Three = "3",
    Four = "4",
    Five = "5",
    Six = "6",
    Seven = "7",
    Eight = "8",
    Nine = "9",
    Zero = "0",
}

local function getInputMapping(actionName)
    return inputMappings[actionName]
end
local function initializeInputMappings()
    inputMappings = {}
    --print("Initializing input mappings", inputSettings)
    if inputSettings ~= nil then
        tArray.registerCallback(function(mappings)
            --print("Received input mappings callback with mappings:", mappings)
            for i, mappingData in ipairs(mappings) do
                for key, value in pairs(mappingData) do
                    if not mappingData["Key"]:match("^Gamepad_") then
                        --print("Mapping found for key:", mappingData["KeyName"], mappingData["Key"])
                        inputMappings[mappingData["KeyName"]] = inputMappingLookup[mappingData["Key"]]
                        if inputMappings[mappingData["KeyName"]] == nil then
                            inputMappings[mappingData["KeyName"]] = mappingData["Key"]
                        end
                    end
                end
            end
        end, "FInputActionKeyMapping", inputSettings, "ActionMappings")
    end
end

local STICK_DEADZONE = 22000
local TOGGLE_SPRINT = true
local LONG_PRESS_SECONDS = 0.35
local xInputStatus = {}
uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)

    local handed = Handed.Right
	local isEating, isGrabbingGlasses, gripHead, isGrabbingEar, triggerMouth, isScratchingEyes, triggerHead, isScratchingEar = gestures.getHeadGestures(state, 1-handed, false)
	local isEatingRight, isGrabbingGlassesRight, gripHeadRight, isGrabbingEarRight, triggerMouthRight, isScratchingEyesRight, triggerHeadRight, isScratchingEarRight = gestures.getHeadGestures(state, handed, false)

    keyboard.updateToggleState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_START), "ESC") --menu
    keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_BACK), "TAB") --inventory
    keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_A), getInputMapping("Interact") or "E") --use

    if ui.isRemapDisabled() == true then
        --keyboard.updateShortLongButtonState(false, "C", "T", "switchWeaponsButton", LONG_PRESS_SECONDS)
        keyboard.updateToggleState(state.Gamepad.bRightTrigger > 0, "LCLICK") -- right trigger simulates mouse clicks
        keyboard.updateToggleState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER), "1") -- category left
        keyboard.updateToggleState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER), "3") -- category right
        keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_B), "SPACE") --esc in splash screens
        keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_B), "ESC")
        keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_B), "TAB")
        keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_DPAD_DOWN), "H") --use H
        keyboard.updateShortLongButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_X), "C", "T", "switchWeaponsButton", LONG_PRESS_SECONDS) --switch weapons

        if xInputStatus.isScratchingEar ~= isScratchingEar then
            print("Grabbing left ear detected", isScratchingEar)
            if isScratchingEar == true then
                keyboard.setInput("KeyPress", "TAB")
            end
            xInputStatus.isScratchingEar = isScratchingEar
        end

        --dont let the right stick control the mouse when the interactive UI is showing
        state.Gamepad.sThumbRX = 0
        return
    end

    if xInputStatus.isScratchingEar ~= isScratchingEar then
        print("Grabbing left ear detected", isScratchingEar)
        if isScratchingEar == true then
            keyboard.setInput("KeyPress", "TAB")
        end
        xInputStatus.isScratchingEar = isScratchingEar
    end

    if xInputStatus.isScratchingEarRight ~= isScratchingEarRight then
        print("Grabbing right ear detected", isScratchingEarRight)
        if isScratchingEarRight == true then
            keyboard.setInput("KeyPress", "C")
        end
        xInputStatus.isScratchingEarRight = isScratchingEarRight
    end

    -- if isGrabbingEarRight then
    --     print("Grabbing right ear detected")
    --     --xInputStatus.isGrabbingEar = true
    --     SetInput("KeyPress", "C")
    -- end

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

    local canSprint = true
    if state.Gamepad.sThumbLY > -8000 and state.Gamepad.sThumbLY < 8000 then
        if xInputStatus.isSprinting then
            keyboard.setInput("KeyUp", "SHIFT")
        end
        xInputStatus.isSprinting = false
        canSprint = false
    end

    if canSprint then
        if TOGGLE_SPRINT then
            if isLeftStickPressed and not xInputStatus.triggerWasPressed then
                xInputStatus.isSprinting = not xInputStatus.isSprinting
            end
        else
            xInputStatus.isSprinting = isLeftStickPressed
        end
        if xInputStatus.triggerWasPressed ~= isLeftStickPressed then
            if xInputStatus.isSprinting then
                keyboard.setInput("KeyDown", "SHIFT")
            else
                keyboard.setInput("KeyUp", "SHIFT")
            end
        end
        xInputStatus.triggerWasPressed = isLeftStickPressed
    end

    keyboard.updateToggleState(state.Gamepad.sThumbLY > 20000, "W") -- forward
    keyboard.updateToggleState(state.Gamepad.sThumbLY < -20000, "S") -- backward
    keyboard.updateToggleState(state.Gamepad.sThumbLX < -20000, "A") -- left
    keyboard.updateToggleState(state.Gamepad.sThumbLX > 20000, "D") -- right
    keyboard.updateToggleState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER), getInputMapping("CastSpell") or "Q") -- cast spells
    keyboard.updateToggleState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER), getInputMapping("bLock") or "R") -- block/parry
    keyboard.updateShortLongButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_X), "C", "T", "switchWeaponsButton", LONG_PRESS_SECONDS) --switch weapons
    keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_Y), "X") --change spell
    keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_DPAD_UP), getInputMapping("QuickbarOne") or "1") --use 1
    keyboard.updateButtonState(triggerMouth, getInputMapping("QuickbarOne") or "1") --use 1  
    keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_DPAD_DOWN), getInputMapping("QuickbarFour") or "4") --use 4
    keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_DPAD_LEFT), getInputMapping("QuickbarTwo") or "2") --use 2
    keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_DPAD_RIGHT), getInputMapping("QuickbarThree") or "3") --use 3
    keyboard.updateButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_THUMB), getInputMapping("SecondaryInteract") or "F") --kick
    keyboard.updateButtonState(isRightStickDown, getInputMapping("Dodge") or "ALT") --Dodge
    keyboard.updateButtonState(isRightStickUp, "SPACE") --Jump

    --keyboard.updateButtonState(isPressingRightTrigger, "LCLICK")

    state.Gamepad.bRightTrigger = 0
    if uevrUtils.isButtonPressed(state,XINPUT_GAMEPAD_A) then
        setDefaultTargeting(Handed.Right)
    else
        if isPressingRightTrigger or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER) then
            setDefaultTargeting(Handed.Right)
        elseif isPressingLeftTrigger or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER) then
            setDefaultTargeting(Handed.Left)
        end
    end

    if status["hasSwipeRight"] then
        --print("Processing right swipe gesture into input")
        if isPressingRightTrigger then
            state.Gamepad.bRightTrigger = 0
            keyboard.setInput("KeyPress", getInputMapping("SecondaryAction") or "RCLICK")
        else
            keyboard.setInput("KeyPress", getInputMapping("PrimaryAction") or "LCLICK")
        end
        status["hasSwipeRight"] = false
    end
	if status["hasSwipeLeft"] then
        --print("Processing left swipe gesture into input")
        if isPressingRightTrigger then
            state.Gamepad.bRightTrigger = 0
            keyboard.setInput("KeyPress", getInputMapping("SecondaryAction") or "RCLICK")
        else
            keyboard.setInput("KeyPress", getInputMapping("PrimaryAction") or "LCLICK")
        end
        status["hasSwipeLeft"] = false
    end

end, 5) --increased priority to get values before remap occurs

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
            initializeInputMappings()
            ui.setCustomState("fadeCamera", nil)
            ui.setCustomState("viewLocked", nil)

        end)
    else
        hands.setAutoCreateHands(false)
        ik.setAutoCreateArms(false)
        hands.destroyHands()
        ik.destroyAll()
        input.setDisabled(true)
        ui.setCustomState("fadeCamera", true, 2)
        ui.setCustomState("viewLocked", true, 2)
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

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    checkPlayState()
    --the game somehow messes with the poseable mesh's root bone rotation after an animation, possiblly
    --because it has a shared skeleton with the source skeletal mesh component, so this compensates 
    --for that by resetting it every tick
    hands.setRootBoneRotation(uevrUtils.rotator(0, 180, 0))
    ik.setRootBoneRotation(uevrUtils.rotator(0, 0, 0))

    -- When paused or in main menu, the right controller controls the mouse cursor
    local isInInteractiveUI = ui.isRemapDisabled()
    if status.isInInteractiveUI ~= isInInteractiveUI then
        status.isInInteractiveUI = isInInteractiveUI
        mouse.enable(isInInteractiveUI)
        setOverlayScale()
    end
end)

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
    if uevrUtils.getValid(pawn,{"Mesh"}) ~= nil then
        if status.isPlayingAttackMontage then
            local controllerRotation = controllers.getControllerRotation(Handed.Right)
            local rootRotation = pawn.RootComponent:K2_GetComponentRotation()
            if controllerRotation ~= nil then
                local hitOffset = configui.getValue("hit_offset")
                if hitOffset ~= nil then
                    pawn.Mesh.RelativeRotation.Pitch = -mathLib.normalizeDeg180((-controllerRotation.Pitch + hitOffset.X))
                    pawn.Mesh.RelativeRotation.Yaw = controllerRotation.Yaw - rootRotation.Yaw - 90 + hitOffset.Y --+ offset.Pitch
                    pawn.Mesh.RelativeRotation.Roll = hitOffset.Z ---controllerRotation.Pitch - 60
                end
            end
        else--if not status.isPlayingCinematicMontage then
            pawn.Mesh.RelativeRotation.Pitch = 0
            pawn.Mesh.RelativeRotation.Yaw = -90
            pawn.Mesh.RelativeRotation.Roll = 10
        end

        --pawn.AttributeComponent:FullHealAllResources()
    end
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

configui.create(configDefinition)

local function getTopLevelWidgetsOnScreen(widgetNames)
    local result = {}

    local gameInstance = Statics:GetGameInstance(uevrUtils.getWorld())
    if gameInstance ~= nil and gameInstance.GameLayout ~= nil then
         local layout = gameInstance.GameLayout
        for _, widgetName in pairs(widgetNames) do
            local widget = layout[widgetName]
             if widget ~= nil and ((widget:IsVisible() and widget.WidgetTree.RootWidget:GetVisibility() == 0) or (widget:IsVisible() and widget:GetVisibility() == 4 and widget.WidgetTree.RootWidget:GetVisibility() == 4)) then
                table.insert(result, {name = widgetName, widget = widget})
            end
        end
     end
    return result
end

local screenWidgets = {}
setInterval(2000, function()
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

end)

