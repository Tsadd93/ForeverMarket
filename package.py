from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo

root = Path(__file__).resolve().parent
toc = (root / "ForeverMarket.toc").read_bytes()
version = next(s.split(": ", 1)[1] for s in toc.decode().splitlines() if s.startswith("## Version:"))
modules = "Starter History Market Valuation Crafting Activity Snapshot Scan Bags SellTab BuyTab Workshop Manager TradeDesk Operations MarketDesk Session PriceRules Migration SessionViews ToolsWindow Version".split()
sections = []
for library, license_name in (("LibDeflate", "LICENSE.txt"), ("LibSerialize", "LICENSE")):
    folder = root / "vendor" / library
    source = (folder / (library + ".lua")).read_text(encoding="utf-8")
    license_text = (folder / license_name).read_text(encoding="utf-8")
    sections.append("--[===[" + license_text + "]===]\ndo local LibStub, arg = nil, nil\n"
                    + "local function loadLibrary(...)\n" + source + "\nend\n"
                    + "ForeverMarket" + library + " = loadLibrary() end\n")
for name in modules:
    file = name + ".lua"
    source = (root / "src" / file).read_bytes().decode("utf-8-sig", errors="replace")
    sections.append("do local function loadModule()\n" + source +
                    "\nend local ok,err=pcall(loadModule); if not ok then print('Forever Market " +
                    file + " failed: '..tostring(err)) end end\n")
folder = root / "vendor" / "AceSerializer"
sections.append("--[===[" + (folder / "LICENSE.txt").read_text() + "]===]\ndo\n"
                "ForeverMarketAceSerializer = {}\nlocal LibStub = {NewLibrary = function() return ForeverMarketAceSerializer end}\n"
                + (folder / "AceSerializer.lua").read_text() + "\nend\n")
target = root / "dist" / ("ForeverMarket-" + version + "-forever.zip")
target.parent.mkdir(exist_ok=True)
def add(z, name, data):
    entry = ZipInfo(name, (2020, 1, 1, 0, 0, 0))
    entry.compress_type = ZIP_DEFLATED
    entry.create_system = 3
    entry.external_attr = 0o100644 << 16
    z.writestr(entry, data)

with ZipFile(target, "w", ZIP_DEFLATED) as z:
    for name in ("ForeverMarket.toc", "ForeverMarket_Forever.toc"):
        add(z, "ForeverMarket/" + name, toc)
    add(z, "ForeverMarket/Research.lua", "-- Optional desktop research. Safe to leave empty.\n")
    add(z, "ForeverMarket/Market.lua", "\n".join(sections))
print(target)
