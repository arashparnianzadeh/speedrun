local Players = game:GetService("Players")
local checkpoints = workspace:WaitForChild("Checkpoints")
local Spawn = workspace:WaitForChild("SpawnLocation")

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
	return self
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
