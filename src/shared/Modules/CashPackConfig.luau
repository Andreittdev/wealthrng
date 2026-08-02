-- Cash Packs: Developer Products (NOT Game Passes -- these are meant to be
-- bought repeatedly, unlike every other Shop entry). Each one credits a
-- flat amount of in-game Cash immediately, no other effect. Ordered
-- cheapest first -- ShopPanel.luau lists them in this order.

local CashPackConfig = {}

-- Bumped up from their original amounts -- the 199R$/349R$ tiers used to
-- give $10M/$25M, the exact same amounts DailyRewardsConfig's Day 5/6 now
-- hand out for free, so paying real Robux got you literally nothing over
-- just logging in. The 199R$+ tiers now clear the best single free daily
-- reward ($25M, Day 6) by a wide margin; the two cheapest tiers (5R$/49R$)
-- are still below it by design -- they're impulse-buy intro tiers, not
-- meant to beat a full day's login reward.
CashPackConfig.Packs = {
	{ ProductId = 3612687901, RobuxPrice = 5, CashAmount = 500000 },
	{ ProductId = 3612687969, RobuxPrice = 49, CashAmount = 3500000 },
	{ ProductId = 3612688017, RobuxPrice = 199, CashAmount = 55000000 },
	{ ProductId = 3612688112, RobuxPrice = 349, CashAmount = 267000000 },
	{ ProductId = 3612688193, RobuxPrice = 999, CashAmount = 1000000000 },
}

function CashPackConfig.GetPack(productId: number)
	for _, pack in CashPackConfig.Packs do
		if pack.ProductId == productId then
			return pack
		end
	end
	return nil
end

return CashPackConfig
