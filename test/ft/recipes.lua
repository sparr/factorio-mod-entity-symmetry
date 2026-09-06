--- Issue #10: "When placing an assembler via blueprint, the symmetric copies have no
--- recipe set." The recipe arrives with the blueprint, so the mod has to carry it across
--- when it makes the copies.
local world = require("test.ft.world")

local ASSEMBLER = "assembling-machine-2"
local RECIPE = "iron-gear-wheel"

--- The recipe on either a real entity or a ghost, or nil with a note on why not.
local function recipe_of(entity)
    local ok, recipe = pcall(function() return entity.get_recipe() end)
    if ok and recipe then return recipe.name end
    return nil, ok and "no recipe set" or "get_recipe errored"
end

describe("an assembler placed from a blueprint", function()
    it("gives its copies the same recipe", function()
        local patch = world.patch{ symmetry = 4 }
        local placed = patch.build_blueprint({ x = 6, y = 0 }, ASSEMBLER,
            function(e) e.set_recipe(RECIPE) end)
        local want = recipe_of(placed)
        assert(want == RECIPE,
            "setup: the placed entity has recipe " .. tostring(want) .. ", not " .. RECIPE)

        local missing, seen = {}, 0
        for _, copy in pairs(patch.copies(ASSEMBLER)) do
            if copy ~= placed then
                seen = seen + 1
                local got, why = recipe_of(copy)
                if got ~= RECIPE then
                    missing[#missing + 1] = tostring(got or why)
                end
            end
        end
        assert(seen == 3, "expected 3 copies, found " .. seen)
        assert(#missing == 0,
            "copies without the recipe: " .. table.concat(missing, ", "))
    end)
end)

describe("other configuration on a copied entity", function()
    it("gives ghost copies the recipe too", function()
        local patch = world.patch{ symmetry = 4, cheat = false }
        local placed = patch.build_blueprint({ x = 6, y = 0 }, ASSEMBLER,
            function(e) e.set_recipe(RECIPE) end)
        local ghosts = patch.ghosts(ASSEMBLER)
        assert(#ghosts >= 1, "expected ghost copies, found none")
        local missing = {}
        for _, ghost in pairs(ghosts) do
            local got, why = recipe_of(ghost)
            if got ~= RECIPE then missing[#missing + 1] = tostring(got or why) end
        end
        assert(#missing == 0, "ghost copies without the recipe: " .. table.concat(missing, ", "))
    end)

    it("copies the signals set on a constant combinator", function()
        local patch = world.patch{ symmetry = 4 }
        local placed = patch.build_blueprint({ x = 6, y = 0 }, "constant-combinator",
            function(e)
                e.get_control_behavior().get_section(1).set_slot(1, {
                    value = { type = "item", name = "iron-plate", quality = "normal" },
                    min = 7,
                })
            end)
        local blank, seen = {}, 0
        for _, copy in pairs(patch.copies("constant-combinator")) do
            if copy ~= placed and copy.name ~= world.CENTER then
                seen = seen + 1
                local section = copy.get_control_behavior().get_section(1)
                local slot = section and section.get_slot(1)
                if not (slot and slot.value and slot.value.name == "iron-plate") then
                    blank[#blank + 1] = "empty"
                end
            end
        end
        assert(seen == 3, "expected 3 combinator copies, found " .. seen)
        assert(#blank == 0, #blank .. " of " .. seen .. " combinator copies have no signals")
    end)

    it("copies the filter set on a splitter", function()
        local patch = world.patch{ symmetry = 4 }
        local placed = patch.build_blueprint({ x = 6, y = 0 }, "splitter",
            function(e) e.splitter_filter = { name = "iron-plate", quality = "normal" } end)
        local blank, seen = {}, 0
        for _, copy in pairs(patch.copies("splitter")) do
            if copy ~= placed then
                seen = seen + 1
                if not copy.splitter_filter then blank[#blank + 1] = "unset" end
            end
        end
        assert(seen == 3, "expected 3 splitter copies, found " .. seen)
        assert(#blank == 0, #blank .. " of " .. seen .. " splitter copies have no filter")
    end)
end)
