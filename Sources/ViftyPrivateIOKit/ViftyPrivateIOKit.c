#include "ViftyPrivateIOKit.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <stdint.h>
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

static io_service_t vifty_get_service_by_name(const char *name) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching(name));
    if (service != IO_OBJECT_NULL) {
        return service;
    }
    return IO_OBJECT_NULL;
}

static io_service_t vifty_get_service_by_class(const char *class_name) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(class_name));
    if (service != IO_OBJECT_NULL) {
        return service;
    }
    return IO_OBJECT_NULL;
}

static io_service_t vifty_get_service_by_iterator(void) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator);
    if (result != KERN_SUCCESS || iterator == IO_OBJECT_NULL) {
        return IO_OBJECT_NULL;
    }
    io_service_t service = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    return service;
}

static io_service_t vifty_get_service_by_registry_walk(void) {
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    if (root == IO_OBJECT_NULL) {
        return IO_OBJECT_NULL;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IORegistryEntryCreateIterator(
        root,
        kIOServicePlane,
        kIORegistryIterateRecursively,
        &iterator
    );
    IOObjectRelease(root);
    if (result != KERN_SUCCESS || iterator == IO_OBJECT_NULL) {
        return IO_OBJECT_NULL;
    }

    io_object_t entry = IO_OBJECT_NULL;
    while ((entry = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        io_name_t name = {0};
        io_name_t className = {0};
        IORegistryEntryGetName(entry, name);
        IOObjectGetClass(entry, className);

        if (strcmp(name, "AppleSMCKeysEndpoint") == 0 || strcmp(className, "AppleSMCKeysEndpoint") == 0) {
            IOObjectRelease(iterator);
            return entry;
        }

        IOObjectRelease(entry);
    }

    IOObjectRelease(iterator);
    return IO_OBJECT_NULL;
}

static io_service_t vifty_get_service_by_known_paths(void) {
    const char *paths[] = {
        "IOService:/AppleARMPE/arm-io/AppleT600xIO/smc@90400000/AppleASCWrapV4/iop-smc-nub/RTBuddy(SMC)/SMCEndpoint1/AppleSMCKeysEndpoint",
        "IOService:/AppleARMPE/arm-io/AppleT811xIO/smc@90400000/AppleASCWrapV4/iop-smc-nub/RTBuddy(SMC)/SMCEndpoint1/AppleSMCKeysEndpoint",
        "IOService:/AppleARMPE/arm-io/AppleT812xIO/smc@90400000/AppleASCWrapV4/iop-smc-nub/RTBuddy(SMC)/SMCEndpoint1/AppleSMCKeysEndpoint",
        "IOService:/AppleARMPE/arm-io/AppleT813xIO/smc@90400000/AppleASCWrapV4/iop-smc-nub/RTBuddy(SMC)/SMCEndpoint1/AppleSMCKeysEndpoint",
        "IOService:/AppleARMPE/arm-io/AppleT814xIO/smc@90400000/AppleASCWrapV4/iop-smc-nub/RTBuddy(SMC)/SMCEndpoint1/AppleSMCKeysEndpoint"
    };

    for (size_t index = 0; index < sizeof(paths) / sizeof(paths[0]); index++) {
        io_registry_entry_t entry = IORegistryEntryFromPath(kIOMainPortDefault, paths[index]);
        if (entry != IO_OBJECT_NULL) {
            return entry;
        }
    }

    return IO_OBJECT_NULL;
}

int ViftyOpenSMC(io_connect_t *connection) {
    if (connection == 0) {
        return KERN_INVALID_ARGUMENT;
    }

    *connection = IO_OBJECT_NULL;
    io_service_t service = IO_OBJECT_NULL;

    service = vifty_get_service_by_name("AppleSMCKeysEndpoint");
    if (service == IO_OBJECT_NULL) service = vifty_get_service_by_name("SMCEndpoint1");
    if (service == IO_OBJECT_NULL) service = vifty_get_service_by_class("AppleSMCKeysEndpoint");
    if (service == IO_OBJECT_NULL) service = vifty_get_service_by_class("AppleSMC");
    if (service == IO_OBJECT_NULL) service = vifty_get_service_by_iterator();
    if (service == IO_OBJECT_NULL) service = vifty_get_service_by_registry_walk();
    if (service == IO_OBJECT_NULL) service = vifty_get_service_by_known_paths();

    if (service == IO_OBJECT_NULL) {
        return kIOReturnNoDevice;
    }

    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return result;
}
