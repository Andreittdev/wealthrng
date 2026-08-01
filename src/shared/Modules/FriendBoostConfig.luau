-- Friend Boost: passive income (equipped item's IncomePerSecond + equipped
-- Assets' IncomePerMinute, see IncomeConfig.luau) gets a percent bonus based
-- on how many of the player's Roblox friends are also online in THIS same
-- server right now -- +10% with 1 friend, +20% with 2 or more. Deliberately
-- does NOT touch sell value (SellManager.luau) -- unlike VIP/Fortune
-- Potion, which boost both, this one is purely "play with friends, earn
-- more passively" -- and doesn't apply to Investments either (those don't
-- generate income at all, see InvestmentDatabase's header).
--
-- Pure leaf module (mirrors PotionConfig/IncomeConfig's role) -- just a
-- friendCount -> bonusPercent lookup, no Players/DataManager access here.
-- FriendBoostManager.luau (server) owns actually counting how many online
-- players are friends and keeping that live as people join/leave.

local FriendBoostConfig = {}

-- Ordered ascending by friend count threshold -- GetBonusPercent walks
-- this to find the highest threshold `friendCount` meets or exceeds.
local TIERS = {
	{ MinFriends = 2, BonusPercent = 20 },
	{ MinFriends = 1, BonusPercent = 10 },
}

function FriendBoostConfig.GetBonusPercent(friendCount: number): number
	for _, tier in TIERS do
		if friendCount >= tier.MinFriends then
			return tier.BonusPercent
		end
	end
	return 0
end

return FriendBoostConfig
