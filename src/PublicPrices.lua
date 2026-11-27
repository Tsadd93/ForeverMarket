-- Stable, read-only consumer interface. Base-item prices are per unit in copper.
local M=ForeverMarketTools
ForeverMarketAPI={version=1}
function ForeverMarketAPI.GetPrice(item,maxAge)
  local id=type(item)=='string' and tonumber(item:match('item:(%d+)') or item) or item
  if type(id)~='number' or id<1 or id~=math.floor(id) or not ForeverMarketDB or not UnitFactionGroup('player') then return end
  if maxAge~=nil and (type(maxAge)~='number' or maxAge<0) then return end
  local post,at,source,bulk=M.prices(id)
  local value=bulk or post
  if not value or value<=0 or not at or at>time() or maxAge and time()-at>maxAge then return end
  return value,at,source
end

-- GEC-based addons discover named price feeds through this optional registry.
local registered
local function registerFeed()
  local lib=LibStub and LibStub:GetLibrary('GECTemplate-1.0',true)
  local bridge=lib and lib.Bridge
  if not bridge or not bridge.Register or registered==bridge then return end
  local function price(id) return (ForeverMarketAPI.GetPrice(id)) end
  local function age(id)
    local _,at=ForeverMarketAPI.GetPrice(id)
    if at then return math.floor((time()-at)/86400) end
  end
  bridge.Register('forevermarket',{title='Forever Market',available=function()return true end,
    tokens={price={type='money',desc='Base item market value per unit',get=price},
      age={type='number',desc='Age of market observation in days',get=age}},
    catalog={{path='price',desc='Unit market value'},{path='age',desc='Days since observation'}}})
  registered=bridge
end
local loader=CreateFrame('Frame')
loader:RegisterEvent('ADDON_LOADED')
loader:SetScript('OnEvent',registerFeed)
registerFeed()
