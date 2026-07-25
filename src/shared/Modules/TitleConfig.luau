-- Net-worth thresholds -> title, ordered ascending. Rebalance freely; only
-- GetTitleForNetWorth's "highest threshold <= netWorth" logic depends on order.

local TitleConfig = {}

TitleConfig.Thresholds = {
	{ Threshold = 0, Title = "Beginner" },
	{ Threshold = 1000, Title = "Saver" },
	{ Threshold = 10000, Title = "Investor" },
	{ Threshold = 100000, Title = "Wealthy" },
	{ Threshold = 1000000, Title = "Millionaire" },
	{ Threshold = 10000000, Title = "Multi-Millionaire" },
	{ Threshold = 1000000000, Title = "Billionaire" },
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
