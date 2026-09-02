local dataStore = game:GetService("DataStoreService"):GetDataStore("PlayerTimes")
local runService = game:GetService("RunService")

local replicatedStorage = game:GetService("ReplicatedStorage")
local timerEvent = replicatedStorage:WaitForChild("TimerEvent")

local Players = game:GetService("Players")
local checkpoints = workspace:WaitForChild("Checkpoints")
local Spawn = workspace:WaitForChild("SpawnLocation")

local startTrigger = workspace:WaitForChild("Startline"):WaitForChild("start")
local finishTrigger = workspace:WaitForChild("Finishline"):WaitForChild("finish")
local lastStage = 3
local SAMPLE_INTERVAL = 0.05

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
	self.best = nil
	return self
end

function Run:start()
	if self.startedAt == nil then
		self.startedAt = workspace:GetServerTimeNow()
		log(self.player.Name, "started")
		timerEvent:FireClient(self.player, "start", self.startedAt)
	end
end

function Run:sample(now)
	if self.player.Character == nil then
		return
	end
	local hrp = self.player.Character:FindFirstChild("HumanoidRootPart")
	if hrp == nil then
		return
	end
	local cf = hrp.CFrame
	local _, yaw = cf:ToOrientation()
	table.insert(self.frames, { cf.X, cf.Y, cf.Z, yaw })
	self.nextSample = now + SAMPLE_INTERVAL
end

function Run:finish()
	if self.startedAt == nil then
		return
	end
	if self.stage == lastStage then
		local finishTime = workspace:GetServerTimeNow() - self.startedAt
		local isBest = self.best == nil or finishTime < self.best
		log(self.player.Name, "finished in", finishTime, "seconds")
		if isBest then
			self.best = finishTime
			self.player:SetAttribute("BestTime", self.best)
			self.bestFrames = self.frames
			timerEvent:FireClient(self.player, "ghost", { frames = self.frames, interval = SAMPLE_INTERVAL })
		end
		timerEvent:FireClient(self.player, "finish", finishTime, isBest)
		log(self.player.Name, "frames", #self.frames)
		self:reset()
	end
end


function Run:reset()
	self.stage = 0
	self.startedAt = nil
	self.player.RespawnLocation = Spawn
	self.frames = {}
	self.nextSample = 0
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
local function keyFor(player)
	return "Player_" .. player.UserId
end

local function runFromHit(hit)
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	return player and runs[player]
end

runService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for _, run in runs do
		if run.startedAt and now >= run.nextSample then
			run:sample(now)
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	runs[player] = Run.new(player)
	local run = runs[player]
	local key = keyFor(player)
	
	local success, result = pcall(function()
		return dataStore:GetAsync(key)
	end)
	
	if success then
		if result then
			run.best = result.best
		end
	else
		warn("load failed for", player.Name, result)
		run.loadFailed = true
	end
	
	log(player.Name, "loaded best", run.best)
	player:SetAttribute("BestTime", run.best)
end)

local function saveBestTimes(player)
	local run = runs[player]
	if not run or run.loadFailed then 
		return 
	end
	local key = keyFor(player)
	local success, result = pcall(function()
		dataStore:SetAsync(key, { best = run.best })
	end)
	if not success then 
		warn("save failed for", player.Name, result) 
	end
end

Players.PlayerRemoving:Connect(function(player)
	saveBestTimes(player)
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

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveBestTimes(player)
	end
end)