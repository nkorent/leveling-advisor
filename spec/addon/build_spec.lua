-- Shells out to tools/build.sh. LA_BUILD_SKIP_TESTS avoids busted recursion.
local function run(cmd)
  local p = io.popen(cmd .. ' 2>&1; echo "EXIT:$?"')
  local out = p:read("*a")
  p:close()
  local code = tonumber(out:match("EXIT:(%d+)%s*$"))
  return code, out
end

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

local ROOT = (debug.getinfo(1, "S").source:match("^@(.*)/spec/addon/[^/]*$")) or "."
if ROOT:sub(1, 1) ~= "/" then
  local p = io.popen("cd " .. ROOT .. " && pwd")
  ROOT = p:read("*l")
  p:close()
end

-- A copy of the addon without Data/ in a fresh temp dir (returns the dir), so
-- both cases behave the same whether or not generated Data files exist.
local function copyWithoutData()
  local tmp = os.tmpname()
  os.remove(tmp)
  assert.are.equal(0, (run("mkdir -p " .. tmp .. " && cp -R " .. ROOT .. "/LevelingAdvisor " .. tmp .. "/LevelingAdvisor && rm -rf " .. tmp .. "/LevelingAdvisor/Data")))
  return tmp
end

describe("tools/build.sh", function()
  local ENV = "cd " .. ROOT .. " && LA_BUILD_SKIP_TESTS=1 "

  it("builds a zip with --allow-missing-data", function()
    local tmp = copyWithoutData()
    local code, out = run(ENV .. "LA_ADDON_DIR=" .. tmp .. "/LevelingAdvisor " .. ROOT .. "/tools/build.sh --allow-missing-data")
    run("rm -rf " .. tmp)
    assert.are.equal(0, code, out)
    assert.is_truthy(out:find("WARNING: no quest data in this build", 1, true), out)
    local zip = out:match("(dist/LevelingAdvisor%-[%w%.]+%-nodata%.zip)")
    assert.is_truthy(zip, out)
    local c2, list = run("unzip -l " .. ROOT .. "/" .. zip)
    assert.are.equal(0, c2)
    assert.is_truthy(list:find("LevelingAdvisor/LevelingAdvisor.toc", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/LICENSE", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/README.md", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/NOTICE.md", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/Core/Advisor.lua", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/UI/MapPins.lua", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/UI/MapPins.xml", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/Media/PinShield.tga", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/Media/PinShieldGlow.tga", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/Bindings.xml", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/Media/BookmarkTab.tga", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/Media/ChainLink.tga", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/UI/Window.lua", 1, true))
    assert.is_truthy(list:find("LevelingAdvisor/UI/Guide.lua", 1, true))
    assert.is_falsy(list:find("spec/", 1, true))
    assert.is_falsy(list:find("dev/", 1, true))
    assert.is_falsy(list:find("pipeline/", 1, true))
    assert.is_falsy(list:find("LevelingAdvisor/Data/", 1, true))
  end)

  it("names the zip -provisional and warns when Meta.lua says provisional = true", function()
    local tmp = copyWithoutData()
    local dir = tmp .. "/LevelingAdvisor"
    local function write(name, body)
      local f = assert(io.open(dir .. "/Data/" .. name .. ".lua", "w"))
      f:write(body)
      f:close()
    end
    assert.are.equal(0, (run("mkdir -p " .. dir .. "/Data")))
    write("Meta", "local _, ns = ...\nns.Data = ns.Data or {}\nns.Data.meta = {built = \"x\", provisional = true}\n")
    for _, f in ipairs({ "Zones", "NPCs", "Dungeons", "Quests" }) do write(f, "local _, ns = ...\n") end
    local code, out = run(ENV .. "LA_ADDON_DIR=" .. dir .. " " .. ROOT .. "/tools/build.sh")
    run("rm -rf " .. tmp)
    assert.are.equal(0, code, out)
    assert.is_truthy(out:find("WARNING: provisional data", 1, true), out)
    local zip = out:match("(dist/LevelingAdvisor%-[%w%.]+%-provisional%.zip)")
    assert.is_truthy(zip, out)
    run("rm -f " .. ROOT .. "/" .. zip)
  end)

  it("names the zip plainly when Meta.lua is not provisional", function()
    local tmp = copyWithoutData()
    local dir = tmp .. "/LevelingAdvisor"
    assert.are.equal(0, (run("mkdir -p " .. dir .. "/Data")))
    for _, f in ipairs({ "Meta", "Zones", "NPCs", "Dungeons", "Quests" }) do
      local h = assert(io.open(dir .. "/Data/" .. f .. ".lua", "w"))
      h:write("local _, ns = ...\n")
      h:close()
    end
    local code, out = run(ENV .. "LA_ADDON_DIR=" .. dir .. " " .. ROOT .. "/tools/build.sh")
    run("rm -rf " .. tmp)
    assert.are.equal(0, code, out)
    assert.is_falsy(out:find("WARNING", 1, true), out)
    local zip = out:match("(dist/LevelingAdvisor%-[%w%.]+%.zip)")
    assert.is_truthy(zip, out)
    assert.is_falsy(zip:find("provisional", 1, true))
    run("rm -f " .. ROOT .. "/" .. zip)
  end)

  it("fails without the flag when Data files are missing", function()
    local tmp = copyWithoutData()
    local code, out = run(ENV .. "LA_ADDON_DIR=" .. tmp .. "/LevelingAdvisor " .. ROOT .. "/tools/build.sh")
    run("rm -rf " .. tmp)
    assert.are.equal(1, code, out)
    assert.is_truthy(out:find("Meta.lua", 1, true), out)
  end)
end)
