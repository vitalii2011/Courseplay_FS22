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
		SHOVEL_ANGLE = 90,
		ARM_MIN = 0.1,
		ARM_MAX = 0.25,
	},
	TRANSPORT_POSITION = {
		SHOVEL_ANGLE = 55,
		ARM_MIN = 1.1,
		ARM_MAX = 1.2,
	},
	PRE_UNLOAD_POSITION = {
		SHOVEL_ANGLE = 45,
		ARM_MIN = 3,
		ARM_MAX = 4,
	},
	UNLOADING_POSITION = {
		ARM_MIN = 3,
		ARM_MAX = 4,
	},

	LOADING_SHOVEL_ANGLE = 90,
	TRANSPORT_SHOVEL_ANGLE = 55,
	PRE_UNLOADING_ANGLE = 45,
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
end

--- Deactivates the shovel position control.
function CpShovelPositions:cpResetShovelState()
	CpUtil.infoImplement(self, "Reset shovelPositionState.")
	local spec = self.spec_cpShovelPositions
	spec.state = CpShovelPositions.DEACTIVATED
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
					elseif tool.axis == "AXIS_FRONTLOADER_TOOL" then 
						spec.shovelToolIx = i
						spec.shovelTool = tool
						spec.shovelVehicle = vehicle
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
function CpShovelPositions.setShovelPosition(spec, shovel, angle, max, min)
	local dir = MathUtil.sign(angle-math.rad(max))
	local diff = math.abs(angle-math.rad(max))
	local isDirty = false
	if max and math.deg(angle) > max then 
		isDirty = true
	elseif min and math.deg(angle)  < min then
		isDirty = true
	else 
		Cylindered.actionEventInput(spec.shovelVehicle, "", 0, spec.shovelToolIx, true)
	end
	if isDirty then 
		Cylindered.actionEventInput(spec.shovelVehicle, "", dir*diff*2, spec.shovelToolIx, true)
		CpUtil.infoImplement(shovel, "Shovel position(%d) angle: %.2f, diff: %.2f, dir: %d", spec.state, math.deg(angle), diff, dir)
	end
	return isDirty
end

--- Changes the front loader angle dependent on the selected position, relative to a target height.
function CpShovelPositions.setArmPosition(spec, shovel, shovelNode, height)
	local min, max = unpack(height)
	local x, y, z = getWorldTranslation(shovelNode)
	local dy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
	local dir = -MathUtil.sign(y-dy - min)
	local diff = math.abs(y-dy - min)
	local isDirty = false
	if max and y-dy > max then 
		isDirty = true
	elseif min and y-dy < min then
		isDirty = true
	else 
		Cylindered.actionEventInput(spec.armVehicle, "", 0, spec.armToolIx, true)
	end
	if isDirty then 
		Cylindered.actionEventInput(spec.armVehicle, "", dir * diff, spec.armToolIx, true)
		CpUtil.infoImplement(shovel, "Arm position(%d) height diff: %.2f, dir: %d", spec.state, diff, dir)
	end
	return isDirty
end

function CpShovelPositions:updateLoadingPosition(dt)
	local spec = self.spec_cpShovelPositions
	local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle then 
		local isDirtyArm = CpShovelPositions.setArmPosition(spec, self, shovelNode, {CpShovelPositions.LOADING_POSITION.ARM_MIN, CpShovelPositions.LOADING_POSITION.ARM_MAX})
		isDirty = isDirtyArm or CpShovelPositions.setShovelPosition(spec, self, angle, CpShovelPositions.LOADING_POSITION.SHOVEL_ANGLE + 1 , CpShovelPositions.LOADING_POSITION.SHOVEL_ANGLE - 1)
	end
	self.isDirty = isDirty
end

function CpShovelPositions:updateTransportPosition(dt)
	local spec = self.spec_cpShovelPositions
	local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle then 
		local isDirtyArm = CpShovelPositions.setArmPosition(spec, self, shovelNode, {CpShovelPositions.TRANSPORT_POSITION.ARM_MIN, CpShovelPositions.TRANSPORT_POSITION.ARM_MAX})
		isDirty = isDirtyArm or CpShovelPositions.setShovelPosition(spec, self, angle, CpShovelPositions.TRANSPORT_POSITION.SHOVEL_ANGLE + 1, CpShovelPositions.TRANSPORT_POSITION.SHOVEL_ANGLE - 1)
	end
	self.isDirty = isDirty
end

function CpShovelPositions:updatePreUnloadPosition(dt)
	self:cpSearchForShovelUnloadingObjectRaycast()
	local spec = self.spec_cpShovelPositions
	local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle then 
		local isDirtyArm = CpShovelPositions.setArmPosition(spec, self, shovelNode, self:getCpShovelUnloadingPositionHeight())
		isDirty = isDirtyArm or CpShovelPositions.setShovelPosition(spec, self, angle, CpShovelPositions.PRE_UNLOAD_POSITION.SHOVEL_ANGLE + 1, CpShovelPositions.PRE_UNLOAD_POSITION.SHOVEL_ANGLE - 1)
	end
	self.isDirty = isDirty
end

function CpShovelPositions:updateUnloadingPosition(dt)
	self:cpSearchForShovelUnloadingObjectRaycast()
	local spec = self.spec_cpShovelPositions
	local angle, shovelNode, maxAngle, minAngle, factor = CpShovelPositions.getShovelData(self)
	local isDirty
	if angle then 
		
		local isDirtyArm = CpShovelPositions.setArmPosition(spec, self, shovelNode, self:getCpShovelUnloadingPositionHeight())
		isDirty = isDirtyArm or  CpShovelPositions.setShovelPosition(spec, self, angle, math.deg(maxAngle)+2, math.deg(maxAngle))
	end
	self.isDirty = isDirty
end

function CpShovelPositions:getCpShovelUnloadingPositionHeight()
	return {CpShovelPositions.PRE_UNLOAD_POSITION.ARM_MIN, CpShovelPositions.PRE_UNLOAD_POSITION.ARM_MAX}
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