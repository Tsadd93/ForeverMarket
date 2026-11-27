dofile('src/ItemNames.lua')
-- Exercise a complete native browse with no Auctionator, LibStub or desktop.
date=os.date
local clock,ready=0,false
function GetTime()return clock end
function time()return 1800000000 end
function GetRealmName()return 'Realm' end
function UnitFactionGroup()return 'Horde' end
function GetCurrentRegion()return 1 end
local frames={}
local function frame()
 local f={visible=true}
 for _,k in ipairs({'SetPoint','SetSize','SetText','SetJustifyH','SetWidth','SetWordWrap','SetEnabled','RegisterEvent'}) do f[k]=function()end end
 function f:SetText(text)self.text=text end
 function f:SetScript(k,fn)self[k]=fn end
 function f:Hide()self.visible=false;if self.OnHide then self:OnHide() end end
 function f:Show()self.visible=true end
 function f:IsVisible()return self.visible end
 f.CreateFontString=frame
 frames[#frames+1]=f;return f
end
CreateFrame=frame
local panel
AuctionHouseFrame={Tabs={frame()},SetDisplayMode=function()end,SetTitle=function()end}
PanelTemplates_DeselectTab=function()end
PanelTemplates_SelectTab=function()end
PanelTemplates_TabResize=function()end
function hooksecurefunc(t,k,fn)
 local old=t[k];t[k]=function(...)old(...);fn(...)end
end
local sends,more,full=0,0,false
local rows={{itemKey={itemID=1},minPrice=16,totalQuantity=2}}
C_AuctionHouse={SendBrowseQuery=function()sends=sends+1 end,RequestMoreBrowseResults=function()more=more+1 end,
 GetBrowseResults=function()return rows end,HasFullBrowseResults=function()return full end,
 IsThrottledMessageSystemReady=function()return ready end}
dofile('src/History.lua')
ForeverMarketResults=function()end;ForeverMarketRowArt=function()end;ForeverMarketCoins=tostring
C_Item={GetItemNameByID=function(id)return 'Item '..id end}
dofile('src/Scan.lua')
local events=frames[#frames]
events:OnEvent('AUCTION_HOUSE_SHOW')
for _,f in ipairs(frames)do if f.selectTab then panel=f end end
ForeverMarketScan();panel:OnUpdate();assert(sends==0)
ready=true;panel:OnUpdate();assert(sends==1)
events:OnEvent('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');panel:OnUpdate();assert(more==1)
full=true;rows[2]={itemKey={itemID=2,itemLevel=17},minPrice=78,totalQuantity=3}
events:OnEvent('AUCTION_HOUSE_BROWSE_RESULTS_ADDED')
assert(ForeverMarketHistory()['g:2:17'].m==78 and ForeverMarketHistory()['1'].m==16)
assert(not ForeverMarketHistory()['1'].bulk)
local function findText(text)
 for _,f in ipairs(frames) do if f.text==text then return f end end
end
assert(findText('Item 2 (17)') and findText('Saved observations  /  2 items by supply'))
for id=3,13 do ForeverMarketObserve(tostring(id),50,id) end
panel:OnShow();assert(findText('Page 1 / 2') and findText('Item 13'))
findText('Next'):OnClick();assert(findText('Page 2 / 2') and not findText('Item 13'))
findText('Previous'):OnClick();assert(findText('Item 13'))
clock=30
ForeverMarketSnapshot=function()return {at=0,rows=2,books={}} end
ForeverMarketScan();panel:OnUpdate();assert(sends==2)
events:OnEvent('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
assert(findText('Scan complete / 2 item prices saved.'))
print('PASS: standalone native tab, throttling, pagination, gear and commodity discovery')
