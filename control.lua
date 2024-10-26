require "util"

---@class (exact) Storage
---@field cached_center_entities LuaEntity[]
---@type Storage
storage=storage

-- Concepts:
-- "direction" is an integer, 0-15, representing North, North by Northeast, Northeast, ..., Northwest, North by Northwest
-- "orientation" is a float, where 0 represents North, 0.25 East, 0.5 South, 0.75 West
-- "angle" is a float, where 0 represents North, PI/2 East, PI South, 3*PI/2 West
-- position is a table with x and y coordinates, each a float
-- +x is East
-- +y is South

-- we're going to refer to these a lot
local N, NNE, NE, ENE, E, ESE, SE, SSE, S, SSW, SW, WSW, W, WNW, NW, NNW =
  defines.direction.north,
  defines.direction.northnortheast,
  defines.direction.northeast,
  defines.direction.eastnortheast,
  defines.direction.east,
  defines.direction.eastsoutheast,
  defines.direction.southeast,
  defines.direction.southsoutheast,
  defines.direction.south,
  defines.direction.southsouthwest,
  defines.direction.southwest,
  defines.direction.westsouthwest,
  defines.direction.west,
  defines.direction.westnorthwest,
  defines.direction.northwest,
  defines.direction.northnorthwest

-- inline arithmetic would be faster, but this is better than a function call
---@type table<defines.direction, float>
local direction_to_orientation = {
  [N]  = 0/16,
  [NNE] = 1/16,
  [NE] = 2/16,
  [ENE] = 3/16,
  [E]  = 4/16,
  [ESE] = 5/16,
  [SE] = 6/16,
  [SSE] = 7/16,
  [S]  = 8/16,
  [SSW] = 9/16,
  [SW] = 10/16,
  [WSW] = 11/16,
  [W]  = 12/16,
  [WNW] = 13/16,
  [NW] = 14/16,
  [NNW] = 15/16,
}

local function orientation_to_direction(ori)
  return math.floor(ori * 16 + 0.5) % 16
end

-- how many directions/orientations can each entity type point
-- 0 means smooth rotation, mostly for vehicles
local orientation_direction_types = {
  ["car"]                   = 0,
  ["tank"]                  = 0,
  ["locomotive"]            = 0,
  ["cargo-wagon"]           = 0,
  ["fluid-wagon"]           = 0,
  ["artillery-wagon"]       = 0,
  ["straight-rail"]               = 8,
  ["curved-rail-a"]               = 8,
  ["curved-rail-b"]               = 8,
  ["half-diagonal-rail"]          = 8,
  ["rail-ramp"]                   = 4,
  ["elevated-straight-rail"]      = 8,
  ["elevated-curved-rail-a"]      = 8,
  ["elevated-curved-rail-b"]      = 8,
  ["elevated-half-diagonal-rail"] = 8,
  ["legacy-straight-rail"]        = 8, -- has special cases handled elsewhere
  ["legacy-curved-rail"]          = 8, -- has special cases handled elsewhere
  ["rail-support"]          = 16,
  ["rail-signal"]           = 16,
  ["rail-chain-signal"]     = 16,
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
  [16] = 0.0625,
}

-- entities that exist on the 2x2 raigrid
local rail_entity_types = {
  ["straight-rail"]               = true,
  ["curved-rail-a"]               = true,
  ["curved-rail-b"]               = true,
  ["half-diagonal-rail"]          = true,
  ["rail-ramp"]                   = true,
  ["elevated-straight-rail"]      = true,
  ["elevated-curved-rail-a"]      = true,
  ["elevated-curved-rail-b"]      = true,
  ["elevated-half-diagonal-rail"] = true,
  ["legacy-straight-rail"]        = true,
  ["legacy-curved-rail"]          = true,
  ["rail-signal"]       = true,
  ["rail-chain-signal"] = true,
  ["train-stop"]        = true,
  ["locomotive"]        = true,
  ["cargo-wagon"]       = true,
  ["fluid-wagon"]       = true,
  ["artillery-wagon"]   = true,
}

-- entities that only support half of the valid directions because they are symmetric
local symmetric_rail_entity_types = {
  ["straight-rail"]               = true,
  ["half-diagonal-rail"]          = true,
  ["elevated-straight-rail"]      = true,
  ["elevated-half-diagonal-rail"] = true,
  ["legacy-straight-rail"]        = true,
  ["legacy-curved-rail"]          = true,
  ["rail-support"]                = true,
}

local function deghost_type(entity)
  return entity.type == "entity-ghost" and entity.ghost_type or entity.type
end

-- Starting at the north point of a circle and proceeding clockwise
-- alternating a b b a, so the order is a6 b6 b0 a0 a10 ...
local curved_rail_directions = { [0] = 6, nil, 0, nil, 10, nil, 4, nil, 14, nil, 8, nil, 2, nil, 12, nil }
-- crd[crdi[x]]==x, crdi[crd[x]]==x
local curved_rail_directions_inverse = { [0] = 2, nil, 12, nil, 6, nil, 0, nil, 10, nil, 4, nil, 14, nil, 8, nil }

---Rotate and/or mirror a given direction and orientation
---@param entity_type string
---@param dir defines.direction|integer direction of the entity [0-15]
---@param ori float orientation of the entity [0.0-1.0)
---@param sym_x boolean mirror in the X direction, across the Y axis
---@param sym_y boolean mirror in the Y direction, across the X axis
---@param sym_diag_1 boolean mirror across a northeast/southwest line
---@param sym_diag_2 boolean mirror across a northwest/southeast line
---@param reori float amount to rotate, 0 = none, 0.25 = 90 degrees clockwise
---@return defines.direction|integer|nil direction
---@return float orientation
local function get_mirrotated_entity_dir_ori(entity_type, dir, ori, sym_x, sym_y, sym_diag_1, sym_diag_2, reori)
  local od_type = orientation_direction_types[entity_type]
  if od_type == nil then
    return 0, 0
  end
  -- rail signals need to be rotated 180 if they are mirrored an odd number of times
  if (entity_type == "rail-signal" or entity_type == "rail-chain-signal") and
    (
      ( sym_x and 1 or 0 ) +
      ( sym_y and 1 or 0 ) +
      ( sym_diag_1 and 1 or 0 ) +
      ( sym_diag_2 and 1 or 0 )
    ) % 2 == 1
  then
    reori = ( (reori or 0) + 0.5 ) % 1
  end
  local curved_rail = entity_type:find"^curved%-rail" ~= nil or entity_type:find"^elevated%-curved%-rail" ~= nil
  if reori ~= 0 then -- rotation
    if od_type == 0 then
      return 0, (ori + reori) % 1
    end
    local dir_reori = reori
    local snap_ori = orientation_snap[orientation_direction_types[entity_type]]
    if snap_ori > 0 then -- round to nearest multiple of snap_ori
      dir_reori = math.floor((reori + (snap_ori / 2)) / snap_ori) * snap_ori
    end
    if curved_rail then
      dir = curved_rail_directions[ ( curved_rail_directions_inverse[ dir ] + dir_reori * 16 ) % 16 ]
      ori = direction_to_orientation[ dir ]
    else
      dir = (dir + dir_reori * 16) % 16
      ori = (ori + dir_reori) % 1
    end
  end
  if sym_x then
    if curved_rail then
      dir = curved_rail_directions[ 14 - curved_rail_directions_inverse[ dir ] ]
    else
      dir = ( 16 - dir ) % 16
      ori = ( 1 - ori ) % 1
    end
  end
  if sym_y then
    if curved_rail then
      dir = curved_rail_directions[ ( 6 - curved_rail_directions_inverse[ dir ] + 16 ) % 16 ]
    else
      dir = ( 24 - dir ) % 16
      ori = ( 1.5 - ori ) % 1
    end
  end
  if sym_diag_1 then
    if curved_rail then
      dir = curved_rail_directions[ ( 2 - curved_rail_directions_inverse[ dir ] + 16 ) % 16 ]
    else
      dir = ( 20 - dir ) % 16
      ori = ( 1.25 - ori ) % 1
    end
  end
  if sym_diag_2 then
    if curved_rail then
      dir = curved_rail_directions[ ( 10 - curved_rail_directions_inverse[ dir ] + 16 ) % 16 ]
    else
      dir = ( 28 - dir ) % 16
      ori = ( 1.75 - ori ) % 1
    end
  end
  if curved_rail then
    ori = direction_to_orientation[dir]
  end
  if od_type == 2 or symmetric_rail_entity_types[entity_type] then
    dir = dir % 8
    ori = ori % 0.5
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
  storage.cached_center_entities[script.register_on_object_destroyed(entity)] = entity
end

---@param control_behavior LuaConstantCombinatorControlBehavior
---@return boolean
local function control_behavior_fresh(control_behavior)
  for _, section in pairs( control_behavior.sections ) do
    if section.filters_count > 0 then
      return false
    end
  end
  return true
end

---Get a mod setting for a player, or the player default if they haven't set it.
---@param player LuaPlayer?
---@param setting string
---@return ModSetting
local function player_or_default_setting( player, setting )
  return player and player.mod_settings[setting]
  or settings.player_default[setting]
end

---@param event EventData.on_built_entity | EventData.on_entity_cloned | EventData.script_raised_built | EventData.script_raised_revive | EventData.on_cancelled_deconstruction | EventData.on_marked_for_deconstruction | EventData.on_player_mined_entity
---@param action any
---@param manual any
local function on_altered_entity(event, action, manual)
  local entity = event.entity or event.source
  local surface = entity.surface
  local centers = storage.cached_center_entities
  ---@type LuaPlayer?
  local player = event.player_index and game.players[event.player_index] or nil

  if entity.name == "symmetry-center" then
    if action == "create" then
      cache_center_entity(entity)
      if manual then
        local cb = entity.get_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
        if cb.sections_count == 0 then
          cb.add_section( "" )
        end
        -- FIXME temp until https://forums.factorio.com/viewtopic.php?f=7&t=116334 is fixed
        if control_behavior_fresh( cb ) then
          -- set some default signals for a new manually placed empty symmetry-center
          -- maybe this should also trigger for new empty symmetry-center ghosts?
          local section = cb.get_section( 1 )
          assert( section ~= nil )
          section.set_slot( 1, {
            -- FIXME quality here is a workaround for https://forums.factorio.com/viewtopic.php?f=7&t=116334
            value = { type="virtual", name="signal-C", quality="normal" },
            min = player_or_default_setting( player, 'entity-symmetry-default-center' ).value --[[@as integer]]
          })
          section.set_slot( 2, {
            value = { type="virtual", name="signal-D", quality="normal" },
            min = player_or_default_setting( player, 'entity-symmetry-default-distance' ).value --[[@as integer]]
          })
          section.set_slot( 3, {
            value = { type="virtual", name="signal-R", quality="normal" },
            min = player_or_default_setting( player, 'entity-symmetry-default-rails' ).value --[[@as integer]]
          })
          section.set_slot( 4, {
            value = { type="virtual", name="signal-S", quality="normal" },
            min = player_or_default_setting( player, 'entity-symmetry-default-symmetry' ).value --[[@as integer]]
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
          local center_dir = ( player_or_default_setting( player, 'entity-symmetry-default-center' ).value )
          local range = ( player_or_default_setting( player, 'entity-symmetry-default-distance' ).value )
          local configured_rail_mode = ( player_or_default_setting( player, 'entity-symmetry-default-rails' ).value )
          local rot_symmetry = ( player_or_default_setting( player, 'entity-symmetry-default-symmetry' ).value )
          local xaxis_mirror = false
          local yaxis_mirror = false
          local diag1_mirror = false
          local diag2_mirror = false
          local include = {}
          local exclude = {}
          local cb = center_entity.get_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
          if not cb.enabled then goto next_center_entity end
          local rail_signal_slot = 3

          for index, filter in pairs(cb.get_section(1).filters) do
            if filter.value.name then
              if filter.value.name == "signal-C" then
                -- move the [C]enter point to an edge/corner of the tile
                center_dir = filter.min
              elseif filter.value.name == "signal-D" then
                -- set the [D]istance/range
                range = filter.min
              elseif filter.value.name == "signal-R" then
                -- optionally turn on or off [R]ail mode for all entities
                configured_rail_mode = filter.min
                rail_signal_slot = index
              elseif filter.value.name == "signal-S" then
                -- type and degree/axes of [S]ymmetry
                if filter.min >= 0 then -- rotational symmetry degree
                  rot_symmetry = filter.min
                else -- mirroring, x/y axes, diagonals
                  rot_symmetry = 0
                  if bit32.band(1, -filter.min) > 0 then xaxis_mirror = true end
                  if bit32.band(2, -filter.min) > 0 then yaxis_mirror = true end
                  if bit32.band(4, -filter.min) > 0 then diag1_mirror = true end
                  if bit32.band(8, -filter.min) > 0 then diag2_mirror = true end
                end
              elseif filter.value.type == "item" then
                -- negative item signals exclude the item
                -- positive filter for just those items
                if filter.min < 0 then
                  exclude.some = true
                  exclude[filter.value.name] = true
                else
                  include.some = true
                  include[filter.value.name] = true
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
                  cb.get_section( 1 ).set_slot( rail_signal_slot, { value = { type = "virtual", name = "signal-R", quality = "normal" }, min = 1 })
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
              ---@type [ defines.direction | integer ]
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
                      true, false, false, false, 0
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
                      false, true, false, false, 0
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
                    local dir, ori = get_mirrotated_entity_dir_ori(
                      deghost_type(entity),
                      directions[n],
                      orientations[n],
                      false, false, true, false, 0
                    )
                    directions[#directions + 1] = dir
                    orientations[#orientations + 1] = ori
                  end
                end
                if diag2_mirror then
                  for n = 1, #positions do
                    local new_position = table.deepcopy(positions[n])
                    new_position.x, new_position.y =
                      center_position.x + (new_position.y - center_position.y),
                      center_position.y + (new_position.x - center_position.x)
                    positions[#positions + 1] = new_position
                    local dir, ori = get_mirrotated_entity_dir_ori(
                      deghost_type(entity),
                      directions[n],
                      orientations[n],
                      false, false, false, true, 0
                    )
                    directions[#directions + 1] = dir
                    orientations[#orientations + 1] = ori
                  end
                end
              elseif rot_symmetry > 1 then -- rotational symmetry instead of mirroring
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
                    false, false, false, false, r * (1 / rot_symmetry)
                  )
                  directions[#directions + 1] = dir
                  orientations[#orientations + 1] = ori
                end
              end
              local cheat = settings.global["entity-symmetry-allow-cheat"].value and player and player.mod_settings["entity-symmetry-cheat"].value
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
                    pcall(function () entity_def.rail_layer = entity.rail_layer end)
                    pcall(function () entity_def.recipe = entity.get_recipe().name end)
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
                                  elseif player then
                                    if action == "destroy" or action == "deconstruct_marked" then
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

local function on_object_destroyed(event)
  storage.cached_center_entities[event.registration_number] = nil
end

local function on_configuration_changed(event)
  if storage.cached_center_entities == nil then
    storage.cached_center_entities = {}
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

-- removal of symmetry-center is handled by registering entity-specific destruction events when they are created
-- so we only need to watch for player mining or marking entities to trigger symmetric removal/marking
script.on_event(defines.events.on_player_mined_entity, function(event) on_altered_entity(event, "destroy", true) end)
script.on_event(defines.events.on_cancelled_deconstruction,  function(event) on_altered_entity(event, "deconstruct_canceled", true) end)
script.on_event(defines.events.on_marked_for_deconstruction, function(event) on_altered_entity(event, "deconstruct_marked", true) end)
script.on_event(defines.events.on_object_destroyed, on_object_destroyed)


script.on_init(on_configuration_changed)
script.on_configuration_changed(on_configuration_changed)

-- local debugnum = 0
-- local function debug_write(...)
--   if game and game.players[1] then
--     game.players[1].print("DEBUG " .. debugnum .. " " .. game.tick .. ": " .. serpent.line(..., {comment=false}))
--     debugnum = debugnum + 1
--   end
-- end

