local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.List = ns.UI.List or {}
local List = ns.UI.List

-- A scrolling list of pooled rows (WowScrollBoxList + MinimalScrollBar).

local function available()
  return type(CreateFrame) == "function" and type(CreateScrollBoxListLinearView) == "function"
    and type(ScrollUtil) == "table" and type(ScrollUtil.InitScrollBoxListWithScrollBar) == "function"
    and type(CreateDataProvider) == "function"
end

-- init(frame, element) fills a pooled row frame; each element has a `height`.
-- Returns nil when the client lacks the scroll box API.
function List.new(parent, init)
  if not available() then return nil end
  local ok, list = pcall(function()
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    local view = CreateScrollBoxListLinearView()
    view:SetElementInitializer("LevelingAdvisorListRowTemplate", init)
    view:SetElementExtentCalculator(function(_, e) return e.height end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    return { box = box, bar = bar, view = view }
  end)
  if not (ok and type(list) == "table") then return nil end

  -- identity names the content (a zone, a dungeon, a search query; nil for a
  -- list with one content). A refresh of the same content keeps the scroll
  -- position (the advisor recomputes often); other content starts at the
  -- top. Fail-soft when the client lacks the constant or the argument.
  function list:set(elements, identity)
    local dp = CreateDataProvider(elements)
    local same = identity == self.identity
    self.identity = identity
    local consts = type(ScrollBoxConstants) == "table" and ScrollBoxConstants or {}
    local keep
    if same then keep = consts.RetainScrollPosition else keep = consts.DiscardScrollPosition end
    if not pcall(self.box.SetDataProvider, self.box, dp, keep) then
      pcall(self.box.SetDataProvider, self.box, dp)
    end
  end
  return list
end

-- Builds a kind's widgets once per pooled frame (build(frame) -> part with
-- .root), keeps them in frame["la" .. Kind], and hides the other kinds' roots.
function List.part(frame, kind, build)
  local key = "la" .. kind:sub(1, 1):upper() .. kind:sub(2)
  local parts = frame.laParts
  if not parts then parts = {}; frame.laParts = parts end
  local part = frame[key]
  if not part then
    part = build(frame)
    frame[key] = part
    parts[kind] = part
  end
  for k, p in pairs(parts) do
    if p.root then p.root:SetShown(k == kind) end
  end
  return part
end
