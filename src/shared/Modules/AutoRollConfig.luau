-- Auto Roll gamepass: once purchased and toggled on (see AutoRollManager.luau
-- server-side, ShopPanel.luau client-side), the server keeps rolling for the
-- player automatically -- respecting the exact same cooldown/VIP/Potion/
-- Upgrade stack a manual ROLL click would -- without needing a click each time.

local AutoRollConfig = {}

AutoRollConfig.GamepassId = 1932550391

-- "Get Auto Roll Free" offer (RollPanel.luau's Auto Roll button, when not
-- owned) -- stay connected for this long and it's granted for free,
-- permanently, no Robux needed. Resets if the player disconnects before it
-- finishes (see AutoRollManager.luau) -- has to be earned in one
-- continuous online stretch, not accumulated piecemeal across sessions.
AutoRollConfig.FreeUnlockSeconds = 30 * 60

return AutoRollConfig
