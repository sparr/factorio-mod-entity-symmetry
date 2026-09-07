--- Issue #10's fluid half. "Rotating" a building with several fluid inputs is rotation and
--- mirroring; there is no separate cycling in vanilla. Rotation already worked. Mirroring
--- was decided by a hardcoded list of four entity names, which missed most of the game --
--- a mirrored foundry kept its inputs on the original side.
local world = require("test.ft.world")

--- signal-S negative is a mirror bitmask: 1 = across the Y axis, 2 = across the X axis.
local MIRROR_X = -1

describe("mirroring a building with fluid inputs", function()
    it("mirrors an entity the old hardcoded list knew about", function()
        local patch = world.patch{ symmetry = MIRROR_X }
        local placed = patch.build({ x = 6, y = 0 }, "chemical-plant")
        local mirrored = 0
        for _, copy in pairs(patch.copies("chemical-plant")) do
            if copy ~= placed and copy.mirroring then mirrored = mirrored + 1 end
        end
        assert(mirrored == 1, "expected the chemical plant copy to be mirrored")
    end)

    it("mirrors one it did not: the foundry", function()
        local patch = world.patch{ symmetry = MIRROR_X }
        -- A crafting machine only has fluid connections once its recipe calls for them,
        -- so mirroring is meaningless until a fluid recipe is set.
        local placed = patch.build_blueprint({ x = 8, y = 0 }, "foundry",
            function(e) e.set_recipe("casting-iron") end)
        local copies, mirrored = 0, 0
        for _, copy in pairs(patch.copies("foundry")) do
            if copy ~= placed then
                copies = copies + 1
                if copy.mirroring then mirrored = mirrored + 1 end
            end
        end
        local proto = prototypes.entity["foundry"]
        local detail = ("use_mirroring=%s source.mirroring=%s copies=%d mirrored=%d")
            :format(tostring(proto.use_mirroring), tostring(placed.mirroring), copies, mirrored)
        assert(copies == 1, "expected one foundry copy, found " .. copies .. "; " .. detail)
        assert(mirrored == 1, "the foundry copy was not mirrored; " .. detail)
    end)

    it("leaves an entity that cannot be mirrored alone", function()
        local patch = world.patch{ symmetry = MIRROR_X }
        local placed = patch.build({ x = 6, y = 0 }, "centrifuge")
        for _, copy in pairs(patch.copies("centrifuge")) do
            if copy ~= placed then
                assert(not copy.mirroring,
                    "a centrifuge cannot be mirrored, but the copy claims to be")
            end
        end
    end)
end)

--- A crafting machine only has fluid connections while its recipe calls for them, and
--- mirroring only sticks while it has them. So what survives this sequence: set a fluid
--- recipe, mirror it, clear the recipe, then paste it where it gets rotational copies?
describe("a mirrored building whose fluid recipe is then cleared", function()
    it("gives the copies the mirrored state too", function()
        local patch = world.patch{ symmetry = 4 }
        local far = { x = patch.origin.x + 20, y = patch.origin.y }
        local source = patch.surface.create_entity{
            name = "foundry", position = far, force = "player", raise_built = false,
        }
        assert(source, "no foundry")

        local report = {}
        source.set_recipe("casting-iron")
        source.mirroring = true
        report[#report + 1] = "with fluid recipe: mirroring=" .. tostring(source.mirroring)
        source.set_recipe(nil)
        report[#report + 1] = "recipe cleared:     mirroring=" .. tostring(source.mirroring)

        -- copy and paste it in, as a player would
        local player = game.players[1]
        player.teleport(far, patch.surface)
        player.cursor_stack.set_stack{ name = "blueprint" }
        player.cursor_stack.create_blueprint{
            surface = patch.surface, force = "player",
            area = {{ far.x - 4, far.y - 4 }, { far.x + 4, far.y + 4 }},
        }
        local entities = player.cursor_stack.get_blueprint_entities() or {}
        for _, e in pairs(entities) do
            report[#report + 1] = ("blueprint entry:    name=%s mirror=%s recipe=%s")
                :format(tostring(e.name), tostring(e.mirror), tostring(e.recipe))
        end
        source.destroy()

        local position = { x = patch.origin.x + 8, y = patch.origin.y }
        player.teleport({ position.x, position.y + 5 }, patch.surface)
        player.build_from_cursor{ position = position }
        player.cursor_stack.clear()

        local placed, copies = nil, {}
        for _, e in pairs(patch.copies("foundry")) do
            if math.abs(e.position.x - position.x) < 3 and math.abs(e.position.y - position.y) < 3 then
                placed = e
            else
                copies[#copies + 1] = e
            end
        end
        report[#report + 1] = "pasted original:    mirroring="
            .. (placed and tostring(placed.mirroring) or "NOT PLACED")
        for _, c in pairs(copies) do
            report[#report + 1] = ("copy at %+d,%+d:     mirroring=%s")
                :format(c.position.x - patch.origin.x, c.position.y - patch.origin.y,
                        tostring(c.mirroring))
        end

        helpers.write_file("es-mirror-edge.txt", table.concat(report, "\n") .. "\n", false)
        assert(placed, "the paste placed nothing")
        assert(placed.mirroring, "setup: the pasted original lost its mirrored state")
        assert(#copies == 3, "expected 3 copies, found " .. #copies)
        for _, c in pairs(copies) do
            assert(c.mirroring,
                "a copy is not mirrored: mirroring persists on an entity with no fluid "
                .. "connections but cannot be set on one, so the fresh copy will not take it")
        end
    end)
end)
