import xarray as xr, numpy as np, pandas as pd
ds = xr.open_dataset("RF25_ind2025_rfp25.nc")
r = ds["RAINFALL"]
print("dims", dict(r.sizes))
print("lon", float(ds.LONGITUDE.min()), float(ds.LONGITUDE.max()))
print("lat", float(ds.LATITUDE.min()), float(ds.LATITUDE.max()))
t = ds.TIME.values  # decoded datetime?
print("time dtype", ds.TIME.dtype, "first", t[0], "last", t[-1], "n", len(t))
vals = r.values
print("shape", vals.shape, "nan count", np.isnan(vals).sum(), "of", vals.size)
finite = vals[np.isfinite(vals)]
print("min/max/mean", finite.min(), finite.max(), finite.mean())
