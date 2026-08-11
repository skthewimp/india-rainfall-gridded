import numpy as np, pandas as pd

# --- grid definition (IMD 0.25 deg) ---
LAT0, LON0, STEP, NLAT, NLON = 6.5, 66.5, 0.25, 129, 135

# --- data cells that actually have rainfall (from 2025 partition) ---
cells = pd.read_parquet("rainfall_parquet/year=2025/data.parquet", columns=["lat","lon"]).drop_duplicates()
cells = cells.astype({"lat":"float64","lon":"float64"}).reset_index(drop=True)
ci = np.rint((cells.lat.values-LAT0)/STEP).astype(int)
cj = np.rint((cells.lon.values-LON0)/STEP).astype(int)
mask = np.zeros((NLAT,NLON), bool); mask[ci,cj]=True
data_lat = cells.lat.values; data_lon = cells.lon.values  # 4964 centers

# --- geonames populated places (class P) ---
cols = ["geonameid","name","asciiname","alt","lat","lon","fclass","fcode","cc","cc2",
        "admin1","admin2","admin3","admin4","population","elev","dem","tz","moddate"]
g = pd.read_csv("IN.txt", sep="\t", names=cols, dtype=str, quoting=3, na_filter=False)
g = g[g.fclass=="P"].copy()
g["lat"]=g.lat.astype(float); g["lon"]=g.lon.astype(float)
g["population"]=pd.to_numeric(g.population, errors="coerce").fillna(0).astype(int)

# state names from admin1
a1 = pd.read_csv("admin1.txt", sep="\t", names=["code","name","ascii","id"], dtype=str, na_filter=False)
a1_map = dict(zip(a1.code, a1.ascii))
g["state"] = ("IN."+g.admin1).map(a1_map).fillna("")

# --- covering cell index ---
pi = np.rint((g.lat.values-LAT0)/STEP).astype(int)
pj = np.rint((g.lon.values-LON0)/STEP).astype(int)
inb = (pi>=0)&(pi<NLAT)&(pj>=0)&(pj<NLON)
hit = np.zeros(len(g), bool)
hit[inb] = mask[pi[inb], pj[inb]]

cell_lat = np.full(len(g), np.nan); cell_lon = np.full(len(g), np.nan)
cell_lat[hit] = LAT0 + pi[hit]*STEP
cell_lon[hit] = LON0 + pj[hit]*STEP

# --- fallback: nearest data cell for misses (brute force, chunked) ---
miss = np.where(~hit)[0]
if len(miss):
    plat = g.lat.values[miss]; plon = g.lon.values[miss]
    for s in range(0, len(miss), 2000):
        e = min(s+2000, len(miss))
        dlat = (plat[s:e,None]-data_lat[None,:])
        dlon = (plon[s:e,None]-data_lon[None,:])*np.cos(np.radians(plat[s:e,None]))
        idx = np.argmin(dlat**2+dlon**2, axis=1)
        cell_lat[miss[s:e]] = data_lat[idx]; cell_lon[miss[s:e]] = data_lon[idx]

# --- haversine dist place->cell (km) ---
R=6371.0
dphi=np.radians(cell_lat-g.lat.values); dl=np.radians(cell_lon-g.lon.values)
aa=np.sin(dphi/2)**2+np.cos(np.radians(g.lat.values))*np.cos(np.radians(cell_lat))*np.sin(dl/2)**2
dist=2*R*np.arcsin(np.sqrt(aa))

out = pd.DataFrame({
    "geonameid":g.geonameid.values,"name":g.name.values,"asciiname":g.asciiname.values,
    "state":g.state.values,"population":g.population.values,
    "place_lat":g.lat.values.astype("float32"),"place_lon":g.lon.values.astype("float32"),
    "cell_lat":cell_lat.astype("float32"),"cell_lon":cell_lon.astype("float32"),
    "dist_km":dist.astype("float32"),
})
out.to_parquet("city_cell_mapping.parquet", engine="pyarrow", compression="zstd", index=False)

print("places mapped:", len(out))
print("covered by their own cell:", int(hit.sum()), "| snapped to nearest:", int((~hit).sum()))
print("median snap dist (km):", round(float(np.median(dist)),2), "| 95th pct:", round(float(np.percentile(dist,95)),2))
print("distinct cells hit:", out[['cell_lat','cell_lon']].drop_duplicates().shape[0], "of 4964")
print(out.sort_values('population',ascending=False)[['name','state','population','cell_lat','cell_lon','dist_km']].head(8).to_string(index=False))
