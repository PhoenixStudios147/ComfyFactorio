local Public = {}
local simplex_noise = require "utils.simplex_noise".d2
local math_random = math.random
local math_abs = math.abs
local math_sqrt = math.sqrt
local math_floor = math.floor
local table_remove = table.remove
local table_insert = table.insert
local table_shuffle_table = table.shuffle_table
local chart_radius = 30
local start_chunk_y = 5
local tile_conversion = {
	["concrete"] = "stone-path",
	["hazard-concrete-left"] = "stone-path",
	["hazard-concrete-right"] = "stone-path",
	["refined-concrete"] = "concrete",
	["refined-hazard-concrete-left"] = "hazard-concrete-left",
	["refined-hazard-concrete-right"] = "hazard-concrete-right",
	["stone-path"] = "landfill",
}

local size_of_vector_list = 128
local function get_collapse_vectors(radius, seed)
	local vectors = {}
	local i = 1
	local m = 1 / (radius * 2)
	for x = radius * -1, radius, 1 do
		for y = radius * -1, radius, 1 do
			local noise = math_abs(simplex_noise(x * m, y * m, seed) * radius * 1.2)
			local d = math_sqrt(x ^ 2 + y ^ 2)
			if d + noise < radius then
				vectors[i] = {x, y}
				i = i + 1
			end
		end
	end
	
	local sorted_vectors = {}
	for _, vector in pairs(vectors) do
		local index = math_floor(math_sqrt(vector[1] ^ 2 + vector[2] ^ 2)) + 1
		if not sorted_vectors[index] then sorted_vectors[index] = {} end
		sorted_vectors[index][#sorted_vectors[index] + 1] = vector		
	end
	
	local final_list = {}	
	for _, row in pairs(sorted_vectors) do
		table_shuffle_table(row)
		for _, tile in pairs(row) do
			table_insert(final_list, tile)
		end
	end
	
	return final_list
end

local function set_positions(surface)
	local level_width = surface.map_gen_settings.width
	local row_count = level_width * 32
	
	local chunk_x = math.floor((level_width * -0.5) / 32)
	local chunk_y = false
	
	local position_x = level_width * -0.5
	local position_y = false
	
	local area = false
	
	for y = start_chunk_y, -1024, -1 do		
		if surface.is_chunk_generated({chunk_x, y}) then			
			position_y = y * 32
			area = {{position_x, position_y},{position_x + level_width, position_y + 32}}			
			if surface.count_tiles_filtered({name = "out-of-map", area = area}) < row_count then
				break
			else
				area = false
			end
		end
	end
	if not area then return end

	local tile_positions = {}
	local i = 1
	for _, tile in pairs(surface.find_tiles_filtered({area = area})) do
		if tile.valid then
			if tile.name ~= "out-of-map" then
				tile_positions[i] = {tile.position.x, tile.position.y}
				i = i + 1
			end
		end
	end
	
	if #tile_positions > 1 then table_shuffle_table(tile_positions) end
	
	local tiles = {}
	for k, p in pairs(tile_positions) do
		tiles[k] = p
		if k > 512 then break end
	end
	
	if #tiles > 1 then
		table.sort(tiles, function (a, b) return a[2] > b[2] end)
	end
	
	for k, p in pairs(tiles) do
		global.map_collapse.positions[k] = {p[1], p[2]}
		if k > 128 then break end
	end
	
	return true
end

local function set_collapse_tiles(surface, position, vectors)
	local i = 1
	for _, vector in pairs(vectors) do
		local position = {x = position[1] + vector[1], y = position[2] + vector[2]}
		local tile = surface.get_tile(position)
		if tile.valid then
			global.map_collapse.processing[i] = tile
			i = i + 1
		end
	end
end

local function setup_next_collapse()
	local surface = game.surfaces[global.active_surface_index]
	local map_collapse = global.map_collapse	
	if not map_collapse.vector_list then
		map_collapse.vector_list = {} 
		for _ = 1, size_of_vector_list, 1 do
			table_insert(global.map_collapse.vector_list, get_collapse_vectors(math_random(16, 24), math_random(1, 9999999)))
		end
	end

	local size_of_positions = #map_collapse.positions
	if size_of_positions == 0 then
		if not set_positions(surface) then return end
	end

	local position = map_collapse.positions[size_of_positions]
	if not position then return end
	
	local tile = surface.get_tile(position)
	if not tile.valid then map_collapse.positions[size_of_positions] = nil return end
	if tile.name == "out-of-map" then map_collapse.positions[size_of_positions] = nil return end
	
	local vectors = map_collapse.vector_list[math_random(1, size_of_vector_list)]
	set_collapse_tiles(surface, position, vectors)	
	
	local last_position = global.map_collapse.last_position
	game.forces.player.chart(surface, {{last_position.x - chart_radius, last_position.y - chart_radius},{last_position.x + chart_radius, last_position.y + chart_radius}})
	global.map_collapse.last_position = {x = position[1], y = position[2]}
	game.forces.player.chart(surface, {{position[1] - chart_radius, position[2] - chart_radius},{position[1] + chart_radius, position[2] + chart_radius}})
end

function Public.delete_out_of_map_chunks(surface)
	local count = 0
	for chunk in surface.get_chunks() do
		if surface.count_tiles_filtered({name = "out-of-map", area = chunk.area}) == 1024 then
			surface.delete_chunk({chunk.x, chunk.y})
			count = count + 1
		end
	end
end

function Public.process()
	local surface = game.surfaces[global.active_surface_index]
	local map_collapse = global.map_collapse
	
	for key, tile in pairs(map_collapse.processing) do
		if not tile.valid then table_remove(map_collapse.processing, key) return end
		local conversion_tile = tile_conversion[tile.name]			
		if conversion_tile then
			surface.set_tiles({{name = conversion_tile, position = tile.position}}, true)
			surface.create_trivial_smoke({name="train-smoke", position = tile.position})	
		else
			surface.set_tiles({{name = "out-of-map", position = tile.position}}, true)
		end
		table_remove(map_collapse.processing, 1)
		return
	end

	setup_next_collapse() 
end

function Public.init()
	global.map_collapse = {}
	global.map_collapse.positions = {}
	global.map_collapse.processing = {}
	global.map_collapse.last_position = {x = 0, y = 0}
end

local event = require 'utils.event'
event.on_init(Public.init())

return Public