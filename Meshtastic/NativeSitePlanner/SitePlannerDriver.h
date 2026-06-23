/* C ABI for the browser/native RF coverage engine.
 *
 * A handle wraps one coverage computation: a faithful port of SPLAT!'s
 * `-c`-mode ITM sweep (splat/splat.cpp) operating on in-memory elevation
 * pages instead of SDF files. All angle conventions follow SPLAT!:
 * latitudes in degrees north, longitudes WEST-POSITIVE 0-360 internally
 * (the create call takes a signed longitude and converts).
 *
 * Heights are in FEET to mirror what reaches SPLAT!'s site structs: the
 * legacy backend wrote QTH files without the meters suffix, so the
 * tx height request field was consumed as feet. Callers decide whether
 * to preserve that quirk (golden tests) or convert properly (UI).
 */
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Error codes returned by the functions below (negative values). */
#define SPLAT_E_NOMEM -1
#define SPLAT_E_BADHANDLE -2
#define SPLAT_E_BADPAGE -3
#define SPLAT_E_TOOLARGE -4
#define SPLAT_E_BADPARAM -5

/* Create a coverage computation. Returns a handle (>= 1) or an error code.
 * tx_lon_deg is signed (-180..180, east positive). tx/rx heights in feet
 * AGL. clutter in meters (converted internally like SPLAT!'s -metric -gc).
 * radius in km (-R -metric). conf/rel are fractions in (0, 1].
 * polarization: 0 horizontal, 1 vertical. radio_climate: 1-7.
 * resolution_ippd: 1200 (3-arcsecond / 90 m, like `splat`) or
 * 3600 (1-arcsecond / 30 m, like `splat-hd`). Pages are
 * resolution_ippd x resolution_ippd cells. */
int splat_create(double tx_lat_deg, double tx_lon_deg,
                 double tx_alt_feet, double rx_alt_feet,
                 double frequency_mhz, double erp_watts,
                 double eps_dielect, double sgm_conductivity,
                 double eno_ns_surfref,
                 int radio_climate, int polarization,
                 double conf, double rel,
                 double clutter_height_m, double radius_km,
                 int resolution_ippd);

/* Number of 1x1 degree elevation pages the computation spans. */
int splat_page_count(int handle);

/* out2[0] = page min_north (floor latitude, degrees),
 * out2[1] = page min_west (floor longitude, WEST-POSITIVE 0-359). */
int splat_page_info(int handle, int index, int32_t *out2);

/* Load elevation for a page: resolution_ippd^2 int16 meters in SDF cell
 * order (outer index ascending south->north, inner ascending east->west).
 * Pages never loaded behave as sea level, matching SPLAT!. */
int splat_load_page(int handle, int index, const int16_t *data);

/* Total number of radials in the perimeter sweep. */
int splat_radial_count(int handle);

/* Run radials [start, start+count). Returns number run or an error. */
int splat_run_radials(int handle, int start, int count);

/* Flatten per-page signal/mask grids into the region-wide output rasters
 * (WritePPMDBM traversal). Call after the radials of interest have run. */
int splat_rasterize(int handle);

/* out8 = [width, height, north, south, east, west, radial_count, page_count].
 * Bounds are the KML LatLonBox values SPLAT! reports (signed degrees). */
int splat_region_info(int handle, double *out8);

/* Region-wide rasters (width*height bytes, row 0 = north). Valid after
 * splat_rasterize. signal: 0-255 where dBm = signal - 200. mask: SPLAT!
 * analysis mask; (mask & 248) != 0 means the pixel was computed. */
uint8_t *splat_signal_ptr(int handle);
uint8_t *splat_mask_ptr(int handle);

/* Histogram of ITM errnum values 0..4 plus a bucket for anything else. */
int splat_errnum_counts(int handle, int32_t *out6);

void splat_destroy(int handle);

/* Heap helpers for hosts that need scratch buffers (wasm). */
void *splat_malloc(int bytes);
void splat_free(void *ptr);

#ifdef __cplusplus
}
#endif
