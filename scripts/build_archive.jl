#!/usr/bin/env julia
# Build the combined, CF-compliant NetCDF archive for Robinson et al. (2017)
# from the two source files produced by the original REMBO + SICOPOLIS runs.
#
# Inputs  (paths relative to the repo of the paper working directory):
#   ../wrk/data/Robinson2017_ncomm_rembo-best-ext.nc   (climate output)
#   ../wrk/data/Robinson2017_ncomm_sico-best-ext.nc    (ice sheet output)
#
# Output:
#   ../Robinson2017_ncomm_rembo-sico-best.nc
#
# The two source files share the same grid (76 x 141) and the same 48
# time levels. This script merges the climate and ice-sheet variables into
# a single file, converts the x/y/xx/yy coordinates from km to m, and adds
# a CF grid_mapping variable (`crs`) describing the Bamber et al. (2001)
# 5 km Greenland polar-stereographic projection.
#
# Run with:
#   julia --project=. build_archive.jl
# (requires NCDatasets.jl; `julia --project=. -e 'using Pkg; Pkg.instantiate()'`
# first if needed.)

using NCDatasets
using Printf

const SCRIPT_DIR = @__DIR__
const REPO_DIR   = normpath(joinpath(SCRIPT_DIR, ".."))
const SRC_DIR    = normpath(joinpath(REPO_DIR, "..", "wrk", "data"))

const REMBO_IN = joinpath(SRC_DIR, "Robinson2017_ncomm_rembo-best-ext.nc")
const SICO_IN  = joinpath(SRC_DIR, "Robinson2017_ncomm_sico-best-ext.nc")
const OUT_NC   = joinpath(REPO_DIR, "Robinson2017_ncomm_rembo-sico-best.nc")

# Bamber et al. (2001) Greenland polar-stereographic projection.
# WGS84 ellipsoid, true scale at 71 N, central meridian 39 W.
const CRS_ATTRS = Dict(
    "grid_mapping_name"                => "polar_stereographic",
    "latitude_of_projection_origin"    => 90.0,
    "straight_vertical_longitude_from_pole" => -39.0,
    "standard_parallel"                => 71.0,
    "false_easting"                    => 0.0,
    "false_northing"                   => 0.0,
    "semi_major_axis"                  => 6378137.0,
    "inverse_flattening"               => 298.257223563,
    "reference_ellipsoid_name"         => "WGS 84",
    "horizontal_datum_name"            => "WGS 84",
    "proj4"                            => "+proj=stere +lat_0=90 +lat_ts=71 +lon_0=-39 +k=1 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs",
    "crs_wkt"                          => """PROJCRS["Bamber 2001 Greenland Polar Stereographic",BASEGEOGCRS["WGS 84",DATUM["World Geodetic System 1984",ELLIPSOID["WGS 84",6378137,298.257223563,LENGTHUNIT["metre",1]]],PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433]]],CONVERSION["Polar Stereographic (variant B)",METHOD["Polar Stereographic (variant B)",ID["EPSG",9829]],PARAMETER["Latitude of standard parallel",71,ANGLEUNIT["degree",0.0174532925199433]],PARAMETER["Longitude of origin",-39,ANGLEUNIT["degree",0.0174532925199433]],PARAMETER["False easting",0,LENGTHUNIT["metre",1]],PARAMETER["False northing",0,LENGTHUNIT["metre",1]]],CS[Cartesian,2],AXIS["easting (X)",east,ORDER[1],LENGTHUNIT["metre",1]],AXIS["northing (Y)",north,ORDER[2],LENGTHUNIT["metre",1]]]""",
    "long_name"                        => "CRS: Bamber et al. (2001) Greenland polar-stereographic projection",
)

# Rembo variables to carry over (mask and zs are dropped: they duplicate the
# SICOPOLIS fields, which are the authoritative ones for this paper).
const REMBO_VARS = [
    "mask_hydro",
    "tann", "tjan", "tjul", "tjja", "tdjf", "ttp",
    "pp", "snow", "smb", "pdds",
]

# Sico variables to carry over.
const SICO_VARS = ["mask", "zs", "zb", "H", "H_t"]


"Copy variable attributes with sensible defaults; drop scale_factor/add_offset
 when they are the trivial (1, 0) pair that clutters the source files."
function copy_attrs!(dst_var, src_var; extra = Dict{String,Any}())
    for (k, v) in src_var.attrib
        if k == "scale_factor" && v == 1
            continue
        elseif k == "add_offset" && v == 0
            continue
        elseif k == "actual_range"
            continue  # will be stale after any change; regenerate below
        end
        dst_var.attrib[k] = v
    end
    for (k, v) in extra
        dst_var.attrib[k] = v
    end
    return dst_var
end


function main()
    isfile(REMBO_IN) || error("Missing input: $REMBO_IN")
    isfile(SICO_IN)  || error("Missing input: $SICO_IN")

    @info "Reading REMBO source" REMBO_IN
    rembo = NCDataset(REMBO_IN, "r")
    @info "Reading SICOPOLIS source" SICO_IN
    sico  = NCDataset(SICO_IN,  "r")

    # Sanity: grids and times must match exactly.
    @assert size(rembo["x"]) == size(sico["x"]) "x grids differ"
    @assert size(rembo["y"]) == size(sico["y"]) "y grids differ"
    @assert size(rembo["time"]) == size(sico["time"]) "time axes differ"

    x_km    = Array(rembo["x"][:])
    y_km    = Array(rembo["y"][:])
    time_ka = Array(rembo["time"][:])
    xx_km   = Array(rembo["xx"][:, :])
    yy_km   = Array(rembo["yy"][:, :])
    lat2d   = Array(rembo["lat"][:, :])
    lon2d   = Array(rembo["lon"][:, :])

    # Convert km -> m for all projected coords (CF/GDAL/QGIS expect metres
    # when a grid_mapping is present).
    x_m  = Float64.(x_km)  .* 1000.0
    y_m  = Float64.(y_km)  .* 1000.0
    xx_m = Float64.(xx_km) .* 1000.0
    yy_m = Float64.(yy_km) .* 1000.0

    isfile(OUT_NC) && rm(OUT_NC)
    @info "Writing combined archive" OUT_NC

    ds = NCDataset(OUT_NC, "c", format = :netcdf4_classic)

    # -- Global attributes ---------------------------------------------------
    ds.attrib["title"]       = "Robinson, Alvarez-Solas, Calov, Ganopolski & Montoya (2017): Greenland ice sheet and climate during MIS 11"
    ds.attrib["summary"]     = "Combined REMBO climate output and SICOPOLIS ice-sheet output for the best-fit MIS 11 simulation extended through the interglacial, on a Greenland grid using the Bamber et al. (2001) polar-stereographic projection."
    ds.attrib["reference"]   = "Robinson, A., Alvarez-Solas, J., Calov, R., Ganopolski, A. & Montoya, M. (2017). MIS-11 duration key to disappearance of the Greenland ice sheet. Nature Communications 8, 16008. https://doi.org/10.1038/ncomms16008"
    ds.attrib["source"]      = "REMBO regional climate-ice-sheet model coupled to SICOPOLIS thermomechanical ice-sheet model."
    ds.attrib["institution"] = "Universidad Complutense de Madrid; Potsdam Institute for Climate Impact Research"
    ds.attrib["Conventions"] = "CF-1.8"
    ds.attrib["projection"]  = "Bamber et al. (2001) polar stereographic (lat_ts=71N, lon_0=-39, WGS84)."
    ds.attrib["history"]     = @sprintf("%s: built by scripts/build_archive.jl (merged REMBO+SICOPOLIS output; x/y converted from km to m; added CF grid_mapping).",
                                        Libc.strftime("%Y-%m-%d %H:%M:%S", time()))

    # -- Dimensions ----------------------------------------------------------
    defDim(ds, "x",    length(x_m))
    defDim(ds, "y",    length(y_m))
    defDim(ds, "time", length(time_ka))

    # -- Coordinate variables ------------------------------------------------
    v_x = defVar(ds, "x", Float64, ("x",))
    v_x[:] = x_m
    v_x.attrib["standard_name"] = "projection_x_coordinate"
    v_x.attrib["long_name"]     = "x coordinate of Bamber 2001 polar-stereographic projection"
    v_x.attrib["units"]         = "m"
    v_x.attrib["axis"]          = "X"

    v_y = defVar(ds, "y", Float64, ("y",))
    v_y[:] = y_m
    v_y.attrib["standard_name"] = "projection_y_coordinate"
    v_y.attrib["long_name"]     = "y coordinate of Bamber 2001 polar-stereographic projection"
    v_y.attrib["units"]         = "m"
    v_y.attrib["axis"]          = "Y"

    v_t = defVar(ds, "time", Float64, ("time",))
    v_t[:] = Float64.(time_ka)
    v_t.attrib["standard_name"] = "time"
    v_t.attrib["long_name"]     = "time before present (present = 1950 CE)"
    v_t.attrib["units"]         = "years"
    v_t.attrib["axis"]          = "T"

    # -- Auxiliary 2D coordinates -------------------------------------------
    v_lat = defVar(ds, "lat", Float32, ("x", "y"))
    v_lat[:, :] = Float32.(lat2d)
    v_lat.attrib["standard_name"] = "latitude"
    v_lat.attrib["long_name"]     = "latitude"
    v_lat.attrib["units"]         = "degrees_north"

    v_lon = defVar(ds, "lon", Float32, ("x", "y"))
    v_lon[:, :] = Float32.(lon2d)
    v_lon.attrib["standard_name"] = "longitude"
    v_lon.attrib["long_name"]     = "longitude"
    v_lon.attrib["units"]         = "degrees_east"

    v_xx = defVar(ds, "xx", Float64, ("x", "y"))
    v_xx[:, :] = xx_m
    v_xx.attrib["long_name"] = "projected x coordinate (2D)"
    v_xx.attrib["units"]     = "m"

    v_yy = defVar(ds, "yy", Float64, ("x", "y"))
    v_yy[:, :] = yy_m
    v_yy.attrib["long_name"] = "projected y coordinate (2D)"
    v_yy.attrib["units"]     = "m"

    # -- CRS grid_mapping variable ------------------------------------------
    v_crs = defVar(ds, "crs", Int32, ())
    v_crs[] = Int32(0)
    for (k, v) in CRS_ATTRS
        v_crs.attrib[k] = v
    end

    # -- Copy data variables. In the source files all data variables are
    #    (time, y, x) in ncdump / CF order, and one — mask_hydro — is (y, x).
    #    NCDatasets uses Julia column-major, so those come back as (x, y, t)
    #    and (x, y). We write with the same Julia-order dims so the on-disk
    #    layout comes out as (time, y, x) / (y, x) in ncdump. ---------------
    extra = Dict{String,Any}(
        "grid_mapping" => "crs",
        "coordinates"  => "lat lon",
    )

    function copy_var!(src_ds, name, tag)
        haskey(src_ds, name) || (@warn "$tag/$name not found, skipping"; return)
        src = src_ds[name]
        arr = src[ntuple(_ -> Colon(), ndims(src))...]
        if ndims(arr) == 3
            @assert size(arr) == (length(x_m), length(y_m), length(time_ka)) "unexpected shape for $name: $(size(arr))"
            dst = defVar(ds, name, Float32, ("x", "y", "time"))
            dst[:, :, :] = Float32.(arr)
        elseif ndims(arr) == 2
            @assert size(arr) == (length(x_m), length(y_m)) "unexpected 2D shape for $name: $(size(arr))"
            dst = defVar(ds, name, Float32, ("x", "y"))
            dst[:, :] = Float32.(arr)
        else
            error("unsupported rank $(ndims(arr)) for $tag/$name")
        end
        copy_attrs!(dst, src; extra = extra)
        @info "  + $tag/$name" size=size(arr)
    end

    for name in REMBO_VARS
        copy_var!(rembo, name, "rembo")
    end
    for name in SICO_VARS
        copy_var!(sico, name, "sico")
    end

    close(ds)
    close(rembo)
    close(sico)

    @info "Done" OUT_NC filesize=filesize(OUT_NC)
    return OUT_NC
end

main()
