-- Curated graphics CVars, grouped by topic. Anything not listed here still shows up
-- (auto-typed) in the "All graphics", "Hidden" and "Everything" views.
--
-- Row helpers:
--   B(cvar, label, note)                       on/off checkbox
--   R(cvar, label, min, max, step, note)       slider + exact-value box (typed values may exceed the range)
--   E(cvar, label, {value, text, ...}, note)   dropdown
-- Optional trailing flags table: { restart = true } marks settings that need a client restart.

local _, ns = ...

local function B(cvar, label, note, flags) return { cvar = cvar, label = label, note = note, kind = "bool", flags = flags } end
local function R(cvar, label, min, max, step, note, flags)
	return { cvar = cvar, label = label, note = note, kind = "range", min = min, max = max, step = step, flags = flags }
end
-- One-click presets: a row of buttons, each writing several CVars at once.
-- cvar = the row's anchor (it must exist for the row to show).
local function P(cvar, label, presets, note)
	return { cvar = cvar, label = label, note = note, kind = "presets", presets = presets }
end
local function E(cvar, label, options, note, flags)
	local list = {}
	for i = 1, #options, 2 do list[#list + 1] = { value = tostring(options[i]), text = options[i + 1] } end
	return { cvar = cvar, label = label, note = note, kind = "enum", options = list, flags = flags }
end
local RESTART = { restart = true }

local function Levels(from, to, names)
	local t = {}
	for v = from, to do
		t[#t + 1] = v
		t[#t + 1] = names and names[v - from + 1] and (v .. " - " .. names[v - from + 1]) or tostring(v)
	end
	return t
end

ns.categories = {
	{
		key = "fog", title = "Fog & Atmosphere",
		E("graphicsViewDistance", "View distance (Blizzard slider)",
			{ 0, "1 (lowest)", 1, "2", 2, "3", 3, "4", 4, "5", 5, "6", 6, "7", 7, "8", 8, "9", 9, "10 (highest)" },
			"Blizzard's combined setting. It rewrites far clip, horizon and detail distances. Low values add distance fog."),
		R("horizonStart", "Horizon start distance", 50, 12000, 50,
			"Lower values fade distant land into the fog sooner (more fog). Values above the game's own do nothing. The Blizzard view distance slider resets it; use Keep my value."),
		R("nearclip", "Near clip", 0.01, 2, 0.01, "Distance before the camera where rendering starts."),
		R("SkyCloudLOD", "Sky cloud texture detail", 0, 3, 1, "Cloud texture resolution. 0 is the game's default."),
	},
	{
		key = "light", title = "Light & Sun",
		B("bloomEnable", "Bloom", "Glow around bright areas."),
		R("bloomUserMult", "Bloom intensity", 0, 3, 0.05, "The game's slider tops out at 1. Higher values are experimental."),
		E("giQuality", "Global illumination quality", Levels(0, 3)),
		R("specular", "Specular highlights", 0, 1, 0.05, "Shine on world surfaces."),
		R("maxLightDist", "Max light distance", 0, 8192, 64, "How far away dynamic lights still render."),
		B("clusteredShading", "Clustered shading", "Lets transparent objects receive lights."),
		B("forceClusteredShading", "Force clustered shading", "Uses clustered forward lighting for every transparent object."),
		B("componentSpecular", "Character specular"),
		B("componentEmissive", "Character emissive/unlit parts"),
		B("ffxGlow", "Full-screen glow"),
		B("ffxDeath", "Death desaturation"),
		B("ffxNether", "Nether full-screen effect"),
		B("ffxVenari", "Cloak of Ven'ari effect"),
		B("ffxLingeringVenari", "Lingering Ven'ari effect"),
	},
	{
		key = "shadow", title = "Shadows",
		E("shadowMode", "Shadow mode", Levels(0, 3)),
		E("shadowTextureSize", "Shadow map resolution", { 512, "512", 1024, "1024", 2048, "2048", 4096, "4096 (experimental)" }),
		R("shadowNumCascades", "Shadow cascades", 1, 4, 1, "More cascades give sharper shadows at distance."),
		B("shadowBlendCascades", "Blend shadow cascades", "Smooths the seams between cascades."),
		B("shadowSoft", "Soft shadows"),
		E("shadowRt", "Ray-traced shadows", Levels(0, 3, { "Off", "Fair", "Good", "High" })),
		R("entityShadowFadeScale", "Character shadow fade distance", 1, 100, 1),
	},
	{
		key = "ao", title = "Ambient Occlusion",
		E("SSAO", "SSAO level", Levels(0, 4, { "Off", "Low", "Good", "High", "Ultra" })),
		E("SSAOType", "SSAO technique", Levels(0, 3), "0 is automatic. Other values select specific techniques (ASSAO or CACAO)."),
		R("assaoShadowMult", "ASSAO strength", 0, 5, 0.05, "Linear effect strength."),
		R("assaoShadowPower", "ASSAO contrast (power)", 0.5, 5, 0.05),
		R("assaoRadius", "ASSAO radius", 0.01, 10, 0.05, "World-space size of the occlusion sphere."),
		R("assaoDetailShadowStrength", "ASSAO fine detail", 0, 5, 0.05),
		R("assaoHorizonAngleThresh", "ASSAO horizon angle threshold", 0, 1, 0.01, "Limits self-shadowing."),
		R("assaoShadowClamp", "ASSAO shadow clamp", 0, 1, 0.01),
		R("assaoSharpness", "ASSAO edge sharpness", 0, 1, 0.01),
		R("assaoBlurPassCount", "ASSAO blur passes", 0, 6, 1),
		R("assaoFadeOutFrom", "ASSAO fade start", 0, 1000, 5),
		R("assaoFadeOutTo", "ASSAO fade end", 0, 2000, 10),
		R("assaoAdaptiveQualityLimit", "ASSAO adaptive quality", 0, 1, 0.01, "Only applies at quality level 3."),
		R("assaoTemporalSSAngleOffset", "ASSAO temporal angle offset", 0, 3.14, 0.01),
		R("assaoTemporalSSRadiusOffset", "ASSAO temporal radius offset", 0, 2, 0.01),
		B("assaoNormals", "ASSAO uses normals"),
		B("ssaoMagicNormals", "SSAO blended normals"),
		R("ssaoMagicThresholdLow", "SSAO normal blend low (deg)", 0, 90, 1),
		R("ssaoMagicThresholdHigh", "SSAO normal blend high (deg)", 0, 90, 1),
		R("cacaoBilateralSimilarityDistanceSigma", "CACAO upsample similarity", 0, 0.2, 0.001),
	},
	{
		key = "image", title = "Image & Post",
		R("Gamma", "Gamma", 0.3, 2.8, 0.01),
		R("Brightness", "Brightness", 0, 100, 1),
		R("Contrast", "Contrast", 0, 100, 1),
		R("RenderScale", "Render scale", 0.33, 2, 0.01, "Values above 1 are supersampling."),
		E("ResampleQuality", "Upscaler / resample", Levels(0, 4, { "Point", "Bilinear", "Bicubic", "FSR 1.0", "CAS" })),
		R("ResampleSharpness", "Sharpening", 0, 2, 0.05),
		B("ResampleAlwaysSharpen", "Always run the sharpen pass"),
		E("ffxAntiAliasingMode", "Post-process anti-aliasing", Levels(0, 4, { "None", "FXAA Low", "FXAA High", "CMAA", "CMAA2" })),
		E("CMAA2Quality", "CMAA2 quality", Levels(0, 3, { "Low", "Medium", "High", "Ultra" })),
		B("CMAA2ExtraSharpness", "CMAA2 extra sharpness"),
		E("MSAAQuality", "MSAA", Levels(0, 3, { "Off", "2x", "4x", "8x" })),
		B("MSAAAlphaTest", "MSAA on foliage (alpha-tested)"),
		E("textureFilteringMode", "Texture filtering", Levels(0, 5, { "Bilinear", "Trilinear", "2x Aniso", "4x Aniso", "8x Aniso", "16x Aniso" })),
		B("DepthBasedOpacity", "Soft particle edges"),
		R("cameraFov", "Field of view", 50, 120, 1, "The engine may clamp values above 90."),
		E("RenderFormat", "Render target format", { 0, "0 - BGRA8", 1, "1 - A2BGR10", 2, "2 - RGBA16F", 3, "3 - RGBA32F" }, nil, RESTART),
		E("OutlineEngineMode", "Object outlines", Levels(0, 2, { "Off", "Mouseover", "Mouseover + Target" })),
	},
	{
		key = "hdr", title = "HDR",
		B("HDROutput", "HDR output"),
		R("HDRFactor", "HDR headroom factor", 1, 8, 0.1, "How far above SDR lighting HDR may push."),
		B("useHDRBrightness", "Override paper-white brightness"),
		R("HDRBrightness", "Paper-white brightness (nits)", 80, 500, 1),
		B("useHDRPeakBrightness", "Override peak brightness"),
		R("HDRPeakBrightness", "Peak brightness (nits)", 200, 4000, 10),
	},
	{
		key = "water", title = "Water",
		E("waterDetail", "Water detail", Levels(0, 3)),
		E("rippleDetail", "Ripple detail", Levels(0, 2)),
		E("reflectionMode", "Reflections", Levels(0, 3)),
		B("reflectionDownscale", "Half-resolution reflections"),
		E("refraction", "Refraction", Levels(0, 2)),
		E("pbrLiquidDetail", "PBR liquid detail", Levels(0, 2)),
		B("gxMTRefraction", "Render refraction in parallel", "Performance only."),
	},
	{
		key = "distance", title = "Distance & LOD",
		R("terrainLodDist", "Terrain LOD distance", 100, 2000, 25),
		R("TerrainLodDiv", "Terrain LOD divisor", 128, 1024, 32),
		R("wmoLodDist", "Building LOD distance", 100, 2000, 25),
		R("wmoLodDistScale", "Building LOD scale", 0.25, 4, 0.05),
		R("wmoDoodadDist", "Building prop distance", 0, 8000, 50),
		R("wmoPortalFadeScale", "Building portal fade", 0, 4000, 50),
		B("wmoPortalInteriorFade", "Portal interior fade"),
		R("doodadLodScale", "Prop LOD scale", 10, 500, 5),
		R("entityLodDist", "Creature LOD distance", 0, 100, 1),
		R("entityLodOffset", "Creature LOD offset", 0, 100, 1),
		R("lodObjectCullSize", "Small-object cull size", 0, 60, 1, "Lower values keep smaller objects visible at range."),
		R("lodObjectMinSize", "Min object size", 0, 60, 1),
		R("lodObjectCullDist", "Object cull distance minimum", 0, 500, 5),
		R("lodObjectFadeScale", "Object fade scale", 0, 500, 5),
		R("lodObjectSizeScale", "Object size scale (culling)", 0.1, 4, 0.05),
		B("dynamicLod", "Dynamic LOD"),
		B("animFrameSkipLOD", "Skip animation frames at range"),
		R("streamingCameraRadius", "Streaming radius", 50, 500, 10),
		R("streamingCameraMaxRadius", "Streaming max radius", 100, 1000, 10),
		R("streamingCameraLookAheadTime", "Streaming look-ahead (ms)", 0, 10000, 100),
	},
	{
		-- The in-game Ground Clutter slider tops out at density 48 / distance 320.
		-- The engine accepts much more; gameMax marks where the game's own slider ends.
		key = "clutter", title = "Ground Clutter",
		P("groundEffectDensity", "Presets", {
			{ "Off", { groundEffectDensity = 0 } },
			{ "Game max", { groundEffectDensity = 48, groundEffectDist = 320, groundEffectFade = 70 } },
			{ "Dense", { groundEffectDensity = 128, groundEffectDist = 400, groundEffectFade = 200 } },
			{ "Fuller", { groundEffectDensity = 256, groundEffectDist = 500, groundEffectFade = 370 } },
		}, "Fuller is the popular \"fuller world\" setting (256 / 500 / 370). Changing the game's own Ground Clutter slider or the overall graphics quality rewrites these; keep Reapply at login on, or use Keep my value (right-click a row)."),
		R("groundEffectDensity", "Density", 0, 256, 4, "Grass and plants per patch. The game's slider stops at 48; 0 turns clutter off.", { gameMax = 48 }),
		R("groundEffectDist", "Distance", 0, 1000, 10, "How far away clutter is drawn (yards). The game's slider stops at 320.", { gameMax = 320 }),
		R("groundEffectFade", "Fade distance", 0, 500, 10, "Distance over which clutter fades in at the edge. The game uses 70.", { gameMax = 70 }),
	},
	{
		key = "textures", title = "Textures & Characters",
		E("worldBaseMip", "World texture detail", Levels(0, 3, { "Full", "Half", "Quarter", "Eighth" })),
		E("terrainMipLevel", "Terrain blend detail", Levels(0, 1, { "Full", "Reduced" })),
		E("componentTextureLevel", "Character texture detail", Levels(0, 3, { "Full", "Half", "Quarter", "Eighth" })),
		B("projectedTextures", "Projected textures", "Spell decals projected onto the ground."),
		R("componentTexCacheSize", "Character texture cache (MB)", 8, 512, 8),
		R("componentTexLoadLimit", "Character textures loaded per frame", 1, 64, 1),
		R("MaxCharacterComponentLoadStartsPerFrame", "Character composites per frame", 1, 8, 1),
		B("componentCompress", "Compress character textures"),
		B("worldPreloadHighResTextures", "Preload high-res textures"),
		R("bodyQuota", "Max visible characters", 10, 400, 5),
	},
	{
		key = "effects", title = "Effects & Particles",
		R("particleDensity", "Particle density", 0, 100, 5),
		R("particleMTDensity", "Multi-texture particle density", 0, 100, 5),
		E("spellClutter", "Spell clutter", Levels(-1, 3)),
		B("showfootprintparticles", "Footprint particles"),
		E("physicsLevel", "Physics (cloth, hair)", Levels(0, 2, { "Off", "Player", "All" })),
		B("M2ForceAdditiveParticleSort", "Force additive particle sort"),
		E("vrsParticles", "Particle shading rate", { "1x1", "1x1 (full)", "1x2", "1x2", "2x1", "2x1", "2x2", "2x2" }),
		E("vrsWorldGeo", "World shading rate", { "1x1", "1x1 (full)", "1x2", "1x2", "2x1", "2x1", "2x2", "2x2" }),
	},
	{
		key = "camera", title = "Camera",
		R("cameraDistanceMaxZoomFactor", "Max zoom-out factor", 1, 4, 0.1, "Hidden CVar. The engine usually caps this at 2.6."),
		R("cameraZoomSpeed", "Zoom speed", 1, 50, 1),
		B("cameraWaterCollision", "Camera collides with water"),
		B("cameraIndirectVisibility", "Camera see-through obstacles"),
		R("cameraIndirectOffset", "Camera obstacle offset", 0, 20, 0.5),
		B("cameraSmoothPitch", "Smooth pitch"),
		B("cameraSmoothYaw", "Smooth yaw"),
		R("cameraYawMoveSpeed", "Yaw speed", 10, 360, 5),
		R("cameraPitchMoveSpeed", "Pitch speed", 10, 360, 5),
		B("cameraTerrainTilt", "Tilt with terrain"),
		R("cameraFoVSmoothSpeed", "FoV smoothing speed", 0, 20, 0.5),
		R("cameraBobbingSmoothSpeed", "Camera bob smoothing", 0, 20, 0.5),
	},
	{
		key = "perf", title = "Frame Rate & Threads",
		B("useMaxFPS", "Limit foreground FPS"),
		R("maxFPS", "Foreground FPS cap", 8, 500, 1),
		B("useMaxFPSBk", "Limit background FPS"),
		R("maxFPSBk", "Background FPS cap", 8, 240, 1),
		B("useTargetFPS", "Use target FPS"),
		R("targetFPS", "Target FPS", 8, 240, 1),
		B("DynamicRenderScale", "Dynamic render scale (beta)"),
		R("DynamicRenderScaleMin", "Dynamic render scale minimum", 0.33, 1, 0.01),
		R("LowLatencyMinInterval", "Low-latency min frame time (us)", -1, 50000, 100),
		B("gxMTDisable", "Disable all render multithreading", "Debugging only; costs a lot of FPS."),
		B("gxMTDecals", "Render decals in parallel", "Blizzard warns this can cause visual artifacts."),
		B("M2UseThreads", "Multithread model animations"),
		B("M2UseInstancing", "Hardware instancing"),
		B("sceneOcclusionEnable", "Software occlusion culling"),
		B("vrsValar", "Velocity/luma variable-rate shading", "Needs VRS Tier 2."),
		B("vrsValarAlwaysOn", "VRS even when not GPU bound"),
		R("ThreadPoolLimitHP", "High-priority job threads", 1, 32, 1, nil, RESTART),
		R("ThreadPoolLimitMP", "Mid-priority job threads", 1, 32, 1, nil, RESTART),
		R("ThreadPoolLimitLP", "Low-priority job threads", 1, 32, 1, nil, RESTART),
	},
	{
		-- Hidden names from WowB.exe that look like visual knobs. Rows only appear if the probe confirms they exist.
		key = "experimental", title = "Experimental (hidden)",
		R("skyNoiseStrength", "Sky noise strength", 0, 4, 0.05),
		R("cloudNoiseStrength", "Cloud noise strength", 0, 4, 0.05),
		R("cameraFarFade", "Camera far fade", 0, 4000, 10),
		R("farBlurAmount", "Far blur amount", 0, 4, 0.05),
		R("windMagnitude", "Wind magnitude", 0, 10, 0.1),
		R("windFactor", "Wind factor", 0, 10, 0.1),
		R("maxLightCount", "Max light count", 0, 512, 1),
		B("useLighting2", "Alternate lighting path"),
		B("showFog", "Show fog (debug)"),
		B("showLighting", "Show lighting (debug)"),
		B("showGlobalVolumetricFog", "Global volumetric fog (debug)"),
		R("overrideMinLod", "Override minimum LOD", 0, 4, 1),
	},
}
