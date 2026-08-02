-- Small popup that appears automatically -- same proximity-only pattern as
-- VIPProximityPanel.luau, no ProximityPrompt/"Press E" -- while standing
-- near the plaza's blue "Group Rewards" floor marker (MapBuilder's
-- buildFloorMarker). Button reads Locked (not in the group) / Claim (in
-- the group, not claimed yet) / Claimed Rewards (already claimed) -- the
-- actual grant + IsInGroup re-check happens server-side
-- (GroupRewardsManager.luau), this is display-only.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroupRewardsConfig = require(ReplicatedStorage.Modules.GroupRewardsConfig)
local Theme = require(script.Parent.Theme)
local ProximityWatcher = require(script.Parent.ProximityWatcher)

local GroupRewardsProximityPanel = {}

local PROXIMITY_RADIUS_STUDS = 10

function GroupRewardsProximityPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local claimGroupReward = remotes:WaitForChild("ClaimGroupReward")
	local groupRewardStateUpdated = remotes:WaitForChild("GroupRewardStateUpdated")

	-- Centered, not bottom-anchored with a fixed "-300" offset -- that
	-- pushed the panel off the top of a short landscape phone screen (same
	-- issue DailyRewardsProximityPanel/LuckyRollProximityPanel had). Safe
	-- to center: this panel is already in MainUI's modalFrames list, so
	-- RollPanel's bottom HUD is hidden the whole time this is open anyway.
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 320, 0, 230)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel)
	Theme.Stroke(panel, Color3.fromRGB(140, 190, 255), 1)
	local panelShadow = Theme.Shadow(panel)
	-- Fixed-pixel popup (unlike the sidebar-triggered dialogs, which use
	-- Theme.ResponsivePanel) -- shrinks as one unit toward its bottom-center
	-- anchor on narrow phone screens instead of running off the edges.
	-- Shadow is a sibling, not a descendant (see Theme.Shadow's comment), so
	-- it needs its OWN matching AutoScale call -- both compute the exact
	-- same Scale independently (pure function of screen width), so they
	-- stay in sync without needing to be linked.
	Theme.AutoScale(screenGui, panel, 320)
	Theme.AutoScale(screenGui, panelShadow, 320)

	local titleLabel = Theme.Label(panel, UDim2.new(1, -20, 0, 30), "Group Rewards", true)
	titleLabel.Position = UDim2.new(0, 10, 0, 10)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center

	local stepsLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 66), "")
	stepsLabel.Position = UDim2.new(0, 12, 0, 44)
	stepsLabel.TextWrapped = true
	stepsLabel.TextYAlignment = Enum.TextYAlignment.Top
	stepsLabel.TextXAlignment = Enum.TextXAlignment.Left
	stepsLabel.TextColor3 = Theme.Colors.TextSecondary
	stepsLabel.Text = "1. Like the game!\n2. Join the group!\nEnjoy the rewards!"

	-- Display copy only -- still grants the single $50,000 Epic
	-- GroupRewardChest item (GroupRewardsConfig.RewardItemId), just
	-- described as "$50K & Free Epic Item" instead of spelling out the
	-- item's exact name/rarity/value.
	local rewardLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 20), "")
	rewardLabel.Position = UDim2.new(0, 12, 0, 116)
	rewardLabel.TextColor3 = Theme.Colors.Accent
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.Text = "Reward: $50K & Free Epic Item"

	local actionButton = Theme.Button(panel, UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -46), "Locked", true)
	actionButton.Activated:Connect(function()
		claimGroupReward:FireServer()
	end)

	local inGroup = false
	local ok, result = pcall(function()
		return Players.LocalPlayer:IsInGroup(GroupRewardsConfig.GroupId)
	end)
	if ok then
		inGroup = result
	end

	local claimed = false
	local function refreshButton()
		if claimed then
			actionButton.Text = "Claimed Rewards"
			actionButton.Active = false
			actionButton.AutoButtonColor = false
			actionButton.BackgroundColor3 = Theme.Colors.Success
			actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		elseif inGroup then
			actionButton.Text = "Claim"
			actionButton.Active = true
			actionButton.AutoButtonColor = true
			actionButton.BackgroundColor3 = Theme.Colors.Accent
			actionButton.TextColor3 = Color3.fromRGB(20, 20, 20)
		else
			actionButton.Text = "Locked"
			actionButton.Active = false
			actionButton.AutoButtonColor = false
			actionButton.BackgroundColor3 = Theme.Colors.Surface
			actionButton.TextColor3 = Theme.Colors.TextSecondary
		end
	end
	refreshButton()

	groupRewardStateUpdated.OnClientEvent:Connect(function(newClaimed: boolean)
		claimed = newClaimed
		refreshButton()
	end)

	-- Same self-healing retry as VIPProximityPanel.luau -- re-resolves
	-- Workspace.Map itself (not just the child lookup) in case a stale Map
	-- existed at t=0 and got destroyed/rebuilt out from under a cached
	-- reference.
	task.spawn(function()
		local marker: BasePart? = nil
		while not marker do
			local mapFolder = Workspace:WaitForChild("Map")
			marker = mapFolder:WaitForChild("GroupRewardsMarker_Disk", 5) :: BasePart?
		end

		ProximityWatcher.Register(marker, PROXIMITY_RADIUS_STUDS, function(inRange)
			panel.Visible = inRange
		end)
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return GroupRewardsProximityPanel
