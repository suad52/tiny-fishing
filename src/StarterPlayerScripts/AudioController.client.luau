--[[
	AudioController — the always-on half of the game's sound.

	Three jobs, none of which any other script should have to think about:
	  1. ZONE MUSIC. One track per zone, crossfaded off the CurrentZone attribute —
	     the same seam ZonesController already publishes for the backdrop and the
	     coin multiplier, so travelling swaps the music for free.
	  2. SEA AMBIENCE. A quiet water-lap bed under everything.
	  3. UI SOUND, GLOBALLY. Rather than editing a click into all ~15 menu
	     controllers (and every future one), this walks PlayerGui and hooks EVERY
	     button, plus DescendantAdded for buttons built later. Menus that open and
	     shut get a swish off their ScreenGui.Enabled.

	The per-action game sounds — cast, splash, reel, bite, payout — belong to the
	script that owns the action, and call ReplicatedStorage.Audio directly.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider   = game:GetService("ContentProvider")
local SoundService      = game:GetService("SoundService")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local plr   = Players.LocalPlayer
local pg    = plr:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- preload
----------------------------------------------------------------------
-- Worth doing up front: an unloaded Sound reports TimeLength 0 and the first play of
-- each clip would otherwise arrive late — which on a 0.6s button click reads as the
-- button not having responded at all.
task.spawn(function()
	local lib = SoundService:WaitForChild("GameAudio", 20)
	if not lib then return end
	pcall(function() ContentProvider:PreloadAsync(lib:GetDescendants()) end)
end)

----------------------------------------------------------------------
-- zone music
----------------------------------------------------------------------
-- Zone ids come from ZonesController's ZONES table:
--   1 Lighthouse Cove · 2 Tropical Reef · 3 Golden Sunset Bay
--   4 Frostbite Fjord · 5 Midnight Trench · 6 Molten Abyss
local function applyZoneMusic()
	local id = plr:GetAttribute("CurrentZone") or 1
	Audio.music("Zone" .. math.clamp(id, 1, 6))
end
plr:GetAttributeChangedSignal("CurrentZone"):Connect(applyZoneMusic)

-- ZonesController writes CurrentZone during ITS init, which may already have happened
-- (no attribute change to listen for) or may be a few frames away still. Applying now
-- and again shortly after covers both without racing: Audio.music no-ops on a repeat.
applyZoneMusic()
task.delay(2, applyZoneMusic)

Audio.startLoop("Sea")

----------------------------------------------------------------------
-- global UI sound
----------------------------------------------------------------------
-- Every button in the game, present and future. The attribute is the idempotence
-- guard: the startup sweep and DescendantAdded both reach buttons built during init,
-- and a doubled connection would play the click twice and sound like a stutter.
local function hookButton(b)
	if b:GetAttribute("SndHooked") then return end
	b:SetAttribute("SndHooked", true)
	-- MouseButton1Down, not Click: the sound should land when the mouse goes down,
	-- which is when the button visually reacts. On Click it trails the press.
	b.MouseButton1Down:Connect(function()
		-- a touch of pitch scatter, or 20 clicks in a row sound like a machine
		Audio.play("Click", { pitch = 0.95 + math.random() * 0.1 })
	end)
end

-- Only "...Menu" ScreenGuis: the HUDs toggle Enabled for reasons that are not a menu
-- opening (blur overlays, the hotbar hider), and swishing on those is noise.
local function hookGui(g)
	if not (g:IsA("ScreenGui") and g.Name:match("Menu$")) then return end
	if g:GetAttribute("SndHooked") then return end
	g:SetAttribute("SndHooked", true)
	g:GetPropertyChangedSignal("Enabled"):Connect(function()
		-- same swish both ways, pitched down on the way out
		Audio.play("Swish", { pitch = g.Enabled and 1.05 or 0.8, volume = 0.7 })
	end)
end

local function hook(inst)
	if inst:IsA("GuiButton") then hookButton(inst)
	elseif inst:IsA("ScreenGui") then hookGui(inst) end
end

for _, d in ipairs(pg:GetDescendants()) do hook(d) end
pg.DescendantAdded:Connect(hook)

print("[Audio] online — zone music, sea ambience, global UI clicks")
