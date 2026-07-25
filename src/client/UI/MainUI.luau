-- Orchestrator: creates the one ScreenGui, wires the 5 remotes to the 3
-- panels. RollResult is consumed directly inside RollPanel (not routed
-- through here) since it's purely a display concern of the reveal window.
--
-- Named MainUI (not init/Init) so it's an unambiguous plain ModuleScript --
-- same reasoning as Main.server.luau/Main.client.luau avoiding Rojo's
-- init-file convention.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatsPanel = require(script.Parent.StatsPanel)
local InventoryPanel = require(script.Parent.InventoryPanel)
local RollPanel = require(script.Parent.RollPanel)

local MainUI = {}

function MainUI.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local inventoryUpdated = remotesFolder:WaitForChild("InventoryUpdated")
	local statsUpdated = remotesFolder:WaitForChild("StatsUpdated")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WealthRNG_UI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local statsHandle = StatsPanel.Create(screenGui)
	local inventoryHandle = InventoryPanel.Create(screenGui, remotesFolder)
	local rollHandle = RollPanel.Create(screenGui, remotesFolder)

	statsUpdated.OnClientEvent:Connect(function(stats)
		statsHandle.Update(stats)
		rollHandle.SetVIP(stats.IsVIP)
	end)

	inventoryUpdated.OnClientEvent:Connect(inventoryHandle.Render)
end

return MainUI
