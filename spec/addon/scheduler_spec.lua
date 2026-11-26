local addon = require("spec.helpers.addon")

local FILES = { "Core/Util.lua", "Core/Init.lua", "Core/Scheduler.lua" }

local function make(opts)
  opts = opts or {}
  local ns, env = addon.load(FILES)
  local queue, state = {}, { combat = opts.combat or false, shown = opts.shown ~= false }
  local timers = 0
  local sched
  local deps = {
    after = function(_, fn) timers = timers + 1; queue[#queue + 1] = fn end,
    inCombat = function() return state.combat end,
    isShown = function() return state.shown end,
    run = function()
      if state.throw then error("boom") end
      state.ran = (state.ran or 0) + 1
    end,
  }
  sched = ns.Scheduler.new(deps)
  local function flush()
    while #queue > 0 do table.remove(queue, 1)() end
  end
  return sched, state, flush, function() return timers end, env
end

describe("Scheduler", function()
  it("coalesces ten quest requests into one run", function()
    local s, _, flush, timers = make()
    for _ = 1, 10 do s:request("quest") end
    assert.equals(1, timers())
    flush()
    assert.equals(1, s.runs)
  end)

  it("starts no timer in combat and runs once after combat ends", function()
    local s, st, flush, timers = make({ combat = true })
    for _ = 1, 5 do s:request("quest") end
    assert.equals(0, timers())
    st.combat = false
    s:onCombatEnd()
    flush()
    assert.equals(1, s.runs)
  end)

  it("defers quest requests while hidden until onShow", function()
    local s, st, flush = make({ shown = false })
    s:request("quest")
    flush()
    assert.equals(0, s.runs)
    st.shown = true
    s:onShow()
    flush()
    assert.equals(1, s.runs)
  end)

  it("runs zone requests even while hidden", function()
    local s, _, flush = make({ shown = false })
    s:request("zone")
    flush()
    assert.equals(1, s.runs)
  end)

  it("sets pending when the timer fires during combat", function()
    local s, st, flush = make()
    s:request("quest")
    st.combat = true
    flush()
    assert.equals(0, s.runs)
    assert.is_true(s.pending)
    st.combat = false
    s:onCombatEnd()
    flush()
    assert.equals(1, s.runs)
  end)

  it("does not stay armed when after() throws", function()
    local ns = addon.load(FILES)
    local fail, queue = true, {}
    local s = ns.Scheduler.new({
      after = function(_, fn)
        if fail then error("no timer", 0) end
        queue[#queue + 1] = fn
      end,
      inCombat = function() return false end,
      isShown = function() return true end,
      run = function() end,
    })
    assert.has_error(function() s:request("quest") end, "no timer")
    assert.is_false(s.armed)
    fail = false
    s:request("quest")
    assert.equals(1, #queue)
    queue[1]()
    assert.equals(1, s.runs)
  end)

  it("survives a run that throws and reports the error", function()
    local s, st, flush, _, env = make()
    st.throw = true
    s:request("quest")
    flush()
    assert.equals(1, #env.errors)
    st.throw = false
    s:request("quest")
    flush()
    assert.equals(1, s.runs)
  end)

  it("onShow runs when run has never run", function()
    local s, _, flush = make()
    s:onShow()
    flush()
    assert.equals(1, s.runs)
  end)

  it("hidden quest request in combat waits for onShow", function()
    local s, st, flush = make({ shown = false, combat = true })
    s:request("quest")
    st.combat = false
    s:onCombatEnd()
    flush()
    assert.equals(0, s.runs)
    st.shown = true
    s:onShow()
    flush()
    assert.equals(1, s.runs)
  end)

  it("hidden zone request in combat runs after combat", function()
    local s, st, flush = make({ shown = false, combat = true })
    s:request("zone")
    st.combat = false
    s:onCombatEnd()
    flush()
    assert.equals(1, s.runs)
  end)

  it("onShow while a timer is armed gives one run", function()
    local s, _, flush = make()
    s:request("quest")
    s:onShow()
    flush()
    assert.equals(1, s.runs)
  end)

  it("onCombatEnd with nothing pending does nothing", function()
    local s, _, flush, timers = make()
    s:onCombatEnd()
    flush()
    assert.equals(0, timers())
    assert.equals(0, s.runs)
  end)

  it("a run that requests again causes exactly one more run", function()
    local ns = addon.load(FILES)
    local queue, count, s = {}, 0, nil
    s = ns.Scheduler.new({
      after = function(_, fn) queue[#queue + 1] = fn end,
      inCombat = function() return false end,
      isShown = function() return true end,
      run = function()
        count = count + 1
        if count == 1 then s:request("quest") end
      end,
    })
    s:request("quest")
    while #queue > 0 do table.remove(queue, 1)() end
    assert.equals(2, s.runs)
  end)

  it("a failed run counts nothing and clears dirty", function()
    local s, st, flush = make()
    st.throw = true
    s:request("quest")
    flush()
    assert.equals(0, s.runs)
    assert.is_false(s.dirty)
  end)
end)
