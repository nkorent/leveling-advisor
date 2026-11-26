-- Fake WoW globals sufficient to load Util.lua and Diag.lua.
-- Returns env, frame, out (captured print lines).
return function(extra)
  local out, frame = {}, {}
  local env = setmetatable({
    print = function(m) out[#out + 1] = m end,
    SlashCmdList = {},
    CreateFrame = function()
      function frame:RegisterEvent(e) self.event = e end
      function frame:SetScript(_, fn) self.onEvent = fn end
      return frame
    end,
    GetBuildInfo = function() return "1.0", "16001" end,
    time = function() return 1234 end,
  }, { __index = _G })
  for k, v in pairs(extra or {}) do env[k] = v end
  return env, frame, out
end
