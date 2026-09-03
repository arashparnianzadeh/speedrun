-- Discord: Rashimaal | Roblox: Rashimaal

local dataStore = game:GetService("DataStoreService"):GetDataStore("PlayerTimes")
local runService = game:GetService("RunService")

local replicatedStorage = game:GetService("ReplicatedStorage")
local timerEvent = replicatedStorage:WaitForChild("TimerEvent")

local Players = game:GetService("Players")
local checkpoints = workspace:WaitForChild("Checkpoints")
local Spawn = workspace:WaitForChild("SpawnLocation")

local startTrigger = workspace:WaitForChild("Startline"):WaitForChild("start")
local finishTrigger = workspace:WaitForChild("Finishline"):WaitForChild("finish")
local lastStage = 0
local SAMPLE_INTERVAL = 0.05

for _, part in checkpoints:GetChildren() do
	local stage = tonumber(part.Name)
	if stage and stage > lastStage then
		lastStage = stage
	end
end

local function round2(n)
	return math.round(n * 100) / 100
end

local Run = {}
Run.__index = Run

function Run.new(player) -- creates a table with the new player's data
	local self = setmetatable({}, Run)
	self.player = player
	self:reset()
	self.lastReset = 0
	self.best = nil
	return self
end

function Run:start() -- starts the run
	if self.startedAt == nil then
		self.startedAt = workspace:GetServerTimeNow()
		timerEvent:FireClient(self.player, "start", self.startedAt)
	end
end

function Run:sample(now) -- saves the player's position for the ghost
	if self.player.Character == nil then
		return
	end
	local hrp = self.player.Character:FindFirstChild("HumanoidRootPart")
	if hrp == nil then
		return
	end
	local cf = hrp.CFrame
	local _, yaw = cf:ToOrientation()
	table.insert(self.frames, { round2(cf.X), round2(cf.Y), round2(cf.Z), round2(yaw) })
	self.nextSample = now + SAMPLE_INTERVAL
end

function Run:sendGhost()
	if self.bestFrames then
		timerEvent:FireClient(self.player, "ghost", { frames = self.bestFrames, interval = SAMPLE_INTERVAL })
	end
end

function Run:finish() -- ends the run
	if self.startedAt == nil then
		return
	end
	if self.stage == lastStage then
		local finishTime = workspace:GetServerTimeNow() - self.startedAt
		local isBest = self.best == nil or finishTime < self.best
		if isBest then
			self.best = finishTime
			self.player:SetAttribute("BestTime", self.best)
			self.bestFrames = self.frames
			self:sendGhost()
		end
		timerEvent:FireClient(self.player, "finish", finishTime, isBest) -- fire client to send the finish time to the player
		self:reset()
	end
end


function Run:reset() -- resets the run
	self.stage = 0
	self.startedAt = nil
	self.player.RespawnLocation = Spawn
	self.frames = {}
	self.nextSample = 0
end

function Run:advance(stage, part) -- advances the run to the next stage
	if self.stage ~= stage - 1 then -- checks the stage
		return
	end
	self.stage = stage
	self.player.RespawnLocation = part
end

local runs = {}
local function keyFor(player) -- key for datastore
	return "Player_" .. player.UserId
end

local function runFromHit(hit) -- gets the run from the part hit
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	return player and runs[player]
end

runService.Heartbeat:Connect(function() -- updates the players' positions
	local now = workspace:GetServerTimeNow()
	for _, run in runs do
		if run.startedAt and now >= run.nextSample then
			run:sample(now)
		end
	end
end)

Players.PlayerAdded:Connect(function(player) -- gets the players data when they join
	runs[player] = Run.new(player)
	local run = runs[player]
	local key = keyFor(player)
	
	local success, result = pcall(function()
		return dataStore:GetAsync(key)
	end)
	
	if success then
		if result then
			run.best = result.best
			run.bestFrames = result.frames
		end
	else
		warn("load failed for", player.Name, result)
		run.loadFailed = true
	end
	
	player:SetAttribute("BestTime", run.best)
	run:sendGhost()
end)

local function saveBestTimes(player) -- saves the players data when they leave
	local run = runs[player]
	if not run or run.loadFailed then 
		return 
	end
	local key = keyFor(player)
	local success, result = pcall(function()
		dataStore:SetAsync(key, { best = run.best, frames = run.bestFrames })
	end)
	if not success then 
		warn("save failed for", player.Name, result) 
	end
end

Players.PlayerRemoving:Connect(function(player)
	saveBestTimes(player)
	runs[player] = nil
end)

for _, part in checkpoints:GetChildren() do -- sets up the checkpoints to make sure each one gets touched
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

timerEvent.OnServerEvent:Connect(function(player, action) -- handles the timer events server side
	local run = runs[player]
	if not run then
		return
	end
	
	if action == "reset" then -- sends the player back to spawn if they click the reset button
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
	elseif action == "ready" then
		run:sendGhost()
	end
end)

game:BindToClose(function() -- saves the players data when the server closes
	for _, player in Players:GetPlayers() do
		saveBestTimes(player)
	end
end)