local replicatedStorage = game:GetService("ReplicatedStorage")
local timerEvent = replicatedStorage:WaitForChild("TimerEvent")

local Players = game:GetService("Players")
local checkpoints = workspace:WaitForChild("Checkpoints")
local Spawn = workspace:WaitForChild("SpawnLocation")

local startTrigger = workspace:WaitForChild("Startline"):WaitForChild("start")
local finishTrigger = workspace:WaitForChild("Finishline"):WaitForChild("finish")
local lastStage = 3

local DEBUG = true

local function log(...)
	if DEBUG then
		print("[Checkpoints]", ...)
	end
end

local Run = {}
Run.__index = Run

function Run.new(player)
	local self = setmetatable({}, Run)
	self.player = player
	self:reset()
	self.lastReset = 0
	return self
end

function Run:start()
	if self.startedAt == nil then
		self.startedAt = workspace:GetServerTimeNow()
		log(self.player.Name, "started")
		timerEvent:FireClient(self.player, "start", self.startedAt)
	end
end

function Run:finish()
	if self.startedAt == nil then
		return
	end
	if self.stage == lastStage then
		local finishTime = workspace:GetServerTimeNow() - self.startedAt
		log(self.player.Name, "finished in", finishTime, "seconds")
		timerEvent:FireClient(self.player, "finish", finishTime)
		self:reset()
	end
end


function Run:reset()
	self.stage = 0
	self.startedAt = nil
	self.player.RespawnLocation = Spawn
end

function Run:advance(stage, part)
	if self.stage ~= stage - 1 then
		return
	end
	self.stage = stage
	self.player.RespawnLocation = part
	log(self.player.Name, "reached stage", stage)
end

local runs = {}

local function runFromHit(hit)
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	return player and runs[player]
end

Players.PlayerAdded:Connect(function(player)
	runs[player] = Run.new(player)
end)

Players.PlayerRemoving:Connect(function(player)
	runs[player] = nil
end)

for _, part in checkpoints:GetChildren() do
	local stage = tonumber(part.Name)

	part.Touched:Connect(function(hit)
		local run = runFromHit(hit)
		if not run then
			return
		end
		run:advance(stage, part)
	end)
end

startTrigger.Touched:Connect(function(hit)
	local run = runFromHit(hit)
	if not run then
		return
	end
	run:start()
end)

finishTrigger.Touched:Connect(function(hit)
	local run = runFromHit(hit)
	if not run then
		return
	end
	run:finish()
end)

timerEvent.OnServerEvent:Connect(function(player, action)
	local run = runs[player]
	if not run then
		return
	end
	
	if action == "reset" then
		local now = workspace:GetServerTimeNow()
		if now - run.lastReset < 1 then
			return
		end
		run.lastReset = now
		run:reset()
		timerEvent:FireClient(player, "reset")
		local character = player.Character
		if not character then
			return
		end
		character:PivotTo(Spawn.CFrame + Vector3.new(0, 3, 0))
	end
end)