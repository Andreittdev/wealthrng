-- Double Cash gamepass (299 Robux) -- the single strongest economic
-- gamepass in the game: +100% cash from BOTH sell value (SellManager.luau)
-- AND passive income (item + Assets, via IncomeConfig.luau). Stacks
-- additively with VIP/Potion/Friend Boost, same "stack, don't replace"
-- shape used everywhere else. Deliberately does NOT touch Investments --
-- those grow on their own separate schedule, they're not "income" (see
-- InvestmentDatabase's header).

local DoubleCashConfig = {}

DoubleCashConfig.GamepassId = 1932255498

DoubleCashConfig.BonusPercent = 100

return DoubleCashConfig
