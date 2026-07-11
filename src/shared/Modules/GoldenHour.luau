local MarketConfig = require(script.Parent.MarketConfig)

local GoldenHour = {}

GoldenHour.Active = false
GoldenHour.Category = nil
GoldenHour.Multiplier = 1

GoldenHour.NextStart = os.time() + MarketConfig.GoldenHour.Interval
GoldenHour.EndTime = 0

function GoldenHour.Start(category)

	local bonus = math.random(
		MarketConfig.GoldenHour.MinBonus,
		MarketConfig.GoldenHour.MaxBonus
	)

	GoldenHour.Active = true
	GoldenHour.Category = category
	GoldenHour.Multiplier = 1 + (bonus / 100)
	GoldenHour.EndTime = os.time() + MarketConfig.GoldenHour.Duration

	return bonus

end

function GoldenHour.Stop()

	GoldenHour.Active = false
	GoldenHour.Category = nil
	GoldenHour.Multiplier = 1

	GoldenHour.NextStart = os.time() + MarketConfig.GoldenHour.Interval

end

function GoldenHour.IsActive()
	return GoldenHour.Active
end

function GoldenHour.GetMultiplier(category)

	if GoldenHour.Active and GoldenHour.Category == category then
		return GoldenHour.Multiplier
	end

	return nil

end

return GoldenHour