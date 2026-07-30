-- Special Roll tiers: every normal roll advances EVERY tier's own
-- session.SpecialRollProgress[tier.Id] by 1, independently and
-- simultaneously (capped at that tier's own Threshold once reached, so it
-- just sits "ready" instead of overflowing). RollPanel shows one
-- icon+countdown badge per tier, all counting down at once (Golden every
-- 20 rolls, Diamond every 100, Ruby every 500, Emerald every 1000) --
-- NOT a shared sequential ladder where only one tier is "next" at a time.
-- Claiming a tier resets ONLY that tier's own progress back to 0, so it
-- immediately starts counting toward its next repeat while the other
-- tiers keep counting (or sitting ready) completely independently.
--
-- Back to these original values (briefly 10x'd to 200/1000/5000/10000
-- while Auto Roll had a real bug making it fire far faster than its
-- actual cooldown, which made these look broken -- that bug is fixed now,
-- rolls land at their real cooldown-paced rate, so the original numbers
-- are the right call again: a fully boosted player (VIP + Speed Potion +
-- maxed Roll Speed Upgrade, ~0.3s/roll) refills Golden in ~6s and Emerald
-- in ~5 min -- frequent enough that the ladder is worth paying attention
-- to without a long dry spell between rewards.
--
-- Each tier uses its own fixed absolute rarity weight table (NOT a
-- multiplier on RarityConfig's base weights, and NOT stacked with VIP/
-- Potion/Upgrade luck bonuses) -- a deliberately hand-tuned distribution
-- per tier so the jump in odds from one tier to the next is exact and
-- predictable rather than compounding unpredictably with whatever luck
-- bonuses a player happens to have active at the moment. Must have an
-- entry for every RarityConfig.Order tier.

local SpecialRollConfig = {}

export type Tier = {
	Id: string,
	Name: string,
	Threshold: number,
	Color: Color3,
	Weights: { [string]: number },
	Image: string,
}

local milestones: { Tier } = {
	{
		Id = "Golden",
		Name = "Golden Roll",
		Threshold = 20,
		Color = Color3.fromRGB(255, 205, 60),
		-- ~1.9% Ultra, ~0.02% Luxury (vs base ~0.5% / ~0.002%) -- a real but
		-- restrained bump, "noticeable, not huge".
		Weights = { Common = 300, Rare = 250, Epic = 150, Legendary = 60, Ultra = 15, Luxury = 0.15 },
		Image = "rbxassetid://89136851778573",
	},
	{
		Id = "Diamond",
		Name = "Diamond Roll",
		Threshold = 100,
		Color = Color3.fromRGB(140, 220, 255),
		-- ~5.5% Ultra, ~0.08% Luxury -- clearly better than Golden.
		Weights = { Common = 150, Rare = 220, Epic = 200, Legendary = 110, Ultra = 40, Luxury = 0.6 },
		Image = "rbxassetid://86728358274379",
	},
	{
		Id = "Ruby",
		Name = "Ruby Roll",
		Threshold = 500,
		Color = Color3.fromRGB(220, 40, 70),
		-- ~20% Ultra, ~0.4% Luxury -- a considerable jump, good items land
		-- often enough to actually see it.
		Weights = { Common = 40, Rare = 120, Epic = 220, Legendary = 220, Ultra = 150, Luxury = 3 },
		Image = "rbxassetid://93022166299604",
	},
	{
		Id = "Emerald",
		Name = "Emerald Roll",
		Threshold = 1000,
		Color = Color3.fromRGB(40, 210, 120),
		-- ~93% Ultra, ~1.6% Luxury -- practically only Ultra/Luxury land,
		-- as requested.
		Weights = { Common = 1, Rare = 2, Epic = 5, Legendary = 12, Ultra = 350, Luxury = 6 },
		Image = "rbxassetid://108236184835796",
	},
}

SpecialRollConfig.Milestones = milestones

return SpecialRollConfig
