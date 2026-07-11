local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local VIP_PASS_ID = 1898198234

local function playerHasVIP(player)
	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, VIP_PASS_ID)
	end)

	return success and result
end

local function createVIPTag(character)
	local head = character:WaitForChild("Head", 5)
	if not head then return end

	if head:FindFirstChild("VIPTag") then
		head.VIPTag:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VIPTag"
	billboard.Size = UDim2.new(0, 120, 0, 35)
	billboard.StudsOffset = Vector3.new(0, 2.7, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "?? VIP"
	label.TextColor3 = Color3.fromRGB(255, 215, 80)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("IsVIP", false)

	task.spawn(function()
		local hasVIP = playerHasVIP(player)
		player:SetAttribute("IsVIP", hasVIP)
	end)

	player.CharacterAdded:Connect(function(character)
		task.wait(1)

		if player:GetAttribute("IsVIP") == true then
			createVIPTag(character)
		end
	end)
end)