#include "Fixture.h"
#include "lc3.h"
#include <stdlib.h>
#include <math.h>
int make_test_packet(uint8_t *packet) {
    void *memory = calloc(1, lc3_encoder_size(10000, 16000));
    if (!memory) return -1;
    lc3_encoder_t encoder = lc3_setup_encoder(10000, 16000, 16000, memory);
    if (!encoder) { free(memory); return -1; }
    for (int frame = 0; frame < 5; ++frame) {
        int16_t samples[160];
        for (int n = 0; n < 160; ++n)
            samples[n] = (int16_t)(12000 * sin(2 * 3.141592653589793 * 440 * (frame * 160 + n) / 16000));
        if (lc3_encode(encoder, LC3_PCM_FORMAT_S16, samples, 1, 40, packet + frame * 40) != 0) {
            free(memory); return -1;
        }
    }
    free(memory);
    return 0;
}
