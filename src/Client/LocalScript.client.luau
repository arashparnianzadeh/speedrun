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

timerEvent.OnClientEvent:Connect(function(action, value, isBest)
	if action == "start" then
		running = true
		startedAt = value
		print(action, value)
	elseif action == "finish" then
		running = false
		timerLabel.Text = formatTime(value)
		print(action, value)
	elseif action == "reset" then
		running = false
		startedAt = nil
		timerLabel.Text = "00:00.00"
		print(action)
	end
end)

runService.RenderStepped:Connect(function()
	if running then
		local elapsed = workspace:GetServerTimeNow() - startedAt
		timerLabel.Text = formatTime(elapsed)
	end
end)

resetButton.Activated:Connect(function()
	timerEvent:FireServer("reset")
end)