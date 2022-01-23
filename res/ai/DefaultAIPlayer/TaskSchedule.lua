-- File: TaskSchedule
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
--require "SLF" -- load SFL.lua

ADSLOTSTATE_OK = 0
ADSLOTSTATE_INSUFFICIENT_AUDIENCE = 2
ADSLOTSTATE_SPOTPLAN_CHANGED = 4
ADSLOTSTATE_SPOTMAX_REACHED = 8
ADSLOTSTATE_TRAILERMAX_REACHED = 16
ADSLOTSTATE_NO_AD_FOUND = 32
ADSLOTSTATE_NO_TRAILER_FOUND = 64


_G["TaskSchedule"] = class(AITask, function(c)
	AITask.init(c)	-- must init base!
	c.Id = _G["TASK_SCHEDULE"]
	c.TargetRoom = TVT.ROOM_OFFICE_PLAYER_ME
	c.BudgetWeight = 0
	c.BasePriority = 10

	--no budget to spare
	c.RequiresBudgetHandling = false

	-- tables containing GUIDs on each entry (or none for an outage)
	c.currentProgrammeSlots = {}
	c.currentAdSlots = {}
	c.changedProgrammeSlots = {}
	c.changedAdSlots = {}

	-- states are bitmasks describing the state of the slot
	c.adSlotsState = {}
    for i=1, 24 do
		c.adSlotsState[i-1] = ADSLOTSTATE_OK
	end

	c.infoCache = {}
--	c.TodayMovieSchedule = {}
--	c.TomorrowMovieSchedule = {}
--	c.TodaySpotSchedule = {}
--	c.TomorrowSpotSchedule = {}
--	c.SpotInventory = {}
	c.SpotRequisition = {}
	c.Player = nil
	c.log = {}

	c.ScheduleTaskStartTime = 0
	c.JobStartTime = 0

	--we run more than one AdScheduleJob
	c.adScheduleJobIndex = 0
	c.lastScheduleHour = -1

	-- basic audience statistics
	-- this value can then be adjusted for each hour in a long term
    c.guessedAudienceAccuracyTotal = 0.25
    c.guessedAudienceAccuracyTotalCount = 0
    c.guessedAudienceAccuracyHourly = {}
    c.guessedAudienceAccuracyHourlyCount = {}
    for i=1, 24 do
		-- we start with some "basic assumptions"
		c.guessedAudienceAccuracyHourly[i] = c.guessedAudienceAccuracyTotal
		c.guessedAudienceAccuracyHourlyCount[i] = 1
    end

	c.ActivationTime = os.clock()
	c.TickCount = 0
	c.TickTimeGone = 0
	c.TickTimeMax = 0
end)



function TaskSchedule:typename()
	return "TaskSchedule"
end



--override to assign more ticks
function TaskSchedule:InitializeMaxTicks()
	AITask.InitializeMaxTicks(self) -- "." and "self" as param!

	local ticksRequired = 0
	--AnalyzeEnvironment
	ticksRequired = ticksRequired + 5
	--AnalyzeSchedule
	ticksRequired = ticksRequired + 5

	local slotsToCheck = 16
	local slotsPerTick = 3

	--programme
	ticksRequired = ticksRequired +  slotsToCheck / slotsPerTick + 2
	--ad requisitions (new ads
	ticksRequired = ticksRequired +  slotsToCheck / slotsPerTick + 2
	--ads
	ticksRequired = ticksRequired +  slotsToCheck / slotsPerTick + 2

	self.MaxTicks = math.max(self.MaxTicks, ticksRequired)
end



function TaskSchedule:Activate()
	self.ActivationTime = os.clock()

	self.AnalyzeEnvironmentJob = JobAnalyzeEnvironment()
	self.AnalyzeEnvironmentJob.Task = self

	self.PreAnalyzeScheduleJob = JobPreAnalyzeSchedule()
	self.PreAnalyzeScheduleJob.Task = self

	self.FulfillRequisitionJob = JobFulfillRequisition()
	self.FulfillRequisitionJob.Task = self

	self.ProgrammeScheduleJob = JobProgrammeSchedule()
	self.ProgrammeScheduleJob.Task = self

	self.AdScheduleJob = JobAdSchedule()
	self.AdScheduleJob.Task = self

	self.PostAnalyzeScheduleJob = JobPostAnalyzeSchedule()
	self.PostAnalyzeScheduleJob.Task = self

	self.IdleJob = AIIdleJob()
	self.IdleJob.Task = self
	self.IdleJob:SetIdleTicks( math.random(5,15) )

	self.Player = _G["globalPlayer"]
	self.SpotRequisition = self.Player:GetRequisitionsByOwner(_G["TASK_SCHEDULE"])
	--self.LogLevel = LOG_TRACE
end



function TaskSchedule:GetNextJobInTargetRoom()
	if (self.AnalyzeEnvironmentJob.Status ~= JOB_STATUS_DONE) then
		return self.AnalyzeEnvironmentJob
	elseif (self.PreAnalyzeScheduleJob.Status ~= JOB_STATUS_DONE) then
		return self.PreAnalyzeScheduleJob
	elseif (self.FulfillRequisitionJob.Status ~= JOB_STATUS_DONE) then
		return self.FulfillRequisitionJob
	elseif (self.AdScheduleJob.Status ~= JOB_STATUS_DONE) then
		--set number of hours to Plan based on index
		self.AdScheduleJob.hoursToPlan = 3
		self.ProgrammeScheduleJob.hoursToPlan = 16
		--debugMsg("last full scheduling: "..self.lastScheduleHour)
		if (self.adScheduleJobIndex == 1) then
			if (self.lastScheduleHour == TVT.GetDayHour()) then
				--TODO optimize
				--full planning need not be done multiple times per hour
				--programme optimization for upcoming programme and ad is OK
				--debugMsg("!skipping full scheduling, already done this hour")
				self.ProgrammeScheduleJob.hoursToPlan = 5
				--or do no planning at all
				--self:SetDone()
				--return
			else
				self.AdScheduleJob.hoursToPlan = 16
			end
		end
		return self.AdScheduleJob
	elseif (self.ProgrammeScheduleJob.Status ~= JOB_STATUS_DONE) then
		--activate regular ad schedule run
		self.lastScheduleHour = TVT.GetDayHour()
		self.AdScheduleJob.Status = JOB_STATUS_NEW
		self.adScheduleJobIndex = 1
		return self.ProgrammeScheduleJob
	elseif (self.PostAnalyzeScheduleJob.Status ~= JOB_STATUS_DONE) then
		return self.PostAnalyzeScheduleJob
	elseif (self.IdleJob ~= nil and self.IdleJob.Status ~= JOB_STATUS_DONE) then
		return self.IdleJob
	end

	--TODO maybe run another ad schedule job after waiting if minute is between 55 and 6
	--ensure that the next hour's ad is optimal as well

	--debugMsg("####TIME############ done scheduler task in " .. (os.clock() - self.ActivationTime) .."s.", true)
	self.ActivationTime = os.clock()

	--TODO
	--self.infoCache = {}

	--self:SetWait()
	self:SetDone()
end



-- called when changing a programme slot
-- method
function TaskSchedule:OnUpdateProgrammeSlot(day, hour, newBroadcastMaterial, oldBroadcastMaterial)
end



-- called when changing an ad slot
-- method
function TaskSchedule:OnUpdateAdSlot(day, hour, newBroadcastMaterial, oldBroadcastMaterial)
-- eg. remove existing requisitions of that slot?
end



function TaskSchedule.BackupPlan(slotType, day)
	local slots = {}
    for i=0, 23 do
		local fixedDay, fixedHour = FixDayAndHour(day, i)

		local currentBroadcastMaterial
		if slotType == TVT.Constants.BroadcastMaterialType.ADVERTISEMENT then
			currentBroadcastMaterial = MY.GetProgrammePlan().GetAdvertisement(fixedDay, fixedHour)
		elseif slotType == TVT.Constants.BroadcastMaterialType.PROGRAMME then
			currentBroadcastMaterial = MY.GetProgrammePlan().GetProgramme(fixedDay, fixedHour)
		end
		if currentBroadcastMaterial then
			slots[i] = currentBroadcastMaterial
		else
			slots[i] = nil
		end
	end
	return slots
end



function TaskSchedule:OnChangeAdSlot(broadcastMaterial, day, hour)
	-- default to 16 upcoming slots
	local checkHourAmount = 16

	-- fetch material of that slot if none was given
	if broadcastMaterial == nil then
		local response = TVT.of_getAdvertisementSlot(day, hour)
		if response.result == TVT.RESULT_OK then
			broadcastMaterial = response.data
		end
	end


	-- check later planned spots of this ad - and remove excess spots
	if broadcastMaterial ~= nil and broadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.ADVERTISEMENT) == 1 then
		local contract = broadcastMaterial.GetSource()
		-- (only needed if there are more spots planned than available)
		if contract ~= nil and contract.GetSpotsPlanned() > contract.GetSpotCount() then
			local spotsTillNow = MY.GetProgrammePlan().GetAdvertisementsPlanned(contract, contract.GetDaySigned(), 0, day, hour, 1)
			local spotsAfter = 0
			local checkHourMin = 1
			local checkHourMax = checkHourAmount
			-- find lastest (total) hour of spots for this contract
			local latestSpotHour = MY.GetProgrammePlan().GetAdContractLatestStartHour(contract, day, hour + 1, -1, -1)
			if latestSpotHour > 0 then checkHourMax = math.min(checkHourAmount, latestSpotHour - (day*24 + hour)) end

			for i= checkHourMin, checkHourMax do
				local planDay, planHour = FixDayAndHour(day, hour + i)
				local result = TVT.of_getAdvertisementSlot(planDay, planHour)
				if result.result == TVT.RESULT_OK and result.data ~= nil and result.data.GetReferenceID() == contract.GetID() then
					-- this spot is still within the limit
					if spotsAfter + spotsTillNow < contract.GetSpotCount() then
						spotsAfter = spotsAfter + 1
					-- reached limit?
					else
						-- remove ad
						local response = TVT.of_setAdvertisementSlot(nil, planDay, planHour)
						if response == TVT.RESULT_OK then
							--debugMsg("Removed excess ad from slot: " .. planHour .."   " .. result.data.GetTitle())
							self.adSlotsState[planHour] = bitmaskSetBit(self.adSlotsState[planHour], ADSLOTSTATE_SPOTMAX_REACHED)
						else
							debugMsg("FAILED to remove excess ad from slot: " .. planHour ..". Error code: " .. response)
						end
					end
				end
			end
		end
	end
end



-- returns amount of broadcasts of the given type (infomercials , programmes)
function TaskSchedule.GetBroadcastTypeCount(slotType, broadcastType, beginDay, beginHour, hours)
	if slotType == nil then return 0 end
	if beginHour == nil then beginHour = 0 end
	if hours == nil then hours = 24 end

	local result = 0
    for i=0, hours-1 do
		local fixedDay, fixedHour = FixDayAndHour(beginDay, beginHour + i)

		local currentBroadcastMaterial
		if slotType == TVT.Constants.BroadcastMaterialType.ADVERTISEMENT then
			currentBroadcastMaterial = MY.GetProgrammePlan().GetAdvertisement(fixedDay, fixedHour)
		elseif slotType == TVT.Constants.BroadcastMaterialType.PROGRAMME then
			currentBroadcastMaterial = MY.GetProgrammePlan().GetProgramme(fixedDay, fixedHour)
		end

		-- requested outage count
		if (broadcastType == TVT.Constants.BroadcastMaterialType.UNKNOWN and currentBroadcastMaterial == nil) then
			result = result + 1
		-- requested special type
		elseif currentBroadcastMaterial and currentBroadcastMaterial.isType(broadcastType) == 1 then
			result = result + 1
		elseif broadcastType == nil or not broadcastType then
			result = result + 1
		end
	end
	return result
end




function TaskSchedule.GetTrailerCount(day, beginHour, hours)
	return TaskSchedule.GetBroadcastTypeCount(TVT.Constants.BroadcastMaterialType.ADVERTISEMENT, TVT.Constants.BroadcastMaterialType.PROGRAMME, day, 0, 24)
end




-- return the individual audience riskyness
function TaskSchedule:GetGuessedAudienceRiskyness(day, hour, broadcast, block)
	-- 1.0 means assuming to get all
	--local baseRiskyness = 0.90

--[[
    c.guessedAudienceAccuracyTotal = 0.25
    c.guessedAudienceAccuracyTotalCount = 0
    c.guessedAudienceAccuracyHourly = {}
    c.guessedAudienceAccuracyHourlyCount = {}
]]
	return 0.90
end




function TaskSchedule.SortProgrammeLicencesByAttraction(licenceList, day, hour)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	if (table.count(licenceList) > 1) then
		-- precache complex weight calculation
		local weights = {}
		for k,v in pairs(licenceList) do
			-- TODO: take time of broadcast into consideration ?
			weights[ v.GetID() ] = AITools:GetBroadcastAttraction(v, fixedDay, fixedHour) -- * (0.4 + 0.6 * 0.9 ^ a.GetProgrammedTimes(fixedDay))
		end

		-- sort
		local sortMethod = function(a, b)
			return weights[ a.GetID() ] > weights[ b.GetID() ]
		end
		table.sort(licenceList, sortMethod)
	end

	return licenceList
end



function TaskSchedule.FilterInfomercialsByMaxRerunsToday(infomercialList, maxRerunsToday, day)
	local fixedDay, fixedHour = FixDayAndHour(day, 0)
	local resultList = {}
	if infomercialList then
		for i, infomercial in ipairs(infomercialList) do
			if maxRerunsToday >= TVT.of_GetBroadcastMaterialInProgrammePlanCount(infomercial.GetID(), fixedDay, 1, 1, 0) then
				table.insert(resultList, infomercial)
			end
		end
	end
	return resultList
end




function TaskSchedule.SortInfomercialsByAttraction(infomercialList, day, hour)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	if (table.count(infomercialList) > 1) then
		-- precache complex weight calculation
		local weights = {}
		for k,v in pairs(infomercialList) do
			-- TODO: take time of broadcast into consideration ?
			weights[ v.GetID() ] = (v.GetPerViewerRevenue()^0.5) * AITools:GetBroadcastAttraction(v, fixedDay, fixedHour) -- * (0.4 + 0.6 * 0.9 ^ a.GetProgrammedTimes(fixedDay))
		end

		-- sort
		local sortMethod = function(a, b)
			return weights[ a.GetID() ] > weights[ b.GetID() ]
		end
		table.sort(infomercialList, sortMethod)
	end

	return infomercialList
end




--returns a list/table of available contracts
-- hour:               hour of this day (past contracts are already
--                     removed from player collection then)
-- includePlannedEnds: whether to include contracts which are planned
--                     to be finished in that time
-- onlyInfomercials:   whether to only include contracts allowing infomercials
function TaskSchedule.GetAvailableContractsList(day, hour, includePlannedEnds, onlyInfomercials, forbiddenIDs)
-- forbiddenIDs:       table containing IDs of contracts ( c.GetID() )
	--defaults
	if (includePlannedEnds == nil) then includePlannedEnds = true end
	if (onlyInfomercials == nil) then onlyInfomercials = false end

	day, hour = FixDayAndHour(day, hour)

	local allContracts = TaskSchedule.GetAllAdContracts()
	local filteredContracts = TaskSchedule.FilterAdContractsByBroadcastableState( allContracts, day, hour, forbiddenIDs)

	if onlyInfomercials then
		local allInfomercials = {}
		for i, contract in ipairs(filteredContracts) do
			if contract.IsInfomercialAllowed() == 1 then
				table.insert(allInfomercials, contract)
			end
		end

		return allInfomercials
	end

	return filteredContracts
end




-- return list of all contracts broadcastable as infomercial that time
function TaskSchedule.GetAvailableInfomercialList(fixedDay, fixedHour, forbiddenIDs)
	-- 1. false = do not include contracts "planned" to end earlier
	-- 2. true = only infomercials
	return TaskSchedule.GetAvailableContractsList(fixedDay, fixedHour, false, true, forbiddenIDs)
end




-- fetch ALL "somehow broadcastable" licences of the player
function TaskSchedule.GetAllProgrammeLicences(forbiddenIDs)
	local allLicences = {}
	for i=0,TVT.of_getProgrammeLicenceCount()-1 do
		local licence = TVT.of_getProgrammeLicenceAtIndex(i)
		if (licence ~= nil) then
			local addIt = true
			-- ignore collection/series headers
			if ( licence.GetSubLicenceCount() > 0 ) then addIt = false end
			-- skip if no new broadcast is possible (controllable and available)
			if (licence.isNewBroadcastPossible() == 0) then addIt = false end
			-- skip forbidden IDs
			if table.contains(forbiddenIDs, licence.GetReferenceID()) then addIt = false end

			if ( addIt == true ) then
				table.insert(allLicences, licence)
			end
		end
	end
	return allLicences
end



function TaskSchedule.FilterProgrammeLicencesByBroadcastableState(licenceList, day, hour, forbiddenIDs)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)
	local filteredList = {}

	if licenceList ~= nil then
		-- add every licence broadcastable at the given time
		for k,licence in pairs(licenceList) do
			local addIt = true
			-- ignore when exceeding broadcast limits
			if ( licence.isExceedingBroadcastLimit() == 1 ) then addIt = false; end
			-- ignore programme licences not allowed for that time
			if ( licence.CanStartBroadcastAtTime(TVT.Constants.BroadcastMaterialType.PROGRAMME, fixedDay, fixedHour) ~= 1 ) then addIt = false; end
			-- skip xrated programme during daytime
			if (licence.GetData().IsXRated() == 1) and (fixedHour < 22 and fixedHour + licence.data.GetBlocks(0) > 5) then addIt = false; end
			-- skip forbidden IDs
			if table.contains(forbiddenIDs, licence.GetReferenceID()) then addIt = false end

			if ( addIt == true ) then
				table.insert(filteredList, licence)
			end
		end
	end
	return filteredList
end



function TaskSchedule.GetFilteredProgrammeLicenceList(minLevel, maxLevel, maxRerunsToday, day, hour, useLicences, forbiddenIDs)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	-- fetch all licences if needed
	if useLicences == nil then
		useLicences = TaskSchedule.GetAllProgrammeLicences(forbiddenIDs)
		-- only broadcastable ones
		useLicences = TaskSchedule.FilterProgrammeLicencesByBroadcastableState(useLicences, fixedDay, fixedHour, forbiddenIDs)
	end

	-- select suiting ones from the list of broadcastable licences
	local resultingLicences = {}
	for k,licence in pairs(useLicences) do
		local qLevel = AITools:GetBroadcastQualityLevel(licence)
		if (minLevel < 0 or qLevel >= minLevel) and (maxLevel < 0 or qLevel <= maxLevel) then
			local sentAndPlannedToday = -1
			-- only do the costly programme plan count if needed
			if maxRerunsToday > 0 then
				sentAndPlannedToday = TVT.of_GetBroadcastMaterialInProgrammePlanCount(licence.GetID(), day, 1, 1, 0)
			end
			if sentAndPlannedToday <= maxRerunsToday then
				--debugMsg("GetProgrammeLicenceList: " .. licence.GetTitle() .. " - " .. sentAndPlannedToday .. " <= " .. maxRerunsToday .. " - A:" .. licence.GetAttractiveness() .. " Qa:" .. licence.GetQualityLevel() .. " Qo:" .. licence.GetQuality() .. " T:" .. licence.GetTopicality())
				table.insert(resultingLicences, licence)
			else
				--debugMsg("GetProgrammeLicenceList: " .. licence.GetTitle() .. " - " .. sentAndPlannedToday .. " <= " .. maxRerunsToday ..  " - A:" .. licence.GetAttractiveness() .. " Qa:" .. licence.GetQualityLevel() .. " Qo:" .. licence.GetQuality() .. " T:" .. licence.GetTopicality() .. "   failed Runs " .. maxRerunsToday)
			end
		--else
			--local sentAndPlannedToday = TVT.of_GetBroadcastMaterialInProgrammePlanCount(licence.GetID(), day, 1)
			--debugMsg("GetProgrammeLicenceList: " .. licence.GetTitle() .. " - " .. sentAndPlannedToday .. " <= " .. maxRerunsToday ..  " - A:" .. licence.GetAttractiveness() .. " Qa:" .. licence.GetQualityLevel() .. " Qo:" .. licence.GetQuality() .. " T:" .. licence.GetTopicality() .. "   failed level " .. qualityLevel)
		end
	end

	return resultingLicences
end




function TaskSchedule.GetProgrammeLicencesForBlock(day, hour, level, forbiddenIDs)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	--average quality level suitable for the given time of the day
	if level == nil then level = AITools:GetAudienceQualityLevel(fixedDay, fixedHour) end
	local allLicences = TaskSchedule.GetAllProgrammeLicences(forbiddenIDs)
	-- filter them to only broadcastable ones
	local filteredLicences = TaskSchedule.FilterProgrammeLicencesByBroadcastableState(allLicences, fixedDay, fixedHour, forbiddenIDs)
	local minLevel = level
	local maxLevel = level
	local maxReruns = 0
	local licenceList

	-- === ADJUST START CONDITIONS ===
	-- adjust (start) rerun limit during night times
	if level == 2 then maxReruns = 1 end --midnight/morning
	if level == 1 then maxReruns = 2 end --even more during night

	-- use worse programmes if you cannot choose from a big pool
	if TVT.of_getProgrammeLicenceCount() < 7 then minLevel = math.max(1, minLevel - 2) end

	--try to find a programme of the given quality/level

	--exact fit?
	TaskSchedule.GetFilteredProgrammeLicenceList(minLevel, maxLevel, maxReruns, fixedDay, fixedHour, filteredLicences, forbiddenIDs)
	--check for some worse/better quality program
	if level <= 3 then
		if (table.count(licenceList) == 0) then licenceList = TaskSchedule.GetFilteredProgrammeLicenceList(minLevel-1, maxLevel, maxReruns + 1, fixedDay, fixedHour, filteredLicences, forbiddenIDs) end
	else
		if (table.count(licenceList) == 0) then licenceList = TaskSchedule.GetFilteredProgrammeLicenceList(minLevel, maxLevel+1, maxReruns + 1, fixedDay, fixedHour, filteredLicences, forbiddenIDs) end
	end
	if (table.count(licenceList) == 0) then licenceList = TaskSchedule.GetFilteredProgrammeLicenceList(minLevel-1, maxLevel+2, maxReruns + 1, fixedDay, fixedHour, filteredLicences, forbiddenIDs) end

	-- with so few licences we accept also repetitions of much worse
	-- suiting or slightly better programmes
	if TVT.of_getProgrammeLicenceCount() < 5 then
		if (table.count(licenceList) == 0) then licenceList = TaskSchedule.GetFilteredProgrammeLicenceList(minLevel-2, maxLevel+1, maxReruns + 2, fixedDay, fixedHour, filteredLicences, forbiddenIDs) end
	end

	if level >= 3 then
		if (table.count(licenceList) == 0) then licenceList = TaskSchedule.GetFilteredProgrammeLicenceList(minLevel-2, maxLevel+2, maxReruns + 2, fixedDay, fixedHour, filteredLicences, forbiddenIDs) end
	end

	-- try to find something at all costs
	if (table.count(licenceList) == 0) then licenceList = TaskSchedule.GetFilteredProgrammeLicenceList(-1, -1, -1, fixedDay, fixedHour, filteredLicences, forbiddenIDs) end

	--debugMsg(" --> found = " .. table.count(licenceList) .. " of " .. table.count(filteredLicences))
	return licenceList
end




function TaskSchedule.GetBestProgrammeLicenceForBlock(day, hour, level, forbiddenIDs)
	local licenceList = TaskSchedule.GetProgrammeLicencesForBlock(day, hour, level, forbiddenIDs)

	-- sort by attraction
	licenceList = TaskSchedule.SortProgrammeLicencesByAttraction(licenceList, day, hour)

	-- return first or "nil" if list is empty
	return table.first(licenceList)
end




-- fetch ALL "somehow broadcastable" licences of the player
function TaskSchedule.GetAllAdContracts()
	local response = TVT.of_getAdContracts()
	if ((response.result == TVT.RESULT_WRONGROOM) or (response.result == TVT.RESULT_NOTFOUND)) then
		return {}
	end
	local allContracts = {}

	for i, contract in ipairs(response.DataArray()) do
		--only add contracts
		if (contract ~= nil) then
			-- local addIt = true
			-- if ... checks ... are any required?

			table.insert(allContracts, contract)
		end
	end
	return allContracts
end




-- filter a given list to only contain adcontracts with broadcastable
-- ad spots (so not "spot 5 of 3") at the given time
function TaskSchedule.FilterAdContractsByBroadcastableState(contractList, day, hour, forbiddenIDs)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)
	local filteredList = {}
	if contractList ~= nil then
		-- add every adcontract broadcastable (= open spots) at the given time
		for k,v in pairs(contractList) do
			local addIt = true
			-- ends before?
			if addIt and v.GetDaysLeft(day) < 0 then addIt = false end
			-- no open spots / all planned before the given hour??
			if addIt and MY.GetProgrammePlan().GetAdvertisementsPlanned(v, v.GetDaySigned(), 0, fixedDay, fixedHour-1, 1) >= v.GetSpotCount() then addIt = false end
			-- skip forbidden IDs
			if addIt and table.contains(forbiddenIDs, v.GetID()) then addIt = false end

			if addIt then table.insert(filteredList, v)	end
		end
	end
	return filteredList
end



function TaskSchedule.FilterAdContractsBySpotsLeft(contractList, day, hour, filterMinimalBlocks)
	if filterMinimalBlocks == nil then filterMinimalBlocks = true end

	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	local plan = MY.GetProgrammePlan()
	local filteredList = {}
	for k,v in pairs(contractList) do
		if (not filterMinimalBlocks) or v.SendMinimalBlocksToday() > 0 then
			-- only add, if there is another spot left
			if plan.GetAdvertisementsPlanned(v, v.GetDaySigned(), 0, fixedDay, fixedHour, 1) < v.GetSpotCount() then
				table.insert(filteredList, v)
			end
		end
	end

	return filteredList
end



-- filter a given list to only contain adcontracts with the given genre
-- and/or flags
function TaskSchedule.FilterAdContractsByFlagsGenresTargetgroups(contractList, flags, genre, targetgroups, forbiddenIDs)
	if flags == nil then flags = -1 end
	if genre == nil then genre = -1 end
	if targetgroups == nil then targetgroups = -1 end
	local filteredList = {}
	if contractList ~= nil then
		-- add every adcontract suiting the filter
		-- -> not limited or with suiting limit
		for k,v in pairs(contractList) do
			local addIt = true
			--debugMsg(" - " .. v.GetTitle() .. "    " .. flags .." ~= " .. v.GetLimitedToProgrammeFlag() .. "    " .. genre .." ~= " .. v.GetLimitedToProgrammeGenre() )
			-- flags
			if addIt and flags > 0 and (v.GetLimitedToProgrammeFlag() > 0 and v.IsLimitedToProgrammeFlag(flags) == 0) then addIt = false end
			-- genres
			if addIt and genre > 0 and (v.GetLimitedToProgrammeGenre() > 0 and v.IsLimitedToProgrammeGenre(genre) == 0) then addIt = false end
			-- targetgroups
			if addIt and targetgroups > 0 and (v.GetLimitedToTargetGroup() > 0 and v.IsLimitedToTargetGroup(targetgroups) == 0) then addIt = false end

			-- skip forbidden IDs
			if addIt and table.contains(forbiddenIDs, v.GetID()) then addIt = false end

			if addIt then table.insert(filteredList, v)	end
		end
	end
	return filteredList
end






function TaskSchedule.SortAdContractsByAcuteness(contractList, day, hour, audienceSum)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	-- precache complex weight calculation
	-- else it would get called for each sort-comparison (a-b, a-c, a-d, b-c, c-d...)
	local weights = {}
	for k,v in pairs(contractList) do
		-- sort the list by highest acuteness (takes spots-to-send into consideration)
		-- but also take into consideration the minimum required audience
		if audienceSum ~= nil and tonumber(audienceSum) > 0 then
			weights[ v.GetID() ] = (0.5 + 0.5 * v.GetMinAudience(TVT.ME) / audienceSum) * v.GetAcuteness()
		else
			weights[ v.GetID() ] = math.round(v.GetMinAudience(TVT.ME)/1000) * v.GetAcuteness()
		end
	end

	-- sort by "weight"
	local sortMethod = function(a, b)
		return weights[ a.GetID() ] > weights[ b.GetID() ]
	end
	table.sort(contractList, sortMethod)

	return contractList
end




-- get a list of spots fitting the given requirements
function TaskSchedule.GetFilteredAdContractList(guessedAudience, day, hour, forBroadcastMaterial, onlyBroadcastable)
	if onlyBroadcastable == nil then onlyBroadcastable = true end

	-- convert number to audience-object
	if type(guessedAudience) == "number" then
		guessedAudience = TVT.audiencePredictor.GetEmptyAudience().InitWithBreakdown(guessedAudience)
	end

	local fixedDay, fixedHour = FixDayAndHour(day, hour)
	local allContracts = TaskSchedule.GetAllAdContracts()
	local filteredContracts
	-- keep only contracts with open spots
	if onlyBroadcastable then
		filteredContracts = TaskSchedule.FilterAdContractsByBroadcastableState(allContracts, fixedDay, fixedHour)
	end

	-- keep only contracts with suiting genre/flags
	if forBroadcastMaterial and forBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.Programme) == 1 then
		filteredContracts = TaskSchedule.FilterAdContractsByFlagsGenresTargetgroups(filteredContracts, forBroadcastMaterial.licence.GetFlags(), forBroadcastMaterial.licence.GetGenre())
	end
-- a) just return all allowed contracts
	filteredContracts = FilterAdContractsByMinAudience(filteredContracts, nil, guessedAudience)

-- or b) this does useless stuff - remove?
--[[
	-- keep only contracts with the desired (tolerable) minAudience
	if guessedAudience then
		local allContractsBelow = FilterAdContractsByMinAudience(filteredContracts, 0, guessedAudience)
		local allContractsBelowCount = table.count(allContractsBelow)
		if allContractsBelowCount > 0 then
			filteredContracts = FilterAdContractsByMinAudience(allContractsBelow, guessedAudience.Copy().MultiplyString("0.8"), guessedAudience)

			-- lower accepted minaudience
			if table.count(filteredContracts) == 0 then
				filteredContracts = FilterAdContractsByMinAudience(allContractsBelow, guessedAudience.Copy().MultiplyString("0.6"), guessedAudience)

				if (table.count(filteredContracts) == 0) then
					filteredContracts = FilterAdContractsByMinAudience(allContractsBelow, guessedAudience.Copy().MultiplyString("0.4"), guessedAudience)

					-- fallback to all below
					if (table.count(filteredContracts) == 0) then
						filteredContracts = allContractsBelow
					end
				end
			end
		else
			filteredContracts = {}
		end
	else
		debugMsg("GetFilteredAdContractList without guessedAudience!")
	end
--]]

	return filteredContracts
end




-- method
function TaskSchedule:GetAdvertisementsForBlock(day, hour, guessedAudience)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	local allContracts = TaskSchedule.GetAllAdContracts()
	local filteredContracts

	-- keep all contracts with open spots
	filteredContracts = TaskSchedule.FilterAdContractsByBroadcastableState(allContracts, day, hour)

	-- keep all with less minAudience requirement than guessed
	if table.count(filteredContracts) > 0 then
		local guessedAudienceSum = 0
		if guessedAudience == nil then
			-- fetch the programme aired before the ad
			local previousProgramme = MY.GetProgrammePlan().GetProgramme(fixedDay, fixedHour)
			if previousProgramme == nil then
				guessedAudienceSum = 0
			else
				local previousProgrammeBlock = math.max(1, MY.GetProgrammePlan().GetProgrammeBlock(fixedDay, fixedHour))
				guessedAudience = self.Task:GuessedAudienceForHour(fixedDay, fixedHour, previousProgramme, previousProgrammeBlock)
				guessedAudienceSum = guessedAudience.GetTotalSum()
			end
		end

		filteredContracts = FilterAdContractsByMinAudience(filteredContracts, 0, guessedAudience)
	end

	return filteredContracts
end


-- returns most useable advertisement for the given time
-- method
function TaskSchedule.GetBestAdvertisementForBlock(day, hour, contractsList, forbiddenIDs)
	if contractsList == nil then
		contractsList = TaskSchedule.GetAvailableContractsList(day, hour, false, false, forbiddenIDs)
	end

	-- work on copy
	local weightedList = table.copy(contractsList)
	-- sort
	TaskSchedule.SortAdContractsByAcuteness(weightedList, day, hour)

	return table.first(weightedList)
end



-- returns most promising infomercial for the given time
function TaskSchedule.GetBestInfomercialForBlock(day, hour, forbiddenIDs)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)
	-- fetch all contracts still available at that time
	-- (assume "all planned" to be run successful then - which
	--  means the contract is gone then)
	local infomercialList = TaskSchedule.GetAvailableInfomercialList(fixedDay, fixedHour, forbiddenIDs)

	-- filter too often run Elements
	local filteredInfomercialList = TaskSchedule.FilterInfomercialsByMaxRerunsToday(infomercialList, 2, fixedDay)

	-- unfiltered if there are none
	if (table.count(filteredInfomercialList) == 0) then
		filteredInfomercialList = TaskSchedule.FilterInfomercialsByMaxRerunsToday(infomercialList, -1, fixedDay)
	end

	-- sort the list by highest "PerViewerRevenue * Topicality * attract"
	filteredInfomercialList = TaskSchedule.SortInfomercialsByAttraction(filteredInfomercialList, fixedDay, fixedHour)

--[[
	-- precache complex weight calculation
	-- else it would get called for each sort-comparison (a-b, a-c, a-d, b-c, c-d...)
	local weights = {}
	for k,v in pairs(availableInfomercialContracts) do
		-- fetch how much it was run from "begin of day to hour-1"
		-- skip calculation for hours 0 and 1 (-1h: not planned yet or
		-- already refreshed)

		if hour > 1 then
			weights[ v.GetID() ] =  v.GetPerViewerRevenue() * v.GetQuality() * (0.2 + 0.8 ^ tonumber( TVT.of_GetBroadcastMaterialProgrammedCountInTimeSpan(v, TVT.Constants.BroadcastMaterialType.PROGRAMME, fixedDay, 0, fixedDay, fixedHour-1) ))
		else
			weights[ v.GetID() ] =  v.GetPerViewerRevenue() * v.GetQuality()
		end
	end

	-- sort by "weight" (PerViewerRevenue and quality (because of attactivity/topicality))
	local sortMethod = function(a, b)
		return weights[ a.GetID() ] > weights[ b.GetID() ]
	end
	table.sort(availableInfomercialContracts, sortMethod)
--]]

	-- return first or "nil" if empty
	return table.first(filteredInfomercialList)
end




function TaskSchedule.GetMovieOrInfomercialForBlock(day, hour, allowInfomercials, forbiddenIDs)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	if allowInfomercials == nil then allowInfomercials = true end

	local choosenInfomercial
	local choosenLicence
	local choosenLicenceValue = 0
	local choosenInfomercialValue = 0
	local level = AITools:GetAudienceQualityLevel(fixedDay, fixedHour)

	choosenLicence = TaskSchedule.GetBestProgrammeLicenceForBlock(fixedDay, fixedHour, level, forbiddenIDs)

	-- fetch potential infomercials
	if allowInfomercials then
		choosenInfomercial = TaskSchedule.GetBestInfomercialForBlock(fixedDay, fixedHour)
	end

	if choosenLicence then
		choosenLicenceValue = AITools:GetBroadcastAttraction(choosenLicence, fixedDay, fixedHour)
	end
	if choosenInfomercial then
		choosenInfomercialValue = AITools:GetBroadcastAttraction(choosenInfomercial, fixedDay, fixedHour)
	end
--debugMsg(" --> values:  licence=" .. choosenLicenceValue .. "  infomercial=" .. choosenInfomercialValue)

	-- === modify chances for an infomercial ===
	-- if we require money or are low on licences, increase chances a bit
	if TVT.of_getProgrammeLicenceCount() < 5 then choosenInfomercialValue = choosenInfomercialValue * 1.2; end

	if choosenLicenceValue > choosenInfomercialValue then
		return choosenLicence
	else
		return choosenInfomercial
	end
end




--returns a list/table of upcoming programme licences
function TaskSchedule.GetUpcomingProgrammesLicenceList(startHoursBefore, endHoursAfter)
	local currentLicenceList = {}

	if (startHoursBefore == nil) then startHoursBefore = 0 end
	if (endHoursAfter == nil) then endHoursAfter = 12 end

	local dayBegin = TVT.GetDay()
	local hourBegin = TVT.GetDayHour() + startHoursBefore
	local dayEnd = TVT.GetDay()
	local hourEnd = TVT.GetDayHour() + endHoursAfter

	dayBegin, hourBegin = FixDayAndHour(dayBegin, hourBegin)
	dayEnd, hourEnd = FixDayAndHour(dayEnd, hourEnd)


	--fetch all upcoming objects, last param = true, so only programmes
	--are returned, no infomercials
	local response = TVT.of_GetBroadcastMaterialInTimeSpan(TVT.Constants.BroadcastMaterialType.PROGRAMME, dayBegin, hourBegin, dayEnd, hourEnd, false, true)
	plannedProgrammes = response.DataArray()

	for i, broadcastMaterial in ipairs(plannedProgrammes) do
		local licence = MY.GetProgrammeCollection().GetProgrammeLicence(broadcastMaterial.GetReferenceID())
		if (licence ~= nil) then
			table.insert(currentLicenceList, licence)
		end
	end

	return currentLicenceList
end




-- helper function: find element in list "l" via function f(v)
function TaskSchedule.GetBroadcastSourceFromTable(referenceID, l)
	for _, v in ipairs(l) do
		if v.GetReferenceID() == referenceID then
			return v
		end
	end
	return nil
end




-- Returns an assumption about potential audience for the given hour and
-- (optional) broadcast
-- without given broadcast, an average quality for the hour is used
function TaskSchedule:GuessedAudienceForHour(day, hour, broadcast, block, guessCurrentHour)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	if (guessCurrentHour == nil) then guessCurrentHour = true; end

	--requesting audience for the current broadcast?
	if (guessCurrentHour == false) and (TVT.GetDay() == fixedDay and TVT.GetDayHour() == fixedHour and TVT.GetDayMinute() >= 5) then
		return TVT.GetCurrentProgrammeAudience()
	end

	-- predicted level of the news show for the given time
	--self:GuessedNewsAudienceForHour(day, hour)

	local level = AITools:GetAudienceQualityLevel(fixedDay, fixedHour)
	-- average quality of a broadcast with the predicted level
	local avgQuality = AITools:GetAverageBroadcastQualityByLevel(level)
	local statQuality1 = self.Player.Stats:GetAverageQualityByHour(1, hour)
	local statQuality2 = self.Player.Stats:GetAverageQualityByHour(2, hour)
	local statQuality3 = self.Player.Stats:GetAverageQualityByHour(3, hour)
	local statQuality4 = self.Player.Stats:GetAverageQualityByHour(4, hour)

	local qualities = {statQuality1, statQuality2, statQuality3, statQuality4}

	local guessedAudience = self:PredictAudience(broadcast, qualities, fixedDay, fixedHour, block, nil, nil)

	local globalPercentageByHour = AITools:GetMaxAudiencePercentage(fixedDay, fixedHour)
	local exclusiveMaxAudience = TVT.getExclusiveMaxAudience()
	local sharedMaxAudience = MY.GetMaxAudience() - exclusiveMaxAudience
	local riskyness = self:GetGuessedAudienceRiskyness(day, hour, broadcast, block)
	self.log["GuessedAudienceForHour"] = "GUESSED: Hour=" .. hour .. "  Lvl=" .. level .. "  Audience: guess=" .. math.round(guessedAudience.GetTotalSum()) .. "  atTV=".. math.round(MY.GetMaxAudience()*globalPercentageByHour) .. "  avgQ="..avgQuality .. "  statQ="..statQuality1.."/"..statQuality2.."/"..statQuality3.."/"..statQuality4 .. "   riskyness="..riskyness
--	debugMsg( self.log["GuessedAudienceForHour"] )

	--modify by some player specific riskyness about guessing wrong
	--and history stats about how wrong we guessed in the past
	guessedAudience = guessedAudience.MultiplyString(tostring(riskyness))

	return guessedAudience
end


-- Returns an assumption about potential audience for the given hour and
-- (optional) broadcast
-- without given broadcast, an average quality for the hour is used
function TaskSchedule:GuessedNewsAudienceForHour(day, hour, newsBroadcast, guessCurrentHour)
	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	if (guessCurrentHour == nil) then guessCurrentHour = true; end

	--requesting audience for the current broadcast?
	if (guessCurrentHour == false) and (TVT.GetDay() == fixedDay and TVT.GetDayHour() == fixedHour and TVT.GetDayMinute() < 5) then
		return TVT.GetCurrentNewsAudience()
	end

	-- predicted level of the news show for the given time
	local level = AITools:GetAudienceQualityLevel(fixedDay, fixedHour)
	-- average quality of a broadcast with the predicted level
	local avgQuality = AITools:GetAverageBroadcastQualityByLevel(level)

	local qualities = {avgQuality, avgQuality, avgQuality, avgQuality}
	local guessedAudience = self:PredictAudience(broadcast, qualities, fixedDay, fixedHour, 1, nil, nil)

	local globalPercentageByHour = AITools:GetMaxAudiencePercentage(fixedDay, fixedHour)
	local exclusiveMaxAudience = TVT.getExclusiveMaxAudience()
	local sharedMaxAudience = MY.GetMaxAudience() - exclusiveMaxAudience
	self.log["GuessedAudienceForHour"] = "Hour=" .. hour .. "  Lvl=" .. level .. "  %  guessedAudience=" .. math.round(guessedAudience.GetTotalSum()) .. "  aud=".. math.round(MY.GetMaxAudience()*globalPercentageByHour) .. " (".. math.floor(100*globalPercentageByHour) .."% of max="..MY.GetMaxAudience()..")"
	--debugMsg( self.log["GuessedAudienceForHour"] )

	return guessedAudience
end


function TaskSchedule:PredictAudience(broadcast, qualities, day, hour, block, previousBroadcastAttraction, previousNewsBroadcastAttraction, storePrediction)
	if broadcast ~= nil then
		if block == nil then block = 1; end

		if self.Player.LastStationMapMarketAnalysis == 0 or TVT.audiencePredictor.GetMarketCount() == 0 then
			TVT.audiencePredictor.RefreshMarkets()
			self.Player.LastStationMapMarketAnalysis = self.Player.WorldTicks
			debugMsg("RefreshMarkets() - never analyzed before")
		-- until stationmap tasks are balanced in - we avoid outdated ones

		elseif self.Player.WorldTicks - self.Player.LastStationMapMarketAnalysis > 1000  then
			TVT.audiencePredictor.RefreshMarkets()
			self.Player.LastStationMapMarketAnalysis = self.Player.WorldTicks
			debugMsg("RefreshMarkets() - previous analysis too old")
		end


		local broadcastQuality = broadcast.GetQuality()
		for i=1,4 do
			-- assume they all send at least a bit as good programme/news as we do
			local q = math.max(qualities[i], 0.6*qualities[i] + 0.4 * broadcastQuality) -- Lua-arrays are 1 based

-- ATTENTION:
			-- for now we cheat and mix in the REAL quality even if
			-- we are not knowing them (no generic room key)
			local realQ = TVT.getBroadcastedProgrammeQuality(day,hour,i)
			if realQ > 0.001 then
				q = 0.7 * q + 0.3 * realQ
--devMsg(TVT.ME..":  player #"..i.."  "..day.."/"..hour..":  q="..q.."  realQ="..realQ)
			end
			TVT.audiencePredictor.SetAverageValueAttraction(i, q)

		end


		local previousDay, previousHour = FixDayAndHour(day, hour-1)
		if previousBroadcastAttraction == nil then
			previousBroadcastAttraction = self.Player.Stats.BroadcastStatistics:GetAttraction(previousDay, previousHour, TVT.Constants.BroadcastMaterialType.PROGRAMME)
		end
		if previousNewsBroadcastAttraction == nil then
			previousNewsBroadcastAttraction = self.Player.Stats.BroadcastStatistics:GetAttraction(previousDay, previousHour, TVT.Constants.BroadcastMaterialType.NEWSSHOW)
			if previousNewsBroadcastAttraction == nil then
				--check for older news show (up to 6 hours) but with less
				--attractivity the older the news is
				for i = 1, 6 do
					local lastNewsDay, lastNewsHour = FixDayAndHour(previousDay, previousHour - i)
					previousNewsBroadcastAttraction = self.Player.Stats.BroadcastStatistics:GetAttraction(lastNewsDay, lastNewsHour, TVT.Constants.BroadcastMaterialType.NEWSSHOW)
					if previousNewsBroadcastAttraction ~= nil then
						previousNewsBroadcastAttraction = TVT.CopyBasicAudienceAttraction(previousNewsBroadcastAttraction, 1.0 - i*0.1)
						break
					end
				end
			end
		end

		-- assign our well known basic attraction (this already includes
		-- audience flow assumptions)
--		local broadcastAttraction = broadcast.GetStaticAudienceAttraction(hour, block, previousBroadcastAttraction, previousNewsBroadcastAttraction)
		local broadcastAttraction = broadcast.GetAudienceAttraction(hour, block, previousBroadcastAttraction, previousNewsBroadcastAttraction, False, False)
		TVT.audiencePredictor.SetAttraction(TVT.ME, broadcastAttraction)
		-- do the real prediction work
		TVT.audiencePredictor.RunPrediction(day, hour)
		local predictedAudience = TVT.audiencePredictor.GetAudience(TVT.ME)

		--store predicted attraction
		if storePrediction ~= false then
			if broadcast.isUsedAsType(TVT.Constants.BroadcastMaterialType.NEWSSHOW) == 1 then
				--debugMsg("STORE PREDICT - "..day.."/"..hour)
--				self.Player.Stats.BroadcastStatistics:AddBroadcast(day, hour, TVT.Constants.BroadcastMaterialType.NEWSSHOW, broadcastAttraction, predictedAudience.GetTotalSum())
			elseif broadcast.isUsedAsType(TVT.Constants.BroadcastMaterialType.PROGRAMME) == 1 then
--				self.Player.Stats.BroadcastStatistics:AddBroadcast(day, hour, TVT.Constants.BroadcastMaterialType.PROGRAMME, broadcastAttraction, predictedAudience.GetTotalSum())
			end
		end

		return predictedAudience
	else
		return TVT.audiencePredictor.GetEmptyAudience()
	end
end


-- add the requirement for a (new) specific ad contract
-- - each time the same requirement (level, audience) is requested,
--   its priority increases
-- - as soon as the requirement is fulfilled (new contract signed), it
--   might get placed (if possible)
function TaskSchedule:AddSpotRequisition(broadcastMaterialGUID, guessedAudience, level, day, hour)
	local slotReq = SpotSlotRequisition()
	slotReq.Day = day
	slotReq.Hour = hour
	slotReq.Minute = 55 -- xx:55 adspots start
	slotReq.guessedAudience = guessedAudience
	slotReq.level = level
	slotReq.broadcastMaterialGUID = broadcastMaterialGUID

	-- TODO Ronny: for now it groups by total sum - find a way to group
	--             by the various target groups

	-- increase priority if guessedAudience/level is requested again
	for k,v in pairs(self.SpotRequisition) do
		if (v.Level == level) then
			-- remove outdated slot requisitions (to avoid multiple reqs
			-- for the same time slot)
			v:RemoveSlotRequisitionByTime(day, hour)

			-- store "lowest" audience to avoid "hard to fulfill
			-- contracts" (lvl5 contract with 100k min requested by
			-- 70k/lvl5 predicted programme)
			-- TODO: what happens to target groups
			--       (a.Total < b.Total but a.children > b.children) ??
			if v.GuessedAudience.GetTotalSum() > guessedAudience.GetTotalSum() then
				v.GuessedAudience = guessedAudience
			end
			v.Count = v.Count + 1
			if (v.Priority < 5) then v.Priority = v.Priority + 1 end

			debugMsg("Raise demand on spots of level " .. level .. " (Audience: " .. math.floor(guessedAudience.GetTotalSum()) .. "). Time: " .. day .. "/" .. string.format("%02d", hour) .. ":55  / Spot requisition: count="..v.Count.."  priority="..v.Priority)
			table.insert(v.SlotReqs, slotReq)
			return v
		end
	end


	--create a new requisition if above did not find an existing one
	local requisition = SpotRequisition()
	requisition.TaskId = _G["TASK_ADAGENCY"]
	requisition.TaskOwnerId = _G["TASK_SCHEDULE"]
	requisition.Priority = 3
	requisition.Level = level
	requisition.GuessedAudience = guessedAudience
	requisition.Count = 1
	requisition.SlotReqs = {}
	table.insert(requisition.SlotReqs, slotReq)
	table.insert(self.SpotRequisition, requisition)
	_G["globalPlayer"]:AddRequisition(requisition)

	debugMsg("Create demand on spots of level " .. level .. " (Audience: " .. math.floor(guessedAudience.GetTotalSum()) .. "). Time: " .. day .. "/" .. string.format("%02d", hour) .. ":55  / Spot requisition: count="..requisition.Count.."  priority="..requisition.Priority)

	return requisition
end




function TaskSchedule:FixAdvertisement(day, hour)
	if (TVT.GetAdContractCount() <= 1) and (TVT.GetProgrammeLicenceCount() <= 0)  then
		--debugMsg("FixAdvertisement: " .. day .."/".. string.format("%02d", hour) .. ":55 - NOT POSSIBLE, not enough adcontracts (>1) or licences.")
	else
		--debugMsg("FixAdvertisement: " .. day .."/".. string.format("%02d", hour) .. ":55")

		--increase importance of schedule task!
		self.SituationPriority = 75

		-- assign player (if called from outside, this is not set yet)
		self.Player = _G["globalPlayer"]
		-- should start schedule then
		self.Player:ForceNextTask()
	end
end


function TaskSchedule:_FixImminentOutage(day, hour, minute, situationPriority)
	if (TVT.GetAdContractCount() <= 0) and (TVT.GetProgrammeLicenceCount() <= 0) then
		--debugMsg("FixImminentOutage: " .. day .."/".. string.format("%02d", hour) .. ":" .. minute .. " - NOT POSSIBLE, not enough adcontracts or licences.")
	else
		--debugMsg("FixImminentOutage: " .. day .."/".. string.format("%02d", hour) .. ":" .. minute)

		--increase importance of schedule task!
		self.SituationPriority = situationPriority

		-- assign player (if called from outside, this is not set yet)
		self.Player = _G["globalPlayer"]
		-- should start schedule then
		self.Player:ForceNextTask()
	end
end


function TaskSchedule:FixImminentAdOutage(day, hour)
	-- the further away, the lower the priority
	self:_FixImminentOutage(day, hour, "55", 65 - math.min(20, 5 * (hour - TVT.GetDayHour() + 1)))
end


function TaskSchedule:FixImminentProgrammeOutage(day, hour)
	-- the further away, the lower the priority
	self:_FixImminentOutage(day, hour, "05", 75 - math.min(20, 5 * (hour - TVT.GetDayHour() + 1)))
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<




-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobAnalyzeEnvironment"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.Task = nil

	c.initialMarketRefreshDone = false
end)


function JobAnalyzeEnvironment:typename()
	return "JobAnalyzeEnvironment"
end


function JobAnalyzeEnvironment:Prepare(pParams)
	self.Task.TickCount = 0
	self.Task.TickTimeMax = 0
	self.Task.TickTimeGone = 0

	local nowTime = os.clock()

	if not self.initialMarketRefreshDone then
		-- one could do this on each audience calculation but this is a rather
		-- complex function needing  some execution time
		TVT.audiencePredictor.RefreshMarkets()

		self.initialMarketRefreshDone = true
	end


	self.Player = _G["globalPlayer"]
	self.Task.Player.LastStationMapMarketAnalysis = self.Player.WorldTicks

	self.Task.TickCount = 0
	self.Task.TickTimeGone = self.Task.TickTimeGone + (os.clock() - nowTime)
end


function JobAnalyzeEnvironment:Tick()
	local nowTime = os.clock()

	-- not enough programmes ?
	-- Raise interest for movie distributor to buy start programme
	local Player = _G["globalPlayer"]

	--refresh stats
	Player.programmeLicencesInArchiveCount = TVT.of_GetProgrammeLicenceCount()

	local totalLicenceCount = Player.programmeLicencesInArchiveCount -- + player.programmeLicencesInSuitcaseCount
	local moviesNeeded = Player.Strategy.startProgrammeAmount - (TVT.Rules.startProgrammeAmount + totalLicenceCount)
	if moviesNeeded > 0 then
		local mdTask = Player.TaskList[TASK_MOVIEDISTRIBUTOR]
		mdTask.SituationPriority = 10 + moviesNeeded * 4
		debugMsg("Startprogramme missing: Raising priority for movie distributor! " .. mdTask.SituationPriority)
	end


	-- only order new programmes if the start programmes are fulfilled already
	if moviesNeeded <= 0 then
		-- not enough "useful" programmes?
		local okTopicalityCount = 0
		local okTopicality = 0.25
		for i=0,TVT.of_getProgrammeLicenceCount()-1 do
			local licence = TVT.of_getProgrammeLicenceAtIndex(i)
			if (licence ~= nil) then
				if licence.GetTopicality() > okTopicality then
					okTopicalityCount = okTopicalityCount + 1
				end
			end
		end

		if okTopicalityCount < 3 then
			debugMsg("LOW on good topicality licences ... ordering new ones")

			-- we need money - if needed, use all we have (only keep some money
			-- for news
			-- 0 - 400.000
			local budget = math.min(math.max(0, TVT.getMoney() - 5000), 400000)

			if budget > 0 then
				-- remove old "topicality count" requisition
				Player.RemoveRequisitionByReason("programmelicences_low_oktopicalitycount")

				-- amount of "good" licences needed
				local neededLicences = 6 - okTopicalityCount

				local requisition = BuyProgrammeLicencesRequisition()
				requisition.TaskId = _G["TASK_MOVIEDISTRIBUTOR"]
				requisition.TaskOwnerId = _G["TASK_SCHEDULE"]
				requisition.Priority = 3 --5
				requisition.reason = "programmelicences_low_oktopicalitycount"

				for i=0, neededLicences-1 do
					--0 - 200.000
					local licenceBudget = math.min(budget, 250000)
					if licenceBudget > 0 then
						local licenceReq = BuySingleProgrammeLicenceRequisition()
						licenceReq.minPrice = 0
						licenceReq.maxPrice = licenceBudget
						--12 hours from now (time is in seconds!)
						licenceReq.lifeTime = tonumber(TVT.GetTimeGoneInSeconds()) + 12 * 3600
						requisition:AddLicenceReq(licenceReq)

						budget = budget - licenceBudget
					end
				end

				--store this to avoid duplicates?
				--table.insert(self.MoviedistributorRequisitions, requisition)
				Player:AddRequisition(requisition)
			end
		end
	end

	local timeGone = (os.clock() - nowTime)
	self.Task.TickCount = self.Task.TickCount + 1
	self.Task.TickTimeGone = self.Task.TickTimeGone + timeGone
	if timeGone > self.Task.TickTimeMax then self.Task.TickTimeMax = timeGone end

	--debugMsg( self:typename() .. ": JOB DONE. ticks=" .. self.Task.TickCount .. "  time=" .. self.Task.TickTimeGone .. "  time/tick=" .. (self.Task.TickTimeGone/self.Task.TickCount) .. "  max=" .. self.Task.TickTimeMax, True)

	self.Status = JOB_STATUS_DONE
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<




-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobPreAnalyzeSchedule"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.Task = nil
end)


function JobPreAnalyzeSchedule:typename()
	return "JobPreAnalyzeSchedule"
end


function JobPreAnalyzeSchedule:Prepare(pParams)
	self.Task.TickCount = 0
	self.Task.TickTimeMax = 0
	self.Task.TickTimeGone = 0
end


function JobPreAnalyzeSchedule:Tick()
	local nowTime = os.clock()

	-- STORE CURRENT SLOTS
	-- only if current-tables are empty/nil (so on start)
	-- MAYBE also do this when 3rd party changed slots?
	--if table.count(self.Task.currentProgrammeSlots) = 0 then
		local day = TVT.GetDay()
		self.Task.currentProgrammeSlots = TaskSchedule.BackupPlan(TVT.Constants.BroadcastMaterialType.PROGRAMME, day)
		self.Task.currentAdSlots = TaskSchedule.BackupPlan(TVT.Constants.BroadcastMaterialType.ADVERTISEMENT, day)
	--end

	local timeGone = (os.clock() - nowTime)
	self.Task.TickCount = self.Task.TickCount + 1
	self.Task.TickTimeGone = self.Task.TickTimeGone + timeGone
	if timeGone > self.Task.TickTimeMax then self.Task.TickTimeMax = timeGone end

	--debugMsg( self:typename() .. ": JOB DONE. ticks=" .. self.Task.TickCount .. "  time=" .. self.Task.TickTimeGone .. "  time/tick=" .. (self.Task.TickTimeGone/self.Task.TickCount) .. "  max=" .. self.Task.TickTimeMax, True)

	self.Status = JOB_STATUS_DONE
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<




-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobPostAnalyzeSchedule"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.Task = nil;
end)



function JobPostAnalyzeSchedule:typename()
	return "JobPostAnalyzeSchedule"
end



function JobPostAnalyzeSchedule:Prepare(pParams)
	self.Task.TickCount = 0
	self.Task.TickTimeMax = 0
	self.Task.TickTimeGone = 0
end



function JobPostAnalyzeSchedule:Tick()
	local nowTime = os.clock()

	-- handled
	for i=0,23 do
		self.Task.changedProgrammeSlots[i] = false
		self.Task.changedAdSlots[i] = false
	end

	local timeGone = (os.clock() - nowTime)
	self.Task.TickCount = self.Task.TickCount + 1
	self.Task.TickTimeGone = self.Task.TickTimeGone + timeGone
	if timeGone > self.Task.TickTimeMax then self.Task.TickTimeMax = timeGone end

	--debugMsg( self:typename() .. ": JOB DONE. ticks=" .. self.Task.TickCount .. "  time=" .. self.Task.TickTimeGone .. "  time/tick=" .. (self.Task.TickTimeGone/self.Task.TickCount) .. "  max=" .. self.Task.TickTimeMax, True)

	self.Status = JOB_STATUS_DONE
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<




-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobFulfillRequisition"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.Task = nil
	c.SpotSlotRequisitions = nil
end)



function JobFulfillRequisition:typename()
	return "JobFulfillRequisition"
end



function JobFulfillRequisition:Prepare(pParams)
	self.Task.TickCount = 0
	self.Task.TickTimeMax = 0
	self.Task.TickTimeGone = 0

	--debugMsg("Erfülle Änderungs-Anforderungen an den Programmplan!")

	self.Player = _G["globalPlayer"]
	self.SpotSlotRequisitions = self.Player:GetRequisitionsByTaskId(_G["TASK_SCHEDULE"])
end



function JobFulfillRequisition:Tick()
	local nowTime = os.clock()

	local gameDay = TVT.GetDay()
	local gameHour = TVT.GetDayHour()
	local gameMinute = TVT.GetDayMinute()
	local requisitionCount = table.count(self.SpotSlotRequisitions)

	if requisitionCount > 0 then
		--check the upcoming advertisements
		--for key, value in pairs(self.SpotSlotRequisitions) do

		-- check up to 2 requisitions per slot
		for i=0, math.min(2, requisitionCount) do
			local value = table.first(self.SpotSlotRequisitions)
			if value ~= nil then
				-- tomorrow OR (today AND (after current hour OR(current hour but no started yet)))
				local timeOK = (value.Day > gameDay or (value.Day == gameDay and (value.Hour > gameHour or (value.Hour == gameHour and gameMinute < 55))))

				if (timeOK and value.ContractId ~= -1) then
					local contract = TVT.of_getAdContractByID(value.ContractId)

					if (contract ~= nil) then
						-- no open spots / all planned before the given hour??
						local plannedSpots = MY.GetProgrammePlan().GetAdvertisementsPlanned(contract, contract.GetDaySigned(), 0, value.Day, value.Hour-1, 1)
						if contract.GetSpotCount() > plannedSpots then
							debugMsg("Set advertisement by requisition: " .. value.Day .. "/" .. string.format("%02d", value.Hour) .. ":" .. value.Minute .. "  contract: " .. contract.GetTitle() .. " [" .. contract.GetID() .."]  MinAud: " .. math.floor(contract.GetMinAudience(TVT.ME)) .. "  acuteness: " .. contract.GetAcuteness() .. "  plannedspots=" .. plannedSpots .. " / " ..contract.GetSpotCount() )

							-- TODO: MARK as based on a specific requisition (to keep it!)
							local result = TVT.of_setAdvertisementSlot(contract, value.Day, value.Hour)
							if result == TVT.RESULT_OK then
								self.Task:OnChangeAdSlot(nil, value.Day, value.Hour)
							elseif result == TVT.RESULT_WRONGROOM then
								debugMsg("Set advertisement: failed - wrong room.")
							elseif result == TVT.RESULT_FAILED then
								debugMsg("Set advertisement: corresponding contract not found.")
							elseif result == TVT.RESULT_SKIPPED then
								debugMsg("Set advertisement: skipped, already placed at this spot.")
							elseif result == TVT.RESULT_NOTALLOWED then
								debugMsg("Set advertisement: too late / not allowed. planned=" .. value.Day.."/"..value.Hour .."  now=" .. gameDay .. "/" .. string.format("%02d", gameHour) .. ":" .. string.format("%02d", gameHour))
							end
						else
							debugMsg("Skip setting advertisement by requisition: " .. value.Day .. "/" .. string.format("%02d", value.Hour) .. ":" .. value.Minute .. "  contract: " .. contract.GetTitle() .. " [" .. contract.GetID() .."] - No spots left.")
						end
					end
				end
				-- completes and removes from the global requisition list
				value:Complete()

				--remove from our cached/prefetched variable too
				table.removeElement(self.SpotSlotRequisitions, value)
			end
		end
	end

	local timeGone = (os.clock() - nowTime)
	self.Task.TickCount = self.Task.TickCount + 1
	self.Task.TickTimeGone = self.Task.TickTimeGone + timeGone
	if timeGone > self.Task.TickTimeMax then self.Task.TickTimeMax = timeGone end

	-- do the next during the next tick
	if table.count(self.SpotSlotRequisitions) > 0 then
		return
	end

	--debugMsg( self:typename() .. ": JOB DONE. ticks=" .. self.Task.TickCount .. "  time=" .. self.Task.TickTimeGone .. "  time/tick=" .. (self.Task.TickTimeGone/self.Task.TickCount) .. "  max=" .. self.Task.TickTimeMax, True)

	self.Status = JOB_STATUS_DONE
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<




-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobAdSchedule"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.Task = nil
	c.plannedHours = 0
	--how many times should we retry to optimize and fill empty slots
	c.planRunsLeft = 5
	c.planRuns = 5
	c.hoursToPlan = 0 -- must be set when initialized
end)



function JobAdSchedule:typename()
	return "JobAdSchedule"
end



function JobAdSchedule:Prepare(pParams)
	self.Task.TickCount = 0
	self.Task.TickTimeMax = 0
	self.Task.TickTimeGone = 0

	self.plannedHours = 0
	--up to 5 planning tries
	self.planRunsLeft = self.planRuns

	-- increase max ticks
	-- optimization takes a while ...
	self.Task.MaxTicks = 16 + self.Task.MaxTicks
end



function JobAdSchedule:OnStop(pParams)
	-- HANDLE ALL CHANGED SLOTS
	local day = TVT.GetDay()
--[[
	local newAdSlots = TaskSchedule.BackupPlan(TVT.Constants.BroadcastMaterialType.ADVERTISEMENT, day)

	--iterating with "ipairs" means to skip "nil" values!
	--for index, newMaterial in ipairs(newAdSlots) do
	--we know store 0-23 so iterate like this
    for index=0, 23 do
		local oldMaterial = self.Task.currentAdSlots[index]
		local newMaterial = newAdSlots[index]
		if ((newMaterial ~= nil) ~= (oldMaterial ~= nil)) or (newMaterial and oldMaterial and newMaterial.GetGUID() ~= oldMaterial.GetGUID()) then
			self.Task.OnUpdateAdSlot(day, index, newMaterial, oldMaterial)
			self.Task.changedAdSlots[index] = true
		end
	end
]]--
	-- STORE NEW SLOTS
	self.Task.currentAdSlots = newAdSlots
end



function JobAdSchedule:Tick()
	local nowTime = os.clock()

	--debugMsg("JobAdSchedule:Tick()  Time: " .. TVT.GetDayHour()..":"..TVT.GetDayMinute() .. "   Tick: ".. self.Task.TickCounter .." / ".. self.Task.MaxTicks .."  TickTime: " .. string.format("%.4f", 1000 * self.TicksTotalTime) .."ms.")
	local nowClock = os.clock()

	local currentDay = TVT.GetDay()
	local currentHour = TVT.GetDayHour()
	local planSlots = 2
	local planHours = self.hoursToPlan
--TODO plan advertisement less far
--	if self.planRunsLeft > 0 then
		-- Add planRunsLeft checks

		if self.plannedHours < planHours then
			for i=1, planSlots do
				local fixedDay, fixedHour = FixDayAndHour(currentDay, currentHour + self.plannedHours)

				-- skip current hour if ad already started
				if fixedHour == currentHour and TVT.GetDayMinute() >= 55 then
					--
				else
					if TVT.of_IsModifyableProgrammePlanSlot(TVT.Constants.BroadcastMaterialType.ADVERTISEMENT, fixedDay, fixedHour) == TVT.RESULT_OK then
						self:HandleSlot(fixedDay, fixedHour)
					end
				end

				--move on to next hour
				self.plannedHours = self.plannedHours + 1
			end
		end

	local timeGone = (os.clock() - nowTime)
	self.Task.TickCount = self.Task.TickCount + 1
	self.Task.TickTimeGone = self.Task.TickTimeGone + timeGone
	if timeGone > self.Task.TickTimeMax then self.Task.TickTimeMax = timeGone end

		if self.plannedHours < planHours then
			--finished current tick
			return
		end
--	end

	--debugMsg( self:typename() .. ": JOB DONE. ticks=" .. self.Task.TickCount .. "  time=" .. self.Task.TickTimeGone .. "  time/tick=" .. (self.Task.TickTimeGone/self.Task.TickCount) .. "  max=" .. self.Task.TickTimeMax, True)

	self.Status = JOB_STATUS_DONE
end




function JobAdSchedule:HandleSlot(day, hour, guessedAudience)
	-- as soon as a new programme/infomercial was set...
	-- check if new requisition of ad contracts are required

	local index = hour % 24
	if self.Task.changedProgrammeSlots[index] == true then
		local result = self:CheckSlot(day, hour, guessedAudience)
		guessedAudience = result["guessedAudience"]
	end

	-- fill with new / better ad or trailer
	self:FillSlot(day, hour, guessedAudience)
end



-- check an ad slot if there are enough adcontracts available
-- if not it adds a new requisition to sign an according contract
function JobAdSchedule:CheckSlot(day, hour, guessedAudience)
	fixedDay, fixedHour = FixDayAndHour(day, hour)
	local currentAd = MY.GetProgrammePlan().GetAdvertisement(fixedDay, fixedHour)
	local currentProgramme = MY.GetProgrammePlan().GetProgramme(fixedDay, fixedHour)
	local addedSpotRequisition = nil
--debugMsg("CheckSlot: " .. (fixedDay - TVT.GetStartDay()) .."/" .. string.format("%02d", fixedHour))
	if guessedAudience == nil then
		local previousProgrammeBlock = math.max(1, MY.GetProgrammePlan().GetProgrammeBlock(fixedDay, fixedHour))
		guessedAudience = self.Task:GuessedAudienceForHour(fixedDay, fixedHour, currentProgramme, previousProgrammeBlock, false)
	end
	local guessedAudienceSum = guessedAudience.GetTotalSum()


	local allContracts = TaskSchedule.GetAllAdContracts()
	local filteredContracts = {}
	local addRequisition = true


	-- keep only contracts with open spots
	if table.count(allContracts) > 0 then
		if onlyBroadcastable then
			filteredContracts = TaskSchedule.FilterAdContractsByBroadcastableState(allContracts, fixedDay, fixedHour)
		else
			filteredContracts = allContracts --reference!
		end

		-- keep only contracts with suiting genre/flags
		if table.count(filteredContracts) > 0 then
			if currentProgramme and currentProgramme.isType(TVT.Constants.BroadcastMaterialType.Programme) == 1 then
				filteredContracts = TaskSchedule.FilterAdContractsByFlagsGenresTargetgroups(filteredContracts, currentProgramme.licence.GetFlags(), currentProgramme.licence.GetGenre())
			end
--debugMsg("  with suiting genre/flags: " .. table.count(filteredContracts))

			if table.count(filteredContracts) > 0 then
				-- keep only contracts with a minimum tolerable minaudience
				filteredContracts = FilterAdContractsByMinAudience(filteredContracts, guessedAudience.Copy().MultiplyString("0.5"), guessedAudience)
--debugMsg("  all contracts between 0.5 - 1.0 *minAudience: " .. table.count(filteredContracts))

				-- only add a requisition if we do not have some older
				-- but "lower" ads available
				--TODO was 3; do not count contracts but slots...
				if table.count(filteredContracts) > 1 then
					addRequisition = false
				end
			end
		end
	end

	if addRequisition then
		local requisitionLevel = AITools:GetAudienceQualityLevel(fixedDay, fixedHour)
		addedSpotRequisition = self.Task:AddSpotRequisition(TVT.GetBroadcastMaterialGUIDInProgrammePlan("", -1, -1), guessedAudience, requisitionLevel, fixedDay, fixedHour)
	end

	return {["guessedAudience"]=guessedAudience, ["addedSpotRequisition"]=addedSpotRequisition}
end



-- guessedAudience: optional
function JobAdSchedule:FillSlot(day, hour, guessedAudience)
	local nowTime = os.clock()

	local nowClock = os.clock()

	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	-- replace ads with trailers if ads have to high requirements
	-- also replace ads with better performing ones

	--rate of "ad-MinAudience / guessedAudience". Ads below get replaced
	--with trailers
	local replaceBadAdsWithTrailerRatePrimeTime = 0.05
	local replaceBadAdsWithTrailerRateDay = 0.10
	local replaceBadAdsWithTrailerRateNight = 0.25

	-- do not send more than X trailers a day
	-- if reaching that limit, keep sending "low requirement" ad spots
	local totalTrailerCount = TaskSchedule.GetTrailerCount(fixedDay)
	local totalTrailerMax = 6
	local placedTrailerCount = 0



	-- increase trailer rate during night
	local replaceBadAdsWithTrailerRate = replaceBadAdsWithTrailerRateDay
	if (fixedHour >= 1 and fixedHour <= 7) then
		replaceBadAdsWithTrailerRate = replaceBadAdsWithTrailerRateNight
	elseif (fixedHour >= 19 and fixedHour <= 23) then
		replaceBadAdsWithTrailerRate = replaceBadAdsWithTrailerRatePrimeTime
	end
	-- without programme, we cannot send trailers
	-- TODO: limit to broadcastable licences...
	if TVT.of_getProgrammeLicenceCount() <= 1 then replaceBadAdsWithTrailerRate = 0 end


	local chosenBroadcastSource = nil
	local chosenBroadcastLog = ""
	local currentBroadcastMaterial = MY.GetProgrammePlan().GetAdvertisement(fixedDay, fixedHour)
	local currentAdFails = false
	local sendTrailer = false
	local sendTrailerReason = ""
	local sendAd = true
	-- the new ad contract to send (if chosen to do so)
	local newAdContract = nil

	local previousProgramme = MY.GetProgrammePlan().GetProgramme(fixedDay, fixedHour)
	local previousProgrammeBlock = math.max(1, MY.GetProgrammePlan().GetProgrammeBlock(fixedDay, fixedHour))
	if guessedAudience == nil then
		guessedAudience = self.Task:GuessedAudienceForHour(fixedDay, fixedHour, previousProgramme, previousProgrammeBlock, false)
	end
	local guessedAudienceSum = guessedAudience.GetTotalSum()

--	debugMsg("Fill ad slot " .. (fixedDay - TVT.GetStartDay()) .. "/" .. string.format("%02d", fixedHour) .. ":55. guessedAudienceSum=" .. math.floor(guessedAudienceSum))

	-- add to debug data of the
	MY.SetAIData("guessedaudience_" .. fixedDay .."_".. fixedHour, guessedAudience)

	-- send a trailer:
	-- ===============
	-- (to avoid outages ... later stages might set an advertisement
	--  instead)
	-- a) outage / no ad
	-- b) not satisfiable advertisement
	-- c) replace existing trailer with better one


	-- a)
	-------------
	-- send trailer: if nothing is send
	-- ignore trailer limit here
	if (currentBroadcastMaterial == nil) then
		sendTrailerReason = "no ad"
		sendTrailer = true

	-- b)
	-------------
	-- send trailer: if a planned advertisement is not satisfiable
	-- take care of trailer limit!
	elseif (currentBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.ADVERTISEMENT) == 1) then
		local adContract = TVT.of_getAdContractByID( currentBroadcastMaterial.GetReferenceID() )
		if (previousProgramme ~= nil and adContract ~= nil) then
			local guessedAudienceValue = guessedAudience.GetTotalValue(adContract.GetLimitedToTargetGroup())
			if guessedAudienceValue < adContract.GetMinAudience(TVT.ME) then
--debugMsg("   current ad: " .. adContract.GetTitle() .. "   audValue=" .. guessedAudienceValue .. "   tg="..adContract.GetLimitedToTargetGroup())
				if totalTrailerCount < totalTrailerMax then
					sendTrailerReason = "unsatisfiable ad (guessedAud "..math.floor(guessedAudienceValue) .. "  <  minAud " .. adContract.GetMinAudience(TVT.ME) .. ")"
					sendTrailer = true
				end
				currentAdFails = true
			end
		end


	-- c)
	-------------
	-- send trailer: if there is a better one available?
	-- ignore trailer limit here (replacing trailer with trailer)
	elseif (currentBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.PROGRAMME) == 1) then
		local upcomingProgrammesLicences = TaskSchedule.GetUpcomingProgrammesLicenceList()
		local licenceID = currentBroadcastMaterial.GetReferenceID()
		-- is the trailer of the past?
		if (not TaskSchedule.GetBroadcastSourceFromTable(licenceID, upcomingProgrammesLicences)) then
			-- is there something planned in the future?
			if (table.count(upcomingProgrammesLicences) > 0) then
				sendTrailerReason = "better trailer (of upcoming programme)"
				sendTrailer = true
			end
		end
	end


	-- find better suiting ad
	-- ======================
	-- factor defines when to show an ad or an trailer
	local minAudienceFactor = 0.3
	-- during afternoon/evening prefer ads (lower ad requirements)
	if fixedHour >= 14 and fixedHour < 24 then minAudienceFactor = 0.15 end
	-- during primetime, send ad at up to all cost?
	if fixedHour >= 19 and fixedHour <= 23 then minAudienceFactor = 0.05 end
	-- if we do not have any programme, allow every audience factor...
	if TVT.of_getProgrammeLicenceCount() <= 1 then minAudienceFactor = 0 end

	local betterAdContractList = TaskSchedule.GetFilteredAdContractList(guessedAudience, fixedDay, fixedHour, previousProgramme, true)
	if (table.count(betterAdContractList) > 0) then
		local oldAdContract
		local oldMinAudience = 0
		local oldMinAudienceTargetGroup = -1
		-- sending an ad on the current slot?
		if (currentBroadcastMaterial ~= nil and currentBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.ADVERTISEMENT) == 1) then
			oldAdContract = TVT.of_getAdContractByID( currentBroadcastMaterial.GetReferenceID() )
			if (oldAdContract ~= nil) then
				oldMinAudience = oldAdContract.GetMinAudience(TVT.ME)
				oldMinAudienceTargetGroup = oldAdContract.GetLimitedToTargetGroup()
			end
		end

		-- fetch best fitting spot (most emerging one)
		newAdContract = TaskSchedule.GetBestAdvertisementForBlock(fixedDay, fixedHour, betterAdContractList, forbiddenIDs)
		local oldAudienceCoverage = 1.0
		local newAudienceCoverage = 1.0 --a 0-guessedAudience is always covered by 100%
		if oldAdContract == nil then oldAudienceCoverage = 0 end

		if guessedAudienceSum > 0 then
			oldAudienceCoverage = oldMinAudience / guessedAudience.GetTotalValue(oldMinAudienceTargetGroup)
			--if the old ad would not get satisfied, it does not cover anything
			if oldAudienceCoverage > 1 then oldAudienceCoverage = -1 end

			if newAdContract ~= nil then
				newAudienceCoverage = newAdContract.GetMinAudience(TVT.ME) / guessedAudience.GetTotalValue(newAdContract.GetLimitedToTargetGroup())
			end
		end
		-- if the ad will fail then it does not cover anything
		if currentAdFails then oldAudienceCoverage = 0 end

		local audienceCoverageIncrease = newAudienceCoverage - oldAudienceCoverage

		-- if new spot only covers <x% of guessed Audience, do not place
		-- an ad, better place a trailer
		-- replace "minAudience=0"-spots with trailers!
		if (newAudienceCoverage > replaceBadAdsWithTrailerRate) then
			-- only different spots - and when audience requirement is at better
			if (newAdContract ~= oldAdContract and audienceCoverageIncrease > 0) then
				chosenBroadcastSource = newAdContract
				if currentAdFails then
					chosenBroadcastLog = "Set ad (avoid failing ad): " .. fixedDay .. "/" .. string.format("%02d", fixedHour) .. ":55  " .. newAdContract.GetTitle() .. " [" .. newAdContract.GetID() .."]  MinAud=" .. newAdContract.GetMinAudience(TVT.ME) .. " (old=" .. oldMinAudience .. ")  guessedAud="..math.floor(guessedAudience.GetTotalValue(newAdContract.GetLimitedToTargetGroup()))
				else
					chosenBroadcastLog = "Set ad (optimized): " .. fixedDay .. "/" .. string.format("%02d", fixedHour) .. ":55  " .. newAdContract.GetTitle() .. " [" .. newAdContract.GetID() .."]  MinAud=" .. newAdContract.GetMinAudience(TVT.ME) .. " (old=" .. oldMinAudience .. ")  guessedAud="..math.floor(guessedAudience.GetTotalValue(newAdContract.GetLimitedToTargetGroup()))
				end
				sendTrailer = false
			end
		else
			-- only place a trailer, if previous is an advertisement
			-- take care of trailer limit here
			if (oldSpot ~= nil and totalTrailerCount < totalTrailerMax) then
				sendTrailerReason = "new ad below ReplaceWithTrailerRate"
				sendTrailer = true
			end
		end


		-- avoid keeping an failing ad
		if currentAdFails and chosenBroadcastSource == nil and newAdContract then
			sendAd = false
			sendTrailer = false
			chosenBroadcastSource = newAdContract
			chosenBroadcastLog = "Set ad (avoid failing ad): " .. fixedDay .. "/" .. string.format("%02d", fixedHour) .. ":55  " .. newAdContract.GetTitle() .. " [" .. newAdContract.GetID() .."]  MinAud=" .. newAdContract.GetMinAudience(TVT.ME) .. " (old=" .. oldMinAudience .. ")  guessedAud="..math.floor(guessedAudience.GetTotalValue(newAdContract.GetLimitedToTargetGroup()))
		-- nothing chosen but having an old one?
		elseif (chosenBroadcastSource == nil and oldAdContract ~= nil) then
			sendAd = false
			sendTrailer = false
			chosenBroadcastSource = oldAdContract
			chosenBroadcastLog = "Set ad (keep old): " .. fixedDay .. "/" .. string.format("%02d", fixedHour) .. ":55  " .. oldAdContract.GetTitle() .. " [" .. oldAdContract.GetID() .."]  MinAud=" .. oldAdContract.GetMinAudience(TVT.ME) .. " (old=" .. oldMinAudience .. ")  guessedAud="..math.floor(guessedAudience.GetTotalValue(oldAdContract.GetLimitedToTargetGroup()))
		end
	end


	-- avoid outage and set to send a trailer in all cases
	if (chosenBroadcastSource == nil and currentBroadcastMaterial == nil and sendTrailer ~= true) then
		sendTrailer = true
		sendTrailerReason = "avoid outage"
	end


	-- send a trailer
	-- ==============
	if (sendTrailer == true) then
		local upcomingProgrammesLicences = TaskSchedule.GetUpcomingProgrammesLicenceList()

		local oldTrailer
		if (currentBroadcastMaterial ~= nil and currentBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.PROGRAMME) == 1) then
			oldTrailer = TVT.of_getProgrammeLicenceByID( currentBroadcastMaterial.GetReferenceID() )
		end

		-- old trailer no longer promoting upcoming programme?
		local reuseOldTrailer = false
		if (oldTrailer ~= nil) then
			reuseOldTrailer = true
			--not in the upcoming list?
			if (TaskSchedule.GetBroadcastSourceFromTable(oldTrailer.GetID(), upcomingProgrammesLicences) ~= nil) then
				reuseOldTrailer = false
			end
		end

		if (reuseOldTrailer == false) then
			-- look for upcoming programmes
			if (table.count(upcomingProgrammesLicences) == 0) then
				-- nothing found: use a random one (if possible)
				if TVT.of_getProgrammeLicenceCount() > 0 then
					local choosenLicence = TVT.of_getProgrammeLicenceAtIndex( math.random(0, TVT.of_getProgrammeLicenceCount()-1) )
					if choosenLicence.IsNewBroadcastPossible() then
						upcomingProgrammesLicences = { choosenLicence }
					end
				end
			end

			if (table.count(upcomingProgrammesLicences) > 0) then
				local choosenLicence = upcomingProgrammesLicences[ math.random( #upcomingProgrammesLicences ) ]
				if (choosenLicence ~= nil) then
					chosenBroadcastSource = choosenLicence
					chosenBroadcastLog = "Set trailer: " .. fixedDay .. "/" .. string.format("%02d", fixedHour) .. ":55  " .. choosenLicence.GetTitle() .. "  Reason: " .. sendTrailerReason
				end
			end
		else
			-- reuse the old trailer
			if (reuseOldTrailer) then
				sendAd = false
				sendTrailer = false
				chosenBroadcastSource = oldTrailer
				--debugMsg("Belasse alten Trailer: " .. fixedDay .. "/" ..fixedHour .. ":55  " .. oldTrailer.GetTitle())
			end
		end
	end


	-- avoid outage
	-- ============
	-- send a random ad spot if nothing else is available
	if (chosenBroadcastSource == nil and currentBroadcastMaterial == nil) then
		if TVT.of_getAdContractCount() > 0 then
			chosenBroadcastSource = TVT.of_getAdContractAtIndex( math.random(0, TVT.of_getAdContractCount()-1) )
			chosenBroadcastLog = "Set ad (no alternative): " .. fixedDay .. "/" .. string.format("%02d", fixedHour) .. ":55  " .. chosenBroadcastSource.GetTitle() .. " [" ..chosenBroadcastSource.GetID() .."]  MinAud: " .. chosenBroadcastSource.GetMinAudience(TVT.ME)
		end
	end


	-- set new material
	-- ================
	if (chosenBroadcastSource ~= nil) then
		local result = TVT.of_setAdvertisementSlot(chosenBroadcastSource, fixedDay, fixedHour)
		if (result == TVT.RESULT_OK) then
			--debugMsg(chosenBroadcastLog)

			self.Task:OnChangeAdSlot(nil, fixedDay, fixedHour)
			-- slot state is fine again
			self.Task.adSlotsState[fixedHour] = ADSLOTSTATE_OK
		end
	end
	--debugMsg("JobSchedule:PlanAdForBlock(day="..day..", hour="..hour..") done in " ..  string.format("%.4f", (1000 * (os.clock() - nowClock))) .. "ms." )
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<




-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
_G["JobProgrammeSchedule"] = class(AIJob, function(c)
	AIJob.init(c)	-- must init base!
	c.Task = nil
	c.plannedHours = 0
	--how many times should we retry to optimize and fill empty slots
	c.planRunsLeft = 5
	c.planRuns = 5
	c.hoursToPlan = 0 -- must be set when initialized
end)



function JobProgrammeSchedule:typename()
	return "JobProgrammeSchedule"
end



function JobProgrammeSchedule:Prepare(pParams)
	self.Task.TickCount = 0
	self.Task.TickTimeMax = 0
	self.Task.TickTimeGone = 0

	self.plannedHours = 0
	--up to 5 planning tries
	self.planRunsLeft = self.planRuns

	-- increase max ticks
	-- optimization takes a while ...
	self.Task.MaxTicks = 36 + self.Task.MaxTicks
end



function JobProgrammeSchedule:OnStop(pParams)
	-- HANDLE ALL CHANGED SLOTS
	local day = TVT.GetDay()
	local newProgrammeSlots = TaskSchedule.BackupPlan(TVT.Constants.BroadcastMaterialType.PROGRAMME, day)

	--iterating with "ipairs" means to skip "nil" values!
	--for index, newMaterial in ipairs(newProgrammeSlots) do
	--we know store 0-23 so iterate like this
    for index=0, 23 do
		local oldMaterial = self.Task.currentProgrammeSlots[index]
		local newMaterial = newProgrammeSlots[index]
		local oldText = "-/-"
		local newText = "-/-"
		if oldMaterial then oldText = oldMaterial.GetTitle() end
		if newMaterial then newText = newMaterial.GetTitle() end
		if ((newMaterial ~= nil) ~= (oldMaterial ~= nil)) or (newMaterial and oldMaterial and newMaterial.GetGUID() ~= oldMaterial.GetGUID()) then
			self.Task.OnUpdateProgrammeSlot(day, index, newMaterial, oldMaterial)
			self.Task.changedProgrammeSlots[index] = true
		end
	end

	-- STORE NEW SLOTS
	self.Task.currentProgrammeSlots = newProgrammeSlots
end



function JobProgrammeSchedule:Tick()
	local nowTime = os.clock()

	--debugMsg("JobProgrammeSchedule:Tick()  Time: " .. TVT.GetDayHour()..":"..TVT.GetDayMinute() .. "   Tick: ".. self.Task.TickCounter .." / ".. self.Task.MaxTicks .."  TickTime: " .. string.format("%.4f", 1000 * self.TicksTotalTime) .."ms.")
	local nowClock = os.clock()


	--plan/optimize existing schedule
	--==========================
	local currentDay = TVT.GetDay()
	local currentHour = TVT.GetDayHour()

	local planSlots = 2
	local planHours = self.hoursToPlan

	--programmes
	--==========
	if self.planRunsLeft > 0 then
		-- plan/optimize up to x slots per tick
		for i=1, planSlots do
			if self.plannedHours < planHours then
				local fixedDay, fixedHour = FixDayAndHour(currentDay, currentHour + self.plannedHours)

				-- skip current hour if already started
				if fixedHour == currentHour and TVT.GetDayMinute() >= 5 then
					--
				-- skip if we cannot change this slot
				elseif TVT.of_IsModifyableProgrammePlanSlot(TVT.Constants.BroadcastMaterialType.PROGRAMME, fixedDay, fixedHour) ~= TVT.RESULT_OK then
					--debugMsg(" skip nonmodifyable: " .. fixedDay .. "/" .. fixedHour)

					local response = TVT.of_getProgrammeSlot(fixedDay, fixedHour)
					if (response.result == TVT.RESULT_OK) then
						-- skip other still occupied slots
						self.plannedHours = self.plannedHours + (response.data.GetBlocks(0)-1)
					end
				else
					local adjustedBlocks = self:FillSlot(fixedDay, fixedHour)
					-- skip already adjusted blocks
					if adjustedBlocks > 1 then
						self.plannedHours = self.plannedHours + (adjustedBlocks-1)
					end
				end

				--move on to next hour
				self.plannedHours = self.plannedHours + 1
			end
		end

		-- planned/optimized all - check if we need to run it again
		if self.plannedHours >= planHours then
			-- still outages left? repeat process, if possible
			if self.plannedHours > 0 then
				local usedSlotsCount = TaskSchedule.GetBroadcastTypeCount(TVT.Constants.BroadcastMaterialType.PROGRAMME, nil, currentDay, currentHour, planHours)

				-- finished, no empty slot left
				if usedSlotsCount == planHours then
--					debugMsg("JobProgrammeSchedule:Tick(): FINISHED: " .. usedSlotsCount .."/" .. planHours .. ".")
--					self.planRunsLeft = 0
				else
					debugMsg("JobProgrammeSchedule:Tick(): NOT all slots used: " .. usedSlotsCount .."/" .. planHours .. ".")
				end

				if TVT.GetAdContractCount() == 0 and TVT.GetProgrammeLicenceCount() == 0 then
					debugMsg("JobProgrammeSchedule:Tick(): Cannot fill outage slots, no licences or adcontracts available.")
					self.planRunsLeft = 0
				end
			end

			-- start all over
			if self.planRunsLeft > 0 then
				self.planRunsLeft = self.planRunsLeft - 1

				-- after initial optimization skip filling all slots over and
				-- over and just start with the first empty slot
				if self.planRuns - self.planRunsLeft > 1 then
					local firstOutage = -1
					for i = 0, planHours-1 do
						if firstOutage == -1 then
							local planDay, planHour = FixDayAndHour(currentDay, currentHour + i)
							local result = TVT.of_getProgrammeSlot(planDay, planHour)
							if result.data == nil then
								self.plannedHours = i
							end
						end
					end
				else
					self.plannedHours = 0
				end

				--give us "planHours" more ticks
				self.Task.MaxTicks = self.Task.MaxTicks + planHours
			end
		end


	local timeGone = (os.clock() - nowTime)
	self.Task.TickCount = self.Task.TickCount + 1
	self.Task.TickTimeGone = self.Task.TickTimeGone + timeGone
	if timeGone > self.Task.TickTimeMax then self.Task.TickTimeMax = timeGone end


		--finished current tick
		return
	else

	local timeGone = (os.clock() - nowTime)
	self.Task.TickCount = self.Task.TickCount + 1
	self.Task.TickTimeGone = self.Task.TickTimeGone + timeGone
	if timeGone > self.Task.TickTimeMax then self.Task.TickTimeMax = timeGone end


	end

	--debugMsg( self:typename() .. ": JOB DONE. ticks=" .. self.Task.TickCount .. "  time=" .. self.Task.TickTimeGone .. "  time/tick=" .. (self.Task.TickTimeGone/self.Task.TickCount) .. "  max=" .. self.Task.TickTimeMax, True)

	--done
	--====
	self.Status = JOB_STATUS_DONE
end




-- plan/optimize the existing schedule for the given time slot
function JobProgrammeSchedule:FillSlot(day, hour)
	--local nowClock = os.clock()

	-- a) replace infomercials with programme during primetime
	-- b) replace infomercials with ones providing higher income
	-- c) replace infomercials of "potentially obsolete contracts" then

	local fixedDay, fixedHour = FixDayAndHour(day, hour)

	local adjustedBlocks = 0
	local chosenBroadcastSource = nil
	local chosenBroadcastMaterial = nil
	local chosenBroadcastLog = ""

	local infomercialAllowed = false
	local programmeAllowed = true

	local currentBroadcastMaterial = MY.GetProgrammePlan().GetProgramme(fixedDay, fixedHour)
	local currentBroadcastBlock = math.max(1, MY.GetProgrammePlan().GetProgrammeBlock(fixedDay, fixedHour))
	local previousBroadcastMaterial = MY.GetProgrammePlan().GetProgramme(fixedDay, fixedHour - currentBroadcastBlock)
--	local previousBroadcastBlock = math.max(1, MY.GetProgrammePlan().GetProgrammeBlock(fixedDay, fixedHour - currentBroadcastBlock))
	local previousHourBroadcastMaterial = MY.GetProgrammePlan().GetProgramme(fixedDay, fixedHour - 1)
	local previousHourBroadcastBlock = math.max(1, MY.GetProgrammePlan().GetProgrammeBlock(fixedDay, fixedHour - 1))

	local guessedAudience = self.Task:GuessedAudienceForHour(fixedDay, fixedHour, previousHourBroadcastMaterial, previousHourBroadcastBlock).GetTotalSum()

	-- table/list of forbidden programme/adcontract IDs
	local forbiddenIDs = {}
	local replaceCurrentBroadcast = false


	-- SKIP OPTIMIZATION
	-- =================
	-- - if running
	-- - if not controllable (eg. opening show)



	-- CHECK CURRENT BROADCAST
	-- =======================
	-- Need to replace current broadcast?
	-- - outtages
	-- - do not send too often
	-- - try to avoid sending a programme right after itself
	-- - do not send infomercials if not wanted
	-- - do not send programme if not wanted

	-- outage
	if currentBroadcastMaterial == nil then
		replaceCurrentBroadcast = true
		chosenBroadcastLog = "Avoid outage."

	-- no interest in sending an infomercial there
	elseif not infomercialAllowed and currentBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.ADVERTISEMENT) == 1 then
		replaceCurrentBroadcast = true
		chosenBroadcastLog = "Avoid infomercials."

	-- no interest in sending an programme there
	elseif not programmeAllowed and currentBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.PROGRAMME) == 1 then
		replaceCurrentBroadcast = true
		chosenBroadcastLog = "Avoid programmes."

	-- avoid running the same programme each after another
	-- (so programmes differ, but licences are the same)
	elseif previousBroadcastMaterial ~= nil and previousBroadcastMaterial.GetID() ~= currentBroadcastMaterial.GetID() and previousBroadcastMaterial.GetSource() == currentBroadcastMaterial.GetSource() then
		replaceCurrentBroadcast = true
		chosenBroadcastLog = "Avoid duplicate."

		-- done later when "improving"
		-- table.insert(forbiddenIDs, previousBroadcastMaterial.GetReferenceID())

	-- avoid running the same programme too often a day
	elseif currentBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.PROGRAMME) == 1 then
		local sentAndPlannedToday = TVT.of_GetBroadcastMaterialInProgrammePlanCount(currentBroadcastMaterial.GetReferenceID(), fixedDay, 1, 1, 0)
		if sentAndPlannedToday >= 1 and TVT.of_getProgrammeLicenceCount() >= 4 then
			replaceCurrentBroadcast = true
			chosenBroadcastLog = "Run too often (" .. sentAndPlannedToday .. "x)."

			table.insert(forbiddenIDs, currentBroadcastMaterial.GetReferenceID())
		end
	end




	-- IMPROVE PROGRAMME SLOT
	-- ======================
	-- - if it is an outage
	-- - or there is a better programme / infomercial available

	-- even think about sending a programme?
	local licenceCount = TVT.of_getProgrammeLicenceCount()
	local canSendProgramme = programmeAllowed
	if licenceCount == 0 then canSendProgramme = false end

	-- avoid fetching this one again (yes this is here and some
	-- lines above for )
	if previousBroadcastMaterial ~= nil then table.insert(forbiddenIDs, previousBroadcastMaterial.GetReferenceID()) end


	-- try to send programme
	if replaceCurrentBroadcast and canSendProgramme then
		local bestProgrammeLicence = TaskSchedule.GetBestProgrammeLicenceForBlock(fixedDay, fixedHour, nil, forbiddenIDs)

		if bestProgrammeLicence ~= nil then
			if chosenBroadcastSource == nil then
				chosenBroadcastLog = "Set programme (avoid outage) \"" .. bestProgrammeLicence.GetTitle() .. "\" [" .. bestProgrammeLicence.GetID() .."]."
			else
				chosenBroadcastLog = "Set programme (optimized) \"" .. bestProgrammeLicence.GetTitle() .. "\" [" .. bestProgrammeLicence.GetID() .."]. Reason: " .. chosenBroadcastLog
			end
			chosenBroadcastSource = bestProgrammeLicence
			chosenBroadcastMaterial = TVT.CreateBroadcastMaterialFromSource(bestProgrammeLicence)
		else
--			debugMsg("Set programme (avoid outage): " .. fixedDay .. "/" .. fixedHour .. ":55  FAILED - no best programme.", true)
		end
	end



	-- even think about sending an infomercial?
	local canSendInfomercial = infomercialAllowed
	local infomercialAcceptance = 0
	-- send an infomercial if we have no other chance (even if forbidden)
	-- (no programme or just 1-2 to repeat over and over)
	if licenceCount <= 2 then canSendInfomercial = true end
	-- with enough licences we want to avoid sending infomercials
	if canSendInfomercial then
		-- start with 100%
		infomercialAcceptance = 1.0
		if (fixedHour >= 1 and fixedHour <= 4) then infomercialAcceptance = 0.35 + 0.65 * math.max(0, 1 - licenceCount/15) end
		if (fixedHour >= 5 and fixedHour <= 9) then infomercialAcceptance = 0.25 + 0.55 * math.max(0, 1 - licenceCount/10) end
		if (fixedHour >=10 and fixedHour <=18) then infomercialAcceptance = 0.15 + 0.45 * math.max(0, 1 - licenceCount/5) end
		if (fixedHour >=19 or fixedHour == 0) then infomercialAcceptance = 0.10 + 0.20 * math.max(0, 1 - licenceCount/3) end

		-- randomly say no?
		if math.random() > infomercialAcceptance ^ 2 then
			canSendInfomercial = false
		end
--		debugMsg("JobProgrammeSchedule:FillSlot(" .. fixedDay .. "/" .. string.format("%02d", fixedHour) .. ":05):  acceptance=" .. infomercialAcceptance .."  canSend="..tostring(canSendInfomercial))
	end


	-- send best possible infomercial (if allowed and feasible)
	if canSendInfomercial then -- and infomercialAcceptance > 0 then
		-- fetch best possible infomercial for that hour (skip forbidden ones)
		local bestInfomercialContract = TaskSchedule.GetBestInfomercialForBlock(fixedDay, fixedHour, forbiddenIDs)

		if bestInfomercialContract ~= nil then
			if currentBroadcastMaterial == nil then
				chosenBroadcastSource = bestInfomercialContract
				chosenBroadcastMaterial = TVT.CreateBroadcastMaterialFromSource(bestInfomercialContract)

				chosenBroadcastLog = "Set infomercial (avoid outage) \"" .. bestInfomercialContract.GetTitle() .. "\" [" .. bestInfomercialContract.GetID() .."]  CPM: " .. string.format("%.4f", bestInfomercialContract.GetPerViewerRevenue())
			else
				-- compare existing broadcast
				if currentBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.ADVERTISEMENT) == 1 then
					-- nothing to check as we already fetched the best
					-- infomercial for that time now
					chosenBroadcastLog = "Set infomercial (optimized) \"" .. bestInfomercialContract.GetTitle() .. "\" [" .. bestInfomercialContract.GetID() .."]  CPM:" .. string.format("%.4f", bestInfomercialContract.GetPerViewerRevenue()) .."  (previous: \"" .. currentBroadcastMaterial.GetTitle() .. "\"  CPM:" .. string.format("%.4f", currentBroadcastMaterial.GetSource().GetPerViewerRevenue()) ..") . Reason: " .. chosenBroadcastLog
--debugMsg("  JobProgrammeSchedule:FillSlot(" .. fixedDay .. "/" .. string.format("%02d", fixedHour) .. ":05):  BETTER INFOMERCIAL")

				-- replace programme with infomercials if they are better
				elseif currentBroadcastMaterial.isType(TVT.Constants.BroadcastMaterialType.PROGRAMME) == 1 then
					local infomercialAttraction = AITools:GetBroadcastAttraction( bestInfomercialContract, fixedDay, fixedHour )
					local programmeAttraction = AITools:GetBroadcastAttraction( currentBroadcastMaterial.GetSource(), fixedDay, fixedHour )
--debugMsg("  JobProgrammeSchedule:FillSlot(" .. fixedDay .. "/" .. string.format("%02d", fixedHour) .. ":05):  programmeAttraction=" .. programmeAttraction .. "  infomercialAttraction="..infomercialAttraction)

					-- modify infomercialAttraction by acceptance
					-- (the higher the acceptance, the more acceptable
					--  an infomercial becomes even with low attraction)
					infomercialAttraction = infomercialAttraction * (1 + 0.4 * infomercialAcceptance)

					if infomercialAttraction > programmeAttraction then
						chosenBroadcastSource = bestInfomercialContract
						chosenBroadcastMaterial = TVT.CreateBroadcastMaterialFromSource(bestInfomercialContract)
					end

					chosenBroadcastLog = "Set infomercial (replaced programme) \"" .. bestInfomercialContract.GetTitle() .. "\" [" .. bestInfomercialContract.GetID() .."]  CPM:" .. string.format("%.4f", bestInfomercialContract.GetPerViewerRevenue()) .."  (previous: \"" .. currentBroadcastMaterial.GetTitle() .. "\"). Reason: " .. chosenBroadcastLog .. "   attraction: infomercial=" .. infomercialAttraction .."  programme=" .. programmeAttraction
				end
			end
		end
	end




	-- set new material
	-- ================
	-- no new programme/infomercial assigned, keep the old one
	if chosenBroadcastSource == nil then
		if currentBroadcastMaterial ~= nil then
			--debugMsg("PlanProgrammeSchedule: Skip placing broadcast \"" .. currentBroadcastMaterial.GetTitle() .. "\" source for "..fixedDay .."/" .. fixedHour .. ":05. Already placed")
			-- skip other still occupied slots
			adjustedBlocks = currentBroadcastMaterial.GetBlocks(0) - MY.GetProgrammePlan().GetProgrammeBlock(fixedDay, fixedHour)
		else
			--debugMsg("JobProgrammeSchedule:FillSlot "..fixedDay .."/" .. string.format("%02d", fixedHour) .. ":05. Found no suitable broadcast to avoid outage.")
		end
	-- try to place selected one
	else
--		debugMsg("PlanProgrammeSchedule: Placing broadcast \"" .. chosenBroadcastSource.GetTitle() .. "\" source for "..fixedDay .."/" .. fixedHour .. ":05")
		local result = TVT.of_setProgrammeSlot(chosenBroadcastSource, fixedDay, fixedHour)
		if (result > 0) then
			local response = TVT.of_getProgrammeSlot(fixedDay, fixedHour)
			if ((response.result ~= TVT.RESULT_WRONGROOM) and (response.result ~= TVT.RESULT_NOTFOUND)) then
--				debugMsg("JobProgrammeSchedule:FillSlot "..fixedDay .."/" .. string.format("%02d", fixedHour) .. ":05. " .. chosenBroadcastLog)
				-- skip other now occupied slots
				adjustedBlocks = response.data.GetBlocks(0)

				currentBroadcastMaterial = response.data
			end
		else
			debugMsg("JobProgrammeSchedule:FillSlot "..fixedDay .."/" .. string.format("%02d", fixedHour) .. ":05. Failed to place broadcast. Result code: " .. result)
		end
	end

	--debugMsg("JobProgrammeSchedule:FillSlot() done in " ..  string.format("%.4f", (1000 * (os.clock() - nowClock))) .. "ms." )

	return adjustedBlocks
end
-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<