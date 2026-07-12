-- Rig R6 simplu, construit din Parts, folosit pentru NPC-urile statice de
-- langa standuri (Token Shop, Egg Shop) -- fara sa depinda de niciun
-- template din ServerStorage. Un template incercat anterior (TestNPC) avea
-- rig-ul intern rupt (Head la 228 studs distanta de HumanoidRootPart, nu
-- sudat corect), asa ca preferam un rig construit de la zero, unde fiecare
-- piesa e pozitionata si sudata explicit relativ la acelasi cframe -- mereu
-- corect, indiferent de ce exista sau nu in ServerStorage.

local TweenService = game:GetService("TweenService")

local NPCKeeperBuilder = {}

-- Weld simplu: calculeaza C0 (cu C1 identitate) ca Part1 sa ramana exact
-- unde a fost pozitionat manual, relativ la Part0.
local function weld(part0, part1, jointName)
	local motor = Instance.new("Motor6D")
	motor.Name = jointName
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = part0.CFrame:Inverse() * part1.CFrame
	motor.Parent = part0
	return motor
end

-- Construieste rig-ul la pozitia/orientarea data de `cframe`, anchorat,
-- nemiscator (WalkSpeed 0), fara nameplate implicit deasupra capului.
function NPCKeeperBuilder.Build(cframe, name)
	local model = Instance.new("Model")
	model.Name = name or "NPCKeeper"

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.Anchored = true
	rootPart.CFrame = cframe
	rootPart.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.BrickColor = BrickColor.new("Reddish brown")
	torso.Anchored = true
	torso.CFrame = cframe
	torso.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.BrickColor = BrickColor.new("Light orange")
	head.Anchored = true
	head.CFrame = cframe * CFrame.new(0, 1.7, 0)
	head.Parent = model

	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head

	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(1, 2, 1)
	rightArm.BrickColor = BrickColor.new("Light orange")
	rightArm.Anchored = true
	rightArm.CFrame = cframe * CFrame.new(1.5, 0, 0)
	rightArm.Parent = model

	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(1, 2, 1)
	leftArm.BrickColor = BrickColor.new("Light orange")
	leftArm.Anchored = true
	leftArm.CFrame = cframe * CFrame.new(-1.5, 0, 0)
	leftArm.Parent = model

	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(1, 2, 1)
	rightLeg.BrickColor = BrickColor.new("Dark stone grey")
	rightLeg.Anchored = true
	rightLeg.CFrame = cframe * CFrame.new(0.5, -2, 0)
	rightLeg.Parent = model

	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(1, 2, 1)
	leftLeg.BrickColor = BrickColor.new("Dark stone grey")
	leftLeg.Anchored = true
	leftLeg.CFrame = cframe * CFrame.new(-0.5, -2, 0)
	leftLeg.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	weld(rootPart, torso, "RootJoint")
	weld(torso, head, "Neck")
	weld(torso, rightArm, "Right Shoulder")
	weld(torso, leftArm, "Left Shoulder")
	weld(torso, rightLeg, "Right Hip")
	weld(torso, leftLeg, "Left Hip")

	model.PrimaryPart = rootPart

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	return model
end

-- Roteste umarul drept inainte-inapoi, in bucla, la nesfarsit -- fara sa
-- depinda de niciun Animation asset.
function NPCKeeperBuilder.StartWave(model)
	local torso = model:FindFirstChild("Torso")
	local rightShoulder = torso and torso:FindFirstChild("Right Shoulder")

	if not rightShoulder then
		return
	end

	local baseC0 = rightShoulder.C0
	local waveC0 = baseC0 * CFrame.Angles(0, 0, math.rad(-110))

	local waveTween = TweenService:Create(
		rightShoulder,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{C0 = waveC0}
	)
	waveTween:Play()
end

return NPCKeeperBuilder
