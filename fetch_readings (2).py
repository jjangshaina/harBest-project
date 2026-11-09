"""
Pull the latest HarBest readings from Supabase and write a clean CSV for
harbest_forecast_pipeline.py.

    python fetch_readings.py --out sensor_readings_live.csv
    python fetch_readings.py --from-csv "sensor_readings_rows 1.csv" --out test.csv   # offline test

Needs env vars SUPABASE_URL and SUPABASE_KEY (unless --from-csv is used).
"""
import argparse, os, sys
import numpy as np
import pandas as pd

TABLE = os.environ.get("READINGS_TABLE", "sensor_readings")
DEVICE_ID = "harbest_pi_zero_w"
FIRMWARE_FIX = pd.Timestamp("2026-10-08", tz="UTC")   # before this, moisture & pH were stored /10
PAGE = 1000


def fail(msg):
    print(f"\nERROR: {msg}\n", file=sys.stderr)
    sys.exit(1)


def get_env():
    url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = os.environ.get("SUPABASE_KEY", "").strip()
    if not url:
        fail("SUPABASE_URL is empty. Add it under GitHub -> Settings -> Secrets and variables -> Actions.")
    if not key:
        fail("SUPABASE_KEY is empty. Add the secret SUPABASE_SERVICE_KEY (the service_role key).")
    if not url.startswith("https://"):
        fail(f"SUPABASE_URL should look like https://xxxx.supabase.co (got '{url[:30]}...').")
    if url.endswith("/rest/v1"):
        url = url[: -len("/rest/v1")]
    return url, key


def fetch_supabase():
    import requests
    url, key = get_env()
    hdr = {"apikey": key, "Authorization": f"Bearer {key}"}
    rows, start = [], 0
    while True:
        params = {"select": "*", "device_id": f"eq.{DEVICE_ID}", "order": "timestamp.asc",
                  "offset": start, "limit": PAGE}
        try:
            r = requests.get(f"{url}/rest/v1/{TABLE}", headers=hdr, params=params, timeout=60)
        except requests.RequestException as e:
            fail(f"Could not reach Supabase: {e}")
        if r.status_code == 401:
            fail("Supabase rejected the key (401). Re-copy the service_role key into SUPABASE_SERVICE_KEY.")
        if r.status_code == 404:
            fail(f"Table '{TABLE}' not found (404). Check the readings table name in Supabase.")
        if not r.ok:
            fail(f"Supabase returned {r.status_code}: {r.text[:300]}")
        batch = r.json()
        rows += batch
        if len(batch) < PAGE:
            break
        start += PAGE
    print(f"fetched {len(rows)} rows from Supabase table '{TABLE}'")
    if not rows:
        fail(f"No rows for device '{DEVICE_ID}'. If the key is the anon key, RLS may be hiding the data.")
    return pd.DataFrame(rows)


def clean(df):
    df = df.copy()
    if "timestamp" not in df:
        fail(f"No 'timestamp' column. Columns found: {list(df.columns)}")
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True, errors="coerce", format="mixed")
    df = df.dropna(subset=["timestamp"]).sort_values("timestamp").drop_duplicates("timestamp")
    if "moisture" in df and "moisture_pct" not in df:
        df = df.rename(columns={"moisture": "moisture_pct"})
    for c in ["temperature", "humidity", "heat_index", "soil_temp", "pH", "EC", "moisture_pct",
              "nitrogen", "phosphorus", "potassium"]:
        if c in df:
            df[c] = pd.to_numeric(df[c], errors="coerce")
        else:
            df[c] = np.nan

    dead = (df["moisture_pct"] == 0) & (df["EC"] == 0)          # probe disconnected
    df.loc[dead, ["moisture_pct", "EC", "pH", "nitrogen", "phosphorus", "potassium"]] = np.nan

    old = df["timestamp"] < FIRMWARE_FIX                          # old firmware scale
    df.loc[old, "moisture_pct"] *= 10
    df.loc[old, "pH"] *= 10
    df.loc[df["pH"] == 0, "pH"] = np.nan

    print(f"cleaned: {len(df)} rows | probe-off blanked: {int(dead.sum())} | rescaled: {int(old.sum())}")
    print(f"range: {df.timestamp.min()} -> {df.timestamp.max()}")
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="sensor_readings_live.csv")
    ap.add_argument("--from-csv")
    a = ap.parse_args()
    df = pd.read_csv(a.from_csv) if a.from_csv else fetch_supabase()
    clean(df).to_csv(a.out, index=False)
    print(f"saved {a.out}")


if __name__ == "__main__":
    main()
