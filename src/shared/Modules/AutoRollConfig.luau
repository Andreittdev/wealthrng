-- Auto Roll gamepass: once purchased and toggled on (see AutoRollManager.luau
-- server-side, ShopPanel.luau client-side), the server keeps rolling for the
-- player automatically -- respecting the exact same cooldown/VIP/Potion/
-- Upgrade stack a manual ROLL click would -- without needing a click each time.

local AutoRollConfig = {}

AutoRollConfig.GamepassId = 1932550391

return AutoRollConfig
