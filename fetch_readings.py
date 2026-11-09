"""
Pull the latest HarBest readings from Supabase and write a clean CSV that
harbest_forecast_pipeline.py can read directly (replaces the manual
"sensor_readings_corrected.csv" export).

    python fetch_readings.py --out sensor_readings_live.csv
    python fetch_readings.py --from-csv "sensor_readings_rows 1.csv" --out test.csv   # offline test

Needs env vars SUPABASE_URL and SUPABASE_KEY (unless --from-csv is used).

Corrections applied automatically (same as the hand-made corrected file):
  * before FIRMWARE_FIX the soil probe logged moisture and pH at 1/10 scale -> x10
  * moisture == 0 and EC == 0 together means the probe was disconnected -> blank
  * column "moisture" is renamed to "moisture_pct" (name the pipeline expects)
"""
import argparse, os
import numpy as np
import pandas as pd

TABLE = "sensor_readings"
DEVICE_ID = "harbest_pi_zero_w"
FIRMWARE_FIX = pd.Timestamp("2026-10-08", tz="UTC")   # first day values arrive in correct scale
COLUMNS = "id,device_id,timestamp,temperature,humidity,heat_index,soil_temp,crop_health,pH,EC,moisture"
PAGE = 1000


def fetch_supabase():
    import requests
    url, key = os.environ["SUPABASE_URL"].rstrip("/"), os.environ["SUPABASE_KEY"]
    hdr = {"apikey": key, "Authorization": f"Bearer {key}"}
    rows, start = [], 0
    while True:
        params = {"select": "*", "device_id": f"eq.{DEVICE_ID}", "order": "timestamp.asc",
                  "offset": start, "limit": PAGE}
        r = requests.get(f"{url}/rest/v1/{TABLE}", headers=hdr, params=params, timeout=60)
        r.raise_for_status()
        batch = r.json()
        rows += batch
        if len(batch) < PAGE:
            break
        start += PAGE
    print(f"fetched {len(rows)} rows from Supabase")
    return pd.DataFrame(rows)


def clean(df):
    df = df.copy()
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    df = df.sort_values("timestamp").drop_duplicates("timestamp")
    if "moisture" in df and "moisture_pct" not in df:
        df = df.rename(columns={"moisture": "moisture_pct"})
    for c in ["temperature", "humidity", "heat_index", "soil_temp", "pH", "EC", "moisture_pct"]:
        if c in df:
            df[c] = pd.to_numeric(df[c], errors="coerce")

    # probe disconnected: everything reads 0
    dead = (df.get("moisture_pct") == 0) & (df.get("EC") == 0)
    df.loc[dead, ["moisture_pct", "EC", "pH"]] = np.nan

    # old firmware stored moisture and pH divided by 10
    old = df["timestamp"] < FIRMWARE_FIX
    df.loc[old, "moisture_pct"] *= 10
    df.loc[old, "pH"] *= 10
    df.loc[df["pH"] == 0, "pH"] = np.nan

    print(f"cleaned: {len(df)} rows | probe-off rows blanked: {int(dead.sum())} "
          f"| rescaled (pre-{FIRMWARE_FIX.date()}): {int(old.sum())}")
    print(f"range: {df.timestamp.min()} -> {df.timestamp.max()}")
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="sensor_readings_live.csv")
    ap.add_argument("--from-csv", help="use a CSV export instead of Supabase (for testing)")
    a = ap.parse_args()
    df = pd.read_csv(a.from_csv) if a.from_csv else fetch_supabase()
    if df.empty:
        raise SystemExit("No readings returned.")
    clean(df).to_csv(a.out, index=False)
    print(f"saved {a.out}")


if __name__ == "__main__":
    main()
