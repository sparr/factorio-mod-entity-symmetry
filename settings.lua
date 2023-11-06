data:extend(
  {
    {
      type          = "int-setting",
      name          = "entity-symmetry-default-center",
      setting_type  = "runtime-per-user",
      default_value = -1,
      minimum_value = -1,
      maximum_value = 7,
    },
    {
      type          = "int-setting",
      name          = "entity-symmetry-default-distance",
      setting_type  = "runtime-per-user",
      default_value = 64,
      minimum_value = 0,
    },
    {
      type           = "int-setting",
      name           = "entity-symmetry-default-rails",
      setting_type   = "runtime-per-user",
      default_value  = 0,
      allowed_values = {0, -1, 1},
    },
    {
      type          = "int-setting",
      name          = "entity-symmetry-default-symmetry",
      setting_type  = "runtime-per-user",
      default_value = 4,
      minimum_value = -15,
    },
    {
      type          = "bool-setting",
      name          = "entity-symmetry-allow-cheat",
      setting_type  = "runtime-global",
      default_value = false,
    },
    {
      type          = "bool-setting",
      name          = "entity-symmetry-cheat",
      setting_type  = "runtime-per-user",
      default_value = false,
    },
  }
)
