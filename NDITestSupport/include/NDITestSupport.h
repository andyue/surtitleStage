#pragma once
#include <stdint.h>
#include <stddef.h>
void *ss_test_receiver_create(const char *path, const char *source);
int ss_test_receive(void *receiver, uint8_t *rgba, size_t capacity, int *width, int *height, int *fps);
void ss_test_receiver_destroy(void *receiver);
