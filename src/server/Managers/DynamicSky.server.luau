local Lighting = game:GetService("Lighting")

-- Cer "animat" dar mereu zi: nori 3D care se misca singuri (Roblox le anima
-- automat, nu trebuie scriptat) -- fara ciclu zi/noapte, ClockTime ramane
-- fix la amiaza.
Lighting.ClockTime = 12

local clouds = Lighting:FindFirstChildOfClass("Clouds")
if not clouds then
	clouds = Instance.new("Clouds")
	clouds.Density = 0.5
	clouds.Cover = 0.45
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = Lighting
end
