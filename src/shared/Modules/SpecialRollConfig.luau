-- Special Roll tiers: independently and simultaneously (NOT a shared
-- sequential ladder where only one tier is "next" at a time), each tier
-- counts up session.SpecialRollProgress[tier.Id] toward its own Threshold,
-- capped there once reached (so it just sits "ready" instead of
-- overflowing). RollPanel shows one icon+countdown badge per tier, all
-- counting down at once. Claiming a tier resets ONLY that tier's own
-- progress back to 0, so it immediately starts counting toward its next
-- repeat while the other tiers keep counting (or sitting ready)
-- completely independently.
--
-- Three Kinds of tier, all driven by RollManager.luau but on different
-- clocks:
--   "Rolls" (Golden/Diamond/Ruby/Emerald) -- progress is actual rolls
--   made, +1 per successful normal roll (see advanceSpecialRollProgress).
--   Each tier's OWN entry in session.SpecialRollProgress, resets to 0 on
--   that tier's own claim, sits ready again independently.
--   "SecondsStage" (Lucky Roll I-VI) -- 6 tiers that all share ONE
--   underlying online-time counter (session.SpecialRollProgress[tier.
--   ProgressKey], all six point at the same key "Lucky") instead of each
--   having their own -- +1 per second per connected player (see the
--   per-second loop near the bottom of RollManager.luau), capped at the
--   final stage's Threshold (90 min). Claiming an early stage does NOT
--   reset the shared counter (the later stages still need it to keep
--   climbing) -- it only flips that one stage's own entry in
--   session.ClaimedLuckyStages so it can't be claimed twice in the same
--   cycle. Only claiming the LAST stage (IsFinalStage = true) resets the
--   shared counter AND every stage's claimed flag back to the start,
--   beginning a fresh 90-minute climb from Stage 1 again.
--   (There is no plain "Seconds" kind anymore -- Lucky used to be one
--   repeating tier like that, replaced by this 6-stage ladder below.)
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
--
-- Golden/Diamond/Ruby/Emerald's Luxury weight is a fixed ABSOLUTE number,
-- not a multiplier on RarityConfig's baseline -- these 4 tiers are now
-- effectively the ONLY realistic way to get a Luxury item at all
-- (RarityConfig.Luxury was walked down to almost zero, see that file's
-- header) precisely because these 4 don't get VIP/Potion/Upgrade's luck
-- stack the way normal rolls do, so tuning odds here (rather than the
-- shared baseline, which a VIP's stack multiplies straight through and
-- keeps blowing the balance between a F2P and a fully-boosted player) is
-- the only lever that moves "time to first Luxury item" for both
-- populations by roughly the same fixed amount, leaving only their
-- different ROLLING SPEED (not their odds) to separate them. Currently
-- ~1 in 25,020 (Golden) -> 5,005 (Diamond) -> 1,252 (Ruby) -> 251
-- (Emerald) for the tier-slot, each roughly a 5x step. Emerald staying the
-- single best "Rolls" tier makes sense either way: 1000 rolls is a real
-- grind on top of everything else it already takes to get there.
--
-- Lucky Roll's 6 SecondsStage tiers below use DIFFERENT math entirely --
-- their target callout is the ULTRA multiplier (what LuckyRollProximityPanel
-- actually displays as "Nx Odds!"), not the Luxury one the 4 tiers above
-- are tuned around, climbing 195x -> 400x -> 1000x -> 1500x -> 3000x ->
-- 5000x across the 90-minute cycle. RarityConfig's Ultra weight was cut
-- further (0.35 -> 0.05, see that file) specifically to leave enough room
-- for a 5000x Ultra multiplier to be achievable without needing more than
-- 100% of a stage's rolls to land Ultra -- at 5000x it's ~30% of Stage
-- VI's rolls, comfortably under that ceiling. Common/Rare/Epic/Legendary
-- are held at Lucky's original flat 120/200/210/140 shape for all 6
-- stages -- only Ultra/Luxury climb, and Luxury rides along at the same
-- ratio to Ultra as the original single Lucky tier had, so it also climbs
-- from a modest bump up through a genuinely great one by Stage VI, all
-- without needing separate reasoning per stage.
--
-- List ORDER matters beyond display: RollPanel.luau's "which ready tier
-- does the dice show" picks the LAST Available entry it finds while
-- iterating this list -- but Lucky's 6 stages are entirely excluded from
-- that (HUD_MILESTONES filters out every "SecondsStage" tier, see
-- RollPanel.luau), so only Golden/Diamond/Ruby/Emerald's relative order
-- matters for it, and that's unchanged (weakest -> strongest).
-- LuckyRollProximityPanel.luau sorts the 6 stages by Threshold itself
-- rather than depending on their order here, so their position in this
-- list doesn't matter functionally -- grouped together after Emerald
-- purely for readability.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)

local SpecialRollConfig = {}

export type Tier = {
	Id: string,
	Name: string,
	Kind: "Rolls" | "SecondsStage",
	Threshold: number,
	Color: Color3,
	Weights: { [string]: number },
	Image: string,
	-- SecondsStage only: which session.SpecialRollProgress key this stage
	-- reads its (shared) progress from, the shared counter's overall cap,
	-- and whether claiming this stage resets the whole shared cycle.
	ProgressKey: string?,
	CycleLengthSeconds: number?,
	IsFinalStage: boolean?,
}

local milestones: { Tier } = {
	{
		Id = "Golden",
		Name = "Golden Roll",
		Kind = "Rolls",
		Threshold = 20,
		Color = Color3.fromRGB(255, 205, 60),
		-- ~1.9% Ultra (unchanged) -- Luxury ~1 in 25,020 for the tier-slot
		-- (before the ~45/55 split between the 2 actual Luxury items) --
		-- the first rung of the ladder, already a real bump over a normal
		-- roll (which is now almost never, see RarityConfig.luau's header).
		Weights = { Common = 300, Rare = 250, Epic = 150, Legendary = 60, Ultra = 15, Luxury = 0.03098 },
		Image = "rbxassetid://89136851778573",
	},
	{
		Id = "Diamond",
		Name = "Diamond Roll",
		Kind = "Rolls",
		Threshold = 100,
		Color = Color3.fromRGB(140, 220, 255),
		-- ~5.5% Ultra (unchanged) -- Luxury ~1 in 5,005 for the tier-slot --
		-- clearly better than Golden.
		Weights = { Common = 150, Rare = 220, Epic = 200, Legendary = 110, Ultra = 40, Luxury = 0.14388 },
		Image = "rbxassetid://86728358274379",
	},
	{
		Id = "Ruby",
		Name = "Ruby Roll",
		Kind = "Rolls",
		Threshold = 500,
		Color = Color3.fromRGB(220, 40, 70),
		-- ~20% Ultra (unchanged) -- Luxury ~1 in 1,252 for the tier-slot --
		-- a considerable jump, good items land often enough to actually see it.
		Weights = { Common = 40, Rare = 120, Epic = 220, Legendary = 220, Ultra = 150, Luxury = 0.59912 },
		Image = "rbxassetid://93022166299604",
	},
	{
		Id = "Emerald",
		Name = "Emerald Roll",
		Kind = "Rolls",
		Threshold = 1000,
		Color = Color3.fromRGB(40, 210, 120),
		-- ~93% Ultra (unchanged) -- Luxury ~1 in 251 for the tier-slot (~1 in
		-- ~558 for the rarer of the 2 actual Luxury items once the
		-- item-level split is applied) -- the single best tier in the game,
		-- practically only Ultra/Luxury land. Combined with the fact
		-- charging Emerald doesn't cost any EXTRA rolls (every normal roll
		-- advances it passively, see advanceSpecialRollProgress), this
		-- fixed 1-in-251 shot is what does virtually all the work bringing
		-- "time to first Luxury item" down to a reasonable timeframe for an
		-- active player (see RarityConfig.luau's header for the full
		-- reasoning -- normal rolls barely contribute at all anymore).
		Weights = { Common = 1, Rare = 2, Epic = 5, Legendary = 12, Ultra = 350, Luxury = 1.47825 },
		Image = "rbxassetid://108236184835796",
	},
	-- Lucky Roll's 6-stage ladder -- one shared 90-minute online-time
	-- counter (ProgressKey = "Lucky"), Threshold climbing in 15-min steps
	-- (900/1800/.../5400 seconds), each stage's Ultra multiplier climbing
	-- 195x -> 5000x (see the header comment above for the full math).
	--
	-- Common/Rare/Epic used to be held flat at 120/200/210 for every stage
	-- (only Ultra/Luxury climbed) -- turned out misleading in practice: at
	-- "1000x Odds!" (Stage III), Common was STILL a ~17% roll (120 out of a
	-- ~713 total), because the multiplier badge only ever described Ultra's
	-- odds specifically, never the overall distribution. Players reasonably
	-- read "1000x" as "this stage is now 1000x better," not "just Ultra is."
	-- Fixed by making Common/Rare/Epic shrink stage-over-stage too (Legendary
	-- held flat at 140 -- it keeps growing in RELATIVE share on its own as
	-- Common/Rare/Epic shrink around it, without needing its own explicit
	-- taper), so each stage's real overall feel escalates, not just its
	-- Ultra tail: Common lands ~18% at Stage I, ~11% at II, ~5.5% at III,
	-- ~2.4% at IV, ~0.8% at V, and ~0.1% (genuinely rare) by Stage VI --
	-- Legendary alone is ~60% of Stage VI's rolls, Ultra ~30% (still exactly
	-- the 5000x-over-baseline target), practically no Common/Rare left.
	-- Ultra/Luxury were re-solved for each stage's new (smaller) tier total
	-- so their multiplier-over-baseline targets land on the exact same
	-- 195x/400x/1000x/1500x/3000x/5000x as before -- shrinking the other 4
	-- tiers changes the tier's total weight, which would otherwise silently
	-- drift Ultra's displayed multiplier if its own weight didn't move too.
	{
		Id = "Lucky1",
		Name = "Lucky Roll I",
		Kind = "SecondsStage",
		Threshold = 15 * 60,
		Color = Color3.fromRGB(180, 100, 255),
		Weights = { Common = 120, Rare = 200, Epic = 210, Legendary = 140, Ultra = 7.98, Luxury = 0.0033 },
		Image = "rbxassetid://0",
		ProgressKey = "Lucky",
		CycleLengthSeconds = 90 * 60,
	},
	{
		Id = "Lucky2",
		Name = "Lucky Roll II",
		Kind = "SecondsStage",
		Threshold = 30 * 60,
		Color = Color3.fromRGB(180, 100, 255),
		Weights = { Common = 60, Rare = 150, Epic = 200, Legendary = 140, Ultra = 13.60, Luxury = 0.00563 },
		Image = "rbxassetid://0",
		ProgressKey = "Lucky",
		CycleLengthSeconds = 90 * 60,
	},
	{
		Id = "Lucky3",
		Name = "Lucky Roll III",
		Kind = "SecondsStage",
		Threshold = 45 * 60,
		Color = Color3.fromRGB(180, 100, 255),
		Weights = { Common = 25, Rare = 90, Epic = 170, Legendary = 140, Ultra = 27.30, Luxury = 0.01129 },
		Image = "rbxassetid://0",
		ProgressKey = "Lucky",
		CycleLengthSeconds = 90 * 60,
	},
	{
		Id = "Lucky4",
		Name = "Lucky Roll IV",
		Kind = "SecondsStage",
		Threshold = 60 * 60,
		Color = Color3.fromRGB(180, 100, 255),
		Weights = { Common = 8, Rare = 40, Epic = 110, Legendary = 140, Ultra = 29.66, Luxury = 0.01227 },
		Image = "rbxassetid://0",
		ProgressKey = "Lucky",
		CycleLengthSeconds = 90 * 60,
	},
	{
		Id = "Lucky5",
		Name = "Lucky Roll V",
		Kind = "SecondsStage",
		Threshold = 75 * 60,
		Color = Color3.fromRGB(180, 100, 255),
		Weights = { Common = 2, Rare = 15, Epic = 60, Legendary = 140, Ultra = 47.97, Luxury = 0.01985 },
		Image = "rbxassetid://0",
		ProgressKey = "Lucky",
		CycleLengthSeconds = 90 * 60,
	},
	{
		Id = "Lucky6",
		Name = "Lucky Roll VI",
		Kind = "SecondsStage",
		Threshold = 90 * 60,
		Color = Color3.fromRGB(180, 100, 255),
		Weights = { Common = 0.3, Rare = 3, Epic = 20, Legendary = 140, Ultra = 70.56, Luxury = 0.02919 },
		Image = "rbxassetid://0",
		ProgressKey = "Lucky",
		CycleLengthSeconds = 90 * 60,
		IsFinalStage = true,
	},
}

SpecialRollConfig.Milestones = milestones

-- How many times more likely a given rarity is to land on this tier vs. a
-- normal roll (base RarityConfig weights, no VIP/Potion/Upgrade) -- the
-- "16x" style callout RollPanel.luau shows on the Lucky Roll badge, same
-- games-like-Sol's-RNG convention of flashing a multiplier instead of a
-- raw percentage. Pure math over the two weight tables, so it stays
-- accurate automatically if either one is ever retuned.
function SpecialRollConfig.GetLuckMultiplier(tier: Tier, rarity: string): number
	local baseTotal = 0
	for _, r in RarityConfig.Order do
		baseTotal += RarityConfig.Tiers[r].Weight
	end
	local baseProbability = RarityConfig.Tiers[rarity].Weight / baseTotal
	if baseProbability <= 0 then
		return 0
	end

	local tierTotal = 0
	for _, weight in tier.Weights do
		tierTotal += weight
	end
	local tierProbability = (tier.Weights[rarity] or 0) / tierTotal

	return tierProbability / baseProbability
end

return SpecialRollConfig
