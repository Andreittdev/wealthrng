-- Net-worth thresholds -> title, ordered ascending. Rebalance freely; only
-- GetTitleForNetWorth's "highest threshold <= netWorth" logic depends on order.

local TitleConfig = {}

-- Millionaire/Billionaire/Trillionaire are the pacing checkpoints
-- AssetDatabase's tier ladder is tuned against (~30min/~2h/~4-4.5h) -- see
-- its header. The steps in between just smooth out the climb.
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
