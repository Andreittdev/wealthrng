local Players = game:GetService("Players")

-- Avatarul 3D REAL (rig-ul jucatorului, cu hainele/accesoriile lui curente),
-- stand pe fiecare piedestal de podium (cele 3 table de leaderboard:
-- Cash/Time Played/Robux Spent) -- nu doar o poza plata. Se actualizeaza
-- automat cand cineva e depasit, pentru ca fiecare tabla re-cheama
-- SetAvatar la fiecare refresh (30s), cu UserId-ul curent de pe locul
-- respectiv -- modelul vechi e distrus si inlocuit doar daca UserId-ul
-- chiar s-a schimbat (nu la fiecare refresh, indiferent de schimbare).
--
-- In plus, fiecare avatar se ROTESTE sa priveasca spre orice jucator
-- apropiat (cerut explicit -- "sa se uite la caracterul meu"), la fel cum ar
-- face un NPC -- doar pe orizontala (nu se apleaca), revine la orientarea
-- implicita (cu spatele la panou) cand nu mai e nimeni aproape.
local PodiumAvatars = {}

-- Animatia standard de "idle" a lui Roblox (R15) -- fara ea, un rig oprit
-- ramane in poza bruta (bind pose), care arata teapan/"impaiat". Cu ea,
-- personajul respira/misca usor, natural, ca un jucator care doar sta pe loc.
local IDLE_ANIMATION_ID = "rbxassetid://507766388"

local LOOK_RADIUS = 40
local LOOK_UPDATE_INTERVAL = 0.2

-- PERFORMANTA: 9 rig-uri complete (3 table x Top 3), fiecare cu animatie de
-- idle continua, permanent in scena, erau principala cauza de FPS scazut --
-- randate/animate tot timpul, chiar si cand nimeni nu era prin preajma sa le
-- vada. Acum modelul e SCOS din workspace (Parent = nil, deci nu se mai
-- randeaza/animeaza deloc) cat timp niciun jucator nu e in raza asta -- doar
-- reapare cand chiar conteaza. Mai mare decat LOOK_RADIUS, ca sa nu clipeasca
-- exact la marginea unde s-ar uita la tine.
local VISIBILITY_RADIUS = 100

-- Toate piedestalele atasate vreodata (9 in total -- 3 table x Top 3) --
-- lista STABILA, pe toata durata serverului (doar slot.Model se schimba cand
-- se schimba rank-urile) -- bucla de "priveste spre jucator" de mai jos
-- itereaza prin ea, fara sa aiba nevoie de curatare separata la fiecare
-- schimbare de avatar.
local allSlots = {}

-- Un "slot" per piedestal -- tine minte modelul curent afisat, UserId-ul lui
-- si orientarea implicita (cu spatele la panou), ca SetAvatar sa stie cand sa
-- NU faca nimic (acelasi jucator inca pe loc) fata de cand chiar trebuie sa
-- schimbe modelul. facingAwayFrom (Vector3, optional) = pozitia tablei/
-- panoului, folosita ca orientare IMPLICITA cand nu e niciun jucator aproape.
function PodiumAvatars.Attach(podiumPart, podiumHeight, facingAwayFrom)
	local slot = {
		Part = podiumPart,
		Height = podiumHeight,
		FacingAwayFrom = facingAwayFrom,
		RestCFrame = nil,
		Model = nil,
		UserId = nil
	}

	table.insert(allSlots, slot)
	return slot
end

-- BUG gasit (varianta anterioara): foloseam podiumPart.CFrame direct pentru
-- orientare -- dar rotatia unui bloc simplu e intamplatoare (nu a fost
-- gandita niciodata ca sa reprezinte "fata inainte", blocurile arata la fel
-- indiferent cum sunt rotite) -- de-aia unele personaje aparea cu spatele.
local function computeFacingCFrame(podiumPart, facingAwayFrom)
	local podiumPosition = podiumPart.Position

	if not facingAwayFrom then
		return CFrame.new(podiumPosition)
	end

	local direction = Vector3.new(podiumPosition.X - facingAwayFrom.X, 0, podiumPosition.Z - facingAwayFrom.Z)

	if direction.Magnitude < 0.01 then
		return CFrame.new(podiumPosition)
	end

	return CFrame.lookAt(podiumPosition, podiumPosition + direction.Unit)
end

-- Aseaza modelul EXACT deasupra piedestalului, cu picioarele pe suprafata de
-- sus (nu ingropat/plutind), cu fata spre jucatori (nu spre panou). Ingheata
-- DOAR radacina (HumanoidRootPart) -- e un mannequin de afisat, nu un NPC
-- viu, fara fizica/coliziuni/click-uri, fara bara de viata/nume plutind
-- deasupra -- dar restul rig-ului ramane liber, legat prin Motor6D-urile
-- proprii, ca sa poata reda animatia de idle si sa se roteasca natural.
local function placeModel(model, slot)
	-- BUG gasit: fara PrimaryPart setat explicit, Model:PivotTo() foloseste
	-- un pivot calculat automat (nu neaparat radacina rig-ului) -- pe un
	-- model cu multe piese/Motor6D-uri, asta putea imprastia bucati departe
	-- de podium sau ingropa jumatate din personaj in piedestal.
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if rootPart then
		model.PrimaryPart = rootPart
	end

	-- Pozitionare in 2 pasi: (1) plasare + orientare implicita, (2) corectie
	-- exacta pe verticala folosind bounding box-ul REAL al modelului, ca
	-- picioarele sa atinga suprafata de sus a piedestalului -- functioneaza
	-- indiferent de R6/R15 sau inaltimea avatarului (nu depindem de o
	-- constanta gen HipHeight, ghicita).
	model:PivotTo(computeFacingCFrame(slot.Part, slot.FacingAwayFrom))

	local boundingCFrame, boundingSize = model:GetBoundingBox()
	local currentBottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	local desiredBottomY = slot.Part.Position.Y + slot.Part.Size.Y / 2

	model:PivotTo(model:GetPivot() + Vector3.new(0, desiredBottomY - currentBottomY, 0))

	-- Tinuta minte pentru bucla de "priveste spre jucator" -- pozitia
	-- (corecta, cu picioarele pe piedestal) NU se mai schimba dupa asta,
	-- doar rotatia se modifica live.
	slot.RestCFrame = model:GetPivot()

	-- BUG gasit: ancorarea FIECAREI piese individual, imediat, o inghetata
	-- in pozitia ei bruta -- inainte ca imbinarile Motor6D dintre cap/
	-- torso/membre sa fi fost rezolvate intr-o poza corecta -- rezultatul
	-- era un "totem" de bucati stivuite, nu un personaj stand normal.
	-- Solutia standard: ancoram DOAR radacina -- restul rig-ului ramane legat
	-- de ea prin Motor6D-urile proprii, deci se pozitioneaza si ramane
	-- corect, la fel cum sta un personaj normal.
	local humanoid = model:FindFirstChildOfClass("Humanoid")

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.Anchored = (descendant == rootPart)
		end
	end

	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		local ok = pcall(function()
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
			local animation = Instance.new("Animation")
			animation.AnimationId = IDLE_ANIMATION_ID

			local track = animator:LoadAnimation(animation)
			track.Looped = true
			track:Play()
		end)

		if not ok then
			warn("PodiumAvatars: idle animation failed to load for " .. model.Name)
		end
	end
end

-- userId poate fi nil (nimeni pe locul asta inca) -- distruge modelul in loc
-- sa lase un avatar vechi/gresit stand acolo.
function PodiumAvatars.SetAvatar(slot, userId)
	if not slot or slot.UserId == userId then
		return
	end

	slot.UserId = userId

	if slot.Model then
		slot.Model:Destroy()
		slot.Model = nil
	end

	if not userId then
		return
	end

	-- CreateHumanoidModelFromUserId cere date de la Roblox (avatarul curent
	-- al jucatorului) -- poate dura -- facut async, ca sa nu blocheze bucla
	-- de refresh a intregii table cat timp asteptam raspunsul.
	task.spawn(function()
		local model

		local ok = pcall(function()
			model = Players:CreateHumanoidModelFromUserId(userId)
		end)

		-- Rank-ul s-a schimbat DIN NOU cat timp modelul se incarca -- aruncam
		-- ce am construit, ca sa nu apara peste jucatorul nou de pe loc.
		if not ok or not model or slot.UserId ~= userId then
			if model then
				model:Destroy()
			end
			return
		end

		model.Name = "PodiumAvatar"
		placeModel(model, slot)
		-- NU parentat inca -- ramane ascuns (nerandat/neanimat) pana cand
		-- bucla de mai jos detecteaza un jucator aproape si il arata.
		model.Parent = nil

		-- BUG gasit (audit): daca rank-ul oscileaza (A -> B -> A) tot in
		-- fereastra cat dureaza CreateHumanoidModelFromUserId, DOUA task-uri
		-- separate pentru A pot trece amandoua verificarea de mai sus (acelasi
		-- userId final) -- fara asta, al doilea suprascria slot.Model fara sa
		-- distruga modelul lasat de primul, scapand un rig animat needistrus.
		if slot.Model and slot.Model ~= model then
			slot.Model:Destroy()
		end

		slot.Model = model
	end)
end

-- Bucla comuna, o singura data pentru toate cele 9 piedestale -- la fiecare
-- 0.2s: (1) decide daca modelul ar trebui sa fie VIZIBIL (cineva in raza
-- VISIBILITY_RADIUS) -- il parenteaza/scoate din workspace in consecinta, (2)
-- daca e vizibil SI cineva e suficient de aproape (LOOK_RADIUS), il roteste
-- (doar pe orizontala) sa priveasca spre el; altfel ramane cu spatele la panou.
task.spawn(function()
	while true do
		task.wait(LOOK_UPDATE_INTERVAL)

		local players = Players:GetPlayers()

		for _, slot in ipairs(allSlots) do
			local model = slot.Model

			if model and slot.RestCFrame then
				local nearestPosition, nearestDistance

				for _, plr in ipairs(players) do
					local character = plr.Character
					local charRoot = character and character:FindFirstChild("HumanoidRootPart")

					if charRoot then
						local distance = (charRoot.Position - slot.Part.Position).Magnitude

						if not nearestDistance or distance < nearestDistance then
							nearestDistance = distance
							nearestPosition = charRoot.Position
						end
					end
				end

				local shouldBeVisible = nearestDistance ~= nil and nearestDistance <= VISIBILITY_RADIUS

				if shouldBeVisible and model.Parent ~= slot.Part then
					model.Parent = slot.Part
				elseif not shouldBeVisible and model.Parent ~= nil then
					model.Parent = nil
				end

				if shouldBeVisible then
					local root = model.PrimaryPart

					if root then
						if nearestDistance <= LOOK_RADIUS then
							local flatTarget = Vector3.new(nearestPosition.X, root.Position.Y, nearestPosition.Z)

							if (flatTarget - root.Position).Magnitude > 0.5 then
								root.CFrame = CFrame.lookAt(root.Position, flatTarget)
							end
						else
							root.CFrame = slot.RestCFrame
						end
					end
				end
			end
		end
	end
end)

return PodiumAvatars
