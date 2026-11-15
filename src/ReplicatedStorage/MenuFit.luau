--[==[
	MenuFit — one fit rule for every pop-up window in the game.

	THE PROBLEM IT REPLACES. Each menu carried its own copy of
		scale = clamp(min(vw/(W+50), vh/(H+50)), 0.4, 1.1)
	i.e. shrink the whole 1100x680 desktop window uniformly until it fits. On a phone the
	HEIGHT is always the binding axis — an 812x375 screen is 2.17:1 while the window is
	1.62:1 — so the window came out at ~0.51 and used barely two thirds of the screen
	width. Measured on the device matrix, body copy landed at 5-7pt and 143 controls fell
	under the 44px touch floor.

	Raising the 0.4 floor does NOT help: the window then overflows the screen. What helps
	is making the window SHORTER rather than smaller, so the width can drive the scale.
	Every one of these windows is a fixed-height header over a body sized (1, -N) — so a
	shorter design height just shortens the scroll viewport, which is exactly right. Each
	menu's minH was found by binary search: the shortest design height at which nothing
	outside a ScrollingFrame pokes out of the window.

	It ALSO moves the window out from under the Roblox top bar. Every one of these
	ScreenGuis sets IgnoreGuiInset = true, so a centred window drew under the platform's
	own chrome — and since the close X lives in the window's top-right corner, on a phone
	it sat inside the top bar's tap region. The adaptive branch centres the window in the
	band BELOW the inset instead.

	DESKTOP IS DELIBERATELY UNTOUCHED. Above ADAPT_BELOW the old formula, the authored
	height and the screen-centred position are all reproduced exactly; a 1313x751 window
	and an iPad both stay on that path. The adaptive branch only runs on small screens.
]==]

local GuiService = game:GetService("GuiService")

local MenuFit = {}

local PAD         = 50    -- the breathing room the original formula allowed on width
local EDGE        = 12    -- gap left below the window on a small screen
local ADAPT_BELOW = 0.85  -- above this the screen is roomy: keep the original behaviour

-- root  : the window Frame, AnchorPoint (0.5, 0.5)
-- scale : its UIScale
-- W, H  : the authored design size
-- minS, maxS : that menu's original clamp
-- minH  : shortest design height this menu's layout survives (defaults to H = no shrink)
function MenuFit.apply(root, scale, W, H, minS, maxS, minH)
	-- A WINDOW MUST SWALLOW THE TAPS THAT LAND ON IT. Every menu parks a full-screen, close-on-
	-- click "Backdrop" button BEHIND its window, and a Frame is not Active by default - so a
	-- tap on any non-button part of the window (the header, a card's body, the strip under a
	-- title) fell straight through to that Backdrop and CLOSED the menu. Measured with
	-- GetGuiObjectsAtPosition on 11 of the 14 menus (a real click on Inventory's header closed
	-- it), on every device. Every window passes through here, so this is the one place to fix it.
	root.Active = true
	local cam = workspace.CurrentCamera
	if not cam then return scale.Scale end
	local vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y
	-- A `< 1` guard is not enough. Client scripts can run before the viewport has settled,
	-- and a handful-of-pixels viewport is not a small screen, it is a not-yet-a-screen: it
	-- sent the Feedback panel down the adaptive branch and left it at a 1e-07 scale until
	-- something re-fitted it. No real device is under 100px on either axis; wait for one.
	if vw < 100 or vh < 100 then return scale.Scale end
	minH = minH or H

	local uniform = math.clamp(math.min(vw / (W + PAD), vh / (H + PAD)), minS, maxS)
	if uniform >= ADAPT_BELOW then
		root.Size = UDim2.fromOffset(W, H)
		root.Position = UDim2.fromScale(0.5, 0.5)
		scale.Scale = uniform
		-- TOUCH TABLETS ONLY (an iPad takes this roomy branch). Screen-centred, a window taller
		-- than ~700 design px started INSIDE the top bar - the Wheel at y 27, Settings 47,
		-- Leaderboard 50 on an iPad, where the platform's own buttons sit. Such a window moves into
		-- the band below the bar, shrinking only if it cannot fit there. A mouse device keeps the
		-- exact original placement, so desktop is pixel-identical.
		local UIS = game:GetService("UserInputService")
		if UIS.TouchEnabled and not UIS.MouseEnabled then
			local inset = GuiService:GetGuiInset().Y
			if (vh - H * uniform) / 2 < inset then
				local availH = math.max(160, vh - inset - EDGE)
				local s = math.max(0.1, math.min(uniform, availH / H))
				scale.Scale = s
				root.Position = UDim2.new(0.5, 0, 0, math.floor(inset + availH / 2 + 0.5))
				return s
			end
		end
		return uniform
	end

	local inset = GuiService:GetGuiInset().Y
	local availH = math.max(160, vh - inset - EDGE)
	local byWidth = math.clamp(vw / (W + PAD), minS, maxS)
	local newH = math.clamp(availH / byWidth, minH, H)
	local s = math.clamp(math.min(vw / (W + PAD), availH / newH), minS, maxS)
	-- The minS floor exists to stop a window becoming unreadably small, but it must never
	-- push the window off the screen: the Shop's 0.45 floor made it 531px wide on a 480px
	-- screen, i.e. 51px of it (and the controls in that strip) simply gone. Below the floor
	-- a small window beats a cropped one - the same trade the BaitRoller's floor makes.
	-- max(): the caps above are ratios of the viewport and must never drive the scale to
	-- zero or below, whatever a caller passes in.
	s = math.max(0.1, math.min(s, (vw - EDGE) / W, availH / newH))

	root.Size = UDim2.fromOffset(W, math.floor(newH + 0.5))
	scale.Scale = s
	-- centre in the band below the platform's top bar, not on the raw screen
	root.Position = UDim2.new(0.5, 0, 0, math.floor(inset + availH / 2 + 0.5))
	return s
end

-- CENTRE A WINDOW ON THE SCREEN (2026-10-10, the owner: "center all the ui stuff to the screen"). Called AFTER a
-- menu's own fit. `up` / `down`: how far its art reaches past the window's box (a breakout icon above, the hard drop
-- below). The window is centred on the real screen; if the art above would then reach into Roblox's top bar, the
-- window gets a little SMALLER - it is never moved off centre. Returns the scale.
-- PHONES TOO (2026-10-11, the owner: "make the button uis centered to the phone screen", then chose "centre, tuck
-- the icon"). Phones used to be skipped: the top bar is a fifth of their height, and centring matches that band at
-- the bottom. So on a phone each menu first TUCKS its breakout icon inside its header (its own phone layout) and
-- passes the reach that is left - 0 for a tucked icon - as `up`; measured, windows then lose ~11-16% of their height
-- instead of the ~25-30% an icon breaking out above them would cost. The close X at the top-right is NOT part of
-- `up`: it rises into the top bar's free region (TopbarInset), right of Roblox's own buttons.
function MenuFit.centre(root, scale, up, down)
	local cam = workspace.CurrentCamera
	if not cam then return scale.Scale end
	local vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y
	if vw < 100 or vh < 100 then return scale.Scale end
	up, down = up or 0, down or 0
	local bar = GuiService.TopbarInset.Max.Y
	local top0 = (bar > 0 and bar or GuiService:GetGuiInset().Y) + 4
	local h = root.Size.Y.Offset
	local s = scale.Scale
	local sMax = math.min((vh / 2 - top0) / (h / 2 + up), (vh / 2 - 6) / (h / 2 + down))
	if s > sMax then
		s = math.max(0.1, sMax)
		scale.Scale = s
	end
	root.Position = UDim2.fromScale(0.5, 0.5)
	return s
end

return MenuFit
