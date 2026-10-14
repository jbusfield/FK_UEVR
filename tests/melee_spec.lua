-- Run from the repository root with Lua 5.4: lua tests/melee_spec.lua
-- A source table may be passed to the chunk when running without filesystem IO.
local suppliedSources = ...
local LIGHT = 'Ability.Active.WeaponAttack.Single.Light'
local HEAVY = 'Ability.Active.WeaponAttack.Hold.Heavy.Release'
local checks = {}
local failures = {}

local function expect(condition, message)
    if not condition then
        failures[#failures + 1] = message or 'mock input check failed'
    end
    return condition
end

local function check(name, condition)
    assert(condition, name)
    checks[#checks + 1] = name
end

local function sourceFor(name)
    if type(suppliedSources) == 'table' then
        local source = suppliedSources[name]
        if not source then return nil, 'missing test source: ' .. name end
        return source
    end
    local file, err = io.open('scripts/' .. name .. '.lua', 'r')
    if not file then return nil, err end
    local source = file:read('*a')
    file:close()
    return source
end

local function vector(x, y, z)
    return {X = x or 0, Y = y or 0, Z = z or 0}
end

local function fixture()
    local f = {queries = {}, impacts = {}, errors = {}, objects = {}, attackRequests = {},
        nativeCalls = {}, propertyReads = {}, invalidAddresses = {}, handles = {},
        handleCalls = {}, releasedHandles = {}, consumedElements = {}, haptics = {}}
    local nextAddress = 10
    local function object(className)
        nextAddress = nextAddress + 1
        local address = nextAddress
        local instance = {
            get_address = function() return address end,
            get_class = function()
                return {get_fname = function()
                    return {to_string = function() return className end}
                end}
            end,
            is_a = function() return className == 'Character' end,
        }
        f.objects[address] = instance
        return instance
    end

    f.player, f.target, f.world = object('Hero'), object('Character'), object('World')
    f.asset, f.weapon, f.mesh = object('StaticMesh'), object('Weapon'), object('SkeletalMeshComponent')
    f.equipment, f.component, f.item = object('Equipment'), object('AbilityComponent'), object('Item')
    f.player.EquipmentComponent, f.player.AbilityComponent = f.equipment, f.component
    f.player.RootComponent, f.player.Mesh, f.player.AnimInstance = object('Root'), object('Mesh'), object('Anim')
    f.target.Mesh, f.target.LimbController = f.mesh, {AllLimbInfo = {}}
    f.target.AttributeComponent, f.target.AbilityComponent = object('Attributes'), object('AbilityComponent')
    f.mesh.GetOwner = function() return f.target end
    f.weapon.StaticMesh = f.asset
    f.position, f.pawnPosition = vector(), vector()
    f.rotation = {X = 0, Y = 0, Z = 0, W = 1}
    f.player.K2_GetActorLocation = function() return f.pawnPosition end
    f.weapon.K2_GetComponentToWorld = function()
        f.nativeCalls.transform = (f.nativeCalls.transform or 0) + 1
        return {Rotation = f.rotation, Translation = f.position, Scale3D = vector(1, 1, 1)}
    end
    f.equipment.GetActiveSlotForType = function(_, tag)
        expect(tag.TagName == 'EquipmentSlot.Hand.R')
        f.nativeCalls.slot = (f.nativeCalls.slot or 0) + 1
        return {Type = tag, Index = 0}
    end
    f.equipment.GetEquippedItemData = function(_, slot, visual)
        expect(slot.Type.TagName == 'EquipmentSlot.Hand.R' and visual == false)
        f.nativeCalls.item = (f.nativeCalls.item or 0) + 1
        return f.item
    end
    f.equipment.GetEquippedStack = function(_, slot, visual)
        expect(slot.Type.TagName == 'EquipmentSlot.Hand.R' and visual == false)
        f.nativeCalls.stack = (f.nativeCalls.stack or 0) + 1
        return f.stackId or {A = 1, B = 2, C = 3, D = 4}
    end
    f.newObject = object

    local identity = {
        Rotation = {X = 0, Y = 0, Z = 0, W = 1},
        Translation = vector(), Scale3D = vector(1, 1, 1),
    }
    f.shape = {Type = 3, Height = 10, Width = 10, Depth = 10, Radius = 0,
        Attachment = {RelativeTransform = identity}}
    local part = 'WeaponPart.Axe.Head'
    f.item.MainWeaponParts = {GameplayTags = {{TagName = part}}}
    f.item.AbilityShapeForWeaponPart = {[part] = f.shape}
    f.item.WeaponPartToDamageMatrix = {[part] = {
        Entries = {{TargetAttributes = {{Spec = {Value = 20, AttributeContributions = {}}}}}},
    }}
    local impactFields = {'ModuleData', 'ImpactPhysics', 'FactionConfig', 'Effects'}
    f.sources = {}
    for _, attack in ipairs({LIGHT, HEAVY}) do
        local impact, fx = object('SlasherAbilityModule_ImpactWeapon'), object('SlasherAbilityModule_FX')
        for _, field in ipairs(impactFields) do
            impact[field] = {marker = attack .. ':' .. field}
        end
        impact.ImpactTargetEffect, impact.ImpactCasterEffect = {}, {}
        impact.bIgnoreBlock, impact.bIncludeWeaponDamage = false, true
        fx.ModuleData = {bEnabled = true}
        fx.PhysicalMaterialTag = {TagName = attack == HEAVY and 'Surface.Axe.Heavy' or 'Surface.Axe.Light'}
        fx.MaterialTagWhenHitByAbility = {TagName = 'None'}
        fx.HitImpactDecalSize, fx.HitImpactLayerIndex = {X = 40, Y = 40}, -1
        f.sources[attack] = {impact = impact, fx = fx}
    end

    f.hits = {{Component = f.mesh:get_address(), ImpactPoint = vector(1, 2, 3), Time = 0.5, BoneName = 'leg_L3'}}
    local mathLibrary = {Quat_Rotator = function(_, quaternion)
        expect(quaternion.W ~= nil)
        f.nativeCalls.rotation = (f.nativeCalls.rotation or 0) + 1
        return {Pitch = 0, Yaw = 0, Roll = 0}
    end}
    local function deepCopyTable(original)
        f.nativeCalls.tableCopies = (f.nativeCalls.tableCopies or 0) + 1
        local copy = {}
        for key, value in pairs(original) do
            copy[key] = type(value) == 'table' and deepCopyTable(value) or value
        end
        return copy
    end
    local utils = {
        profiler = {wrap = function(_, _, func) return func end},
        print = function(message) f.errors[#f.errors + 1] = message end,
        triggerHapticVibration = function(hand) f.haptics[#f.haptics + 1] = hand end,
        deepCopyTable = deepCopyTable,
        getValid = function(value)
            if type(value) == 'table' and value.get_address and f.invalidAddresses[value:get_address()] then
                return nil
            end
            return value
        end,
        getWorld = function() return f.world end,
        get_class = function(name) return name end,
        find_default_instance = function(name)
            if name == 'Class /Script/Engine.KismetMathLibrary' then return mathLibrary end
            return name
        end,
        tagFromString = function(name) return {TagName = name} end,
        get_struct_object = function(name)
            expect(name == 'ScriptStruct /Script/CoreUObject.Quat')
            return {X = 0, Y = 0, Z = 0, W = 1}
        end,
        spawn_object = function(name)
            if f.spawnUnavailable then return nil end
            local instance = object(name)
            instance.GetActiveAnimation = function() return nil end
            if name == 'Class /Script/SLASHER.SlasherAbilityModule_FX' then
                instance.PhysicalMaterialTag, instance.MaterialTagWhenHitByAbility = {}, {}
                instance.HitImpactDecalSize = {X = 0, Y = 0}
            end
            return instance
        end,
    }
    local bridge = {}
    local nativeFields = {
        bIgnoreBlock = true, bIncludeWeaponDamage = true, bDisableShapeOnImpact = true,
        bUseAimingSocket = true, bUseDefaultAimingSocket = true,
        PhysicalMaterialTag = true, MaterialTagWhenHitByAbility = true,
        HitImpactDecalSize = true, HitImpactLayerIndex = true,
        ['ImpactTargetEffect.OwnerAbility'] = true, ['ImpactCasterEffect.OwnerAbility'] = true,
        ['AbilityData.bActive'] = true,
    }
    function bridge.getProperty(instance, field)
        f.propertyReads[field] = (f.propertyReads[field] or 0) + 1
        expect(not nativeFields[field], 'unnecessary bridge read: ' .. field)
        if f.missingField == field then return nil end
        return instance[field]
    end
    function bridge.setProperty(instance, field, value)
        expect(not nativeFields[field], 'unnecessary bridge write: ' .. field)
        instance[field] = value
    end
    function bridge.executeFunction(instance, method, ...)
        if f.exceptionMethod == method then error('simulated binding exception') end
        if f.noResponse == method then return nil end
        if f.failMethod == method then return {error = 'simulated bridge failure'} end
        if f.missingResult == method then return {} end
        local args = {...}
        if method == 'GetSingleAbilityDataOfTypeInCollection' then
            local requested = args[1].TagName
            f.attackRequests[#f.attackRequests + 1] = requested
            local attack = f.missingHeavy and LIGHT or requested
            local authored = f.sources[attack]
            return {ReturnValue = {
                MainType = {TagName = attack},
                ImpactType = {TagName = attack == HEAVY and 'Ability.Impact.Heavy' or 'Ability.Impact.Light'},
                ModuleObjects = {authored.impact, authored.fx},
            }}
        elseif method == 'GetBoundingPointsForShape' then
            local corners = {}
            for _, x in ipairs({-10, 10}) do
                for _, y in ipairs({-10, 10}) do
                    for _, z in ipairs({-10, 10}) do corners[#corners + 1] = vector(x, y, z) end
                end
            end
            return {ReturnValue = corners}
        elseif method == 'BoxTraceMultiByProfile' then
            expect(args[6] == 'Weapon', 'collision profile changed')
            if f.queryError then return {error = 'simulated bridge failure'} end
            f.queries[#f.queries + 1] = {startPoint = args[2], endPoint = args[3], halfSize = args[4]}
            if f.failTraceAt == #f.queries then return {error = 'simulated later substep failure'} end
            return {OutHits = f.hits}
        elseif method == 'GenerateHitInfo' then
            local fx = instance.AbilityData.ModuleObjects[2]
            if not expect(fx, 'missing wound FX module') then return {error = 'missing FX'} end
            local target, mesh = instance.AbilityData.Target, instance.AbilityData.TargetComponent
            return {ReturnValue = {
                TargetActor = f.generatedTarget or target, TargetAbilityComp = target.AbilityComponent,
                TargetAttributeComp = target.AttributeComponent, HitSkeleton = mesh,
                HitBone = f.generatedBone or 'None', Direction = vector(1, 0, 0),
                PhysicalMaterialTag = fx.PhysicalMaterialTag, ImpactDecalSize = fx.HitImpactDecalSize,
                ImpactLayerIndex = fx.HitImpactLayerIndex,
                AbilityEffects = {nativeOnly = 'preserved effects'},
                TargetBlockAbility = {nativeOnly = 'preserved block context'},
                SweepResult = args[1],
            }}
        elseif method == 'Impact' then
            f.impacts[#f.impacts + 1] = {data = instance.AbilityData, info = args[1].HitInfo}
            return {OutImpactResult = {HitInfo = args[1].HitInfo}}
        end
        expect(false, 'unexpected native call: ' .. method)
        return {error = 'unexpected native call: ' .. method}
    end
    local nextHandle = 1000
    local function storeHandle(value, array)
        nextHandle = nextHandle + 1
        f.handles[nextHandle] = {value = array and deepCopyTable(value) or value, array = array, taken = {}}
        return nextHandle
    end
    local function takeHandle(param)
        local handle = type(param) == 'table' and param['$handle']
        local stored = handle and f.handles[handle]
        if not expect(stored ~= nil, 'native handle missing or used twice') then return nil end
        local value
        if stored.array then
            local index = param['$index'] + 1
            if not expect(stored.value[index] ~= nil and not stored.taken[index], 'array element missing or used twice') then
                return nil
            end
            stored.taken[index] = true
            f.consumedElements[#f.consumedElements + 1] = {handle = handle, index = index}
            value = stored.value[index]
        else
            expect(param['$index'] == nil, 'struct handle cannot take an array index')
            value = stored.value
            f.handles[handle] = nil
        end
        for key, child in pairs(param) do
            if key ~= '$handle' and key ~= '$index' then value[key] = child end
        end
        return value
    end
    function bridge.handleParam(handle, changes, index)
        local param = {['$handle'] = handle}
        for key, value in pairs(changes or {}) do param[key] = value end
        if index ~= nil then param['$index'] = index - 1 end
        return param
    end
    function bridge.releaseHandle(handle)
        f.releasedHandles[#f.releasedHandles + 1] = handle
        f.handles[handle] = nil
    end
    function bridge.executeFunctionWithHandle(instance, method, keep, outputs, ...)
        expect((method == 'BoxTraceMultiByProfile' and keep == 'OutHits')
            or (method == 'GenerateHitInfo' and keep == 'ReturnValue'), 'unexpected kept output')
        local args = {...}
        f.handleCalls[#f.handleCalls + 1] = {method = method, keep = keep, outputs = outputs, args = args}
        if method == 'GenerateHitInfo' then
            if f.failBeforeConsume == method then return nil end
            args[1] = takeHandle(args[1])
            if not args[1] then return nil end
        end
        local response = bridge.executeFunction(instance, method, table.unpack(args))
        if response == nil or response.error then return nil end
        local value = response[keep]
        if type(value) ~= 'table' then return {} end
        local projected = {}
        if keep == 'OutHits' then
            for index in ipairs(value) do projected[index] = {} end
        end
        for _, path in ipairs(outputs) do
            local prefix, field = path:match('^(.-)%.(.+)$')
            expect(prefix == keep and field ~= nil, 'must project individual output fields')
            if keep == 'OutHits' then
                for index, hit in ipairs(value) do projected[index][field] = hit[field] end
            else
                projected[field] = value[field]
            end
        end
        if f.missingProjected == method then projected = nil end
        local result = {[keep] = projected}
        if f.noHandle ~= method then result.handle = storeHandle(value, keep == 'OutHits') end
        return result
    end
    function bridge.executeFunctionWithOutputs(instance, method, outputs, ...)
        expect(method == 'Impact' and type(outputs) == 'table' and next(outputs) == nil,
            'Impact must suppress all output serialization')
        if f.failBeforeConsume == method then return nil end
        local args = {...}
        args[1].HitInfo = takeHandle(args[1].HitInfo)
        if not args[1].HitInfo then return nil end
        local response = bridge.executeFunction(instance, method, table.unpack(args))
        if response == nil or response.error then return nil end
        return {}
    end
    f.keepHits = function() return storeHandle(f.hits, true) end

    local env = setmetatable({
        Handed = {Left = 0, Right = 1},
        LogLevel = {Error = 1, Debug = 4},
        uevrUtils = utils, plugin = bridge,
        json = {dump_string = function() return 'test enum' end},
        uevr = {
            api = {to_uobject = function(_, address) return f.objects[address] end},
            params = {functions = {log_error = function(message) f.errors[#f.errors + 1] = message end}},
        },
    }, {__index = _G})
    local loaded = {['libs/uevr_utils'] = utils, ['libs/core/plugin'] = bridge}
    env.require = function(name)
        if not loaded[name] then
            local source, sourceError = sourceFor(name)
            if not expect(source, sourceError) then return nil end
            local chunk, compileError = load(source, name, 't', env)
            if not expect(chunk, compileError) then return nil end
            loaded[name] = chunk()
        end
        return loaded[name]
    end
    f.melee = env.require('helpers/melee')
    f.native = env.require('helpers/melee/native')
    f.sweep = env.require('helpers/melee/sweep')
    function f.tick(distance, deltaTime, enabled)
        f.position = vector(f.position.X + (distance or 0), f.position.Y, f.position.Z)
        f.melee.update(f.player, f.weapon, deltaTime or 0.02, enabled ~= false)
    end
    return f
end

local f = fixture()
f.tick()
f.tick(10)
check('movement outside a gesture makes no query', #f.queries == 0)
f.melee.beginSwing()
f.tick(0.1)
check('gesture window sweeps without a second speed threshold', #f.queries == 1 and #f.impacts == 1)
local light = f.impacts[1]
check('light hit preserves authored data and damage matrix', light.data.MainType.TagName == LIGHT
    and light.data.ModuleObjects[1].ImpactPhysics.marker == LIGHT .. ':ImpactPhysics'
    and light.info.AbilityShape.WeaponDamageMatrix.Entries[1].TargetAttributes[1].Spec.Value == 20)
check('wound uses actual contact point and authored FX', light.info.HitBone == 'leg_L3'
    and light.info.MeshImpactPoint.X == 1 and light.info.MeshImpactPoint.Y == 2 and light.info.MeshImpactPoint.Z == 3
    and light.info.PhysicalMaterialTag.TagName == 'Surface.Axe.Light' and light.info.ImpactDecalSize.X == 40)
check('contact context stays inactive and unticked', light.data.bActive == false and light.data.bCanTick == false)
check('authored modules remain unchanged', f.sources[LIGHT].impact.ImpactTargetEffect.OwnerAbility == nil)
check('simple equipment and frame calls use native bindings', f.nativeCalls.slot == 2
    and f.nativeCalls.item == 2 and f.nativeCalls.stack == 1
    and f.nativeCalls.transform == 3 and f.nativeCalls.rotation == 1)
check('ordinary copies use the existing utility', (f.nativeCalls.tableCopies or 0) >= 4)
f.melee.beginSwing()
for _ = 1, 55 do f.tick(0.1) end
check('duplicate begin and repeated contact cause one hit', #f.impacts == 1)
f.melee.endSwing()
local queryCount = #f.queries
f.tick(10)
check('end closes the window immediately', #f.queries == queryCount)
f.melee.setHeavyInput(true)
f.melee.beginSwing()
f.melee.setHeavyInput(false)
f.tick(0.1)
check('heavy selection stays latched after trigger release', #f.impacts == 2
    and f.impacts[2].data.MainType.TagName == HEAVY and f.impacts[2].data.ImpactType.TagName == 'Ability.Impact.Heavy'
    and f.impacts[2].info.PhysicalMaterialTag.TagName == 'Surface.Axe.Heavy')
f.melee.endSwing()
f.melee.beginSwing()
f.tick(0.1)
check('separate swings respect the hit cooldown', #f.impacts == 2)
for _ = 1, 55 do f.tick() end
check('new window can hit after cooldown', #f.impacts == 3 and f.impacts[3].data.MainType.TagName == LIGHT)
f.weapon.StaticMesh = f.newObject('StaticMesh')
queryCount = #f.queries
f.tick(0.1)
f.tick(0.1)
check('weapon change cancels the old window', #f.queries == queryCount)
f.melee.setHeavyInput(true)
f.melee.resetWeapon()
f.melee.beginSwing()
f.tick()
f.tick(0.1)
check('initial pose preserves begin and reset clears stale trigger', #f.impacts == 4
    and f.impacts[4].data.MainType.TagName == LIGHT)
queryCount = #f.queries
f.tick(100)
check('tracking jump skips an unsafe sweep', #f.queries == queryCount)
f.tick(0.1)
check('tracking jump preserves the gesture window', #f.queries == queryCount + 1)
f.tick(0, 0.2)
queryCount = #f.queries
f.tick()
f.tick()
check('stalled frame closes the window', #f.queries == queryCount)
f.melee.beginSwing()
f.tick(0, 0.02, false)
f.tick()
f.tick()
check('disabled update closes the window', #f.queries == queryCount)
check('valid operation logs no errors', #f.errors == 0)
check('frame completion frees handles from hits and skipped contacts', next(f.handles) == nil)
check('native-only effects and blocking data survive the handle path',
    light.info.AbilityEffects.nativeOnly == 'preserved effects'
    and light.info.TargetBlockAbility.nativeOnly == 'preserved block context')

f = fixture()
f.hits[1].Normal = vector(0, 0, 1)
local enemy = f.newObject('Character')
local enemyMesh = f.newObject('SkeletalMeshComponent')
enemy.Mesh, enemy.AttributeComponent, enemy.AbilityComponent, enemy.LimbController =
    enemyMesh, f.newObject('Attributes'), f.newObject('AbilityComponent'), {AllLimbInfo = {}}
enemyMesh.GetOwner = function() return enemy end
f.hits[2] = {Component = enemyMesh:get_address(), ImpactPoint = vector(10, 20, 30), Time = 0.2, BoneName = 'head1'}
f.hits[3] = {Component = f.mesh:get_address(), ImpactPoint = vector(5, 6, 7), Time = 0.1,
    BoneName = 'leg_L3', Normal = vector(0, 1, 0)}
f.tick()
f.melee.beginSwing()
f.rotation = {X = 0, Y = 0, Z = math.sin(math.rad(45)), W = math.cos(math.rad(45))}
f.tick()
local used = {}
for _, element in ipairs(f.consumedElements) do used[element.index] = true end
check('two targets consume distinct selected elements from a kept array', #f.impacts == 2
    and #f.consumedElements == 2 and used[2] and used[3]
    and f.consumedElements[1].handle == f.consumedElements[2].handle)
local nearest
for _, impact in ipairs(f.impacts) do
    if impact.data.Target:get_address() == f.target:get_address() then nearest = impact.info end
end
check('closest contact retains its unprojected native hit fields', nearest.MeshImpactPoint.X == 5
    and nearest.SweepResult.Normal.Y == 1)
check('unselected elements and angular substep arrays are released', next(f.handles) == nil and #f.queries == 4)
f.tick()
check('repeated contacts do not consume handles or repeat haptics', next(f.handles) == nil
    and #f.consumedElements == 2 and #f.haptics == 2)
f.melee.endSwing()
f.melee.beginSwing()
f.tick()
check('cooldown skips free their arrays without generating hit info', next(f.handles) == nil
    and #f.consumedElements == 2 and #f.haptics == 2)

for _, outcome in ipairs({'miss', 'self contact'}) do
    local case = fixture()
    if outcome == 'miss' then case.hits = {}
    else
        case.player.Mesh.GetOwner = function() return case.player end
        case.hits = {{Component = case.player.Mesh:get_address(), ImpactPoint = vector(), Time = 0, BoneName = 'None'}}
    end
    case.tick()
    case.melee.beginSwing()
    case.tick()
    check(outcome .. ' frees its native array without a hit', next(case.handles) == nil
        and #case.impacts == 0 and #case.haptics == 0 and #case.errors == 0)
end

local handleFailures = {
    {'missing trace handle', function(case) case.noHandle = 'BoxTraceMultiByProfile' end},
    {'missing trace projection', function(case) case.missingProjected = 'BoxTraceMultiByProfile' end},
    {'missing hit-info handle', function(case) case.noHandle = 'GenerateHitInfo' end},
    {'missing hit-info projection', function(case) case.missingProjected = 'GenerateHitInfo' end},
    {'wrong target validation', function(case) case.generatedTarget = case.newObject('Character') end},
    {'generation failure before consumption', function(case) case.failBeforeConsume = 'GenerateHitInfo' end},
    {'impact failure before consumption', function(case) case.failBeforeConsume = 'Impact' end},
    {'generation binding exception', function(case) case.exceptionMethod = 'GenerateHitInfo' end},
    {'impact binding exception', function(case) case.exceptionMethod = 'Impact' end},
    {'validation binding exception', function(case)
        case.target.is_a = function() error('simulated target validation exception') end
    end},
    {'later angular substep failure', function(case)
        case.failTraceAt = 2
        case.rotation = {X = 0, Y = 0, Z = math.sin(math.rad(45)), W = math.cos(math.rad(45))}
    end},
}
for _, scenario in ipairs(handleFailures) do
    local case = fixture()
    case.tick()
    case.melee.beginSwing()
    scenario[2](case)
    case.tick()
    check(scenario[1] .. ' releases all frame handles', next(case.handles) == nil
        and #case.impacts == 0 and #case.haptics == 0 and #case.errors == 1)
end

f = fixture()
f.tick()
f.melee.beginSwing()
f.rotation = {X = 0, Y = 0, Z = math.sin(math.rad(45)), W = math.cos(math.rad(45))}
f.tick()
check('angular sweep is capped at four queries', #f.queries == 4 and #f.impacts == 1)
check('rotation contributes to contact velocity', math.abs(f.impacts[1].info.AbilityShape.Velocity.Y) > 1)
f.queryError = true
f.tick()
f.tick()
check('bridge error pauses the weapon and logs once', #f.errors == 1)
f.queryError = false
f.melee.resetWeapon()
f.melee.beginSwing()
f.tick()
f.tick()
check('weapon reset permits recovery', #f.impacts == 2)

f = fixture()
f.missingHeavy = true
f.melee.setHeavyInput(true)
f.melee.beginSwing()
f.tick()
f.tick(0.1)
check('missing heavy data cannot silently produce a light hit', #f.impacts == 0 and #f.errors == 1)

-- Call each public operation directly, without melee.update's boundary catch.
local function contactFor(case)
    local traceHandle = case.keepHits()
    return {player = case.player, target = case.target, mesh = case.mesh,
        hit = case.hits[1], velocity = vector(100, 0, 0),
        traceHandle = traceHandle, traceIndex = 1, handles = {[traceHandle] = true}}
end

-- Caching must preserve authored data while contact objects stay independent.
f = fixture()
local firstResult, firstError = f.native.applyHit(contactFor(f))
local first = f.impacts[1]
first.info.AbilityShape.WeaponDamageMatrix.Entries[1].TargetAttributes[1].Spec.Value = 999
first.data.ModuleObjects[1].ImpactPhysics.marker = 'modified private module'
first.data.TargetLocation.X = 999
f.hits[1].ImpactPoint = vector(4, 5, 6)
f.stackId = {A = 9, B = 8, C = 7, D = 6}
local secondResult, secondError = f.native.applyHit(contactFor(f))
local second = f.impacts[2]
check('warm hits reuse authored queries and container reads', firstResult ~= nil and secondResult ~= nil
    and firstError == nil and secondError == nil and #f.attackRequests == 1
    and f.propertyReads.MainWeaponParts == 1 and f.propertyReads.WeaponPartToDamageMatrix == 1
    and f.propertyReads.ImpactPhysics == 1)
check('warm hits construct distinct private modules', first.data.ModuleObjects[1]:get_address()
    ~= second.data.ModuleObjects[1]:get_address())
check('mutating a previous hit cannot corrupt cached damage or modules',
    second.info.AbilityShape.WeaponDamageMatrix.Entries[1].TargetAttributes[1].Spec.Value == 20
    and second.data.ModuleObjects[1].ImpactPhysics.marker == LIGHT .. ':ImpactPhysics')
check('warm hits refresh the actual point and item stack', second.data.TargetLocation.X == 4
    and first.data.TargetLocation.X == 999 and second.info.AbilityShape.ItemStackId.A == 9
    and f.nativeCalls.stack == 2)
local heavyContact = contactFor(f)
heavyContact.heavy = true
local heavyResult = f.native.applyHit(heavyContact)
check('light and heavy cache entries preserve separate definitions', heavyResult ~= nil
    and #f.attackRequests == 2 and f.impacts[3].data.MainType.TagName == HEAVY
    and f.impacts[3].info.PhysicalMaterialTag.TagName == 'Surface.Axe.Heavy')
f.native.applyHit(contactFor(f))
check('returning to light reuses its own cached definition', #f.attackRequests == 2
    and f.impacts[4].data.MainType.TagName == LIGHT)
f.melee.resetWeapon()
f.native.applyHit(contactFor(f))
check('weapon reset discards authored snapshots', #f.attackRequests == 3
    and f.propertyReads.WeaponPartToDamageMatrix == 2 and f.propertyReads.ImpactPhysics == 3)

for _, identity in ipairs({'item', 'world', 'player', 'equipment', 'ability component'}) do
    local case = fixture()
    case.native.applyHit(contactFor(case))
    if identity == 'item' then
        local replacement = case.newObject('Item')
        replacement.MainWeaponParts = case.item.MainWeaponParts
        replacement.AbilityShapeForWeaponPart = case.item.AbilityShapeForWeaponPart
        replacement.WeaponPartToDamageMatrix = {['WeaponPart.Axe.Head'] = {
            Entries = {{TargetAttributes = {{Spec = {Value = 35, AttributeContributions = {}}}}}},
        }}
        case.item = replacement
    elseif identity == 'world' then
        case.world = case.newObject('World')
    elseif identity == 'player' then
        local replacement = case.newObject('Hero')
        replacement.EquipmentComponent, replacement.AbilityComponent = case.equipment, case.component
        replacement.RootComponent, replacement.Mesh, replacement.AnimInstance =
            case.player.RootComponent, case.player.Mesh, case.player.AnimInstance
        case.player = replacement
    elseif identity == 'equipment' then
        local replacement = case.newObject('Equipment')
        replacement.GetActiveSlotForType = case.equipment.GetActiveSlotForType
        replacement.GetEquippedItemData = case.equipment.GetEquippedItemData
        replacement.GetEquippedStack = case.equipment.GetEquippedStack
        case.equipment, case.player.EquipmentComponent = replacement, replacement
    else
        case.component = case.newObject('AbilityComponent')
        case.player.AbilityComponent = case.component
    end
    local response, responseError = case.native.applyHit(contactFor(case))
    check(identity .. ' change invalidates cached attack data', response ~= nil and responseError == nil
        and #case.attackRequests == 2 and #case.impacts == 2)
    if identity == 'item' then
        check('item change with the same mesh refreshes damage',
            case.impacts[2].info.AbilityShape.WeaponDamageMatrix.Entries[1].TargetAttributes[1].Spec.Value == 35)
    end
end

f = fixture()
f.native.applyHit(contactFor(f))
f.invalidAddresses[f.sources[LIGHT].impact:get_address()] = true
f.sources[LIGHT].impact = f.sources[HEAVY].impact
local refreshed, refreshError = f.native.applyHit(contactFor(f))
check('expired authored module references are refreshed before reuse', refreshed ~= nil and refreshError == nil
    and #f.attackRequests == 2 and #f.impacts == 2)
f = fixture()
f.missingField = 'ImpactPhysics'
local failed, failureReason = f.native.applyHit(contactFor(f))
f.missingField = nil
local recovered, recoveryError = f.native.applyHit(contactFor(f))
check('failed cache initialization leaves no partial attack snapshot', failed == nil
    and type(failureReason) == 'string' and recovered ~= nil and recoveryError == nil
    and #f.attackRequests == 2 and #f.impacts == 1)

local invalidHits = {
    {'missing equipment returns a failure', function(case) case.player.EquipmentComponent = nil end},
    {'missing primary part returns a failure', function(case) case.item.MainWeaponParts = nil end},
    {'missing damage matrix returns a failure', function(case) case.item.WeaponPartToDamageMatrix = nil end},
    {'missing impact settings return a failure', function(case) case.missingField = 'ImpactPhysics' end},
    {'missing source FX settings return a failure', function(case) case.sources[LIGHT].fx.PhysicalMaterialTag = nil end},
    {'object construction failure returns a failure', function(case) case.spawnUnavailable = true end},
    {'attack query failure returns a failure', function(case) case.failMethod = 'GetSingleAbilityDataOfTypeInCollection' end},
    {'hit generation failure returns a failure', function(case) case.failMethod = 'GenerateHitInfo' end},
    {'impact failure returns a failure', function(case) case.failMethod = 'Impact' end},
    {'missing generated hit result returns a failure', function(case) case.missingResult = 'GenerateHitInfo' end},
    {'wrong generated target returns a failure', function(case) case.generatedTarget = case.newObject('Character') end},
    {'wrong generated bone returns a failure', function(case) case.generatedBone = 'head1' end},
    {'missing registered limb returns a failure', function(case) case.target.LimbController.AllLimbInfo = {leg = {}} end},
    {'missing contact coordinates return a failure', function(case) case.hits[1].ImpactPoint = nil end},
    {'malformed map key returns a failure', function(case) case.sources[LIGHT].impact.Effects = {[{}] = 1} end},
}
for _, scenario in ipairs(invalidHits) do
    local case = fixture()
    scenario[2](case)
    local result, reason = case.native.applyHit(contactFor(case))
    check(scenario[1], result == nil and type(reason) == 'string' and #case.impacts == 0)
end

f = fixture()
local result, reason = f.native.applyHit(nil)
check('missing contact returns a failure directly', result == nil and type(reason) == 'string')
f.shape.Type = 0
result, reason = f.sweep.getGeometry(f.player, f.asset)
check('unsupported geometry returns a failure directly', result == nil and type(reason) == 'string')
f = fixture()
f.failMethod = 'GetBoundingPointsForShape'
result, reason = f.sweep.getGeometry(f.player, f.asset)
check('geometry bridge error returns a failure directly', result == nil and type(reason) == 'string')
f = fixture()
local geometry = f.sweep.getGeometry(f.player, f.asset)
local pose = f.sweep.getPose(f.weapon, geometry)
f.queryError = true
result, reason = f.sweep.collectContacts(f.player, pose, pose, 0.02)
check('sweep bridge error returns a failure directly', result == nil and type(reason) == 'string')
f.queryError = false
f.hits[1].Component = 0
result, reason = f.sweep.collectContacts(f.player, pose, pose, 0.02)
check('missing sweep component returns a failure directly', result == nil and type(reason) == 'string')
f = fixture()
f.sources[LIGHT].impact.Effects = {[{}] = 1}
result, reason = f.native.applyHit(contactFor(f))
check('invalid container copy returns a failure directly', result == nil and type(reason) == 'string')

f = fixture()
local tagKey = {TagName = 'Attribute.Health'}
local original = {[tagKey] = {nested = {value = 20}}}
f.sources[LIGHT].impact.Effects = original
result, reason = f.native.applyHit(contactFor(f))
local copiedEffects = f.impacts[1].data.ModuleObjects[1].Effects
check('bridge copy converts tag keys to strings', reason == nil
    and copiedEffects['Attribute.Health'].nested.value == 20 and copiedEffects[tagKey] == nil)
copiedEffects['Attribute.Health'].nested.value = 10
check('bridge normalization preserves the source data', original[tagKey].nested.value == 20)

for _, referenceType in ipairs({'string', 'address wrapper', 'value wrapper'}) do
    local case = fixture()
    local address = case.mesh:get_address()
    if referenceType == 'string' then case.hits[1].Component = tostring(address)
    elseif referenceType == 'address wrapper' then case.hits[1].Component = {address = address}
    else case.hits[1].Component = {value = address} end
    case.tick()
    case.melee.beginSwing()
    case.tick(0.1)
    check('inline component resolution accepts ' .. referenceType, #case.impacts == 1 and #case.errors == 0)
end

for _, method in ipairs({'GetSingleAbilityDataOfTypeInCollection', 'GenerateHitInfo', 'Impact'}) do
    local case = fixture()
    case.noResponse = method
    local response, responseError = case.native.applyHit(contactFor(case))
    check(method .. ' nil response is handled directly', response == nil and type(responseError) == 'string')
end
f = fixture()
f.noResponse = 'GetBoundingPointsForShape'
result, reason = f.sweep.getGeometry(f.player, f.asset)
check('geometry nil response is handled directly', result == nil and type(reason) == 'string')
f = fixture()
geometry = f.sweep.getGeometry(f.player, f.asset)
pose = f.sweep.getPose(f.weapon, geometry)
f.noResponse = 'BoxTraceMultiByProfile'
result, reason = f.sweep.collectContacts(f.player, pose, pose, 0.02)
check('sweep nil response is handled directly', result == nil and type(reason) == 'string')

local ok = #failures == 0
print('Melee regression checks: ' .. #checks .. '; failures: ' .. #failures)
return {ok = ok, checks = checks, failures = failures}
