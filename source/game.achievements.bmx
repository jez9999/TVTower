SuperStrict
Import "game.achievements.base.bmx"

Import "game.broadcast.audienceresult.bmx"
Import "game.broadcast.base.bmx"
Import "game.world.worldtime.bmx"
Import "game.player.finance.bmx"


Type TAchievementTask_FulfillAchievements extends TAchievementTask
	Field achievementGUIDs:string[]
	Field eventListeners:TLink[] {nosave}
	

	Method New()
'print "register fulfill listeners"
		eventListeners :+ [EventManager.registerListenerMethod( "Achievement.OnComplete", self, "OnCompleteAchievement" ) ]
	End Method


	Method Delete()
		EventManager.unregisterListenersByLinks(eventListeners)
	End Method


	'override
	Function CreateNewInstance:TAchievementTask_FulfillAchievements()
		return new TAchievementTask_FulfillAchievements
	End Function


	Method Init:TAchievementTask_FulfillAchievements(config:object)
		local configData:TData = TData(config)
		if not configData then return null

		local num:int = 1
		local achievementGUID:string = configData.GetString("achievementGUID"+num, "")

		While achievementGuid
			achievementGUIDs :+ [achievementGUID]
			achievementGUID = configData.GetString("achievementGUID")
		Wend

		return self
	End Method


	Method OnCompleteAchievement:int(triggerEvent:TEventBase)
		local achievement:TAchievement = TAchievement(triggerEvent.GetSender())
		if not achievement then return False

		local time:long = triggerEvent.GetData().GetLong("time", -1)
		if time < 0 then return False

'print "on completing an achievement"

		local interested:int = False
		For local guid:string = EachIn achievementGUIDs
			if guid <> achievement.GetGUID() then continue

			interested = True
			exit
		Next
		if not interested then return False

print "on completing an achievement ... and interested"

		For local playerID:int = 1 to 4
			'player already completed that achievement
			if IsCompleted(playerID, time) or IsFailed(playerID, time) then continue

			Local completing:int = True
			For local guid:string = EachIn achievementGUIDs
				local checkAchievement:TAchievement = GetAchievementCollection().GetAchievement(guid)
				if not checkAchievement then continue

				'if one of the required is failing, we cannot complete
				if not checkAchievement.IsCompleted(playerID, time)
					completing = False
					exit
				endif
			Next

			if completing then SetCompleted(playerID, time)
		Next
	End Method
			 

	'no override needed
	'we only update on achievement completitions
	'Method Update:int(time:long)
End Type




Type TAchievementTask_ReachAudience extends TAchievementTask
	Field minAudienceAbsolute:Int = -1
	Field minAudienceQuote:Float = -1.0
	Field limitToGenres:int = 0
	Field limitToFlags:int = 0
	'use -1 to ignore time
	Field checkHour:int = -1
	Field checkMinute:int = -1


	'override
	Function CreateNewInstance:TAchievementTask_ReachAudience()
		return new TAchievementTask_ReachAudience
	End Function

		
	'override
	Method GetTitle:string()
		local t:string = Super.GetTitle()
		if minAudienceAbsolute >= 0
			t = t.Replace("%VALUE%", TFunctions.dottedValue(minAudienceAbsolute))
		elseif minAudienceQuote >= 0
			t = t.Replace("%VALUE%", MathHelper.NumberToString(minAudienceQuote*100.0,2, True)+"%")
		endif
		return t
	End Method
		

	Method Init:TAchievementTask_ReachAudience(config:object)
		local configData:TData = TData(config)
		if not configData then return null

		minAudienceAbsolute = configData.GetInt("minAudienceAbsolute", minAudienceAbsolute)
		minAudienceQuote = configData.GetFloat("minAudienceQuote", minAudienceQuote)

		limitToGenres = configData.GetInt("limitToGenres", limitToGenres)
		limitToFlags = configData.GetInt("limitToFlags", limitToFlags)

		return self
	End Method


	'override
	Method Update:int(time:long)
		'check for completitions
		if checkHour = -1 or GetWorldTime().GetDayHour(time) = checkHour
			if checkMinute = -1 or GetWorldTime().GetDayMinute(time) = checkMinute
				For local playerID:int = 1 to 4
					if IsCompleted(playerID, time) or IsFailed(playerID, time) then continue

					'todo: check genres/flags
					
					local audienceResult:TAudienceResult = GetBroadcastManager().GetAudienceResult(playerID)
					if not audienceResult or not audienceResult.audience then continue

					if minAudienceAbsolute >= 0 and audienceResult.audience.GetTotalSum() > minAudienceAbsolute
						SetCompleted(playerID, time)
					endif
					if minAudienceQuote >= 0 and audienceResult.GetAudienceQuotePercentage() > minAudienceQuote
						SetCompleted(playerID, time)
					endif
				Next
			endif
		endif

		return Super.Update(time)
	End Method
End Type




Type TAchievementTask_ReachBroadcastArea extends TAchievementTask
	Field minReachAbsolute:Int = -1
	Field minReachPercentage:Float = -1.0


	'override
	Function CreateNewInstance:TAchievementTask_ReachBroadcastArea()
		local instance:TAchievementTask_ReachBroadcastArea = new TAchievementTask_ReachBroadcastArea

		'instead of registering them in "new()" (which is run for the
		'"creator instance" too) we do it here
		instance.eventListeners :+ [EventManager.registerListenerMethod( "StationMap.onRecalculateAudienceSum", instance, "onRecalculateAudienceSum" ) ]

		return instance
	End Function

		
	'override
	Method GetTitle:string()
		local t:string = Super.GetTitle()
		if minReachAbsolute >= 0
			t = t.Replace("%VALUE%", TFunctions.dottedValue(minReachAbsolute))
		elseif minReachPercentage >= 0
			t = t.Replace("%VALUE%", MathHelper.NumberToString(minReachPercentage*100.0,2, True)+"%")
		endif
		return t
	End Method
		

	Method Init:TAchievementTask_ReachBroadcastArea(config:object)
		local configData:TData = TData(config)
		if not configData then return null

		minReachAbsolute = configData.GetInt("minReachAbsolute", minReachAbsolute)
		minReachPercentage = configData.GetFloat("minReachPercentage", minReachPercentage)

		return self
	End Method


	Method onRecalculateAudienceSum:int(triggerEvent:TEventBase)
		local map:TStationMap = TStationMap(triggerEvent.GetSender())
		if not map then return False

		local time:Long = GetWorldTime().GetTimeGone()


		if IsCompleted(map.owner, time) or IsFailed(map.owner, time) then return False

		if minReachAbsolute >= 0 and map.GetReach() >= minReachAbsolute
			SetCompleted(map.owner, time)
		endif
		if minReachPercentage >= 0 and map.getCoverage() >= minReachPercentage
			SetCompleted(map.owner, time)
		endif

		return True
	End Method

	'not needed
	'Method Update:int(time:long)
End Type




Type TAchievementReward_Money extends TAchievementReward
	Field money:int
	

	'override
	Function CreateNewInstance:TAchievementReward_Money()
		return new TAchievementReward_Money
	End Function


	'override
	Method GetTitle:string()
		local t:string = Super.GetTitle()
		if not t then t = TFunctions.dottedValue(money) +" "+ CURRENCYSIGN
		return t
	End Method


	Method Init:TAchievementReward_Money(config:object)
		local configData:TData = TData(config)
		if not configData then return null

		money = configData.GetInt("money", money)

		return self
	End Method


	'overriden
	Method CustomGiveToPlayer:int(playerID:int)
		local finance:TPlayerFinance = GetPlayerFinance(playerID)
		if not finance then return False

			
		finance.EarnGrantedBenefits(money)
		return True
	End Method
End Type



'=== REGISTER CREATORS ===
'TASKS
GetAchievementCollection().RegisterElement("task::ReachAudience", new TAchievementTask_ReachAudience)
GetAchievementCollection().RegisterElement("task::ReachBroadcastArea", new TAchievementTask_ReachBroadcastArea)
'REWARDS
GetAchievementCollection().RegisterElement("reward::Money", new TAchievementReward_Money)


rem
'=== EXAMPLE ===
local achievement:TAchievement = new TAchievement
local audienceConfig:TData = new TData.AddNumber("minAudienceAbsolute", 100000)
local moneyConfig:TData = new TData.AddNumber("money", 50000)
local task:TAchievementTask = TAchievementCollection.CreateTask("task::ReachAudience", audienceConfig)
local reward:TAchievementReward = TAchievementCollection.CreateReward("reward::Money", moneyConfig)

achievement.SetTitle(new TLocalizedString)
achievement.title.Set("Erreiche 100.000 Zuschauer", "de")
achievement.title.Set("Reach an audience of 100.000", "en")
achievement.AddTask( task.GetGUID() )
achievement.AddReward( reward.GetGUID() )
GetAchievementCollection().AddTask( task )
GetAchievementCollection().AddReward( reward )
GetAchievementCollection().AddAchievement( achievement )
endrem