-- Discord: Rashimaal | Roblox: Rashimaal

local dataStore = game:GetService("DataStoreService"):GetDataStore("PlayerTimes") -- fetched once so the store name lives in one place
local runService = game:GetService("RunService") -- for Heartbeat

local replicatedStorage = game:GetService("ReplicatedStorage") -- the folder both the server and the client can see
local timerEvent = replicatedStorage:WaitForChild("TimerEvent") -- the one RemoteEvent all timer messages travel down

local players = game:GetService("Players") -- for PlayerAdded, PlayerRemoving and GetPlayerFromCharacter
local checkpoints = workspace:WaitForChild("Checkpoints") -- folder holding the parts named 1, 2, 3 and so on
local spawnLocation = workspace:WaitForChild("SpawnLocation") -- where a reset run sends you back to

local startTrigger = workspace:WaitForChild("Startline"):WaitForChild("start") -- only this thin invisible part should fire Touched not the poles
local finishTrigger = workspace:WaitForChild("Finishline"):WaitForChild("finish") -- same idea for the finish line
local lastStage = 0 -- highest checkpoint number filled in by the loop below
local SAMPLE_INTERVAL = 0.05 -- 20 a second. bigger cuts corners, smaller means a bigger save

for _, part in checkpoints:GetChildren() do -- add a part named 4 and the finish check updates itself
	local stage = tonumber(part.Name) -- part names are strings, so convert. non numeric parts give nil
	if stage and stage > lastStage then -- skip the nils, keep the biggest number
		lastStage = stage -- remember the new highest checkpoint
	end
end

local function round2(n) -- stops floats saving as 12.300000000000001 and shrinks the payload
	return math.round(n * 100) / 100 -- 0.01 studs, invisible on a ghost moving at 20fps
end

local function formatTime(timeVal) -- the server writes the leaderstats string itself, so it needs its own copy
	local mins = math.floor(math.fmod(timeVal,3600)/60) -- whole minutes, wrapping at an hour
	local secs = math.fmod(timeVal,60) -- leftover seconds, keeping the decimals
	return string.format("%02d:%05.2f", mins, secs) -- pads to 00:07.42 so the label never jumps width
end

local Run = {} -- one object per player instead of six parallel tables to keep in sync
Run.__index = Run -- run:advance() misses on the instance, falls back here and calls it with self bound

function Run.new(player)
	local self = setmetatable({}, Run) -- fresh table that inherits every Run method
	self.player = player -- so the methods can reach the player without being passed it
	self:reset() -- one definition of start of an attempt, instead of writing those fields twice
	self.lastReset = 0 -- outside reset because it has to survive a reset
	self.best = nil -- outside reset too, because finish calls reset and would wipe the PB a line after setting it
	return self -- caller stores this in runs[player]
end

function Run:start()
	if self.startedAt == nil then -- without this, walking back through the line mid run restarts your clock
		self.startedAt = workspace:GetServerTimeNow() -- synced clock, so the client can count from the same start. os.clock is local to one machine
		timerEvent:FireClient(self.player, "start", self.startedAt) -- one message per run, then the client counts locally
	end
end

function Run:sample(now)
	if self.player.Character == nil then -- nil while respawning and before the first spawn
		return
	end
	local hrp = self.player.Character:FindFirstChild("HumanoidRootPart") -- missing for a frame or two while the character loads
	if hrp == nil then -- same deal, bail rather than error
		return -- nextSample is not advanced either, so it retries next Heartbeat
	end
	local cf = hrp.CFrame -- position and rotation of the player's root
	local _, yaw = cf:ToOrientation() -- characters only turn about Y, so pitch and roll are noise
	table.insert(self.frames, { round2(cf.X), round2(cf.Y), round2(cf.Z), round2(yaw) }) -- four numbers instead of a CFrame's twelve
	self.nextSample = now + SAMPLE_INTERVAL -- the Heartbeat condition reads this, so writing it schedules the next sample
end

function Run:sendGhost()
	if self.bestFrames then -- the check inside means all three callers can call it blind, new players just get nothing
		-- interval is sent with the frames so old saves still play at the right speed
		timerEvent:FireClient(self.player, "ghost", { frames = self.bestFrames, interval = SAMPLE_INTERVAL })
	end
end

function Run:finish()
	if self.startedAt == nil then -- rejects touching the finish without ever starting
		return -- spawning near it, falling onto it, crossing it after a reset
	end
	if self.stage == lastStage then -- advance only accepts stage minus 1, so reaching lastStage proves every checkpoint in order
		local finishTime = workspace:GetServerTimeNow() - self.startedAt -- seconds since the start line
		local isBest = self.best == nil or finishTime < self.best -- nil check first, or short circuits before the comparison
		if isBest then -- swapped, the first finish would error comparing a number with nil
			self.best = finishTime -- set before showBest, which reads it
			self:showBest() -- pushes the new PB to the GUI and the Tab list
			self.bestFrames = self.frames -- reset makes a new frames table, so this keeps the old one
			self:sendGhost() -- set before sendGhost, which reads it
		end
		timerEvent:FireClient(self.player, "finish", finishTime, isBest) -- server time, so ping cannot change the result
		self:reset() -- attempt is over, rearm start and clear the attempt state
	end
end


function Run:reset()
	self.stage = 0 -- back to before the first checkpoint
	self.startedAt = nil -- this is what rearms Run:start
	-- Neutral must stay ticked on the pads, or the engine ignores them for players on another team
	self.player.RespawnLocation = spawnLocation -- Roblox handles every respawn from here
	self.frames = {} -- new table, so bestFrames keeps pointing at the old one
	self.nextSample = 0 -- 0 is always in the past, so the first sample fires immediately on the next start
end

function Run:showBest()
	self.player:SetAttribute("BestTime", self.best) -- attributes are state, so the client can read it whenever it loads
	if self.best then -- raw number for the GUI to format however it likes
		self.bestValue.Value = formatTime(self.best) -- Tab displays the value verbatim, so it has to be preformatted
	else
		self.bestValue.Value = "" -- blank rather than the word nil for a player with no PB
	end
end

function Run:advance(stage, part)
	if self.stage ~= stage - 1 then -- stops out of order touches, like hitting 3 while on 1
		return -- also the debounce. Touched fires once per limb and every repeat now fails this same check
	end
	self.stage = stage -- checkpoint accepted
	self.player.RespawnLocation = part -- RespawnLocation only accepts a SpawnLocation, a plain Part gets rejected
end

local runs = {} -- keyed by the Player object. no string building, no collisions, exact key on leave
local function keyFor(player) -- key format exists once, so save and load can never disagree
	return "Player_" .. player.UserId -- UserId never changes, unlike the display name. the prefix namespaces the store
end

local function runFromHit(hit) -- all three touch handlers ask the same question
	local player = players:GetPlayerFromCharacter(hit.Parent) -- nil when a rock or a stray part touches the pad
	return player and runs[player]
end

runService.Heartbeat:Connect(function() -- one connection total, so cost scales with players not connections
	local now = workspace:GetServerTimeNow() -- read once so everyone samples against the same timestamp this tick
	for _, run in runs do -- every player who is currently mid run
		if run.startedAt and now >= run.nextSample then -- every frame would store three times the data
			run:sample(now) -- so ghosts recorded on different servers still play back at the same speed
		end
	end
end)

players.PlayerAdded:Connect(function(player)
	runs[player] = Run.new(player) -- their run exists before anything can touch a trigger
	local run = runs[player] -- local handle so the rest of the handler is shorter
	local leaderstats = Instance.new("Folder") -- roblox hardcodes this name for the tab player list
	leaderstats.Name = "leaderstats" -- anything else and the list shows nothing
	leaderstats.Parent = player -- has to hang off the Player instance
	local bestValue = Instance.new("StringValue") -- string, because a NumberValue would show 12.34 instead of 00:12.34
	bestValue.Name = "Best" -- this becomes the column header
	bestValue.Parent = leaderstats -- inside the folder is what makes it show up
	run.bestValue = bestValue -- cached so showBest skips walking player.leaderstats.Best every update
	local key = keyFor(player) -- built once, used by the load below

	local success, result = pcall(function() -- DataStore calls are network calls and throw on outage or throttling
		return dataStore:GetAsync(key) -- unprotected, an error here aborts the rest of the handler
	end)

	if success then -- three cases live here
		if result then -- returning player with a save
			run.best = result.best -- their PB
			run.bestFrames = result.frames -- and the ghost that set it
		end -- success with nil result is the second case. new player, nothing to load
	else
		warn("load failed for", player.Name, result) -- the only case where we do not know what they have
		run.loadFailed = true -- flag it so the save on leave knows not to trust nil
	end

	run:showBest() -- these publish best and bestFrames, so the load has to have finished first
	run:sendGhost() -- called before, they'd broadcast nil and the player would sit blank
end)

local function saveBestTimes(player)
	local run = runs[player] -- nil if they never fully joined
	if not run or run.loadFailed then -- best is nil only because we could not read it, not because they have no PB
		return -- writing would overwrite a real record with nil and destroy it permanently
	end
	local key = keyFor(player) -- same function as the load, so the keys match
	local success, result = pcall(function() -- SetAsync throws too and this runs during shutdown
		-- a table keeps the frames with their time and new fields can be added without breaking old saves
		dataStore:SetAsync(key, { best = run.best, frames = run.bestFrames })
	end)
	if not success then -- nothing to retry against here
		warn("save failed for", player.Name, result) -- at least it lands in the server log
	end
end

players.PlayerRemoving:Connect(function(player) -- save before clearing, because saveBestTimes reads runs[player]
	saveBestTimes(player) -- clear it first and the not run guard fires and nothing is written
	runs[player] = nil -- drops the strong reference so the run and its frames can be collected
end)

for _, part in checkpoints:GetChildren() do -- wires up every checkpoint in the folder
	local stage = tonumber(part.Name) -- once per part at setup, not on every touch

	part.Touched:Connect(function(hit) -- the closure captures stage and part
		local run = runFromHit(hit) -- rocks, debris and half joined players all land here
		if not run then -- nothing to advance
			return -- ignore the touch
		end
		run:advance(stage, part) -- the rules live in advance, the handler is just plumbing
	end)
end

startTrigger.Touched:Connect(function(hit) -- all three handlers being identical is the point
	local run = runFromHit(hit) -- one place decides what counts as a real player
	if not run then -- same guard as the others
		return -- ignore
	end
	run:start() -- the already started rule lives in start, not here
end)

finishTrigger.Touched:Connect(function(hit) -- same shape again
	local run = runFromHit(hit) -- shared lookup
	if not run then -- same guard
		return -- ignore
	end
	run:finish() -- the started and all checkpoints rules live in finish, so they cannot drift from three copies
end)

timerEvent.OnServerEvent:Connect(function(player, action) -- clients can fire anything, any time
	local run = runs[player] -- nil before PlayerAdded finishes and after they leave
	if not run then -- rejecting nil stops the server erroring on run.lastReset below
		return -- also drops junk from a spamming client
	end

	if action == "reset" then -- the client is untrusted, so it only asks and the server decides
		local now = workspace:GetServerTimeNow() -- otherwise it could teleport anywhere or fake a finish
		if now - run.lastReset < 1 then -- stops button mashing and remote spam from firing a teleport every frame
			return -- one second is under human double click speed but long enough to kill a loop
		end
		run.lastReset = now -- start the cooldown
		run:reset() -- clears the attempt and puts the respawn back at spawn
		timerEvent:FireClient(player, "reset") -- the client waits for this, so a rejected reset never shows on screen
		local character = player.Character -- nil if they died and are mid respawn, or left between the fire and this line
		if not character then -- the reset above still counted, only the teleport is skipped
			return -- they'll spawn at spawnLocation anyway
		end
		character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 3, 0)) -- moves the whole model, +3 on Y so they land on the pad and not in it
	elseif action == "ready" then -- fired once the LocalScript has actually connected OnClientEvent
		run:sendGhost() -- PlayerAdded fires well before that, so a ghost sent only from there goes into the void
	end
end)

game:BindToClose(function() -- PlayerRemoving is not guaranteed to finish during a shutdown and SetAsync yields
	for _, player in players:GetPlayers() do -- everyone still connected
		saveBestTimes(player) -- BindToClose holds the shutdown open, up to 30 seconds, so these writes can land
	end
end)
