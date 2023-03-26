--[[
	This specialization is used to control the shovel position into 4 stages:
		- Loading position 0.2m above the ground.
		- Transport position 
		- Pre unloading position
		- Unloading position

	TODO: 
		- Fine tuning
		- Testing from different front loaders ...
		- Add Telescopic handlers support.
]]--

---@class CpShovelPositions
CpShovelPositions = {
	DEACTIVATED = 0,
	LOADING = 1,
	TRANSPORT = 2,
	PRE_UNLOAD = 3,
	UNLOADING = 4,
	NUM_STATES = 4,
	LOADING_POSITION = {
		ARM_LIMITS = {
			0.1,
			0.20
		},
		SHOVEL_LIMITS = {
			92,
			94
		},
	},
	TRANSPORT_POSITION = {
		ARM_LIMITS = {
			0.1,
			0.20
		},
		SHOVEL_LIMITS = {
			54,
			56
		},
	},
	PRE_UNLOAD_POSITION = {
		ARM_LIMITS = {
			3,
			4
		},
		SHOVEL_LIMITS = {
			44,
			46
		},
	},
	UNLOADING_POSITION = {
		ARM_LIMITS = {
			4,
			5
		},
	},
	RAYCAST_DISTANCE = 10,
	MAX_RAYCAST_OFFSET = 6,
	RAYCAST_OFFSET_HEIGHT = 8,
	DEBUG = true
}
CpShovelPositions.MOD_NAME = g_currentModName
CpShovelPositions.NAME = ".cpShovelPositions"
CpShovelPositions.SPEC_NAME = CpShovelPositions.MOD_NAME .. CpShovelPositions.NAME
CpShovelPositions.KEY = "." .. CpShovelPositions.SPEC_NAME

function CpShovelPositions.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
	if CpShovelPositions.DEBUG then 
		g_devHelper.consoleCommands:registerConsoleCommand('cpSetShovelState', 'cpSetShovelState', 'consoleCommandSetShovelState', CpShovelPositions)
	end
end

function CpShovelPositions.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Shovel, specializations) and not 
		SpecializationUtil.hasSpecialization(Trailer, specializations) and not 
		SpecializationUtil.hasSpecialization(ConveyorBelt, specializations)
end

function CpShovelPositions.register(typeManager, typeName, specializations)
	if CpShovelPositions.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpShovelPositions.SPEC_NAME)
	end
end

function CpShovelPositions.registerEventListeners(vehicleType)	
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpShovelPositions)
	SpecializationUtil.registerEventListener(vehicleType, "onDraw", CpShovelPositions)	
	SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", CpShovelPositions)
end

function CpShovelPositions.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "cpSetShovelState", CpShovelPositions.cpSetShovelState)
    SpecializationUtil.registerFunction(vehicleType, "cpResetShovelState", CpShovelPositions.cpResetShovelState)
	SpecializationUtil.registerFunction(vehicleType, "cpSetupShovelPositions", CpShovelPositions.cpSetupShovelPositions)
	SpecializationUtil.registerFunction(vehicleType, "areCpShovelPositionsDirty", CpShovelPositions.areCpShovelPositionsDirty)
	SpecializationUtil.registerFunction(vehicleType, "getCpShovelUnloadingPositionHeight", CpShovelPositions.getCpShovelUnloadingPositionHeight)
	SpecializationUtil.registerFunction(vehicleType, "isCpShovelUnloadingRaycastAllowed", CpShovelPositions.isCpShovelUnloadingRaycastAllowed)
	SpecializationUtil.registerFunction(vehicleType, "cpSearchForShovelUnloadingObjectRaycast", CpShovelPositions.cpSearchForShovelUnloadingObjectRaycast)
	SpecializationUtil.registerFunction(vehicleType, "cpShovelUnloadingRaycastCallback", CpShovelPositions.cpShovelUnloadingRaycastCallback)
	
end


function CpShovelPositions:onLoad(savegame)
	--- Register the spec: spec_ShovelPositions
    self.spec_cpShovelPositions = self["spec_" .. CpShovelPositions.SPEC_NAME]
    local spec = self.spec_cpShovelPositions
	--- Current shovel state.
	spec.state = CpShovelPositions.DEACTIVATED
end

function CpShovelPositions:onDraw()
	if CpShovelPositions.DEBUG and self:getRootVehicle() then 
		local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
		if shovelNode then
			DebugUtil.drawDebugNode(shovelNode, "shovelNode")
		end
	end
end

function CpShovelPositions:consoleCommandSetShovelState(state)
	local vehicle = g_currentMission.controlledVehicle
	if not vehicle then 
		CpUtil.info("Not entered a valid vehicle!")
	end
	state = tonumber(state)
	if state == nil or state < 0 or state > CpShovelPositions.NUM_STATES then 
		CpUtil.infoVehicle(vehicle, "No valid state(0 - %d) was given!", CpShovelPositions.NUM_STATES)
		return
	end
	if not vehicle:getIsAIActive() then 
		local shovels, found = AIUtil.getAllChildVehiclesWithSpecialization(vehicle, Shovel)
		if found then 
			shovels[1]:cpSetShovelState(state)
		else 
			CpUtil.infoVehicle(vehicle, "No valid vehicle/implement with a shovel was found!")
		end
	else 
		CpUtil.infoVehicle(vehicle, "Error, AI is active!")
	end
end

--- Changes the current shovel state position.
function CpShovelPositions:cpSetShovelState(state)
	CpUtil.infoImplement(self, "Changed shovelPositionState to %d.", state)
	local spec = self.spec_cpShovelPositions
	spec.state = state
	CpShovelPositions.cpSetupShovelPositions(self)
	if state == CpShovelPositions.DEACTIVATED then 
		ImplementUtil.stopMovingTool(spec.armVehicle, spec.armTool)
		ImplementUtil.stopMovingTool(spec.shovelVehicle, spec.shovelTool)
	end
end

--- Deactivates the shovel position control.
function CpShovelPositions:cpResetShovelState()
	CpUtil.infoImplement(self, "Reset shovelPositionState.")
	local spec = self.spec_cpShovelPositions
	spec.state = CpShovelPositions.DEACTIVATED
	ImplementUtil.stopMovingTool(spec.armVehicle, spec.armTool)
	ImplementUtil.stopMovingTool(spec.shovelVehicle, spec.shovelTool)
end

function CpShovelPositions:areCpShovelPositionsDirty()
	local spec = self.spec_cpShovelPositions
	return spec.isDirty
end

--- Sets the relevant moving tools.
function CpShovelPositions:cpSetupShovelPositions()
	local spec = self.spec_cpShovelPositions
	spec.shovelToolIx = nil
	spec.armToolIx = nil
	spec.shovelTool = nil
	spec.armTool = nil
	local rootVehicle = self:getRootVehicle()
	local childVehicles = rootVehicle:getChildVehicles()
	for _, vehicle in ipairs(childVehicles) do
		if vehicle.spec_cylindered then
			for i, tool in pairs(vehicle.spec_cylindered.movingTools) do
				if tool.controlGroupIndex ~= nil then 
					if tool.axis == "AXIS_FRONTLOADER_ARM" then 
						spec.armToolIx = i
						spec.armTool = tool
						spec.armVehicle = vehicle
						spec.armProjectionNode = CpUtil.createNode("CpShovelArmProjectionNode", 
							0, 0, 0, getParent(tool.node))
					elseif tool.axis == "AXIS_FRONTLOADER_TOOL" then 
						spec.shovelToolIx = i
						spec.shovelTool = tool
						spec.shovelVehicle = vehicle
						spec.shovelProjectionNode = CpUtil.createNode("CpShovelProjectionNode", 
							0, 0, 0, getParent(tool.node))
					end
				end
			end
		end
	end
end

function CpShovelPositions:onUpdateTick(dt)
	local spec = self.spec_cpShovelPositions
	if spec.shovelToolIx == nil or  spec.armToolIx == nil then 
		return
	end
	if spec.state == CpShovelPositions.LOADING then 
		CpShovelPositions.updateLoadingPosition(self, dt)
	elseif spec.state == CpShovelPositions.TRANSPORT then 
		CpShovelPositions.updateTransportPosition(self, dt)
	elseif spec.state == CpShovelPositions.PRE_UNLOAD then 
		CpShovelPositions.updatePreUnloadPosition(self, dt)
	elseif spec.state == CpShovelPositions.UNLOADING then 
		CpShovelPositions.updateUnloadingPosition(self, dt)
	end
end

--- Changes the shovel angle dependent on the selected position.
function CpShovelPositions.setShovelPosition(dt, spec, shovel, shovelNode, angle, limits)
	local min, max = unpack(limits)
	local targetAngle = math.rad(min) + math.rad(max - min)/2
	if math.deg(angle) < max and  math.deg(angle) > min  then 
		ImplementUtil.stopMovingTool(spec.shovelVehicle, spec.shovelTool)
		return false
	end
	

	local curRot = {}
	curRot[1], curRot[2], curRot[3] = getRotation(spec.shovelTool.node)
	local oldRot = curRot[spec.shovelTool.rotationAxis]
	local radius = calcDistanceFrom(shovelNode, spec.shovelTool.node)
	local x, y, z = getTranslation(spec.shovelTool.node)

	setTranslation(spec.shovelProjectionNode, x, y, z)

	setRotation(spec.shovelProjectionNode, targetAngle - math.pi/2, 0, 0)

	local sx, sy, sz = getWorldTranslation(shovelNode)
	local tx, _, tz = getWorldTranslation(spec.shovelTool.node)
	local px, py, pz = localToWorld(spec.shovelProjectionNode, 0, 0, radius)
	
	DebugUtil.drawDebugCircleAtNode(spec.shovelTool.node, radius, 30, nil, true)

	DebugUtil.drawDebugLine(px, py, pz, sx, sy, sz)
	DebugUtil.drawDebugLine(px, py, pz, tx, py, tz)
	

	local yRot = math.atan2(MathUtil.vector3Length(px - sx, py - sy, pz - sz),
	MathUtil.vector3Length(px - tx, py - py, pz - tz))

	local dyRot = 0
	if angle > targetAngle then 
		dyRot = -yRot
	else 
		dyRot = yRot
	end
	
	CpUtil.infoImplement(shovel, 
		"Shovel position(%d) angle: %.2f, targetAngle: %.2f, yRot: %.2f, oldRot: %.2f", 
		spec.state, math.deg(angle), math.deg(targetAngle), math.deg(yRot), math.deg(oldRot)) 

	return ImplementUtil.moveMovingToolToRotation(spec.shovelVehicle, spec.shovelTool, dt, 
		MathUtil.clamp(oldRot + dyRot , spec.shovelTool.rotMin, spec.shovelTool.rotMax))
end

--- Changes the front loader angle dependent on the selected position, relative to a target height.
function CpShovelPositions.setArmPosition(dt, spec, shovel, shovelNode, limits)
	--- Interval in which the shovel height should be in.
	local min, max = unpack(limits)
	local x, y, z = getWorldTranslation(spec.shovelTool.node)
	local dy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
	local height = y - dy 
	local targetHeight = min + (max - min)/2
	local diff = height - (min + (max - min)/2)
	
	if height < max and height > min then 
		ImplementUtil.stopMovingTool(spec.armVehicle, spec.armTool)
		return false
	end

	local curRot = {}
	curRot[1], curRot[2], curRot[3] = getRotation(spec.armTool.node)
	local oldRot = curRot[spec.armTool.rotationAxis]
	local radius = calcDistanceFrom(spec.armTool.node, spec.shovelTool.node)

	local _, ay, _ = localToLocal(spec.armTool.node, spec.armVehicle.rootNode, 0, 0, 0)

	local nodeDiff = MathUtil.clamp( targetHeight - ay , -radius, radius) + ay

	local ax, _, az = getWorldTranslation(spec.armTool.node)
	local sx, sy, sz = getWorldTranslation(spec.shovelTool.node)
	local _, py, _ = localToWorld(spec.armVehicle.rootNode, 0, nodeDiff, 0)
	local px, pz = sx, sz

	setWorldTranslation(spec.armProjectionNode, px, py, pz)

	DebugUtil.drawDebugCircleAtNode(spec.armTool.node, radius, 30, nil, true)

	DebugUtil.drawDebugNode(spec.armProjectionNode, "Projection node", false, 0)

	DebugUtil.drawDebugLine(px, py, pz, sx, sy, sz)
	DebugUtil.drawDebugLine(px, py, pz, ax, py, az) -- y
	
	local yRot = math.atan2(MathUtil.vector3Length(px - sx, py - sy, pz - sz),
		MathUtil.vector3Length(px - ax, py - py, pz - az))

	if height > targetHeight then 
		yRot = yRot
	else 
		yRot = -yRot
	end
	
	CpUtil.infoImplement(shovel, 
		"Arm position(%d) height diff: %.2f, targetHeight: %.2f, old angle: %.2f, yRot: %.2f",
		spec.state, diff, targetHeight,  math.deg(oldRot),  math.deg(yRot))

	return ImplementUtil.moveMovingToolToRotation(spec.armVehicle, spec.armTool, dt, 
		MathUtil.clamp(oldRot + yRot , spec.armTool.rotMin, spec.armTool.rotMax))
end

function CpShovelPositions:updateLoadingPosition(dt)
	local spec = self.spec_cpShovelPositions
	local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle then 
		local isDirtyArm = CpShovelPositions.setArmPosition(dt, spec, self, shovelNode, CpShovelPositions.LOADING_POSITION.ARM_LIMITS)
		isDirty = isDirtyArm or CpShovelPositions.setShovelPosition(dt, spec, self, shovelNode, angle, CpShovelPositions.LOADING_POSITION.SHOVEL_LIMITS)
	end
	self.isDirty = isDirty
end

function CpShovelPositions:updateTransportPosition(dt)
	local spec = self.spec_cpShovelPositions
	local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle then 
		local isDirtyArm = CpShovelPositions.setArmPosition(dt, spec, self, shovelNode, CpShovelPositions.TRANSPORT_POSITION.ARM_LIMITS)
		isDirty = isDirtyArm or CpShovelPositions.setShovelPosition(dt, spec, self, shovelNode, angle, CpShovelPositions.TRANSPORT_POSITION.SHOVEL_LIMITS)
	end
	self.isDirty = isDirty
end

function CpShovelPositions:updatePreUnloadPosition(dt)
	self:cpSearchForShovelUnloadingObjectRaycast()
	local spec = self.spec_cpShovelPositions
	local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle then 
		local isDirtyArm = CpShovelPositions.setArmPosition(dt, spec, self, shovelNode, self:getCpShovelUnloadingPositionHeight())
		isDirty = isDirtyArm or CpShovelPositions.setShovelPosition(dt, spec, self, shovelNode, angle, CpShovelPositions.PRE_UNLOAD_POSITION.SHOVEL_LIMITS)
	end
	self.isDirty = isDirty
end

function CpShovelPositions:updateUnloadingPosition(dt)
	self:cpSearchForShovelUnloadingObjectRaycast()
	local spec = self.spec_cpShovelPositions
	local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle and maxAngle then 
		
		local isDirtyArm = CpShovelPositions.setArmPosition(dt, spec, self, shovelNode, self:getCpShovelUnloadingPositionHeight())
		isDirty = isDirtyArm or  CpShovelPositions.setShovelPosition(dt, spec, self, shovelNode, angle, {math.deg(maxAngle), math.deg(maxAngle) + 1})
	end
	self.isDirty = isDirty
end

function CpShovelPositions:getCpShovelUnloadingPositionHeight()
	return CpShovelPositions.PRE_UNLOAD_POSITION.ARM_LIMITS
end

--- Gets all relevant shovel data.
function CpShovelPositions:getShovelData()
	local shovelSpec = self.spec_shovel
	if shovelSpec == nil then 
		CpUtil.infoImplement(self, "Shovel spec not found!")
		return 
	end
	local info = shovelSpec.shovelDischargeInfo
    if info == nil or info.node == nil then 
		CpUtil.infoImplement(self, "Info or node not found!")
		return 
	end
    if info.maxSpeedAngle == nil or info.minSpeedAngle == nil then
		CpUtil.infoImplement(self, "maxSpeedAngle or minSpeedAngle not found!")
		return 
	end

	if shovelSpec.shovelNodes == nil then 
		CpUtil.infoImplement(self, "Shovel nodes not found!")
		return 
	end

	if shovelSpec.shovelNodes[1] == nil then 
		CpUtil.infoImplement(self, "Shovel nodes index 0 not found!")
		return 
	end

	if shovelSpec.shovelNodes[1].node == nil then 
		CpUtil.infoImplement(self, "Shovel node not found!")
		return 
	end
	local _, dy, _ = localDirectionToWorld(info.node, 0, 0, 1)
	local angle = math.acos(dy)
	local factor = math.max(0, math.min(1, (angle - info.minSpeedAngle) / (info.maxSpeedAngle - info.minSpeedAngle)))
	return angle, shovelSpec.shovelNodes[1].node, info.maxSpeedAngle, info.minSpeedAngle, factor
end

function CpShovelPositions:isCpShovelUnloadingRaycastAllowed()
	return true
end

--- Searches for unloading targets.
function CpShovelPositions:cpSearchForShovelUnloadingObjectRaycast()
	local spec = self.spec_cpShovelPositions
	spec.currentObjectFound = nil
	if not self:isCpShovelUnloadingRaycastAllowed()then
		return
	end
	local rootVehicle = self:getRootVehicle()
	if rootVehicle == nil or rootVehicle.getAIDirectionNode == nil then 
		return
	end
	local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
	local node = rootVehicle:getAIDirectionNode()
	local dirX, _, dirZ = localDirectionToWorld(shovelNode, 0, 0, 1)
	local _, _, dz = localToLocal(shovelNode, node, 0, 0, 0)
	local dirY = -5
	for i=1, CpShovelPositions.MAX_RAYCAST_OFFSET do
		local x, y, z = localToWorld(node, 0, CpShovelPositions.RAYCAST_OFFSET_HEIGHT, i + dz)
		raycastAll(x, y, z, dirX, dirY, dirZ, "cpShovelUnloadingRaycastCallback", CpShovelPositions.RAYCAST_DISTANCE, self)
		DebugUtil.drawDebugLine(x, y, z, x+dirX*CpShovelPositions.RAYCAST_DISTANCE, y+dirY*CpShovelPositions.RAYCAST_DISTANCE, z+dirZ*CpShovelPositions.RAYCAST_DISTANCE, 1, 0, 0)
	end
end

--- Raycast callback for searching of trailers/triggers.
function CpShovelPositions:cpShovelUnloadingRaycastCallback(transformId, x, y, z, distance, nx, ny, nz, subShapeIndex, hitShapeId, isLast)
	local spec = self.spec_cpShovelPositions
	local object = g_currentMission:getNodeObject(transformId)
	local trigger = g_triggerManager:getUnloadTriggerForNode(transformId)
	--- Has the target already been hit ?
	if not self:isCpShovelUnloadingRaycastAllowed() then
		return false
	end
	if spec.currentObjectFound then 
		return false
	end
	local rootVehicle = self:getRootVehicle()
	if trigger and trigger.getFillUnitIndexFromNode then
		local fillUnitIndex = trigger:getFillUnitIndexFromNode(hitShapeId)
		local fillType = self:getDischargeFillType(self:getCurrentDischargeNode())
		if fillType ~= nil and fillUnitIndex ~= nil and trigger:getFillUnitSupportsToolTypeAndFillType(fillUnitIndex, ToolType.DISCHARGEABLE, fillType) then 
			if trigger:getIsFillAllowedFromFarm(rootVehicle:getActiveFarm()) then 
				CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "UnloadTrigger found!")
				spec.currentObjectFound = {
					object = trigger,
					fillUnitIndex = trigger:getFillUnitIndexFromNode(hitShapeId),
				}
				return true
			else 
				CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "Not allowed to unload into!")
			end
		else 
			CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "Fill type or tool type not supported!")
		end
	--is object a vehicle, trailer,...
	elseif object and object:isa(Vehicle) then 
		--check if the vehicle is stopped 
		local rootVehicle = object:getRootVehicle()
		if not AIUtil.isStopped(rootVehicle) then 
			return false
		end

		--object supports filltype, bassicly trailer and so on
		if object.getFillUnitSupportsToolType then
			for fillUnitIndex, fillUnit in pairs(object:getFillUnits()) do
				--object supports filling by shovel
				local allowedToFillByShovel = object:getFillUnitSupportsToolType(fillUnitIndex, ToolType.DISCHARGEABLE)	
				local fillType = self:getDischargeFillType(self:getCurrentDischargeNode())
				--object supports fillType
				local supportedFillType = object:getFillUnitSupportsFillType(fillUnitIndex,fillType)
				if allowedToFillByShovel then 
					CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "allowedToFillByShovel")
					if supportedFillType then 
						if object:getFillUnitFreeCapacity(fillUnitIndex, fillType, rootVehicle:getActiveFarm()) > 0 then 
							if object:getIsFillAllowedFromFarm(rootVehicle:getActiveFarm()) then 
								CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "valid trailer found!")
								spec.currentObjectFound = {
									object = object,
									fillUnitIndex = fillUnitIndex
								}
								return true
							else 
								CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "Not allowed to unload into!")
							end
						else 
							CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "No free capacity!")
						end
					else
						CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "not  supportedFillType")
					end
				else
					CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "not  allowedToFillByShovel")
				end
			end
		else
			CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "FillUnit not found!")
		end
	else 
		--CpUtil.debugVehicle(CpDebug.DBG_SILO, rootVehicle, "Nothing found!")
	end

	return false
end