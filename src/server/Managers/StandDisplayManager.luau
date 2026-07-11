local StandDisplayManager = {}

local function clearDisplay(stand)
	for _, child in ipairs(stand:GetDescendants()) do
		if child.Name == "DisplayedItem" then
			child:Destroy()
		end
	end
end

local function createDisplayItem(itemData, spot, itemDisplay)
	local part = Instance.new("Part")
	part.Name = "DisplayedItem"
	part.Size = Vector3.new(1.1, 0.25, 1.1)
	part.Anchored = true
	part.CanCollide = false
	part.Color = Color3.fromRGB(220, 220, 220)
	part.CFrame = spot.CFrame * CFrame.new(0, 0.45, 0)
	part.Parent = itemDisplay

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ItemNameGui"
	billboard.Size = UDim2.new(0, 100, 0, 28)
	billboard.StudsOffset = Vector3.new(0, 0.8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 35
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = itemData.ItemName or "Item"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.Parent = billboard
end

function StandDisplayManager.UpdateStand(player)
	local generatedStands = workspace:FindFirstChild("GeneratedStands")
	if not generatedStands then return end

	local playerStand = nil

	for _, stand in ipairs(generatedStands:GetChildren()) do
		if stand:GetAttribute("OwnerUserId") == player.UserId then
			playerStand = stand
			break
		end
	end

	if not playerStand then return end

	local itemDisplay = playerStand:FindFirstChild("ItemDisplay", true)
	if not itemDisplay then return end

	local displaySpots = itemDisplay:FindFirstChild("DisplaySpots")
	if not displaySpots then return end

	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	clearDisplay(playerStand)

	local spots = {}

	for _, spot in ipairs(displaySpots:GetChildren()) do
		if spot:IsA("BasePart") then
			table.insert(spots, spot)
		end
	end

	table.sort(spots, function(a, b)
		return a.Name < b.Name
	end)

	for index, item in ipairs(inventory:GetChildren()) do
		local spot = spots[index]
		if not spot then break end

		local itemData = {
			ItemName = item:FindFirstChild("ItemName") and item.ItemName.Value or item.Name
		}

		createDisplayItem(itemData, spot, itemDisplay)
	end
end

return StandDisplayManager