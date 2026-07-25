-- Single source of truth for the base (non-VIP) roll cooldown, shared by
-- RollManager (server, authoritative) and RollPanel (client, UX mirror).

local RollConfig = {}

RollConfig.BaseCooldownSeconds = 1.5

return RollConfig
