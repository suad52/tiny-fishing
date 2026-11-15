--[[
	WheelServer — earns and spends Spin Wheel spins.

	Same split as DailyServer: the server owns the CLOCK (playtime accrued, spins banked)
	and picks the winning segment; WheelController owns the PAYLOAD and applies it into the
	client-side stores. See fishing-game-server-persistence for why.

	You bank one spin per SPIN_EVERY seconds of actual time in-game, up to MAX_BANKED so
	leaving the game open all night isn't a strategy. Unspent spins and the part-finished
	timer persist, so a short session isn't wasted.

	The winning index is chosen HERE, not by the client, and weights live only on the
	server. WheelController is told the index and animates to it.
]]

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SPIN_EVERY = 300     -- seconds of playtime per free spin
local MAX_BANKED = 3
local PUSH_EVERY = 15      -- resync cadence; the client counts down locally in between

-- must stay in step with WheelController's SEGMENTS (same order)
local WEIGHTS = { 22, 18, 16, 12, 10, 8, 8, 6 }
local TOTAL = 0
for _, w in ipairs(WEIGHTS) do TOTAL += w end

local store
do
	local ok, res = pcall(function() return DataStoreService:GetDataStore("SpinWheel_v1") end)
	store = ok and res or nil
end

local remotes = ReplicatedStorage:FindFirstChild("WheelRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "WheelRemotes"
	remotes.Parent = ReplicatedStorage
end
local function remote(name)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = remotes end
	return r
end
local stateEvent  = remote("State")   -- server -> client: spins, secondsToNext
local spinEvent   = remote("Spin")    -- client -> server: request a spin
local resultEvent = remote("Result")  -- server -> client: winning segment index

local rec = {}   -- [userId] = { spins, partial }
local function key(plr) return "u_" .. plr.UserId end

local function save(plr)
	if not store then return end
	local r = rec[plr.UserId]; if not r then return end
	pcall(function() store:SetAsync(key(plr), { spins = r.spins, partial = r.partial }) end)
end

local function pushState(plr)
	local r = rec[plr.UserId]; if not r then return end
	stateEvent:FireClient(plr, r.spins, math.max(0, SPIN_EVERY - r.partial), SPIN_EVERY, MAX_BANKED)
end

Players.PlayerAdded:Connect(function(plr)
	local data
	if store then
		local ok, res = pcall(function() return store:GetAsync(key(plr)) end)
		if ok and type(res) == "table" then data = res end
	end
	rec[plr.UserId] = {
		spins   = math.clamp(tonumber(data and data.spins) or 0, 0, MAX_BANKED),
		partial = math.clamp(tonumber(data and data.partial) or 0, 0, SPIN_EVERY),
	}
	task.delay(3, function() if plr.Parent then pushState(plr) end end)
end)

Players.PlayerRemoving:Connect(function(plr)
	save(plr)
	rec[plr.UserId] = nil
end)
game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do save(plr) end
end)

spinEvent.OnServerEvent:Connect(function(plr)
	local r = rec[plr.UserId]
	if not r or r.spins <= 0 then
		pushState(plr)                       -- refuse, and correct the client's view
		return
	end
	r.spins -= 1
	local roll, acc = math.random() * TOTAL, 0
	local index = #WEIGHTS
	for i, w in ipairs(WEIGHTS) do
		acc += w
		if roll <= acc then index = i break end
	end
	resultEvent:FireClient(plr, index)
	pushState(plr)
	save(plr)
end)

-- the playtime clock
task.spawn(function()
	local since = 0
	while task.wait(1) do
		since += 1
		for _, plr in ipairs(Players:GetPlayers()) do
			local r = rec[plr.UserId]
			if r then
				r.partial += 1
				if r.partial >= SPIN_EVERY then
					r.partial -= SPIN_EVERY
					if r.spins < MAX_BANKED then
						r.spins += 1
						pushState(plr)       -- a spin just landed: tell them immediately
						save(plr)
					else
						r.partial = SPIN_EVERY   -- banked out; hold the bar full
					end
				end
			end
		end
		if since >= PUSH_EVERY then
			since = 0
			for _, plr in ipairs(Players:GetPlayers()) do pushState(plr) end
		end
	end
end)

print("[WheelServer] online — 1 spin / " .. SPIN_EVERY .. "s, max " .. MAX_BANKED ..
	" banked " .. (store and "(DataStore ready)" or "(no DataStore — spins won't persist)"))
