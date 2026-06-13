/* Browser/native RF coverage engine.
 *
 * A faithful port of SPLAT! 1.4.2's area-coverage ITM sweep
 * (splat/splat.cpp, invoked by the legacy backend as:
 *   splat -t tx.qth -L <rx_m> -metric -R <km> -sc -gc <m> -ngs -N
 *         -o out.ppm -dbm -db <thr> -kml -olditm
 * ) restructured to run against in-memory elevation pages with no
 * filesystem, no globals, and a resumable radial loop so Web Workers can
 * split the sweep. The propagation model itself is the unmodified
 * point_to_point_ITM() from splat/itwom3.0.cpp, compiled alongside.
 *
 * Functions kept verbatim from splat.cpp (line refs against the submodule):
 * arccos (222), ReduceAngle (238), LonDiff (250), Put/Get mask & signal
 * (309-434), GetElevation (436), Distance (492), Azimuth (509),
 * ReadPath (582), PlotLRPath (2775, antenna-pattern and .ano paths dropped
 *  - both are dead under the backend's flags), PlotLRMap edge sweep (3198),
 * region setup from main() (8410-8569), WritePPMDBM raster traversal and
 * KML bounds (5150-5310). Quirks (integer-degree page regions, the
 * east-bounds dpp asymmetry, feet/meter round-trips) are preserved on
 * purpose: golden tests compare output against the legacy service.
 */

#include "SitePlannerDriver.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include <vector>

/* Constants verbatim from splat.cpp / splat.h (MAXPAGES=64, std mode). */
#define PI 3.141592653589793
#define TWOPI 6.283185307179586
#define HALFPI 1.570796326794896
#define DEG2RAD 1.74532925199e-02
#define EARTHRADIUS 20902230.97
#define METERS_PER_MILE 1609.344
#define METERS_PER_FOOT 0.3048
#define KM_PER_MILE 1.609344
#define FOUR_THIRDS 1.3333333333333
#define ARRAYSIZE 76810

/* deg_limit table entries and page caps for the two production builds:
 * standard (`splat`, MAXPAGES=64) and HD (`splat-hd`, MAXPAGES=16). */
#define DEG_LIMIT_SD 3.5
#define DEG_LIMIT_HD 1.5
#define MAX_PAGES_SD 64
#define MAX_PAGES_HD 16

/* ITM entry point, splat/itwom3.0.cpp:2327 (-olditm model). */
void point_to_point_ITM(double elev[], double tht_m, double rht_m,
                        double eps_dielect, double sgm_conductivity,
                        double eno_ns_surfref, double frq_mhz,
                        int radio_climate, int pol, double conf, double rel,
                        double &dbloss, char *strmode, int &errnum);

namespace {

struct Site {
    double lat;
    double lon; /* west-positive 0-360 */
    float alt;  /* feet AGL */
};

struct Page {
    int min_north;
    int max_north;
    int min_west;
    int max_west;
    short *data;     /* [ippd][ippd], meters; x south->north, y east->west */
    unsigned char *mask;
    unsigned char *signal;
};

struct Engine {
    std::vector<Page> pages;

    /* Accumulated region bounds (LoadSDF semantics). */
    int min_north = 90;
    int max_north = -90;
    int min_west = 360;
    int max_west = -1;

    int ippd = 1200;
    int mpi = 1199;
    double ppd = 1200.0;
    double dpp = 1.0 / 1200.0;
    int max_pages = MAX_PAGES_SD;

    Site tx{};
    double rx_alt_feet = 0.0;
    double clutter = 0.0;   /* feet */
    double max_range = 0.0; /* miles */

    /* Longley-Rice parameters (LR struct in splat.cpp). */
    double eps_dielect = 0.0;
    double sgm_conductivity = 0.0;
    double eno_ns_surfref = 0.0;
    double frq_mhz = 0.0;
    double conf = 0.0;
    double rel = 0.0;
    double erp = 0.0;
    int radio_climate = 0;
    int pol = 0;

    /* Precomputed perimeter radial targets, in PlotLRMap order. */
    std::vector<double> radial_lat;
    std::vector<double> radial_lon;

    /* Path buffers (the path/elev globals in splat.cpp). */
    std::vector<double> path_lat;
    std::vector<double> path_lon;
    std::vector<double> path_elevation;
    std::vector<double> path_distance;
    int path_length = 0;
    std::vector<double> elev;

    /* Point-to-point link profile (issue #14): packed [dist_km, ground_m]. */
    std::vector<double> p2p_profile;
    int p2p_length = 0;

    /* Region-wide output rasters (filled by splat_rasterize). */
    std::vector<unsigned char> out_signal;
    std::vector<unsigned char> out_mask;
    int out_width = 0;
    int out_height = 0;

    int32_t errnum_counts[6] = {0, 0, 0, 0, 0, 0};
};

std::vector<Engine *> g_engines;

Engine *get_engine(int handle) {
    if (handle < 1 || handle > (int)g_engines.size())
        return nullptr;
    return g_engines[handle - 1];
}

/* ---- helpers verbatim from splat.cpp ---- */

double arccos(double x, double y) {
    double result = 0.0;
    if (y > 0.0)
        result = acos(x / y);
    if (y < 0.0)
        result = PI + acos(x / y);
    return result;
}

int ReduceAngle(double angle) {
    double temp = acos(cos(angle * DEG2RAD));
    return (int)rint(temp / DEG2RAD);
}

double LonDiff(double lon1, double lon2) {
    double diff = lon1 - lon2;
    if (diff <= -180.0)
        diff += 360.0;
    if (diff >= 180.0)
        diff -= 360.0;
    return diff;
}

/* Shared page lookup used by every grid accessor (splat.cpp:320-329). */
inline Page *find_page(Engine &e, double lat, double lon, int &x, int &y) {
    for (size_t indx = 0; indx < e.pages.size(); indx++) {
        Page &p = e.pages[indx];
        x = (int)rint(e.ppd * (lat - p.min_north));
        y = e.mpi - (int)rint(e.ppd * (LonDiff((double)p.max_west, lon)));
        if (x >= 0 && x <= e.mpi && y >= 0 && y <= e.mpi)
            return &p;
    }
    return nullptr;
}

int PutMask(Engine &e, double lat, double lon, int value) {
    int x, y;
    Page *p = find_page(e, lat, lon, x, y);
    if (p) {
        p->mask[x * e.ippd + y] = (unsigned char)value;
        return (int)p->mask[x * e.ippd + y];
    }
    return -1;
}

int GetMask(Engine &e, double lat, double lon) {
    int x, y;
    Page *p = find_page(e, lat, lon, x, y);
    if (p)
        return (int)p->mask[x * e.ippd + y];
    return -1; /* OrMask(...,0) result for unfound locations */
}

void PutSignal(Engine &e, double lat, double lon, unsigned char signal) {
    int x, y;
    Page *p = find_page(e, lat, lon, x, y);
    if (p)
        p->signal[x * e.ippd + y] = signal;
}

unsigned char GetSignal(Engine &e, double lat, double lon) {
    int x, y;
    Page *p = find_page(e, lat, lon, x, y);
    if (p)
        return p->signal[x * e.ippd + y];
    return 0;
}

double GetElevation(Engine &e, const Site &location) {
    int x, y;
    Page *p = find_page(e, location.lat, location.lon, x, y);
    if (p)
        return 3.28084 * p->data[x * e.ippd + y];
    return -5000.0;
}

double Distance(const Site &site1, const Site &site2) {
    double lat1 = site1.lat * DEG2RAD;
    double lon1 = site1.lon * DEG2RAD;
    double lat2 = site2.lat * DEG2RAD;
    double lon2 = site2.lon * DEG2RAD;
    return 3959.0 * acos(sin(lat1) * sin(lat2) +
                         cos(lat1) * cos(lat2) * cos(lon1 - lon2));
}

double Azimuth(const Site &source, const Site &destination) {
    double dest_lat = destination.lat * DEG2RAD;
    double dest_lon = destination.lon * DEG2RAD;
    double src_lat = source.lat * DEG2RAD;
    double src_lon = source.lon * DEG2RAD;

    double beta = acos(sin(src_lat) * sin(dest_lat) +
                       cos(src_lat) * cos(dest_lat) * cos(src_lon - dest_lon));

    double num = sin(dest_lat) - (sin(src_lat) * cos(beta));
    double den = cos(src_lat) * sin(beta);
    double fraction = num / den;

    if (fraction >= 1.0)
        fraction = 1.0;
    if (fraction <= -1.0)
        fraction = -1.0;

    double azimuth = acos(fraction);

    double diff = dest_lon - src_lon;
    if (diff <= -PI)
        diff += TWOPI;
    if (diff >= PI)
        diff -= TWOPI;
    if (diff > 0.0)
        azimuth = TWOPI - azimuth;

    return azimuth / DEG2RAD;
}

/* ReadPath, splat.cpp:582. */
void ReadPath(Engine &e, const Site &source, const Site &destination) {
    int c;
    double azimuth, distance, lat1, lon1, beta, den, num, lat2, lon2,
        total_distance, dx, dy, path_length = 0.0, miles_per_sample,
        samples_per_radian = 68755.0;
    Site tempsite{};

    lat1 = source.lat * DEG2RAD;
    lon1 = source.lon * DEG2RAD;

    lat2 = destination.lat * DEG2RAD;
    lon2 = destination.lon * DEG2RAD;

    if (e.ppd == 1200.0)
        samples_per_radian = 68755.0;
    if (e.ppd == 3600.0)
        samples_per_radian = 206265.0;

    azimuth = Azimuth(source, destination) * DEG2RAD;

    total_distance = Distance(source, destination);

    if (total_distance > (30.0 / e.ppd)) /* > 0.5 pixel distance */
    {
        dx = samples_per_radian * acos(cos(lon1 - lon2));
        dy = samples_per_radian * acos(cos(lat1 - lat2));
        path_length = sqrt((dx * dx) + (dy * dy));
        miles_per_sample = total_distance / path_length;
    } else {
        c = 0;
        dx = 0.0;
        dy = 0.0;
        path_length = 0.0;
        miles_per_sample = 0.0;
        total_distance = 0.0;

        lat1 = lat1 / DEG2RAD;
        lon1 = lon1 / DEG2RAD;

        e.path_lat[c] = lat1;
        e.path_lon[c] = lon1;
        e.path_elevation[c] = GetElevation(e, source);
        e.path_distance[c] = 0.0;
    }

    for (distance = 0.0, c = 0;
         (total_distance != 0.0 && distance <= total_distance &&
          c < ARRAYSIZE);
         c++, distance = miles_per_sample * (double)c) {
        beta = distance / 3959.0;
        lat2 = asin(sin(lat1) * cos(beta) +
                    cos(azimuth) * sin(beta) * cos(lat1));
        num = cos(beta) - (sin(lat1) * sin(lat2));
        den = cos(lat1) * cos(lat2);

        if (azimuth == 0.0 && (beta > HALFPI - lat1))
            lon2 = lon1 + PI;

        else if (azimuth == HALFPI && (beta > HALFPI + lat1))
            lon2 = lon1 + PI;

        else if (fabs(num / den) > 1.0)
            lon2 = lon1;

        else {
            if ((PI - azimuth) >= 0.0)
                lon2 = lon1 - arccos(num, den);
            else
                lon2 = lon1 + arccos(num, den);
        }

        while (lon2 < 0.0)
            lon2 += TWOPI;
        while (lon2 > TWOPI)
            lon2 -= TWOPI;

        lat2 = lat2 / DEG2RAD;
        lon2 = lon2 / DEG2RAD;

        e.path_lat[c] = lat2;
        e.path_lon[c] = lon2;
        tempsite.lat = lat2;
        tempsite.lon = lon2;
        e.path_elevation[c] = GetElevation(e, tempsite);
        e.path_distance[c] = distance;
    }

    /* Make sure exact destination point is recorded at path.length-1 */

    if (c < ARRAYSIZE) {
        e.path_lat[c] = destination.lat;
        e.path_lon[c] = destination.lon;
        e.path_elevation[c] = GetElevation(e, destination);
        e.path_distance[c] = total_distance;
        c++;
    }

    if (c < ARRAYSIZE)
        e.path_length = c;
    else
        e.path_length = ARRAYSIZE - 1;
}

/* PlotLRPath, splat.cpp:2775. The antenna-pattern integration and the
 * .ano/elevation-angle block are omitted: the backend never supplies
 * pattern files (LR.antenna_pattern stays all-zero, making the pattern
 * adjustment a no-op) nor an .ano fd (gating off the angle computation). */
void PlotLRPath(Engine &e, const Site &source, const Site &destination) {
    int y, ifs, ofs, errnum = 0;
    char strmode[100];
    double loss = 0.0, rxp, dBm;

    ReadPath(e, source, destination);

    double *elev = e.elev.data();

    /* Copy elevations plus clutter along path into the elev[] array. */

    for (int x = 1; x < e.path_length - 1; x++)
        elev[x + 2] = (e.path_elevation[x] == 0.0
                           ? e.path_elevation[x] * METERS_PER_FOOT
                           : (e.clutter + e.path_elevation[x]) *
                                 METERS_PER_FOOT);

    /* Copy ending points without clutter */

    elev[2] = e.path_elevation[0] * METERS_PER_FOOT;
    elev[e.path_length + 1] =
        e.path_elevation[e.path_length - 1] * METERS_PER_FOOT;

    for (y = 2; (y < (e.path_length - 1) &&
                 e.path_distance[y] <= e.max_range);
         y++) {
        /* Process this point only if it has not already been processed. */

        if ((GetMask(e, e.path_lat[y], e.path_lon[y]) & 248) != (1 << 3)) {
            /* Determine attenuation for each point along the path
             * using ITM's point_to_point mode starting at y=2
             * (number_of_points = 1), the shortest distance terrain
             * can play a role in path loss. */

            elev[0] = y - 1; /* (number of points - 1) */

            /* Distance between elevation samples */

            elev[1] =
                METERS_PER_MILE * (e.path_distance[y] - e.path_distance[y - 1]);

            point_to_point_ITM(elev, source.alt * METERS_PER_FOOT,
                               destination.alt * METERS_PER_FOOT,
                               e.eps_dielect, e.sgm_conductivity,
                               e.eno_ns_surfref, e.frq_mhz, e.radio_climate,
                               e.pol, e.conf, e.rel, loss, strmode, errnum);

            if (errnum >= 0 && errnum < 5)
                e.errnum_counts[errnum]++;
            else
                e.errnum_counts[5]++;

            /* ERP is always nonzero for coverage requests; SPLAT!'s
             * path-loss-only branch is unreachable here. dBm is based
             * on EIRP (ERP + 2.14). */

            rxp = e.erp / (pow(10.0, (loss - 2.14) / 10.0));
            dBm = 10.0 * (log10(rxp * 1000.0));

            /* Scale roughly between 0 and 255 */

            ifs = 200 + (int)rint(dBm);

            if (ifs < 0)
                ifs = 0;
            if (ifs > 255)
                ifs = 255;

            ofs = GetSignal(e, e.path_lat[y], e.path_lon[y]);

            if (ofs > ifs)
                ifs = ofs;

            PutSignal(e, e.path_lat[y], e.path_lon[y], (unsigned char)ifs);

            /* Mark this point as having been analyzed */

            PutMask(e, e.path_lat[y], e.path_lon[y],
                    (GetMask(e, e.path_lat[y], e.path_lon[y]) & 7) +
                        (1 << 3));
        }
    }
}

/* Page creation with LoadSDF's region-bounds accumulation
 * (splat.cpp:2100-2176). Every page starts as sea level. */
int add_page(Engine &e, int min_north, int min_west, int max_west) {
    int max_north = min_north + 1;

    for (const Page &p : e.pages) {
        if (p.min_north == min_north && p.min_west == min_west &&
            p.max_north == max_north && p.max_west == max_west)
            return 0; /* already in memory */
    }

    if ((int)e.pages.size() >= e.max_pages)
        return SPLAT_E_TOOLARGE;

    size_t cells = (size_t)e.ippd * (size_t)e.ippd;
    Page p{};
    p.min_north = min_north;
    p.max_north = max_north;
    p.min_west = min_west;
    p.max_west = max_west;
    p.data = (short *)calloc(cells, sizeof(short));
    p.mask = (unsigned char *)calloc(cells, 1);
    p.signal = (unsigned char *)calloc(cells, 1);
    if (!p.data || !p.mask || !p.signal) {
        free(p.data);
        free(p.mask);
        free(p.signal);
        return SPLAT_E_NOMEM;
    }
    e.pages.push_back(p);

    /* Accumulate region bounds exactly like LoadSDF. */

    if (e.max_north == -90)
        e.max_north = max_north;
    else if (max_north > e.max_north)
        e.max_north = max_north;

    if (e.min_north == 90)
        e.min_north = min_north;
    else if (min_north < e.min_north)
        e.min_north = min_north;

    if (e.max_west == -1)
        e.max_west = max_west;
    else {
        if (abs(max_west - e.max_west) < 180) {
            if (max_west > e.max_west)
                e.max_west = max_west;
        } else {
            if (max_west < e.max_west)
                e.max_west = max_west;
        }
    }

    if (e.min_west == 360)
        e.min_west = min_west;
    else {
        if (abs(min_west - e.min_west) < 180) {
            if (min_west < e.min_west)
                e.min_west = min_west;
        } else {
            if (min_west > e.min_west)
                e.min_west = min_west;
        }
    }

    return 0;
}

/* LoadTopoData, splat.cpp:7379. */
int LoadTopoData(Engine &e, int max_lon, int min_lon, int max_lat,
                 int min_lat) {
    int x, y, width, ymin, ymax, rc;

    width = ReduceAngle(max_lon - min_lon);

    if ((max_lon - min_lon) <= 180.0) {
        for (y = 0; y <= width; y++)
            for (x = min_lat; x <= max_lat; x++) {
                ymin = (int)(min_lon + (double)y);

                while (ymin < 0)
                    ymin += 360;
                while (ymin >= 360)
                    ymin -= 360;

                ymax = ymin + 1;

                while (ymax < 0)
                    ymax += 360;
                while (ymax >= 360)
                    ymax -= 360;

                rc = add_page(e, x, ymin, ymax);
                if (rc < 0)
                    return rc;
            }
    } else {
        for (y = 0; y <= width; y++)
            for (x = min_lat; x <= max_lat; x++) {
                ymin = max_lon + y;

                while (ymin < 0)
                    ymin += 360;
                while (ymin >= 360)
                    ymin -= 360;

                ymax = ymin + 1;

                while (ymax < 0)
                    ymax += 360;
                while (ymax >= 360)
                    ymax -= 360;

                rc = add_page(e, x, ymin, ymax);
                if (rc < 0)
                    return rc;
            }
    }

    return 0;
}

/* The four perimeter edge sweeps of PlotLRMap (splat.cpp:3266-3376),
 * recorded as a radial target list so workers can run arbitrary slices. */
void precompute_radials(Engine &e) {
    double lat, lon;
    int y;

    double minwest = e.dpp + (double)e.min_west;
    double maxnorth = (double)e.max_north - e.dpp;

    for (lon = minwest, y = 0; (LonDiff(lon, (double)e.max_west) <= 0.0);
         y++, lon = minwest + (e.dpp * (double)y)) {
        double L = lon;
        if (L >= 360.0)
            L -= 360.0;
        e.radial_lat.push_back((double)e.max_north);
        e.radial_lon.push_back(L);
    }

    for (lat = maxnorth, y = 0; lat >= (double)e.min_north;
         y++, lat = maxnorth - (e.dpp * (double)y)) {
        e.radial_lat.push_back(lat);
        e.radial_lon.push_back((double)e.min_west);
    }

    for (lon = minwest, y = 0; (LonDiff(lon, (double)e.max_west) <= 0.0);
         y++, lon = minwest + (e.dpp * (double)y)) {
        double L = lon;
        if (L >= 360.0)
            L -= 360.0;
        e.radial_lat.push_back((double)e.min_north);
        e.radial_lon.push_back(L);
    }

    for (lat = (double)e.min_north, y = 0; lat < (double)e.max_north;
         y++, lat = (double)e.min_north + (e.dpp * (double)y)) {
        e.radial_lat.push_back(lat);
        e.radial_lon.push_back((double)e.max_west);
    }
}

void free_engine(Engine *e) {
    for (Page &p : e->pages) {
        free(p.data);
        free(p.mask);
        free(p.signal);
    }
    delete e;
}

} // namespace

extern "C" {

int splat_create(double tx_lat_deg, double tx_lon_deg, double tx_alt_feet,
                 double rx_alt_feet, double frequency_mhz, double erp_watts,
                 double eps_dielect, double sgm_conductivity,
                 double eno_ns_surfref, int radio_climate, int polarization,
                 double conf, double rel, double clutter_height_m,
                 double radius_km, int resolution_ippd) {
    if (tx_lat_deg < -90.0 || tx_lat_deg > 90.0 || tx_lon_deg < -180.0 ||
        tx_lon_deg > 180.0 || frequency_mhz < 20.0 ||
        frequency_mhz > 20000.0 || erp_watts <= 0.0 || radio_climate < 1 ||
        radio_climate > 7 || polarization < 0 || polarization > 1 ||
        conf <= 0.0 || conf > 1.0 || rel <= 0.0 || rel > 1.0 ||
        clutter_height_m < 0.0 || radius_km <= 0.0 || radius_km > 1000.0 ||
        (resolution_ippd != 1200 && resolution_ippd != 3600))
        return SPLAT_E_BADPARAM;

    Engine *e = new (std::nothrow) Engine;
    if (!e)
        return SPLAT_E_NOMEM;

    e->ippd = resolution_ippd;
    e->mpi = resolution_ippd - 1;
    e->ppd = (double)resolution_ippd;
    e->dpp = 1.0 / e->ppd;
    e->max_pages = (resolution_ippd == 3600) ? MAX_PAGES_HD : MAX_PAGES_SD;

    /* LoadQTH longitude convention: the legacy backend wrote west-positive
     * longitudes (abs(lon) if lon < 0 else 360 - lon); LoadQTH then
     * normalizes negatives. Replicated bit-for-bit, including lon=0 -> 360. */
    double lon_wp = (tx_lon_deg < 0.0) ? -tx_lon_deg : 360.0 - tx_lon_deg;
    if (lon_wp < 0.0)
        lon_wp += 360.0;

    e->tx.lat = tx_lat_deg;
    e->tx.lon = lon_wp;
    e->tx.alt = (float)tx_alt_feet;
    e->rx_alt_feet = rx_alt_feet;

    /* -metric conversions from main(): km -> miles, meters -> feet. */
    e->max_range = radius_km / KM_PER_MILE;
    e->clutter = clutter_height_m / METERS_PER_FOOT;

    e->eps_dielect = eps_dielect;
    e->sgm_conductivity = sgm_conductivity;
    e->eno_ns_surfref = eno_ns_surfref;
    e->frq_mhz = frequency_mhz;
    e->radio_climate = radio_climate;
    e->pol = polarization;
    e->conf = conf;
    e->rel = rel;
    e->erp = erp_watts;

    /* Region setup from main() (8410-8569), single transmitter site. */

    int txlat = (int)floor(e->tx.lat);
    int txlon = (int)floor(e->tx.lon);

    int min_lat = txlat;
    int max_lat = txlat;
    int min_lon = txlon;
    int max_lon = txlon;

    /* First LoadTopoData call covers the transmitter's own page. */
    int rc = LoadTopoData(*e, max_lon, min_lon, max_lat, min_lat);
    if (rc < 0) {
        free_engine(e);
        return rc;
    }

    double deg_range = e->max_range / 57.0;
    double deg_range_lon;
    double deg_limit =
        (resolution_ippd == 3600) ? DEG_LIMIT_HD : DEG_LIMIT_SD;

    if (fabs(e->tx.lat) < 70.0)
        deg_range_lon = deg_range / cos(DEG2RAD * e->tx.lat);
    else
        deg_range_lon = deg_range / cos(DEG2RAD * 70.0);

    if (deg_range > deg_limit)
        deg_range = deg_limit;
    if (deg_range_lon > deg_limit)
        deg_range_lon = deg_limit;

    int north_min = (int)floor(e->tx.lat - deg_range);
    int north_max = (int)floor(e->tx.lat + deg_range);

    int west_min = (int)floor(e->tx.lon - deg_range_lon);

    while (west_min < 0)
        west_min += 360;
    while (west_min >= 360)
        west_min -= 360;

    int west_max = (int)floor(e->tx.lon + deg_range_lon);

    while (west_max < 0)
        west_max += 360;
    while (west_max >= 360)
        west_max -= 360;

    if (north_min < min_lat)
        min_lat = north_min;
    if (north_max > max_lat)
        max_lat = north_max;

    if (LonDiff(west_min, min_lon) < 0.0)
        min_lon = west_min;
    if (LonDiff(west_max, max_lon) >= 0.0)
        max_lon = west_max;

    rc = LoadTopoData(*e, max_lon, min_lon, max_lat, min_lat);
    if (rc < 0) {
        free_engine(e);
        return rc;
    }

    precompute_radials(*e);

    e->out_width = (int)((unsigned)(e->ippd * ReduceAngle(e->max_west - e->min_west)));
    e->out_height = (int)((unsigned)(e->ippd * ReduceAngle(e->max_north - e->min_north)));

    e->path_lat.resize(ARRAYSIZE);
    e->path_lon.resize(ARRAYSIZE);
    e->path_elevation.resize(ARRAYSIZE);
    e->path_distance.resize(ARRAYSIZE);
    e->elev.resize(ARRAYSIZE + 10);

    /* Reuse a freed slot if one exists. */
    for (size_t i = 0; i < g_engines.size(); i++) {
        if (g_engines[i] == nullptr) {
            g_engines[i] = e;
            return (int)i + 1;
        }
    }
    g_engines.push_back(e);
    return (int)g_engines.size();
}

int splat_page_count(int handle) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;
    return (int)e->pages.size();
}

int splat_page_info(int handle, int index, int32_t *out2) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;
    if (index < 0 || index >= (int)e->pages.size() || !out2)
        return SPLAT_E_BADPAGE;
    out2[0] = e->pages[index].min_north;
    out2[1] = e->pages[index].min_west;
    return 0;
}

int splat_load_page(int handle, int index, const int16_t *data) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;
    if (index < 0 || index >= (int)e->pages.size() || !data)
        return SPLAT_E_BADPAGE;
    memcpy(e->pages[index].data, data,
           (size_t)e->ippd * (size_t)e->ippd * sizeof(int16_t));
    return 0;
}

int splat_radial_count(int handle) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;
    return (int)e->radial_lat.size();
}

int splat_run_radials(int handle, int start, int count) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;
    if (start < 0 || count < 0 || start > (int)e->radial_lat.size())
        return SPLAT_E_BADPARAM;

    int end = start + count;
    if (end > (int)e->radial_lat.size())
        end = (int)e->radial_lat.size();

    Site edge{};
    for (int i = start; i < end; i++) {
        edge.lat = e->radial_lat[i];
        edge.lon = e->radial_lon[i];
        edge.alt = (float)e->rx_alt_feet;
        PlotLRPath(*e, e->tx, edge);
    }
    return end - start;
}

int splat_rasterize(int handle) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;

    size_t n = (size_t)e->out_width * (size_t)e->out_height;
    e->out_signal.assign(n, 0);
    e->out_mask.assign(n, 0);

    /* WritePPMDBM traversal (splat.cpp:5343-5360). */
    double north = (double)e->max_north - e->dpp;
    double lat, lon;
    int x, y;

    for (y = 0, lat = north; y < e->out_height;
         y++, lat = north - (e->dpp * (double)y)) {
        for (x = 0, lon = (double)e->max_west; x < e->out_width;
             x++, lon = (double)e->max_west - (e->dpp * (double)x)) {
            if (lon < 0.0)
                lon += 360.0;

            int px, py;
            Page *p = find_page(*e, lat, lon, px, py);
            if (p) {
                e->out_mask[(size_t)y * e->out_width + x] =
                    p->mask[px * e->ippd + py];
                e->out_signal[(size_t)y * e->out_width + x] =
                    p->signal[px * e->ippd + py];
            }
        }
    }
    return 0;
}

int splat_region_info(int handle, double *out8) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;
    if (!out8)
        return SPLAT_E_BADPARAM;

    /* KML LatLonBox values, WritePPMDBM:5230-5238 - including the original
     * minwest/min_west asymmetry in the east bound, which the legacy
     * GeoTIFFs inherit. */
    double minwest = e->dpp + (double)e->min_west;
    double north = (double)e->max_north - e->dpp;
    double south = (double)e->min_north;
    double east = (minwest < 180.0) ? -minwest : 360.0 - (double)e->min_west;
    double west =
        (double)(e->max_west < 180 ? -e->max_west : 360 - e->max_west);

    out8[0] = (double)e->out_width;
    out8[1] = (double)e->out_height;
    out8[2] = north;
    out8[3] = south;
    out8[4] = east;
    out8[5] = west;
    out8[6] = (double)e->radial_lat.size();
    out8[7] = (double)e->pages.size();
    return 0;
}

uint8_t *splat_signal_ptr(int handle) {
    Engine *e = get_engine(handle);
    if (!e || e->out_signal.empty())
        return nullptr;
    return e->out_signal.data();
}

uint8_t *splat_mask_ptr(int handle) {
    Engine *e = get_engine(handle);
    if (!e || e->out_mask.empty())
        return nullptr;
    return e->out_mask.data();
}

int splat_errnum_counts(int handle, int32_t *out6) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;
    if (!out6)
        return SPLAT_E_BADPARAM;
    for (int i = 0; i < 6; i++)
        out6[i] = e->errnum_counts[i];
    return 0;
}

/* Single transmitter->destination link analysis (issue #14). Runs the same
 * ITM model the coverage sweep uses, over the full great-circle profile from
 * the TX to one target, and reports the destination path loss / signal plus
 * the terrain profile for the line-of-sight chart. Unlike PlotLRPath it does
 * NOT write to the page rasters, so it is safe to call independently of (or
 * after) a coverage run.
 *
 * The caller must have loaded the terrain pages the TX->target path crosses
 * (same LoadSDF semantics as coverage); unloaded ground reads as sea level.
 * elev[1] uses SPLAT's point-to-point report spacing (total / (points - 1)).
 *
 * out5 receives [loss_db, dbm, distance_km, azimuth_deg, errnum]. dbm uses the
 * coverage convention (EIRP from ERP; RX antenna gain excluded - add it in TS).
 * Returns the profile point count (>= 2) or a negative SPLAT_E_* code. */
int splat_point_to_point(int handle, double dst_lat_deg, double dst_lon_deg,
                         double dst_alt_feet, double *out5) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;
    if (!out5 || dst_lat_deg < -90.0 || dst_lat_deg > 90.0 ||
        dst_lon_deg < -180.0 || dst_lon_deg > 180.0)
        return SPLAT_E_BADPARAM;

    /* West-positive longitude, matching LoadQTH (see splat_create). */
    double lon_wp = (dst_lon_deg < 0.0) ? -dst_lon_deg : 360.0 - dst_lon_deg;
    if (lon_wp < 0.0)
        lon_wp += 360.0;

    Site dst{};
    dst.lat = dst_lat_deg;
    dst.lon = lon_wp;
    dst.alt = (float)dst_alt_feet;

    ReadPath(*e, e->tx, dst);
    int n = e->path_length;
    if (n < 2)
        return SPLAT_E_BADPARAM;

    double *elev = e->elev.data();

    /* Terrain (+ clutter on interior cells; sea-level cells and the two
     * endpoints get none), in meters, exactly as PlotLRPath builds it. */
    for (int x = 1; x < n - 1; x++)
        elev[x + 2] = (e->path_elevation[x] == 0.0
                           ? e->path_elevation[x] * METERS_PER_FOOT
                           : (e->clutter + e->path_elevation[x]) *
                                 METERS_PER_FOOT);
    elev[2] = e->path_elevation[0] * METERS_PER_FOOT;
    elev[n + 1] = e->path_elevation[n - 1] * METERS_PER_FOOT;

    /* ITM over the whole profile (number_of_points = n). */
    elev[0] = (double)(n - 1);
    elev[1] = METERS_PER_MILE * (e->path_distance[n - 1] / (double)(n - 1));

    double loss = 0.0;
    char strmode[100];
    int errnum = 0;
    point_to_point_ITM(elev, e->tx.alt * METERS_PER_FOOT,
                       dst.alt * METERS_PER_FOOT, e->eps_dielect,
                       e->sgm_conductivity, e->eno_ns_surfref, e->frq_mhz,
                       e->radio_climate, e->pol, e->conf, e->rel, loss, strmode,
                       errnum);

    double rxp = e->erp / pow(10.0, (loss - 2.14) / 10.0);
    double dBm = 10.0 * log10(rxp * 1000.0);

    out5[0] = loss;
    out5[1] = dBm;
    out5[2] = e->path_distance[n - 1] * KM_PER_MILE;
    out5[3] = Azimuth(e->tx, dst);
    out5[4] = (double)errnum;

    /* Pack the ground profile as [distance_km, elevation_m] pairs (no clutter)
     * for the UI's line-of-sight / Fresnel chart. */
    e->p2p_profile.resize((size_t)n * 2);
    for (int i = 0; i < n; i++) {
        e->p2p_profile[(size_t)i * 2] = e->path_distance[i] * KM_PER_MILE;
        e->p2p_profile[(size_t)i * 2 + 1] =
            e->path_elevation[i] * METERS_PER_FOOT;
    }
    e->p2p_length = n;

    return n;
}

/* Pointer to the packed [distance_km, elevation_m] profile from the most
 * recent splat_point_to_point call (length = 2 * returned point count). */
double *splat_p2p_profile_ptr(int handle) {
    Engine *e = get_engine(handle);
    if (!e || e->p2p_profile.empty())
        return nullptr;
    return e->p2p_profile.data();
}

/* Highest loaded terrain cell within radius_km of the TX (issue #39): "find
 * highpoint". Scans the loaded page grids (cell->lat/lon inverts find_page's
 * mapping) and returns the highest cell strictly above the TX's own ground, or
 * the TX position unchanged if nothing nearby is higher. out3 receives
 * [lat_deg, lon_signed_deg, elevation_m]. The caller loads the pages covering
 * the search disk first. Returns 0 or a negative SPLAT_E_* code. */
int splat_highpoint(int handle, double radius_km, double *out3) {
    Engine *e = get_engine(handle);
    if (!e)
        return SPLAT_E_BADHANDLE;
    if (!out3 || radius_km <= 0.0)
        return SPLAT_E_BADPARAM;

    const double radius_mi = radius_km / KM_PER_MILE;

    /* Baseline: the TX's own ground, so we only relocate to something higher. */
    short best = -32768;
    {
        int tx_x, tx_y;
        Page *tp = find_page(*e, e->tx.lat, e->tx.lon, tx_x, tx_y);
        if (tp)
            best = tp->data[tx_x * e->ippd + tx_y];
    }
    double best_lat = e->tx.lat;
    double best_lon_wp = e->tx.lon;

    Site cell{};
    for (Page &p : e->pages) {
        if (!p.data)
            continue;
        for (int x = 0; x <= e->mpi; x++) {
            const double lat = p.min_north + (double)x / e->ppd;
            const short *row = &p.data[(size_t)x * e->ippd];
            for (int y = 0; y <= e->mpi; y++) {
                const short m = row[y];
                if (m <= best)
                    continue; /* cheap reject before the great-circle test */
                const double lon_wp =
                    p.max_west - (double)(e->mpi - y) / e->ppd;
                cell.lat = lat;
                cell.lon = lon_wp;
                if (Distance(e->tx, cell) <= radius_mi) {
                    best = m;
                    best_lat = lat;
                    best_lon_wp = lon_wp;
                }
            }
        }
    }

    double wp = best_lon_wp;
    while (wp < 0.0)
        wp += 360.0;
    while (wp >= 360.0)
        wp -= 360.0;
    out3[0] = best_lat;
    out3[1] = (wp <= 180.0) ? -wp : 360.0 - wp;
    out3[2] = (double)best;
    return 0;
}

void splat_destroy(int handle) {
    Engine *e = get_engine(handle);
    if (!e)
        return;
    g_engines[handle - 1] = nullptr;
    free_engine(e);
}

void *splat_malloc(int bytes) {
    if (bytes <= 0)
        return nullptr;
    return malloc((size_t)bytes);
}

void splat_free(void *ptr) { free(ptr); }

} /* extern "C" */
