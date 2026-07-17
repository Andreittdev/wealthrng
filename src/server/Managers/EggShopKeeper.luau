-- NPC-ul care sta langa Egg Shop, face cu mana -- fara text deasupra
-- capului (spre deosebire de cel de la Token Shop, aici s-a cerut explicit
-- "fara text doar un npc").
--
-- ModuleScript, apelat explicit de EggShopStand.server.luau DUPA ce
-- PetShop e relocat, ca sa nu existe risc de race condition intre scripturi.

local NPCKeeperBuilder = require(script.Parent:WaitForChild("NPCKeeperBuilder"))

local EggShopKeeper = {}

-- Pozitie aproximativa, langa trigger -- nu au fost date coordonate exacte
-- (spre deosebire de standul de Token Shop); spune-mi daca trebuie mutat.
function EggShopKeeper.Spawn(petShop, position)
	local workspaceParent = petShop.Parent

	local existingKeeper = workspaceParent:FindFirstChild("EggShopKeeper")
	if existingKeeper then
		existingKeeper:Destroy()
	end

	local keeperCFrame = CFrame.new(position)
		* CFrame.Angles(0, math.rad(90), 0)

	local keeper = NPCKeeperBuilder.Build(keeperCFrame, "EggShopKeeper")
	keeper.Parent = workspaceParent

	NPCKeeperBuilder.StartWave(keeper)

	return keeper
end

return EggShopKeeper
