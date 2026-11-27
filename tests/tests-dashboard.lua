dofile('src/ItemNames.lua')
local all,events={},{}
local function widget(kind,name,parent)
  local w={parent=parent,shown=true,kind=kind,name=name}
  for _,k in ipairs({'SetPoint','SetSize','SetWidth','SetJustifyH','SetWordWrap','SetFrameStrata','SetClampedToScreen','SetMovable','RegisterForDrag','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','EnableMouse','Raise','SetAutoFocus','SetAllPoints','ClearAllPoints','SetColorTexture','SetTextColor','SetFocus','ClearFocus'})do w[k]=function()end end
  function w:SetText(t)self.text=t end
  function w:GetText()return self.text or '' end
  function w:GetName()return self.name end
  function w:SetEnabled(v)self.enabled=v end
  function w:Hide()self.shown=false end
  function w:Show()self.shown=true;if self.OnShow then self:OnShow()end end
  function w:IsShown()return self.shown end
  function w:IsVisible()return self.shown and (not self.parent or self.parent:IsVisible())end
  function w:SetShown(v)self.shown=v end
  function w:SetScript(k,f)self[k]=f end
  function w:RegisterEvent(e)events[e]=self end
  function w:CreateTexture()return widget('texture',nil,self)end
  function w:CreateFontString()return widget('label',nil,self)end
  all[#all+1]=w;return w
end
CreateFrame=widget;UIParent=widget('frame');UISpecialFrames={};time=function()return 200000 end;date=os.date
UnitName=function()return 'Rogue' end;UnitFactionGroup=function()return 'Horde' end
GetCurrentRegion=function()return 1 end;ForeverMarketVenueRealm=function()return 'Realm' end
ForeverMarketEventRealm=function(e)return e.realm end
ForeverMarketCoins=tostring;C_Timer={After=function(_,fn)fn()end}
local account={mail={}};local fund={cash=700,flips={},sessions={}}
ForeverMarketTradingFund=function()return fund end
ForeverMarketMarginBP=function()return 500 end
ForeverMarketPaperResults=function()return {}end
ForeverMarketHistory=function()return {}end
ForeverMarketLiveSync=function()return false end
local M={scope=function()return 'Realm|Horde'end,account=function()return account end,
 fundSummary=function()return {cash=700,inventory=10,pending=0,profit=0,other=0,rows={}}end,
 settings=function()return {cutBP=500,lostDepositPerUnit=0}end,session=function()return {watches={}}end,
 runOutcomes=function()return {}end,tradeResults=function()return {count=0,spent=0,profit=0,items={}}end}
ForeverMarketDB={};ForeverMarketTools=M
local ahTab
ForeverMarketTab=function(_,frame,name)assert(name=='Analytics');ahTab=frame;frame.selectTab=function()frame:Show()end end
dofile('src/Dashboard.lua')
local function find(root,text)
 for _,w in ipairs(all) do
  if w:IsVisible() and w.text==text then
   local p=w;while p do if p==root then return w end;p=p.parent end
  end end
end
M.openDashboard()
local hub
for _,w in ipairs(all) do if w.name=='ForeverMarketDashboard' then hub=w end end
assert(find(hub,'Spendable trading cash'));find(hub,'Settings'):OnClick()
assert(find(hub,'Minimum flip profit (%)'))
find(hub,'Minimum flip profit (%)').parent:OnClick()
for _,w in ipairs(all) do if w.kind=='EditBox' and w:IsVisible() then w:SetText('8')end end
find(hub,'Save'):OnClick();assert(ForeverMarketDB.buyTargetBP==800)
AuctionHouseFrame=widget('frame');events.AUCTION_HOUSE_SHOW:OnEvent('AUCTION_HOUSE_SHOW')
M.openAnalytics();assert(ahTab:IsShown() and not find(ahTab,'Settings') and not find(ahTab,'Tools'))
for _,section in ipairs({'Sales & profit','Item history','Watchlist','Research','Overview'})do find(ahTab,section):OnClick()end
ForeverMarketResearch={realm='Realm',faction='Horde',region=1,at=time(),items={},simulation={at=time(),paths=200,budget=10000,results={{scenario='Slow sales',policy='5% target',medianProfit=32}}}}
find(ahTab,'Research'):OnClick();assert(find(ahTab,'Slow sales'))
ForeverMarketResearch.realm='Other';find(ahTab,'Refresh'):OnClick();assert(not find(ahTab,'Slow sales'))
