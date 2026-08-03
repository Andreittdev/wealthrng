-- Net-worth thresholds -> title, ordered ascending. Rebalance freely; only
-- GetTitleForNetWorth's "highest threshold <= netWorth" logic depends on order.

local TitleConfig = {}

-- Millionaire/Billionaire/Trillionaire are the pacing checkpoints
-- AssetDatabase's tier ladder is tuned against (~30min/~2h/~4-4.5h) -- see
-- its header. The steps in between just smooth out the climb.
--
-- Trillionaire used to be the top title, but the economy doesn't stop
-- there -- AssetDatabase's RealEstateEmpire alone is $100T, and buying
-- multiple stacks of InvestmentDatabase's CelestialCore ($5T each, up to
-- x100 per purchase) pushes a maxed-out whale's Net Worth well past that.
-- These extra tiers give that late-late-game climb somewhere to go instead
-- of just staying "Trillionaire" forever once you clear $1T.
TitleConfig.Thresholds = {
	{ Threshold = 0, Title = "Beginner" },
	{ Threshold = 1000, Title = "Saver" },
	{ Threshold = 10000, Title = "Employee" },
	{ Threshold = 100000, Title = "Middle Class" },
	{ Threshold = 1000000, Title = "Millionaire" },
	{ Threshold = 10000000, Title = "Multi-Millionaire" },
	{ Threshold = 100000000, Title = "Wealthy" },
	{ Threshold = 1000000000, Title = "Billionaire" },
	{ Threshold = 10000000000, Title = "Multi-Billionaire" },
	{ Threshold = 100000000000, Title = "Tycoon" },
	{ Threshold = 1000000000000, Title = "Trillionaire" },
	{ Threshold = 10000000000000, Title = "Multi-Trillionaire" },
	{ Threshold = 100000000000000, Title = "Mogul" },
	{ Threshold = 1000000000000000, Title = "Titan" },
	{ Threshold = 10000000000000000, Title = "Colossus" },
	{ Threshold = 100000000000000000, Title = "Legend" },
	{ Threshold = 1000000000000000000, Title = "Immortal" },
}

function TitleConfig.GetTitleForNetWorth(netWorth: number): string
	local best = TitleConfig.Thresholds[1].Title
	for _, entry in TitleConfig.Thresholds do
		if netWorth >= entry.Threshold then
			best = entry.Title
		else
			break
		end
	end
	return best
end

return TitleConfig
