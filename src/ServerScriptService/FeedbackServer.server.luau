--[[ FeedbackServer — receives player feedback from the Feedback menu.

	This is the only place feedback actually LANDS, so it re-validates everything:
	the client is untrusted, and a RemoteEvent is callable by any exploiter with any
	payload. Shape, types, lengths and rate limit are all re-checked here.

	Where it goes:
	  1. print() -> visible in the live Developer Console (F9 -> Server) and in the
	     Creator Dashboard's server logs. Works with zero setup.
	  2. a DataStore, if Studio/API access allows it (pcall'd, so it simply no-ops in
	     a local Studio session instead of erroring every submission).
--]]

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local remote = ReplicatedStorage:WaitForChild("FeedbackRemote")

local store
pcall(function() store = DataStoreService:GetDataStore("PlayerFeedback") end)

local COOLDOWN = 20
local lastSent = {}

remote.OnServerEvent:Connect(function(plr, payload)
	if type(payload) ~= "table" then return end

	local cat    = tostring(payload.category or "Other"):sub(1, 24)
	local rating = math.clamp(math.floor(tonumber(payload.rating) or 0), 0, 5)
	local msg    = tostring(payload.message or ""):sub(1, 400)
	if #msg < 2 then return end

	local now = os.clock()
	if lastSent[plr.UserId] and now - lastSent[plr.UserId] < COOLDOWN then
		remote:FireClient(plr, false, "Please wait a moment before sending again.")
		return
	end
	lastSent[plr.UserId] = now

	print(string.format("[Feedback] %s (%d) | %s | %d/5 | %s", plr.Name, plr.UserId, cat, rating, msg))

	if store then
		local key = string.format("%d_%d", os.time(), plr.UserId)
		local ok = pcall(function()
			store:SetAsync(key, {
				user = plr.Name, userId = plr.UserId,
				category = cat, rating = rating, message = msg, at = os.time(),
			})
		end)
		if not ok then
			warn("[Feedback] DataStore write failed (expected in Studio without API access)")
		end
	end

	remote:FireClient(plr, true)
end)

Players.PlayerRemoving:Connect(function(p) lastSent[p.UserId] = nil end)

print("[FeedbackServer] online" .. (store and " (DataStore ready)" or " (log only)"))
