// Feeds the default sink's monitor audio through libcava (LukashonakV's
// fork of karlstav/cava, built as a shared library - the plain Arch
// `cava` package is just the CLI and doesn't ship this) and prints one
// frame per line as semicolon-separated 0-100 integers, the same shape
// Cava.qml already expects.
//
// Built against that fork's real include/cava/cavacore.h: cava_init
// returns a struct cava_plan* whose ->status/->error_message report
// failure (it does NOT return NULL on error, unlike an earlier version
// of this file that checked for that), and there is no `cava_plan`
// typedef - it's `struct cava_plan` throughout.
//
// Device selection is deliberately simple rather than using PulseAudio's
// full async/context API: shells out to `pactl get-default-sink` once at
// startup and appends ".monitor", instead of reimplementing PulseAudio's
// own default-sink introspection.
#include <pulse/simple.h>
#include <pulse/error.h>
#include <cava/cavacore.h>

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define BARS 25
#define RATE 44100
#define CHANNELS 1
#define BUFFER_SAMPLES 512

static char *default_monitor_device(void) {
    FILE *p = popen("pactl get-default-sink", "r");
    if (!p) {
        return NULL;
    }

    char sink[256] = {0};
    if (!fgets(sink, sizeof(sink), p)) {
        pclose(p);
        return NULL;
    }
    pclose(p);

    sink[strcspn(sink, "\n")] = '\0';
    if (sink[0] == '\0') {
        return NULL;
    }

    char *device = malloc(strlen(sink) + strlen(".monitor") + 1);
    if (device) {
        sprintf(device, "%s.monitor", sink);
    }
    return device;
}

int main(void) {
    char *device = default_monitor_device();

    pa_sample_spec spec;
    spec.format = PA_SAMPLE_S16LE;
    spec.rate = RATE;
    spec.channels = CHANNELS;

    int pa_err = 0;
    pa_simple *pa = pa_simple_new(NULL, "quickshell-cava", PA_STREAM_RECORD, device,
                                   "cava capture", &spec, NULL, NULL, &pa_err);
    free(device);

    if (!pa) {
        fprintf(stderr, "pa_simple_new failed: %s\n", pa_strerror(pa_err));
        return 1;
    }

    // The installed public header only forward-declares struct
    // cava_plan (its fields, including ->status/->error_message, are
    // only visible inside cava's own build) - so unlike a typical
    // "check the return value" API, there's no way for external code to
    // read the error path at all here. cava_init also never returns
    // NULL. BARS/RATE/CHANNELS/cutoffs above are fixed, known-valid
    // values (25 bars is well under the ~257-bar ceiling for a 512-frame
    // buffer at 44100Hz), so in practice this always succeeds.
    struct cava_plan *plan = cava_init(BARS, RATE, CHANNELS, 1, 0.77, 50, 10000);

    int16_t samples[BUFFER_SAMPLES * CHANNELS];
    double cava_in[BUFFER_SAMPLES * CHANNELS];
    double cava_out[BARS * CHANNELS];

    setvbuf(stdout, NULL, _IOLBF, 0);

    while (1) {
        if (pa_simple_read(pa, samples, sizeof(samples), &pa_err) < 0) {
            fprintf(stderr, "pa_simple_read failed: %s\n", pa_strerror(pa_err));
            return 1;
        }

        for (int i = 0; i < BUFFER_SAMPLES * CHANNELS; i++) {
            cava_in[i] = (double)samples[i];
        }

        cava_execute(cava_in, BUFFER_SAMPLES * CHANNELS, cava_out, plan);

        for (int i = 0; i < BARS; i++) {
            int v = (int)(cava_out[i] * 100.0);
            if (v < 0) v = 0;
            if (v > 100) v = 100;
            printf("%s%d", i == 0 ? "" : ";", v);
        }
        printf("\n");
    }
}
