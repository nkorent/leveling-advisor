-- Shells out to tools/build.sh. LA_BUILD_SKIP_TESTS avoids busted recursion, and
-- LA_DIST_DIR sends every build into a temp dir so the repo's dist/ (which may hold
-- a real release zip) is never touched.
local function run(cmd)
  local p = io.popen(cmd .. ' 2>&1; echo "EXIT:$?"')
  local out = p:read("*a")
  p:close()
  local code = tonumber(out:match("EXIT:(%d+)%s*$"))
  return code, out
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

-- Runs tools/build.sh on the addon copy in tmp, building into tmp/dist.
local function build(tmp, addonDir, args)
  return run("cd " .. ROOT .. " && LA_BUILD_SKIP_TESTS=1 LA_DIST_DIR=" .. tmp .. "/dist LA_ADDON_DIR=" .. addonDir
    .. " " .. ROOT .. "/tools/build.sh" .. (args and (" " .. args) or ""))
end

-- The zip path build.sh printed, if it lies in tmp/dist and matches the suffix pattern.
local function zipIn(out, tmp, suffix)
  for line in out:gmatch("[^\n]+") do
    if line:sub(1, #tmp + 6) == tmp .. "/dist/" and line:match("^.*/LevelingAdvisor%-[%w%.]+" .. suffix .. "%.zip$") then
      return line
    end
  end
end

local function writeData(dir, files)
  assert.are.equal(0, (run("mkdir -p " .. dir .. "/Data")))
  for name, body in pairs(files) do
    local f = assert(io.open(dir .. "/Data/" .. name .. ".lua", "w"))
    f:write(body)
    f:close()
  end
end

describe("tools/build.sh", function()
  it("builds a zip with --allow-missing-data", function()
    local tmp = copyWithoutData()
    local code, out = build(tmp, tmp .. "/LevelingAdvisor", "--allow-missing-data")
    local zip = zipIn(out, tmp, "%-nodata")
    local c2, list = run("unzip -l " .. tostring(zip))
    run("rm -rf " .. tmp)
    assert.are.equal(0, code, out)
    assert.is_truthy(out:find("WARNING: no quest data in this build", 1, true), out)
    assert.is_truthy(zip, out)
    assert.are.equal(0, c2, list)
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
    local stub = "local _, ns = ...\n"
    writeData(dir, {
      Meta = "local _, ns = ...\nns.Data = ns.Data or {}\nns.Data.meta = {built = \"x\", provisional = true}\n",
      Zones = stub, NPCs = stub, Dungeons = stub, Quests = stub,
    })
    local code, out = build(tmp, dir)
    local zip = zipIn(out, tmp, "%-provisional")
    run("rm -rf " .. tmp)
    assert.are.equal(0, code, out)
    assert.is_truthy(out:find("WARNING: provisional data", 1, true), out)
    assert.is_truthy(zip, out)
  end)

  it("names the zip plainly when Meta.lua is not provisional", function()
    local tmp = copyWithoutData()
    local dir = tmp .. "/LevelingAdvisor"
    local stub = "local _, ns = ...\n"
    writeData(dir, { Meta = stub, Zones = stub, NPCs = stub, Dungeons = stub, Quests = stub })
    local code, out = build(tmp, dir)
    local zip = zipIn(out, tmp, "")
    run("rm -rf " .. tmp)
    assert.are.equal(0, code, out)
    assert.is_falsy(out:find("WARNING", 1, true), out)
    assert.is_truthy(zip, out)
    assert.is_falsy(zip:find("provisional", 1, true))
  end)

  it("fails without the flag when Data files are missing", function()
    local tmp = copyWithoutData()
    local code, out = build(tmp, tmp .. "/LevelingAdvisor")
    run("rm -rf " .. tmp)
    assert.are.equal(1, code, out)
    assert.is_truthy(out:find("Meta.lua", 1, true), out)
  end)

  -- A dist dir that would make the stage dir the addon source must never delete it. Run on a
  -- copy of the repo's build files, never on the real tree.
  for _, dist in ipairs({ ".", "LevelingAdvisor", "LevelingAdvisor/Media" }) do
    it("refuses LA_DIST_DIR=" .. dist .. " and leaves the addon untouched", function()
      local tmp = copyWithoutData()
      local repo = tmp .. "/repo"
      assert.are.equal(0, (run("mkdir -p " .. repo .. "/tools && cp " .. ROOT .. "/tools/build.sh "
        .. ROOT .. "/tools/check-lua-syntax.sh " .. repo .. "/tools/ && cp " .. ROOT .. "/LICENSE " .. ROOT
        .. "/README.md " .. ROOT .. "/NOTICE.md " .. repo .. "/ && mv " .. tmp .. "/LevelingAdvisor " .. repo .. "/")))
      local listing = "cd " .. repo .. " && find LevelingAdvisor -type f | sort | xargs cksum"
      local _, before = run(listing)
      local code, out = run("cd " .. repo .. " && LA_BUILD_SKIP_TESTS=1 LA_DIST_DIR=" .. dist .. " "
        .. repo .. "/tools/build.sh --allow-missing-data")
      local _, after = run(listing)
      run("rm -rf " .. tmp)
      assert.are.equal(2, code, out)
      assert.is_truthy(out:find("build: refusing LA_DIST_DIR=", 1, true), out)
      assert.is_truthy(before:find("LevelingAdvisor/Core/Advisor.lua", 1, true), before)
      assert.are.equal(before, after)
    end)
  end

  it("does not touch the repo's dist/", function()
    local tmp = copyWithoutData()
    local marker = tmp .. "/marker"
    local listing = "ls -laR " .. ROOT .. "/dist 2>&1"
    local _, before = run(listing)
    assert.are.equal(0, (run("touch " .. marker)))
    -- A full second so a file written after the marker is strictly newer on 1 s clocks.
    run("sleep 1")
    local code, out = build(tmp, tmp .. "/LevelingAdvisor", "--allow-missing-data")
    local _, after = run(listing)
    local _, newer = run("[ -d " .. ROOT .. "/dist ] && find " .. ROOT .. "/dist -newer " .. marker .. " || true")
    run("rm -rf " .. tmp)
    assert.are.equal(0, code, out)
    assert.are.equal(before, after)
    assert.are.equal("EXIT:0", (newer:gsub("%s+$", "")))
  end)
end)
