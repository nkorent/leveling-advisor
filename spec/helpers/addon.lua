-- Addon spec helper.
--   load(files, extra) -> ns, env, out
-- Loads the listed LevelingAdvisor/ files (relative paths) through load_addon
-- into a fake WoW env. env.flush() runs queued C_Timer.After callbacks.
-- env.frames lists every frame created; env.frame is the first one.
-- out collects print lines; env.errors collects errors sent to geterrorhandler().
local load_addon = require("spec.helpers.load_addon")

local M = {}

function M.env(extra)
  local out, queue, frames, errors = {}, {}, {}, {}
  local env = setmetatable({
    geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end,
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      out[#out + 1] = table.concat(parts, " ")
    end,
    SlashCmdList = {},
    CreateFrame = function()
      local f = { events = {} }
      function f:RegisterEvent(e) self.events[e] = true end
      function f:UnregisterEvent(e) self.events[e] = nil end
      function f:SetScript(name, fn) self[name == "OnEvent" and "onEvent" or name] = fn end
      frames[#frames + 1] = f
      return f
    end,
    C_Timer = { After = function(_, fn) queue[#queue + 1] = fn end },
    InCombatLockdown = function() return false end,
    UnitFactionGroup = function() return "Alliance" end,
    GetBuildInfo = function() return "1.0", "16001" end,
    time = function() return 1234 end,
  }, { __index = _G })
  for k, v in pairs(extra or {}) do env[k] = v end
  env.frames = frames
  env.errors = errors
  env.flush = function()
    while #queue > 0 do table.remove(queue, 1)() end
  end
  return env, out
end

function M.load(files, extra)
  local env, out = M.env(extra)
  local ns = load_addon("LevelingAdvisor", files, env)
  env.frame = env.frames[1]
  return ns, env, out
end

return M
