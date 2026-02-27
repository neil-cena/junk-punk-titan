--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetPackConfig = require(Shared:WaitForChild("AssetPackConfig"))

local assetpacksFolder = script.Parent
local defaultPackModule = assetpacksFolder:WaitForChild("DefaultPack")
local defaultPack = require(defaultPackModule)

local warnedKeys: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warnedKeys[key] then
		return
	end
	warnedKeys[key] = true
	warn(message)
end

local function getPackModule(packName: string): ModuleScript
	local exact = assetpacksFolder:FindFirstChild(packName)
	if exact ~= nil and exact:IsA("ModuleScript") then
		return exact
	end

	local suffixed = assetpacksFolder:FindFirstChild(packName .. "Pack")
	if suffixed ~= nil and suffixed:IsA("ModuleScript") then
		return suffixed
	end

	return defaultPackModule
end

local function deepMerge(defaultValue: any, overrideValue: any, path: string): any
	if type(defaultValue) ~= "table" then
		if overrideValue == nil then
			return defaultValue
		end
		return overrideValue
	end

	if type(overrideValue) ~= "table" then
		if overrideValue ~= nil then
			warnOnce(path, ("[AssetPack] Expected table at '%s'; falling back to Default."):format(path))
		end
		overrideValue = {}
	end

	local merged: { [any]: any } = {}
	for key, defaultChild in defaultValue do
		local nextPath = ("%s.%s"):format(path, tostring(key))
		merged[key] = deepMerge(defaultChild, (overrideValue :: { [any]: any })[key], nextPath)
	end

	for key, overrideChild in overrideValue do
		if merged[key] == nil then
			merged[key] = overrideChild
		end
	end

	return merged
end

local function resolvePack(): ({ [any]: any }, string)
	local configured = tostring(AssetPackConfig.ActivePack or "Default")
	local module = getPackModule(configured)
	local ok, loaded = pcall(require, module)
	if not ok or type(loaded) ~= "table" then
		warnOnce("load_failed_" .. configured, ("[AssetPack] Failed to load '%s'; using DefaultPack."):format(configured))
		return defaultPack, "Default"
	end

	if module == defaultPackModule and configured ~= "Default" then
		warnOnce("missing_pack_" .. configured, ("[AssetPack] Pack '%s' not found; using DefaultPack."):format(configured))
	end

	return loaded :: { [any]: any }, configured
end

local function strictOrWarn(condition: boolean, key: string, message: string)
	if condition then
		return
	end
	if AssetPackConfig.Strict then
		error(message)
	end
	warnOnce(key, message)
end

local function resolveSection(sectionName: string): any
	local activePack, packName = resolvePack()
	local section = activePack[sectionName]
	local defaultSection = defaultPack[sectionName]

	strictOrWarn(
		defaultSection ~= nil,
		"missing_default_" .. sectionName,
		("[AssetPack] DefaultPack is missing required section '%s'."):format(sectionName)
	)

	if defaultSection == nil then
		return section
	end

	if section == nil then
		strictOrWarn(
			false,
			("missing_%s_%s"):format(packName, sectionName),
			("[AssetPack] Pack '%s' missing section '%s'; using DefaultPack section."):format(packName, sectionName)
		)
		section = {}
	end

	return deepMerge(defaultSection, section, sectionName)
end

local AssetPackResolver = {}

function AssetPackResolver.GetVisualManifest(): { [any]: any }
	return resolveSection("VisualManifest")
end

function AssetPackResolver.GetAudioManifest(): { [any]: any }
	return resolveSection("AudioManifest")
end

function AssetPackResolver.GetAnimations(): { [any]: any }
	return resolveSection("Animations")
end

function AssetPackResolver.GetActivePackName(): string
	return tostring(AssetPackConfig.ActivePack or "Default")
end

return AssetPackResolver
