local m = {}
local Players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

local ragdollTime = 30
local footDamage = 25

local RunService = game:GetService("RunService")
local Assets = game.ReplicatedStorage.StriderAssets

local function applyEffects(part)
	local deathTween = tweenService:Create(part, TweenInfo.new(0.3), {Transparency = 1})
	part.Color = Color3.new(0,0,0)
	local newEffects1 = Assets.Particles.Glow:Clone()
	local newEffects2 = Assets.Particles.BetterGlow:Clone()
	newEffects1.Parent = part
	newEffects2.Parent = part
	task.wait(2)
	if part:FindFirstChild("face") then
		part.face:Destroy()
	end
	newEffects1:Destroy()
	newEffects2:Destroy()
	deathTween:Play()
end

local function disintegrate(character)
	character.HumanoidRootPart.Anchored = true
	if character:FindFirstChild("Pants") then
		character.Pants:Destroy()
	end
	if character:FindFirstChild("Shirt") then
		character.Shirt:Destroy()
	end
	for _, part in pairs(character:GetDescendants()) do

		if part:IsA("BasePart") then
			if part.Name ~= "Head" then
				part.Anchored = true
			end
			task.spawn(applyEffects, part)
		elseif part:IsA("Accessory") then
			task.spawn(function()
				task.wait(2)
				part:Destroy()
			end)
		end
	end
end

function m:Start()
	local PhysicsService = game:GetService("PhysicsService")
	local newGroup = "NoWalls"
	-- Set strider to be non-collidable with invisible walls
	PhysicsService:RegisterCollisionGroup(newGroup)
	PhysicsService:CollisionGroupSetCollidable(newGroup, newGroup, false)
	for _, part in pairs(workspace.Ignore.Map:GetChildren()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = newGroup
		end
	end

	m.Shared.Services.Remotes:Connect("StriderRemote", function(player, interaction, ...)
		local args = {...}
		if interaction == "FootDamage" then
			player.Character.Humanoid:TakeDamage(footDamage)
		end

		if not player:FindFirstChild("StriderObject") then return end

		if interaction == "Update" then
			m.Shared.Services.Remotes:FireAll("StriderRemote", "Update", player, ...)
		elseif interaction == "Start" then
			local strider = args[1]
			strider.Strider_Reference.Anchored = false
			local healthConn
			healthConn = strider.Humanoid.HealthChanged:Connect(function(health)
				if health <= 0 then

					local newSoundPart = Instance.new("Part")
					newSoundPart.Position = strider.ActualHitbox.Position
					newSoundPart.Anchored = true
					newSoundPart.CanCollide = false
					newSoundPart.Transparency = 1
					newSoundPart.Parent	= workspace.Ignore
					local newSound = Assets.Sounds.Other.Death:Clone()
					newSound.Parent = newSoundPart
					newSound:Play()
					game:GetService("Debris"):AddItem(newSoundPart)
					--strider:Destroy()
					local newValue = Instance.new("BoolValue")
					newValue.Name = "Dead"
					newValue.Parent = strider
					strider.ActualHitbox.RigidConstraint:Destroy()
					strider.ActualHitbox.Anchored = false
					strider.Strider_Reference.LinearVelocity:Destroy()
					healthConn:Disconnect()
					task.wait(ragdollTime)
					if player:FindFirstChild("StriderObject") then
						player.StriderObject:Destroy()
					end
					if strider then
						strider:Destroy()
					end
					player:LoadCharacter()
				end
			end)
			strider.PrimaryPart:SetNetworkOwner(player)
		elseif interaction == "Fire" then
			m.Shared.Services.Remotes:FireAll("StriderRemote", "Fire", player, ...)
		elseif interaction == "WarpEffects" then
			m.Shared.Services.Remotes:FireAll("StriderRemote", "WarpEffects", player, ...)
		elseif interaction == "WarpDamage" then
			local damage = args[1]
			local humanoid = args[2]
			humanoid:TakeDamage(damage)
			if humanoid.Health <= 0 then
				disintegrate(humanoid.Parent)
			end
		elseif interaction == "Voice" then
			local strider = args[1]
			local index = args[2]
			local voices = Assets.Sounds.Voice
			local newSound = voices:GetChildren()[index]:Clone()
			newSound.Parent = strider.Strider_Reference
			newSound:Play()
			game:GetService("Debris"):AddItem(newSound, 5)
		elseif interaction == "Alert" then
			local strider = args[1]
			local voices = Assets.Sounds.Alert
			local newSound = voices:GetChildren()[math.random(1, #voices:GetChildren())]:Clone()
			newSound.Parent = strider.Strider_Reference
			newSound:Play()
			game:GetService("Debris"):AddItem(newSound, 5)
		end
	end)
end
return m
