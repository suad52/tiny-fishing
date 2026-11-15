--[==[
	FirstCatchChat - shows FirstCatchServer's announcements as a system message in the General chat
	channel, with the fish in its rarity colour (FishData.rarityColor, the Index's own palette).
	A catch made in ANOTHER server arrives with global = true and is tagged [GLOBAL].
]==]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService   = game:GetService("TextChatService")

local FishData = require(ReplicatedStorage:WaitForChild("FishData"))
local remote   = ReplicatedStorage:WaitForChild("ChatRemotes"):WaitForChild("FirstCatch")

local ICON = { Mythic = "🔱", Legendary = "🌟", Epic = "💎" }

local function hex(c)
	if typeof(c) ~= "Color3" then return "#FFFFFF" end
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- rich text: a display name must never be able to open a tag
local function esc(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

local general
local function channel()
	if general and general.Parent then return general end
	local chans = TextChatService:FindFirstChild("TextChannels")
	general = chans and chans:FindFirstChild("RBXGeneral")
	return general
end

remote.OnClientEvent:Connect(function(who, fish, rarity, global)
	local ch = channel()
	if not ch then return end
	local col = hex(FishData.rarityColor and FishData.rarityColor[rarity])
	ch:DisplaySystemMessage(string.format(
		'%s%s <font color="#FFFFFF"><b>%s</b></font> caught their first <font color="%s"><b>%s %s</b></font>!',
		global and '<font color="#7FD8FF"><b>[GLOBAL]</b></font> ' or "",
		ICON[rarity] or "🎣", esc(who), col, esc(rarity), esc(fish)))
end)
