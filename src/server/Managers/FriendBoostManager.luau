-- Counts, per online player, how many of their Roblox friends are ALSO
-- online in this same server right now -- feeds FriendBoostConfig's
-- friendCount -> bonusPercent lookup (IncomeConfig.luau applies it to
-- passive item/Asset income, see that file's header). Recomputed for
-- EVERYONE whenever the roster changes (a join/leave can change every
-- other online player's count, not just the player who joined/left), via
-- this module's own Players.PlayerAdded/PlayerRemoving (not
-- Main.server.luau's onPlayerAdded) so it stays self-contained.
--
-- Deliberately does NOT require StatsManager to push a live update the
-- instant a friend joins -- that would make this <-> StatsManager a
-- circular require (StatsManager already has to require THIS, to read the
-- bonus for its IncomeConfig calls). IncomeManager.luau's own per-tick
-- loop (every 3s while any item income is nonzero) already calls
-- StatsManager.Recompute regularly regardless, so the bonus surfaces on
-- its own within a few seconds of a friend joining -- no explicit push
-- needed for a passive-income-only bonus like this one.
--
-- Player:IsFriendsWith can yield (a web call, Roblox-side cached
-- afterwards) -- every recompute pass runs in its own task.spawn so a
-- slow/failed lookup can't block anything else, and a single failed check
-- (pcall) just counts as "not friends" instead of erroring the whole pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FriendBoostConfig = require(ReplicatedStorage.Modules.FriendBoostConfig)

local FriendBoostManager = {}

local friendCountCache: { [Player]: number } = {}

-- `onlineList` is passed explicitly (not re-read from Players:GetPlayers()
-- internally) so PlayerRemoving can exclude the leaving player, who's
-- still technically present in Players:GetPlayers() at the moment that
-- event fires.
local function recomputeFor(onlineList: { Player })
	for _, player in onlineList do
		local count = 0
		for _, other in onlineList do
			if other ~= player then
				local ok, areFriends = pcall(function()
					return player:IsFriendsWith(other.UserId)
				end)
				if ok and areFriends then
					count += 1
				end
			end
		end
		friendCountCache[player] = count
	end
end

function FriendBoostManager.GetBonusPercent(player: Player): number
	return FriendBoostConfig.GetBonusPercent(friendCountCache[player] or 0)
end

Players.PlayerAdded:Connect(function()
	task.spawn(recomputeFor, Players:GetPlayers())
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	friendCountCache[leavingPlayer] = nil

	local remaining = {}
	for _, player in Players:GetPlayers() do
		if player ~= leavingPlayer then
			table.insert(remaining, player)
		end
	end
	task.spawn(recomputeFor, remaining)
end)

return FriendBoostManager
