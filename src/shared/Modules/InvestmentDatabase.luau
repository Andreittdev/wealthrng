-- Precious metals & ores -- a Price that counts toward Net Worth,
-- deliberately NO income field -- that's what separates an Investment from
-- an Asset (displayed to players as "Invest", conceptually a liability in
-- the Rich-Dad-Poor-Dad sense: doesn't pay you, but still has real value,
-- same as holding real gold/silver doesn't pay a wage but isn't worthless).
-- Named distinctly from ItemDatabase's roll items (this is a shop
-- purchase, not something you can roll) to avoid confusion in the UI.
--
-- 11 tiers spanning $100 to $5T (~8x per tier, same idea as
-- AssetDatabase's ladder) so there's an entry point at every stage of the
-- game, not just once a player has hundreds of thousands to spare.
--
-- Priced to stay roughly ~20x cheaper than the same-index AssetDatabase
-- tier, all the way up through the 2nd-to-last tier (MeteoriteOre vs
-- LuxuryHotelChain) -- the top tier (CelestialCore) is the one exception,
-- deliberately kept at that same ~20x-cheaper ratio against
-- AssetDatabase's NEW top tier (RealEstateEmpire, now $100T -- see that
-- file's header) instead of against the old $1.8T one, so it's still a
-- genuine multi-day "what do I do with my spare cash" capstone purchase
-- rather than becoming trivial pocket change the moment RealEstateEmpire
-- got its own capstone price bump.
--
-- Long-term appreciation: unlike Assets, Investments don't generate income,
-- but holding one long enough still grows its value (real-world calendar
-- time, keeps compounding while offline too) -- +10% every ~3.5 days held,
-- compounding for as long as it's kept, up to a cap (see
-- MAX_APPRECIATION_PERIODS below). Net Worth and sell refunds both use
-- ComputeCurrentValue, not the flat Price, once an investment has been
-- owned a while.
--
-- This is deliberately the *better* long-term play vs. an equal-price
-- Asset -- 10%/3.5 days compounds to roughly 2.3x in a month, ~9x by the
-- time it caps out (~2.5 months held). An Asset's price never grows and
-- its income only accrues while equipped and online. The trade-off runs
-- the other way short-term: an Investment's value doesn't step up at all
-- until a full 3.5-day period has elapsed (ComputeCurrentValue floors
-- partial periods to 0), so it earns nothing in the first few days while
-- an Asset is paying out from minute one -- Assets win for
-- immediate/active income, Investments win for patient/long-term/AFK
-- wealth, but the cap keeps a single early purchase from eventually
-- dwarfing every other net-worth source on its own (uncapped, 10%/3.5
-- days reaches ~135x in 6 months and keeps compounding forever).

export type Investment = {
	Id: string,
	Name: string,
	Price: number,
	Image: string,
}

local InvestmentDatabase = {}

local APPRECIATION_RATE = 0.10
local APPRECIATION_PERIOD_SECONDS = 3.5 * 24 * 60 * 60 -- ~3.5 days
-- Caps compounding at 25 periods (~87.5 days, ~2.5-3 months) so a single
-- early purchase can't grow unbounded forever just by sitting there
-- offline -- 1.1^25 =~ 10.8x the purchase price, then it holds flat.
local MAX_APPRECIATION_PERIODS = 25

local investments: { [string]: Investment } = {
	CopperOre = { Id = "CopperOre", Name = "Copper Ore", Price = 100, Image = "rbxassetid://85646899481683" },
	IronOre = { Id = "IronOre", Name = "Iron Ore", Price = 800, Image = "rbxassetid://89229509277978" },
	SilverBar = { Id = "SilverBar", Name = "Silver Bar", Price = 6000, Image = "rbxassetid://121708659018392" },
	GoldBar = { Id = "GoldBar", Name = "Gold Bar", Price = 45000, Image = "rbxassetid://72838956813822" },
	PlatinumBar = { Id = "PlatinumBar", Name = "Platinum Bar", Price = 350000, Image = "rbxassetid://82765577499842" },
	DiamondOre = { Id = "DiamondOre", Name = "Diamond Ore", Price = 2500000, Image = "rbxassetid://104870970917124" },
	EmeraldOre = { Id = "EmeraldOre", Name = "Emerald Ore", Price = 18000000, Image = "rbxassetid://128307788657328" },
	RubyOre = { Id = "RubyOre", Name = "Ruby Ore", Price = 210000000, Image = "rbxassetid://73899233840909" },
	SapphireOre = { Id = "SapphireOre", Name = "Sapphire Ore", Price = 1600000000, Image = "rbxassetid://133438648565815" },
	MeteoriteOre = { Id = "MeteoriteOre", Name = "Meteorite Ore", Price = 12000000000, Image = "rbxassetid://105175920707349" },
	CelestialCore = { Id = "CelestialCore", Name = "Celestial Core", Price = 5000000000000, Image = "rbxassetid://106239809107728" },
}

function InvestmentDatabase.GetInvestment(id: string): Investment?
	return investments[id]
end

function InvestmentDatabase.GetAllInvestments(): { [string]: Investment }
	return investments
end

-- Current appreciated value of an owned investment: Price * 1.1^periodsHeld,
-- stepping up once per full APPRECIATION_PERIOD_SECONDS elapsed since
-- purchase (real calendar time -- `now`/`purchasedAt` are both os.time()),
-- capped at MAX_APPRECIATION_PERIODS so it plateaus instead of compounding
-- forever.
function InvestmentDatabase.ComputeCurrentValue(id: string, purchasedAt: number, now: number): number
	local investment = investments[id]
	if not investment then
		return 0
	end

	local elapsedSeconds = math.max(now - purchasedAt, 0)
	local periods = math.min(math.floor(elapsedSeconds / APPRECIATION_PERIOD_SECONDS), MAX_APPRECIATION_PERIODS)
	return investment.Price * (1 + APPRECIATION_RATE) ^ periods
end

-- A single owned entry can represent more than one unit (bought via the
-- x1/x10/x100 quantity buttons) -- this is the one place that multiplies
-- by Quantity, so every caller (StatsManager's net worth, sell payout,
-- trade valuation, NetWorthPanel/TradePanel display) stays in sync
-- instead of each re-deriving it. `Quantity` defaults to 1 for old saved
-- entries from before this field existed.
function InvestmentDatabase.ComputeEntryValue(entry: { Id: string, PurchasedAt: number, Quantity: number? }, now: number): number
	return InvestmentDatabase.ComputeCurrentValue(entry.Id, entry.PurchasedAt, now) * (entry.Quantity or 1)
end

return InvestmentDatabase
