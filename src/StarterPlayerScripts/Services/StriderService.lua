local striderModule = {}
striderModule.__index = striderModule
local currentStriders = {}
--game.Players.LocalPlayer:GetMouse().TargetFilter = workspace.Ignore
function striderModule:Start()
	striderModule.Shared.Services.Remotes:Connect("StriderRemote", function(interaction, ...)
		local args = {...}
		if interaction == "Update" then
			local player = args[1]
			local cframe = args[2]
			local speed = args[3]
			local offset = args[4]
			local height = args[5]
			local huddled = args[6]
			local target = args[7]

			if player ~= game.Players.LocalPlayer then
				--currentStriders[player.Name].strider:SetPrimaryPartCFrame(cframe)
				currentStriders[player.Name].speed = speed
				currentStriders[player.Name].offsetVector = offset
				currentStriders[player.Name].height = height
				currentStriders[player.Name].huddled = huddled
				currentStriders[player.Name].target = target
			end
		end
	end)

	while true do
		for _, player in pairs(game.Players:GetPlayers()) do
			task.spawn(function()
				if player:FindFirstChild("StriderObject") and not currentStriders[player.Name] then
					print("starting")
					local newStrider = striderModule.new(player:FindFirstChild("StriderObject").Value)
					currentStriders[player.Name] = newStrider
					newStrider:Initialize(player)
				elseif currentStriders[player.Name] and not player:FindFirstChild("StriderObject") then
					print("removing")
					currentStriders[player.Name]:removeStrider()
					currentStriders[player.Name] = nil
				end
			end)
			task.wait(0.02)
		end
		task.wait()
	end
end



local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ignoreFolder      = workspace.Ignore
local assets            = ReplicatedStorage:WaitForChild("StriderAssets")

local mouse             = game.Players.LocalPlayer:GetMouse()

local function solveIK(originCF, targetPos, l1, l2)	
	-- build intial values for solving
	local localized = originCF:pointToObjectSpace(targetPos)
	local localizedUnit = localized.unit
	local l3 = localized.magnitude

	-- build a "rolled" planeCF for a more natural arm look
	local axis = Vector3.new(0, 0, -1):Cross(localizedUnit)
	local angle = math.acos(-localizedUnit.Z)
	local planeCF = originCF * CFrame.fromAxisAngle(axis, angle)

	-- case: point is to close, unreachable
	-- action: push back planeCF so the "hand" still reaches, angles fully compressed
	if l3 < math.max(l2, l1) - math.min(l2, l1) then
		return planeCF, -math.pi/2, math.pi

		-- case: point is to far, unreachable
		-- action: for forward planeCF so the "hand" still reaches, angles fully extended
	elseif l3 > l1 + l2 then
		return planeCF, math.pi/2, 0

		-- case: point is reachable
		-- action: planeCF is fine, solve the angles of the triangle
	else
		local a1 = -math.acos((-(l2 * l2) + (l1 * l1) + (l3 * l3)) / (2 * l1 * l3))
		local a2 = math.acos(((l2  * l2) - (l1 * l1) + (l3 * l3)) / (2 * l2 * l3))
		return planeCF, a1 + math.pi/2, a2 - a1
	end
end

local cam = workspace.CurrentCamera

local function GetMouseHit(toIgnore)
	local ignore = {workspace.Ignore, toIgnore}

	local pos = UserInputService:GetMouseLocation()
	local camRay = cam:ViewportPointToRay(pos.X, pos.Y, 1)
	local ray = Ray.new(camRay.Origin, camRay.Direction*999)
	local hit, pos, norm, mat = workspace:FindPartOnRayWithIgnoreList(ray, ignore, false, true)

	return hit, CFrame.new(pos, pos+ray.Direction), norm, mat
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function bezierCurve(a, b, c, t)
	return lerp(lerp(a, b, t), lerp(b, c, t), t)
end

local function rndspr(spread)
	-- Returns a random spread based on the spread value
	return Vector3.new(math.random(-spread*100, spread*100)/100, math.random(-spread*100, spread*100)/100, math.random(-spread*100, spread*100)/100)
end


function striderModule.new(strider)
	local self = setmetatable({}, striderModule)

	self.walkSpeed = 10
	self.runSpeed = 18
	self.speed = 0.01
	self.turnRate = 0.02

	self.outAngle = 75 -- The angle the left and right legs will be in degrees
	self.gapDistance = 7 -- The distance between the legs

	self.offsetDistance = 100 
	self.offsetVector = Vector3.new(0.1,-20,0.1)

	self.fireRate = 5 -- In bullets per second (of the minigun)
	self.fireSpeed = 100 -- In studs per second (of the minigun)
	self.spread = 0.7 -- In studs (of the minigun)
	self.warpSpeed = 550 -- In studs per second (of the warp cannon)
	self.warpRate = 0.1 -- In bullets per second (of the warp cannon)
	self.stompDistance = 9 -- In studs

	self.lastVoice = 0
	self.lastWarp = 0
	self.lastFired = 0
	self.lastHuddled = 0

	self.previousVoice = nil
	self.previousStep = nil

	self.maxHeight = 28 -- Max height of the strider with q and e
	self.minHeight = 10 -- Min height of the strider with q and e

	self.voiceCooldown = 3 -- Cooldown between voice lines in seconds
	self.huddleCooldown = 5 -- Cooldown between strider huddling in seconds

	self.strider = strider
	self.striderRef = strider:WaitForChild("Strider_Reference")
	self.mainBone = self.striderRef:WaitForChild("Combine_Strider.Body_Bone")

	self.leftShoulderBone       = self.mainBone:WaitForChild("Combine_Strider.Leg_Left_Bone")
	self.leftLegBone            = self.leftShoulderBone:WaitForChild("Combine_Strider.Leg_Left_Bone1")
	self.leftWristBone          = self.leftLegBone:WaitForChild("Combine_Strider.Foot_Left")

	self.rightShoulderBone      = self.mainBone:WaitForChild("Combine_Strider.Leg_Right_Bone")
	self.rightLegBone           = self.rightShoulderBone:WaitForChild("Combine_Strider.Leg_Right_Bone1")
	self.rightWristBone         = self.rightLegBone:WaitForChild("Combine_Strider.Foot_Right")

	self.hindShoulderBone       = self.mainBone:WaitForChild("Combine_Strider.Leg_Hind_Bone")
	self.hindLegBone            = self.hindShoulderBone:WaitForChild("Combine_Strider.Leg_Hind_Bone1")
	self.hindWristBone          = self.hindLegBone:WaitForChild("Combine_Strider.Foot_Hind")

	self.UPPER_LENGTH			= math.abs(self.leftLegBone.Position.X)
	self.LOWER_LENGTH			= math.abs(self.leftWristBone.Position.X)
	self.legLength              = self.UPPER_LENGTH + self.LOWER_LENGTH

	self.projService            = striderModule.Shared.Services.ProjectileService

	local oldPos = self.striderRef.Position

	self.leftShoulderBone.CFrame = CFrame.new(self.leftShoulderBone.Position)
	self.rightShoulderBone.CFrame = CFrame.new(self.rightShoulderBone.Position)
	self.hindShoulderBone.CFrame = CFrame.new(self.hindShoulderBone.Position)
	self.leftLegBone.CFrame = CFrame.new(self.leftLegBone.Position)
	self.rightLegBone.CFrame = CFrame.new(self.rightLegBone.Position)
	self.hindLegBone.CFrame = CFrame.new(self.hindLegBone.Position)


	local LEFT_SHOULDER_C0_CACHE		= self.leftShoulderBone.CFrame
	local LEFT_SHOULDER_WORLD_CACHE     = self.leftShoulderBone.WorldCFrame
	local LEFT_ELBOW_C0_CACHE		    = self.leftLegBone.CFrame

	local RIGHT_SHOULDER_C0_CACHE		= self.rightShoulderBone.CFrame
	local RIGHT_SHOULDER_WORLD_CACHE    = self.rightShoulderBone.WorldCFrame
	local RIGHT_ELBOW_C0_CACHE		    = self.rightLegBone.CFrame

	local HIND_SHOULDER_C0_CACHE		= self.hindShoulderBone.CFrame
	local HIND_SHOULDER_WORLD_CACHE     = self.hindShoulderBone.WorldCFrame
	local HIND_ELBOW_C0_CACHE		    = self.hindLegBone.CFrame



	self.height = 25
	self.dt = 0.01
	self.startHealth = self.strider.Humanoid.Health
	self.huddled = self.strider:WaitForChild("Huddled").Value
	self.huddling = false
	self.huddleDone = false
	self.outAngle = self.outAngle + self.height * 3.5
	self.newAngle = self.outAngle + self.height
	self.distFactor = (math.sqrt(self.legLength^2 - self.height^2))
	self.originalDistFactor = self.distFactor

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	self.rayParams.FilterDescendantsInstances = {strider, ignoreFolder}

	self.overlapParams = OverlapParams.new()
	self.overlapParams.FilterType = Enum.RaycastFilterType.Blacklist
	self.overlapParams.FilterDescendantsInstances = {strider, ignoreFolder}

	self.targetVector = Vector3.new()
	self.target = CFrame.new()
	self.RemoteConnection = striderModule.Shared.Services.Remotes:Connect("StriderRemote", function(...)
		self:OnRemoteEvent(...)
	end)

	self.legs = {
		["Left"] = {
			["goal"] = CFrame.new(),
			["shoulder"] = self.leftShoulderBone,
			["leg"] = self.leftLegBone,
			["wrist"] = self.leftWristBone,
			["shoulderC0"] = LEFT_SHOULDER_C0_CACHE,
			["shoulderWorld"] = LEFT_SHOULDER_WORLD_CACHE,
			["elbowC0"] = LEFT_ELBOW_C0_CACHE,
			["groundPart"] = nil,
			["desiredPosition"] = Vector3.new()
		},
		["Right"] = {
			["goal"] = CFrame.new(),
			["shoulder"] = self.rightShoulderBone,
			["leg"] = self.rightLegBone,
			["wrist"] = self.rightWristBone,
			["shoulderC0"] = RIGHT_SHOULDER_C0_CACHE,
			["shoulderWorld"] = RIGHT_SHOULDER_WORLD_CACHE,
			["elbowC0"] = RIGHT_ELBOW_C0_CACHE,
			["groundPart"] = nil,
			["desiredPosition"] = Vector3.new()

		},
		["Hind"] = {
			["goal"] = CFrame.new(),
			["shoulder"] = self.hindShoulderBone,
			["leg"] = self.hindLegBone,
			["wrist"] = self.hindWristBone,
			["shoulderC0"] = HIND_SHOULDER_C0_CACHE,
			["shoulderWorld"] = HIND_SHOULDER_WORLD_CACHE,
			["elbowC0"] = HIND_ELBOW_C0_CACHE,
			["groundPart"] = nil,
			["desiredPosition"] = Vector3.new()
		},
	}

	local downResult = workspace:Raycast(self.legs["Hind"].shoulder.TransformedWorldCFrame.Position, Vector3.new(0, -100, 0), self.rayParams)
	local newCF = self.striderRef.CFrame
	if downResult then
		newCF = CFrame.new(downResult.Position, downResult.Position + newCF.LookVector)
	end
	self.legs["Hind"].goal = CFrame.new(newCF.Position)
	self.legs["Left"].goal = CFrame.new((newCF * CFrame.new(-self.gapDistance, 0, 0)).Position)
	self.legs["Right"].goal = CFrame.new((newCF * CFrame.new(self.gapDistance, 0, 0)).Position)

	for _, leg in pairs(self.legs) do
		local fullOffset = self.striderRef.CFrame:ToObjectSpace(leg.goal).Position
		local offset = Vector3.new(fullOffset.X, 0, fullOffset.Z)
		leg.offset = offset
	end
	return self
end

function striderModule:MovementCheck()
	return not self.huddled and not self.huddling and not self.strider:FindFirstChild("Dead")
end

function striderModule:Initialize(player)
	local currentCamera = workspace.CurrentCamera

	--self.striderRef.Anchored = true
	-- Calculate time PER leg using basic physics equation and then dividing by 3
	self.legTime = self.distFactor / math.abs(self.speed) / 3 

	-- Calculate the distance we want the legs to move per each leg movement (adding shoulderbone Z to account for the offset of the shoulder)
	self.moveDist = self.distFactor * self.legTime + self.speed + self.hindShoulderBone.Position.Z * (self.striderRef.CFrame.LookVector:Dot((self.targetVector - self.striderRef.Position).Unit * Vector3.new(1,0,1)))

	for _, boneRef in pairs(self.legs) do
		-- We do this to make the legs independant of the main bone to prevent the animations from interfering with the leg movement
		boneRef.shoulder.Parent = self.striderRef
	end

	local startRefPos = self.striderRef.CFrame
	self.player = player

	if player == game.Players.LocalPlayer then
		repeat task.wait() until currentCamera.CameraSubject
		self.Character = player.Character or player.CharacterAdded:Wait()
		self.healthInterface = assets.Interface.StriderHealth:Clone()
		self.healthInterface.Parent = self.player.PlayerGui
		-- Server initialization (network ownership)
		striderModule.Shared.Services.Remotes:Fire("StriderRemote", "Start", self.strider)
	end



	self.walkAnim = self.strider.Humanoid:LoadAnimation(assets.Animations.StriderWalk)
	self.idleAnim = self.strider.Humanoid:LoadAnimation(assets.Animations.StriderIdle)
	self.Heartbeat = RunService.Heartbeat:Connect(function(dt)
		if self.strider.Parent == nil then
			self:removeStrider()
			return
		end
		if self.striderRef.CamPart:FindFirstChild("WeldConstraint") then
			self.striderRef.CamPart.WeldConstraint:Destroy()
		end
		if self.strider:FindFirstChild("Dead") then
			self.Heartbeat:Disconnect()
			self:striderDeath()
			return
		end
		-- This is used to calculate the leg speed (for you bastards using fps unlockers)
		self.dt = dt

		if self.speed > 0.5 then
			if not self.walkAnim.IsPlaying and self:MovementCheck() then
				self.walkAnim:Play()
				self.idleAnim:Stop()
			end
		else
			if not self.idleAnim.IsPlaying and self:MovementCheck() then
				self.idleAnim:Play()
				self.walkAnim:Stop()
			end
		end

		if not self.huddled then
			self.mainBone.Position = Vector3.new(0,self.height - 15,0)
		end

		if player == game.Players.LocalPlayer then
			self.Character:WaitForChild("Humanoid").WalkSpeed = 0
			local hit, cf, norm, mat = GetMouseHit(self.strider)
			self.target = cf
			self.striderRef.CamPart.Position = CFrame.new(self.mainBone.WorldCFrame.Position.X, self.mainBone.TransformedWorldCFrame.Position.Y + 5, self.mainBone.WorldCFrame.Position.Z).Position
			currentCamera.CameraSubject = self.striderRef.CamPart

			local newVector, newSpeed = self:getInputs(dt)

			if self:MovementCheck() then

				self.offsetVector = newVector
				self.speed = newSpeed
				local x, y, z = currentCamera.CFrame:ToOrientation()
				local downResult = workspace:Raycast(self.striderRef.Position + Vector3.new(0,-48 + self.height,0), Vector3.new(0, -100, 0), self.rayParams)

				if downResult then
					self.striderRef.Position = self.striderRef.Position:Lerp(downResult.Position + Vector3.new(0,50,0), 0.02)
				end

				local startCF = CFrame.new(self.strider.PrimaryPart.Position, Vector3.new(self.targetVector.X, self.striderRef.Position.Y, self.targetVector.Z)).LookVector * -self.speed * dt
				local newCF = CFrame.new(self.strider.PrimaryPart.Position - startCF)
				local _, newY, _ = self.strider.PrimaryPart.CFrame:Lerp(newCF * CFrame.Angles(0, y, 0), self.turnRate):ToOrientation()
				self.strider:SetPrimaryPartCFrame(newCF * CFrame.Angles(0, newY, 0))

			end
			self.healthInterface.Frame.Health.Text = "HEALTH: "..tostring(self.strider.Humanoid.Health)
			striderModule.Shared.Services.Remotes:Fire("StriderRemote","Update", self.striderRef.CFrame, self.speed, self.offsetVector, self.height, self.huddled, self.target)
		end

		self.targetVector = self.striderRef.CFrame * self.offsetVector
		self.distFactor = (math.sqrt(self.legLength^2 - self.height^2))
		if not self.huddling and not self.huddled then
			self.legTime = self.originalDistFactor / math.abs(self.speed) / 3
		end
		self.moveDist = self.distFactor / 3 + self.hindShoulderBone.Position.Z * (self.striderRef.CFrame.LookVector:Dot((self.targetVector - self.striderRef.Position).Unit * Vector3.new(1,0,1))) * (self.distFactor / self.originalDistFactor)

		local neck = self.mainBone["Combine_Strider.Neck_Bone"]["Combine_Strider.Head_Bone"]
		neck.CFrame = CFrame.new(neck.TransformedWorldCFrame.Position, self.target.Position):ToObjectSpace(self.mainBone["Combine_Strider.Neck_Bone"].TransformedWorldCFrame):Inverse()

		if self.huddled then
			self.legs["Hind"].desiredPosition = (self.mainBone.TransformedWorldCFrame * CFrame.new(0,-5,-6)).Position
			self.legs["Left"].desiredPosition = (self.mainBone.TransformedWorldCFrame * CFrame.new(-3,-8, 6)).Position
			self.legs["Right"].desiredPosition = (self.mainBone.TransformedWorldCFrame * CFrame.new(3,-8,6)).Position

			self.legs["Hind"].goal = CFrame.new(self.legs["Hind"].desiredPosition)
			self.legs["Left"].goal = CFrame.new(self.legs["Left"].desiredPosition)
			self.legs["Right"].goal = CFrame.new(self.legs["Right"].desiredPosition)

			self:bendLeg("Left", -180)
			self:bendLeg("Right", 180)
			self:bendLeg("Hind", 0)
		else
			if not self.huddling then
				self:getLegDist("Left", self.moveDist)
				self:getLegDist("Right", self.moveDist)
				self:getLegDist("Hind", self.moveDist)
			end
			self:bendLeg("Left", -self.outAngle + self.height * 3.5)
			self:bendLeg("Right", self.outAngle - self.height * 3.5)
			self:bendLeg("Hind", 0)
		end

	end)
	if self.huddled then
		self:doHuddleLoop()
	end

	local lastLeg = nil
	while true do
		if self.legTime < 3 then
			local furthestLeg = nil
			local furtherIndex = nil
			local furthestDist = 0
			for l,b in pairs(self.legs) do
				local behindDist = (b.goal.Position - self.targetVector) * Vector3.new(1,0,1)
				local behindMag = behindDist.Magnitude
				if b ~= lastLeg and behindMag > furthestDist then
					furthestLeg = b
					furtherIndex = l
					furthestDist = behindMag
				end
			end
			if furthestLeg and self:MovementCheck() then
				lastLeg = furthestLeg
				self:moveLeg(furtherIndex)
			end
		else
			repeat task.wait() until self.legTime < 3
		end

		game:GetService("RunService").Heartbeat:Wait()
	end

end

function striderModule:getInputs(dt)
	-- We have to do this otherwise the strider position will go to NAN and break the entire strider
	local offsetVector = Vector3.new(0.1,-20,0.1)
	local newVector = offsetVector
	local newSpeed = 0.01
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		newVector = newVector + Vector3.new(0,0,-self.offsetDistance)
		newSpeed = self.walkSpeed
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		newVector = newVector + Vector3.new(0,0,self.offsetDistance)
		newSpeed = self.walkSpeed
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		newVector = newVector + Vector3.new(-self.offsetDistance,0,0)
		newSpeed = self.walkSpeed
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		newVector = newVector + Vector3.new(self.offsetDistance,0,0) 
		newSpeed = self.walkSpeed
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		if newSpeed > 0.5 then
			newSpeed = self.runSpeed
		end
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.E) then
		self.height = math.min(self.height + 0.175, self.maxHeight)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		self.height = math.max(self.height - 0.175, self.minHeight)
	end
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		if tick() - self.lastFired > 1 / self.fireRate then
			self:Fire()
			self.lastFired = tick()
		end
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.F) then
		if tick() - self.lastWarp > 1 / self.warpRate then
			self.lastWarp = tick()
			self:FireWarpCannon()
		end
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.R) then
		if tick() - self.lastVoice > self.voiceCooldown then
			self.lastVoice = tick()
			local newIndex = math.random(1, #assets.Sounds.Voice:GetChildren())
			striderModule.Shared.Services.Remotes:Fire("StriderRemote", "Voice", self.strider, newIndex)
		end
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.T) then
		if tick() - self.lastVoice > self.voiceCooldown then
			self.lastVoice = tick()
			local newIndex = math.random(1, #assets.Sounds.Alert:GetChildren())
			striderModule.Shared.Services.Remotes:Fire("StriderRemote", "Alert", self.strider, newIndex)
		end
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.P) then
		if tick() - self.lastHuddled > self.huddleCooldown then
			self.lastHuddled = math.huge
			self.huddled = false
		end
	end
	return newVector, newSpeed
end

function striderModule:bendLeg(boneReference, angle)
	local SHOULDER_C0_CHACHE = self.legs[boneReference].shoulderC0
	local ELBOW_C0_CHACHE = self.legs[boneReference].elbowC0
	local shoulderPos = (self.mainBone.TransformedWorldCFrame * SHOULDER_C0_CHACHE).Position
	local shoulderCFrame = CFrame.new(shoulderPos, shoulderPos + self.striderRef.CFrame.LookVector) * CFrame.Angles(0, math.rad(angle), 0)
	local goalPosition = self.legs[boneReference].goal.Position
	local bottomPos = Vector3.new(shoulderCFrame.Position.X, goalPosition.Y, shoulderCFrame.Position.Z)

	local planeCF, shoulderAngle, elbowAngle = solveIK(shoulderCFrame, goalPosition, self.UPPER_LENGTH, self.LOWER_LENGTH)

	local newCF = planeCF * CFrame.Angles(0,0,0) * CFrame.Angles(shoulderAngle, math.rad(90), math.rad(90))

	self.legs[boneReference].shoulder.WorldCFrame = newCF

	self.legs[boneReference].leg.CFrame = ELBOW_C0_CHACHE * CFrame.Angles(0, 0, elbowAngle)
end

function striderModule:striderDeath()
	self.walkAnim:Stop()
	self.idleAnim:Stop()
	local function createPart(cframe)
		local newPart = Instance.new("Part")
		newPart.Size = Vector3.new(1,1,1)
		newPart.Anchored = false
		newPart.CFrame = cframe
		newPart.Transparency = 1
		newPart.Parent = workspace.Ignore
		newPart.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0, 0.3, 100)
		local newAttachment = Instance.new("Attachment")
		newAttachment.Position = Vector3.new(0,0,0)
		newAttachment.Parent = newPart
		return newPart
	end

	local function createRope(parent1, parent2)
		local newRod = Instance.new("RodConstraint")
		newRod.Attachment0 = parent1
		newRod.Attachment1 = parent2
		newRod.Length = (parent1.WorldPosition - parent2.WorldPosition).Magnitude
		newRod.Visible = false
		newRod.Parent = parent1.Parent
		return newRod
	end

	local legLeftPart = createPart(self.legs["Left"].goal)
	local legRightPart = createPart(self.legs["Right"].goal)
	local legHindPart = createPart(self.legs["Hind"].goal)

	local shoulderHindPart = createPart(self.legs["Hind"].leg.TransformedWorldCFrame)
	local shoulderLeftPart = createPart(self.legs["Left"].leg.TransformedWorldCFrame)
	local shoulderRightPart = createPart(self.legs["Right"].leg.TransformedWorldCFrame)

	createRope(legLeftPart.Attachment, shoulderLeftPart.Attachment)
	createRope(legRightPart.Attachment, shoulderRightPart.Attachment)
	createRope(legHindPart.Attachment, shoulderHindPart.Attachment)
	createRope(shoulderHindPart.Attachment, self.legs["Hind"].shoulder)
	createRope(shoulderLeftPart.Attachment, self.legs["Left"].shoulder)
	createRope(shoulderRightPart.Attachment, self.legs["Right"].shoulder)
	local actualHitbox = self.strider:WaitForChild("ActualHitbox")
	self.striderRef.Anchored = true
	self.deathConnection = RunService.Heartbeat:Connect(function()
		if self.strider.Parent == nil then
			self:removeStrider()
			return
		end
		self.mainBone.WorldCFrame = actualHitbox.CFrame
		if self.player == game.Players.LocalPlayer then
			workspace.CurrentCamera.CameraSubject = actualHitbox
		end
		self.legs["Hind"].shoulder.WorldCFrame = CFrame.new(actualHitbox.CFrame * self.legs["Hind"].shoulderC0.Position, shoulderHindPart.Position) * CFrame.Angles(0, math.rad(90), math.rad(180))
		self.legs["Left"].shoulder.WorldCFrame = CFrame.new(actualHitbox.CFrame * self.legs["Left"].shoulderC0.Position, shoulderLeftPart.Position) * CFrame.Angles(0, math.rad(90), math.rad(180))
		self.legs["Right"].shoulder.WorldCFrame = CFrame.new(actualHitbox.CFrame * self.legs["Right"].shoulderC0.Position, shoulderRightPart.Position) * CFrame.Angles(0, math.rad(90), math.rad(180))

		self.legs["Hind"].leg.WorldCFrame = CFrame.new(shoulderHindPart.Position, legHindPart.Position) * CFrame.Angles(0, math.rad(90), math.rad(180))
		self.legs["Left"].leg.WorldCFrame = CFrame.new(shoulderLeftPart.Position, legLeftPart.Position) * CFrame.Angles(0, math.rad(90), math.rad(180))
		self.legs["Right"].leg.WorldCFrame = CFrame.new(shoulderRightPart.Position, legRightPart.Position) * CFrame.Angles(0, math.rad(90), math.rad(180))
	end)
end


function striderModule:doTween(cancelRef, posRef)
	local Part = self.legs[posRef]
	--local P1, P2, P3 = Part.P1, Part.P2, Part.P3
	local P1 = Part.goal.Position
	local primaryPos = self.strider.ActualHitbox
	local P2 = self.legs[posRef].desiredPosition + Vector3.new(0, 2, 0)
	local P3 = (P2 + P1) / 2 + Vector3.new(0, 4, 0) + primaryPos.CFrame.RightVector * math.random() * 5

	local lerpTime = 0
	local moveTime = self.legTime
	while lerpTime < 1 do
		if self[cancelRef] then
			return
		end
		local P2 = self.legs[posRef].desiredPosition
		local alpha = TweenService:GetValue(lerpTime, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

		Part.goal = CFrame.new(bezierCurve(P1, P3, P2, alpha))

		lerpTime += 1 / (moveTime / self.dt)
		RunService.Heartbeat:Wait()
	end

end

function striderModule:getLegDist(legReference, moveDist)
	local startLeftOffset = self.mainBone.TransformedWorldCFrame * self.legs[legReference]["offset"]
	local leftPos = CFrame.new(startLeftOffset, self.targetVector) * CFrame.new(0,0,-moveDist)
	local leftResult = workspace:Raycast(leftPos.Position, Vector3.new(0,-300,0), self.rayParams)
	if leftResult then
		leftPos = CFrame.new(leftPos.Position + Vector3.new(0, -leftResult.Distance, 0))
		self.legs[legReference]["groundPart"] = leftResult.Instance
	end
	self.legs[legReference]["desiredPosition"] = leftPos.Position
end

function striderModule:moveLeg(posRef)
	local posPart = self.legs[posRef].goal
	self:doTween("huddled", posRef)
	local newStep = assets.Particles.Footstep:Clone()
	newStep.Position = self.legs[posRef].goal.Position + Vector3.new(0, 0.1, 0)
	newStep.Parent = workspace.Ignore
	if self.legs[posRef].groundPart then
		newStep:WaitForChild("ParticleEmitter").Color = ColorSequence.new(self.legs[posRef].groundPart.Color or Color3.fromRGB(120, 125, 136))
	end
	newStep:WaitForChild("ParticleEmitter"):Emit(20)
	Debris:AddItem(newStep, 3)
	local children = assets.Sounds.Steps:GetChildren()
	if self.previousStep then
		table.remove(children, self.previousStep)
	end
	local newIndex = math.random(1,#children)
	local newSound = children[newIndex]:Clone()
	newSound.Parent = newStep
	newSound:Play()
	self.previousStep = newIndex
	Debris:AddItem(newSound, 1)
	local player = self.player
	if player then
		local canTeamKill = self.player:FindFirstChild("CanTeamKill") and self.player:FindFirstChild("CanTeamKill").Value
		if player ~= game.Players.LocalPlayer then
			if player.Team == game.Players.LocalPlayer.Team and not canTeamKill then
				return
			end
			if (self.legs[posRef].goal.Position - game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude < self.stompDistance then
				striderModule.Shared.Services.Remotes:Fire("StriderRemote", "FootDamage")
			end
		end
	end
end

function striderModule:OnRemoteEvent(...)
	local args = {...}
	local player = args[2]
	local action = args[1]
	local strider = args[3]
	if action == "Fire" and strider == self.strider and player ~= game.Players.LocalPlayer then
		self:FireEffects()
	elseif action == "WarpEffects" and strider == self.strider and player ~= game.Players.LocalPlayer then
		local cf = args[4]
		self:WarpCannonEffects(cf)
	end
end

function striderModule:FireEffects()
	local newEmitter = assets.Particles.BulletEmitter:Clone()
	local newSound = assets.Sounds.Firing.Fire:Clone()
	newEmitter.CFrame = self.mainBone["Combine_Strider.Neck_Bone"]["Combine_Strider.Head_Bone"].TransformedWorldCFrame * CFrame.new(0,0,-2)
	newEmitter.Parent = workspace.Ignore
	newSound.Parent = newEmitter
	newSound:Play()
	newEmitter.flash:Emit(1)
	Debris:AddItem(newEmitter, 1)
end

function striderModule:Fire()
	local startPos  = (self.mainBone["Combine_Strider.Neck_Bone"]["Combine_Strider.Head_Bone"].TransformedWorldCFrame * CFrame.new(0,0,-2)).Position
	local hit, cf, norm, mat = GetMouseHit(self.strider)
	local dir       = cf.Position - startPos + rndspr(self.spread)
	local ptime     = time()
	local color     =Color3.fromRGB(94, 199, 255)
	local speed     = 1000
	self.projService:Fire(
		startPos,
		dir, --+ rndspr(self.Config.Stats.Spread),
		speed,
		nil,
		nil,
		nil,
		color,
		{workspace.Ignore, self.strider},
		ptime
	)
	striderModule.Shared.Services.Remotes:Fire("StriderRemote", "Fire", self.strider)
	self:FireEffects(self.strider)
end

function striderModule:doHuddleLoop()
	while true do
		if not self.huddled then
			self.huddling = true
			self.legTime = 1
			self:getLegDist("Left", 1)
			self:getLegDist("Right", 1)
			self:getLegDist("Hind", 1)
			task.spawn(function()
				self:moveLeg("Hind")
			end)
			task.spawn(function()
				self:moveLeg("Left")
			end)
			task.spawn(function()
				self:moveLeg("Right")
			end)

			task.wait(self.legTime)
			self.height = self.mainBone.TransformedWorldCFrame.Position.Y - self.legs["Hind"].desiredPosition.Y - 7
			print(self.height)
			self.striderRef.CFrame = CFrame.new(self.legs["Hind"].desiredPosition + Vector3.new(0, 50, 0))
			--idleAnim:Play()
			self.huddling = false
			break
		end
		task.wait()
	end
end

function striderModule:WarpCannonEffects(cf)
	local startPos  = (self.mainBone["Combine_Strider.Gun_Bone1"]["Combine_Strider.Gun_Bone2"].TransformedWorldCFrame * CFrame.new(-5,-2,0)).Position
	local newParticle = assets.Particles.WarpCannon:Clone()
	newParticle.CFrame = CFrame.new(startPos, cf.Position)

	local moveConnection
	moveConnection = RunService.Heartbeat:Connect(function()
		if not newParticle.Parent then
			moveConnection:Disconnect()
			return
		end
		newParticle.CFrame = CFrame.new((self.mainBone["Combine_Strider.Gun_Bone1"]["Combine_Strider.Gun_Bone2"].TransformedWorldCFrame * CFrame.new(-5,-2,0)).Position, cf.Position)
	end)

	newParticle.Parent = workspace.Ignore
	newParticle.Aura:Emit(1)

	local newTargetPart = Instance.new("Part")
	newTargetPart.Anchored = true
	newTargetPart.CanCollide = false
	newTargetPart.Size = Vector3.new(0.2,0.2,0.2)
	newTargetPart.Transparency = 1
	newTargetPart.CFrame = CFrame.new(cf.Position)
	newTargetPart.Parent = workspace.Ignore

	local newAttachment = Instance.new("Attachment")
	newAttachment.Parent = newTargetPart
	newParticle.Beam.Attachment0 = newAttachment

	local newSound = assets.Sounds.Firing.WarpCharge:Clone()
	newSound.Parent = newParticle
	newSound:Play()

	local newTween = TweenService:Create(newParticle.Beam, TweenInfo.new(1.2), {Width0 = 0.25})
	local newTween2 = TweenService:Create(newParticle.Beam, TweenInfo.new(1.2), {Width1 = 0.25})
	newTween:Play()
	newTween2:Play()
	newParticle.Beam.Transparency = NumberSequence.new(0.7,0.7)

	newSound.Ended:Wait()
	newParticle.Dot:Emit(1)
	newParticle.Beam.Transparency = NumberSequence.new(0,0)
	newParticle.Beam.Width0 = 0.75
	newParticle.Beam.Width1 = 0.75

	local newSound2 = assets.Sounds.Firing.WarpFire:Clone()
	newSound2.Parent = newParticle
	newSound2:Play()
	Debris:AddItem(newParticle, 10)
	Debris:AddItem(newTargetPart, 10)

	local newTween = TweenService:Create(newParticle.Attachment, TweenInfo.new((startPos - cf.Position).Magnitude/self.warpSpeed), {WorldPosition = cf.Position})
	newTween:Play()

	task.spawn(function()
		for i = 1, 100 do
			newParticle.Beam.Transparency = NumberSequence.new(i/100,1)
			task.wait(0.01)
		end
	end)
end


function striderModule:FireWarpCannon()
	local hit, cf, norm, mat = GetMouseHit(self.strider)
	striderModule.Shared.Services.Remotes:Fire("StriderRemote", "WarpEffects", self.strider, cf)
	self:WarpCannonEffects(cf)
	local queryResult = workspace:GetPartBoundsInRadius(cf.Position, 20, self.overlapParams)
	local canTeamKill = self.player:FindFirstChild("CanTeamKill") and self.player:FindFirstChild("CanTeamKill").Value
	for i,v in pairs(queryResult) do
		if v.Parent:FindFirstChild("Humanoid") then
			--v.Parent.Humanoid:TakeDamage(100)
			if self.player.Team == game.Players:GetPlayerFromCharacter(v.Parent).Team and not canTeamKill then
				continue
			end
			striderModule.Shared.Services.Remotes:Fire("StriderRemote", "WarpDamage", 200, v.Parent.Humanoid)
		end
	end
end

function striderModule:removeStrider()
	self.RemoteConnection:Disconnect()
	self.Heartbeat:Disconnect()
	if self.player == game.Players.LocalPlayer then
		workspace.CurrentCamera.CameraSubject = self.player.Character.Humanoid
		self.Character:WaitForChild("Humanoid").WalkSpeed = 16
	end
	if self.deathConnection then
		self.deathConnection:Disconnect()
	end
end



return striderModule

