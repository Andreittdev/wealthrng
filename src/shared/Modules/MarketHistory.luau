local MarketHistory = {}

MarketHistory.MaxEntries = 5
MarketHistory.History = {}

function MarketHistory.Add(category, percent)
	table.insert(MarketHistory.History, 1, {
		Time = os.date("%H:%M"),
		Category = category,
		Percent = percent
	})

	while #MarketHistory.History > MarketHistory.MaxEntries do
		table.remove(MarketHistory.History)
	end
end

function MarketHistory.Get()
	return MarketHistory.History
end

return MarketHistory