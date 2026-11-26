-- Loads addon files the way the WoW client does: each file receives
-- (addonName, ns). The addon name is the basename of dir. An optional env
-- table is used as the files' global environment (fake WoW API injection).
-- Returns ns so callers can load more files into the same namespace.
return function(dir, files, env)
  local ns = {}
  local addonName = dir:match("([^/]+)/*$")
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(dir .. "/" .. f))
    if env then setfenv(chunk, env) end
    chunk(addonName, ns)
  end
  return ns
end
