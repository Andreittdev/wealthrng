-- Abbreviates large currency numbers (K/M/B/T/Qa) instead of printing raw
-- digit strings -- this economy's numbers routinely reach into the
-- billions/trillions (see AssetDatabase's pacing model), and "$1800000000000"
-- crammed into a small UI card is unreadable. Shared (not per-panel) since
-- every money-displaying panel needs the same formatting.

local NumberFormat = {}

-- Largest first -- the first tier `n` clears wins.
local TIERS = {
	{ Value = 1e15, Suffix = "Qa" },
	{ Value = 1e12, Suffix = "T" },
	{ Value = 1e9, Suffix = "B" },
	{ Value = 1e6, Suffix = "M" },
	{ Value = 1e3, Suffix = "K" },
}

-- One decimal place, floored (not rounded) so e.g. 999,999 reads "999.9K"
-- instead of rounding up to a misleading "1000.0K".
function NumberFormat.Format(n: number): string
	n = math.floor(n)
	local sign = n < 0 and "-" or ""
	n = math.abs(n)

	for _, tier in TIERS do
		if n >= tier.Value then
			local scaled = math.floor((n / tier.Value) * 10) / 10
			local text = string.format("%.1f", scaled)
			if text:sub(-2) == ".0" then
				text = text:sub(1, -3)
			end
			return sign .. text .. tier.Suffix
		end
	end

	return sign .. tostring(n)
end

function NumberFormat.FormatCash(n: number): string
	return "$" .. NumberFormat.Format(n)
end

return NumberFormat
