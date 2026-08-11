-- Pure leaf: the live-mob registry (HP, existence) plus simple proximity/
-- damage primitives -- no dependency on PetManager, EndlessModeMobManager,
-- or EndlessModeAllyManager, so all three of those can read/damage mobs
-- without requiring each other back. Same "shared leaf so nobody has to
-- require the 'real' manager" idiom PotionConfig.luau/IncomeConfig.luau use
-- to dodge circular requires.
--
-- Owns nothing about WALKING/targeting/base damage -- that's
-- EndlessModeMobManager's job. This only tracks "how much HP does this mob
-- Part have left" and "which registered mob is closest to X".

local EndlessModeMobRegistry = {}

type MobEntry = {
	HP: number,
	MaxHP: number,
	OnDeath: (() -> ())?,
	OnDamage: ((number, number) -> ())?,
}

local mobs: { [BasePart]: MobEntry } = {}

-- `onDeath` fires exactly once, the instant this mob's HP first reaches 0
-- from ANY source (a Tank/Ally melee tick or a Damage building) -- lets
-- EndlessModeMobManager clean up whatever walk/melee state that mob was in
-- without needing to poll a "did someone else already kill this" flag.
-- `onDamage(currentHP, maxHP)` fires on every hit that DOESN'T kill it --
-- lets a caller (EndlessModeMobManager.luau's floating HP bar) redraw
-- without polling either.
function EndlessModeMobRegistry.Register(mob: BasePart, hp: number, onDeath: (() -> ())?, onDamage: ((number, number) -> ())?)
	mobs[mob] = { HP = hp, MaxHP = hp, OnDeath = onDeath, OnDamage = onDamage }
end

function EndlessModeMobRegistry.Unregister(mob: BasePart)
	mobs[mob] = nil
end

function EndlessModeMobRegistry.IsAlive(mob: BasePart): boolean
	return mobs[mob] ~= nil
end

-- Returns true if this hit killed it -- by the time this returns, `mob` is
-- already unregistered and its OnDeath already fired, so callers don't need
-- to separately check IsAlive right after.
function EndlessModeMobRegistry.Damage(mob: BasePart, amount: number): boolean
	local entry = mobs[mob]
	if not entry then
		return false
	end

	entry.HP -= amount
	if entry.HP > 0 then
		if entry.OnDamage then
			entry.OnDamage(entry.HP, entry.MaxHP)
		end
		return false
	end

	mobs[mob] = nil
	if entry.OnDeath then
		entry.OnDeath()
	end
	return true
end

-- Nearest currently-alive REPLICATED mob to `position`, within `maxRange`
-- studs if given (nil = unlimited). Nil if none are in range -- callers
-- (Damage buildings, Allies) just skip their attack for that tick.
function EndlessModeMobRegistry.GetNearestAliveMob(position: Vector3, maxRange: number?): BasePart?
	local nearest: BasePart? = nil
	local nearestDistance = maxRange or math.huge
	for mob in mobs do
		if mob.Parent then
			local distance = (mob.Position - position).Magnitude
			if distance <= nearestDistance then
				nearestDistance = distance
				nearest = mob
			end
		end
	end
	return nearest
end

return EndlessModeMobRegistry
