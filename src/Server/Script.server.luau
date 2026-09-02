local Players = game:GetService("Players")
local checkpoints = workspace:WaitForChild("Checkpoints")
local Spawn = workspace:WaitForChild("SpawnLocation")

local stageOf = {} -- shows what stage the player is, 0 means not started
local lastCheckpoint = {} -- shows the last checkpoint the player reached

local DEBUG = true

local function log(...)
	if DEBUG then
		print("[Checkpoints]", ...)
	end
end

Players.PlayerAdded:Connect(function(player)
	stageOf[player] = 0 -- when a player joins they start at 0
	player.RespawnLocation = Spawn
end)

Players.PlayerRemoving:Connect(function(player)
	stageOf[player] = nil
end)

local function onCharacterAdded(player, character) -- respawns the player to the correct checkpoint
	local stage = stageOf[player]
	if stage == 0 then
		return
	end
	local part = checkpoints:FindFirstChild(tostring(stage))
	character:WaitForChild("HumanoidRootPart")
	player.RespawnLocation = part
end


for _, part in checkpoints:GetChildren() do
	local stage = tonumber(part.Name)

	part.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then
			return
		end
		if stageOf[player] ~= stage - 1 then -- checks if the player has not skipped a stage
			return
		end
		stageOf[player] = stage
		log(player.Name, "reached stage", stage)
		lastCheckpoint[player] = part -- saves the last checkpoint the player reached
		onCharacterAdded(player, hit.Parent) -- respawns the player
	end)
end
