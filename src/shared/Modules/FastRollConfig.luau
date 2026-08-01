-- Fast Roll gamepass (149 Robux): unlike Luck Pass/Ultra Luck Pass (which
-- only touch rarity odds), this actually shortens how long each roll TAKES
-- to resolve -- both the client-side spin/result-display timing
-- (RollPanel.luau's playReveal) AND the server-side cooldown
-- (RollManager.TryRoll), together, so neither one is left as an unchanged
-- bottleneck behind the other.
--
-- Every roll (shown OR hidden via Hide Rolls) waits AT LEAST
-- SpinSeconds + ResultDisplaySeconds before the next one can fire --
-- that's deliberate (see RollPanel.luau's playReveal header), so cooldown
-- alone was never actually the bottleneck once it dropped under ~2.7s
-- (the un-owned total: 0.9 spin + 1.8 display) -- VIP's 0.75s cooldown
-- already proved that. Owning Fast Roll lowers the 2.7s floor itself to
-- 1.5s (0.5 spin + 1.0 display), a real ~1.8x grind-speed increase, and
-- CooldownMultiplier keeps the server cooldown safely under that new floor
-- across every VIP/Potion/Upgrade combination so it never becomes the new
-- bottleneck instead.
--
-- Rare showcase holds (RollPanel.luau's RARE_RESULT_DISPLAY_SECONDS, for
-- Legendary/Ultra/Luxury) are deliberately NOT shortened by this -- those
-- are the "post it in chat" moments, meant to be savored regardless of how
-- fast the player is set up to grind normal rolls.

local FastRollConfig = {}

FastRollConfig.GamepassId = 1934372912

FastRollConfig.SpinSeconds = 0.5
FastRollConfig.ResultDisplaySeconds = 1.0

FastRollConfig.CooldownMultiplier = 0.6

return FastRollConfig
