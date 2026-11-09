"""
HarBest forecasting pipeline  (re-runnable: drop in a new CSV export and run it)

    python harbest_forecast_pipeline.py --csv sensor_readings_corrected.csv

Steps (mirrors the methodology list):
  1 Data collection   2 Data cleaning     3 Feature engineering
  4 Data encoding     5 Feature selection 6 EDA
  7 Model training    8 Model evaluation  9 Algorithm selection
 10 System integration (JSON + SQL + optional push to Supabase)

The pipeline adapts to how much continuous data it finds. With less than
MIN_HOURS_FOR_ML hours it stays in "experimental" mode and forecasts with the
persistence baseline only (still reporting how the ML models would score).
"""
import argparse, json, os, warnings
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

warnings.filterwarnings("ignore")

# ============================== CONFIG ====================================
TARGETS = ["moisture_pct", "temperature", "humidity", "pH", "EC"]
SENSORS = ["temperature", "humidity", "soil_temp", "pH", "EC", "moisture_pct"]
UNITS = {"moisture_pct": "%", "temperature": "°C", "humidity": "%", "pH": "", "EC": "µS/cm"}
# PLACEHOLDER optimal ranges - replace with values justified for mustard greens.
OPTIMAL = {"moisture_pct": (60, 80), "temperature": (15, 25),
           "humidity": (60, 80), "pH": (6.0, 7.0), "EC": None}
TZ = "Asia/Manila"
DEVICE_ID = "harbest_pi_zero_w"
GAP_SECONDS = 600            # a gap longer than this starts a new segment
MIN_SEGMENT_MIN = 30         # shorter segments are ignored for training
WARMUP_MIN = 10              # drop the first minutes after each restart (probe warm-up spikes)
MIN_HOURS_FOR_ML = 72        # below this: persistence-only "experimental" mode
STALE_HOURS = 6              # latest reading older than this -> app shows "stale"
N_LAGS = 5
HISTORY_HOURS = 12
FEATURE_SETS = ["lags", "lags+time", "lags+time+sensors"]
# ==========================================================================

def banner(n, title):
    print(f"\n{'=' * 64}\nSTEP {n}: {title}\n{'=' * 64}")

# ---------------------------------------------------------------- STEP 1
def step1_collect(csv):
    banner(1, "Data collection")
    df = pd.read_csv(csv)
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    df = df.sort_values("timestamp").drop_duplicates("timestamp").reset_index(drop=True)
    sensors = [c for c in SENSORS if c in df and df[c].notna().any()]
    missing = [c for c in SENSORS if c not in sensors]
    print(f"rows: {len(df)} | {df.timestamp.min()} -> {df.timestamp.max()}")
    print(f"usable sensor columns: {sensors}")
    if missing:
        print(f"NOT available / empty (ignored): {missing}")
    return df, sensors

# ---------------------------------------------------------------- STEP 2
def step2_clean(df, sensors):
    banner(2, "Data cleaning")
    df = df.copy()
    both_zero = (df["temperature"] == 0) & (df["humidity"] == 0)
    df.loc[both_zero, ["temperature", "humidity"]] = np.nan      # failed DHT22 reads
    gap = df["timestamp"].diff().dt.total_seconds()
    df["moisture_jump"] = ((df["moisture_pct"].diff().abs() > 15) & (gap < 60)).astype(int) \
        if "moisture_pct" in df else 0
    df["segment_id"] = (gap.fillna(0) > GAP_SECONDS).cumsum()
    seg = df.groupby("segment_id")["timestamp"].agg(start="min", end="max", n_rows="count")
    seg["minutes"] = (seg["end"] - seg["start"]).dt.total_seconds() / 60
    seg["usable"] = seg["minutes"] >= MIN_SEGMENT_MIN
    usable_hours = seg.loc[seg.usable, "minutes"].sum() / 60
    print(f"failed 0/0 DHT22 reads blanked: {int(both_zero.sum())}")
    print(f"segments: {len(seg)} | usable (>= {MIN_SEGMENT_MIN} min): {int(seg.usable.sum())} "
          f"| usable hours: {usable_hours:.1f}")
    return df, seg, usable_hours

def decide_mode(usable_hours):
    if usable_hours < 24:
        step, horizons = 1, [5, 15, 30]
    elif usable_hours < 24 * 7:
        step, horizons = 5, [15, 30, 60, 180]
    else:
        step, horizons = 5, [60, 180, 360, 720, 1440]
    return dict(step=step, horizons=horizons,
                ml_ok=usable_hours >= MIN_HOURS_FOR_ML,
                snaive_ok=usable_hours >= 48,
                status="ok" if usable_hours >= MIN_HOURS_FOR_ML else "experimental")

def resample(df, seg, sensors, step):
    parts = []
    for sid in seg.index[seg.usable]:
        s = df[df.segment_id == sid].set_index("timestamp")
        s = s[s.index >= s.index.min() + pd.Timedelta(minutes=WARMUP_MIN)]
        r = s[sensors].resample(f"{step}min").mean().interpolate(limit=3)
        r["moisture_jump"] = s["moisture_jump"].resample(f"{step}min").max().fillna(0)
        r["segment_id"] = sid
        parts.append(r.dropna(subset=sensors, how="all"))
    return pd.concat(parts)

# ------------------------------------------------------------ STEPS 3-5
def build_frame(ts, target, h, fset, step, sensors, snaive_P):
    out = []
    for sid, seg in ts.groupby("segment_id"):
        s = seg[target]
        X = pd.DataFrame({f"lag{l}": s.shift(l) for l in range(N_LAGS)}, index=seg.index)
        if fset != "lags":
            X["roll6"] = s.rolling(6, min_periods=6).mean()
            tl = (seg.index + pd.Timedelta(minutes=h * step)).tz_convert(TZ)
            frac = tl.hour + tl.minute / 60
            X["hour_sin"] = np.sin(2 * np.pi * frac / 24)
            X["hour_cos"] = np.cos(2 * np.pi * frac / 24)
        if fset == "lags+time+sensors":
            for c in sensors:
                if c != target:
                    X[c] = seg[c]
            last, since = None, []
            for i, w in enumerate(seg["moisture_jump"].values):
                if w > 0:
                    last = i
                since.append(min((i - last) * step, 1440) if last is not None else 1440)
            X["min_since_wet"] = since
        feats = list(X.columns)
        X["y"] = s.shift(-h)
        X["snaive"] = s.shift(snaive_P - h) if snaive_P and snaive_P > h else np.nan
        out.append(X)
    F = pd.concat(out)
    feats = [c for c in F.columns if c not in ("y", "snaive")]
    return F, feats

def step4_encode(F, feats):
    """All inputs are numeric (flags are 0/1, time is sin/cos), so nothing needs
    one-hot encoding. Categorical labels such as crop_health are NOT used as inputs."""
    assert all(np.issubdtype(F[c].dtype, np.number) for c in feats)
    return F

def make_model(kind):
    if kind == "ridge":
        return make_pipeline(StandardScaler(), Ridge(alpha=10.0))
    return GradientBoostingRegressor(n_estimators=150, max_depth=2, learning_rate=0.05,
                                     subsample=0.8, random_state=0)

def metrics(y, p, base):
    mae = mean_absolute_error(y, p)
    base_mae = mean_absolute_error(y, base)
    try:
        r2 = r2_score(y, p)
    except Exception:
        r2 = np.nan
    return dict(MAE=mae, RMSE=mean_squared_error(y, p) ** 0.5, R2=r2,
                skill=(1 - mae / base_mae) if base_mae > 0 else np.nan)

# ------------------------------------------------------------ STEPS 7-9
def run_target(ts, target, h_min, cfg, sensors, report):
    step = cfg["step"]
    h = h_min // step          # horizon in resampled steps
    P = 1440 // step if cfg["snaive_ok"] else None
    frames, feats_by = {}, {}
    for fs in FEATURE_SETS:
        F, feats = build_frame(ts, target, h, fs, step, sensors, P)
        step4_encode(F, feats)
        frames[fs], feats_by[fs] = F, feats
    valid = None
    for fs, F in frames.items():
        ok = F.dropna(subset=feats_by[fs] + ["y"]).index
        valid = ok if valid is None else valid.intersection(ok)
    valid = valid.sort_values()
    n = len(valid)
    n_tr, n_va = int(n * 0.6), int(n * 0.2)
    tr, va, te = valid[:n_tr], valid[n_tr:n_tr + n_va], valid[n_tr + n_va:]
    base_F = frames["lags"]
    persist = lambda idx: base_F.loc[idx, "lag0"].values
    chosen = dict(kind="persistence", fset="lags")
    can_ml = cfg["ml_ok"] and len(tr) >= 40 and len(va) >= 10 and len(te) >= 10

    # candidates scored on validation (Steps 5 + 9)
    val_scores = {}
    if len(va) >= 5:
        val_scores[("persistence", "lags")] = mean_absolute_error(base_F.loc[va, "y"], persist(va))
    if len(tr) >= 40 and len(va) >= 5:
        for fs in FEATURE_SETS:                                # Step 5: feature selection
            for kind in ("ridge", "gbm"):
                F, ft = frames[fs], feats_by[fs]
                m = make_model(kind).fit(F.loc[tr, ft], F.loc[tr, "y"] - F.loc[tr, "lag0"])
                p = F.loc[va, "lag0"] + m.predict(F.loc[va, ft])
                val_scores[(kind, fs)] = mean_absolute_error(F.loc[va, "y"], p)
    if P and len(va) >= 5:
        sv = base_F.loc[va].dropna(subset=["snaive"])
        if len(sv) >= 20:
            val_scores[("snaive", "lags")] = mean_absolute_error(sv["y"], sv["snaive"])
    best_ml = min((k for k in val_scores if k[0] in ("ridge", "gbm")),
                  key=val_scores.get, default=None)
    if can_ml and val_scores:
        k = min(val_scores, key=val_scores.get)
        chosen = dict(kind=k[0], fset=k[1])

    # test metrics for persistence, best ML (even if not chosen) and the chosen model
    def fit_predict(kind, fs, fit_idx, pred_idx):
        F, ft = frames[fs], feats_by[fs]
        if kind == "persistence":
            return F.loc[pred_idx, "lag0"].values
        if kind == "snaive":
            return F.loc[pred_idx, "snaive"].values
        m = make_model(kind).fit(F.loc[fit_idx, ft], F.loc[fit_idx, "y"] - F.loc[fit_idx, "lag0"])
        return F.loc[pred_idx, "lag0"].values + m.predict(F.loc[pred_idx, ft])

    test_rows, resid = {}, None
    if len(te) >= 5:
        y_te, base_te = base_F.loc[te, "y"].values, persist(te)
        trva = tr.append(va) if hasattr(tr, "append") else tr.union(va)
        todo = {("persistence", "lags"), (chosen["kind"], chosen["fset"])}
        if best_ml:
            todo.add(best_ml)
        for kind, fs in todo:
            if kind == "snaive":
                continue
            try:
                p = fit_predict(kind, fs, trva, te)
                test_rows[(kind, fs)] = metrics(y_te, p, base_te)
                if (kind, fs) == (chosen["kind"], chosen["fset"]):
                    resid = y_te - p
            except Exception:
                pass
    if resid is None and len(va) >= 5:
        resid = base_F.loc[va, "y"].values - persist(va)

    for (kind, fs), v in val_scores.items():
        row = dict(variable=target, horizon_min=h * step, candidate=kind, feature_set=fs,
                   val_MAE=v, n_train=len(tr), n_val=len(va), n_test=len(te),
                   chosen=(kind, fs) == (chosen["kind"], chosen["fset"]))
        row.update({f"test_{k}": x for k, x in test_rows.get((kind, fs), {}).items()})
        report.append(row)

    # band from residuals
    if resid is not None and len(resid) >= 10:
        lo, hi = np.quantile(resid, [0.1, 0.9])
    else:
        mae = np.mean(np.abs(resid)) if resid is not None and len(resid) else 0.0
        lo, hi = -1.5 * mae, 1.5 * mae

    # forecast from the latest reading (Step 10 input)
    last_t = ts[target].dropna().index[-1]
    last_v = float(ts.loc[last_t, target])
    pred, used = last_v, "persistence"
    F, ft = frames[chosen["fset"]], feats_by[chosen["fset"]]
    if chosen["kind"] in ("ridge", "gbm") and last_t in F.index and F.loc[[last_t], ft].notna().all(axis=1).iloc[0]:
        m = make_model(chosen["kind"]).fit(F.loc[valid, ft], F.loc[valid, "y"] - F.loc[valid, "lag0"])
        pred = float(F.loc[last_t, "lag0"] + m.predict(F.loc[[last_t], ft])[0])
        used = f"{chosen['kind']} ({chosen['fset']})"
    elif chosen["kind"] == "snaive" and last_t in base_F.index and pd.notna(base_F.loc[last_t, "snaive"]):
        pred, used = float(base_F.loc[last_t, "snaive"]), "same time yesterday"
    mtr = test_rows.get((chosen["kind"], chosen["fset"])) or test_rows.get(("persistence", "lags")) or {}
    return dict(h_min=h * step, time=last_t + pd.Timedelta(minutes=h * step),
                value=pred, lower=pred + lo, upper=pred + hi, model=used,
                metrics=mtr, n_train=len(tr) + len(va)), last_t, last_v

# --------------------------------------------------------------- STEP 10
def leaves_optimal(origin_t, origin_v, fc, rng):
    if rng is None:
        return None
    lo, hi = rng
    pts = [(origin_t, origin_v)] + [(f["time"], f["value"]) for f in fc]
    inside = lambda v: lo <= v <= hi
    for (t0, v0), (t1, v1) in zip(pts[:-1], pts[1:]):
        if inside(v0) and not inside(v1):
            edge = hi if v1 > hi else lo
            frac = (edge - v0) / (v1 - v0) if v1 != v0 else 1
            return t0 + (t1 - t0) * frac
    return None

def action_text(target, status, leave_t, direction):
    when = f" around {leave_t.tz_convert(TZ):%H:%M}" if leave_t is not None else ""
    if target == "moisture_pct":
        if status == "out_of_range" and direction == "low":
            return "Moisture is below the optimal range - consider watering now."
        if status == "caution" and direction == "low":
            return f"Consider watering before{when} to keep moisture in range."
        if status == "caution":
            return f"Moisture may rise above the optimal range{when}; hold off watering."
    if status == "optimal":
        return "Forecast stays within the optimal range."
    if status == "n/a":
        return "No optimal range set for this variable."
    return f"Forecast leaves the optimal range{when}; check conditions."

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default="sensor_readings_corrected.csv")
    ap.add_argument("--out", default=str(Path(__file__).parent / "output"))
    ap.add_argument("--no-plots", action="store_true")
    ap.add_argument("--push", action="store_true", help="POST the run to Supabase (needs SUPABASE_URL / SUPABASE_KEY)")
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)

    df, sensors = step1_collect(a.csv)
    df, seg, usable_hours = step2_clean(df, sensors)
    seg.to_csv(out / "segments.csv")
    cfg = decide_mode(usable_hours)
    print(f"mode: {cfg['status']} | resample {cfg['step']} min | horizons (min): "
          f"{cfg['horizons']} | ML allowed: {cfg['ml_ok']}")
    if not seg.usable.any():
        raise SystemExit("No continuous segment long enough. Collect more continuous data.")
    ts = resample(df, seg, sensors, cfg["step"])
    targets = [t for t in TARGETS if t in sensors]

    banner(3, "Feature engineering")
    print(f"lags(0..{N_LAGS-1}), rolling mean, time-of-day sin/cos ({TZ}), other sensors, "
          f"minutes since last watering jump. Feature sets tried: {FEATURE_SETS}")
    banner(4, "Data encoding")
    print("All model inputs are numeric -> no categorical encoding needed (crop_health excluded).")
    banner(5, "Feature selection")
    print("Each feature set is scored on a validation split; the best one is kept per variable/horizon.")

    banner(6, "Exploratory data analysis")
    eda = ts[targets].describe().T.round(3)
    eda.to_csv(out / "eda_summary.csv")
    print(eda[["count", "mean", "std", "min", "max"]].to_string())
    if usable_hours >= 24:
        loc = ts.copy(); loc["hour"] = loc.index.tz_convert(TZ).hour
        loc.groupby("hour")[targets].mean().round(2).to_csv(out / "hourly_profile.csv")
        print("saved hourly_profile.csv (daily cycle)")

    banner("7-9", "Training, evaluation and algorithm selection")
    report, results, origins = [], {}, {}
    for t in targets:
        results[t] = []
        for h in cfg["horizons"]:
            r, last_t, last_v = run_target(ts, t, h, cfg, sensors, report)
            results[t].append(r); origins[t] = (last_t, last_v)
        print(f"{t:13s} -> " + ", ".join(f"{r['h_min']}m:{r['model'].split(' ')[0]}" for r in results[t]))
    rep = pd.DataFrame(report).round(4)
    rep.to_csv(out / "model_report.csv", index=False)

    banner(10, "System integration")
    now = datetime.now(timezone.utc)
    latest = ts.index.max()
    stale = (pd.Timestamp(now) - latest) > pd.Timedelta(hours=STALE_HOURS)
    payload = dict(
        generated_at=now.isoformat(), device_id=DEVICE_ID, status=cfg["status"],
        stale=bool(stale), latest_reading=latest.isoformat(),
        note=("Experimental: not enough continuous data for machine learning; "
              "forecasts use the last-value baseline." if cfg["status"] == "experimental"
              else "Models selected by validation error."),
        data_summary=dict(rows=int(len(df)), usable_hours=round(usable_hours, 1),
                          resample_min=cfg["step"], horizons_min=[r["h_min"] for r in results[targets[0]]]),
        variables={})
    flat = []
    for t in targets:
        origin_t, origin_v = origins[t]
        fc = results[t]
        rng = OPTIMAL.get(t)
        leave = leaves_optimal(origin_t, origin_v, fc, rng)
        if rng is None:
            status, direction = "n/a", None
        elif not (rng[0] <= origin_v <= rng[1]):
            status, direction = "out_of_range", "low" if origin_v < rng[0] else "high"
        elif leave is not None:
            status = "caution"
            direction = "low" if min(f["value"] for f in fc) < rng[0] else "high"
        else:
            status, direction = "optimal", None
        seg_id = ts.loc[origin_t, "segment_id"]
        hist = ts[(ts.segment_id == seg_id) & (ts.index > origin_t - pd.Timedelta(hours=HISTORY_HOURS))][t].dropna()
        hist = hist.iloc[:: max(1, len(hist) // 96)]
        m = fc[0]["metrics"]
        mae_txt = f"{m['MAE']:.2f}" if m and "MAE" in m else "n/a"
        payload["variables"][t] = dict(
            unit=UNITS[t], optimal=list(rng) if rng else None, status=status,
            current=dict(time=origin_t.isoformat(), value=round(origin_v, 3)),
            leaves_optimal_at=leave.isoformat() if leave is not None else None,
            suggested_action=action_text(t, status, leave, direction),
            history=[dict(t=i.isoformat(), v=round(float(v), 3)) for i, v in hist.items()],
            forecast=[dict(t=f["time"].isoformat(), horizon_min=f["h_min"], value=round(f["value"], 3),
                           lower=round(f["lower"], 3), upper=round(f["upper"], 3)) for f in fc],
            model=fc[0]["model"],
            footer=(f"Model: last-value baseline (no training), checked on {fc[0]['n_train']} readings, "
                    if fc[0]["model"] == "persistence" else
                    f"Model: {fc[0]['model']}, trained on {fc[0]['n_train']} readings, ")
                   + f"typical error (MAE) {mae_txt}{UNITS[t]}. Forecasts are estimates and get less certain further ahead.")
        for f in fc:
            flat.append(dict(device_id=DEVICE_ID, variable=t, made_at=now.isoformat(),
                             target_time=f["time"].isoformat(), horizon_min=f["h_min"],
                             predicted=round(f["value"], 3), lower=round(f["lower"], 3),
                             upper=round(f["upper"], 3), model=f["model"]))
    (out / "forecast_output.json").write_text(json.dumps(payload, indent=2))
    pd.DataFrame(flat).to_csv(out / "forecast_rows.csv", index=False)
    print(f"saved forecast_output.json ({cfg['status']}), forecast_rows.csv, model_report.csv")
    if stale:
        print(f"NOTE: latest reading ({latest}) is older than {STALE_HOURS} h -> 'stale': true")

    if not a.no_plots:
        import matplotlib; matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, axes = plt.subplots(len(targets), 1, figsize=(8, 2.7 * len(targets)))
        for ax, t in zip(np.atleast_1d(axes), targets):
            v = payload["variables"][t]
            h = pd.DataFrame(v["history"]); f = pd.DataFrame(v["forecast"])
            h["t"] = pd.to_datetime(h["t"]).dt.tz_convert(TZ); f["t"] = pd.to_datetime(f["t"]).dt.tz_convert(TZ)
            if v["optimal"]:
                ax.axhspan(*v["optimal"], color="#cfe8cf", alpha=0.6, label="optimal")
            ax.plot(h["t"], h["v"], color="#2f7d32", label="actual")
            ax.plot(f["t"], f["value"], "--o", color="#e07b1a", ms=3, label="forecast")
            ax.fill_between(f["t"], f["lower"], f["upper"], color="#f5c08a", alpha=0.5, label="confidence")
            ax.set_title(f"{t} - {v['status']}", fontsize=10); ax.legend(fontsize=7, loc="upper left")
        fig.tight_layout(); fig.savefig(out / "forecast_preview.png", dpi=110)
        print("saved forecast_preview.png")

    if a.push:
        push_to_supabase(payload, flat, cfg, now)


def push_to_supabase(payload, flat, cfg, now):
    import sys, requests
    url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = os.environ.get("SUPABASE_KEY", "").strip()
    if not url or not key:
        sys.exit("ERROR: SUPABASE_URL / SUPABASE_KEY secrets are missing.")
    hdr = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json",
           "Prefer": "return=representation"}
    # NaN is not valid JSON -> convert to null
    body = json.loads(json.dumps(dict(device_id=DEVICE_ID, made_at=now.isoformat(),
                                      status=cfg["status"], summary=payload), default=str)
                      .replace("NaN", "null"))
    r = requests.post(f"{url}/rest/v1/forecast_runs", headers=hdr, json=body, timeout=60)
    if r.status_code == 404:
        sys.exit("ERROR: table 'forecast_runs' does not exist. Run supabase/forecasts.sql in the SQL Editor.")
    if r.status_code in (401, 403):
        sys.exit(f"ERROR: Supabase refused the insert ({r.status_code}). Use the service_role key. {r.text[:200]}")
    if not r.ok:
        sys.exit(f"ERROR: forecast_runs insert failed {r.status_code}: {r.text[:300]}")
    run_id = r.json()[0]["id"]
    print(f"pushed run {run_id} to forecast_runs (this is what the app reads)")

    rows = json.loads(json.dumps([dict(x, run_id=run_id) for x in flat]).replace("NaN", "null"))
    r2 = requests.post(f"{url}/rest/v1/forecasts", headers=hdr, json=rows, timeout=60)
    if r2.ok:
        print(f"pushed {len(rows)} rows to forecasts")
    else:  # optional table - don't fail the whole run for it
        print(f"WARNING: forecasts insert skipped ({r2.status_code}): {r2.text[:200]}")

if __name__ == "__main__":
    main()
