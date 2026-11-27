"""Refresh the bounded regional sample used in Forever Market releases."""
import csv
import io
import math
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen

REGIONS = ((1, "us"), (2, "kr"), (3, "eu"), (4, "tw"))
ROOT = Path(__file__).resolve().parent
def fetch(region):
    code, slug = region
    url = f"https://public-data.tradeskillmaster.com/forever/{slug}/region/items.csv"
    with urlopen(url, timeout=25) as response:
        rows = csv.DictReader(io.TextIOWrapper(response, encoding="utf-8-sig"))
        records = []
        for row in rows:
            try:
                item = int(row["itemId"])
                price = int(row["marketValue"])
                rate = float(row["saleRate"])
                sold = float(row["soldPerDay"])
                at = int(datetime.fromisoformat(row["updatedAt"].replace("Z", "+00:00")).timestamp())
            except (ValueError, TypeError):
                continue
            age = datetime.now(timezone.utc).timestamp() - at
            if item > 0 and price > 0 and 0 <= rate <= 1 and math.isfinite(sold) and sold >= 0 and 0 <= age <= 7*86400:
                records.append((item, price, rate, sold, at))
    if not records:
        raise ValueError(f"No recent regional sales evidence for {slug}")
    records.sort(key=lambda r: (-r[3], r[0]))
    return code, records[:1000]

if __name__ == "__main__":
    lines = ["-- Public regional observations from TradeSkillMaster (tradeskillmaster.com/public-data).",
             "-- Columns: market value in copper, sale rate, units per day, observation time (UTC).",
             "if not GetCurrentRegion then return end", "local region=GetCurrentRegion()"]
    with ThreadPoolExecutor(4) as pool:
        for code, rows in pool.map(fetch, REGIONS):
            lines.append(f"if region=={code} then ForeverMarketRegionPrices={{")
            lines.extend(f"  [{i}]={{{price},{rate},{sold},{at}}}," for i,price,rate,sold,at in rows)
            lines.append("} end")
            print(code, len(rows))
    (ROOT / "src" / "RegionalPrices.lua").write_bytes(("\n".join(lines)+"\n").encode())
