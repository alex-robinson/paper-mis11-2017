# paper-mis11-2017

Data archive for:

> Robinson, A., Alvarez-Solas, J., Calov, R., Ganopolski, A. & Montoya, M. (2017).
> *MIS-11 duration key to disappearance of the Greenland ice sheet.*
> **Nature Communications** 8, 16008. <https://doi.org/10.1038/ncomms16008>

## Contents

- `Robinson2017_ncomm_rembo-sico-best.nc` — combined REMBO (climate) and
  SICOPOLIS (ice sheet) output for the best-fit MIS 11 simulation extended
  through the interglacial, on a Greenland grid (20 km spacing) using the
  Bamber et al. (2001) polar-stereographic projection. All fields share the
  same `(time, y, x)` grid (48 time slices × 141 × 76). CF-1.8 conventions,
  with a `crs` grid_mapping variable so QGIS / GDAL / rioxarray / xarray+cf
  pick up the projection automatically.
- `scripts/build_archive.jl` — Julia script that rebuilds the archive from
  the two original per-model NetCDF files. Run with:
  ```sh
  cd scripts
  julia --project=. -e 'using Pkg; Pkg.instantiate()'
  julia --project=. build_archive.jl
  ```
  The script expects the original files at
  `../../wrk/data/Robinson2017_ncomm_{rembo,sico}-best-ext.nc`.

## Projection

Bamber et al. (2001) polar-stereographic projection:

| parameter | value |
|---|---|
| projection | polar stereographic (north) |
| standard parallel (`lat_ts`) | 71°N |
| central meridian (`lon_0`) | −39° |
| latitude of origin (`lat_0`) | 90°N |
| ellipsoid / datum | WGS 84 |
| false easting / northing | 0 / 0 |
| units | metres |

PROJ string: `+proj=stere +lat_0=90 +lat_ts=71 +lon_0=-39 +k=1 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs`.

## Variables

REMBO climate output (from `..._rembo-best-ext.nc`):
`mask_hydro`, `tann`, `tjan`, `tjul`, `tjja`, `tdjf`, `ttp`, `pp`, `snow`,
`smb`, `pdds`.

SICOPOLIS ice-sheet output (from `..._sico-best-ext.nc`):
`mask`, `zs`, `zb`, `H`, `H_t`.

Note: REMBO's own `mask` and `zs` fields were dropped in favour of the
SICOPOLIS versions, which are the authoritative fields for this paper.

Auxiliary coordinates: 1D `x`/`y` (projected, metres), 2D `lat`/`lon`
(geographic, degrees), 2D `xx`/`yy` (projected, metres — redundant with
`x`/`y` but useful for some analyses).
