local _, ns = ...

-- Decides when to recompute. Pure: all WoW access is injected through deps
-- (after, inCombat, isShown, run).
local Scheduler = {}
ns.Scheduler = Scheduler
Scheduler.DEBOUNCE_S = 0.4

local Sched = {}
Sched.__index = Sched

function Scheduler.new(deps)
  return setmetatable({
    deps = deps,
    armed = false,
    pending = false,
    pendingForce = false,
    dirty = false,
    attempted = false,
    runs = 0,
  }, Sched)
end

function Sched:_fire()
  self.armed = false
  if self.deps.inCombat() then
    -- A timer is only armed for an allowed request, so keep that permission.
    self.pending = true
    self.pendingForce = true
    return
  end
  -- Cleared even if run fails below, so a broken run is never retried in a loop.
  self.dirty = false
  self.attempted = true
  local ok, err = pcall(self.deps.run)
  if ok then
    self.runs = self.runs + 1
  else
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, err) end
  end
end

function Sched:request(reason)
  if self.deps.inCombat() then
    self.pending = true
    if reason == "zone" or reason == "open" then
      self.pendingForce = true
    else
      self.dirty = true
    end
    return
  end
  if not self.deps.isShown() and reason ~= "zone" and reason ~= "open" then
    self.dirty = true
    return
  end
  if self.armed then return end
  -- Armed before the call (a synchronous after must not leave it stuck),
  -- but only stays armed if after() succeeds.
  self.armed = true
  local ok, err = pcall(self.deps.after, Scheduler.DEBOUNCE_S, function() self:_fire() end)
  if not ok then
    self.armed = false
    error(err, 0)
  end
end

function Sched:onCombatEnd()
  if not self.pending then return end
  self.pending = false
  local force = self.pendingForce
  self.pendingForce = false
  if force or self.deps.isShown() then
    self:request("open")
  end -- otherwise dirty stays set and the next onShow runs
end

function Sched:onShow()
  if self.dirty or not self.attempted then
    self:request("open")
  end
end
