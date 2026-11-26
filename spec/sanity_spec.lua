describe("toolchain", function()
  it("runs Lua 5.1 semantics like WoW", function()
    assert.equals("Lua 5.1", _VERSION)
    -- table.unpack is not asserted nil: busted's dependencies polyfill it at load time
    -- (bare `luajit` has none). tools/check-lua-syntax.sh greps for table.unpack/pack/goto
    -- instead. WoW code must use the global `unpack`.
    assert.is_function(unpack)
  end)
end)
