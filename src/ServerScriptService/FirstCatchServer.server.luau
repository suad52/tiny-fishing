--[==[
	FirstCatchServer - "🎣 Name caught their first Legendary Kraken!" in everyone's chat.

	IndexController's markDiscovered() is the one place that knows a species is NEW to this player,
	so it reports the name here (ChatRemotes.FirstCatch). This script checks it against FishData,
	keeps one announcement per player per species, and - if the fish is at least MinRarity - tells
	every client, whose FirstCatchChat shows it as a system message in the General channel.

	MinRarity (this script's attribute, default "Epic") is the dial: Common / Uncommon / Rare /
	Epic / Legendary / Mythic. Lower it and chat fills fast - there are 27 Common+Uncommon species
	and a new player finds most of them in their first few minutes.

	GLOBAL: the same line also goes to EVERY other server through MessagingService (topic
	FirstCatch_v1), tagged [GLOBAL] there, for fish at least GlobalMinRarity (default "Legendary" -
	6 species; across every server even Epic would scroll chat away). This server still shows its
	own line normally. Publishing is queued at 1 a second and each server shows at most
	GLOBAL_PER_MIN global lines a minute, so a busy game cannot flood anyone. MessagingService does
	not run in Studio without API access: the DevGlobal BindableEvent under this script feeds the
	receive path by hand - DevGlobal:Fire(displayName, fishName).

	"First" means first this session: nothing in this game is saved between visits, and the Fish
	Index starts empty on every join, so a rejoin can announce the same fish again.
	TRUST: client-reported, like the rest of the economy. The dedupe caps a spammer at 61 lines.
]==]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService  = game:GetService("MessagingService")

local FishData = require(ReplicatedStorage:WaitForChild("FishData"))

local folder = ReplicatedStorage:FindFirstChild("ChatRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "ChatRemotes"
	folder.Parent = ReplicatedStorage
end
local remote = folder:FindFirstChild("FirstCatch")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "FirstCatch"
	remote.Parent = folder
end

local RANK = {}
for i, r in ipairs(FishData.rarityOrder) do RANK[r] = i end
local BY_NAME = {}
for _, f in ipairs(FishData.fish) do BY_NAME[f.name] = f end

local seen = {}   -- [player] = { [fish name] = true }

local TOPIC          = "FirstCatch_v1"
local GLOBAL_PER_MIN = 8

local function atLeast(f, attr, default)
	return (RANK[f.rarity] or 0) >= (RANK[script:GetAttribute(attr)] or RANK[default])
end

-- outgoing: queued, one publish a second (well inside MessagingService's per-server budget)
local outbox = {}
local function publishGlobal(who, f)
	if #outbox < 20 then table.insert(outbox, { j = game.JobId, n = who, f = f.name, r = f.rarity }) end
end
task.spawn(function()
	while true do
		local msg = table.remove(outbox, 1)
		if msg then
			local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, msg)
			if not ok then warn("[FirstCatch] global publish failed: " .. tostring(err)) end
		end
		task.wait(1)
	end
end)

-- incoming: from any OTHER server, re-checked (never trust the wire), capped per minute
local recent = {}
local function onGlobal(data)
	if type(data) ~= "table" or data.j == game.JobId then return end
	local f = type(data.f) == "string" and BY_NAME[data.f]
	if not f or not atLeast(f, "GlobalMinRarity", "Legendary") then return end
	if type(data.n) ~= "string" or #data.n == 0 or #data.n > 40 then return end
	local now = os.clock()
	while recent[1] and now - recent[1] > 60 do table.remove(recent, 1) end
	if #recent >= GLOBAL_PER_MIN then return end
	table.insert(recent, now)
	remote:FireAllClients(data.n, f.name, f.rarity, true)
end
task.spawn(function()
	local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(m) onGlobal(m.Data) end)
	if not ok then warn("[FirstCatch] global chat unavailable here: " .. tostring(err)) end
end)

local dev = script:FindFirstChild("DevGlobal") or Instance.new("BindableEvent")
dev.Name = "DevGlobal"
dev.Parent = script
dev.Event:Connect(function(who, fish)
	local f = BY_NAME[fish]
	if f then onGlobal({ j = "dev", n = tostring(who), f = f.name, r = f.rarity }) end
end)

remote.OnServerEvent:Connect(function(plr, name)
	if type(name) ~= "string" then return end
	local f = BY_NAME[name]
	if not f then return end
	local mine = seen[plr]
	if not mine then
		mine = {}
		seen[plr] = mine
	end
	if mine[name] then return end
	mine[name] = true
	if atLeast(f, "MinRarity", "Epic") then remote:FireAllClients(plr.DisplayName, f.name, f.rarity) end
	if atLeast(f, "GlobalMinRarity", "Legendary") then publishGlobal(plr.DisplayName, f) end
end)

Players.PlayerRemoving:Connect(function(plr) seen[plr] = nil end)

print(("[FirstCatch] online - this server: %s+, every server: %s+"):format(
	tostring(script:GetAttribute("MinRarity") or "Epic"), tostring(script:GetAttribute("GlobalMinRarity") or "Legendary")))
