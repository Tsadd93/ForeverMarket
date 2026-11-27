import re
from pathlib import Path
from tempfile import NamedTemporaryFile
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo

root = Path(__file__).resolve().parent
toc = (root / "ForeverMarket.toc").read_bytes()
version = next(s.split(": ", 1)[1] for s in toc.decode().splitlines() if s.startswith("## Version:"))
modules = "Starter RegionalPrices ItemNames History Market Valuation Crafting Activity Snapshot Scan Bags SellTab BuyTab Workshop Manager TradeDesk Operations MarketDesk Session PublicPrices CancelQueue PriceRules Migration FeedSources MarketAnalysis SessionViews ToolsWindow Dashboard Version".split()
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
    source = (root / "src" / file).read_bytes().decode("utf-8-sig")
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
    # Reject encoding damage in the actual shipped payload, including embedded library text.
    text = data if isinstance(data, str) else data.decode("utf-8")
    damaged = re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\ufffd]|\u00e2[\u20ac\u2020\u201e]|[\u00c2\u00c3][\u00a0-\u00bf]", text)
    if damaged:
        line = text.count("\n", 0, damaged.start()) + 1
        raise ValueError(f"{name}:{line}: invalid control character or corrupted UTF-8 text")
    entry = ZipInfo(name, (2020, 1, 1, 0, 0, 0))
    entry.compress_type = ZIP_DEFLATED
    entry.create_system = 3
    entry.external_attr = 0o100644 << 16
    z.writestr(entry, data)

with NamedTemporaryFile(dir=target.parent, suffix=".zip", delete=False) as staging:
    temporary = Path(staging.name)
try:
    with ZipFile(temporary, "w", ZIP_DEFLATED) as z:
        for name in ("ForeverMarket.toc", "ForeverMarket_Forever.toc"):
            add(z, "ForeverMarket/" + name, toc)
        add(z, "ForeverMarket/Research.lua", "-- Optional desktop research. Safe to leave empty.\n")
        for feed in ("DesktopRegion", "DesktopRealm"):
            add(z, "ForeverMarket/" + feed + ".lua", "-- Optional desktop prices.\n")
        add(z, "ForeverMarket/Market.lua", "\n".join(sections))
    temporary.replace(target)
finally:
    temporary.unlink(missing_ok=True)
print(target)
