-- Right-side inventory list. Same data flow as the old PlaceholderUI
-- (InventoryUpdated -> Render, Sell button -> SellItem:FireServer), just
-- restyled through Theme with rarity-colored cards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local Theme = require(script.Parent.Theme)

local InventoryPanel = {}

function InventoryPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local sellItem = remotes:WaitForChild("SellItem")

	local frame = Instance.new("ScrollingFrame")
	frame.Size = UDim2.new(0, 260, 0.6, 0)
	frame.Position = UDim2.new(1, -276, 0, 16)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.ScrollBarThickness = 6
	frame.ScrollBarImageColor3 = Theme.Colors.Accent
	frame.Parent = screenGui
	frame.Visible = false
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
		frame.Visible = not frame.Visible
	end

	function handle.Render(inventory: { { Uid: number, ItemId: string } })
		for _, child in frame:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for _, entry in inventory do
			local item = ItemDatabase.GetItem(entry.ItemId)
			if not item then
				continue
			end

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 54)
			row.BackgroundColor3 = Theme.Colors.Surface
			row.BackgroundTransparency = 0
			row.BorderSizePixel = 0
			row.Parent = frame
			Theme.Round(row, UDim.new(0, 8))
			Theme.Stroke(row, RarityConfig.GetColor(item.Rarity), 2)

			local nameLabel = Theme.Label(row, UDim2.new(0.58, 0, 0, 24), string.format("%s ($%d)", item.Name, item.Value))
			nameLabel.Position = UDim2.new(0, 10, 0, 6)

			local incomeLabel = Theme.Label(row, UDim2.new(0.58, 0, 0, 18), string.format("+$%d/s", item.IncomePerSecond))
			incomeLabel.Position = UDim2.new(0, 10, 0, 30)
			incomeLabel.TextColor3 = Theme.Colors.Success

			local sellButton = Theme.Button(row, UDim2.new(0.36, 0, 0.55, 0), UDim2.new(1, -10, 0.5, 0), "Sell")
			sellButton.AnchorPoint = Vector2.new(1, 0.5)
			sellButton.BackgroundColor3 = Theme.Colors.Danger
			sellButton.TextColor3 = Color3.fromRGB(255, 255, 255)

			sellButton.Activated:Connect(function()
				sellItem:FireServer(entry.Uid)
			end)
		end
	end

	return handle
end

return InventoryPanel
