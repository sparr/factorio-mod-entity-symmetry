require "util"

-- Concepts:
-- "direction" is an integer, 0-7, representing North, Northeast, ..., West, Northwest
-- "orientation" is a float, where 0 represents North, 0.25 East, 0.5 South, 0.75 West
-- "angle" is a float, where 0 represents North, PI/2 East, PI South, 3*PI/2 West
-- position is a table with x and y coordinates, each a float
-- +x is East
-- +y is South

-- we're going to refer to these a lot
local N, NE, E, SE, S, SW, W, NW =
  defines.direction.north,
  defines.direction.northeast,
  defines.direction.east,
  defines.direction.southeast,
  defines.direction.south,
  defines.direction.southwest,
  defines.direction.west,
  defines.direction.northwest

-- inline arithmetic would be faster, but this is better than a function call
local direction_to_orientation = {
  [N]  = 0,
  [NE] = 0.125,
  [E]  = 0.25,
  [SE] = 0.375,
  [S]  = 0.5,
  [SW] = 0.625,
  [W]  = 0.75,
  [NW] = 0.875
}

local function orientation_to_direction(ori)
  return math.floor(ori * 8 + 0.5) % 8
end

-- curved rail directions are a little weird, so mirroring them requires a lookup
local direction_curvedrail_mirror_x =
  {[N]=NE, [NE]=N, [E]=NW, [SE]=W, [S]=SW, [SW]=S, [W]=SE, [NW]=E}
local direction_curvedrail_mirror_y =
  {[N]=SW, [NE]=S, [E]=SE, [SE]=E, [S]=NE, [SW]=N, [W]=NW, [NW]=W}

-- how many directions/orientations can each entity type point
-- 0 means smooth rotation, mostly for vehicles
local orientation_direction_types = {
  ["car"]                   = 0,
  ["tank"]                  = 0,
  ["locomotive"]            = 0,
  ["cargo-wagon"]           = 0,
  ["fluid-wagon"]           = 0,
  ["artillery-wagon"]       = 0,
  ["straight-rail"]         = 8, -- has special cases handled elsewhere
  ["curved-rail"]           = 8, -- has special cases handled elsewhere
  ["rail-signal"]           = 8,
  ["rail-chain-signal"]     = 8,
  ["inserter"]              = 4,
  ["transport-belt"]        = 4,
  ["underground-belt"]      = 4,
  ["splitter"]              = 4,
  ["loader"]                = 4,
  ["pipe-to-ground"]        = 4,
  ["pump"]                  = 4,
  ["pump-jack"]             = 4,
  ["train-stop"]            = 4,
  ["arithmetic-combinator"] = 4,
  ["decider-combinator"]    = 4,
  ["constant-combinator"]   = 4,
  ["boiler"]                = 4,
  ["mining-drill"]          = 4,
  ["chemical-plant"]        = 4,
  ["offshore-pump"]         = 4,
  ["ammo-turret"]           = 4,
  ["fluid-turret"]          = 4,
  ["artillery-turret"]      = 4,
  ["simple-entity-with-owner"] = 4,
  ["storage-tank"]          = 2,
  ["steam-engine"]          = 2,
  ["steam-turbine"]         = 2,
}

-- lookup for what angle to snap entity orientations to
local orientation_snap = {
  [0] = 0,
  [2] = 0.25, -- I don't remember why this isn't 0.5
  [4] = 0.25,
  [8] = 0.125,
}

-- entities that exist on the 2x2 rail grid
local rail_entity_types = {
  ["straight-rail"]     = true,
  ["curved-rail"]       = true,
  ["rail-signal"]       = true,
  ["rail-chain-signal"] = true,
  ["train-stop"]        = true,
  ["locomotive"]        = true,
  ["cargo-wagon"]       = true,
  ["fluid-wagon"]       = true,
  ["artillery-wagon"]   = true,
}

local function deghost_type(entity)
  return entity.type == "entity-ghost" and entity.ghost_type or entity.type
end

-- given an entity type and its current direction and orientation
-- return the direction and orientation after optional mirroring/rotation
-- sym_x for east/west mirror
-- sym_y for north/south/mirror
-- reori for rotation, 0.25 = 90 degrees clockwise
local function get_mirrotated_entity_dir_ori(entity_type, dir, ori, sym_x, sym_y, reori)
  local od_type = orientation_direction_types[entity_type]
  if od_type == nil then
    return 0, 0
  end
  -- rail signals need to be rotated 180 if they are mirrored once
  if (entity_type == "rail-signal" or entity_type == "rail-chain-signal") and
    ((sym_x and not sym_y) or (sym_y and not sym_x))
  then
    reori = (reori or 0) + 0.5
  end
  if reori then -- rotation
    if od_type == 0 then
      return 0, (ori + reori) % 1
    end
    local dir_reori = reori
    local snap_ori = orientation_snap[orientation_direction_types[entity_type]]
    if snap_ori > 0 then -- round to nearest multiple of snap_ori
      dir_reori = math.floor((reori + (snap_ori / 2)) / snap_ori) * snap_ori
    end
    dir = (dir + dir_reori * 8) % 8
    ori = (ori + dir_reori) % 1
  end
  if sym_x then
    if entity_type == "curved-rail" then
      dir = direction_curvedrail_mirror_x[dir]
    else
      dir = (8 - dir) % 8
      ori = (1 - ori) % 1
    end
  end
  if sym_y then
    if entity_type == "curved-rail" then
      dir = direction_curvedrail_mirror_y[dir]
    else
      dir = ((8 - ((dir - 2) % 8)) + 2) % 8
      ori = ((1 - ((ori - 0.25) % 1)) + 0.25) % 1
    end
  end
  if entity_type == "curved-rail" then
    ori = direction_to_orientation[dir]
  end
  if od_type == 2 or entity_type == "straight-rail" then
    -- these types never point south/west
    if dir == 4 or dir == 6 then dir = dir - 4 end
    if ori == 0.5 or ori == 0.75 then ori = ori - 0.5 end
  end
  return dir, ori
end

-- given two positions, orbit one around the other
-- orientation 0.25 = 90 degrees clockwise
local function orient_position_relative(center, position, orientation)
  local delta = table.deepcopy(position)
  delta.x = delta.x - center.x
  delta.y = delta.y - center.y
  orientation = orientation % 1
  if orientation == 0.5 then
    delta.x, delta.y = -delta.x, -delta.y
  elseif orientation == 0.25 then
    delta.x, delta.y = -delta.y, delta.x
  elseif orientation == 0.75 then
    delta.x, delta.y = delta.y, -delta.x
  elseif orientation == 0 then
    -- nothing
  else
    -- trig time
    local magnitude = (delta.x * delta.x + delta.y * delta.y) ^ 0.5
    local angle = orientation * math.pi * 2
    angle = math.atan2(delta.x, delta.y) + angle
    delta.x = math.sin(angle) * magnitude
    delta.y = math.cos(angle) * magnitude
  end
  delta.x, delta.y = delta.x + center.x, delta.y + center.y
  return delta
end

local function cache_center_entity(entity)
  if entity.valid ~= true then return end
  global.cached_center_entities[script.register_on_entity_destroyed(entity)] = entity
end

local function control_behavior_empty(control_behavior)
  for _, parameter in pairs(control_behavior.parameters) do -- API bug, maybe to be fixed in 1.1
    if parameter.signal.name then return false end
  end
  return true
end

local function on_altered_entity(event, action, manual)
  local entity = event.created_entity or event.entity or event.source
  local surface = entity.surface
  local centers = global.cached_center_entities
  local player = event.player_index and game.players[event.player_index] or nil

  if entity.name == "symmetry-center" then
    if action == "create" then
      cache_center_entity(entity)
      if manual then
        local cb = entity.get_control_behavior()
        if control_behavior_empty(cb) then
          -- set some default signals for a new manually placed empty symmetry-center
          -- maybe this should also trigger for new empty symmetry-center ghosts?
          cb.set_signal(1, {
            signal={type="virtual", name="signal-C"},
            count=tostring(
              player and player.mod_settings['entity-symmetry-default-center'].value
              or settings.player['entity-symmetry-default-center'].value
            )
          })
          cb.set_signal(2, {
            signal={type="virtual", name="signal-D"},
            count=tostring(
              player and player.mod_settings['entity-symmetry-default-distance'].value
              or settings.player['entity-symmetry-default-distance'].value
            )
          })
          cb.set_signal(3, {
            signal={type="virtual", name="signal-R"},
            count=tostring(
              player and player.mod_settings['entity-symmetry-default-rails'].value
              or settings.player['entity-symmetry-default-rails'].value
            )
          })
          cb.set_signal(4, {
            signal={type="virtual", name="signal-S"},
            count=tostring(
              player and player.mod_settings['entity-symmetry-default-symmetry'].value
              or settings.player['entity-symmetry-default-symmetry'].value
            )
          })
        end
      end
    end
    return -- disallow cloning symmetry-centers to avoid infinite recursion for now
  end
  if manual then
    local rail_mode = rail_entity_types[deghost_type(entity)] or entity.prototype.building_grid_bit_shift == 2 or false
    local new_centers = {}
    for i, center_entity in pairs(centers) do
      if not center_entity.valid then
        centers[i] = nil
      elseif center_entity.surface.name == entity.surface.name then
        if center_entity ~= entity then
          local center_dir = ( player and player.mod_settings['entity-symmetry-default-center'].value
            or settings.player['entity-symmetry-default-center'].value )
          local range = ( player and player.mod_settings['entity-symmetry-default-distance'].value
            or settings.player['entity-symmetry-default-distance'].value )
          local configured_rail_mode = ( player and player.mod_settings['entity-symmetry-default-rails'].value
            or settings.player['entity-symmetry-default-rails'].value )
          local rot_symmetry = ( player and player.mod_settings['entity-symmetry-default-symmetry'].value
            or settings.player['entity-symmetry-default-symmetry'].value )
          local xaxis_mirror = false
          local yaxis_mirror = false
          local diag1_mirror = false
          local diag2_mirror = false
          local include = {}
          local exclude = {}
          local cb = center_entity.get_control_behavior()
          if not cb.enabled then goto next_center_entity end
          local rail_signal_slot = 3

          for _, parameter in pairs(cb.parameters) do
            if parameter.signal.name then
              if parameter.signal.name == "signal-C" then
                -- move the [C]enter point to an edge/corner of the tile
                center_dir = parameter.count
              elseif parameter.signal.name == "signal-D" then
                -- set the [D]istance/range
                range = parameter.count
              elseif parameter.signal.name == "signal-R" then
                -- optionally turn on or off [R]ail mode for all entities
                configured_rail_mode = parameter.count
                rail_signal_slot = parameter.index
              elseif parameter.signal.name == "signal-S" then
                -- type and degree/axes of [S]ymmetry
                if parameter.count >= 0 then -- rotational symmetry degree
                  rot_symmetry = parameter.count
                else -- mirroring, x/y axes, diagonals
                  rot_symmetry = 0
                  if bit32.band(1, -parameter.count) > 0 then xaxis_mirror = true end
                  if bit32.band(2, -parameter.count) > 0 then yaxis_mirror = true end
                  if bit32.band(4, -parameter.count) > 0 then diag1_mirror = true end
                  if bit32.band(8, -parameter.count) > 0 then diag2_mirror = true end
                end
              elseif parameter.signal.type == "item" then
                -- negative item signals exclude the item
                -- positive filter for just those items
                if parameter.count < 0 then
                  exclude.some = true
                  exclude[parameter.signal.name] = true
                else
                  include.some = true
                  include[parameter.signal.name] = true
                end
              end
            end
          end
          local center_position = table.deepcopy(center_entity.position)
          -- rail grid is 2x2, find the center of the rail tile
          if rail_mode or configured_rail_mode > 0 then
            center_position.x = math.floor(((center_position.x - 1) / 2) + 0.5) * 2 + 1
            center_position.y = math.floor(((center_position.y - 1) / 2) + 0.5) * 2 + 1
          end
          -- negative range is circular, positive is square
          if (range>0 and ((entity.position.x - center_position.x)^2 + (entity.position.y - center_position.y)^2) <= range*range) or
            (math.abs(entity.position.x - center_position.x) <= range and math.abs(entity.position.y - center_position.y) <= range)
          then
            if (not include.some and not exclude.some) or
              (include.some and (include[entity.name] or ((entity.name=="straight-rail" or entity.name=="curved-rail") and include["rail"]))) or
              (not include.some and exclude.some and not (exclude[entity.name] or ((entity.name=="straight-rail" or entity.name=="curved-rail") and exclude["rail"])))
            then
              if rail_mode then
                if configured_rail_mode == 0 then
                  cb.set_signal(rail_signal_slot, {signal={type="virtual", name="signal-R"}, count="1"})
                end
              elseif configured_rail_mode > 0 then
                rail_mode = true
              end
              local conditional_rail_offset = rail_mode and 1 or 0.5
              if center_dir >=0 and center_dir <= 7 then
                -- move the [C]enter point to an edge/corner of the tile
                if     center_dir == 1 then
                  center_position.x = center_position.x + conditional_rail_offset
                  center_position.y = center_position.y - conditional_rail_offset
                elseif center_dir == 3 then
                  center_position.x = center_position.x + conditional_rail_offset
                  center_position.y = center_position.y + conditional_rail_offset
                elseif center_dir == 5 then
                  center_position.x = center_position.x - conditional_rail_offset
                  center_position.y = center_position.y + conditional_rail_offset
                elseif center_dir == 7 then
                  center_position.x = center_position.x - conditional_rail_offset
                  center_position.y = center_position.y - conditional_rail_offset
                elseif center_dir == 0 then
                  center_position.y = center_position.y - conditional_rail_offset
                elseif center_dir == 2 then
                  center_position.x = center_position.x + conditional_rail_offset
                elseif center_dir == 4 then
                  center_position.y = center_position.y + conditional_rail_offset
                elseif center_dir == 6 then
                  center_position.x = center_position.x - conditional_rail_offset
                end
              end
              local positions = {table.deepcopy(entity.position)}
              local directions = {entity.direction}
              local orientations = {entity.orientation}
              if rot_symmetry == 0 then
                if xaxis_mirror then
                  for n = 1, #positions do
                    local new_position = table.deepcopy(positions[n])
                    new_position.x = center_position.x - (new_position.x - center_position.x)
                    positions[#positions + 1] = new_position
                    local dir, ori = get_mirrotated_entity_dir_ori(
                      deghost_type(entity),
                      directions[n],
                      orientations[n],
                      true, false, false
                    )
                    directions[#directions + 1] = dir
                    orientations[#orientations + 1] = ori
                  end
                end
                if yaxis_mirror then
                  for n = 1, #positions do
                    local new_position = table.deepcopy(positions[n])
                    new_position.y = center_position.y - (new_position.y - center_position.y)
                    positions[#positions + 1] = new_position
                    local dir, ori = get_mirrotated_entity_dir_ori(
                      deghost_type(entity),
                      directions[n],
                      orientations[n],
                      false, true, false
                    )
                    directions[#directions + 1] = dir
                    orientations[#orientations + 1] = ori
                  end
                end
                if diag1_mirror then
                  for n = 1, #positions do
                    local new_position = table.deepcopy(positions[n])
                    new_position.x, new_position.y =
                      center_position.x - (new_position.y - center_position.y),
                      center_position.y - (new_position.x - center_position.x)
                    positions[#positions + 1] = new_position
                    directions[#directions + 1] = ((deghost_type(entity) == "curved-rail" and 3 or 2) - directions[n]) % 8
                    orientations[#orientations + 1] = (-orientations[n] + 0.25) % 1
                  end
                end
                if diag2_mirror then
                  for n = 1, #positions do
                    local new_position = table.deepcopy(positions[n])
                    new_position.x, new_position.y =
                      center_position.x + (new_position.y - center_position.y),
                      center_position.y + (new_position.x - center_position.x)
                    positions[#positions + 1] = new_position
                    directions[#directions + 1] = ((deghost_type(entity) == "curved-rail" and 7 or 6) - directions[n]) % 8
                    orientations[#orientations + 1] = (-orientations[n] + 0.75) % 1
                  end
                end
              elseif rot_symmetry > 1 then -- rotational symmetry instead of mirroring
                local rot_direction = directions[1]
                local rot_orientation = orientations[1]
                for r = 1, rot_symmetry - 1 do
                  positions[#positions + 1] = orient_position_relative(
                    center_position,
                    positions[1],
                    r / rot_symmetry
                  )
                  local dir, ori = get_mirrotated_entity_dir_ori(
                    deghost_type(entity),
                    directions[1],
                    orientations[1],
                    false, false, r * (1 / rot_symmetry)
                  )
                  directions[#directions + 1] = dir
                  orientations[#orientations + 1] = ori
                end
              end
              local cheat = settings.global["entity-symmetry-allow-cheat"].value and player.mod_settings["entity-symmetry-cheat"].value
              -- now actually make or remove the additional entities
              for n = 2, #positions do
                if action == "create" then
                  local pos = positions[n]
                  local dir = entity.supports_direction and directions[n] or 0
                  if orientation_direction_types[deghost_type(entity)] == 0 then
                    -- smooth turning entities are spawned with a direction
                    dir = orientation_to_direction(orientations[n])
                  end

                  if positions[1].x ~= positions[n].x or
                     positions[1].y ~= positions[n].y or
                     (entity.supports_direction and entity.direction ~= directions[n]) or
                     orientations[1] ~= orientations[n] then

                    -- can't use clone because rail entities can't change direction after creation
                    -- local new_entity = entity.clone{position = pos}
                    -- new_entity.direction = dir

                    --TODO type-specific attributes
                    local entity_def = {
                      position = pos,
                      direction = dir,
                      force = entity.force,
                      raise_built = true,
                    }
                    if cheat then
                      entity_def.name = entity.name
                      entity_def.inner_name = entity.name == "entity-ghost" and entity.ghost_name or nil
                    else
                      entity_def.name = "entity-ghost"
                      entity_def.inner_name = entity.name == "entity-ghost" and entity.ghost_name or entity.name
                    end
                    local new_entity = surface.create_entity(entity_def)

                    if cheat and entity.name == "symmetry-center" then
                      new_centers[#new_centers+1] = new_entity
                    end
                  end
                elseif action == "destroy" or action == "deconstruct_canceled" or action == "deconstruct_marked" then
                  local found_entities = surface.find_entities_filtered{
                    area = {{positions[n].x - 0.5, positions[n].y - 0.5}, {positions[n].x + 0.5, positions[n].y + 0.5}},
                    name = entity.name,
                    type = entity.type,
                    force = entity.force.name,
                  }
                  if #found_entities then
                    for _, found_entity in ipairs(found_entities) do
                      if found_entity.valid then
                        if found_entity.position.x == positions[n].x and found_entity.position.y == positions[n].y then
                          if found_entity.orientation == orientations[n] then
                            if (not entity.supports_direction) or (found_entity.direction == directions[n]) then
                              if found_entity ~= entity then
                                if entity.type ~= "entity-ghost" or found_entity.ghost_name == entity.ghost_name then
                                  if (cheat and action == "destroy") or entity.type == "entity-ghost" then
                                    found_entity.destroy()
                                  elseif action == "destroy" or action == "deconstruct_marked" then
                                    found_entity.order_deconstruction(player.force, player)
                                  elseif action == "deconstruct_canceled" then
                                    found_entity.cancel_deconstruction(player.force, player)
                                  end
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                else
                  -- debug_write("unrecognized action " .. params.action)
                end
              end
            end
          end
        end
      end
      ::next_center_entity::
    end
    for _, new_center in pairs(new_centers) do
      cache_center_entity(new_center)
    end
  end
end

local function on_entity_destroyed(event)
  global.cached_center_entities[event.registration_number] = nil
end

local function on_configuration_changed(event)
  if global.cached_center_entities == nil then
    global.cached_center_entities = {}
    for _,surface in pairs(game.surfaces) do
      local centers = surface.find_entities_filtered{name="symmetry-center"}
      for _, center in pairs(centers) do
        cache_center_entity(center)
      end
    end
  end
end

--TODO handle rotation and reconfiguration events for entities

-- handle all ways an entity can be built so that we catch new symmetry-center entities being created
-- only on_built_entity will actually trigger symmetric cloning
script.on_event(defines.events.on_built_entity,       function(event) on_altered_entity(event, "create", true) end)
-- clones should have already been created when the ghost was created
-- script.on_event(defines.events.on_robot_built_entity, function(event) on_altered_entity(event, "create", false) end)
script.on_event(defines.events.on_entity_cloned,      function(event) on_altered_entity(event, "create", false) end)
script.on_event(defines.events.script_raised_built,   function(event) on_altered_entity(event, "create", false) end)
script.on_event(defines.events.script_raised_revive,  function(event) on_altered_entity(event, "create", false) end)
script.on_event(defines.events.on_cancelled_deconstruction,  function(event) on_altered_entity(event, "deconstruct_canceled", true) end)
script.on_event(defines.events.on_marked_for_deconstruction, function(event) on_altered_entity(event, "deconstruct_marked", true) end)

-- removal of symmetry-center is handled by registering entity-specific destruction events when they are created
-- so we only need to watch for player mining entities to trigger symmetric removal
script.on_event(defines.events.on_player_mined_entity, function(event) on_altered_entity(event, "destroy", true) end)

script.on_event(defines.events.on_entity_destroyed, on_entity_destroyed)

script.on_init(on_configuration_changed)
script.on_configuration_changed(on_configuration_changed)

-- local debugnum = 0
-- local function debug_write(...)
--   if game and game.players[1] then
--     game.players[1].print("DEBUG " .. debugnum .. " " .. game.tick .. ": " .. serpent.line(..., {comment=false}))
--     debugnum = debugnum + 1
--   end
-- end

