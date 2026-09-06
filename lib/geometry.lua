--- Direction and orientation maths, extracted from control.lua so it can be unit tested.
--- Nothing here touches the game state: it depends only on defines.direction and
--- table.deepcopy, both of which the unit tests stub.
---
--- Concepts, repeated from control.lua:
--- "direction" is an integer, 0-15, N, NNE, NE, ... NW, NNW
--- "orientation" is a float, 0 = North, 0.25 = East, 0.5 = South, 0.75 = West
--- +x is East, +y is South

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
  ["assembling-machine"]    = 4,
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

-- entities that exist on the 2x2 rail grid
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

local supports_mirroring = {
  ["assembling-machine-1"] = true,
  ["oil-refinery"]         = true,
  ["chemical-plant"]       = true,
  ["centrifuge"]           = true,
}

---Type of the entity, or the entity inside an entity ghost
---@param entity LuaEntity
---@return string
local function deghost_type(entity)
  return entity.type == "entity-ghost" and entity.ghost_type or entity.type
end

---Name of the entity, or the entity inside an entity ghost
---@param entity LuaEntity
---@return string
local function deghost_name(entity)
  return entity.type == "entity-ghost" and entity.ghost_name or entity.name
end

-- Starting at the north point of a circle and proceeding clockwise
-- alternating a b b a, so the order is a6 b6 b0 a0 a10 ...
local curved_rail_directions = { [0] = 6, nil, 0, nil, 10, nil, 4, nil, 14, nil, 8, nil, 2, nil, 12, nil }
-- crd[crdi[x]]==x, crdi[crd[x]]==x
local curved_rail_directions_inverse = { [0] = 2, nil, 12, nil, 6, nil, 0, nil, 10, nil, 4, nil, 14, nil, 8, nil }

---Perform a horizontal flip of a given direction and orientation
---@param dir defines.direction|integer direction [0-15]
---@param ori float orientation [0-1)
---@param curved_rail boolean is this a curved rail?
---@return defines.direction|integer direction
---@return float orientation
local function flip_h( dir, ori, curved_rail )
  if curved_rail then
    dir = curved_rail_directions[ 14 - curved_rail_directions_inverse[ dir ] ]
    assert( dir ~= nil )
  else
    dir = ( 16 - dir ) % 16
    ori = ( 1 - ori ) % 1
  end
  return dir, ori
end

---Perform a vertical flip of a given direction and orientation
---@param dir defines.direction|integer direction [0-15]
---@param ori float orientation [0-1)
---@param curved_rail boolean is this a curved rail?
---@return defines.direction|integer direction
---@return float orientation
local function flip_v( dir, ori, curved_rail )
  if curved_rail then
    dir = curved_rail_directions[ ( 6 - curved_rail_directions_inverse[ dir ] + 16 ) % 16 ]
    assert( dir ~= nil )
  else
    dir = ( 24 - dir ) % 16
    ori = ( 1.5 - ori ) % 1
  end
return dir, ori
end

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
---@return boolean flip whether the target should be flipped
local function get_mirrotated_entity_dir_ori(entity_type, entity_name, dir, ori, sym_x, sym_y, sym_diag_1, sym_diag_2, reori)
  local od_type = orientation_direction_types[entity_type]
  if od_type == nil then
    return 0, 0, false
  end
  local flip = supports_mirroring[entity_name] and
  (
    ( sym_x and 1 or 0 ) +
    ( sym_y and 1 or 0 ) +
    ( sym_diag_1 and 1 or 0 ) +
    ( sym_diag_2 and 1 or 0 )
  ) % 2 == 1
  or
  false
  -- rail signals need to be rotated 180 if they are mirrored an odd number of times
  if (entity_type == "rail-signal" or entity_type == "rail-chain-signal") and flip then
    reori = ( (reori or 0) + 0.5 ) % 1
  end
  local curved_rail = entity_type:find"^curved%-rail" ~= nil or entity_type:find"^elevated%-curved%-rail" ~= nil
  if reori ~= 0 then -- rotation
    if od_type == 0 then
      return 0, (ori + reori) % 1, false
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
    dir, ori = flip_h( dir, ori, curved_rail )
  end
  if sym_y then
    dir, ori = flip_v( dir, ori, curved_rail )
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
  return dir, ori, flip
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

return {
    direction_to_orientation = direction_to_orientation,
    orientation_to_direction = orientation_to_direction,
    orientation_direction_types = orientation_direction_types,
    orientation_snap = orientation_snap,
    rail_entity_types = rail_entity_types,
    symmetric_rail_entity_types = symmetric_rail_entity_types,
    supports_mirroring = supports_mirroring,
    deghost_type = deghost_type,
    deghost_name = deghost_name,
    curved_rail_directions = curved_rail_directions,
    curved_rail_directions_inverse = curved_rail_directions_inverse,
    flip_h = flip_h,
    flip_v = flip_v,
    get_mirrotated_entity_dir_ori = get_mirrotated_entity_dir_ori,
    orient_position_relative = orient_position_relative,
}
