--[[
	MenuBlurManager (client) — v2
	When a full-screen button-menu is open:
	  * blurs the 3D game via a shared Lighting.BlurEffect, AND
	  * frosts/dims the on-screen UI that a BlurEffect physically can't touch
	    (Roblox only blurs the 3D scene, never GUI) — the bait-roll slots
	    (BaitRoller.Panel) and the button bar (MainMenu.MenuBar) — by fading a
	    managed dark veil over each. So everything behind the menu recedes
	    together instead of the game going soft while the UI stays crisp.

	Watches: the overlay ScreenGuis' .Enabled (Shop/Upgrades/Index/Rebirth/
	Zones) and the MainMenu placeholder Popup.Visible.
]]

local Players      = game:GetService("Players")
local Lighting     = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")

local MAX_BLUR = 20
local VEIL_T   = 0.2    -- veil transparency while a menu is open (lower = darker)
local FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- 3D-scene blur
local blur = Lighting:FindFirstChild("MenuBlur")
if not blur then
	blur = Instance.new("BlurEffect")
	blur.Name = "MenuBlur"
	blur.Size = 0
	blur.Parent = Lighting
end

-- overlay ScreenGuis whose .Enabled = "this menu is open"
-- Every full-screen menu belongs here. If one is missing it simply never blurs, which is
-- invisible in isolation and only shows up as "that menu feels different" — DailyMenu,
-- WheelMenu and FeedbackMenu were all missing until an audit cross-checked this list
-- against the actual ScreenGuis in StarterGui.
local OVERLAYS = {
	ShopMenu = true, UpgradesMenu = true, IndexMenu = true, RebirthMenu = true,
	ZonesMenu = true, SettingsMenu = true, QuestsMenu = true, InventoryMenu = true,
	LeaderboardMenu = true, FeedbackMenu = true, DailyMenu = true, WheelMenu = true, GiftsMenu = true,
	BoatsMenu = true,
	-- Built at RUNTIME by InventoryController rather than sitting in StarterGui, so it will
	-- not show up in a StarterGui audit like the one that found the three missing above.
	-- anyOpen() walks PlayerGui, so it is found there all the same.
	BaitsMenu = true,
}

local function anyOpen()
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and OVERLAYS[g.Name] and g.Enabled then return true end
	end
	local mm = pg:FindFirstChild("MainMenu")
	local popup = mm and mm:FindFirstChild("Popup")
	if popup and popup:IsA("GuiObject") and popup.Visible then return true end
	return false
end

-- one dark veil per UI panel we want to "blur" (slots + buttons)
local function ensureVeil(host)
	if not host then return nil end
	local v = host:FindFirstChild("MenuVeil")
	if not v then
		v = Instance.new("Frame")
		v.Name = "MenuVeil"
		v.BackgroundColor3 = Color3.fromRGB(4, 10, 26)
		v.BorderSizePixel = 0
		v.Size = UDim2.fromScale(1, 1)
		v.Position = UDim2.fromScale(0, 0)
		v.ZIndex = 30000
		v.BackgroundTransparency = 1
		v.Visible = false
		v.Active = false          -- never intercept clicks
		v.Parent = host
	end
	return v
end

-- the two panels: bait-roll slots + the right-side button bar (live refs, respawn-safe)
local function veilHosts()
	local t = {}
	local br = pg:FindFirstChild("BaitRoller")
	local panel = br and br:FindFirstChild("Panel")
	if panel then t[#t+1] = panel end
	local mm = pg:FindFirstChild("MainMenu")
	local bar = mm and mm:FindFirstChild("MenuBar")
	if bar then t[#t+1] = bar end
	return t
end

local function update()
	-- Settings > Menu Blur (Set_Blur) can switch the whole effect off. It gates the
	-- veil too: a dark veil with no blur behind it just reads as a bug.
	local open = anyOpen() and (plr:GetAttribute("Set_Blur") ~= false)
	TweenService:Create(blur, FADE, { Size = open and MAX_BLUR or 0 }):Play()
	for _, host in ipairs(veilHosts()) do
		local v = ensureVeil(host)
		if v then
			if open then
				v.Visible = true
				TweenService:Create(v, FADE, { BackgroundTransparency = VEIL_T }):Play()
			else
				local tw = TweenService:Create(v, FADE, { BackgroundTransparency = 1 })
				tw.Completed:Connect(function() if not anyOpen() then v.Visible = false end end)
				tw:Play()
			end
		end
	end
end

-- hook menu open/close signals
local hooked = {}
local function hookOverlay(g)
	if hooked[g] then return end
	hooked[g] = true
	g:GetPropertyChangedSignal("Enabled"):Connect(update)
end
for _, g in ipairs(pg:GetChildren()) do
	if g:IsA("ScreenGui") and OVERLAYS[g.Name] then hookOverlay(g) end
end
pg.ChildAdded:Connect(function(g)
	if g:IsA("ScreenGui") and OVERLAYS[g.Name] then hookOverlay(g); update() end
end)

task.spawn(function()
	local mm = pg:WaitForChild("MainMenu", 20)
	if not mm then return end
	local popup = mm:WaitForChild("Popup", 20)
	if popup and not hooked[popup] then
		hooked[popup] = true
		popup:GetPropertyChangedSignal("Visible"):Connect(update)
		update()
	end
end)

-- re-run when the Settings menu flips the toggle
plr:GetAttributeChangedSignal("Set_Blur"):Connect(update)

-- make sure the panels exist before first paint
if not pg:FindFirstChild("BaitRoller") then pg:WaitForChild("BaitRoller", 20) end
update()
