-- Auto Claim gamepass: once purchased, Lucky Roll's per-second server loop
-- (RollManager.luau) automatically claims each of the 6 Lucky Roll stages
-- the instant it becomes ready, without needing to walk up to the marker
-- and press Claim -- same "buy once, server just does it from then on"
-- shape as the Auto Roll gamepass, except there's no on/off toggle for
-- this one (see AutoClaimManager.luau's header for why).
--
local AutoClaimConfig = {}

AutoClaimConfig.GamepassId = 1933305055

return AutoClaimConfig
