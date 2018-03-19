obs = obslua

function script_log(message)
	obs.script_log(obs.LOG_INFO, message)
end

local sample_seconds = 60
local alarm_level = 20
local alarm_source = ""

function update_frames()
	local output = obs.obs_get_output_by_name("simple_stream")
	if output ~= nil then
		local frames = obs.obs_output_get_total_frames(output)
		local dropped = obs.obs_output_get_frames_dropped(output)
		obs.obs_output_release(output)
		script_log(dropped .. "/" .. frames)
	end
end

function sample_modified(props, p, settings)
	return false -- text controls refreshing properties reset focus on each character
end

function alarm_modified(props, p, settings)
	return false -- text controls refreshing properties reset focus on each character
end

function refresh(props, p, set)
	if alarm_source ~= nil then
		local current_source = obs.obs_frontend_get_current_scene()
		local current_scene = obs.obs_scene_from_source(current_source)
		local item = obs.obs_scene_find_source(current_scene, alarm_source)
		if item ~= nil then
			obs.obs_sceneitem_set_visible(item, true)
		end
	end
	return true
end

function dump_obs()
	local keys = {}
	for key,value in pairs(obs) do
		keys[#keys+1] = key
	end
	table.sort(keys)
	local output = {}
	for i,key in ipairs(keys) do
		local value = type(obs[key])
		if value == 'number' then
			value = obs[key]
		elseif value == 'string' then
			value = '"' .. obs[key] .. '"'
		end
		output[i] = key .. " : " .. value
	end
	script_log(table.concat(output, "\n"))
end

-- A function named script_description returns the description shown to
-- the user
local description = [[Play an alarm if you start dropping frames
]]
function script_description()
	return description
end

-- A function named script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
	script_log("props")

	local props = obs.obs_properties_create()

	local ss = obs.obs_properties_add_int(props, "sample_seconds", "Sample Seconds", 1, 300, 5) 
	obs.obs_property_set_modified_callback(ss, sample_modified)

	local al = obs.obs_properties_add_int(props, "alarm_level", "Alarm Level", 0, 100, 5)
	obs.obs_property_set_modified_callback(ss, level_modified)

	local p = obs.obs_properties_add_list(props, "alarm_source", "Alarm Media Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local sources = obs.obs_enum_sources()
	if sources ~= nil then
		for _, source in ipairs(sources) do
			source_id = obs.obs_source_get_id(source)
			if source_id == "ffmpeg_source" then
				local name = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(p, name, name)
			end
		end
	end
	obs.source_list_release(sources)

	local ref = obs.obs_properties_add_button(props, "refresh", "Refresh", refresh)
	obs.obs_property_set_long_description(ref, "Updated calculated fields with changes from text controls.")

	return props
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
	script_log("defaults")

	obs.obs_data_set_default_int(settings, "sample_seconds", 60)
	obs.obs_data_set_default_int(settings, "alarm_level", 20)
	obs.obs_data_set_default_string(settings, "alarm_source", "")
end

--
-- A function named script_update will be called when settings are changed
function script_update(settings)
	script_log("update")
	my_settings = settings

	sample_seconds = obs.obs_data_get_int(settings, "sample_seconds")
	alarm_level = obs.obs_data_get_int(settings, "alarm_level")
	alarm_source = obs.obs_data_get_string(settings, "alarm_source")
end

-- a function named script_load will be called on startup
function script_load(settings)
	script_log("load")
	--dump_obs()
	obs.timer_add(update_frames, 2000)
end

function script_unload()
	-- this crashes OBS
	--obs.timer_remove(update_frames)
end
