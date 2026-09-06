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

local geometry = require("lib.geometry")
local orbit = require("lib.orbit")

local direction_to_orientation = geometry.direction_to_orientation
local orientation_to_direction = geometry.orientation_to_direction
local orientation_direction_types = geometry.orientation_direction_types
local orientation_snap = geometry.orientation_snap
local rail_entity_types = geometry.rail_entity_types
local symmetric_rail_entity_types = geometry.symmetric_rail_entity_types
local supports_mirroring = geometry.supports_mirroring
local deghost_type = geometry.deghost_type
local deghost_name = geometry.deghost_name
local curved_rail_directions = geometry.curved_rail_directions
local curved_rail_directions_inverse = geometry.curved_rail_directions_inverse
local flip_h = geometry.flip_h
local flip_v = geometry.flip_v
local get_mirrotated_entity_dir_ori = geometry.get_mirrotated_entity_dir_ori
local orient_position_relative = geometry.orient_position_relative
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

---Entities in `area` that are the same thing as `entity`, whether either side is a ghost.
---A ghost is named entity-ghost with the real name in ghost_name, so filtering on
---entity.name alone never matches a real entity against its ghost copies (issue #13).
---@param surface LuaSurface
---@param area BoundingBox
---@param entity LuaEntity
---@return LuaEntity[]
local function sibling_candidates(surface, area, entity)
  local want_name, want_type = deghost_name(entity), deghost_type(entity)
  local found = {}
  for _, candidate in pairs(surface.find_entities_filtered{
    area = area, force = entity.force.name,
  }) do
    if candidate.valid
      and deghost_name(candidate) == want_name
      and deghost_type(candidate) == want_type
    then
      found[#found + 1] = candidate
    end
  end
  return found
end

---@param event EventData.on_built_entity | EventData.on_entity_cloned | EventData.script_raised_built | EventData.script_raised_revive | EventData.on_cancelled_deconstruction | EventData.on_marked_for_deconstruction | EventData.on_player_mined_entity | EventData.on_player_rotated_entity | EventData.on_player_flipped_entity
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
              local flips = {entity.mirroring}
              if action == "modify" then
                -- search for matching entities should use the prior state of the entity
                if event.previous_direction then
                  -- rotation event
                  directions[1] = event.previous_direction
                  orientations[1] = direction_to_orientation[ directions[1] ]
                elseif event.horizontal ~= nil then
                  -- flip event
                  flips[1] = not flips[1]
                  local curved_rail = entity.type:find"^curved%-rail" ~= nil or entity.type:find"^elevated%-curved%-rail" ~= nil
                  if event.horizontal then
                    directions[1], orientations[1] = flip_h( directions[1], orientations[1], curved_rail )
                  else
                    directions[1], orientations[1] = flip_v( directions[1], orientations[1], curved_rail )
                  end
                end
              end
              if rot_symmetry == 0 then
                if xaxis_mirror then
                  for n = 1, #positions do
                    local new_position = table.deepcopy(positions[n])
                    new_position.x = center_position.x - (new_position.x - center_position.x)
                    positions[#positions + 1] = new_position
                    local dir, ori, flip = get_mirrotated_entity_dir_ori(
                      deghost_type(entity),
                      deghost_name(entity),
                      directions[n],
                      orientations[n],
                      true, false, false, false, 0
                    )
                    directions[#directions + 1] = dir
                    orientations[#orientations + 1] = ori
                    flips[#flips + 1] = entity.mirroring ~= flip
                  end
                end
                if yaxis_mirror then
                  for n = 1, #positions do
                    local new_position = table.deepcopy(positions[n])
                    new_position.y = center_position.y - (new_position.y - center_position.y)
                    positions[#positions + 1] = new_position
                    local dir, ori, flip = get_mirrotated_entity_dir_ori(
                      deghost_type(entity),
                      deghost_name(entity),
                      directions[n],
                      orientations[n],
                      false, true, false, false, 0
                    )
                    directions[#directions + 1] = dir
                    orientations[#orientations + 1] = ori
                    flips[#flips + 1] = entity.mirroring ~= flip
                  end
                end
                if diag1_mirror then
                  for n = 1, #positions do
                    local new_position = table.deepcopy(positions[n])
                    new_position.x, new_position.y =
                      center_position.x - (new_position.y - center_position.y),
                      center_position.y - (new_position.x - center_position.x)
                    positions[#positions + 1] = new_position
                    local dir, ori, flip = get_mirrotated_entity_dir_ori(
                      deghost_type(entity),
                      deghost_name(entity),
                      directions[n],
                      orientations[n],
                      false, false, true, false, 0
                    )
                    directions[#directions + 1] = dir
                    orientations[#orientations + 1] = ori
                    flips[#flips + 1] = entity.mirroring ~= flip
                  end
                end
                if diag2_mirror then
                  for n = 1, #positions do
                    local new_position = table.deepcopy(positions[n])
                    new_position.x, new_position.y =
                      center_position.x + (new_position.y - center_position.y),
                      center_position.y + (new_position.x - center_position.x)
                    positions[#positions + 1] = new_position
                    local dir, ori, flip = get_mirrotated_entity_dir_ori(
                      deghost_type(entity),
                      deghost_name(entity),
                      directions[n],
                      orientations[n],
                      false, false, false, true, 0
                    )
                    directions[#directions + 1] = dir
                    orientations[#orientations + 1] = ori
                    flips[#flips + 1] = entity.mirroring ~= flip
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
                    deghost_name(entity),
                    directions[1],
                    orientations[1],
                    false, false, false, false, r * (1 / rot_symmetry)
                  )
                  directions[#directions + 1] = dir
                  orientations[#orientations + 1] = ori
                  flips[#flips + 1] = flips[1]
                end
              end
              local cheat = settings.global["entity-symmetry-allow-cheat"].value and player and player.mod_settings["entity-symmetry-cheat"].value

              -- Removing is not the reverse of placing. A copy was placed by rotating and
              -- then snapping to the placement grid, and rotate-then-snap is not a group
              -- operation, so rotating the removed entity's own position gives positions
              -- that can miss its siblings by up to a diagonal tile -- which is why S=2 and
              -- S=4 worked and nothing else did (issue #2). Ask lib/orbit which placement
              -- best explains what is actually on the ground instead.
              if rot_symmetry > 1 and action ~= "create" then
                local proto = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
                local snap = orbit.snapper(proto.tile_width or 1, proto.tile_height or 1)
                local function occupied(position)
                  local candidates = sibling_candidates(surface, {
                    {position.x - 0.6, position.y - 0.6},
                    {position.x + 0.6, position.y + 0.6},
                  }, entity)
                  for _, candidate in pairs(candidates) do
                    if candidate ~= entity then return candidate end
                  end
                  return nil
                end
                local recovered = orbit.choose(center_position, positions[1], rot_symmetry, snap, occupied)
                -- keep the entity's own slot first, as the loop below skips index 1
                local reordered = { positions[1] }
                local own = orbit.key(positions[1])
                for _, position in ipairs(recovered) do
                  if orbit.key(position) ~= own then reordered[#reordered + 1] = position end
                end
                positions = reordered
                -- copies of a rotation share the original's direction handling, and the
                -- removal path only compares direction when the entity supports it
                for n = #directions + 1, #positions do
                  directions[n] = directions[math.min(n, #directions)] or directions[1]
                  orientations[n] = orientations[math.min(n, #orientations)] or orientations[1]
                  flips[n] = flips[math.min(n, #flips)] or flips[1]
                end
              end

              -- now actually make or remove the additional entities
              for n = 2, #positions do
                if action == "create" then
                  local pos = positions[n]
                  local dir = entity.supports_direction and directions[n] or 0
                  local flip = flips[n]
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
                      mirroring = flip, -- pending https://forums.factorio.com/viewtopic.php?f=28&t=117626
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
                    log(serpent.line(entity_def))
                    local new_entity = surface.create_entity(entity_def)
                    if new_entity then -- creation may have failed for duplicates/collisions
                      if flip then
                        -- workaround for https://forums.factorio.com/viewtopic.php?f=7&t=117633
                        new_entity.mirroring = flip
                      end
                      if cheat and entity.name == "symmetry-center" then
                        new_centers[#new_centers+1] = new_entity
                      end
                    end
                  end
                elseif action == "destroy" or action == "deconstruct_canceled" or action == "deconstruct_marked" or action == "modify" then
                  local found_entities = sibling_candidates(surface, {
                    {positions[n].x - 0.5, positions[n].y - 0.5},
                    {positions[n].x + 0.5, positions[n].y + 0.5},
                  }, entity)
                  if #found_entities > 0 then
                    for _, found_entity in ipairs(found_entities) do
                      if found_entity.valid then
                        if found_entity.position.x == positions[n].x and found_entity.position.y == positions[n].y then
                          if found_entity.orientation == orientations[n] then
                            if found_entity.mirroring == flips[n] then
                              if (not entity.supports_direction) or (found_entity.direction == directions[n]) then
                                if found_entity ~= entity then
                                  do
                                    if action == "destroy" or action == "deconstruct_canceled" or action == "deconstruct_marked" then
                                      if (cheat and action == "destroy") or entity.type == "entity-ghost" then
                                        found_entity.destroy()
                                      elseif player then
                                        if action == "destroy" or action == "deconstruct_marked" then
                                          found_entity.order_deconstruction(player.force, player)
                                        elseif action == "deconstruct_canceled" then
                                          found_entity.cancel_deconstruction(player.force, player)
                                        end
                                      end
                                    elseif action == "modify" then
                                      if event.previous_direction then
                                        -- rotation event
                                        found_entity.direction = ( found_entity.direction + entity.direction - event.previous_direction ) % 16
                                      elseif event.horizontal ~= nil then
                                        -- flip event
                                        local curved_rail = entity.type:find"^curved%-rail" ~= nil or entity.type:find"^elevated%-curved%-rail" ~= nil
                                        found_entity.mirroring = not found_entity.mirroring
                                        if event.horizontal then
                                          found_entity.direction, found_entity.orientation = flip_h( found_entity.direction, found_entity.orientation, curved_rail )
                                        else
                                          found_entity.direction, found_entity.orientation = flip_v( found_entity.direction, found_entity.orientation, curved_rail )
                                        end
                                      else
                                        -- debug_write("unrecognized action " .. params.action)
                                      end
                                    else
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

script.on_event(defines.events.on_player_rotated_entity, function(event) on_altered_entity(event, "modify", true) end)
script.on_event(defines.events.on_player_flipped_entity, function(event) on_altered_entity(event, "modify", true) end)

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

--- The integration tier, which runs inside a live game rather than against stubs.
--- es-tests is never published, so this can never fire on a player's machine -- which
--- matters, because info.json keeps test/ out of the package.
if script.active_mods["factorio-test"] and script.active_mods["es-tests"] then
    require("__factorio-test__/init")({
        "test.ft.rotational",
        "test.ft.ghosts",
    }, {
        load_luassert = true,
        game_speed = 100,
    })
end
