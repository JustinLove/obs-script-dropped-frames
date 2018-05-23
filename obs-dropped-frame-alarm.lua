local obs = obslua
local bit = require("bit")

local ffi = require("ffi")

ffi.cdef[[

struct video_output;
typedef struct video_output video_t;

uint32_t video_output_get_skipped_frames(const video_t *video);
uint32_t video_output_get_total_frames(const video_t *video);
video_t *obs_get_video(void);

]]

--local obsffi = ffi.load("obs.0.dylib") -- OS X
local obsffi = ffi.load("obs") -- Windows
-- Linux?

local function script_log(message) -- luacheck: no unused args
	-- "unreachable code"
	-- luacheck: push ignore
	if false then
		obs.script_log(obs.LOG_INFO, message)
	end
	-- luacheck: pop
end

local sample_rate = 1000
local graph_width = 600
local graph_height = 200
local graph_margin = 0

local mode = "live"
local output_mode = "simple_stream"
local sample_seconds = 60
local lagged_frame_alarm_level = 0.2
local skipped_frame_alarm_level = 0.2
local dropped_frame_alarm_level = 0.2
local alarm_source = ""
local alarm_repeat = 60

local frame_history = {}
local alarm_active = false
local has_hooked_output = false

local fake_frames = 0
local fake_lagged = 0
local fake_skipped = 0
local fake_dropped = 0

local function hide_all_alarms()
	local names = obs.obs_frontend_get_scene_names()
	for _,name in ipairs(names) do
		local source = obs.obs_get_source_by_name(name)
		local scene = obs.obs_scene_from_source(source)
		if scene ~= nil then
			local item = obs.obs_scene_find_source(scene, alarm_source)
			if item ~= nil then
				obs.obs_sceneitem_set_visible(item, false)
			end
		end
		obs.obs_source_release(source)
	end
end

local function output_stop(calldata) -- luacheck: no unused args
	hide_all_alarms()
end

local function hook_output()
	local output = obs.obs_get_output_by_name(output_mode)
	if output ~= nil then
		local handler = obs.obs_output_get_signal_handler(output)
		if handler ~= nil then
			has_hooked_output = true
			obs.signal_handler_connect(handler, "stop", output_stop)
		end
		obs.obs_output_release(output)
	end
end

local function unhook_output()
	local output = obs.obs_get_output_by_name(output_mode)
	if output ~= nil then
		local handler = obs.obs_output_get_signal_handler(output)
		if handler ~= nil then
			obs.signal_handler_disconnect(handler, "stop", output_stop)
		end
		obs.obs_output_release(output)
	end
end

local function set_alarm_visible(visible)
	if alarm_source ~= nil then
		local current_source = obs.obs_frontend_get_current_scene()
		local current_scene = obs.obs_scene_from_source(current_source)
		local item = obs.obs_scene_find_source(current_scene, alarm_source)
		if item ~= nil then
			obs.obs_sceneitem_set_visible(item, visible)
		end
		obs.obs_source_release(current_source)
	end
end

local function activate_alarm()
	script_log("alarm")
	set_alarm_visible(true)
	obs.timer_remove(activate_alarm)
end

local function play_alarm()
	set_alarm_visible(false)
	obs.timer_add(activate_alarm, 500)
end

local function check_alarm()
	if #frame_history < 2 then
		return
	end
	local newest = frame_history[1]
	local oldest = frame_history[#frame_history]
	local render_frames = newest.render_frames - oldest.render_frames
	local render_lagged = newest.render_lagged - oldest.render_lagged
	local encoder_frames = newest.encoder_frames - oldest.encoder_frames
	local encoder_skipped = newest.encoder_skipped - oldest.encoder_skipped
	local output_frames = newest.output_frames - oldest.output_frames
	local output_dropped = newest.output_dropped - oldest.output_dropped
	local render_rate = 0
	if render_frames > 0 then
		render_rate = render_lagged/render_frames
	end
	local encoder_rate = 0
	if encoder_frames > 0 then
		encoder_rate = encoder_skipped/encoder_frames
	end
	local output_rate = 0
	if output_frames > 0 then
		output_rate = output_dropped/output_frames
	end
	--script_log(render_lagged .. "/" .. render_frames .. " " .. render_rate .. " : " .. lagged_frame_alarm_level)
	--script_log(encoder_skipped .. "/" .. encoder_frames .. " " .. encoder_rate .. " : " .. skipped_frame_alarm_level)
	--script_log(output_dropped .. "/" .. output_frames .. " " .. output_rate .. " : " .. dropped_frame_alarm_level)
	if render_rate > lagged_frame_alarm_level
		or encoder_rate > skipped_frame_alarm_level
		or output_rate > dropped_frame_alarm_level then
		if not alarm_active then
			play_alarm()
			alarm_active = true
			obs.timer_add(play_alarm, alarm_repeat*1000)
		end
	else
		if alarm_active then
			alarm_active = false
			obs.timer_remove(play_alarm)
		end
	end
end

local function update_frames()
	-- luacheck bug?
	-- luacheck: push no unused
	local render_frames = 0
	local render_lagged = 0
	-- luacheck: pop

	local encoder_frames = 0
	local encoder_skipped = 0

	local output_frames = 0
	local output_dropped = 0
	local output_congestion = 0.0

	if mode == "test" then
		fake_frames = fake_frames + math.random(19,21)

		render_frames = fake_frames
		fake_lagged = fake_lagged + math.random(0, 20)
		render_lagged = fake_lagged

		encoder_frames = fake_frames
		fake_skipped = fake_skipped + math.random(0, 20)
		encoder_skipped = fake_skipped

		output_frames = fake_frames
		fake_dropped = fake_dropped + math.random(0, 20)
		output_dropped = fake_dropped
		output_congestion = math.random()
	else
		render_frames = obs.obs_get_total_frames()
		render_lagged = obs.obs_get_lagged_frames()

		if obsffi ~= nil then
			local video = obsffi.obs_get_video()
			if video ~= nil then
				encoder_frames = obsffi.video_output_get_total_frames(video)
				encoder_skipped = obsffi.video_output_get_skipped_frames(video)
			end
		end

		local output = obs.obs_get_output_by_name(output_mode)
		-- output will be nil when not actually streaming
		if output ~= nil then
			output_frames = obs.obs_output_get_total_frames(output)
			output_dropped = obs.obs_output_get_frames_dropped(output)
			output_congestion = obs.obs_output_get_congestion(output)
			obs.obs_output_release(output)

			if has_hooked_output == false then
				hook_output()
			end
		end
	end

	--script_log("render" .. render_lagged .. "/" .. render_frames)
	--script_log("encoder" .. encoder_skipped .. "/" .. encoder_frames)
	--script_log("output" .. output_dropped .. "/" .. output_frames)

	table.insert(frame_history, 1,
		{
			render_frames = render_frames,
			render_lagged = render_lagged,
			encoder_frames = encoder_frames,
			encoder_skipped = encoder_skipped,
			output_frames = output_frames,
			output_dropped = output_dropped,
			output_congestion = output_congestion
		})

	local sample_size = (sample_seconds * 1000 / sample_rate) + 1
	-- + 1 so that we get n differences
	while #frame_history > sample_size do
		table.remove(frame_history)
	end

	check_alarm()
end

local function extract_series(table, attribute)
	local series = {}
	for i = 1,#table-1 do
		series[i] = table[i][attribute] - table[i+1][attribute]
	end
	return series
end

local function table_max(table)
	local best = table[1] or 0
	for _,v in ipairs(table) do
		best = math.max(best, v)
	end
	return best
end

local function test_alarm(props, p, set) -- luacheck: no unused args
	play_alarm()
	return true
end

-- A function named script_description returns the description shown to
-- the user
-- luacheck: push no max line length
local description = [[Play an alarm if you start losing frames due to rendering, encoding, or network output.

Add a media source for the alarm. A suitable sound file is provided with the script. Open Advanced Audio Properties for the source and change Audio Monitoring to Monitor Only (mute output).

Add a copy of the alarm source to every scene where you want to hear it.

A custom source is available for drawing a dropped frame graph in the sample period. It can be added to the source panel. You may want to hide it and use a windowed projector to view the graph yourself.

Source has settings for color of each layer - Rendering Lag (default purple), Encoding Lag (default orange), Dropped Frames (default yellow), and Congestion (default green).
]]
-- luacheck: pop
function script_description()
	return description
end

-- A function named script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
	script_log("props")

	local props = obs.obs_properties_create()

	local m = obs.obs_properties_add_list(props,
		"mode", "Mode", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	obs.obs_property_list_add_string(m, "Live", "live")
	obs.obs_property_list_add_string(m, "Test", "test")
	obs.obs_property_set_long_description(m,
		"Test generates fake frame counts.")

	local o = obs.obs_properties_add_list(props,
		"output_mode", "Output Mode", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	obs.obs_property_list_add_string(o, "Simple", "simple_stream")
	obs.obs_property_list_add_string(o, "Advanced", "adv_stream")
	obs.obs_property_set_long_description(o,
		"Must match the OBS streaming mode you are using.")

	local ss = obs.obs_properties_add_int(props,
		"sample_seconds", "Sample Seconds", 1, 300, 5)
	obs.obs_property_set_long_description(ss,
		"Period during which the alarm level is checked.")

	local lfal = obs.obs_properties_add_int(props,
		"lagged_frame_alarm_level", "Rendering: Lagged Frame Alarm Level", 0, 100, 5)
	obs.obs_property_set_long_description(lfal,
		"Percentage of frames missed due to rendering lag in sample period which should trigger the alarm.")

	local sfal = obs.obs_properties_add_int(props,
		"skipped_frame_alarm_level", "Encoding: Skipped Frame Alarm Level", 0, 100, 5)
	obs.obs_property_set_long_description(sfal,
		"Percentage of frames missed due to encoding lag in sample period which should trigger the alarm.")

	local dfal = obs.obs_properties_add_int(props,
		"dropped_frame_alarm_level", "Network: Dropped Frame Alarm Level", 0, 100, 5)
	obs.obs_property_set_long_description(dfal,
		"Percentage of frames missed due to output (network) errors in sample period which should trigger the alarm.")

	local p = obs.obs_properties_add_list(props,
		"alarm_source", "Alarm Media Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local sources = obs.obs_enum_sources()
	if sources ~= nil then
		for _, source in ipairs(sources) do
			local source_id = obs.obs_source_get_id(source)
			if source_id == "ffmpeg_source" then
				local name = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(p, name, name)
			end
		end
	end
	obs.source_list_release(sources)
	obs.obs_property_set_long_description(p,
		"See above for how to create an appropriate media source.")

	local rep = obs.obs_properties_add_int(props,
		"alarm_repeat", "Alarm Repeat Seconds", 0, 60*60, 5)
	obs.obs_property_set_long_description(rep,
		"Number of seconds before repeating alarm if condition remains true.")

	local ref = obs.obs_properties_add_button(props,
		"test_alarm", "Test Alarm", test_alarm)
	obs.obs_property_set_long_description(ref,
		"Test activating selected media sources")

	return props
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
	script_log("defaults")

	obs.obs_data_set_default_string(settings, "mode", "live")
	obs.obs_data_set_default_string(settings, "output_mode", "simple_stream")
	obs.obs_data_set_default_int(settings, "sample_seconds", 60)
	obs.obs_data_set_default_int(settings, "lagged_frame_alarm_level", 20)
	obs.obs_data_set_default_int(settings, "skipped_frame_alarm_level", 20)
	obs.obs_data_set_default_int(settings, "dropped_frame_alarm_level", 20)
	obs.obs_data_set_default_string(settings, "alarm_source", "")
	obs.obs_data_set_default_int(settings, "alarm_repeat", 60)
end

--
-- A function named script_update will be called when settings are changed
function script_update(settings)
	script_log("update")

	mode = obs.obs_data_get_string(settings, "mode")

	local new_output_mode = obs.obs_data_get_string(settings, "output_mode")
	if new_output_mode ~= output_mode then
		unhook_output()
		output_mode = new_output_mode
		hook_output()
	else
		output_mode = new_output_mode
	end

	sample_seconds = obs.obs_data_get_int(settings, "sample_seconds")
	lagged_frame_alarm_level = obs.obs_data_get_int(settings, "lagged_frame_alarm_level") / 100
	skipped_frame_alarm_level = obs.obs_data_get_int(settings, "skipped_frame_alarm_level") / 100
	dropped_frame_alarm_level = obs.obs_data_get_int(settings, "dropped_frame_alarm_level") / 100
	alarm_source = obs.obs_data_get_string(settings, "alarm_source")
	alarm_repeat = obs.obs_data_get_int(settings, "alarm_repeat")

	if alarm_active then
		obs.timer_remove(play_alarm)
		obs.timer_add(play_alarm, alarm_repeat*1000)
	end
end

-- a function named script_load will be called on startup
function script_load(settings) -- luacheck: no unused args
	script_log("load")
	obs.timer_add(update_frames, sample_rate)
	hook_output()
end

function script_unload()
	set_alarm_visible(false)
	-- these crash OBS
	--unhook_output()
	--hide_all_alarms()
	--obs.timer_remove(update_frames)
end

local source_def = {}
source_def.id = "lua_dropped_frame_graph_source"
source_def.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO, obs.OBS_SOURCE_CUSTOM_DRAW)

source_def.get_name = function()
	return "Dropped Frame Graph"
end

source_def.create = function(source, settings) -- luacheck: no unused args
	return {
		lagged_color = 0xcc5015bd,
		skipped_color = 0xcc027fe9,
		dropped_color = 0xcc00f8ca,
		congestion_color = 0xcc0f9b8a,
	}
end

source_def.destroy = function(data) -- luacheck: no unused args
end

source_def.get_defaults = function(settings)
	obs.obs_data_set_default_int(settings, "lagged_color", 0xcc5015bd)
	obs.obs_data_set_default_int(settings, "skipped_color", 0xcc027fe9)
	obs.obs_data_set_default_int(settings, "dropped_color", 0xcc00f8ca)
	obs.obs_data_set_default_int(settings, "congestion_color", 0xcc0f9b8a)
end

source_def.get_properties = function(data) -- luacheck: no unused args
	local props = obs.obs_properties_create()

	local lc = obs.obs_properties_add_color(props, "lagged_color", "Rendering Lagged Color")
	obs.obs_property_set_long_description(lc, "Graph Color for fraction of lagged frames due to rendering lag")

	local sc = obs.obs_properties_add_color(props, "skipped_color", "Encoder Skipped Color")
	obs.obs_property_set_long_description(sc, "Graph Color for fraction of skipped frames due to encoding lag")

	local dc = obs.obs_properties_add_color(props, "dropped_color", "Network Dropped Color")
	obs.obs_property_set_long_description(dc, "Graph Color for fraction of dropped frames due to output/network issues")

	local cc = obs.obs_properties_add_color(props, "congestion_color", "Network Congestion Color")
	obs.obs_property_set_long_description(cc, "Graph Color for congestion resported by network output")

	return props
end

source_def.update = function(data, settings)
	data.lagged_color = obs.obs_data_get_int(settings, "lagged_color")
	data.skipped_color = obs.obs_data_get_int(settings, "skipped_color")
	data.dropped_color = obs.obs_data_get_int(settings, "dropped_color")
	data.congestion_color = obs.obs_data_get_int(settings, "congestion_color")
end

local function area_chart(value, total, color, color_param, effect_solid)
	if bit.band(color, 0xff000000) == 0 then
		return
	end

	obs.gs_matrix_push()
	local frames = extract_series(frame_history, total)
	obs.gs_matrix_scale3f(1, 1/table_max(frames), 1)

	local values = extract_series(frame_history, value)

	obs.gs_render_start(true)

	for i,d in ipairs(values) do
		obs.gs_vertex2f(i-1, d)
		obs.gs_vertex2f(i-1, 0)
	end

	local vec = obs.vec4()
	obs.vec4_from_rgba(vec, color)
	obs.gs_effect_set_vec4(color_param, vec)
	while obs.gs_effect_loop(effect_solid, "Solid") do
		obs.gs_render_stop(obs.GS_TRISTRIP)
	end

	obs.gs_matrix_pop()
end


source_def.video_render = function(data, effect) -- luacheck: no unused args
	obs.gs_blend_state_push()
	obs.gs_reset_blend_state()

	local effect_solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
	local color_param = obs.gs_effect_get_param_by_name(effect_solid, "color");

	obs.gs_matrix_push()
	obs.gs_matrix_translate3f(graph_margin, graph_margin, 0)
	obs.gs_matrix_scale3f(graph_width - graph_margin*2, graph_height - graph_margin*2, 1)
	obs.gs_matrix_translate3f(0, 1, 0)
	obs.gs_matrix_scale3f(1, -1, 1)

	if #frame_history > 1 then
		obs.gs_matrix_push()
		obs.gs_matrix_translate3f(1, 0, 0)
		obs.gs_matrix_scale3f(-1, 1, 1)
		obs.gs_matrix_scale3f(1/(#frame_history-1), 1, 1)

		obs.gs_render_start(true)

		if bit.band(data.congestion_color, 0xff000000) ~= 0 then
			for i,h in ipairs(frame_history) do
				obs.gs_vertex2f(i-1, h.output_congestion)
				obs.gs_vertex2f(i-1, 0)
			end

			local color = obs.vec4()
			obs.vec4_from_rgba(color, data.congestion_color);
			obs.gs_effect_set_vec4(color_param, color);
			while obs.gs_effect_loop(effect_solid, "Solid") do
				obs.gs_render_stop(obs.GS_TRISTRIP)
			end
		end

		area_chart("output_dropped", "output_frames", data.dropped_color, color_param, effect_solid)
		area_chart("encoder_skipped", "encoder_frames", data.skipped_color, color_param, effect_solid)
		area_chart("render_lagged", "render_frames", data.lagged_color, color_param, effect_solid)

		obs.gs_matrix_pop()
	end

	obs.gs_matrix_pop()

	obs.gs_blend_state_pop()
end

source_def.get_width = function(data) -- luacheck: no unused args
	return graph_width
end

source_def.get_height = function(data) -- luacheck: no unused args
	return graph_height
end

obs.obs_register_source(source_def)
