--- Shared ground for the integration fixtures. factorio-test does not reset the world
--- between tests, so a test that wants clean ground asks for a patch.

local world = {}

world.CENTER = "symmetry-center"
world.SUBJECT = "wooden-chest"     -- no direction, no mirroring: the simplest thing to copy

local next_patch = 0

--- A fresh square of lab tiles well away from anything else, with a symmetry centre in
--- the middle configured by the signals the mod reads:
---   S  symmetry: positive is a rotational degree, negative is a mirror bitmask
---   D  distance/range in tiles
--- Copies are placed as ghosts unless the player can pay for them. Cheat mode makes the
--- mod place real entities, which is the case issue #2 describes and the only way to
--- exercise the removal path -- the removal search filters by entity name, so it never
--- matches a ghost. The mod owns both settings, so a fixture registered from the mod may
--- write them.
---@param opts table {symmetry = integer, range = integer, cheat = boolean}
function world.patch(opts)
    opts = opts or {}
    local surface = game.surfaces[1]
    local cheat = opts.cheat
    if cheat == nil then cheat = true end
    settings.global["entity-symmetry-allow-cheat"] = { value = cheat }
    local player = game.players[1]
    if player then player.mod_settings["entity-symmetry-cheat"] = { value = cheat } end
    next_patch = next_patch + 1
    local origin = { x = next_patch * 64, y = 0 }
    local half = 24

    local area = {{ origin.x - half, origin.y - half }, { origin.x + half, origin.y + half }}
    local tiles = {}
    for x = origin.x - half, origin.x + half do
        for y = origin.y - half, origin.y + half do
            tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } }
        end
    end
    surface.set_tiles(tiles)
    for _, e in pairs(surface.find_entities_filtered{ area = area }) do
        if e.type ~= "character" then e.destroy() end
    end

    local centre = surface.create_entity{
        name = world.CENTER, position = origin, force = "player", raise_built = true,
    }
    assert(centre, "could not place the symmetry centre")

    local section = centre.get_control_behavior().get_section(1)
    local slot = 0
    local function signal(name, value)
        slot = slot + 1
        section.set_slot(slot, {
            value = { type = "virtual", name = name, quality = "normal" },
            min = value,
        })
    end
    signal("signal-S", opts.symmetry or 4)
    signal("signal-D", opts.range or 32)

    local patch = { surface = surface, origin = origin, centre = centre, area = area }

    --- Build one entity at an offset from the centre.
    --- It has to be a real player build: the mod only mirrors placements it considers
    --- manual, and script_raised_built is not one of them, so create_entity does nothing.
    function patch.build(offset, name)
        name = name or world.SUBJECT
        local player = game.players[1]
        assert(player, "no player to build with")
        local position = { x = origin.x + offset.x, y = origin.y + offset.y }
        -- Stand next to the build site: build_from_cursor obeys the character's build
        -- range, so the player has to be within reach but not on the tile itself.
        player.teleport({ position.x, position.y + 2 }, surface)
        player.cursor_stack.set_stack{ name = name, count = 50 }
        player.build_from_cursor{ position = position }
        player.cursor_stack.clear()
        -- The game snaps a 1x1 entity to the middle of its tile, so the entity is not at
        -- the position we asked for; search the tile instead of matching exactly.
        local found = surface.find_entities_filtered{
            area = {{ position.x - 0.5, position.y - 0.5 }, { position.x + 1.5, position.y + 1.5 }},
            name = name,
        }
        assert(found[1], "could not build " .. name .. " at " .. position.x .. "," .. position.y)
        return found[1]
    end

    --- Every copy the mod made, plus the original, excluding the centre.
    --- A player who cannot pay for the copies gets ghosts, so both count.
    function patch.copies(name)
        name = name or world.SUBJECT
        local found = {}
        for _, e in pairs(surface.find_entities_filtered{ area = area, force = "player" }) do
            if e.name == name or (e.name == "entity-ghost" and e.ghost_name == name) then
                found[#found + 1] = e
            end
        end
        return found
    end

    --- Only the ghost copies.
    function patch.ghosts(name)
        name = name or world.SUBJECT
        local found = {}
        for _, e in pairs(surface.find_entities_filtered{
            area = area, name = "entity-ghost", force = "player",
        }) do
            if e.ghost_name == name then found[#found + 1] = e end
        end
        return found
    end

    --- Mine an entity the way a player does, so the mod sees on_player_mined_entity.
    function patch.mine(entity)
        local player = game.players[1]
        assert(player, "no player to mine with")
        player.mine_entity(entity, true)
    end

    return patch
end

return world
