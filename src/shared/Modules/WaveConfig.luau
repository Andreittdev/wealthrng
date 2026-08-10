-- Endless Mode's wave pacing -- flat duration per wave, tuned so a player
-- grinding continuously hits the current cap (MaxWave) in exactly
-- TargetHours. 800 waves * 45s = 36000s = exactly 10 hours, per explicit
-- request ("wave 800-850 in 10 ore de joc, sa fie maximul momentan").
-- MaxWave is a soft ceiling on today's content, not a hard game design
-- limit -- raise it later once there's more to fight past it.

local WaveConfig = {}

WaveConfig.MaxWave = 800
WaveConfig.WaveDurationSeconds = 45
WaveConfig.TargetHoursToMaxWave = (WaveConfig.MaxWave * WaveConfig.WaveDurationSeconds) / 3600

-- Elapsed active seconds -> current wave (1-indexed, clamped at MaxWave).
function WaveConfig.GetWaveForElapsedSeconds(elapsedSeconds: number): number
	local wave = math.floor(elapsedSeconds / WaveConfig.WaveDurationSeconds) + 1
	return math.clamp(wave, 1, WaveConfig.MaxWave)
end

return WaveConfig
