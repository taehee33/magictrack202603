#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDBase.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef uint32_t IOHIDEventType;
typedef uint32_t IOHIDEventField;
typedef void (*IOHIDEventCallback)(void *target, void *refcon, IOHIDServiceClientRef service, IOHIDEventRef event);

extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
extern void IOHIDEventSystemClientScheduleWithRunLoop(IOHIDEventSystemClientRef client, CFRunLoopRef runLoop, CFStringRef runLoopMode);
extern void IOHIDEventSystemClientUnscheduleWithRunLoop(IOHIDEventSystemClientRef client, CFRunLoopRef runLoop, CFStringRef runLoopMode);
extern void IOHIDEventSystemClientRegisterEventCallback(IOHIDEventSystemClientRef client, IOHIDEventCallback callback, void *target, void *refcon);
extern IOHIDEventType IOHIDEventGetType(IOHIDEventRef event);
extern CFArrayRef IOHIDEventGetChildren(IOHIDEventRef event);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, IOHIDEventField field);
extern uint64_t IOHIDEventGetIntegerValue(IOHIDEventRef event, IOHIDEventField field);
extern CFStringRef IOHIDEventCopyDescription(IOHIDEventRef event);

enum {
    kIOHIDEventTypeNULL = 0,
    kIOHIDEventTypeVendorDefined = 1,
    kIOHIDEventTypeButton = 2,
    kIOHIDEventTypeKeyboard = 3,
    kIOHIDEventTypeTranslation = 4,
    kIOHIDEventTypeRotation = 5,
    kIOHIDEventTypeScroll = 6,
    kIOHIDEventTypeScale = 7,
    kIOHIDEventTypeZoom = 8,
    kIOHIDEventTypeVelocity = 9,
    kIOHIDEventTypeOrientation = 10,
    kIOHIDEventTypeDigitizer = 11,
    kIOHIDEventTypeAmbientLightSensor = 12,
    kIOHIDEventTypeAccelerometer = 13,
    kIOHIDEventTypeProximity = 14,
    kIOHIDEventTypeTemperature = 15,
    kIOHIDEventTypeNavigationSwipe = 16,
    kIOHIDEventTypePointer = 17,
    kIOHIDEventTypeProgress = 18,
    kIOHIDEventTypeMultiAxisPointer = 19
};

enum {
    kIOHIDEventFieldDigitizerX = (11 << 16) | 0,
    kIOHIDEventFieldDigitizerY = (11 << 16) | 1,
    kIOHIDEventFieldDigitizerZ = (11 << 16) | 2,
    kIOHIDEventFieldDigitizerRange = (11 << 16) | 7,
    kIOHIDEventFieldDigitizerTouch = (11 << 16) | 8,
    kIOHIDEventFieldDigitizerIsDisplayIntegrated = (11 << 16) | 9,
    kIOHIDEventFieldDigitizerChildEventMask = (11 << 16) | 10
};

static int gEventCount = 0;

static const char *event_type_name(IOHIDEventType type) {
    switch (type) {
        case kIOHIDEventTypeDigitizer: return "digitizer";
        case kIOHIDEventTypeScroll: return "scroll";
        case kIOHIDEventTypePointer: return "pointer";
        case kIOHIDEventTypeTranslation: return "translation";
        case kIOHIDEventTypeRotation: return "rotation";
        case kIOHIDEventTypeScale: return "scale";
        case kIOHIDEventTypeButton: return "button";
        default: return "other";
    }
}

static void event_callback(void *target, void *refcon, IOHIDServiceClientRef service, IOHIDEventRef event) {
    (void)target;
    (void)refcon;

    gEventCount++;
    IOHIDEventType type = IOHIDEventGetType(event);
    CFTypeRef builtInValue = IOHIDServiceClientCopyProperty(service, CFSTR("Built-In"));
    CFTypeRef productValue = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
    Boolean builtIn = false;
    if (builtInValue && CFGetTypeID(builtInValue) == CFBooleanGetTypeID()) {
        builtIn = CFBooleanGetValue((CFBooleanRef)builtInValue);
    }

    fprintf(stdout, "EVENT count=%d type=%u(%s) builtIn=%d service=%p",
            gEventCount, type, event_type_name(type), builtIn, service);

    if (productValue && CFGetTypeID(productValue) == CFStringGetTypeID()) {
        char product[256];
        if (CFStringGetCString((CFStringRef)productValue, product, sizeof(product), kCFStringEncodingUTF8)) {
            fprintf(stdout, " product=%s", product);
        }
    }

    if (type == kIOHIDEventTypeDigitizer) {
        double x = IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerX);
        double y = IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerY);
        uint64_t range = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldDigitizerRange);
        uint64_t touch = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldDigitizerTouch);
        CFArrayRef children = IOHIDEventGetChildren(event);
        CFIndex childCount = children ? CFArrayGetCount(children) : 0;
        fprintf(stdout, " x=%.4f y=%.4f range=%llu touch=%llu children=%ld",
                x, y, (unsigned long long)range, (unsigned long long)touch, (long)childCount);
    }

    fputc('\n', stdout);
    fflush(stdout);

    if (builtInValue) {
        CFRelease(builtInValue);
    }
    if (productValue) {
        CFRelease(productValue);
    }
}

int main(int argc, char **argv) {
    int duration = 10;
    if (argc > 1) {
        duration = atoi(argv[1]);
        if (duration <= 0) {
            duration = 10;
        }
    }

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    if (!client) {
        fprintf(stderr, "failed to create event system client\n");
        return 1;
    }

    IOHIDEventSystemClientScheduleWithRunLoop(client, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDEventSystemClientRegisterEventCallback(client, event_callback, NULL, NULL);

    fprintf(stdout, "IOHID_EVENT_PROBE duration=%d\n", duration);
    fflush(stdout);

    for (int second = 0; second < duration; second++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
        fprintf(stdout, "TICK second=%d events=%d\n", second + 1, gEventCount);
        fflush(stdout);
    }

    IOHIDEventSystemClientUnscheduleWithRunLoop(client, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    CFRelease(client);
    return 0;
}
