require "alyxlib.helpers.easyconvars"
require "alyxlib.controls.input"


-- We have 4 sounds - on/off, via button and auto.
-- When automatic it's much quieter.

---@class WeaponSounds
---@field auto_off string
---@field auto_on string
---@field btn_off string
---@field btn_on string

-- Turning on/off the hologram. 
---@type WeaponSounds
local SND_HOLO = {
	auto_off="TSpen.ToggleSight.HoloAutoOff",
	auto_on="TSpen.ToggleSight.HoloAutoOn",
	btn_off="TSpen.ToggleSight.HoloBtnOff",
	btn_on="TSpen.ToggleSight.HoloBtnOn",
};

-- "Detaching" and re-attaching a physical prop.
---@type WeaponSounds
local SND_ATTACH = {
	auto_off="TSpen.ToggleSight.AttachAutoOff",
	auto_on="TSpen.ToggleSight.AttachAutoOn",
	btn_off="TSpen.ToggleSight.AttachBtnOff",
	btn_on="TSpen.ToggleSight.AttachBtnOn",
}

-- Flipping down a part while turning on/off the hologram.
---@type WeaponSounds
local SND_FLIP = {
	auto_off="TSpen.ToggleSight.FlipAutoOff",
	auto_on="TSpen.ToggleSight.FlipAutoOn",
	btn_off="TSpen.ToggleSight.FlipBtnOff",
	btn_on="TSpen.ToggleSight.FlipBtnOn",
}

-- On default and most modded reflex_sights entities, where the screen is. 
-- Direction is inconsistent, many modded sights omit. All our replacements have
-- it though.
local ATTACH_REFLEX = "reticule_attach"

local CTX_ENABLED = "tspen_toggle_sight_enabled"
local REPLACE_PREFIX = "models/weapons/ts_togglesight/"
local CVAR_AUTO = "tspen_reflex_control_auto"
local DEBUG = false;

-- Definitions for each weapon. 
---@class WeaponInfo
---@field name string Debug name for the weapon.
---@field snd_pos Vector = Offset from child model to play sound from.
---@field sounds WeaponSounds The sounds to use.
---@field auto_range number Radius for auto-swapping.
---@field replace? string If set, auto-define replace_lhand/rhand.
---@field replace_lhand? string If set, full model path to replace for this hand.
---@field replace_rhand? string If set, full model path to replace for this hand.
---@field group? integer The bodygroup index to change, if set.
---@field on_state? integer States to use when turned on/off.
---@field off_state? integer
---@field disable_draw? boolean If set, hide when disabled.
---@field sight_pos_lhand? Vector The offset to the reflex sights, for auto mode. 
---       If unset, use the `reticule_attach` attachment point to locate.
---@field sight_pos_rhand? Vector The offset to the reflex sights, for auto mode. 
---       If unset, use the `reticule_attach` attachment point to locate.
-- Later set:
---@field auto_range_sqr? number Pre-squared radius.
---@field replaced boolean? If the model has been replaced during this session.

---@type table<string, WeaponInfo>
local weapons = {
	-- Doesn't seem to be any SMG mods, we can unconditionally do this one.
	hlvr_weapon_rapidfire={
		name="RapidFire",
		-- This bodygroup already exists by default.
		model="holosight",
		group=0,
		on_state=0,
		off_state=1,
		auto_range=2.5,
		sounds=SND_HOLO,
		snd_pos=Vector(0, -1.0, 4.0),
	}
};

-- Name + sight offsets, when inheriting.
---@class SightInfo
---@field name string Debug name for the weapon.
---@field pos_lhand? Vector
---@field pos_rhand? Vector

-- Wrap so we can discard all this data once evaulated. Mods can't change
-- within any given session.
(function ()

-- Pistols which have a physical sight with the view inside it.
-- To toggle those would logically need to be added/removed.
---@type table<string, SightInfo>
local phys_sight = {
	["2971436118"] = {name="Desert Eagle"},
	["2804426219"] = {name="Apex Legends Pistol"},
	["2503412081"] = {
		name="OTS-14 Groza",
		pos_lhand=Vector(0.4, 0, 8.35),
		pos_rhand=Vector(0.4, 0, 8.35),
	},
	["2386620896"] = {
		name="Fallout 4 Pistol",
		pos_lhand=Vector(-0.7, -0.03, 4.35),
		pos_rhand=Vector(-0.7, 0.03, 4.35),
	},
	["2281728283"] = {
		name="COD 50 GS",
		pos_lhand=Vector(5.8, 0, 3.8),
		pos_rhand=Vector(5.8, 0, 3.8),
	},
	["2353427612"] = {name="Modern Warfare Renetti"},
	["2406708838"] = {
		name="DL-44 Blaster",
		pos_lhand=Vector(-5.4, 14.5, 2.3),
		pos_rhand=Vector(-5.4, -14.5, 2.3),
	},
};

-- Pistols that don't have their own attachments, just use the default sight model.
-- No custom sight offsets necessary, the default model has the attachment.
local default_sight = {
	["2778816428"] = "Gunman Pistol",
	["2595135995"] = "Cyberpunk liberty",
	["2290585929"] = "CSGO Five-SeveN",
	["2282845209"] = "Goldeneye PP7",
	["2263486326"] = "Boneworks M1911",
	["2258990046"] = "Silenced Pistol",
	["2248623741"] = "AJM-9",
	["2243234414"] = "MMod Pistol",
}

-- Sight is composed only of the holo part, so we can disable-draw to hide.
---@type table<string, SightInfo>
local invis_sight = {
	["2352925224"] = {
		name="Deus Ex HR Zenith",
		pos_lhand=Vector(5, 0, 4),
		pos_rhand=Vector(5, 0, 4),
	},
	["2291028898"] = {name="Doom EMG Pistol"},
	["2251436253"] = {name="TF2 Pistol"}, -- Uses default model.
}

-- Config for standard Alyxgun.
--- @type WeaponInfo
local standard_pistol = {
	name="Alyxgun",
	group=1,
	on_state=1,
	off_state=0,
	auto_range=2,
	snd_pos=Vector(0, 2.6875, 2.825),
	sounds=SND_HOLO,
	replace="alyxgun",
};

for addon in Convars:GetStr("default_enabled_addons_list"):gmatch("[^,]+") do
	if addon == "2482808860" then
		print("togglesight: Shooter Pistol mod detected, toggling sights.")
		weapons.hlvr_weapon_energygun = {
			name="Shooter Pistol",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=2,
			snd_pos=Vector(0, 2.6875, 4.0),
			sounds=SND_HOLO,
			replace="shooterpistol",
		};
		return;
	end

	if addon == "2122819116" then
		print("togglesight: Luger P08 mod detected, toggling sights.")
		weapons.hlvr_weapon_energygun = {
			name="Luger P08",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=2,
			snd_pos=Vector(4.7, 0, 4.0),
			sounds=SND_ATTACH,
			-- Both are identical.
			replace_lhand=REPLACE_PREFIX .. "luger_ambi.vmdl",
			replace_rhand=REPLACE_PREFIX .. "luger_ambi.vmdl",
		};
		return;
	end

	-- These two are both made by MCMessenger, and share a sight.
	if addon == "2126368719" then
		print("togglesight: Halo M6C mod detected, toggling sights.")
		weapons.hlvr_weapon_energygun = {
			name="Halo M6C",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=2,
			snd_pos=Vector(4.8, 0, 4.0),
			sounds=SND_FLIP,
			replace="mcmessenger"
		};
		return;
	end
	if addon == "2168778468" then
		print("togglesight: Walther PPK mod detected, toggling sights.")
		weapons.hlvr_weapon_energygun = {
			name="Walther PPK",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=2,
			snd_pos=Vector(4.8, 0, 4.0),
			sounds=SND_FLIP,
			replace="mcmessenger"
		};
		return;
	end

	if default_sight[addon] ~= nil then
		-- Just uses the regular one, copy the config.
		print("togglesight: " .. default_sight[addon] .. " detected, uses standard sights.")
		standard_pistol.name = default_sight[addon];
		weapons.hlvr_weapon_energygun = standard_pistol;
		return;
	end

	local sight = phys_sight[addon]
	if sight ~= nil then
		-- It's not disableable, it'll be "removed" when not used.
		print("togglesight: " .. sight.name .. " detected, hiding/showing physical sight.")
		weapons.hlvr_weapon_energygun = {
			name=sight.name,
			disable_draw=true,
			auto_range=2,
			sounds=SND_ATTACH,
			sight_pos_lhand=sight.pos_lhand,
			sight_pos_rhand=sight.pos_rhand,
			snd_pos=Vector(0, 0, 0),
		};
		return;
	end

	sight = invis_sight[addon]
	if sight ~= nil then
		print("togglesight: " .. sight.name .. " detected, hiding/showing holo sight.")
		weapons.hlvr_weapon_energygun = {
			name=sight.name,
			disable_draw=true,
			auto_range=2,
			sounds=SND_HOLO,
			sight_pos_lhand=sight.pos_lhand,
			sight_pos_rhand=sight.pos_rhand,
			snd_pos=Vector(0, 0, 0),
		};
		return;
	end
end
print("togglesight: No known pistol mods detected.")
weapons.hlvr_weapon_energygun = standard_pistol;

end)()


for _,info in pairs(weapons) do
	-- Allow specifying replace lhand/rhand standalone, for ambidexterous etc
	-- sights.
	info.auto_range_sqr = info.auto_range * info.auto_range;
	if info.replace or info.replace_lhand or info.replace_rhand then
		if not info.replace_lhand then
			info.replace_lhand = REPLACE_PREFIX .. info.replace .. "_lhand.vmdl"
		end
		if not info.replace_rhand then
			info.replace_rhand = REPLACE_PREFIX .. info.replace .. "_rhand.vmdl"
		end
		GlobalPrecache("model", info.replace_lhand);
		GlobalPrecache("model", info.replace_rhand);
		GlobalPrecache("sound", info.sounds.auto_off)
		GlobalPrecache("sound", info.sounds.auto_on)
		GlobalPrecache("sound", info.sounds.btn_off)
		GlobalPrecache("sound", info.sounds.btn_on)
	end
end

---@param x boolean
local function identity(x) return x end
---@param x boolean
local function toggle(x) return not x end

-- Turn on Alyxlib's button tracking
Input.AutoStart = true

-- Find the sight entity, then update its state.
---@param gun CBaseAnimating
---@param info WeaponInfo
---@param state_func fun(old: boolean, info: WeaponInfo, sights: CBaseAnimating): boolean
local function UpdateSight(gun, info, state_func)
	-- @type CBaseAnimating
	local child = gun:FirstMoveChild() --[[@as CBaseAnimating]]
	while child do
		if child:GetClassname() == "reflex_sights" then
			-- Found, toggle if required.
			local prev_enabled = Storage.LoadBoolean(gun, CTX_ENABLED, true)
			local enabled = state_func(prev_enabled, info, child)
			if enabled ~= prev_enabled then
				Storage.SaveBoolean(gun, CTX_ENABLED, enabled)
				-- local pos = RotatePosition(child:GetAbsOrigin(), child:GetAngles(), info.snd_pos);
				-- print("Snd pos: " .. tostring(pos - gun:GetOrigin()))
				if EasyConvars:GetBool(CVAR_AUTO) then
					gun:EmitSound(vlua.select(enabled, info.sounds.auto_on, info.sounds.auto_off));
				else
					gun:EmitSound(vlua.select(enabled, info.sounds.btn_on, info.sounds.btn_off));
				end
			end
			local replace = vlua.select(Player.IsLeftHanded, info.replace_lhand, info.replace_rhand);
			if replace then
				local mdl = child:GetModelName();
				-- After a reload the model gets set to null, we need to always set the first time.
				if mdl ~= replace or not info.replaced then
					print(string.format("Togglesight: Override model \"%s\" -> \"%s\"", mdl, replace));
					-- Save/restore the skin, for the Shooter Pistol. Harmless otherwise.
					local prev_skin = child:GetMaterialGroupHash();
					child:SetModel(replace);
					child:SetMaterialGroupHash(prev_skin);
					info.replaced = true;
				end
			end
			if info.disable_draw then
				local alpha = vlua.select(enabled, 255, 0)
				--print(string.format("Set sight for %s, alpha=%i", info.name, alpha))
				child:SetRenderAlpha(alpha);
			end
			if info.group ~= nil then
				local state = vlua.select(enabled, info.on_state, info.off_state);
				--print(string.format("Set sight for %s, body %i = %i", info.name, info.group, state));
				child:SetBodygroup(info.group, state)
			end
		end
		child = child:NextMovePeer()
	end
end

-- Update the held weapon.
---@param state_func fun(old: boolean, info: WeaponInfo, sights: CBaseAnimating): boolean
local function UpdateHeldSight(state_func)
	local gun = Player:GetWeapon() --[[@as CBaseAnimating]]
	if gun == nil then
		return
	end
	local info = weapons[gun:GetClassname()]
	if info ~= nil then
		UpdateSight(gun, info, state_func);
	end
end

-- Calculate whether the eye is close to the sights.
---@param old_state boolean
---@param info WeaponInfo
---@param sights CBaseAnimating
---@returns boolean
local function IsEyeClose(old_state, info, sights)


	-- Location of the reflex sight screen, in world.
	local reflex_pos;
	local reflex_off = vlua.select(Player.IsLeftHanded, info.sight_pos_lhand, info.sight_pos_rhand);
	if reflex_off == nil then
		-- Try and grab from the attachment point.
		local attach_ind = sights:ScriptLookupAttachment(ATTACH_REFLEX);
		reflex_pos = sights:GetAttachmentOrigin(attach_ind);
		reflex_off = sights:TransformPointWorldToEntity(reflex_pos);
		if reflex_off:LengthSquared() < 0.1 then
			-- It's right at the origin, probably not valid.
			print("togglesight: ERROR, no sight position for gun " .. info.name .. "!");
			-- Roughly where most sights are.
			reflex_off = Vector(4, 0, 4);
			reflex_pos = sights:TransformPointEntityToWorld(reflex_off);
		end
		if Player.IsLeftHanded then
			info.sight_pos_lhand = reflex_off;
		else
			info.sight_pos_rhand = reflex_off;
		end
		print("Offset for gun " .. info.name .. " = " .. tostring(reflex_off));
	else
		reflex_pos = sights:TransformPointEntityToWorld(reflex_off);
	end
	-- Simple check, if looking backwards at the gun, always disable.
	if sights:GetForwardVector():Dot(Player.HMDAvatar:GetForwardVector()) < 0 then
		return false
	end

	-- Distance between eyes, seems to be in cm. 6.285 is about the average IPD.
	local eye_dist = (Convars:GetFloat("r_stereo_eye_separation") or 6.285) / 2.54;

	-- Offset from player eye center to reflex
	local eye_off = Player:EyePosition() - reflex_pos;
	-- Local camera right.
	local player_right = Player.HMDAvatar:GetRightVector();
	-- Left/right eye offset
	local eye_left = eye_off + (player_right * -eye_dist);
	local eye_right = eye_off + (player_right * eye_dist);

	-- Local axes.
	local sight_up = sights:GetUpVector();
	local sight_right = sights:GetRightVector();
	-- Finally, calc 2D distance in sight plane = check if eye is within cylinder
	-- extending out of the sights.
	local dist_left = eye_left:Dot(sight_up)^2 + eye_left:Dot(sight_right)^2;
	local dist_right = eye_right:Dot(sight_up)^2 + eye_right:Dot(sight_right)^2;

	-- Increase by the eye distance, to get a cone.
	local range = info.auto_range;
	if old_state then
		-- Add some hysteresis - if in range, need to pull further out to detach.
		range = range + 2;
	end

	if DEBUG then
		local sight_back = reflex_pos + sights:GetForwardVector() * -32.0;
		DebugDrawSphere(reflex_pos, Vector(255, 0, 255), 32, range, false, 0.1);
		-- Aligned edges to show the cylinder.
		DebugDrawLine(reflex_pos + sight_up * range, sight_back + sight_up * range, 255, 255, 0, false, 0.1);
		DebugDrawLine(reflex_pos - sight_up * range, sight_back - sight_up * range, 255, 255, 0, false, 0.1);
		DebugDrawLine(reflex_pos + sight_right * range, sight_back + sight_right * range, 255, 255, 0, false, 0.1);
		DebugDrawLine(reflex_pos - sight_right * range, sight_back - sight_right * range, 255, 255, 0, false, 0.1);
	end
	range = range * range;
	return dist_left < range or dist_right < range;
end

local EVT_BUTTON_CTX = "tspen_toggle_sight";

local function AutoThink()
	if not EasyConvars:GetBool(CVAR_AUTO) then
		return; -- Non-auto, stop thinking.
	end
	-- Automatically toggle.
	if not Player:HasWeaponEquipped() then
		return 0.25; -- Wait for a weapon.
	end
	UpdateHeldSight(IsEyeClose);
	return 0.05;
end

local function SetupCallbacks(auto)
	-- Avoid double-registering.
	Input:StopListeningByContext(EVT_BUTTON_CTX);

	if auto then
		-- Auto mode.
		Player:SetContextThink("TSpen_ToggleSight_AutoThink", AutoThink, 0.0);
	else
		-- Button mode.
		Input:ListenToButton(
			"press", -1, DIGITAL_INPUT_TOGGLE_LASER_SIGHT, 1,
			function() UpdateHeldSight(toggle) end,
			EVT_BUTTON_CTX
		);
	end
end

EasyConvars:RegisterToggle(
	CVAR_AUTO, true,
	"If set the sight will enable automatically when aligned with the eye. " ..
	"Otherwise, the Toggle Laser Sight button will be used.",
	nil, function(value)
		SetupCallbacks(truthy(value))
	end
);
EasyConvars:SetPersistent(CVAR_AUTO, true);

local function Init()
	Input:TrackButton(DIGITAL_INPUT_TOGGLE_LASER_SIGHT);
	SetupCallbacks(EasyConvars:GetBool(CVAR_AUTO));
	-- Look for already-equipped weapons, toggle them in case we loaded from save.
	local hand_pos = Player.PrimaryHand:GetAbsOrigin();
	for info_cls, info in pairs(weapons) do
		local gun = Entities:FindByClassnameNearest(info_cls, hand_pos, 128) --[[@as CBaseAnimating?]]
		if gun ~= nil then
			UpdateSight(gun, info, identity)
		end
	end
	print("TS Toggle Reflex Sights active.")
end
ListenToPlayerEvent("vr_player_ready", Init);

-- Whenever weapons are switched or the hand swaps, update in case they got out of sync.
ListenToPlayerEvent("weapon_switch", function() UpdateHeldSight(identity) end)
ListenToPlayerEvent("primary_hand_changed", function() UpdateHeldSight(identity) end)
