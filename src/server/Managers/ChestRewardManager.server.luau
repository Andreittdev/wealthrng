-- Recompensa de la Chest (cerc "GROUP REWARDS", vezi ChestStand.server.luau).
-- Text-ul cere "Like + Join Group", dar tehnic NU putem verifica un Like
-- (Roblox nu expune deloc informatia asta scripturilor, indiferent de API) --
-- verificam DOAR apartenenta la grup (player:IsInGroup), pe incredere pentru
-- Like. Recompensa: o singura data per jucator, persistata prin DataManager.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local claimChestRewardFunction = remotes:FindFirstChild("ClaimChestReward")
if not claimChestRewardFunction then
	claimChestRewardFunction = Instance.new("RemoteFunction")
	claimChestRewardFunction.Name = "ClaimChestReward"
	claimChestRewardFunction.Parent = remotes
end

-- Lock per-jucator -- player:IsInGroup face un yield (apel de retea), iar
-- intre verificarea ChestRewardClaimed si SetAttribute-ul de mai jos exista
-- o fereastra reala in care 2-3 InvokeServer trase rapid (client modificat,
-- sau doar spam) treceau TOATE de verificarea "already claimed" inainte ca
-- vreuna sa apuce sa seteze attribute-ul -- bani duplicati. Acelasi tipar ca
-- buyInProgress din NPCManager.server.luau.
local claimInProgress = {}

claimChestRewardFunction.OnServerInvoke = function(player)
	if claimInProgress[player] then
		return {Success = false, Reason = "NotReady"}
	end

	claimInProgress[player] = true

	local function finish(result)
		claimInProgress[player] = nil
		return result
	end

	if player:GetAttribute("ChestRewardClaimed") == true then
		return finish({Success = false, Reason = "AlreadyClaimed"})
	end

	local isInGroup = false
	local ok, result = pcall(function()
		return player:IsInGroup(Economy.ChestReward.GroupId)
	end)

	if ok then
		isInGroup = result
	end

	if not isInGroup then
		return finish({Success = false, Reason = "NotInGroup"})
	end

	-- Re-verificat DUPA yield-ul de mai sus (IsInGroup) -- desi lock-ul de
	-- mai sus opreste deja apeluri concurente, verificarea initiala de mai
	-- sus a rulat inainte de acest yield, deci o repetam ca sa fim siguri.
	if player:GetAttribute("ChestRewardClaimed") == true then
		return finish({Success = false, Reason = "AlreadyClaimed"})
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")

	if not money then
		return finish({Success = false, Reason = "NotReady"})
	end

	money.Value += Economy.ChestReward.Money
	player:SetAttribute("ChestRewardClaimed", true)
	DataManager.SaveData(player)

	return finish({Success = true, Amount = Economy.ChestReward.Money})
end

Players.PlayerRemoving:Connect(function(player)
	claimInProgress[player] = nil
end)
