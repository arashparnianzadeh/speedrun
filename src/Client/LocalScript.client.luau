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

local function removeGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
end

local function makeGhost()
	local character = player.Character
	if not character then
		return nil
	end
	character.Archivable = true
	local clone = character:Clone()
	for _, thing in clone:GetDescendants() do
		if thing:IsA("BasePart") then
			thing.Anchored = true
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
	clone.Name = "Ghost"
	clone.Parent = workspace
	return clone
end

timerEvent.OnClientEvent:Connect(function(action, value, isBest)
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

runService.RenderStepped:Connect(function()
	if running then
		local elapsed = workspace:GetServerTimeNow() - startedAt

		if ghost and ghostframes then
			local frameNumber = elapsed / ghostinterval
			local i = math.floor(frameNumber) + 1
			local alpha = frameNumber - math.floor(frameNumber)
			local a = ghostframes[i]
			local b = ghostframes[i + 1] or a
			if a then
				ghost:PivotTo(frameToCFrame(a):Lerp(frameToCFrame(b), alpha))
			else
				removeGhost()
			end
		end
		timerLabel.Text = formatTime(elapsed)
	end
end)

resetButton.Activated:Connect(function()
	timerEvent:FireServer("reset")
end)