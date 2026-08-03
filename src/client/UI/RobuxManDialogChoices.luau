-- Small floating reply-choice buttons for the "Robux Man" NPC dialogue --
-- deliberately NOT a big modal panel (this is a quick "pick a reply,
-- Robux Man answers with another bubble" interaction, not a screen you
-- need to dismiss). Appears just above screen-center, no backdrop -- the
-- game keeps rendering behind it. RobuxManManager.luau (server) sends the
-- choice list right after his bubble-chat greeting; this shows the
-- buttons, and picking one fires the choice back and hides them again.

local Theme = require(script.Parent.Theme)

local RobuxManDialogChoices = {}

local BUTTON_HEIGHT = 58
local BUTTON_GAP = 10

function RobuxManDialogChoices.Create(screenGui: ScreenGui, remotes: Folder)
	local robuxManShowChoices = remotes:WaitForChild("RobuxManShowChoices")
	local robuxManChoiceSelected = remotes:WaitForChild("RobuxManChoiceSelected")

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 420, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 0.62, 0)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.ZIndex = 9
	container.Parent = screenGui
	Theme.AutoScale(screenGui, container, 420)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, BUTTON_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local function clearButtons()
		for _, child in container:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
	end

	robuxManShowChoices.OnClientEvent:Connect(function(choices: { { Id: string, Text: string } })
		clearButtons()

		-- Empty list -- server's ANSWER_DISPLAY_SECONDS timer expired
		-- without the player clicking anything -- just hide, nothing to show.
		if #choices == 0 then
			container.Visible = false
			return
		end

		for order, choice in choices do
			local button = Theme.Button(container, UDim2.new(1, 0, 0, BUTTON_HEIGHT), UDim2.new(0, 0, 0, 0), choice.Text, order == 1)
			button.LayoutOrder = order
			button.TextWrapped = true
			button.Activated:Connect(function()
				robuxManChoiceSelected:FireServer(choice.Id)
				container.Visible = false
				clearButtons()
			end)
		end

		container.Visible = true
	end)

	local handle = {}
	handle.Frame = container
	return handle
end

return RobuxManDialogChoices
