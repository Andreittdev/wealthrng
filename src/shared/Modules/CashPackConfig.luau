-- Cash Packs: Developer Products (NOT Game Passes -- these are meant to be
-- bought repeatedly, unlike every other Shop entry). Each one credits a
-- flat amount of in-game Cash immediately, no other effect. Ordered
-- cheapest first -- ShopPanel.luau lists them in this order.

local CashPackConfig = {}

CashPackConfig.Packs = {
	{ ProductId = 3612687901, RobuxPrice = 5, CashAmount = 67000 },
	{ ProductId = 3612687969, RobuxPrice = 49, CashAmount = 500000 },
	{ ProductId = 3612688017, RobuxPrice = 199, CashAmount = 10000000 },
	{ ProductId = 3612688112, RobuxPrice = 349, CashAmount = 25000000 },
	{ ProductId = 3612688193, RobuxPrice = 999, CashAmount = 100000000 },
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
