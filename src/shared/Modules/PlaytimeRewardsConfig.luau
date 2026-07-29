-- Playtime Rewards: stand near the plaza's purple "Playtime Rewards" floor
-- marker (MapBuilder's buildFloorMarker) to see a ladder of milestones,
-- each unlocking independently once ACCUMULATED time actually spent in the
-- game (tracked server-side, persisted, keeps counting across sessions --
-- not a real-world calendar gate like Daily Rewards) reaches that
-- milestone's ThresholdSeconds. Unlike Daily Rewards' single "next day"
-- pointer, every milestone here has its own claimed/unclaimed state, so
-- multiple can be sitting ready to claim (or counting down) at once.
--
-- Cash + Potion only (per the original ask -- "dam la playeri cash si
-- potiuni"). PotionIds is nil for cash-only milestones; when set,
-- PotionDurationSeconds (if given) OVERRIDES each granted potion's own
-- PotionDatabase.DurationSeconds -- e.g. Milestone 3 hands out a Luck
-- Potion for 20 minutes even though a normally-bought one only lasts 10.

export type Milestone = {
	ThresholdSeconds: number,
	CashAmount: number,
	PotionIds: { string }?,
	PotionDurationSeconds: number?,
}

local PlaytimeRewardsConfig = {}

-- 5 milestones at 10/20/30/45/60 minutes -- values stay modest next to the
-- core loop's pacing (AssetDatabase's header: ~30 min of ACTIVE play to
-- $1,000,000), since this rewards passive time spent in the game, not
-- active grinding. Milestones 3 and 5 are Potion-only (CashAmount = 0, no
-- $ shown on their card) -- the "special item" slots.
PlaytimeRewardsConfig.Milestones = {
	{ ThresholdSeconds = 10 * 60, CashAmount = 1000 },
	{ ThresholdSeconds = 20 * 60, CashAmount = 5000 },
	{ ThresholdSeconds = 30 * 60, CashAmount = 0, PotionIds = { "LuckPotion" }, PotionDurationSeconds = 20 * 60 },
	{ ThresholdSeconds = 45 * 60, CashAmount = 20000 },
	{
		ThresholdSeconds = 60 * 60,
		CashAmount = 0,
		PotionIds = { "LuckPotion", "SpeedPotion", "FortunePotion" },
		PotionDurationSeconds = 15 * 60,
	},
}

return PlaytimeRewardsConfig
