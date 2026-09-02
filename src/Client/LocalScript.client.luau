local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local timerEvent = replicatedStorage:WaitForChild("TimerEvent")

local timerGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("TimerGui")
local timerLabel = timerGui:WaitForChild("Timer")

local function formatTime(timeVal)
	local mins = math.floor(math.fmod(timeVal,3600)/60)
	local secs = math.fmod(timeVal,60)
	return string.format("%02d:%05.2f", mins, secs)
end

local running
local startedAt

timerEvent.OnClientEvent:Connect(function(action, value)
	if action == "start" then
		running = true
		startedAt = value
		print(action, value)
	elseif action == "finish" then
		running = false
		timerLabel.Text = formatTime(value)
		print(action, value)
	end
end)

runService.RenderStepped:Connect(function()
	if running then
		local elapsed = workspace:GetServerTimeNow() - startedAt
		timerLabel.Text = formatTime(elapsed)
	end
end)
