#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
typedef struct SSNDIRuntime SSNDIRuntime;
SSNDIRuntime *ss_ndi_open(const char *path, char *error, size_t capacity);
const char *ss_ndi_version(SSNDIRuntime *runtime);
void *ss_ndi_sender_create(SSNDIRuntime *runtime, const char *name);
void ss_ndi_sender_destroy(SSNDIRuntime *runtime, void *sender);
void ss_ndi_send(SSNDIRuntime *runtime, void *sender, const uint8_t *rgba, int width, int height, int fps);
int ss_ndi_connections(SSNDIRuntime *runtime, void *sender);
void ss_ndi_convert_rgba(const uint8_t *source, uint8_t *destination, size_t pixels, double opacity, bool transparent);
