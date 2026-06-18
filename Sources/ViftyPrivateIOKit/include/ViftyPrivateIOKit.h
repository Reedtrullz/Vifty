#ifndef VIFTY_PRIVATE_IOKIT_H
#define VIFTY_PRIVATE_IOKIT_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char name[128];
    double celsius;
} ViftyHIDTemperature;

int ViftyCopyHIDTemperatures(ViftyHIDTemperature *buffer, int capacity);

#ifdef __cplusplus
}
#endif

#endif
