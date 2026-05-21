#ifndef VIFTY_PRIVATE_IOKIT_H
#define VIFTY_PRIVATE_IOKIT_H

#include <IOKit/IOKitLib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char name[128];
    double celsius;
} ViftyHIDTemperature;

int ViftyCopyHIDTemperatures(ViftyHIDTemperature *buffer, int capacity);
int ViftyOpenSMC(io_connect_t *connection);

#ifdef __cplusplus
}
#endif

#endif
