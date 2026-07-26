-- Right-side inventory list. Same data flow as the old PlaceholderUI
-- (InventoryUpdated -> Render, Sell button -> SellItem:FireServer), just
-- restyled through Theme with rarity-colored cards.
--
-- Items only earn IncomePerSecond while equipped -- only ItemDatabase.
-- MaxEquipped (currently 1) can be equipped at once, so tapping Equip on
-- a new row just swaps out whichever one was equipped before (server-side
-- swap in InventoryManager.Equip, this panel doesn't need to know). Each
-- row gets an Equip/Unequip toggle alongside Sell, and a header shows the
-- slot count.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local InventoryPanel = {}

function InventoryPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local sellItem = remotes:WaitForChild("SellItem")
	local equipItem = remotes:WaitForChild("EquipItem")
	local unequipItem = remotes:WaitForChild("UnequipItem")
	local equippedItemsUpdated = remotes:WaitForChild("EquippedItemsUpdated")

	local currentInventory: { { Uid: number, ItemId: string } } = {}
	local equippedUids: { number } = {}

	local outer = Instance.new("Frame")
	outer.Size = UDim2.new(0, 260, 0.6, 24)
	outer.Position = UDim2.new(1, -276, 0, 16)
	outer.BackgroundTransparency = 1
	outer.Parent = screenGui
	outer.Visible = false

	local statusLabel = Theme.Label(outer, UDim2.new(1, 0, 0, 20), "Equipped: 0/0")
	statusLabel.TextColor3 = Theme.Colors.TextSecondary

	local frame = Instance.new("ScrollingFrame")
	frame.Size = UDim2.new(1, 0, 1, -24)
	frame.Position = UDim2.new(0, 0, 0, 24)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.ScrollBarThickness = 6
	frame.ScrollBarImageColor3 = Theme.Colors.Accent
	frame.Parent = outer
	Theme.Round(frame)
	Theme.Stroke(frame, Color3.fromRGB(255, 215, 140), 1)
	Theme.Shadow(frame)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	local handle = {}

	function handle.Toggle()
		outer.Visible = not outer.Visible
	end

	local function render()
		statusLabel.Text = string.format("Equipped: %d/%d", #equippedUids, ItemDatabase.MaxEquipped)

		for _, child in frame:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for _, entry in currentInventory do
			local item = ItemDatabase.GetItem(entry.ItemId)
			if not item then
				continue
			end

			local isEquipped = table.find(equippedUids, entry.Uid) ~= nil

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 78)
			row.BackgroundColor3 = Theme.Colors.Surface
			row.BackgroundTransparency = 0
			row.BorderSizePixel = 0
			row.Parent = frame
			Theme.Round(row, UDim.new(0, 8))
			Theme.Stroke(row, isEquipped and Theme.Colors.Accent or RarityConfig.GetColor(item.Rarity), isEquipped and 2.5 or 2)

			local nameLabel = Theme.Label(row, UDim2.new(1, -20, 0, 22), string.format("%s (%s)", item.Name, NumberFormat.FormatCash(item.Value)))
			nameLabel.Position = UDim2.new(0, 10, 0, 6)

			local incomeText = "+" .. NumberFormat.FormatCash(item.IncomePerSecond) .. "/s"
			local incomeLabel = Theme.Label(
				row,
				UDim2.new(1, -20, 0, 16),
				isEquipped and (incomeText .. " (equipped)") or (incomeText .. " if equipped")
			)
			incomeLabel.Position = UDim2.new(0, 10, 0, 28)
			incomeLabel.TextColor3 = isEquipped and Theme.Colors.Success or Theme.Colors.TextSecondary

			local equipButton = Theme.Button(row, UDim2.new(0.48, 0, 0, 26), UDim2.new(0, 10, 1, -34), isEquipped and "Unequip" or "Equip", not isEquipped)
			equipButton.Activated:Connect(function()
				if isEquipped then
					unequipItem:FireServer(entry.Uid)
				else
					equipItem:FireServer(entry.Uid)
				end
			end)

			local sellButton = Theme.Button(row, UDim2.new(0.48, 0, 0, 26), UDim2.new(1, -10, 1, -34), "Sell")
			sellButton.AnchorPoint = Vector2.new(1, 0)
			sellButton.BackgroundColor3 = Theme.Colors.Danger
			sellButton.TextColor3 = Color3.fromRGB(255, 255, 255)
			sellButton.Activated:Connect(function()
				sellItem:FireServer(entry.Uid)
			end)
		end
	end

	function handle.Render(inventory: { { Uid: number, ItemId: string } })
		currentInventory = inventory
		render()
	end

	equippedItemsUpdated.OnClientEvent:Connect(function(uids: { number })
		equippedUids = uids
		render()
	end)

	return handle
end

return InventoryPanel
