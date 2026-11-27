-- Resolve item placeholders only while formatting labels. Stored history and
-- auction requests continue to use their original item keys.
local waiting, requested, failed = {}, {}, {}
local listener
local pattern = '%f[%a][Ii]tem #?(%d+)%f[%D]'

function ForeverMarketSetItemText(label, source)
  waiting[label] = nil
  if type(source) ~= 'string' or not source:find(pattern) then
    label:SetText(source)
    return
  end
  local missing = {}
  local display = source:gsub(pattern, function(key)
    local id = tonumber(key)
    local name = C_Item.GetItemNameByID(id)
    if name and name ~= '' then return name end
    if failed[id] and GetTime() < failed[id] then return 'Unknown item ('..key..')' end
    missing[id] = true
    return 'Loading item name...'
  end)
  label:SetText(display)
  if not next(missing) then return end
  waiting[label] = {source=source, display=display, ids=missing}
  if not listener then
    listener = CreateFrame('Frame')
    listener:RegisterEvent('GET_ITEM_INFO_RECEIVED')
    listener:SetScript('OnEvent', function(_, _, id, success)
      if not requested[id] then return end
      requested[id] = nil
      if success == false or not C_Item.GetItemNameByID(id) then failed[id] = GetTime()+60 end
      local redraw = {}
      for widget, state in pairs(waiting) do
        if state.ids[id] then redraw[widget] = state end
      end
      for widget, state in pairs(redraw) do
        if widget:GetText() == state.display then
          ForeverMarketSetItemText(widget, state.source)
        else
          waiting[widget] = nil
        end
      end
    end)
  end
  for id in pairs(missing) do
    if not requested[id] or GetTime()-requested[id] >= 30 then
      requested[id] = GetTime()
      if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id)
      else C_Item.GetItemInfo(id) end
    end
  end
end
-- Chat cannot edit a line after printing. Resolve its item names first.
function ForeverMarketPrintItemText(text)
  local line = {}
  function line:GetText() return self.text end
  function line:SetText(value)
    self.text = value
    if not value:find('Loading item name...',1,true) then print(value) end
  end
  ForeverMarketSetItemText(line,text)
end
