# Tests

Two tiers, kept separate. Pure decisions belong in the unit tier; anything about what the
engine really does belongs in the integration tier.

## Unit tier — `test/run.sh`

Busted specs in `test/spec` run against the stubs in `test/support`, in the same Lua 5.2
that Factorio runs, with no game at all. Milliseconds.

```bash
luarocks --lua-version 5.2 --tree .luarocks install busted   # once
test/run.sh                 # everything
test/run.sh --filter flip   # a subset
```

They cover `lib/geometry.lua`, which is the direction and orientation maths lifted out of
`control.lua` precisely so it could be tested: it depends only on `defines.direction` and
`table.deepcopy`, both stubbed.

## Integration tier — `test/ft/run.sh`

Fixtures in `test/ft` drive a real Factorio through
[factorio-test](https://mods.factorio.com/mod/factorio-test), headless.

```bash
npm install                        # once: fetches factorio-test-cli
test/ft/run.sh                     # the whole suite
test/ft/run.sh "rotational"        # only tests matching a Lua pattern
test/ft/run.sh -v                  # with the game's own log lines
test/ft/run.sh -g --no-auto-start  # open a window and pick tests by hand
```

`ES_FACTORIO` points at the game binary, `ES_FT_DATA` at the throwaway data directory the
run happens in (`~/.cache/es-factorio-test` by default, deliberately outside the repo --
the runner symlinks the mod under test into that directory's mods folder, so a data
directory inside the repo would make the repo contain itself).

`control.lua` registers the fixtures, guarded on both `factorio-test` and `es-tests` being
loaded. `es-tests` is a marker mod that is never published, so the hook can never fire on a
player's machine -- which matters, because `info.json` keeps `test/` out of the package.

### Writing a fixture

`test/ft/world.lua` holds the shared ground: `world.patch{ symmetry = 6 }` clears a fresh
square, drops a symmetry centre in the middle configured through the signals the mod reads
(`signal-S` symmetry, `signal-D` range), and hands back a patch with `build`, `copies` and
`mine` on it. factorio-test does not reset the world between tests, so a test that wants
clean ground asks for a patch.

Three things will silently make the mod look like it does nothing:

- **The mod only mirrors placements it considers manual.** `create_entity` raises
  `script_raised_built`, which is not manual, so a fixture has to build through the
  player's cursor -- and within the character's build range, or the build simply does not
  happen.
- **A 1x1 entity snaps to the middle of its tile**, so the entity is not at the position
  the fixture asked for. Search the tile rather than matching the position exactly.
- **Without cheat mode the copies are ghosts**, and the removal path filters candidates by
  entity name, which never matches `entity-ghost`. `world.patch` turns cheat mode on so
  copies are real entities; without it every removal test fails identically and hides the
  real bug.

## Known failures

`test/ft/rotational.lua` has two tests red on purpose: removal for S=6 and S=7, which is
issue #2, open since 2020. They are the reproduction, and they stay red until the fix
lands. `test/spec/roundtrip_spec.lua` explains why a tolerance cannot fix it.
