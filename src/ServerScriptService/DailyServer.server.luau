--[[
	DailyServer — owns the CLOCK for Daily Rewards.

	The client cannot be trusted with "is a new day", so the day boundary and the streak
	live here and persist in a DataStore. What the server does NOT do is hand out the
	reward: money, bait, boosts and pearls are all client-side in this place
	(leaderstats.Money / Bait_* / Inv_* / Pearls), so the server only decides WHETHER a
	claim is allowed and WHICH day of the cycle it is. DailyController applies the payload.
	Same trust model as IdleServer — no new exploit surface, but the seam to harden first
	if the economy ever moves server-side.

	Day boundary is UTC midnight: floor(os.time() / 86400). Timezone-neutral and cheap.

	Stored per player: { lastDay = <utc day int>, day = <1..CYCLE last claimed>, total = n }
	  lastDay == today      -> already claimed, nothing available
	  lastDay == today - 1  -> streak intact, next day of the cycle
	  anything older        -> streak broken, back to day 1
]]

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CYCLE = 7

local store
do
	local ok, res = pcall(function() return DataStoreService:GetDataStore("DailyRewards_v1") end)
	store = ok and res or nil
end

local remotes = ReplicatedStorage:FindFirstChild("DailyRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "DailyRemotes"
	remotes.Parent = ReplicatedStorage
end
local function remote(name)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end
local stateEvent = remote("State")     -- server -> client: canClaim, nextDay, streak, total
local claimEvent = remote("Claim")     -- client -> server: request; answered with State
local syncEvent  = remote("Sync")      -- client -> server: "tell me where I stand"

local cache = {}   -- [userId] = { lastDay, day, total }
local function key(plr) return "u_" .. plr.UserId end
local function today() return math.floor(os.time() / 86400) end

local function load(plr)
	if cache[plr.UserId] then return cache[plr.UserId] end
	local rec = { lastDay = nil, day = 0, total = 0 }
	if store then
		local ok, res = pcall(function() return store:GetAsync(key(plr)) end)
		if ok and type(res) == "table" then
			rec.lastDay = tonumber(res.lastDay)
			rec.day     = tonumber(res.day) or 0
			rec.total   = tonumber(res.total) or 0
		end
	end
	cache[plr.UserId] = rec
	return rec
end

local function save(plr)
	if not store then return end
	local rec = cache[plr.UserId]
	if not rec then return end
	pcall(function() store:SetAsync(key(plr), { lastDay = rec.lastDay, day = rec.day, total = rec.total }) end)
end

-- what is available right now, without changing anything
local function evaluate(rec)
	local t = today()
	if rec.lastDay == t then
		return false, (rec.day % CYCLE) + 1        -- claimed; this is tomorrow's day
	elseif rec.lastDay == t - 1 then
		return true, (rec.day % CYCLE) + 1         -- streak intact
	else
		return true, 1                             -- new player, or streak broken
	end
end

local function pushState(plr)
	local rec = load(plr)
	local canClaim, nextDay = evaluate(rec)
	stateEvent:FireClient(plr, canClaim, nextDay, rec.day, rec.total)
end

claimEvent.OnServerEvent:Connect(function(plr)
	local rec = load(plr)
	local canClaim, nextDay = evaluate(rec)
	if not canClaim then
		pushState(plr)                             -- refuse, and correct the client's view
		return
	end
	rec.lastDay = today()
	rec.day     = nextDay
	rec.total  += 1
	save(plr)
	-- granted == the client may apply day `nextDay`'s payload
	stateEvent:FireClient(plr, false, (nextDay % CYCLE) + 1, rec.day, rec.total, nextDay)
end)

syncEvent.OnServerEvent:Connect(function(plr) pushState(plr) end)

Players.PlayerAdded:Connect(function(plr)
	task.delay(3, function() if plr.Parent then pushState(plr) end end)
end)
Players.PlayerRemoving:Connect(function(plr)
	save(plr)
	cache[plr.UserId] = nil
end)
game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do save(plr) end
end)

-- a player online across UTC midnight should see the badge light up without rejoining
task.spawn(function()
	local lastTick = today()
	while task.wait(30) do
		local t = today()
		if t ~= lastTick then
			lastTick = t
			for _, plr in ipairs(Players:GetPlayers()) do pushState(plr) end
		end
	end
end)

print("[DailyServer] online — " .. CYCLE .. "-day cycle " ..
	(store and "(DataStore ready)" or "(no DataStore — progress won't persist)"))
