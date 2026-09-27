#include "G2LC3Bridge.h"
#include "lc3.h"
#include <stdlib.h>

// Independently implemented ownership and bounds-checked bridge to Google liblc3.
void *g2_lc3_create(void) {
    unsigned size = lc3_decoder_size(10000, 16000);
    if (!size) return NULL;
    void *memory = calloc(1, size);
    if (!memory) return NULL;
    if (!lc3_setup_decoder(10000, 16000, 16000, memory)) {
        free(memory);
        return NULL;
    }
    return memory;
}
void g2_lc3_destroy(void *decoder) { free(decoder); }
int g2_lc3_decode(void *decoder, const uint8_t *input, size_t count,
                  int16_t *output, size_t capacity) {
    if (!decoder || !input || count != 40 || !output || capacity < 160) return -1;
    return lc3_decode((lc3_decoder_t)decoder, input, 40, LC3_PCM_FORMAT_S16, output, 1);
}
