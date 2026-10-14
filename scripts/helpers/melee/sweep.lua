local uevrUtils = require('libs/uevr_utils')
local plugin = require('libs/core/plugin')
local native = require('helpers/melee/native')

-- Sweep the authored weapon box in world space. Contact velocity includes
-- translation and rotation so Impact can choose the appropriate reaction.
local M = {}
local BOX_SHAPE_TYPE = 3
local ANGULAR_STEP = math.rad(12)
local MAX_SUBSTEPS = 4
local MAX_HALF_EXTENT_LENGTH = 500 -- Unreal units (cm).
local AXIS_EPSILON = 0.00001
local IDENTITY = {
    Rotation = {X = 0, Y = 0, Z = 0, W = 1},
    Translation = {X = 0, Y = 0, Z = 0},
    Scale3D = {X = 1, Y = 1, Z = 1},
}

local geometryKey, geometry
local systemLibrary, abilityLibrary, mathLibrary
local rotationArgument
local pendingHandles = {}
local TRACE_OUTPUTS = {
    'OutHits.Component', 'OutHits.BoneName', 'OutHits.ImpactPoint', 'OutHits.Time',
}

-- Contacts borrow an element of these native arrays for this frame only.
-- The same registry also owns any generated hit handles until Impact takes them.
function M.releaseHandles()
    for handle in pairs(pendingHandles) do
        pendingHandles[handle] = nil
        plugin.releaseHandle(handle)
    end
end
M.releaseHandles = uevrUtils.profiler:wrap('melee.sweep.releaseHandles', M.releaseHandles)

-- Bridge structs are decoded into Lua values. Reject incomplete coordinates
-- before using them in sweep calculations or passing them back to Unreal.
local function isVector(value)
    return value ~= nil and (type(value) == 'table' or type(value) == 'userdata')
        and type(value.X) == 'number' and type(value.Y) == 'number' and type(value.Z) == 'number'
end

local function isQuaternion(value)
    return isVector(value) and type(value.W) == 'number'
end

local function add(a, b)
    return {X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z}
end

local function subtract(a, b)
    return {X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z}
end

local function scale(vector, factor)
    return {X = vector.X * factor, Y = vector.Y * factor, Z = vector.Z * factor}
end

local function dot(a, b)
    return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

local function cross(a, b)
    return {
        X = a.Y * b.Z - a.Z * b.Y,
        Y = a.Z * b.X - a.X * b.Z,
        Z = a.X * b.Y - a.Y * b.X,
    }
end

local function length(vector)
    return math.sqrt(dot(vector, vector))
end

local function lerp(a, b, fraction)
    return add(a, scale(subtract(b, a), fraction))
end

local function quaternionDot(a, b)
    return dot(a, b) + a.W * b.W
end

local function quaternionMultiply(a, b)
    local vector = add(add(scale(b, a.W), scale(a, b.W)), cross(a, b))
    return {X = vector.X, Y = vector.Y, Z = vector.Z, W = a.W * b.W - dot(a, b)}
end

local function quaternionBlend(a, b, fraction)
    local sign = quaternionDot(a, b) < 0 and -1 or 1
    local rotation = {
        X = a.X + (sign * b.X - a.X) * fraction,
        Y = a.Y + (sign * b.Y - a.Y) * fraction,
        Z = a.Z + (sign * b.Z - a.Z) * fraction,
        W = a.W + (sign * b.W - a.W) * fraction,
    }
    local norm = math.sqrt(quaternionDot(rotation, rotation))
    return {
        X = rotation.X / norm, Y = rotation.Y / norm,
        Z = rotation.Z / norm, W = rotation.W / norm,
    }
end

local function rotate(vector, rotation)
    local axis = {X = rotation.X, Y = rotation.Y, Z = rotation.Z}
    local perpendicular = scale(cross(axis, vector), 2)
    return add(vector, add(scale(perpendicular, rotation.W), cross(axis, perpendicular)))
end

local function transformPoint(point, transform)
    local scaled = {
        X = point.X * transform.Scale3D.X,
        Y = point.Y * transform.Scale3D.Y,
        Z = point.Z * transform.Scale3D.Z,
    }
    return add(transform.Translation, rotate(scaled, transform.Rotation))
end

local function initializeLibraries()
    if uevrUtils.getValid(systemLibrary) and uevrUtils.getValid(abilityLibrary)
        and uevrUtils.getValid(mathLibrary) and rotationArgument then
        return true
    end
    systemLibrary = uevrUtils.find_default_instance('Class /Script/Engine.KismetSystemLibrary')
    abilityLibrary = uevrUtils.find_default_instance('Class /Script/SLASHER.AbilityFunctionLibrary')
    mathLibrary = uevrUtils.find_default_instance('Class /Script/Engine.KismetMathLibrary')
    if not uevrUtils.getValid(systemLibrary) or not uevrUtils.getValid(abilityLibrary) or not uevrUtils.getValid(mathLibrary) then
        return false, 'box query libraries unavailable'
    end
    -- A private native FQuat avoids JSON marshaling and sharing the library's
    -- reusable struct with other modules during a sweep.
    rotationArgument = uevrUtils.get_struct_object('ScriptStruct /Script/CoreUObject.Quat')
    if not rotationArgument then
        return false, 'native quaternion argument unavailable'
    end
    return true
end
initializeLibraries = uevrUtils.profiler:wrap('melee.sweep.initializeLibraries', initializeLibraries)

local function isBoxType(value, depth)
    if type(value) == 'number' then
        return value == BOX_SHAPE_TYPE
    elseif type(value) == 'string' then
        return value == 'Box' or value:match('[:.]Box$') or tonumber(value) == BOX_SHAPE_TYPE
    elseif type(value) == 'table' and depth < 5 then
        -- Bridge enum results can contain nested property wrappers.
        for key, child in pairs(value) do
            if key ~= 'offset' and key ~= 'size' and key ~= 'address' and isBoxType(child, depth + 1) then
                return true
            end
        end
    end
    return false
end

local function getHalfSize(shape)
    -- The native helper defines axis order and half extents. Supplying only
    -- geometry avoids copying owning containers or native collision caches.
    local result = plugin.executeFunction(abilityLibrary, 'GetBoundingPointsForShape', {
        Type = BOX_SHAPE_TYPE,
        Height = shape.Height, Width = shape.Width, Depth = shape.Depth,
        Radius = shape.Radius, WorldTransform = IDENTITY,
    })
    if result == nil or result.error then
        return nil, result and result.error or 'GetBoundingPointsForShape returned no bridge response'
    end
    local corners = result.ReturnValue
    if type(corners) ~= 'table' or #corners < 8 then
        return nil, 'native box bounding points unavailable'
    end

    local minimum = {X = math.huge, Y = math.huge, Z = math.huge}
    local maximum = {X = -math.huge, Y = -math.huge, Z = -math.huge}
    for _, point in ipairs(corners) do
        if not isVector(point) then
            return nil, 'native box bounding point unavailable'
        end
        for _, axis in ipairs({'X', 'Y', 'Z'}) do
            minimum[axis] = math.min(minimum[axis], point[axis])
            maximum[axis] = math.max(maximum[axis], point[axis])
        end
    end

    local halfSize = scale(subtract(maximum, minimum), 0.5)
    if halfSize.X <= 0 or halfSize.Y <= 0 or halfSize.Z <= 0
        or length(halfSize) >= MAX_HALF_EXTENT_LENGTH then
        return nil, 'invalid native box extents'
    end
    return halfSize
end
getHalfSize = uevrUtils.profiler:wrap('melee.sweep.getHalfSize', getHalfSize)

function M.resetWeapon()
    geometryKey, geometry = nil, nil
end

function M.getGeometry(player, asset)
    if not uevrUtils.getValid(player) or not uevrUtils.getValid(asset) then
        return nil, 'weapon geometry objects unavailable'
    end
    local key = tostring(player:get_address()) .. ':' .. tostring(asset:get_address())
    if geometryKey == key then
        return geometry
    end

    local ready, err = initializeLibraries()
    if not ready then
        return nil, err
    end
    local shape, part = native.getWeaponShape(player)
    if not shape then
        return nil, part
    end
    if not isBoxType(shape.Type, 0) then
        return nil, 'native box type unavailable for ' .. part
    end
    local relative = shape.Attachment and shape.Attachment.RelativeTransform
    if not relative or not isQuaternion(relative.Rotation)
        or not isVector(relative.Translation) or not isVector(relative.Scale3D) then
        return nil, 'native box offset unavailable'
    end
    local halfSize
    halfSize, err = getHalfSize(shape)
    if not halfSize then
        return nil, err
    end
    geometry = {halfSize = halfSize, relative = relative}
    geometryKey = key
    return geometry
end
M.getGeometry = uevrUtils.profiler:wrap('melee.sweep.getGeometry', M.getGeometry)

function M.getPose(weapon, weaponGeometry)
    if not uevrUtils.getValid(weapon) or type(weaponGeometry) ~= 'table' then
        return nil, 'weapon pose inputs unavailable'
    end
    local world = weapon:K2_GetComponentToWorld()
    local relative = weaponGeometry.relative
    local halfSize = weaponGeometry.halfSize
    if world == nil or relative == nil or halfSize == nil then
        return nil, 'weapon transform unavailable'
    end
    return {
        center = transformPoint(relative.Translation, world),
        rotation = quaternionMultiply(world.Rotation, relative.Rotation),
        halfSize = {
            X = halfSize.X * math.abs(world.Scale3D.X * relative.Scale3D.X),
            Y = halfSize.Y * math.abs(world.Scale3D.Y * relative.Scale3D.Y),
            Z = halfSize.Z * math.abs(world.Scale3D.Z * relative.Scale3D.Z),
        },
    }
end
M.getPose = uevrUtils.profiler:wrap('melee.sweep.getPose', M.getPose)

local function getMotion(previousPose, currentPose, deltaTime)
    local angle = 2 * math.acos(math.min(1, math.abs(quaternionDot(previousPose.rotation, currentPose.rotation))))
    local inverse = {
        X = -previousPose.rotation.X, Y = -previousPose.rotation.Y,
        Z = -previousPose.rotation.Z, W = previousPose.rotation.W,
    }
    local difference = quaternionMultiply(currentPose.rotation, inverse)
    if difference.W < 0 then
        difference = {X = -difference.X, Y = -difference.Y, Z = -difference.Z, W = -difference.W}
    end
    local axis = {X = difference.X, Y = difference.Y, Z = difference.Z}
    local axisLength = length(axis)
    local angularVelocity = {X = 0, Y = 0, Z = 0}
    if axisLength > AXIS_EPSILON then
        angularVelocity = scale(axis, angle / (deltaTime * axisLength))
    end
    local linearVelocity = scale(subtract(currentPose.center, previousPose.center), 1 / deltaTime)
    local steps = math.max(1, math.min(MAX_SUBSTEPS, math.ceil(angle / ANGULAR_STEP)))
    return linearVelocity, angularVelocity, steps
end
getMotion = uevrUtils.profiler:wrap('melee.sweep.getMotion', getMotion)

local function collectHit(contacts, player, hit, traceHandle, traceIndex, startPoint, endPoint, step, steps, linear, angular)
    if type(hit) ~= 'table' then
        return false, 'box sweep hit unavailable'
    end
    -- Bridge hit references may arrive as a UObject, address, or property wrapper.
    local reference = hit.Component
    local mesh
    if type(reference) == 'userdata' then
        mesh = reference
    else
        if type(reference) == 'table' then
            reference = reference.address or reference.value
        end
        if type(reference) == 'string' then
            reference = tonumber(reference)
        end
        if type(reference) == 'number' and reference > 0 then
            mesh = uevr.api:to_uobject(reference)
        end
    end
    mesh = uevrUtils.getValid(mesh)
    if not mesh then
        return false, 'box sweep component unavailable'
    end
    local target = uevrUtils.getValid(mesh:GetOwner())
    if not target then
        return false, 'box sweep hit owner unavailable'
    end
    if target:get_address() == player:get_address() then
        return true
    end

    local point = hit.ImpactPoint
    if not isVector(point) then
        return false, 'box sweep contact point unavailable'
    end
    local fraction = hit.Time or 0
    local time = ((step - 1) + fraction) / steps
    local address = target:get_address()
    if not contacts[address] or time < contacts[address].time then
        local radius = subtract(point, lerp(startPoint, endPoint, fraction))
        contacts[address] = {
            player = player, target = target, mesh = mesh, hit = hit, time = time,
            traceHandle = traceHandle, traceIndex = traceIndex, handles = pendingHandles,
            velocity = add(linear, cross(angular, radius)),
        }
    end
    return true
end
collectHit = uevrUtils.profiler:wrap('melee.sweep.collectHit', collectHit)

function M.collectContacts(player, previousPose, currentPose, deltaTime)
    if not uevrUtils.getValid(player) or type(deltaTime) ~= 'number' or deltaTime <= 0
        or type(previousPose) ~= 'table' or type(currentPose) ~= 'table'
        or not isVector(previousPose.center) or not isVector(currentPose.center)
        or not isQuaternion(previousPose.rotation) or not isQuaternion(currentPose.rotation)
        or not isVector(currentPose.halfSize) then
        return nil, 'sweep inputs unavailable'
    end
    local ready, err = initializeLibraries()
    if not ready then
        return nil, err
    end
    local linear, angular, steps = getMotion(previousPose, currentPose, deltaTime)
    local contacts = {}
    for step = 1, steps do
        local startPoint = lerp(previousPose.center, currentPose.center, (step - 1) / steps)
        local endPoint = lerp(previousPose.center, currentPose.center, step / steps)
        local rotation = quaternionBlend(previousPose.rotation, currentPose.rotation, (step - 0.5) / steps)
        rotationArgument.X, rotationArgument.Y = rotation.X, rotation.Y
        rotationArgument.Z, rotationArgument.W = rotation.Z, rotation.W
        local rotator = mathLibrary:Quat_Rotator(rotationArgument)
        if not rotator or type(rotator.Pitch) ~= 'number'
            or type(rotator.Yaw) ~= 'number' or type(rotator.Roll) ~= 'number' then
            M.releaseHandles()
            return nil, 'native sweep orientation unavailable'
        end
        local orientation = {Pitch = rotator.Pitch, Yaw = rotator.Yaw, Roll = rotator.Roll}
        local result = plugin.executeFunctionWithHandle(systemLibrary, 'BoxTraceMultiByProfile', 'OutHits', TRACE_OUTPUTS,
            player, startPoint, endPoint, currentPose.halfSize, orientation, 'Weapon',
            false, {player}, 0, {}, true, {}, {}, 0)
        if result == nil or result.error then
            M.releaseHandles()
            return nil, result and result.error or 'BoxTraceMultiByProfile returned no bridge response'
        end
        if type(result.handle) ~= 'number' or result.handle <= 0 then
            M.releaseHandles()
            return nil, 'native box sweep returned no handle'
        end
        pendingHandles[result.handle] = true
        if type(result.OutHits) ~= 'table' then
            M.releaseHandles()
            return nil, 'native box sweep returned no hit array'
        end

        for index, hit in ipairs(result.OutHits) do
            local collected, hitError = collectHit(contacts, player, hit, result.handle, index,
                startPoint, endPoint, step, steps, linear, angular)
            if not collected then
                M.releaseHandles()
                return nil, hitError
            end
        end
    end
    return contacts
end
M.collectContacts = uevrUtils.profiler:wrap('melee.sweep.collectContacts', M.collectContacts)

return M
