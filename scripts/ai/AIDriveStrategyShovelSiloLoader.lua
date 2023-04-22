--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2022 

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

---@class AIDriveStrategyShovelSiloLoader : AIDriveStrategyCourse
---@field shovelController ShovelController
AIDriveStrategyShovelSiloLoader = {}
local AIDriveStrategyShovelSiloLoader_mt = Class(AIDriveStrategyShovelSiloLoader, AIDriveStrategyCourse)

----------------------------------------------------------------
--- State properties
----------------------------------------------------------------
--[[
    shovelPosition : number (1-4)
    shovelMovingSpeed : number|nil speed while the shovel/ front loader is moving
]]


----------------------------------------------------------------
--- States
----------------------------------------------------------------

AIDriveStrategyShovelSiloLoader.myStates = {
    DRIVING_ALIGNMENT_COURSE = {shovelPosition = ShovelController.POSITIONS.TRANSPORT},
    DRIVING_INTO_SILO = {shovelPosition = ShovelController.POSITIONS.LOADING, shovelMovingSpeed = 0},
    DRIVING_OUT_OF_SILO = {shovelPosition = ShovelController.POSITIONS.TRANSPORT},
    WAITING_FOR_TRAILER = {shovelPosition = ShovelController.POSITIONS.TRANSPORT},
    DRIVING_TO_TRAILER = {shovelPosition = ShovelController.POSITIONS.TRANSPORT},
    DRIVING_TO_UNLOAD = {shovelPosition = ShovelController.POSITIONS.PRE_UNLOADING, shovelMovingSpeed = 0},
    UNLOADING = {shovelPosition = ShovelController.POSITIONS.UNLOADING, shovelMovingSpeed = 0},
}

AIDriveStrategyShovelSiloLoader.safeSpaceToTrailer = 5
AIDriveStrategyShovelSiloLoader.maxValidTrailerDistance = 30

function AIDriveStrategyShovelSiloLoader.new(customMt)
    if customMt == nil then
        customMt = AIDriveStrategyShovelSiloLoader_mt
    end
    local self = AIDriveStrategyCourse.new(customMt)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyShovelSiloLoader.myStates)
    self.state = self.states.DRIVING_INTO_SILO
    return self
end

function AIDriveStrategyShovelSiloLoader:delete()
    AIDriveStrategyShovelSiloLoader:superClass().delete(self)
    if self.siloController then 
        self.siloController:delete()
        self.siloController = nil
    end
    CpUtil.destroyNode(self.heapNode)
    CpUtil.destroyNode(self.unloadNode)
end

function AIDriveStrategyShovelSiloLoader:getGeneratedCourse(jobParameters)
    return nil
end

function AIDriveStrategyShovelSiloLoader:setSiloAndHeap(bunkerSilo, heapSilo)
    self.bunkerSilo = bunkerSilo
    self.heapSilo = heapSilo
end

function AIDriveStrategyShovelSiloLoader:startWithoutCourse(jobParameters)
 
    -- to always have a valid course (for the traffic conflict detector mainly)
    self.course = Course.createStraightForwardCourse(self.vehicle, 25)
    self:startCourse(self.course, 1)

    self.jobParameters = jobParameters

    if self.bunkerSilo ~= nil then 
        self:debug("Bunker silo was found.")
        self.silo = self.bunkerSilo
    else 
        self:debug("Heap was found.")
        self.silo = self.heapSilo
    end

    self.siloController = CpBunkerSiloLoaderController(self.silo, self.vehicle, self)
    
    if self.shovelController:isFull() then
        self.state = self.states.WAITING_FOR_TRAILER
    else
        self:startDrivingToSilo()
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Implement handling
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyShovelSiloLoader:initializeImplementControllers(vehicle)
    self:addImplementController(vehicle, MotorController, Motorized, {}, nil)
    self:addImplementController(vehicle, WearableController, Wearable, {}, nil)

    self.shovelImplement, self.shovelController = self:addImplementController(vehicle, ShovelController, Shovel, {}, nil)

    self.siloEndProximitySensor = SingleForwardLookingProximitySensorPack(self.vehicle, self.shovelController:getShovelNode(), 5, 1)
end

--- Fuel save only allowed when no trailer is there to unload into.
function AIDriveStrategyShovelSiloLoader:isFuelSaveAllowed()
    return self.state == self.states.WAITING_FOR_TRAILER
end

-----------------------------------------------------------------------------------------------------------------------
--- Static parameters (won't change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyShovelSiloLoader:setAllStaticParameters()
    AIDriveStrategyShovelSiloLoader:superClass().setAllStaticParameters(self)
    self:setFrontAndBackMarkers()

    self.heapNode = CpUtil.createNode("heapNode", 0, 0, 0, nil)
    self.unloadNode = CpUtil.createNode("unloadNode", 0, 0, 0, nil)
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyShovelSiloLoader:onWaypointPassed(ix, course)
    if course:isLastWaypointIx(ix) then
        if self.state == self.states.DRIVING_ALIGNMENT_COURSE then 
            local course = self:getRememberedCourseAndIx()
            self:startCourse(course, 1)
            self.state = self.states.DRIVING_INTO_SILO
        elseif self.state == self.states.DRIVING_INTO_SILO then

            local startPos, endPos = self.siloController:getLastTarget()
            local x, z = unpack(endPos)
            local dx, dz = unpack(startPos)

            local reverseCourse = Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz, 
                0, 0, 3, 3, true)
            self:startCourse(reverseCourse, 1)
            self.state = self.states.DRIVING_OUT_OF_SILO
        elseif self.state == self.states.DRIVING_OUT_OF_SILO then
            self.state = self.states.WAITING_FOR_TRAILER
        elseif self.state == self.states.DRIVING_TO_TRAILER then
            local course = Course.createFromNodeToNode(self.vehicle, self.vehicle:getAIDirectionNode(), self.unloadNode, 
                0, 0, 0, 3, false)
            self:startCourse(course, 1)

            self.state = self.states.DRIVING_TO_UNLOAD
        elseif self.state == self.states.DRIVING_TO_UNLOAD then
            self.state = self.states.UNLOADING
          

            --self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
        end
    end
end

--- this the part doing the actual work on the field after/before all
--- implements are started/lowered etc.
function AIDriveStrategyShovelSiloLoader:getDriveData(dt, vX, vY, vZ)
    self:updateLowFrequencyImplementControllers()

    local moveForwards = not self.ppc:isReversing()
    local gx, gz

    ----------------------------------------------------------------
    if not moveForwards then
        local maxSpeed
        gx, gz, maxSpeed = self:getReverseDriveData()
        self:setMaxSpeed(maxSpeed)
    else
        gx, _, gz = self.ppc:getGoalPointPosition()
    end
    if self.state == self.states.DRIVING_ALIGNMENT_COURSE then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    elseif self.state == self.states.WAITING_FOR_PATHFINDER then 
        self:setMaxSpeed(0)
    elseif self.state == self.states.DRIVING_INTO_SILO then 
        self:setMaxSpeed(self.settings.bunkerSiloSpeed:getValue())

        local _, _, closestObject = self.siloEndProximitySensor:getClosestObjectDistanceAndRootVehicle()
        local isEndReached, maxSpeed = self.siloController:isEndReached(self.shovelController:getShovelNode(), 0)
        if self.silo:isTheSameSilo(closestObject) or isEndReached then
            self:debug("End wall detected or bunker silo end is reached.")
            self.state = self.states.DRIVING_OUT_OF_SILO
        end
        if self.shovelController:isFull() then 
            self:debug("Shovel is full, starting to drive out of the silo.")
            self.state = self.states.DRIVING_OUT_OF_SILO
        end

    elseif self.state == self.states.DRIVING_OUT_OF_SILO then 
        self:setMaxSpeed(self.settings.bunkerSiloSpeed:getValue())

    elseif self.state == self.states.WAITING_FOR_TRAILER then 
        self:setMaxSpeed(0)
        self:searchForTrailerToUnloadInto()
    elseif self.state == self.states.DRIVING_TO_TRAILER then 
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    elseif self.state == self.states.DRIVING_TO_UNLOAD then
        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
        if self.shovelController:isShovelOverTrailer(self.targetTrailer.trailer) then 
            self.state = self.states.UNLOADING     
        end
    elseif self.state == self.states.UNLOADING then 
        self:setMaxSpeed(0)
        if self:hasFinishedUnloading() then 
            self:startDrivingToSilo()
        end
    end
    if self.state.properties.shovelPosition then 
        if not self.frozen and self.shovelController:moveShovelToPosition(self.state.properties.shovelPosition) then 
            if self.state.properties.shovelMovingSpeed ~= nil then 
                self:setMaxSpeed(self.state.properties.shovelMovingSpeed)
            end
        end
    end

    self:limitSpeed()
    return gx, gz, moveForwards, self.maxSpeed, 100
end

function AIDriveStrategyShovelSiloLoader:update(dt)
    AIDriveStrategyCourse.update(self)
    self:updateImplementControllers(dt)
    if CpDebug:isChannelActive(CpDebug.DBG_SILO, self.vehicle) then
        if self.course:isTemporary() then
            self.course:draw()
        elseif self.ppc:getCourse():isTemporary() then
            self.ppc:getCourse():draw()
        end
        if self.silo then 
            self.silo:drawDebug()
        end
        if self.heapSilo then 
            CpUtil.drawDebugNode(self.heapNode, false, 3)
        end
        if self.targetTrailer then 
            CpUtil.drawDebugNode(self.unloadNode, false, 3)
            CpUtil.drawDebugNode(self.targetTrailer.exactFillRootNode, false, 3, "ExactFillRootNode")
        end
    end
end

----------------------------------------------------------------
--- Pathfinding
----------------------------------------------------------------

--- Find an alignment path to the heap course.
---@param course table heap course
function AIDriveStrategyShovelSiloLoader:startPathfindingToStart(course)
    if not self.pathfinder or not self.pathfinder:isActive() then
        self.state = self.states.WAITING_FOR_PATHFINDER
        self:rememberCourse(course, 1)

        self.pathfindingStartedAt = g_currentMission.time
        local done, path
        local fm = self:getFrontAndBackMarkers()
        self.pathfinder, done, path = PathfinderUtil.startPathfindingFromVehicleToWaypoint(
            self.vehicle, course, 1, 0, -(fm + 4),
            true, nil)
        if done then
            return self:onPathfindingDoneToStart(path)
        else
            self:setPathfindingDoneCallback(self, self.onPathfindingDoneToStart)
        end
    else
        self:debug('Pathfinder already active')
    end
    return true
end

function AIDriveStrategyShovelSiloLoader:onPathfindingDoneToStart(path)
    if path and #path > 2 then
        self:debug("Found alignment path to the course for the heap.")
        local alignmentCourse = Course(self.vehicle, CourseGenerator.pointsToXzInPlace(path), true)
        self:startCourse(alignmentCourse, 1)
        self.state = self.states.DRIVING_ALIGNMENT_COURSE
    else 
        local course = self:getRememberedCourseAndIx()
        self:debug("No alignment path found!")
        self:startCourse(course, 1)
        self.state = self.states.DRIVING_INTO_SILO
    end
end

function AIDriveStrategyShovelSiloLoader:searchForTrailerToUnloadInto()
    self:debugSparse("Searching for an trailer nearby.")
    for i, vehicle in pairs(g_currentMission.vehicles) do 
        if SpecializationUtil.hasSpecialization(vehicle, Trailer) then 
            local rootVehicle = vehicle.rootVehicle
            local cx, cz = self.silo:getFrontCenter()
            local vx, _, vz = getWorldTranslation(vehicle)
            local distanceToFrontSiloCenter = MathUtil.vector2Length(cx - vx, cz - vz)
            if rootVehicle and AIUtil.isStopped(rootVehicle) and distanceToFrontSiloCenter <= self.maxValidTrailerDistance then 
                local canLoad, fillUnitIndex, fillType, exactFillRootNode = 
                    ImplementUtil.getCanLoadTo(vehicle, self.shovelImplement) 
                if canLoad and exactFillRootNode ~= nil then 
                    self.targetTrailer = {
                        fillUnitIndex = fillUnitIndex,
                        fillType = fillType,
                        exactFillRootNode = exactFillRootNode,
                        trailer = vehicle
                    }
                    self:debug("Found valid trailer %s attached to %s with a distance of %.2fm to the silo front center for fill type %s in fill unit %d.", 
                        CpUtil.getName(vehicle), CpUtil.getName(vehicle.rootVehicle),
                        self.maxValidTrailerDistance, g_fillTypeManager:getFillTypeTitleByIndex(fillType), fillUnitIndex)
                    self:startPathfindingToTrailer(vehicle, exactFillRootNode)
                    return
                end
            end
        end
    end
end


--- Find an alignment path to the heap course.
function AIDriveStrategyShovelSiloLoader:startPathfindingToTrailer(trailer, exactFillRootNode)
    if not self.pathfinder or not self.pathfinder:isActive() then
        self.state = self.states.WAITING_FOR_PATHFINDER
        local dx, _, _ = localToLocal(self.shovelController:getShovelNode(), trailer, 0, 0, 0)

        local loadingLeftSide = dx > 0

        local x, y, z = localToLocal(exactFillRootNode, trailer.rootNode, 0, 0, 0)

        local gx, gy, gz = localToWorld(trailer.rootNode, x, y, z)
        local dirX, dirZ = localDirectionToWorld(trailer.rootNode, loadingLeftSide and 1 or -1, 0, 0)
        local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
        setTranslation(self.unloadNode, gx, gy, gz)
        setRotation(self.unloadNode, 0, yRot, 0)

        local spaceToTrailer = math.max(self.turningRadius, self.safeSpaceToTrailer)

        self.pathfindingStartedAt = g_currentMission.time
        local done, path, goalNodeInvalid
        self.pathfinder, done, path, goalNodeInvalid = PathfinderUtil.startPathfindingFromVehicleToNode(
            self.vehicle, self.unloadNode,
            0, -spaceToTrailer, true,
            nil, {}, nil,
            0, nil, true
        )
        if done then
            return self:onPathfindingDoneToTrailer(path, goalNodeInvalid)
        else
            self:setPathfindingDoneCallback(self, self.onPathfindingDoneToTrailer)
        end
    else
        self:debug('Pathfinder already active')
    end
    return true
end

function AIDriveStrategyShovelSiloLoader:onPathfindingDoneToTrailer(path, goalNodeInvalid)
    if path and #path > 2 then
        self:debug("Found alignment path to the course for the silo.")
        local alignmentCourse = Course(self.vehicle, CourseGenerator.pointsToXzInPlace(path), true)
        
        self:startCourse(alignmentCourse, 1)
        self.state = self.states.DRIVING_TO_TRAILER
    else 
        self:debug("No alignment path found, starting with silo course!")
        local course = self:getRememberedCourseAndIx()
        self:startCourse(course, 1)
    end
end

----------------------------------------------------------------
--- Silo work
----------------------------------------------------------------

function AIDriveStrategyShovelSiloLoader:startDrivingToSilo()
    if self.silo:getTotalFillLevel() <=0 then 
        self:debug("Stopping the driver, as the silo is empty.")
        self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
        return
    end


    local startPos, endPos = self.siloController:getTarget(self:getWorkWidth())
    local x, z = unpack(startPos)
    local dx, dz = unpack(endPos)

    local siloCourse = Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz, 
        0, 0, 3, 3, false)


    local distance = siloCourse:getDistanceBetweenVehicleAndWaypoint(self.vehicle, 1)

    if distance > 2 * self.turningRadius then
        self:debug("Start driving to silo with pathfinder.")
        self:startPathfindingToStart(siloCourse)
    else
        self:debug("Start driving into the silo.")
        self:startCourse(siloCourse, 1)
        self.state = self.states.DRIVING_INTO_SILO
    end
end

function AIDriveStrategyShovelSiloLoader:getWorkWidth()
    return self.settings.bunkerSiloWorkWidth:getValue()
end

----------------------------------------------------------------
--- Unloading
----------------------------------------------------------------
function AIDriveStrategyShovelSiloLoader:hasFinishedUnloading()
    if self.targetTrailer.trailer:getFillUnitFreeCapacity(self.targetTrailer.fillUnitIndex) <= 0 then 
        self:debug("Trailer is full, abort unloading into trailer %s.", CpUtil.getName(self.targetTrailer.trailer))
        return true
    end
    if self.shovelController:isEmpty() then 
        self:debug("Finished unloading, as the shovel is empty.")
        return true
    end

    return false
end

