-- Precious metals & ores -- a Price that counts toward Net Worth,
-- deliberately NO income field -- that's what separates an Investment from
-- an Asset (displayed to players as "Invest", conceptually a liability in
-- the Rich-Dad-Poor-Dad sense: doesn't pay you, but still has real value,
-- same as holding real gold/silver doesn't pay a wage but isn't worthless).
-- Named distinctly from ItemDatabase's roll items (this is a shop
-- purchase, not something you can roll) to avoid confusion in the UI.
--
-- Long-term appreciation: unlike Assets, Investments don't generate income,
-- but holding one long enough still grows its value (real-world calendar
-- time, keeps compounding while offline too) -- +10% every ~3.5 days held,
-- compounding for as long as it's kept. Net Worth and sell refunds both use
-- ComputeCurrentValue, not the flat Price, once an investment has been
-- owned a while.

export type Investment = {
	Id: string,
	Name: string,
	Price: number,
}

local InvestmentDatabase = {}

local APPRECIATION_RATE = 0.10
local APPRECIATION_PERIOD_SECONDS = 3.5 * 24 * 60 * 60 -- ~3.5 days

local investments: { [string]: Investment } = {
	SilverBar = { Id = "SilverBar", Name = "Silver Bar", Price = 20000 },
	GoldBar = { Id = "GoldBar", Name = "Gold Bar", Price = 75000 },
	PlatinumBar = { Id = "PlatinumBar", Name = "Platinum Bar", Price = 250000 },
	DiamondOre = { Id = "DiamondOre", Name = "Diamond Ore", Price = 750000 },
	MeteoriteOre = { Id = "MeteoriteOre", Name = "Meteorite Ore", Price = 2000000 },
}

function InvestmentDatabase.GetInvestment(id: string): Investment?
	return investments[id]
end

function InvestmentDatabase.GetAllInvestments(): { [string]: Investment }
	return investments
end

-- Current appreciated value of an owned investment: Price * 1.1^periodsHeld,
-- stepping up once per full APPRECIATION_PERIOD_SECONDS elapsed since
-- purchase (real calendar time -- `now`/`purchasedAt` are both os.time()).
function InvestmentDatabase.ComputeCurrentValue(id: string, purchasedAt: number, now: number): number
	local investment = investments[id]
	if not investment then
		return 0
	end

	local elapsedSeconds = math.max(now - purchasedAt, 0)
	local periods = math.floor(elapsedSeconds / APPRECIATION_PERIOD_SECONDS)
	return investment.Price * (1 + APPRECIATION_RATE) ^ periods
end

return InvestmentDatabase
