#include "ViftyPrivateIOKit.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef const struct __IOHIDEvent *IOHIDEventRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int64_t field);

static CFNumberRef vifty_number(int value) {
    return CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &value);
}

int ViftyCopyHIDTemperatures(ViftyHIDTemperature *buffer, int capacity) {
    if (buffer == 0 || capacity <= 0) {
        return 0;
    }

    const int appleVendorPage = 0xff00;
    const int temperatureUsage = 0x0005;
    const int64_t temperatureEventType = 15;
    const int64_t temperatureField = temperatureEventType << 16;

    CFStringRef keys[2] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    CFNumberRef usagePage = vifty_number(appleVendorPage);
    CFNumberRef usage = vifty_number(temperatureUsage);
    if (usagePage == 0 || usage == 0) {
        if (usagePage) CFRelease(usagePage);
        if (usage) CFRelease(usage);
        return 0;
    }

    CFTypeRef values[2] = { usagePage, usage };
    CFDictionaryRef matching = CFDictionaryCreate(
        kCFAllocatorDefault,
        (const void **)keys,
        (const void **)values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    CFRelease(usagePage);
    CFRelease(usage);

    if (matching == 0) {
        return 0;
    }

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == 0) {
        CFRelease(matching);
        return 0;
    }

    IOHIDEventSystemClientSetMatching(client, matching);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    CFRelease(matching);

    if (services == 0) {
        CFRelease(client);
        return 0;
    }

    int written = 0;
    CFIndex serviceCount = CFArrayGetCount(services);
    for (CFIndex index = 0; index < serviceCount && written < capacity; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        if (service == 0) {
            continue;
        }

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, temperatureEventType, 0, 0);
        if (event == 0) {
            continue;
        }

        double celsius = IOHIDEventGetFloatValue(event, temperatureField);
        CFRelease(event);
        if (celsius <= 0.0 || celsius >= 130.0) {
            continue;
        }

        char name[128] = {0};
        CFTypeRef product = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (product != 0 && CFGetTypeID(product) == CFStringGetTypeID()) {
            CFStringGetCString((CFStringRef)product, name, sizeof(name), kCFStringEncodingUTF8);
        }
        if (product != 0) {
            CFRelease(product);
        }

        if (name[0] == '\0') {
            snprintf(name, sizeof(name), "Thermal Sensor %d", written + 1);
        }

        strncpy(buffer[written].name, name, sizeof(buffer[written].name) - 1);
        buffer[written].name[sizeof(buffer[written].name) - 1] = '\0';
        buffer[written].celsius = celsius;
        written += 1;
    }

    CFRelease(services);
    CFRelease(client);
    return written;
}
