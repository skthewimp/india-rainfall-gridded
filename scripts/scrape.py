import os, sys, time, subprocess, urllib.request, urllib.parse
import xarray as xr

OUT = "rainfall_parquet"
URL = "https://www.imdpune.gov.in/cmpg/Griddata/RF25.php"
YEARS = range(1901, 2026)
os.makedirs(OUT, exist_ok=True)

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

def convert(nc_path, year):
    ds = xr.open_dataset(nc_path)
    df = ds["RAINFALL"].to_dataframe().reset_index()
    ds.close()
    df = df.rename(columns={"TIME":"date","LATITUDE":"lat","LONGITUDE":"lon","RAINFALL":"rainfall_mm"})
    df = df.dropna(subset=["rainfall_mm"])
    df["date"] = df["date"].dt.date.astype("datetime64[ns]")
    df["lat"] = df["lat"].astype("float32")
    df["lon"] = df["lon"].astype("float32")
    df["rainfall_mm"] = df["rainfall_mm"].astype("float32")
    df = df[["date","lat","lon","rainfall_mm"]].sort_values(["date","lat","lon"]).reset_index(drop=True)
    d = os.path.join(OUT, f"year={year}")
    os.makedirs(d, exist_ok=True)
    df.to_parquet(os.path.join(d, "data.parquet"), engine="pyarrow", compression="zstd", index=False)
    return len(df)

for y in YEARS:
    part = os.path.join(OUT, f"year={y}", "data.parquet")
    if os.path.exists(part):
        log(f"{y} skip (exists)")
        continue
    nc = f"_tmp_{y}.nc"
    # reuse local files already downloaded
    if y == 2025 and os.path.exists("RF25_ind2025_rfp25.nc"):
        nc = "RF25_ind2025_rfp25.nc"; downloaded = False
    elif y == 1901 and os.path.exists("test_1901.nc"):
        nc = "test_1901.nc"; downloaded = False
    else:
        try:
            data = urllib.parse.urlencode({"RF25": str(y)}).encode()
            req = urllib.request.Request(URL, data=data)
            with urllib.request.urlopen(req, timeout=120) as r, open(nc, "wb") as f:
                f.write(r.read())
            downloaded = True
        except Exception as e:
            log(f"{y} DOWNLOAD FAIL {e}"); continue
    try:
        n = convert(nc, y)
        log(f"{y} ok rows={n}")
    except Exception as e:
        log(f"{y} CONVERT FAIL {e}")
    finally:
        if nc.startswith("_tmp_") and os.path.exists(nc):
            os.remove(nc)
    time.sleep(2)  # polite

log("DONE")
