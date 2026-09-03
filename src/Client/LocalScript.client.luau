local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local timerEvent = replicatedStorage:WaitForChild("TimerEvent")
local player = game:GetService("Players").LocalPlayer

local timerGui = player.PlayerGui:WaitForChild("TimerGui")
local timerLabel = timerGui:WaitForChild("Timer")
local resetButton = timerGui:WaitForChild("ResetButton")
local BestTime = timerGui:WaitForChild("BestTime")

local function formatTime(timeVal)
	local mins = math.floor(math.fmod(timeVal,3600)/60)
	local secs = math.fmod(timeVal,60)
	return string.format("%02d:%05.2f", mins, secs)
end

local function updateBest()
	local best = player:GetAttribute("BestTime")
	if best then
		BestTime.Text = formatTime(best)
	end
end

updateBest()
player:GetAttributeChangedSignal("BestTime"):Connect(updateBest)

local running
local startedAt
local ghostframes
local ghostinterval
local ghost
local ghostTracks
local ghostCurrent

local function removeGhost() -- removes the ghost character
	if ghost then
		ghost:Destroy()
		ghost = nil
		ghostTracks = nil
		ghostCurrent = nil
	end
end

local function makeGhost() -- makes the ghost character
	local character = player.Character
	if not character then
		return nil
	end
	character.Archivable = true
	local clone = character:Clone()
	for _, thing in clone:GetDescendants() do -- make the ghost look like a ghost
		if thing:IsA("BasePart") then
			thing.Anchored = thing.Name == "HumanoidRootPart"
			thing.CanCollide = false
			thing.Transparency = 0.6
			thing.Color = Color3.fromRGB(80, 140, 255)
		elseif thing:IsA("Decal") or thing:IsA("Shirt") or thing:IsA("Pants") or thing:IsA("LuaSourceContainer") then
			thing:Destroy()
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	local controller = Instance.new("AnimationController")
	controller.Parent = clone
	local animator = Instance.new("Animator")
	animator.Parent = controller
	clone.Name = "Ghost"
	clone.Parent = workspace
	local animate = character:FindFirstChild("Animate")
	ghostTracks = {}
	for _, name in { "idle", "run", "jump", "fall" } do -- load the animations for the ghost
		local animation = animate[name]:FindFirstChildOfClass("Animation")
		ghostTracks[name] = animator:LoadAnimation(animation)
	end
	return clone
end

timerEvent.OnClientEvent:Connect(function(action, value, isBest) -- handles the timer events client side
	if action == "start" then
		running = true
		startedAt = value
		if ghostframes then ghost = makeGhost() end
		print(action, value)
	elseif action == "finish" then
		running = false
		timerLabel.Text = formatTime(value)
		removeGhost()
		print(action, value)
	elseif action == "reset" then
		running = false
		startedAt = nil
		timerLabel.Text = "00:00.00"
		removeGhost()
		print(action)
	elseif action == "ghost" then
		ghostframes = value.frames
		ghostinterval = value.interval
	end
end)

local function frameToCFrame(f)
	return CFrame.new(f[1], f[2], f[3]) * CFrame.Angles(0, f[4], 0)
end

local function setGhostAnimation(name) -- plays the given animation on the ghost character
	if name == ghostCurrent then
		return
	end
	if ghostCurrent then
		ghostTracks[ghostCurrent]:Stop()
	end
	ghostTracks[name]:Play()
	ghostCurrent = name
end

runService.RenderStepped:Connect(function() -- updates the ghost character
	if running then
		local elapsed = workspace:GetServerTimeNow() - startedAt

		if ghost and ghostframes then
			local frameNumber = elapsed / ghostinterval
			local i = math.floor(frameNumber) + 1
			local alpha = frameNumber - math.floor(frameNumber)
			local a = ghostframes[i]
			local b = ghostframes[i + 1] or a
			if a then -- applies animations depending on the current frame
				ghost:PivotTo(frameToCFrame(a):Lerp(frameToCFrame(b), alpha))
				local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
				local horizontal = math.sqrt(dx * dx + dz * dz) / ghostinterval
				local vertical = dy / ghostinterval
				if vertical > 3 then
					setGhostAnimation("jump")
				elseif vertical < -3 then
					setGhostAnimation("fall")
				elseif horizontal > 1 then
					setGhostAnimation("run")
				else
					setGhostAnimation("idle")
				end
			else
				removeGhost()
			end
		end
		timerLabel.Text = formatTime(elapsed)
	end
end)

resetButton.Activated:Connect(function() -- fires the reset event when the reset button is clicked
	timerEvent:FireServer("reset")
end)
timerEvent:FireServer("ready")