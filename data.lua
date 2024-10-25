data:extend(
{
  {
    type = "recipe",
    name = "symmetry-center",
    enabled = true,
    results = { { type = "item", name = "symmetry-center", amount = 1 } },
    ingredients = {},
  },
  {
    type = "item",
    name = "symmetry-center",
    icon = "__base__/graphics/icons/shapes/shape-circle.png",
    icon_size = 64,
    place_result = "symmetry-center",
    subgroup = "circuit-network",
    order = "c[combinators]-z[symmetry-center]",
    stack_size = 10
  },
})

local entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
entity.name = "symmetry-center"
entity.icon = "__base__/graphics/icons/shapes/shape-circle.png"
entity.icon_size = 64
entity.sprites.north = { filename = "__base__/graphics/icons/shapes/shape-circle.png", size = 64, scale = 0.5 }
entity.sprites.east  = entity.sprites.north
entity.sprites.south = entity.sprites.north
entity.sprites.west  = entity.sprites.north
entity.minable = {hardness = 0.1, mining_time = 0.5, result = "symmetry-center"}
entity.max_health = 1000
-- FIXME doesn't self collide currently https://forums.factorio.com/viewtopic.php?f=28&t=117486
entity.collision_mask = { layers = {} }  -- only collides with itself
data:extend({entity})
