data:extend(
{
  {
    type = "recipe",
    name = "symmetry-center",
    enabled = true,
    result = "symmetry-center",
    ingredients = {},
  },
  {
    type = "item",
    name = "symmetry-center",
    icon = "__base__/graphics/icons/signal/shape_square.png",
    icon_size = 32,
    place_result = "symmetry-center",
    subgroup = "circuit-network",
    order = "c[combinators]-z[symmetry-center]",
    stack_size = 10
  },
})

local entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
entity.name = "symmetry-center"
entity.icon = "__base__/graphics/icons/signal/shape_square.png"
entity.minable = {hardness = 0.1, mining_time = 0.5, result = "symmetry-center"}
entity.max_health = 1000
entity.collision_mask = {"layer-14"} -- only collide with itself and unlucky other mods
data:extend({entity})
