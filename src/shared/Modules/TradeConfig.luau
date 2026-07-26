-- Single source of truth for the trading Net Worth gate, shared by
-- TradeManager (server, authoritative) and TradePanel (client, so the
-- player picker can show the requirement without a round trip).

local TradeConfig = {}

TradeConfig.MinNetWorth = 1000000

return TradeConfig
