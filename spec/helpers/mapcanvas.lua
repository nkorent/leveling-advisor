-- A fake of Blizzard's map canvas (MapCanvasMixin) and of the pin and data provider mixins,
-- shared by spec/helpers/ui.lua (its WorldMapFrame) and spec/addon/mappins_render_spec.lua,
-- so the two cannot drift apart. Pin templates come from the addon's own XML.
--
--   M.template(path, name)  the virtual frame template `name` in the XML file at path:
--                           { name, frameType, mixin, size = { x, y } | nil, enableMouse,
--                             scripts = { { event, method }, ... } } (nil when absent)
--   M.mixins()              { CreateFromMixins, Mixin, MapCanvasPinMixin,
--                             MapCanvasDataProviderMixin }: globals for the addon env
--   M.attach(map, opts)     makes the table `map` a map canvas (the client's WorldMapFrame is
--                           one) and returns it. opts:
--       newFrame(frameType, parent, templateName, template) -> a new frame of the template,
--                           its XML <Size> (template.size) applied the way the engine does,
--                           with at least SetScript, GetScript, Show and Hide (the caller's
--                           widget fake)
--       env                 where the template's mixin global is looked up (at acquire time)
--       templates           list of M.template records the canvas can acquire
--       mapID               the displayed map
--
-- The canvas, like MapCanvasMixin:
--   AddDataProvider(p)      keeps p and calls p:OnAdded(map) (the mixin's OnAdded remembers the
--                           map for GetMap); map.providers lists them
--   SetMapID(id)            a new map refreshes every provider (OnMapChanged -> RefreshAllData)
--   AcquirePin(name, ...)   takes a pooled pin, or creates one: CreateFrame of the template's
--                           type (newFrame), Mixin(frame, <mixin global>), the XML <Scripts>
--                           (method= calls self:<method>(...)), then OnLoad. A new pin
--                           with enableMouse gets the canvas's own mouse handlers: OnMouseUp
--                           calls pin:OnMouseUp(button, upInside) and, when upInside,
--                           pin:OnClick(button); OnMouseDown, OnEnter and OnLeave call
--                           pin:OnMouseDown / OnMouseEnter / OnMouseLeave. Then pin:Show() and
--                           pin:OnAcquired(...).
--   RemoveAllPinsByTemplate(name)  hides each pin of that template, calls pin:OnReleased()
--                           and returns it to the pool
--   EnumeratePinsByTemplate(name)  the template pool's EnumerateActive(): pairs over the
--                           active set, so the KEY is the pin (value true), as on the client
--   EnumerateAllPins()      an iterator over every active pin of every pool (one value: the pin)
--   map.pinPools            template name -> pool: { activeObjects = { [pin] = true } } with
--                           EnumerateActive() and GetNumActive(), as the client's frame pools
--   map.pins                the acquired pins in acquire order (always the same table)
local M = {}

local function readFile(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

local function attr(attrs, name)
  return attrs:match("%f[%w]" .. name .. '%s*=%s*"([^"]*)"')
end

function M.template(path, name)
  local xml = readFile(path):gsub("<!%-%-.-%-%->", "")
  local tag, attrs = xml:match('<(%a+)(%s[^>]-name%s*=%s*"' .. name:gsub("%p", "%%%0") .. '"[^>]*)>')
  if not tag then return nil end
  local open = xml:find('name%s*=%s*"' .. name:gsub("%p", "%%%0") .. '"')
  local close = xml:find("</" .. tag .. ">", open, true)
  local body = xml:sub(open, close or #xml)
  local t = {
    name = name, frameType = tag, mixin = attr(attrs, "mixin"),
    enableMouse = attr(attrs, "enableMouse") == "true", virtual = attr(attrs, "virtual") == "true",
    scripts = {},
  }
  local sx, sy = body:match('<Size%s+x="([%d%.]+)"%s+y="([%d%.]+)"%s*/>')
  if sx then t.size = { tonumber(sx), tonumber(sy) } end
  local scripts = body:match("<Scripts>(.-)</Scripts>") or ""
  for event, rest in scripts:gmatch("<(On%a+)([^>]*)/>") do
    t.scripts[#t.scripts + 1] = { event, attr(rest, "method") }
  end
  return t
end

local function mixin(target, ...)
  for i = 1, select("#", ...) do
    for k, v in pairs((select(i, ...))) do target[k] = v end
  end
  return target
end

-- Fresh mixin tables (each client gets its own, so a spec may patch them).
function M.mixins()
  local pin = {}
  function pin:OnLoad() end
  function pin:OnAcquired() end
  function pin:OnReleased() end
  function pin:OnClick() end
  function pin:OnMouseEnter() end
  function pin:OnMouseLeave() end
  function pin:OnMouseDown() end
  function pin:OnMouseUp() end
  function pin:SetPosition(x, y) self.pos = { x, y } end
  function pin:GetPosition() return self.pos and self.pos[1], self.pos and self.pos[2] end
  function pin:UseFrameLevelType(t) self.levelType = t end
  function pin:SetScalingLimits(...) self.scaling = { ... } end
  function pin:GetMap() return self.owningMap end

  local provider = {}
  function provider:OnAdded(map) self.owningMap = map end
  function provider:OnRemoved() self.owningMap = nil end
  function provider:GetMap() return self.owningMap end
  function provider:RemoveAllData() end
  function provider:RefreshAllData() end
  function provider:OnMapChanged() self:RefreshAllData() end

  return {
    CreateFromMixins = function(...) return mixin({}, ...) end,
    Mixin = mixin,
    MapCanvasPinMixin = pin,
    MapCanvasDataProviderMixin = provider,
  }
end

function M.attach(map, opts)
  map.mapID = opts.mapID
  map.providers = map.providers or {}
  map.pins = map.pins or {}
  map.pinPools = {}
  local templates = {}
  for _, t in ipairs(opts.templates or {}) do templates[t.name] = t end

  function map:GetMapID() return self.mapID end
  function map:SetMapID(id)
    if id == self.mapID then return end
    self.mapID = id
    for _, p in ipairs(self.providers) do p:OnMapChanged() end
  end
  function map:AddDataProvider(p)
    self.providers[#self.providers + 1] = p
    p:OnAdded(self)
  end

  local function newPin(t)
    local pin = opts.newFrame(t.frameType, map, t.name, t)
    local mx = opts.env[t.mixin]
    assert(type(mx) == "table", "template " .. t.name .. ": mixin " .. tostring(t.mixin) .. " is not a table")
    mixin(pin, mx)
    for _, s in ipairs(t.scripts) do
      local method = s[2]
      pin:SetScript(s[1], function(self, ...) return self[method](self, ...) end)
    end
    local onLoad = pin:GetScript("OnLoad")
    if onLoad then onLoad(pin) end
    if t.enableMouse then
      pin:SetScript("OnMouseUp", function(self, button, upInside)
        self:OnMouseUp(button, upInside)
        if upInside then self:OnClick(button) end
      end)
      pin:SetScript("OnMouseDown", function(self, button) self:OnMouseDown(button) end)
      pin:SetScript("OnEnter", function(self) self:OnMouseEnter() end)
      pin:SetScript("OnLeave", function(self) self:OnMouseLeave() end)
    end
    return pin
  end

  local function poolOf(self, name)
    local pool = self.pinPools[name]
    if not pool then
      pool = { activeObjects = {}, free = {} }
      function pool:EnumerateActive() return pairs(self.activeObjects) end
      function pool:GetNumActive()
        local n = 0
        for _ in pairs(self.activeObjects) do n = n + 1 end
        return n
      end
      self.pinPools[name] = pool
    end
    return pool
  end

  function map:AcquirePin(name, ...)
    local t = assert(templates[name], "unknown pin template " .. tostring(name))
    local pool = poolOf(self, name)
    local pin = table.remove(pool.free) or newPin(t)
    pool.activeObjects[pin] = true
    pin.pinTemplate, pin.owningMap = name, self
    pin:Show()
    pin:OnAcquired(...)
    self.pins[#self.pins + 1] = pin
    return pin
  end

  function map:RemoveAllPinsByTemplate(name)
    local i = 1
    while i <= #self.pins do
      local pin = self.pins[i]
      if pin.pinTemplate == name then
        table.remove(self.pins, i)
        pin:Hide()
        pin:OnReleased()
        pin.pinTemplate, pin.owningMap = nil, nil
        local pool = poolOf(self, name)
        pool.activeObjects[pin] = nil
        pool.free[#pool.free + 1] = pin
      else
        i = i + 1
      end
    end
  end

  function map:EnumeratePinsByTemplate(name)
    local pool = self.pinPools[name]
    if not pool then return function() end end
    return pool:EnumerateActive()
  end

  function map:EnumerateAllPins()
    local list = {}
    for _, p in ipairs(self.pins) do list[#list + 1] = p end
    local i = 0
    return function()
      i = i + 1
      return list[i]
    end
  end

  return map
end

return M
