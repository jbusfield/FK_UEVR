local uevrUtils = require('libs/uevr_utils')
local plugin = require('libs/core/plugin')

-- Native hit processing owns damage, blocking, reactions, and wound effects.
-- Public operations return nil plus a reason on failure; validation never throws.
local M = {}

local LIGHT_ATTACK = 'Ability.Active.WeaponAttack.Single.Light'
local HEAVY_ATTACK = 'Ability.Active.WeaponAttack.Hold.Heavy.Release'
local RIGHT_HAND_SLOT_TYPE = 'EquipmentSlot.Hand.R'
local IMPACT_CLASS = 'Class /Script/SLASHER.SlasherAbilityModule_ImpactWeapon'
local FX_CLASS = 'Class /Script/SLASHER.SlasherAbilityModule_FX'

-- These structs contain Unreal containers and need bridge copies.
local IMPACT_STRUCT_FIELDS = {
    'ModuleData', 'ImpactPhysics', 'FactionConfig',
    'Effects', 'ImpactTargetEffect', 'ImpactCasterEffect',
}
local FX_STRUCT_FIELDS = {'ModuleData'}
local HIT_INFO_OUTPUTS = {
    'ReturnValue.Direction', 'ReturnValue.TargetActor',
    'ReturnValue.TargetAttributeComp', 'ReturnValue.TargetAbilityComp',
    'ReturnValue.HitSkeleton', 'ReturnValue.HitLimbData', 'ReturnValue.HitBone',
}

-- Authored Lua snapshots belong to the current equipped item. Per-hit objects
-- and contact state are never cached.
local weaponCache

function M.resetWeaponCache()
    weaponCache = nil
end

-- Copy a bridge payload while converting structured gameplay-tag map keys
-- to JSON-compatible strings. Ordinary table copies use uevrUtils.deepCopyTable.
local function copyWithStringTagKeys(value)
    if type(value) ~= 'table' then
        return value
    end

    local result = {}
    for key, child in pairs(value) do
        if type(key) == 'table' then
            if not key.TagName then
                return nil, 'unsupported structured map key'
            end
            key = tostring(key.TagName)
        end
        local copied, err = copyWithStringTagKeys(child)
        if err then
            return nil, err
        end
        result[key] = copied
    end
    return result
end

local function bridgeTagName(tag)
    if type(tag) == 'table' then
        return tostring(tag.TagName or '')
    end
    return tostring(tag)
end

local function findWeaponPartData(map, partName)
    if type(map) ~= 'table' then
        return nil
    end
    for key, value in pairs(map) do
        if bridgeTagName(key) == partName then
            return value
        end
    end
end

local function readModuleContainerFields(source, fields)
    local settings = {}
    for _, field in ipairs(fields) do
        local value = plugin.getProperty(source, field)
        if value == nil then
            return nil, 'missing authored field: ' .. field
        end
        local copied, err = copyWithStringTagKeys(value)
        if err then
            return nil, field .. ': ' .. err
        end
        settings[field] = copied
    end
    return settings
end
readModuleContainerFields = uevrUtils.profiler:wrap('melee.native.readModuleContainerFields', readModuleContainerFields)

local function getEquippedWeapon(player)
    if not uevrUtils.getValid(player) then
        return nil, 'player unavailable'
    end
    local equipment = uevrUtils.getValid(player.EquipmentComponent)
    if not equipment then
        return nil, 'equipment unavailable'
    end

    local handType = uevrUtils.tagFromString(RIGHT_HAND_SLOT_TYPE)
    if not handType then
        return nil, 'equipment slot type unavailable'
    end
    local slot = equipment:GetActiveSlotForType(handType)
    if not slot then
        return nil, 'active equipment slot unavailable'
    end
    local item = uevrUtils.getValid(equipment:GetEquippedItemData(slot, false))
    if not item then
        return nil, 'equipped weapon unavailable'
    end

    local world = uevrUtils.getWorld()
    if not world then
        return nil, 'weapon world unavailable'
    end
    local playerAddress, worldAddress = player:get_address(), world:get_address()
    local equipmentAddress, itemAddress = equipment:get_address(), item:get_address()
    if weaponCache and weaponCache.playerAddress == playerAddress
        and weaponCache.worldAddress == worldAddress
        and weaponCache.equipmentAddress == equipmentAddress
        and weaponCache.itemAddress == itemAddress then
        weaponCache.slot = slot
        return weaponCache
    end
    weaponCache = nil

    local parts = plugin.getProperty(item, 'MainWeaponParts')
    local part = type(parts) == 'table' and type(parts.GameplayTags) == 'table' and parts.GameplayTags[1]
    if not part then
        return nil, 'primary weapon part unavailable'
    end
    weaponCache = {
        playerAddress = playerAddress, worldAddress = worldAddress,
        equipmentAddress = equipmentAddress, itemAddress = itemAddress,
        equipment = equipment, slot = slot, item = item, part = part, attacks = {},
    }
    return weaponCache
end
getEquippedWeapon = uevrUtils.profiler:wrap('melee.native.getEquippedWeapon', getEquippedWeapon)

function M.getWeaponShape(player)
    local weapon, err = getEquippedWeapon(player)
    if not weapon then
        return nil, err
    end
    local partName = bridgeTagName(weapon.part)
    local shape = weapon.shape
    if not shape then
        shape = findWeaponPartData(plugin.getProperty(weapon.item, 'AbilityShapeForWeaponPart'), partName)
    end
    if type(shape) ~= 'table' then
        return nil, 'native combat shape unavailable for ' .. partName
    end
    weapon.shape = shape
    return uevrUtils.deepCopyTable(shape), partName
end
M.getWeaponShape = uevrUtils.profiler:wrap('melee.native.getWeaponShape', M.getWeaponShape)

local function getDamagePayload(player)
    local weapon, err = getEquippedWeapon(player)
    if not weapon then
        return nil, err
    end
    local partName = bridgeTagName(weapon.part)
    if not weapon.matrix then
        local shape = weapon.shape or findWeaponPartData(plugin.getProperty(weapon.item, 'AbilityShapeForWeaponPart'), partName)
        local matrix = findWeaponPartData(plugin.getProperty(weapon.item, 'WeaponPartToDamageMatrix'), partName)
        if type(shape) ~= 'table' or type(matrix) ~= 'table' then
            return nil, 'weapon shape/damage matrix unavailable for ' .. partName
        end
        if type(matrix.Entries) ~= 'table' or #matrix.Entries == 0 then
            return nil, 'weapon damage matrix is empty'
        end

        for _, entry in ipairs(matrix.Entries) do
            if type(entry) ~= 'table' or type(entry.TargetAttributes) ~= 'table' then
                return nil, 'weapon damage attributes unavailable'
            end
            for _, attribute in ipairs(entry.TargetAttributes) do
                if type(attribute) ~= 'table' or type(attribute.Spec) ~= 'table' then
                    return nil, 'weapon damage spec unavailable'
                end
                if type(attribute.Spec.AttributeContributions) ~= 'table' then
                    return nil, 'weapon damage contributions unavailable'
                end
            end
        end
        local copied
        copied, err = copyWithStringTagKeys(matrix)
        if err then
            return nil, err
        end
        weapon.shape, weapon.matrix = shape, copied
    end

    local stackId = weapon.equipment:GetEquippedStack(weapon.slot, false)
    if not stackId then
        return nil, 'equipped weapon stack unavailable'
    end
    return {matrix = weapon.matrix, part = weapon.part, stackId = stackId}
end
getDamagePayload = uevrUtils.profiler:wrap('melee.native.getDamagePayload', getDamagePayload)

local function getAttackData(component, heavy)
    -- Single.Heavy is a medium impact; held-trigger swings use the charged release.
    local attackTag = heavy and HEAVY_ATTACK or LIGHT_ATTACK
    local componentAddress = component:get_address()
    if weaponCache.attackComponentAddress ~= componentAddress then
        weaponCache.attackComponentAddress, weaponCache.attacks = componentAddress, {}
    end
    local cached = weaponCache.attacks[attackTag]
    if cached and uevrUtils.getValid(cached.impactSource)
        and (cached.fxSource == nil or uevrUtils.getValid(cached.fxSource)) then
        return cached
    end
    weaponCache.attacks[attackTag] = nil
    local response = plugin.executeFunction(component, 'GetSingleAbilityDataOfTypeInCollection',
        {TagName = attackTag}, {}, {})
    if response == nil or response.error then
        return nil, response and response.error or 'GetSingleAbilityDataOfTypeInCollection returned no bridge response'
    end
    local data = response.ReturnValue
    if type(data) ~= 'table' or bridgeTagName(data.MainType) ~= attackTag then
        return nil, 'equipped attack data unavailable for ' .. attackTag
    end
    if type(data.ModuleObjects) ~= 'table' then
        return nil, 'attack modules unavailable'
    end

    local impactSource, fxSource
    for _, module in ipairs(data.ModuleObjects) do
        if uevrUtils.getValid(module) then
            local className = module:get_class():get_fname():to_string()
            if className == 'SlasherAbilityModule_ImpactWeapon' and not impactSource then
                impactSource = module
            elseif className == 'SlasherAbilityModule_FX' and not fxSource then
                fxSource = module
            end
        end
    end
    if not impactSource then
        return nil, 'weapon impact module unavailable'
    end
    local impactSettings, err = readModuleContainerFields(impactSource, IMPACT_STRUCT_FIELDS)
    if not impactSettings then
        return nil, err
    end
    local fxSettings
    if fxSource then
        fxSettings, err = readModuleContainerFields(fxSource, FX_STRUCT_FIELDS)
        if not fxSettings then
            return nil, err
        end
    end
    local template
    template, err = copyWithStringTagKeys(data)
    if err then
        return nil, err
    end
    cached = {
        data = template, impactSource = impactSource, fxSource = fxSource,
        impactSettings = impactSettings, fxSettings = fxSettings,
    }
    weaponCache.attacks[attackTag] = cached
    return cached
end
getAttackData = uevrUtils.profiler:wrap('melee.native.getAttackData', getAttackData)

local function createModules(ability, attack)
    local impact = uevrUtils.getValid(uevrUtils.spawn_object(IMPACT_CLASS, ability))
    if not impact then
        return nil, 'could not construct private impact module'
    end
    -- The bridge converts UObject references in its arguments in place. Give
    -- every private module its own copy so the cached snapshots stay untouched.
    for _, field in ipairs(IMPACT_STRUCT_FIELDS) do
        plugin.setProperty(impact, field, uevrUtils.deepCopyTable(attack.impactSettings[field]))
    end
    if not impact.ImpactTargetEffect or not impact.ImpactCasterEffect then
        return nil, 'impact effect settings unavailable'
    end
    impact.bIgnoreBlock = attack.impactSource.bIgnoreBlock
    impact.bIncludeWeaponDamage = attack.impactSource.bIncludeWeaponDamage
    impact.bDisableShapeOnImpact = false
    impact.bUseAimingSocket = false
    impact.bUseDefaultAimingSocket = false
    impact.ImpactTargetEffect.OwnerAbility = ability
    impact.ImpactCasterEffect.OwnerAbility = ability

    local modules = {impact}
    local source = attack.fxSource
    if source then
        local fx = uevrUtils.getValid(uevrUtils.spawn_object(FX_CLASS, ability))
        if not fx then
            return nil, 'could not construct private hit FX module'
        end
        for _, field in ipairs(FX_STRUCT_FIELDS) do
            plugin.setProperty(fx, field, uevrUtils.deepCopyTable(attack.fxSettings[field]))
        end
        if not source.PhysicalMaterialTag or not source.MaterialTagWhenHitByAbility
            or not fx.PhysicalMaterialTag or not fx.MaterialTagWhenHitByAbility
            or not source.HitImpactDecalSize or not fx.HitImpactDecalSize then
            return nil, 'hit FX settings unavailable'
        end
        fx.PhysicalMaterialTag.TagName = source.PhysicalMaterialTag.TagName
        fx.MaterialTagWhenHitByAbility.TagName = source.MaterialTagWhenHitByAbility.TagName
        fx.HitImpactDecalSize.X = source.HitImpactDecalSize.X
        fx.HitImpactDecalSize.Y = source.HitImpactDecalSize.Y
        fx.HitImpactLayerIndex = source.HitImpactLayerIndex
        modules[#modules + 1] = fx
    end
    return modules
end
createModules = uevrUtils.profiler:wrap('melee.native.createModules', createModules)

local function configureContext(ability, template, modules, component, contact, bone, point)
    local data = uevrUtils.deepCopyTable(template)
    local player = contact.player
    data.ModuleObjects = modules
    data.Caster, data.Causer = player, player
    data.CastingCharacter, data.CastingHero, data.CastingComponent = player, player, component
    data.CasterSceneComp, data.CasterMeshComp = player.RootComponent, player.Mesh
    data.CasterAnimInstance, data.World = player.AnimInstance, uevrUtils.getWorld()
    data.Target, data.TargetComponent, data.TargetBone = contact.target, contact.mesh, bone
    data.TargetLocation, data.TargetSearchImpactPoint = point, point
    data.Velocity = {X = contact.velocity.X, Y = contact.velocity.Y, Z = contact.velocity.Z}
    data.bActive, data.bCanTick, data.bTickDuration = false, false, false
    data.ItemAnimationData, data.CauserInput = {}, {TagName = 'None'}
    plugin.setProperty(ability, 'AbilityData', data)

    if not ability.AbilityData or ability.AbilityData.bActive ~= false then
        return false, 'contact context unexpectedly active'
    end
    if uevrUtils.getValid(ability:GetActiveAnimation()) then
        return false, 'contact context unexpectedly has an animation'
    end
    return true
end
configureContext = uevrUtils.profiler:wrap('melee.native.configureContext', configureContext)

local function validateTarget(info, target, mesh, bone)
    if not uevrUtils.getValid(info.TargetActor) or info.TargetActor:get_address() ~= target:get_address() then
        return false, 'generated target does not match contact'
    end
    local characterClass = uevrUtils.get_class('Class /Script/SLASHER.SlasherCharacter')
    if not characterClass then
        return false, 'character class unavailable'
    end
    if target:is_a(characterClass) then
        if not uevrUtils.getValid(info.TargetAttributeComp) or not uevrUtils.getValid(info.TargetAbilityComp) then
            return false, 'generated target components missing'
        end
        if not uevrUtils.getValid(info.HitSkeleton) or info.HitSkeleton:get_address() ~= mesh:get_address() then
            return false, 'generated hit skeleton does not match contact'
        end
        if not uevrUtils.getValid(info.HitLimbData) then
            -- Dummies have no damage limbs. Missing data on registered limbs stops the hit.
            local controller = uevrUtils.getValid(target.LimbController)
            if not controller then
                return false, 'target limb controller unavailable'
            end
            local limbs = plugin.getProperty(controller, 'AllLimbInfo')
            if type(limbs) ~= 'table' or limbs.error then
                return false, 'target limb table unavailable'
            end
            if next(limbs) ~= nil then
                return false, 'native limb lookup failed for ' .. bone
            end
        end
    end
    local generatedBone = tostring(info.HitBone)
    if generatedBone ~= 'None' and generatedBone ~= bone then
        return false, 'native hit generation redirected the bone to ' .. generatedBone
    end
    return true
end
validateTarget = uevrUtils.profiler:wrap('melee.native.validateTarget', validateTarget)

function M.applyHit(contact)
    if type(contact) ~= 'table' then
        return nil, 'contact unavailable'
    end
    local player = uevrUtils.getValid(contact.player)
    local target = uevrUtils.getValid(contact.target)
    local mesh = uevrUtils.getValid(contact.mesh)
    if not player or not target or target == player or not mesh then
        return nil, 'contact objects unavailable'
    end
    if type(contact.hit) ~= 'table' or not contact.hit.BoneName
        or contact.hit.ImpactPoint == nil or contact.velocity == nil then
        return nil, 'contact geometry unavailable'
    end
    if type(contact.traceHandle) ~= 'number' or contact.traceHandle <= 0
        or type(contact.traceIndex) ~= 'number' or contact.traceIndex < 1
        or type(contact.handles) ~= 'table' then
        return nil, 'contact native handle unavailable'
    end
    local component = uevrUtils.getValid(player.AbilityComponent)
    if not component then
        return nil, 'player ability component unavailable'
    end

    -- Refresh equipment identity before consulting the attack cache.
    local payload, err = getDamagePayload(player)
    if not payload then
        return nil, err
    end
    local attack
    attack, err = getAttackData(component, contact.heavy)
    if not attack then
        return nil, err
    end
    local hit = contact.hit
    local bone = tostring(hit.BoneName)
    local point = {X = hit.ImpactPoint.X, Y = hit.ImpactPoint.Y, Z = hit.ImpactPoint.Z}

    local ability = uevrUtils.spawn_object('Class /Script/SLASHER.Ability', component)
    if not uevrUtils.getValid(ability) then
        return nil, 'could not construct contact context'
    end
    local modules
    modules, err = createModules(ability, attack)
    if not modules then
        return nil, err
    end
    local configured
    configured, err = configureContext(ability, attack.data, modules, component, contact, bone, point)
    if not configured then
        return nil, err
    end

    -- Time these bridge calls directly, retaining their local response checks.
    local profiler = uevrUtils.profiler
    local started = profiler.enabled and os.clock()
    local generated = plugin.executeFunctionWithHandle(ability, 'GenerateHitInfo', 'ReturnValue', HIT_INFO_OUTPUTS,
        plugin.handleParam(contact.traceHandle, nil, contact.traceIndex))
    if started then
        local name = 'melee.native.GenerateHitInfo'
        profiler.counts[name] = (profiler.counts[name] or 0) + 1
        profiler.totalTimes[name] = (profiler.totalTimes[name] or 0) + (os.clock() - started) * 1000
    end
    if generated == nil or generated.error then
        return nil, generated and generated.error or 'GenerateHitInfo returned no bridge response'
    end
    local handle = generated.handle
    if type(handle) ~= 'number' or handle <= 0 then
        return nil, 'native hit generation returned no handle'
    end
    contact.handles[handle] = true
    local info = generated.ReturnValue
    local direction = type(info) == 'table' and info.Direction
    if type(direction) ~= 'table' or type(direction.X) ~= 'number'
        or type(direction.Y) ~= 'number' or type(direction.Z) ~= 'number' then
        plugin.releaseHandle(handle)
        contact.handles[handle] = nil
        return nil, 'native hit info unavailable'
    end
    local valid
    valid, err = validateTarget(info, target, mesh, bone)
    if not valid then
        plugin.releaseHandle(handle)
        contact.handles[handle] = nil
        return nil, err
    end

    -- The complete generated hit stays native. Send only contact corrections
    -- and the weapon payload; its other fields (including wound FX) stay intact.
    local matrix = uevrUtils.deepCopyTable(payload.matrix)
    local part = payload.part
    if type(part) == 'table' then
        part = uevrUtils.deepCopyTable(part)
    end
    local changes = {HitBone = bone, TargetObject = mesh, MeshImpactPoint = point}
    changes.AbilityShape = {
        WeaponDamageMatrix = matrix, WeaponPart = part, ItemStackId = payload.stackId,
        OwningAbility = ability,
        Velocity = {X = contact.velocity.X, Y = contact.velocity.Y, Z = contact.velocity.Z},
        Direction = {X = info.Direction.X, Y = info.Direction.Y, Z = info.Direction.Z},
    }
    started = profiler.enabled and os.clock()
    -- Impact's output fields are unused; skip serializing its large result.
    local impact = plugin.executeFunctionWithOutputs(ability, 'Impact', {}, {
        HitInfo = plugin.handleParam(handle, changes), CritMultiplier = 1,
    })
    if started then
        local name = 'melee.native.Impact'
        profiler.counts[name] = (profiler.counts[name] or 0) + 1
        profiler.totalTimes[name] = (profiler.totalTimes[name] or 0) + (os.clock() - started) * 1000
    end
    if impact == nil or impact.error then
        plugin.releaseHandle(handle)
        contact.handles[handle] = nil
        return nil, impact and impact.error or 'Impact returned no bridge response'
    end
    contact.handles[handle] = nil -- Impact consumed the single-use handle.
    return true
end
M.applyHit = uevrUtils.profiler:wrap('melee.native.applyHit', M.applyHit)

return M
