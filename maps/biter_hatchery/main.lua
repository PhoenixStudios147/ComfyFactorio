require "modules.no_turrets"
local RPG = require "modules.rpg"
local Tabs = require 'comfy_panel.main'
local Map_score = require "modules.map_score"
local unit_raffle = require "maps.biter_hatchery.raffle_tables"
local map_functions = require "tools.map_functions"
local Terrain = require "maps.biter_hatchery.terrain"
local Gui = require "maps.biter_hatchery.gui"
require "maps.biter_hatchery.share_chat"
local Team = require "maps.biter_hatchery.team"
local Reset = require "functions.soft_reset"
local Map = require "modules.map_info"
local math_random = math.random
local Public = {}

local worm_turret_spawn_radius = 18
local worm_turret_vectors = {}
worm_turret_vectors.west = {}
for x = 0, worm_turret_spawn_radius, 1 do
	for y = worm_turret_spawn_radius * -1, worm_turret_spawn_radius, 1 do
		local d = math.sqrt(x ^ 2 + y ^ 2)
		if d <= worm_turret_spawn_radius and d > 3 then table.insert(worm_turret_vectors.west, {x, y}) end
	end
end
worm_turret_vectors.east = {}
for x = worm_turret_spawn_radius * -1, 0, 1 do
	for y = worm_turret_spawn_radius * -1, worm_turret_spawn_radius, 1 do
		local d = math.sqrt(x ^ 2 + y ^ 2)
		if d <= worm_turret_spawn_radius and d > 3 then table.insert(worm_turret_vectors.east, {x, y}) end
	end
end

local function draw_spawn_ores(surface)
	local x = global.map_forces.west.hatchery.position.x - 64
	map_functions.draw_smoothed_out_ore_circle({x = x, y = 32}, "iron-ore", surface, 15, 2500)
	map_functions.draw_smoothed_out_ore_circle({x = x, y = -32}, "copper-ore", surface, 15, 2500)
	map_functions.draw_smoothed_out_ore_circle({x = x, y = 0}, "coal", surface, 15, 1500)
	map_functions.draw_smoothed_out_ore_circle({x = x, y = 64}, "stone", surface, 15, 1500)
	
	local x = global.map_forces.east.hatchery.position.x + 64
	map_functions.draw_smoothed_out_ore_circle({x = x, y = 32}, "copper-ore", surface, 15, 2500)
	map_functions.draw_smoothed_out_ore_circle({x = x, y = -32}, "iron-ore", surface, 15, 2500)
	map_functions.draw_smoothed_out_ore_circle({x = x, y = 0}, "coal", surface, 15, 1500)
	map_functions.draw_smoothed_out_ore_circle({x = x, y = -64}, "stone", surface, 15, 1500)
end

function Public.reset_map()
	local map_gen_settings = {}
	map_gen_settings.seed = math_random(1, 10000000)
	map_gen_settings.water = 0.2
	map_gen_settings.starting_area = 1
	map_gen_settings.terrain_segmentation = 10
	map_gen_settings.cliff_settings = {cliff_elevation_interval = math_random(16, 48), cliff_elevation_0 = math_random(16, 48)}	
	map_gen_settings.autoplace_controls = {
		["coal"] = {frequency = 100, size = 0.5, richness = 0.5,},
		["stone"] = {frequency = 100, size = 0.5, richness = 0.5,},
		["copper-ore"] = {frequency = 100, size = 0.5, richness = 0.5,},
		["iron-ore"] = {frequency = 100, size = 0.5, richness = 0.5,},
		["uranium-ore"] = {frequency = 50, size = 0.5, richness = 0.5,},
		["crude-oil"] = {frequency = 50, size = 0.5, richness = 0.5,},
		["trees"] = {frequency = math_random(5, 10) * 0.1, size = math_random(5, 10) * 0.1, richness = math_random(3, 10) * 0.1},
		["enemy-base"] = {frequency = 0, size = 0, richness = 0}	
	}
	
	if not global.active_surface_index then
		global.active_surface_index = game.create_surface("biter_hatchery", map_gen_settings).index		
	else
		global.active_surface_index = Reset.soft_reset_map(game.surfaces[global.active_surface_index], map_gen_settings, Team.starting_items).index
	end
	
	local surface = game.surfaces[global.active_surface_index]
	surface.request_to_generate_chunks({0,0}, 10)
	surface.force_generate_chunk_requests()
		
	game.forces.west.set_spawn_position({-160, 0}, surface)
	game.forces.east.set_spawn_position({160, 0}, surface)		
		
	local e = surface.create_entity({name = "biter-spawner", position = {-160, 0}, force = "west"})
	surface.create_entity({name = "small-worm-turret", position = {-155, 0}, force = "west"})
	e.active = false
	global.map_forces.west.hatchery = e
	global.map_forces.east.target = e
	
	local e = surface.create_entity({name = "biter-spawner", position = {160, 0}, force = "east"})
	surface.create_entity({name = "small-worm-turret", position = {155, 0}, force = "east"})
	e.active = false
	global.map_forces.east.hatchery = e
	global.map_forces.west.target = e
	
	draw_spawn_ores(surface)
	
	RPG.rpg_reset_all_players()
	
	Team.set_force_attributes()	
	Team.assign_random_force_to_active_players()
	
	for _, player in pairs(game.connected_players) do
		if player.gui.left.biter_hatchery_game_won then player.gui.left.biter_hatchery_game_won.destroy() end
		Team.teleport_player_to_active_surface(player)		
	end
	
	for _, player in pairs(game.forces.spectator.connected_players) do
		player.character.destroy()
		Team.set_player_to_spectator(player)	
	end	
	for _, player in pairs(game.forces.spectator.players) do
		Gui.rejoin_question(player)
	end
end

local function spawn_worm_turret(surface, force_name, food_item)
	local r_max = surface.count_entities_filtered({type = "turret", force = force_name}) + 1
	if math_random(1, r_max) ~= 1 then return end
	local vectors = worm_turret_vectors[force_name]
	local vector = vectors[math_random(1, #vectors)]
	local worm = "small-worm-turret"
	local position = {x = global.map_forces[force_name].hatchery.position.x, y = global.map_forces[force_name].hatchery.position.y}
	position.x = position.x + vector[1]
	position.y = position.y + vector[2]
	position = surface.find_non_colliding_position("biter-spawner", position, 16, 1)
	if not position then return end
	surface.create_entity({name = worm, position = position, force = force_name})
	surface.create_entity({name = "blood-explosion-huge", position = position})
end

local function spawn_units(belt, food_item, removed_item_count)
	local count_per_flask = unit_raffle[food_item][2]
	local raffle = unit_raffle[food_item][1]
	for _ = 1, removed_item_count, 1 do
		for _ = 1, count_per_flask, 1 do
			local unit = belt.surface.create_entity({name = raffle[math_random(1, #raffle)], position = belt.position, force = belt.force})
			unit.ai_settings.allow_destroy_when_commands_fail = false
			unit.ai_settings.allow_try_return_to_spawner = false
		end
	end
	if math_random(1, 32) == 1 then spawn_worm_turret(belt.surface, belt.force.name, food_item) end
end

local function get_belts(spawner)
	local belts = spawner.surface.find_entities_filtered({
			type = "transport-belt",
			area = {{spawner.position.x - 5, spawner.position.y - 3},{spawner.position.x + 4, spawner.position.y + 3}},
			force = spawner.force,
		})
	return belts
end

local nom_msg = {"munch", "munch", "yum", "nom"}

local function feed_floaty_text(entity)
	entity.surface.create_entity({name = "flying-text", position = entity.position, text = nom_msg[math_random(1, 4)], color = {math_random(50, 100), 0, 255}})
	local position = {x = entity.position.x - 0.75, y = entity.position.y - 1}
	local b = 1.35
	for a = 1, math_random(0, 2), 1 do
		local p = {(position.x + 0.4) + (b * -1 + math_random(0, b * 20) * 0.1), position.y + (b * -1 + math_random(0, b * 20) * 0.1)}			
		entity.surface.create_entity({name = "flying-text", position = p, text = "♥", color = {math_random(150, 255), 0, 255}})						
	end
end

local function eat_food_from_belt(belt)
	for i = 1, 2, 1 do
		local line = belt.get_transport_line(i)
		for food_item, raffle in pairs(unit_raffle) do
			local removed_item_count = line.remove_item({name = food_item, count = 8})
			if removed_item_count > 0 then
				feed_floaty_text(belt)
				spawn_units(belt, food_item, removed_item_count)
			end
		end
	end	
end

local function nom()
	local surface = game.surfaces[global.active_surface_index]
	for key, force in pairs(global.map_forces) do
		force.hatchery.health = force.hatchery.health + 1
		local belts = get_belts(force.hatchery)
		for _, belt in pairs(belts) do
			eat_food_from_belt(belt)
		end
	end
end

local function send_unit_groups()
	local surface = game.surfaces[global.active_surface_index]
	for key, force in pairs(global.map_forces) do
		local units = {}
		for _, unit in pairs(surface.find_entities_filtered({type = "unit", force = key})) do
			if not unit.unit_group then
				units[#units + 1] = unit
			end
		end
		if #units > 0 then
			local vectors = worm_turret_vectors[key]
			local vector = vectors[math_random(1, #vectors)]
			local position = {x = force.hatchery.position.x + vector[1], y = force.hatchery.position.y + vector[2]}	
			local unit_group = surface.create_unit_group({position = position, force = key})
			for _, unit in pairs(units) do unit_group.add_member(unit) end
			if not force.target then return end
			if not force.target.valid then return end
			unit_group.set_command({
				type = defines.command.compound,
				structure_type = defines.compound_command.return_last,
				commands = {
					{
						type = defines.command.attack_area,
						destination = {x = force.target.position.x, y = force.target.position.y},
						radius = 6,
						distraction = defines.distraction.by_anything
					},
					{
						type = defines.command.attack,
						target = force.target,
						distraction = defines.distraction.by_enemy,
					},			
				}
			})
		end
	end
end

local border_teleport = {
	["east"] = 2,
	["west"] = -2,
}

local function on_player_changed_position(event)
	local player = game.players[event.player_index]
	if not player.character then return end
	if not player.character.valid then return end
	if player.position.x >= -4 and player.position.x <= 4 then
		if not border_teleport[player.force.name] then return end
		if player.character.driving then player.character.driving = false end
		player.teleport({player.position.x + border_teleport[player.force.name], player.position.y}, game.surfaces[global.active_surface_index])
	end
end

local function on_entity_died(event)
	if not event.entity.valid then	return end
	if global.game_reset_tick then return end
	if event.entity.type ~= "unit-spawner" then return end
	
	local str
	if event.entity.force.name == "east" then
		game.print("East lost their Hatchery.", {100, 100, 100})
		str = ">>>> West team has won the game!!! <<<<"
		for _, player in pairs(game.forces.east.connected_players) do
			player.play_sound{path="utility/game_lost", volume_modifier=0.85}
		end
		for _, player in pairs(game.forces.west.connected_players) do
			player.play_sound{path="utility/game_won", volume_modifier=0.85}			
			Map_score.set_score(player, Map_score.get_score(player) + 1)
		end
	else
		game.print("West lost their Hatchery.", {100, 100, 100})
		str = ">>>> East team has won the game!!! <<<<"
		for _, player in pairs(game.forces.west.connected_players) do
			player.play_sound{path="utility/game_lost", volume_modifier=0.85}
		end
		for _, player in pairs(game.forces.east.connected_players) do
			player.play_sound{path="utility/game_won", volume_modifier=0.85}
			Map_score.set_score(player, Map_score.get_score(player) + 1)
		end
	end
	
	game.print(string.upper(str), {250, 120, 0})
	game.print("Next round starting in 30 seconds..", {150, 150, 150})
	
	for _, player in pairs(game.forces.spectator.connected_players) do
		player.play_sound{path="utility/game_won", volume_modifier=0.85}
	end
	global.game_reset_tick = game.tick + 1800
	
	for _, player in pairs(game.connected_players) do
		for _, child in pairs(player.gui.left.children) do child.destroy() end
		Tabs.comfy_panel_call_tab(player, "Map Scores")
		--player.gui.left.add({type = "frame", name = "biter_hatchery_game_won", caption = str})
	end
end

local function on_player_joined_game(event)
	local player = game.players[event.player_index]
	local surface = game.surfaces[global.active_surface_index]
	
	Gui.spectate_button(player)
	
	if player.gui.left.biter_hatchery_game_won then player.gui.left.biter_hatchery_game_won.destroy() end
	
	if player.surface.index ~= global.active_surface_index then		
		if player.force.name == "spectator" then 
			Team.set_player_to_spectator(player)
			Team.teleport_player_to_active_surface(player)		
			return 
		end
		Team.assign_force_to_player(player)
		Team.teleport_player_to_active_surface(player)
		Team.put_player_into_random_team(player)	
	end
end

local function tick()
	local game_tick = game.tick
	if game_tick % 240 == 0 then
		local area = {{-256, -97}, {255, 96}}
		game.forces.west.chart(game.surfaces[global.active_surface_index], area)
		game.forces.east.chart(game.surfaces[global.active_surface_index], area)
	end	
	if game_tick % 1200 == 0 then send_unit_groups() end	
	if global.game_reset_tick then
		if global.game_reset_tick < game_tick then
			global.game_reset_tick = nil
			Public.reset_map()
		end
		return
	end	
	nom()	
end

--Construction Robot Restriction
local robot_build_restriction = {
	["east"] = function(x)
		if x < 0 then return true end
	end,
	["west"] = function(x)
		if x > 0 then return true end
	end
}

local function on_robot_built_entity(event)
	if not robot_build_restriction[event.robot.force.name] then return end
	if not robot_build_restriction[event.robot.force.name](event.created_entity.position.x) then return end
	local inventory = event.robot.get_inventory(defines.inventory.robot_cargo)
	inventory.insert({name = event.created_entity.name, count = 1})
	event.robot.surface.create_entity({name = "explosion", position = event.created_entity.position})
	game.print("Team " .. event.robot.force.name .. "'s construction drone had an accident.", {r = 200, g = 50, b = 100})
	event.created_entity.destroy()
end

local function on_entity_damaged(event)
	local entity = event.entity
	if not entity.valid then return end
	if entity.type ~= "unit-spawner" then return end
	local cause = event.cause
	if cause then
		if cause.valid then
			if cause.type == "unit" then return end
		end
	end
	entity.health = entity.health + event.final_damage_amount	
end

local function on_init()
	game.difficulty_settings.technology_price_multiplier = 0.5 
	game.map_settings.enemy_evolution.destroy_factor = 0
	game.map_settings.enemy_evolution.pollution_factor = 0	
	game.map_settings.enemy_evolution.time_factor = 0
	game.map_settings.enemy_expansion.enabled = false
	game.map_settings.pollution.enabled = false
	global.map_forces = {
		["west"] = {},
		["east"] = {},
	}
	
	local T = Map.Pop_info()
	T.main_caption = "Biter Hatchery"
	T.sub_caption =  "..nibble nibble nom nom.."
	T.text = table.concat({
		"Defeat the enemy teams nest.\n",
		"Feed your hatchery science flasks to breed biters!\n",
		"They will soon after swarm to the opposing teams nest!\n",
		"\n",
		"Lay transport belts to your hatchery and they will happily nom the juice off the conveyor.\n",
		"Higher tier flasks will breed stronger biters!\n",
		"\n",
		"Player turrets are disabled.\n",
		"Feeding may spawn friendly worm turrets.\n",
		"The center river may not be crossed.\n",
		"Construction robots may not build over the river.\n",
	})
	T.main_caption_color = {r = 150, g = 0, b = 255}
	T.sub_caption_color = {r = 0, g = 250, b = 150}
	
	Team.create_forces()
	Public.reset_map()
end

local event = require 'utils.event'
event.on_init(on_init)
event.on_nth_tick(60, tick)
event.add(defines.events.on_robot_built_entity, on_robot_built_entity)
event.add(defines.events.on_entity_died, on_entity_died)
event.add(defines.events.on_player_joined_game, on_player_joined_game)
event.add(defines.events.on_player_changed_position, on_player_changed_position)
event.add(defines.events.on_entity_damaged, on_entity_damaged)