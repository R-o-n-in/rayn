#include "/home/ron/.nimble/pkgs2/naylib-26.08.0-19dd4e7e34c705c677e89b3a6516846c9f2e0125/raylib/external/glfw/src/internal.h"
#include <wayland-client.h>

void setCustomInputRegion(void* surfPtr, int x, int y, int w, int h) {
    if (!_glfw.wl.compositor) return;
    struct wl_surface* surface = (struct wl_surface*)surfPtr;
    if (!surface && _glfw.windowListHead) {
        surface = _glfw.windowListHead->wl.surface;
    }
    if (surface) {
        struct wl_region* region = wl_compositor_create_region(_glfw.wl.compositor);
        if (region) {
            wl_region_add(region, x, y, w, h);
            wl_surface_set_input_region(surface, region);
            wl_region_destroy(region);
            wl_surface_commit(surface);
        }
    }
}
