-- 1dCA: one-dimensional cellular automata

-- EDIT THIS!
max_brightness = 10

local grid_size = grid_size_x() * grid_size_y()
local start_time = get_time()
local dirty = true
local intro_metro = 1
local intro_level = 10
local intro_duration = 10
local intro_complete = false
local redraw_metro = 2
local snapshots_saver_metro = 3
local main_metro = 4

local number_of_voices = grid_size == 128 and 8 or 16
local transport_running = false

local neighborhoods = {
	{ 1, 1, 1 },
	{ 1, 1, 0 },
	{ 1, 0, 1 },
	{ 1, 0, 0 },
	{ 0, 1, 1 },
	{ 0, 1, 0 },
	{ 0, 0, 1 },
	{ 0, 0, 0 },
}

-- EDIT THIS!
-- a table to track our note values:
notes = {}
for i = 1, number_of_voices do
	notes[i] = { 60, 62, 64, 67, 72, 77 }
end

-- BINARY OPS //
function number_to_binary(n)
	local binary_translate = {}
	for i = 0, 7 do
		table.insert(binary_translate, (n & (2 ^ i)) >> i)
	end
	return binary_translate
end

function binary_to_number(t)
	local number_translate = ""
	for i = #t, 1, -1 do
		number_translate = number_translate .. t[i]
	end
	return tonumber(number_translate, 2)
end

-- translate the seed integer to binary
local function seed_to_binary(v)
	return number_to_binary(voice[v].seed)
end

-- translate the rule integer to binary
local function rule_to_binary(v)
	return number_to_binary(voice[v].rule)
end
-- // BINARY OPS

voice = {}
local display_voice = {}
for i = 1, number_of_voices do
	voice[i] = {}
	voice[i].muted = false
	voice[i].bit = 1
	voice[i].octave = 0
	voice[i].active_notes = {}
	voice[i].ch = i
	voice[i].vel = 64
	voice[i].seed = 36+i
	voice[i].seed_as_binary = {}
	voice[i].next_seed = voice[i].seed
	voice[i].originating_seed = voice[i].seed
	voice[i].rule = 30
	voice[i].rule_as_binary = rule_to_binary(i)
	voice[i].scale_low = 1
	voice[i].scale_high = #notes[i]
	voice[i].semi = 0
	voice[i].ppqn_div = 4
	display_voice[i] = false
end

ppqn = {}
local ppqn_counter = {}
for i = 1, number_of_voices do
	ppqn[i] = 96 / voice[i].ppqn_div
	ppqn_counter[i] = 1
end

local random_gate = {}
for i = 1, number_of_voices do
	random_gate[i] = {}
	random_gate[i].comparator = 99
	random_gate[i].probability = 100
end

local random_note = {}
for i = 1, number_of_voices do
	random_note[i] = {}
	random_note[i].tran = 0
	random_note[i].down = 0
	random_note[i].comparator = 99
	random_note[i].probability = 100
	random_note[i].add = 0
end

-- SNAPSHOTS //
-- a table to track our snapshots:
local snapshots = {}
for i = 1, 15 do
	snapshots[i] = {}
	snapshots[i].data = {}
end

function toggle_mute(i)
	voice[i].muted = not voice[i].muted
end


local snapshot_params = {
	"bit",
	"octave",
	"rule",
	"rule_as_binary",
	"seed",
	"seed_as_binary",
	"originating_seed",
	"semi",
	"scale_low",
	"scale_high",
	"vel",
	"ch",
	"ppqn_div",
	"muted"
}

function snapshot_pack(slot)
	for i = 1, number_of_voices do
		snapshots[slot].data[i] = {}
		for _,v in pairs(snapshot_params) do
			snapshots[slot].data[i][v] = voice[i][v]
		end
	end
end

function snapshot_unpack(slot, jump)
	for i = 1, number_of_voices do
		for _, v in pairs(snapshot_params) do
			voice[i][v] = snapshots[slot].data[i][v]
		end
		voice[i].rule_as_binary = rule_to_binary(i)
		voice[i].seed = voice[i].originating_seed
		change_ppqn_div(i, snapshots[slot].data[i].ppqn_div)
		bang(i)
	end
end

function snapshot_save(slot)
	if not _alt then
		snapshot_pack(slot)
		snapshots.focus = slot
	else
		snapshot_clear(slot)
	end
	dirty = true
end

function snapshot_clear(slot)
	snapshots[slot].data = {}
	dirty = true
end

function snapshot_press(x,y,z)
	if z == 1 then
		if #snapshots[y].data == 0 then
			if snapshot_being_saved == nil then
				snapshot_being_saved = y
				metro_set(snapshots_saver_metro, 250, 1)
			end
		elseif not _alt then
			if snapshots.focus == y then
				snapshot_unpack(y, true)
			else
				snapshots.focus = y
				snapshot_unpack(y, false)
			end
		else
			if snapshot_being_saved == nil then
				snapshot_being_saved = y
				metro_set(snapshots_saver_metro, 250, 1)
			end
		end
	else
		if snapshot_being_saved ~= nil then
			metro_stop(snapshots_saver_metro)
			snapshot_being_saved = nil
		end
	end
end
-- // SNAPSHOTS

-- GRID //
-- GRID KEY HANDLING:
function grid(x, y, z)
	-- SNAPSHOT MANAGEMENT:
	if x == 16 and y <= (grid_size == 128 and 6 or 14) then
		snapshot_press(x,y,z)
	-- BITS:
	elseif x <= 8 and y <= number_of_voices and z == 1 then
		-- CHANGE RULE:
		if _rule then
			voice[y].rule_as_binary[9 - x] = voice[y].rule_as_binary[9 - x] == 1 and 0 or 1
			change_rule(y, binary_to_number(voice[y].rule_as_binary))
		-- CHANGE BIT:
		elseif _seed then
			local originating_seed_as_binary = number_to_binary(voice[y].originating_seed)
			originating_seed_as_binary[9 - x] = originating_seed_as_binary[9 - x] == 1 and 0 or 1
			change_seed(y, binary_to_number(originating_seed_as_binary))
		elseif _ppqn then
			change_ppqn_div(y, x)
		else
			voice[y].bit = 9 - x
		end
	elseif x == 10 and y <= number_of_voices and z == 1 and _alt then
		toggle_mute(y)
	-- _ppqn KEY:
	elseif x == 12 and y == (grid_size == 128 and 8 or 16) then
		_ppqn = z == 1
	-- _rule KEY:
	elseif x == 14 and y == (grid_size == 128 and 8 or 16) then
		_rule = z == 1
	-- _seed KEY:
	elseif x == 15 and y == (grid_size == 128 and 8 or 16) then
		_seed = z == 1
	-- _alt KEY:
	elseif x == 16 and y == (grid_size == 128 and 8 or 16) then
		_alt = z == 1
	end

	dirty = true
end

-- GRID REDRAWS:
function draw_intro()
	grid_led_all(0)
	for i = 4, 6 do
		grid_led(i + 1, 3, intro_level)
		grid_led(i + 1, 6, intro_level)
		grid_led(5, i, intro_level)
		grid_led(i + 6, 3, intro_level)
		grid_led(i + 6, 6, intro_level)
		grid_led(10, i, intro_level)
	end
	intro_level = wrap(intro_level - 1, 1, 10)
	grid_refresh()
end

function redraw_grid()
	-- clear LEDs:
	grid_led_all(0)

	-- snapshots:
	for y = 1, (grid_size == 128 and 7 or 15) do
		if #snapshots[y].data > 0 then
			local unselected = max_brightness > 12 and 8 or 5
			grid_led(16, y, snapshots.focus == y and max_brightness or unselected)
		end
	end

	-- voices:
	for i = 1, number_of_voices do
		-- RULE DISPLAY:
		if _rule then
			for j = 1, 8 do
				if voice[i].rule_as_binary[j] == 1 then
					grid_led(9 - j, i, 8)
				else
					grid_led(9 - j, i, 2)
				end
			end
		elseif _seed then
			local originating_seed_as_binary = number_to_binary(voice[i].originating_seed)
			for j = 1, 8 do
				if originating_seed_as_binary[j] == 1 then
					grid_led(9 - j, i, 8)
				else
					grid_led(9 - j, i, 2)
				end
			end
		elseif _ppqn then
			for j = 1, 8 do
				if voice[i].ppqn_div == j then
					grid_led(j, i, 8)
				else
					grid_led(j, i, 2)
				end
			end
		else
			-- binary stream:
			for j = 1, 8 do
				if voice[i].seed_as_binary[j] == 1 then
					grid_led(9 - j, i, voice[i].muted and 2 or 4)
				else
					grid_led(9 - j, i, voice[i].muted and 0 or 2)
				end
			end
			grid_led(9 - voice[i].bit, i, voice[i].muted and 4 or 9)
			if _alt then
				grid_led(10, i, voice[i].muted and 4 or 12)
			end
			if voice[i].seed_as_binary[voice[i].bit] == 1 and display_voice[i] then
				grid_led(9 - voice[i].bit, i, 15)
			end
		end
	end

	-- _ppqn:
	grid_led(12, grid_size == 128 and 8 or 16, _ppqn and max_brightness or 3)
	-- _rule:
	grid_led(14, grid_size == 128 and 8 or 16, _rule and max_brightness or 3)
	-- _seed:
	grid_led(15, grid_size == 128 and 8 or 16, _seed and max_brightness or 3)
	-- _alt:
	grid_led(16, grid_size == 128 and 8 or 16, _alt and max_brightness or 5)

	grid_refresh()
end
-- // GRID

-- CA logic //

-- basic compare function, used in bang()
local function compare(s, n)
	if type(s) == type(n) then
		if type(s) == "table" then
			for loop = 1, 3 do
				if compare(s[loop], n[loop]) == false then
					return false
				end
			end

			return true
		else
			return s == n
		end
	end
	return false
end

local function scale(lo, hi, received)
	scaled = math.floor(((received / 256) * (hi + 1 - lo) + lo))
end

local function transpose(semitone)
	semi = semitone
end

function bang(v)
	voice[v].seed_as_binary = seed_to_binary(v)
	local seed_pack = {}
	for i = 1, 8 do
		seed_pack[i] = {
			voice[v].seed_as_binary[wrap(10 - i, 1, 8)],
			voice[v].seed_as_binary[9 - i],
			voice[v].seed_as_binary[wrap(8 - i, 1, 8)],
		}
	end

	local function com(seed_packN, lshift, mask)
		local commute
		for i = 8, 1, -1 do
			if compare(seed_packN, neighborhoods[9 - i]) then
				commute = (voice[v].rule_as_binary[i] << lshift) & mask
			end
		end
		if commute == nil then
			commute = (0 << lshift) & mask
		end
		return commute
	end

	voice[v].next_seed = 0
	for i = 1, 8 do
		voice[v].next_seed = voice[v].next_seed + com(seed_pack[i], 8 - i, 2 ^ (8 - i))
	end
end

function notes_off(n)
	for i = 1, #voice[n].active_notes do
		midi_note_off(
			voice[n].active_notes[i],
			voice[n].vel,
			voice[n].ch
		)
		voice[n].active_notes = {}
	end
end

local function iterate(i)
	if ppqn_counter[i] > ppqn[i] then
		ppqn_counter[i] = 1
		notes_off(i)
		voice[i].seed = voice[i].next_seed
		bang(i)
		display_voice[i] = false
		if not voice[i].muted and voice[i].seed_as_binary[voice[i].bit] == 1 then
			random_gate[i].comparator = math.random(0, 100)
			if random_gate[i].comparator < random_gate[i].probability then
				scale(voice[i].scale_low, voice[i].scale_high, voice[i].seed)
				random_note[i].comparator = math.random(0, 100)
				display_voice[i] = true
				if random_note[i].comparator < random_note[i].probability then
					random_note[i].add = random_note[i].tran
				else
					random_note[i].add = 0
				end
				midi_note_on(
					notes[i][scaled] + (36 + (voice[i].octave * 12) + voice[i].semi + random_note[i].add),
					voice[i].vel,
					voice[i].ch
				)
				table.insert(
					voice[i].active_notes,
					notes[i][scaled] + (36 + (voice[i].octave * 12) + voice[i].semi + random_note[i].add)
				)
			end
		end
		dirty = true
	else
		ppqn_counter[i] = ppqn_counter[i] + 1
	end
end

function change_rule(i, r)
	voice[i].rule = r
	voice[i].seed = voice[i].originating_seed
	voice[i].rule_as_binary = rule_to_binary(i)
	bang(i)
end

function change_seed(i,s)
	voice[i].originating_seed = s
	voice[i].seed = s
	bang(i)
end

function change_ppqn_div(i, div)
	voice[i].ppqn_div = div
	ppqn[i] = 96/div
	ppqn_counter[i] = 1
end
-- // CA logic

-- METRO //
function metro(index, count)
	if index == intro_metro then
		if get_time() - start_time >= intro_duration then
			metro_set(intro_metro, 0)
			intro_complete = true
			transport_running = true
			dirty = true
		else
			draw_intro()
		end
	elseif index == redraw_metro and dirty then
		if intro_complete then
			redraw_grid()
			dirty = false
		end
	elseif index == snapshots_saver_metro then
		if snapshot_being_saved ~= nil then
			snapshot_save(snapshot_being_saved)
			snapshot_being_saved = nil
			dirty = true
		end
	elseif index == main_metro and transport_running then
		for i = 1,number_of_voices do
			iterate(i)
		end
	end
end
-- // METRO

metro_set(intro_metro, 50)
metro_set(redraw_metro, 20) -- (1000/50), 50fps in ms [needed as of 241203]
metro_set(main_metro, 10)