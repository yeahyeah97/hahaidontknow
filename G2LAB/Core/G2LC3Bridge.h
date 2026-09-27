#pragma once
#include <stdint.h>
#include <stddef.h>
void *g2_lc3_create(void);
void g2_lc3_destroy(void *decoder);
int g2_lc3_decode(void *decoder, const uint8_t *input, size_t count, int16_t *output, size_t capacity);
