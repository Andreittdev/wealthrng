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

claimChestRewardFunction.OnServerInvoke = function(player)
	if player:GetAttribute("ChestRewardClaimed") == true then
		return {Success = false, Reason = "AlreadyClaimed"}
	end

	local isInGroup = false
	local ok, result = pcall(function()
		return player:IsInGroup(Economy.ChestReward.GroupId)
	end)

	if ok then
		isInGroup = result
	end

	if not isInGroup then
		return {Success = false, Reason = "NotInGroup"}
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")

	if not money then
		return {Success = false, Reason = "NotReady"}
	end

	money.Value += Economy.ChestReward.Money
	player:SetAttribute("ChestRewardClaimed", true)
	DataManager.SaveData(player)

	return {Success = true, Amount = Economy.ChestReward.Money}
end
