require "util"

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
  return math.floor(ori * 8 + 0.5)
end

local direction_curvedrail_mirror_x =
  {[N]=NE,[NE]=N,[E]=NW,[SE]=W,[S]=SW,[SW]=S,[W]=SE,[NW]=E}
local direction_curvedrail_mirror_y =
  {[N]=SW,[NE]=S,[E]=SE,[SE]=E,[S]=NE,[SW]=N,[W]=NW,[NW]=W}

-- how many directions/orientations can each entity type point
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
  ["storage-tank"]          = 2,
  ["steam-engine"]          = 2,
  ["steam-turbine"]         = 2,
}

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

local orientation_snap = {[0.125]={}, [0.25]={}}

for entity_type, od_type in pairs(orientation_direction_types) do
  if od_type == 8 then
    orientation_snap[0.125][entity_type] = true
  elseif od_type == 4 or od_type == 2 then
    orientation_snap[0.25][entity_type] = true
  end
end

local function get_mirrotated_entity_dir_ori(entity_type, dir, ori, sym_x, sym_y, reori)
  if not orientation_direction_types[entity_type] then return 0,0 end
  if reori then -- rotation
    local od_type = orientation_direction_types[entity_type]
    if od_type == 0 then
      return 0, (ori + reori)%1
    end
    local dir_reori = reori
    local snap_ori = 0
    if orientation_snap[0.25][entity_type] then
      snap_ori = 0.25
    elseif orientation_snap[0.125][entity_type] then
      snap_ori = 0.125
    end
    if snap_ori then -- round to nearest multiple of snap_ori
      dir_reori = math.floor((reori + (snap_ori/2))/snap_ori)*snap_ori
    end
    dir = (dir + dir_reori*8)%8
    ori = (ori + dir_reori)%1
  else -- mirroring
    if entity_type == "curved-rail" then
      if sym_x then
        dir = direction_curvedrail_mirror_x[dir]
      end
      if sym_y then
        dir = direction_curvedrail_mirror_y[dir]
      end
      ori = direction_to_orientation[dir]
    else
      if sym_x then
        dir = (8 - dir)%8
        ori = (1 - ori)%1
      end
      if sym_y then
        dir = ((8-((dir-2)%8))+2)%8
        ori = ((1-((ori-0.25)%1))+0.25)%1
      end
    end
  end
  if od_type == 2 or entity_type == "straight-rail" then
    -- these types never point south/west
    if dir==4 or dir==6 then dir = dir - 4 end
    if ori==0.5 or ori==0.75 then ori = ori - 0.5 end
  end
  return dir, ori
end

local function orient_position_relative(center, position, orientation)
  delta = table.deepcopy(position)
  delta.x = delta.x - center.x
  delta.y = delta.y - center.y
  orientation = orientation%1
  if orientation == 0.5 then
    -- easy
    delta.x = -delta.x
    delta.y = -delta.y
  elseif orientation == 0.25 then
    local temp_y = delta.y
    delta.y = delta.x
    delta.x = -temp_y
  elseif orientation == 0.75 then
    local temp_y = delta.y
    delta.y = -delta.x
    delta.x = temp_y
  elseif orientation == 0 then
    -- nothing
  else
    -- trig time
    local magnitude = (delta.x * delta.x + delta.y * delta.y) ^ 0.5
    angle = orientation * math.pi * 2
    angle = math.atan2(delta.x, delta.y) + angle
    delta.x = math.sin(angle) * magnitude
    delta.y = math.cos(angle) * magnitude
  end
  delta.x = delta.x + center.x
  delta.y = delta.y + center.y
  return delta
end

local function on_altered_entity(params)
  local event = params.event
  local entity = event.created_entity and event.created_entity or event.entity
  --TODO mod settings for defaults
  if entity.name == "symmetry-center" and params.action == "built" then
    local cb = entity.get_control_behavior()
    if cb.get_signal(1).signal == nil then
      cb.set_signal(1, {signal={type="virtual",name="signal-C"}, count="-1"})
    end
    if cb.get_signal(2).signal == nil then
      cb.set_signal(2, {signal={type="virtual",name="signal-D"}, count="64"})
    end
    if cb.get_signal(3).signal == nil then
      cb.set_signal(3, {signal={type="virtual",name="signal-R"}, count="0"})
    end
    if cb.get_signal(4).signal == nil then
      cb.set_signal(4, {signal={type="virtual",name="signal-M"}, count="0"})
    end
    if cb.get_signal(5).signal == nil then
      cb.set_signal(5, {signal={type="virtual",name="signal-X"}, count="3"})
    end
    if cb.get_signal(6).signal == nil then
      cb.set_signal(6, {signal={type="virtual",name="signal-S"}, count="4"})
    end
  end
  local surface = entity.surface
  local centers = surface.find_entities_filtered{name="symmetry-center"}
  local rail_entity = rail_entity_types[entity.type]
  local rail_mode = rail_entity
  for _,center_entity in ipairs(centers) do
    if center_entity == entity then goto next_center_entity end
    --TODO mod settings for defaults
    local center_dir = -1
    local range = 64
    local configured_rail_mode = 0
    local symmetry = 4
    local mirror = false
    local xaxis_mirror = true
    local yaxis_mirror = true
    local include = {}
    local exclude = {}
    local cb = center_entity.get_control_behavior()
    for n=1,cb.signals_count do
      local sig = cb.get_signal(n)
      if sig.signal then
        if sig.signal.name == "signal-C" then
          -- move the [C]enter point to an edge/corner of the tile
          center_dir = sig.count
        elseif sig.signal.name == "signal-D" then
          -- set the [D]istance/range
          range = sig.count
        elseif sig.signal.name == "signal-R" then
          -- optionally turn on or off [R]ail mode for all entities
          configured_rail_mode = sig.count
        elseif sig.signal.name == "signal-S" then
          -- Degree of rotational [S]ymmetry
          symmetry = sig.count
        elseif sig.signal.name == "signal-M" then
          -- [M]irror or rotate(default)
          if sig.count > 0 then
            mirror = true
          end
        elseif sig.signal.name == "signal-X" then
          -- set mirroring a[X]es
          if     sig.count == 0 then
            xaxis_mirror = false
            yaxis_mirror = false
          elseif sig.count == 1 then
            xaxis_mirror = true
            yaxis_mirror = false
          elseif sig.count == 2 then
            xaxis_mirror = false
            yaxis_mirror = true
          elseif sig.count == 3 then
            xaxis_mirror = true
            yaxis_mirror = true
          end
        elseif sig.signal.type == "item" then
          -- negative item signals exclude the item
          -- positive filter for just those items
          if sig.count < 0 then
            exclude.some = true
            exclude[sig.signal.name] = true
          else
            include.some = true
            include[sig.signal.name] = true
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
            cb.set_signal(3, {signal={type="virtual",name="signal-R"}, count="1"})
          end
        elseif configured_rail_mode > 0 then
          rail_mode = true
        end
        if center_dir >=0 and center_dir <= 7 then
          -- move the [C]enter point to an edge/corner of the tile
          if     center_dir == 1 then
            center_position.x = center_position.x + (rail_mode and 1 or 0.5)
            center_position.y = center_position.y - (rail_mode and 1 or 0.5)
          elseif center_dir == 3 then
            center_position.x = center_position.x + (rail_mode and 1 or 0.5)
            center_position.y = center_position.y + (rail_mode and 1 or 0.5)
          elseif center_dir == 5 then
            center_position.x = center_position.x - (rail_mode and 1 or 0.5)
            center_position.y = center_position.y + (rail_mode and 1 or 0.5)
          elseif center_dir == 7 then
            center_position.x = center_position.x - (rail_mode and 1 or 0.5)
            center_position.y = center_position.y - (rail_mode and 1 or 0.5)
          elseif center_dir == 0 then
            center_position.y = center_position.y - (rail_mode and 1 or 0.5)
          elseif center_dir == 2 then
            center_position.x = center_position.x + (rail_mode and 1 or 0.5)
          elseif center_dir == 4 then
            center_position.y = center_position.y + (rail_mode and 1 or 0.5)
          elseif center_dir == 6 then
            center_position.x = center_position.x - (rail_mode and 1 or 0.5)
          end
        end
        local positions = {table.deepcopy(entity.position)}
        local directions = {entity.direction}
        local orientations = {entity.orientation}
        if mirror then
          if xaxis_mirror then
            for n=1,#positions do
              local new_position = table.deepcopy(positions[n])
              new_position.x = center_position.x - (new_position.x - center_position.x)
              positions[#positions+1] = new_position
              local dir, ori = get_mirrotated_entity_dir_ori(
                entity.type,
                directions[n],
                orientations[n],
                true, false, false
              )
              directions[#directions+1] = dir
              orientations[#orientations+1] = ori
            end
          end
          if yaxis_mirror then
            for n=1,#positions do
              local new_position = table.deepcopy(positions[n])
              new_position.y = center_position.y - (new_position.y - center_position.y)
              positions[#positions+1] = new_position
              local dir, ori = get_mirrotated_entity_dir_ori(
                entity.type,
                directions[n],
                orientations[n],
                false, true, false
              )
              directions[#directions+1] = dir
              orientations[#orientations+1] = ori
            end
          end
        else -- rotation instead of mirroring
          if symmetry > 1 then
            local rot_direction = directions[1]
            local rot_orientation = orientations[1]
            for r=1,symmetry-1 do
              positions[#positions+1] = orient_position_relative(
                center_position,
                positions[1],
                r/symmetry
              )
              local dir, ori = get_mirrotated_entity_dir_ori(
                entity.type,
                directions[1],
                orientations[1],
                false, false, r*(1/symmetry)
              )
              directions[#directions+1] = dir
              orientations[#orientations+1] = ori
            end
          end
        end
        -- now actually make or remove the additional entities
        for n=2,#positions do
          if params.action == "built" then
            local pos = positions[n]
            local dir = entity.supports_direction and directions[n] or 0
            if orientation_direction_types[entity.type] == 0 then
              -- smooth turning entities are spawned with a direction
              dir = orientation_to_direction(orientations[n])
            end
            surface.create_entity{
              name = entity.name,
              position = pos,
              direction = dir,
              force = entity.force,
              --TODO type-specific attributes
            }
          elseif params.action == "player_mined" then
            local found_entities = surface.find_entities_filtered{
              area = {{positions[n].x-0.5,positions[n].y-0.5},{positions[n].x+0.5,positions[n].y+0.5}},
              name = entity.name,
              type = entity.type,
              force = entity.force.name,
            }
            if #found_entities then
              for _,found_entity in ipairs(found_entities) do
                if found_entity.position.x == positions[n].x and found_entity.position.y == positions[n].y then
                  if found_entity.orientation == orientations[n] then
                    if (not entity.supports_direction) or (found_entity.direction == directions[n]) then
                      found_entity.destroy()
                    end
                  end
                end
              end
            else
              -- debug("no centers to delete")
            end
          else
            -- debug("unrecognized action " .. params.action)
          end
        end
      end
    end
    ::next_center_entity::
  end
end

local function on_built_entity(event)
  on_altered_entity{event = event, action = "built"}
end

local function on_player_mined_entity(event)
  on_altered_entity{event = event, action = "player_mined"}
end

--TODO handle bots
--TODO handle rotation and reconfiguration events for entities
--TODO handle script_raised_built script_raised_destroy
script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.on_player_mined_entity, on_player_mined_entity)

-- local debugnum = 0
-- local function debug(...)
--   if game and game.players[1] then
--     game.players[1].print("DEBUG " .. debugnum .. " " .. game.tick .. ": " .. serpent.line(...,{comment=false}))
--     debugnum = debugnum + 1
--   end
-- end

