#include "NDITestSupport.h"
#include "../NDIBridge/SDK/Processing.NDI.Lib.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
typedef struct { const NDIlib_v5 *api; NDIlib_recv_instance_t receiver; void *library; } Receiver;
void *ss_test_receiver_create(const char *path, const char *source) {
    void *library = dlopen(path, RTLD_LOCAL | RTLD_NOW);
    if (!library) return NULL;
    const NDIlib_v5 *(*load)(void) = dlsym(library, "NDIlib_v5_load");
    const NDIlib_v5 *api = load ? load() : NULL;
    if (!api) { dlclose(library); return NULL; }
    NDIlib_find_create_t fc = { .show_local_sources = true };
    NDIlib_find_instance_t finder = api->find_create_v2(&fc);
    if (!finder) { dlclose(library); return NULL; }
    NDIlib_recv_instance_t receiver = NULL;
    for (int attempt = 0; attempt < 30 && !receiver; attempt++) {
        uint32_t count = 0;
        const NDIlib_source_t *sources = api->find_get_current_sources(finder, &count);
        for (uint32_t i = 0; i < count; i++) {
            if (!strstr(sources[i].p_ndi_name, source)) continue;
            NDIlib_recv_create_v3_t c = {0};
            c.source_to_connect_to = sources[i]; c.color_format = NDIlib_recv_color_format_RGBX_RGBA;
            c.bandwidth = NDIlib_recv_bandwidth_highest; c.allow_video_fields = false;
            c.p_ndi_recv_name = "SubtitleStage Automated Verification";
            receiver = api->recv_create_v3(&c); break;
        }
        if (!receiver) api->find_wait_for_sources(finder, 100);
    }
    api->find_destroy(finder);
    if (!receiver) { dlclose(library); return NULL; }
    Receiver *r = calloc(1, sizeof(*r)); r->api = api; r->receiver = receiver; r->library = library; return r;
}
int ss_test_receive(void *receiver, uint8_t *rgba, size_t capacity, int *width, int *height, int *fps) {
    Receiver *r = receiver;
    NDIlib_video_frame_v2_t f = {0};
    NDIlib_frame_type_e type = r->api->recv_capture_v2(r->receiver, &f, NULL, NULL, 50);
    if (type != NDIlib_frame_type_video) return 0;
    int result = -1;
    if (f.p_data && f.xres > 0 && f.yres > 0 && (size_t)f.xres * f.yres * 4 <= capacity &&
        (f.FourCC == NDIlib_FourCC_video_type_RGBA || f.FourCC == NDIlib_FourCC_video_type_RGBX)) {
        for (int y = 0; y < f.yres; y++) {
            memcpy(rgba + y * f.xres * 4, f.p_data + y * f.line_stride_in_bytes, f.xres * 4);
        }
        if (f.FourCC == NDIlib_FourCC_video_type_RGBX) {
            for (size_t p = 3; p < (size_t)f.xres * f.yres * 4; p += 4) rgba[p] = 255;
        }
        *width = f.xres; *height = f.yres; *fps = f.frame_rate_N / f.frame_rate_D; result = 1;
    }
    r->api->recv_free_video_v2(r->receiver, &f); return result;
}
void ss_test_receiver_destroy(void *receiver) {
    Receiver *r = receiver; r->api->recv_destroy(r->receiver); dlclose(r->library); free(r);
}
