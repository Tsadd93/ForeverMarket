function CreateFrame()return{RegisterEvent=function()end,SetScript=function()end}end
function ForeverMarketPostPrice(p)return math.max(1,p-2)end
function ForeverMarketSaleNet(n)return math.floor(n*.95)end
function ForeverMarketDepositLoss(n)return 0 end
dofile('src/Bags.lua')
local function check(changes)
 local x={class=7,vendor=10,price=200,age=10,count=20};for k,v in pairs(changes or {})do x[k]=v end;return ForeverMarketBagDecision(x)
end
assert(check()=='ah')
assert(check({price=12})==nil)
assert(check({bound=true})==nil)
assert(check({quest=true})==nil)
assert(check({class=4})==nil)
assert(check({age=86401})=='check')
assert(check({age=-1})=='check')
assert(check({price=0})=='check')
assert(check({price=25,count=1})==nil)
print('PASS: bag markers, fees/deposit allowance, low-margin stacks, bound/quest exclusions, missing and stale prices')
local tick,clear,badge,tint
local function noop()end
local function widget(parent)
 local w={parent=parent,shown=true}
 for _,k in ipairs({'SetPoint','SetSize','SetHeight','SetWidth','SetFrameLevel','ClearAllPoints','SetAllPoints','SetColorTexture','SetFont','RegisterEvent'})do w[k]=noop end
 function w:SetPoint(point,parent,relative,x,y)self.anchor={point,parent,relative,x,y}end
 function w:SetParent(p)self.parent=p end
 function w:GetParent()return self.parent end
 function w:IsShown()return self.shown end
 function w:GetFrameLevel()return 1 end
 function w:SetShown(b)self.shown=b end
 function w:Hide()self.shown=false end
 function w:Show()self.shown=true end
 function w:SetText(t)self.text=t end
 function w:SetScript(k,fn)self[k]=fn;if k=='OnUpdate' then tick=fn end end
 return w
end
UIParent=widget();ContainerFrameCombinedBags=widget()
local bag=ContainerFrameCombinedBags;bag.GetLeft=function()return 500 end
local slot=widget(bag);slot.IsObjectType=function(_,k)return k=='Button'end
slot.GetBagID=function()return 0 end;slot.GetID=function()return 1 end
bag.GetChildren=function()return slot end
slot.CreateTexture=function(_,_,_,_,layer)local t=widget(slot);if layer==5 then tint=t end;return t end
slot.CreateFontString=function()badge=widget(slot);return badge end
CreateFrame=function(kind,_,parent)local w=widget(parent);if kind=='Button' then clear=w end;return w end
local guid='A'
C_Item={GetItemGUID=function()return guid end,GetItemInfo=function()return 'Gear' end}
ItemLocation={CreateFromBagAndSlot=function()return {}end}
UnitGUID=function()return 'character' end;InCombatLockdown=function()return false end
ForeverMarketDB={};C_Container={GetContainerNumSlots=function(b)return b==0 and 1 or 0 end,
 GetContainerItemInfo=function()return {itemID=42,hyperlink='item:42',stackCount=1} end}
dofile('src/Bags.lua')
local s={bag=0,slot=1,loc={},link='item:42',count=1};local q={observed=10}
ForeverMarketVendorDecision(s,q,true);tick(nil,1)
assert(badge.text:find('SELL') and tint.shown and clear.shown and clear.parent==bag)
assert(clear.anchor[1]=='BOTTOMLEFT' and clear.anchor[2]==bag and clear.anchor[3]=='BOTTOMLEFT')
clear:OnClick();assert(badge.text=='' and not tint.shown and not clear.shown)
ForeverMarketVendorDecision(s,q,true);tick(nil,1);assert(not tint.shown)
q.observed=20;ForeverMarketVendorDecision(s,q,true);tick(nil,1);assert(tint.shown)
guid='B';tick(nil,1);assert(not tint.shown)
guid='A';ForeverMarketVendorDecision(s,q,false);tick(nil,1);assert(not tint.shown)
