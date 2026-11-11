#include "NDIBridge.h"
#include "SDK/Processing.NDI.Lib.h"
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
struct SSNDIRuntime { void *library; const NDIlib_v5 *api; char *path; };
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
// Keep the initialized SDK loaded for process lifetime: its discovery threads may outlive a sender.
static SSNDIRuntime *loaded;
SSNDIRuntime *ss_ndi_open(const char *path, char *error, size_t capacity) {
    pthread_mutex_lock(&lock);
    if (loaded) {
        if (strcmp(path, loaded->path)) {
            snprintf(error, capacity, "Restart SubtitleStage before selecting a different NDI runtime.");
            pthread_mutex_unlock(&lock); return NULL;
        }
        pthread_mutex_unlock(&lock); return loaded;
    }
    void *lib = dlopen(path, RTLD_LOCAL | RTLD_NOW);
    if (!lib) { snprintf(error, capacity, "%s", dlerror()); pthread_mutex_unlock(&lock); return NULL; }
    const NDIlib_v5 *(*load)(void) = dlsym(lib, "NDIlib_v5_load");
    const NDIlib_v5 *api = load ? load() : NULL;
    if (!api || !api->initialize || !api->send_create || !api->send_destroy || !api->send_send_video_v2 || !api->send_get_no_connections) {
        snprintf(error, capacity, "The selected library does not provide the supported NDI v5 API.");
        dlclose(lib); pthread_mutex_unlock(&lock); return NULL;
    }
    if (!api->initialize()) {
        snprintf(error, capacity, "NDI runtime initialization failed on this computer.");
        // Retain the image even on initialization failure to avoid racing runtime threads.
        pthread_mutex_unlock(&lock); return NULL;
    }
    loaded = calloc(1, sizeof(*loaded)); loaded->library = lib; loaded->api = api; loaded->path = strdup(path);
    pthread_mutex_unlock(&lock); return loaded;
}
const char *ss_ndi_version(SSNDIRuntime *r) { return r->api->version ? r->api->version() : "NDI"; }
void *ss_ndi_sender_create(SSNDIRuntime *r, const char *name) {
    NDIlib_send_create_t config = { .p_ndi_name = name, .clock_video = false, .clock_audio = false };
    return r->api->send_create(&config);
}
void ss_ndi_sender_destroy(SSNDIRuntime *r, void *s) { r->api->send_destroy(s); }
void ss_ndi_send(SSNDIRuntime *r, void *s, const uint8_t *rgba, int w, int h, int fps) {
    NDIlib_video_frame_v2_t f = {0};
    f.xres = w; f.yres = h; f.FourCC = NDIlib_FourCC_video_type_RGBA;
    f.frame_rate_N = fps; f.frame_rate_D = 1; f.picture_aspect_ratio = (float)w / h;
    f.frame_format_type = NDIlib_frame_format_type_progressive;
    f.timecode = NDIlib_send_timecode_synthesize; f.p_data = (uint8_t *)rgba; f.line_stride_in_bytes = w * 4;
    // Synchronous send on the worker: caller may safely reuse pixels after return.
    r->api->send_send_video_v2(s, &f);
}
int ss_ndi_connections(SSNDIRuntime *r, void *s) { return r->api->send_get_no_connections(s, 0); }
void ss_ndi_convert_rgba(const uint8_t *s, uint8_t *d, size_t pixels, double opacity, bool transparent) {
    unsigned scale = (unsigned)(opacity * 65535.0 + 0.5);
    for (size_t i = 0; i < pixels; i++, s += 4, d += 4) {
        unsigned a = s[3];
        if (transparent) {
            unsigned faded = (a * scale + 32767) / 65535;
            d[3] = faded;
            for (int c = 0; c < 3; c++) {
                unsigned straight = a ? (s[c] * 255U + a / 2) / a : 0;
                d[c] = faded ? (straight > 255 ? 255 : straight) : 0;
            }
        } else {
            for (int c = 0; c < 3; c++) d[c] = (s[c] * scale + 32767) / 65535;
            d[3] = 255;
        }
    }
}
