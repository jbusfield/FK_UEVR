local uevrUtils = require('libs/uevr_utils')
local native = require('helpers/melee/native')
local sweep = require('helpers/melee/sweep')

-- Gesture callbacks own the hit window. update() retains pose history every
-- frame and queries contacts only inside that window.
local M = {}
local currentLogLevel = LogLevel.Error

function M.setLogLevel(val)
    currentLogLevel = val
end

function M.print(text, logLevel)
    if logLevel == nil then logLevel = LogLevel.Debug end
    if logLevel <= currentLogLevel then
        uevrUtils.print('[melee] ' .. text, logLevel)
    end
end

local MAX_FRAME_DELTA = 0.1 -- Seconds; skip stalled frames.
local MAX_TRACKING_JUMP = 50 -- Unreal units (cm) per frame.
local MAX_TRACKING_JUMP_SQUARED = MAX_TRACKING_JUMP * MAX_TRACKING_JUMP
local HIT_COOLDOWN = 1.00 -- Seconds between separate swings against one actor.
local HAPTIC_DURATION = 0.15 -- Seconds
local HAPTIC_FREQUENCY = 1000.0 -- Hertz
local HAPTIC_AMPLITUDE = 1.0 -- 0.0 to 1.0

local state = {
    elapsed = 0,
    windowOpen = false,
    heavyHeld = false,
    swingHeavy = false,
    hitActors = {},
    lastHitTimes = {},
}

function M.setHeavyInput(pressed)
    state.heavyHeld = pressed == true
end

function M.beginSwing()
    if state.windowOpen then
        return
    end
    state.windowOpen = true
    state.swingHeavy = state.heavyHeld
    state.hitActors = {}
end

function M.endSwing()
    state.windowOpen = false
    state.swingHeavy = false
end

function M.finish()
    sweep.releaseHandles()
    native.resetWeaponCache()
    state.previousPose, state.previousPawn, state.weaponKey = nil, nil, nil
    state.windowOpen, state.heavyHeld, state.swingHeavy = false, false, false
    state.hitActors, state.lastHitTimes = {}, {}
end

function M.resetWeapon()
    state.failedWeaponKey = nil
    sweep.resetWeapon()
    M.finish()
end

local function update(player, weapon, deltaTime, enabled)
    if not enabled or not uevrUtils.getValid(player) or not uevrUtils.getValid(weapon)
        or type(deltaTime) ~= 'number' or deltaTime <= 0 or deltaTime > MAX_FRAME_DELTA then
        M.finish()
        return true
    end

    local world = uevrUtils.getWorld()
    local asset = uevrUtils.getValid(weapon.StaticMesh)
    if not world or not asset then
        M.finish()
        return true
    end

    local key = table.concat({
        player:get_address(), world:get_address(), weapon:get_address(), asset:get_address(),
    }, ':')
    if state.failedWeaponKey == key then
        return true
    end
    if state.weaponKey ~= key then
        -- A first pose can arrive after gesture begin. Only an actual weapon,
        -- pawn, or world change cancels the window.
        if state.weaponKey then
            M.finish()
        end
        state.weaponKey, state.failedWeaponKey = key, nil
    end

    local geometry, err = sweep.getGeometry(player, asset)
    if not geometry then
        return false, err
    end
    local currentPose
    currentPose, err = sweep.getPose(weapon, geometry)
    if not currentPose then
        return false, err
    end
    local location = player:K2_GetActorLocation()
    if location == nil then
        return false, 'pawn location unavailable'
    end
    local currentPawn = {X = location.X, Y = location.Y, Z = location.Z}
    state.elapsed = state.elapsed + deltaTime

    local previousPose, previousPawn = state.previousPose, state.previousPawn
    state.previousPose, state.previousPawn = currentPose, currentPawn
    if not previousPose then
        return true
    end

    if state.windowOpen then
        local pawnDx = currentPawn.X - previousPawn.X
        local pawnDy = currentPawn.Y - previousPawn.Y
        local pawnDz = currentPawn.Z - previousPawn.Z
        local weaponDx = currentPose.center.X - previousPose.center.X - pawnDx
        local weaponDy = currentPose.center.Y - previousPose.center.Y - pawnDy
        local weaponDz = currentPose.center.Z - previousPose.center.Z - pawnDz
        -- Skip discontinuous tracking without closing the window or clearing hits.
        if pawnDx * pawnDx + pawnDy * pawnDy + pawnDz * pawnDz > MAX_TRACKING_JUMP_SQUARED
            or weaponDx * weaponDx + weaponDy * weaponDy + weaponDz * weaponDz > MAX_TRACKING_JUMP_SQUARED then
            return true
        end
        local contacts
        contacts, err = sweep.collectContacts(player, previousPose, currentPose, deltaTime)
        if not contacts then
            return false, err
        end
        for address, contact in pairs(contacts) do
            local lastHit = state.lastHitTimes[address]
            if not state.hitActors[address] and (not lastHit or state.elapsed - lastHit >= HIT_COOLDOWN) then
                -- Record before Impact: native callbacks can run during the call.
                state.hitActors[address] = true
                state.lastHitTimes[address] = state.elapsed
                contact.heavy = state.swingHeavy
                local result, hitError = native.applyHit(contact)
                if not result then
                    return false, hitError
                end
                uevrUtils.triggerHapticVibration(Handed.Right, 0, HAPTIC_DURATION * (contact.heavy and 1.8 or 1.0), HAPTIC_FREQUENCY, HAPTIC_AMPLITUDE)
            end
        end
    end
    return true
end

function M.update(player, weapon, deltaTime, enabled)
    -- Expected failures arrive as return values. The boundary catch is only
    -- for unexpected exceptions from third-party Lua or engine bindings.
    local completed, ok, err = pcall(update, player, weapon, deltaTime, enabled)
    -- Runs after success, expected failures, and binding exceptions. Cooldown
    -- skips and duplicate contacts leave native array elements to release here.
    sweep.releaseHandles()
    if not completed then
        err, ok = ok, false
    end
    if not ok then
        state.failedWeaponKey = state.weaponKey
        M.finish()
        M.print('paused for this weapon: ' .. tostring(err), LogLevel.Error)
    end
    return ok, err
end
M.update = uevrUtils.profiler:wrap('melee.update', M.update)

return M
