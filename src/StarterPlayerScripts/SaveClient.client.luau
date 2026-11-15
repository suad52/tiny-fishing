--[==[
	SaveClient - sends this player's progress to SaveServer so it survives leaving (2026-10-11).

	The economy lives in this client (attributes on the Player, leaderstats.Money), and a client-side change never
	replicates to the server, so the server only knows what this script tells it. It builds a SNAPSHOT from an
	allowlist (ALLOW below - SaveServer re-checks every name and type) and sends it:
	    * ~2.5 s after any saved value or the balance changes (debounced, so a run of catches is one send),
	    * every 30 s regardless,
	    * straight after a Robux grant is APPLIED (the applying menu fires SaveRemotes.Ack with the receipt id), carrying
	      that id as an ACK - ProductServer only completes the purchase once a snapshot holding the grant is saved.
	Nothing is sent until the server has finished restoring the save (DataLoaded): a snapshot taken before that would
	be the defaults, and would save them over the real progress.

	Zone_2..6 and Boat_2..8 always go as a full set (false where unowned): a rebirth re-locks zones by clearing them,
	and the server REPLACES its copy, so "absent" has to be said out loud.
	BoostLeft_<key> (seconds left on a live potion, written by BoostClient every second) is included in every
	snapshot but never TRIGGERS one, or a running potion would send a snapshot every second.
]==]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

local plr = Players.LocalPlayer

local ALLOW = {
	"^Rebirths$", "^Pearls$", "^Perk_%a+$", "^Upg_%a+$", "^EquippedRod$", "^Bait_%w+$", "^Inv_[%w_]+$",
	"^JackpotCasts$", "^CurrentZone$", "^CurrentBoat$", "^QP_[%w_]+$", "^QT_%a+$", "^MT_[%w_]+$",
	"^Q_DayStamp$", "^Q_WeekStamp$", "^BaitPity%d$", "^BoostLeft_[%w_]+$",
	"^Rod_%d+$", "^Zone_%d+$", "^Boat_%d+$", "^QC_[%w_]+$", "^IX_%w+$", "^TutorialDone$", "^StarterBought$",
	"^AutoCastOn$", "^Set_%w+$", "^EquippedBait$", "^IndexSeen$",
}
local function allowed(n)
	for _, p in ipairs(ALLOW) do
		if n:match(p) then return true end
	end
	return false
end
local function quiet(n) return n:sub(1, 10) == "BoostLeft_" end

local remotes = ReplicatedStorage:WaitForChild("SaveRemotes", 60)
local snapEv = remotes and remotes:WaitForChild("Snapshot", 30)
if not snapEv then
	warn("[SaveClient] SaveRemotes.Snapshot missing - progress will not save this visit")
	return
end

-- not before the restore has landed (see the header)
while plr:GetAttribute("DataLoaded") ~= true do plr:GetAttributeChangedSignal("DataLoaded"):Wait() end

local function money()
	local ls = plr:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Money")
end

local acks, ackOrder = {}, {}
local function build()
	local attrs = {}
	for n, v in pairs(plr:GetAttributes()) do
		if allowed(n) then
			local t = type(v)
			if (t == "number" and v == v and v ~= math.huge and v ~= -math.huge) or t == "boolean" or t == "string" then
				attrs[n] = v
			end
		end
	end
	for i = 2, 6 do if attrs["Zone_" .. i] == nil then attrs["Zone_" .. i] = false end end
	for i = 2, 8 do if attrs["Boat_" .. i] == nil then attrs["Boat_" .. i] = false end end
	local m = money()
	return { attrs = attrs, coins = m and m.Value or nil, acks = ackOrder }
end

local lastSig = ""
local function send(force)
	local snap = build()
	local ok, sig = pcall(HttpService.JSONEncode, HttpService, snap)
	if not ok then sig = tostring(os.clock()) end
	if sig == lastSig and not force then return end
	lastSig = sig
	snapEv:FireServer(snap)
end

local scheduled = false
local function schedule()
	if scheduled then return end
	scheduled = true
	task.delay(2.5, function()
		scheduled = false
		send(false)
	end)
end

plr.AttributeChanged:Connect(function(n)
	if allowed(n) and not quiet(n) then schedule() end
end)

-- the balance changes on every catch; follow whichever Money object exists (CurrencyClient makes it at join)
local bound
local function bindMoney()
	local m = money()
	if m and m ~= bound then
		bound = m
		m.Changed:Connect(schedule)
	end
end
bindMoney()
plr.ChildAdded:Connect(function(c) if c.Name == "leaderstats" then task.defer(bindMoney) end end)

-- Robux grants. SaveClient must NOT listen on the grant remotes itself: a RemoteEvent fired before any listener exists
-- is delivered only to the FIRST script that connects, and this one starts long before the menus, so it would steal a
-- receipt Roblox re-sends at join (and the Robux-zone restores) and ack an item nobody applied. Instead the script
-- that APPLIES a grant fires this client-only Ack with the receipt id, after applying it.
local ackEv = remotes:FindFirstChild("Ack") or Instance.new("BindableEvent")
ackEv.Name = "Ack"
ackEv.Parent = remotes
ackEv.Event:Connect(function(receiptId)
	if type(receiptId) ~= "string" or acks[receiptId] then return end
	acks[receiptId] = true
	table.insert(ackOrder, receiptId)
	if #ackOrder > 30 then acks[table.remove(ackOrder, 1)] = nil end
	task.defer(send, true)
end)

-- a first snapshot once the menus have had a moment to seed, then the safety net
task.delay(6, function() send(true) end)
task.spawn(function()
	while true do
		task.wait(30)
		send(false)
	end
end)
