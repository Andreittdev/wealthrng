-- Handles ClaimPlaytimeReward: server-authoritative per-milestone gate +
-- payout (Cash, plus a Potion on milestones that have one -- see
-- PlaytimeRewardsConfig.Milestones). Claimed by standing near the plaza's
-- purple "Playtime Rewards" floor marker (MapBuilder's buildFloorMarker)
-- and pressing Claim on a ready card in PlaytimeRewardsProximityPanel.luau.
-- Once every milestone in the list has been claimed, the whole ladder
-- loops (see isCycleComplete below) instead of being a one-time list.
--
-- Owns the actual playtime accrual too (+1 to session.PlaytimeSeconds every
-- second a player is online) -- lives here, not DataManager, since it's a
-- Playtime-Rewards-specific concept, not a generic session field other
-- managers need to read.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlaytimeRewardsConfig = require(ReplicatedStorage.Modules.PlaytimeRewardsConfig)
local PotionDatabase = require(ReplicatedStorage.Modules.PotionDatabase)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local claimPlaytimeReward = RemotesBootstrap:WaitForChild("ClaimPlaytimeReward")
local playtimeRewardStateUpdated = RemotesBootstrap:WaitForChild("PlaytimeRewardStateUpdated")
local potionUpdated = RemotesBootstrap:WaitForChild("PotionUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local PlaytimeRewardsManager = {}

local PUSH_INTERVAL_SECONDS = 5

-- Shared by the initial push (Main.server.luau), the periodic tick below,
-- and after a successful claim, so all three always agree on exactly what
-- the client already receives. CycleStartSeconds is included so the client
-- can compute each milestone's actual (cycle-relative) threshold itself --
-- see PlaytimeRewardsProximityPanel.luau.
function PlaytimeRewardsManager.PushState(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	playtimeRewardStateUpdated:FireClient(player, {
		PlaytimeSeconds = session.PlaytimeSeconds,
		Claimed = session.ClaimedPlaytimeMilestones,
		CycleStartSeconds = session.PlaytimeRewardCycleStartSeconds,
	})
end

-- True once every milestone in the list has been claimed this cycle.
local function isCycleComplete(claimed: { [string]: boolean }): boolean
	for index in PlaytimeRewardsConfig.Milestones do
		if not claimed[tostring(index)] then
			return false
		end
	end
	return true
end

claimPlaytimeReward.OnServerEvent:Connect(function(player: Player, milestoneIndex: unknown)
	if typeof(milestoneIndex) ~= "number" or milestoneIndex ~= math.floor(milestoneIndex) then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	local milestone = PlaytimeRewardsConfig.Milestones[milestoneIndex]
	if not milestone then
		return
	end

	local key = tostring(milestoneIndex)
	if session.ClaimedPlaytimeMilestones[key] then
		return
	end

	local actualThreshold = session.PlaytimeRewardCycleStartSeconds + milestone.ThresholdSeconds
	if session.PlaytimeSeconds < actualThreshold then
		return
	end

	session.Cash += milestone.CashAmount
	session.ClaimedPlaytimeMilestones[key] = true

	-- CashAmount = 0 marks a Potion-only "special item" slot (see
	-- PlaytimeRewardsConfig.luau) -- no "$0" in the claimed message for those.
	local description = milestone.CashAmount > 0 and NumberFormat.FormatCash(milestone.CashAmount) or nil

	if milestone.PotionIds then
		local now = os.time()
		local grantedNames = {}

		for _, potionId in milestone.PotionIds do
			local potion = PotionDatabase.GetPotion(potionId)
			if potion then
				-- Same "extend, don't reset" stacking PotionManager.luau uses
				-- for a manual purchase, including the Potion Boost Time
				-- upgrade -- PotionDurationSeconds (if set) overrides the
				-- potion's own normal duration, not just a multiplier on top
				-- of it.
				local currentExpiry = session.ActivePotions[potionId] or 0
				local baseDuration = milestone.PotionDurationSeconds or potion.DurationSeconds
				local duration = baseDuration * UpgradeConfig.GetPotionDurationMultiplier(session.Upgrades.PotionBoost or 0)
				session.ActivePotions[potionId] = math.max(currentExpiry, now) + duration
				table.insert(grantedNames, potion.Name)
			end
		end

		if #grantedNames > 0 then
			potionUpdated:FireClient(player, session.ActivePotions)
			local potionsText = table.concat(grantedNames, ", ")
			description = description and (description .. " + " .. potionsText) or potionsText
		end
	end

	-- Once every milestone this cycle is claimed, loop the whole ladder:
	-- clear the claimed set and advance the cycle's baseline to right now,
	-- so milestone 1's ThresholdSeconds counts down fresh from this
	-- moment instead of the list just sitting fully claimed forever.
	if isCycleComplete(session.ClaimedPlaytimeMilestones) then
		session.ClaimedPlaytimeMilestones = {}
		session.PlaytimeRewardCycleStartSeconds = session.PlaytimeSeconds
	end

	systemMessage:FireClient(player, string.format("Playtime Reward Claimed: %s!", description))
	PlaytimeRewardsManager.PushState(player)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local session = DataManager.Get(player)
			if session then
				session.PlaytimeSeconds += 1
			end
		end
	end
end)

-- Keeps every milestone card's countdown roughly live without pushing
-- every single second.
task.spawn(function()
	while true do
		task.wait(PUSH_INTERVAL_SECONDS)
		for _, player in Players:GetPlayers() do
			PlaytimeRewardsManager.PushState(player)
		end
	end
end)

return PlaytimeRewardsManager
