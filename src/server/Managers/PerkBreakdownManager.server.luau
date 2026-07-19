local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerkSummary = require(script.Parent:WaitForChild("PerkSummary"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getPerkBreakdownFunction = remotes:WaitForChild("GetPerkBreakdown")

getPerkBreakdownFunction.OnServerInvoke = function(player)
	return PerkSummary.GetBreakdown(player)
end
