--[==[
	SeaWave - the ONE description of the sea surface.

	SeaFX draws the wave ribbon from this, and BoatClient rocks the hull on it, so
	the boat rides the crests you can actually see. That is the whole reason the
	coefficients live here instead of being copied: a second copy in the boat code
	drifts out of phase with the ribbon the moment the swell is retuned, and "the
	boat is rocking to invisible water" is not a bug anyone would go looking for
	in a wave table.

	COORDINATES. `x` is WORLD X (the ribbon bars are placed at their own world x,
	and the boat samples the world x of its bow and stern). `t` is `os.clock()` -
	every reader must use the same clock or they desynchronise.

	heightAt returns studs above the SEA PLANE, not above the waterline: its mean
	is BASE, because the ribbon has to crest above the plane's own dead-straight
	top edge (see SeaFX's header - both ends of that range are load-bearing).
	Anything FLOATING wants `heightAt(x, t) - BASE`, the zero-mean displacement.
--]==]

local SeaWave = {}

-- Three sines so the swell never visibly repeats. Amplitudes sum to 0.48, so the
-- crest lives in y 0.12..1.08. Held as a local as well as a field because SeaFX
-- calls heightAt 144 times a frame and a table index per call is pure waste.
local BASE = 0.6
SeaWave.BASE = BASE

function SeaWave.heightAt(x, t)
	return BASE
		+ 0.26 * math.sin(x * 0.26 + t * 1.4)
		+ 0.15 * math.sin(x * 0.58 - t * 2.1)
		+ 0.07 * math.sin(x * 1.15 + t * 3.0)
end

return SeaWave
