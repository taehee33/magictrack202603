#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef CFTypeRef MTDeviceRef;
typedef CFMutableArrayRef (*MTDeviceCreateListFn)(void);
typedef MTDeviceRef (*MTDeviceCreateDefaultFn)(void);
typedef MTDeviceRef (*MTDeviceCreateFromServiceFn)(CFTypeRef);
typedef MTDeviceRef (*MTDeviceCreateFromDeviceIDFn)(uint64_t);
typedef bool (*MTDeviceIsBuiltInFn)(MTDeviceRef);
typedef int (*MTDeviceStartFn)(MTDeviceRef, int);
typedef int (*MTDeviceStopFn)(MTDeviceRef);
typedef void (*MTDeviceScheduleOnRunLoopFn)(MTDeviceRef, CFRunLoopRef, CFStringRef);
typedef CFRunLoopSourceRef (*MTDeviceCreateMultitouchRunLoopSourceFn)(MTDeviceRef);
typedef bool (*MTDeviceBoolFn)(MTDeviceRef);
typedef int (*MTDeviceSetInputDetectionModeFn)(MTDeviceRef, int);
typedef int (*MTDeviceSetTouchModeFn)(MTDeviceRef, int);
typedef int (*MTDeviceSetSurfaceOrientationFn)(MTDeviceRef, int);
typedef int (*MTDeviceGetFamilyIDFn)(MTDeviceRef, int *);
typedef int (*MTDeviceGetDriverTypeFn)(MTDeviceRef, int *);
typedef int (*MTDeviceGetDeviceIDFn)(MTDeviceRef, uint64_t *);
typedef CFTypeRef (*MTDeviceGetServiceFn)(MTDeviceRef);

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    uint32_t state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector;
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

typedef void (*MTFrameCallbackFunction)(MTDeviceRef, MTTouch *, size_t, double, size_t);
typedef void (*MTPathCallbackFunction)(MTDeviceRef, long, long, MTTouch *);
typedef void (*MTRegisterContactFrameCallbackFn)(MTDeviceRef, MTFrameCallbackFunction);
typedef void (*MTRegisterPathCallbackFn)(MTDeviceRef, MTPathCallbackFunction);
typedef void (*MTButtonStateCallbackFunction)(MTDeviceRef, int, int, int);
typedef void (*MTImageCallbackFunction)(MTDeviceRef, void *, size_t, double, size_t);
typedef void (*MTBlobFrameCallbackFunction)(MTDeviceRef, void *, size_t, double, size_t);
typedef void (*MTRegisterButtonStateCallbackFn)(MTDeviceRef, MTButtonStateCallbackFunction);
typedef void (*MTRegisterImageCallbackFn)(MTDeviceRef, MTImageCallbackFunction);
typedef void (*MTRegisterBlobFrameCallbackFn)(MTDeviceRef, MTBlobFrameCallbackFunction);
typedef void (*MTRegisterFullFrameCallbackFn)(MTDeviceRef, MTFrameCallbackFunction);
typedef void (*MTRegisterFrameHeaderCallbackFn)(MTDeviceRef, MTFrameCallbackFunction);
typedef void (*MTInputDetectionCallbackFunction)(MTDeviceRef, int, int, int, int);
typedef void (*MTRegisterInputDetectionCallbackFn)(MTDeviceRef, MTInputDetectionCallbackFunction);

static int gCallbackCount = 0;
static int gPathCallbackCount = 0;
static int gButtonCallbackCount = 0;
static int gImageCallbackCount = 0;
static int gBlobCallbackCount = 0;
static int gFullFrameCallbackCount = 0;
static int gFrameHeaderCallbackCount = 0;
static int gInputDetectionCallbackCount = 0;

static void contact_callback(MTDeviceRef device, MTTouch *touches, size_t numTouches, double timestamp, size_t frame) {
    gCallbackCount++;
    fprintf(stdout, "CALLBACK device=%p touches=%zu time=%.6f frame=%zu count=%d\n",
            device, numTouches, timestamp, frame, gCallbackCount);
    if (numTouches > 0 && touches) {
        MTTouch *t = &touches[0];
        fprintf(stdout,
                "  TOUCH finger=%d state=%u norm=(%.4f,%.4f) vel=(%.4f,%.4f) angle=%.4f size=%.4f\n",
                t->fingerID,
                t->state,
                t->normalizedVector.position.x,
                t->normalizedVector.position.y,
                t->normalizedVector.velocity.x,
                t->normalizedVector.velocity.y,
                t->angle,
                t->zTotal);
    }
    fflush(stdout);
}

static void path_callback(MTDeviceRef device, long pathID, long state, MTTouch *touch) {
    gPathCallbackCount++;
    fprintf(stdout, "PATH device=%p path=%ld state=%ld count=%d",
            device, pathID, state, gPathCallbackCount);
    if (touch) {
        fprintf(stdout, " norm=(%.4f,%.4f) vel=(%.4f,%.4f) finger=%d touchState=%u angle=%.4f size=%.4f",
                touch->normalizedVector.position.x,
                touch->normalizedVector.position.y,
                touch->normalizedVector.velocity.x,
                touch->normalizedVector.velocity.y,
                touch->fingerID,
                touch->state,
                touch->angle,
                touch->zTotal);
    }
    fputc('\n', stdout);
    fflush(stdout);
}

static void button_callback(MTDeviceRef device, int buttonIndex, int buttonState, int unknown) {
    gButtonCallbackCount++;
    fprintf(stdout,
            "BUTTON device=%p button=%d state=%d unknown=%d count=%d\n",
            device, buttonIndex, buttonState, unknown, gButtonCallbackCount);
    fflush(stdout);
}

static void image_callback(MTDeviceRef device, void *image, size_t length, double timestamp, size_t frame) {
    gImageCallbackCount++;
    fprintf(stdout,
            "IMAGE device=%p image=%p length=%zu time=%.6f frame=%zu count=%d\n",
            device, image, length, timestamp, frame, gImageCallbackCount);
    fflush(stdout);
}

static void blob_callback(MTDeviceRef device, void *blob, size_t count, double timestamp, size_t frame) {
    gBlobCallbackCount++;
    fprintf(stdout,
            "BLOB device=%p blob=%p count=%zu time=%.6f frame=%zu callbacks=%d\n",
            device, blob, count, timestamp, frame, gBlobCallbackCount);
    fflush(stdout);
}

static void full_frame_callback(MTDeviceRef device, MTTouch *touches, size_t numTouches, double timestamp, size_t frame) {
    gFullFrameCallbackCount++;
    fprintf(stdout,
            "FULLFRAME device=%p touches=%zu time=%.6f frame=%zu count=%d\n",
            device, numTouches, timestamp, frame, gFullFrameCallbackCount);
    fflush(stdout);
}

static void frame_header_callback(MTDeviceRef device, MTTouch *touches, size_t numTouches, double timestamp, size_t frame) {
    gFrameHeaderCallbackCount++;
    fprintf(stdout,
            "FRAMEHEADER device=%p touches=%zu time=%.6f frame=%zu count=%d\n",
            device, numTouches, timestamp, frame, gFrameHeaderCallbackCount);
    fflush(stdout);
}

static void input_detection_callback(MTDeviceRef device, int a, int b, int c, int d) {
    gInputDetectionCallbackCount++;
    fprintf(stdout,
            "INPUTDETECT device=%p a=%d b=%d c=%d d=%d count=%d\n",
            device, a, b, c, d, gInputDetectionCallbackCount);
    fflush(stdout);
}

static void *load_framework(void) {
    const char *path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport";
    void *handle = dlopen(path, RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "dlopen fail: %s\n", dlerror());
    }
    return handle;
}

static void print_symbol_availability(void *handle) {
    const char *symbols[] = {
        "MTDeviceCreateList",
        "MTDeviceCreateDefault",
        "MTDeviceCreateFromService",
        "MTDeviceCreateFromDeviceID",
        "MTDeviceStart",
        "MTDeviceStop",
        "MTDeviceIsBuiltIn",
        "MTDeviceGetDeviceID",
        "MTDeviceGetService",
        "MTDeviceGetFamilyID",
        "MTDeviceGetDriverType",
        "MTRegisterContactFrameCallback",
        "MTUnregisterContactFrameCallback",
        "MTRegisterPathCallback",
        "MTUnregisterPathCallback",
        "MTRegisterButtonStateCallback",
        "MTRegisterImageCallback",
        "MTRegisterBlobFrameCallback",
        "MTRegisterFullFrameCallback",
        "MTRegisterFrameHeaderCallback",
        "MTRegisterInputDetectionCallback",
        "MTDeviceIsAlive",
        "MTDeviceIsAvailable",
        "MTDeviceDriverIsReady",
        "MTDeviceIsRunning",
        "MTDeviceSetInputDetectionMode",
        "MTDeviceSetTouchMode",
        "MTDeviceSetSurfaceOrientation"
    };

    size_t count = sizeof(symbols) / sizeof(symbols[0]);
    for (size_t i = 0; i < count; i++) {
        fprintf(stdout, "SYM %-32s %s\n", symbols[i], dlsym(handle, symbols[i]) ? "yes" : "no");
    }
}

static CFArrayRef load_devices(void *handle, MTDeviceCreateListFn *createListOut) {
    MTDeviceCreateListFn createList = (MTDeviceCreateListFn)dlsym(handle, "MTDeviceCreateList");
    if (!createList) {
        fprintf(stderr, "missing MTDeviceCreateList\n");
        return NULL;
    }
    if (createListOut) {
        *createListOut = createList;
    }
    CFArrayRef devices = createList();
    if (!devices) {
        fprintf(stderr, "createList returned NULL\n");
        return NULL;
    }
    return devices;
}

static int run_info_mode(void *handle) {
    MTDeviceCreateListFn createList = NULL;
    MTDeviceCreateDefaultFn createDefault = (MTDeviceCreateDefaultFn)dlsym(handle, "MTDeviceCreateDefault");
    MTDeviceCreateFromServiceFn createFromService = (MTDeviceCreateFromServiceFn)dlsym(handle, "MTDeviceCreateFromService");
    MTDeviceCreateFromDeviceIDFn createFromDeviceID = (MTDeviceCreateFromDeviceIDFn)dlsym(handle, "MTDeviceCreateFromDeviceID");
    MTDeviceIsBuiltInFn isBuiltIn = (MTDeviceIsBuiltInFn)dlsym(handle, "MTDeviceIsBuiltIn");
    MTDeviceGetFamilyIDFn getFamilyID = (MTDeviceGetFamilyIDFn)dlsym(handle, "MTDeviceGetFamilyID");
    MTDeviceGetDriverTypeFn getDriverType = (MTDeviceGetDriverTypeFn)dlsym(handle, "MTDeviceGetDriverType");
    MTDeviceGetDeviceIDFn getDeviceID = (MTDeviceGetDeviceIDFn)dlsym(handle, "MTDeviceGetDeviceID");
    MTDeviceGetServiceFn getService = (MTDeviceGetServiceFn)dlsym(handle, "MTDeviceGetService");
    CFArrayRef devices = load_devices(handle, &createList);
    if (!devices) {
        return 2;
    }

    print_symbol_availability(handle);

    CFIndex count = CFArrayGetCount(devices);
    fprintf(stdout, "DEVICES %ld\n", (long)count);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        int familyID = -1;
        int driverType = -1;
        uint64_t deviceID = 0;
        int familyStatus = getFamilyID ? getFamilyID(dev, &familyID) : -1;
        int driverStatus = getDriverType ? getDriverType(dev, &driverType) : -1;
        int deviceStatus = getDeviceID ? getDeviceID(dev, &deviceID) : -1;
        fprintf(stdout,
                "DEVICE[%ld] ptr=%p builtIn=%d service=%p deviceID=%llu(deviceStatus=%d) family=%d(familyStatus=%d) driver=%d(driverStatus=%d)\n",
                (long)i,
                dev,
                isBuiltIn ? isBuiltIn(dev) : -1,
                getService ? getService(dev) : NULL,
                (unsigned long long)deviceID,
                deviceStatus,
                familyID,
                familyStatus,
                driverType,
                driverStatus);
        if (createFromService && getService) {
            fprintf(stdout, "  FROM_SERVICE[%ld] %p\n", (long)i, createFromService(getService(dev)));
        }
        if (createFromDeviceID && deviceStatus == 0) {
            fprintf(stdout, "  FROM_DEVICE_ID[%ld] %p\n", (long)i, createFromDeviceID(deviceID));
        }
    }
    if (createDefault) {
        MTDeviceRef defaultDevice = createDefault();
        int familyID = -1;
        int driverType = -1;
        uint64_t deviceID = 0;
        int familyStatus = getFamilyID ? getFamilyID(defaultDevice, &familyID) : -1;
        int driverStatus = getDriverType ? getDriverType(defaultDevice, &driverType) : -1;
        int deviceStatus = getDeviceID ? getDeviceID(defaultDevice, &deviceID) : -1;
        fprintf(stdout,
                "DEFAULT ptr=%p builtIn=%d service=%p deviceID=%llu(deviceStatus=%d) family=%d(familyStatus=%d) driver=%d(driverStatus=%d)\n",
                defaultDevice,
                isBuiltIn ? isBuiltIn(defaultDevice) : -1,
                getService ? getService(defaultDevice) : NULL,
                (unsigned long long)deviceID,
                deviceStatus,
                familyID,
                familyStatus,
                driverType,
                driverStatus);
    }
    fflush(stdout);
    return 0;
}

static int run_contact_mode(void *handle, int durationSeconds, bool usePathCallback) {
    MTRegisterContactFrameCallbackFn registerCallback =
        (MTRegisterContactFrameCallbackFn)dlsym(handle, "MTRegisterContactFrameCallback");
    MTRegisterPathCallbackFn registerPathCallback =
        (MTRegisterPathCallbackFn)dlsym(handle, "MTRegisterPathCallback");
    MTDeviceStartFn start = (MTDeviceStartFn)dlsym(handle, "MTDeviceStart");
    MTDeviceStopFn stop = (MTDeviceStopFn)dlsym(handle, "MTDeviceStop");
    MTDeviceIsBuiltInFn isBuiltIn = (MTDeviceIsBuiltInFn)dlsym(handle, "MTDeviceIsBuiltIn");

    if ((!registerCallback && !usePathCallback) || (!registerPathCallback && usePathCallback) || !start || !stop) {
        fprintf(stderr, "missing callback symbols\n");
        return 3;
    }

    CFArrayRef devices = load_devices(handle, NULL);
    if (!devices) {
        return 4;
    }

    CFIndex count = CFArrayGetCount(devices);
    fprintf(stdout, "%s_MODE devices=%ld duration=%d\n",
            usePathCallback ? "PATH" : "CONTACT",
            (long)count,
            durationSeconds);

    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        fprintf(stdout, "REGISTER[%ld] ptr=%p builtIn=%d\n",
                (long)i, dev, isBuiltIn ? isBuiltIn(dev) : -1);
        if (usePathCallback) {
            registerPathCallback(dev, path_callback);
        } else {
            registerCallback(dev, contact_callback);
        }
        fprintf(stdout, "START_RC[%ld]=%d\n", (long)i, start(dev, 0));
    }
    fflush(stdout);

    for (int second = 0; second < durationSeconds; second++) {
        sleep(1);
        fprintf(stdout, "TICK second=%d contactCallbacks=%d pathCallbacks=%d\n",
                second + 1, gCallbackCount, gPathCallbackCount);
        fflush(stdout);
    }

    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        fprintf(stdout, "STOP_RC[%ld]=%d\n", (long)i, stop(dev));
    }
    fflush(stdout);
    return 0;
}

static int run_other_mode(void *handle, int durationSeconds, const char *mode) {
    MTRegisterButtonStateCallbackFn registerButtonCallback =
        (MTRegisterButtonStateCallbackFn)dlsym(handle, "MTRegisterButtonStateCallback");
    MTRegisterImageCallbackFn registerImageCallback =
        (MTRegisterImageCallbackFn)dlsym(handle, "MTRegisterImageCallback");
    MTRegisterBlobFrameCallbackFn registerBlobCallback =
        (MTRegisterBlobFrameCallbackFn)dlsym(handle, "MTRegisterBlobFrameCallback");
    MTDeviceStartFn start = (MTDeviceStartFn)dlsym(handle, "MTDeviceStart");
    MTDeviceStopFn stop = (MTDeviceStopFn)dlsym(handle, "MTDeviceStop");
    MTDeviceIsBuiltInFn isBuiltIn = (MTDeviceIsBuiltInFn)dlsym(handle, "MTDeviceIsBuiltIn");

    if (!start || !stop) {
        fprintf(stderr, "missing start/stop symbols\n");
        return 3;
    }

    if ((strcmp(mode, "button") == 0 && !registerButtonCallback)
        || (strcmp(mode, "image") == 0 && !registerImageCallback)
        || (strcmp(mode, "blob") == 0 && !registerBlobCallback)) {
        fprintf(stderr, "missing %s callback symbol\n", mode);
        return 3;
    }

    CFArrayRef devices = load_devices(handle, NULL);
    if (!devices) {
        return 4;
    }

    CFIndex count = CFArrayGetCount(devices);
    fprintf(stdout, "%s_MODE devices=%ld duration=%d\n", mode, (long)count, durationSeconds);

    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        fprintf(stdout, "REGISTER[%ld] ptr=%p builtIn=%d\n",
                (long)i, dev, isBuiltIn ? isBuiltIn(dev) : -1);

        if (strcmp(mode, "button") == 0) {
            registerButtonCallback(dev, button_callback);
        } else if (strcmp(mode, "image") == 0) {
            registerImageCallback(dev, image_callback);
        } else if (strcmp(mode, "blob") == 0) {
            registerBlobCallback(dev, blob_callback);
        }

        fprintf(stdout, "START_RC[%ld]=%d\n", (long)i, start(dev, 0));
    }
    fflush(stdout);

    for (int second = 0; second < durationSeconds; second++) {
        sleep(1);
        fprintf(stdout,
                "TICK second=%d buttonCallbacks=%d imageCallbacks=%d blobCallbacks=%d\n",
                second + 1,
                gButtonCallbackCount,
                gImageCallbackCount,
                gBlobCallbackCount);
        fflush(stdout);
    }

    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        fprintf(stdout, "STOP_RC[%ld]=%d\n", (long)i, stop(dev));
    }
    fflush(stdout);
    return 0;
}

static int run_startscan_mode(void *handle, int maxArg, bool useDefaultDevice) {
    MTDeviceCreateDefaultFn createDefault = (MTDeviceCreateDefaultFn)dlsym(handle, "MTDeviceCreateDefault");
    MTDeviceStartFn start = (MTDeviceStartFn)dlsym(handle, "MTDeviceStart");
    MTDeviceStopFn stop = (MTDeviceStopFn)dlsym(handle, "MTDeviceStop");
    MTDeviceIsBuiltInFn isBuiltIn = (MTDeviceIsBuiltInFn)dlsym(handle, "MTDeviceIsBuiltIn");

    if (!start || !stop) {
        fprintf(stderr, "missing start/stop symbols\n");
        return 3;
    }

    fprintf(stdout, "STARTSCAN maxArg=%d useDefault=%d\n", maxArg, useDefaultDevice ? 1 : 0);
    if (useDefaultDevice) {
        if (!createDefault) {
            fprintf(stderr, "missing MTDeviceCreateDefault\n");
            return 4;
        }
        MTDeviceRef dev = createDefault();
        fprintf(stdout, "DEFAULT ptr=%p builtIn=%d\n", dev, isBuiltIn ? isBuiltIn(dev) : -1);
        for (int arg = 0; arg <= maxArg; arg++) {
            int startRC = start(dev, arg);
            int stopRC = stop(dev);
            fprintf(stdout, "ARG[%d] start=%d stop=%d\n", arg, startRC, stopRC);
        }
        fflush(stdout);
        return 0;
    }

    CFArrayRef devices = load_devices(handle, NULL);
    if (!devices) {
        return 4;
    }
    CFIndex count = CFArrayGetCount(devices);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        fprintf(stdout, "DEVICE[%ld] ptr=%p builtIn=%d\n", (long)i, dev, isBuiltIn ? isBuiltIn(dev) : -1);
        for (int arg = 0; arg <= maxArg; arg++) {
            int startRC = start(dev, arg);
            int stopRC = stop(dev);
            fprintf(stdout, "  ARG[%d] start=%d stop=%d\n", arg, startRC, stopRC);
        }
    }
    fflush(stdout);
    return 0;
}

static int run_startscan_scheduled_mode(void *handle, int maxArg, bool useDefaultDevice) {
    MTDeviceCreateDefaultFn createDefault = (MTDeviceCreateDefaultFn)dlsym(handle, "MTDeviceCreateDefault");
    MTDeviceStartFn start = (MTDeviceStartFn)dlsym(handle, "MTDeviceStart");
    MTDeviceStopFn stop = (MTDeviceStopFn)dlsym(handle, "MTDeviceStop");
    MTDeviceIsBuiltInFn isBuiltIn = (MTDeviceIsBuiltInFn)dlsym(handle, "MTDeviceIsBuiltIn");
    MTDeviceScheduleOnRunLoopFn scheduleOnRunLoop =
        (MTDeviceScheduleOnRunLoopFn)dlsym(handle, "MTDeviceScheduleOnRunLoop");
    MTDeviceCreateMultitouchRunLoopSourceFn createRunLoopSource =
        (MTDeviceCreateMultitouchRunLoopSourceFn)dlsym(handle, "MTDeviceCreateMultitouchRunLoopSource");

    if (!start || !stop || !scheduleOnRunLoop || !createRunLoopSource) {
        fprintf(stderr, "missing scheduling symbols\n");
        return 3;
    }

    fprintf(stdout, "STARTSCAN_SCHEDULED maxArg=%d useDefault=%d\n", maxArg, useDefaultDevice ? 1 : 0);

    if (useDefaultDevice) {
        if (!createDefault) {
            fprintf(stderr, "missing MTDeviceCreateDefault\n");
            return 4;
        }
        MTDeviceRef dev = createDefault();
        fprintf(stdout, "DEFAULT ptr=%p builtIn=%d\n", dev, isBuiltIn ? isBuiltIn(dev) : -1);
        scheduleOnRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRunLoopSourceRef source = createRunLoopSource(dev);
        fprintf(stdout, "SOURCE %p\n", source);
        if (source) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        }
        for (int arg = 0; arg <= maxArg; arg++) {
            int startRC = start(dev, arg);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
            int stopRC = stop(dev);
            fprintf(stdout, "ARG[%d] start=%d stop=%d\n", arg, startRC, stopRC);
        }
        fflush(stdout);
        return 0;
    }

    CFArrayRef devices = load_devices(handle, NULL);
    if (!devices) {
        return 4;
    }
    CFIndex count = CFArrayGetCount(devices);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        fprintf(stdout, "DEVICE[%ld] ptr=%p builtIn=%d\n", (long)i, dev, isBuiltIn ? isBuiltIn(dev) : -1);
        scheduleOnRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRunLoopSourceRef source = createRunLoopSource(dev);
        fprintf(stdout, "  SOURCE %p\n", source);
        if (source) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        }
        for (int arg = 0; arg <= maxArg; arg++) {
            int startRC = start(dev, arg);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
            int stopRC = stop(dev);
            fprintf(stdout, "  ARG[%d] start=%d stop=%d\n", arg, startRC, stopRC);
        }
    }
    fflush(stdout);
    return 0;
}

static void print_device_state(
    MTDeviceRef dev,
    MTDeviceBoolFn isAlive,
    MTDeviceBoolFn isAvailable,
    MTDeviceBoolFn driverIsReady,
    MTDeviceBoolFn isRunning
) {
    fprintf(stdout,
            "STATE alive=%d available=%d driverReady=%d running=%d\n",
            isAlive ? isAlive(dev) : -1,
            isAvailable ? isAvailable(dev) : -1,
            driverIsReady ? driverIsReady(dev) : -1,
            isRunning ? isRunning(dev) : -1);
}

static int run_state_mode(void *handle) {
    MTDeviceCreateFromServiceFn createFromService = (MTDeviceCreateFromServiceFn)dlsym(handle, "MTDeviceCreateFromService");
    MTDeviceCreateFromDeviceIDFn createFromDeviceID = (MTDeviceCreateFromDeviceIDFn)dlsym(handle, "MTDeviceCreateFromDeviceID");
    MTDeviceIsBuiltInFn isBuiltIn = (MTDeviceIsBuiltInFn)dlsym(handle, "MTDeviceIsBuiltIn");
    MTDeviceBoolFn isAlive = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsAlive");
    MTDeviceBoolFn isAvailable = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsAvailable");
    MTDeviceBoolFn driverIsReady = (MTDeviceBoolFn)dlsym(handle, "MTDeviceDriverIsReady");
    MTDeviceBoolFn isRunning = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsRunning");
    MTDeviceGetDeviceIDFn getDeviceID = (MTDeviceGetDeviceIDFn)dlsym(handle, "MTDeviceGetDeviceID");
    MTDeviceGetServiceFn getService = (MTDeviceGetServiceFn)dlsym(handle, "MTDeviceGetService");
    CFArrayRef devices = load_devices(handle, NULL);
    if (!devices) {
        return 4;
    }
    CFIndex count = CFArrayGetCount(devices);
    fprintf(stdout, "STATE_MODE devices=%ld\n", (long)count);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        fprintf(stdout, "DEVICE[%ld] ptr=%p builtIn=%d ", (long)i, dev, isBuiltIn ? isBuiltIn(dev) : -1);
        print_device_state(dev, isAlive, isAvailable, driverIsReady, isRunning);
        if (getService && createFromService) {
            MTDeviceRef fromService = createFromService(getService(dev));
            fprintf(stdout, "  FROM_SERVICE[%ld] ptr=%p ", (long)i, fromService);
            print_device_state(fromService, isAlive, isAvailable, driverIsReady, isRunning);
        }
        if (getDeviceID && createFromDeviceID) {
            uint64_t deviceID = 0;
            if (getDeviceID(dev, &deviceID) == 0) {
                MTDeviceRef fromDeviceID = createFromDeviceID(deviceID);
                fprintf(stdout, "  FROM_DEVICE_ID[%ld] ptr=%p ", (long)i, fromDeviceID);
                print_device_state(fromDeviceID, isAlive, isAvailable, driverIsReady, isRunning);
            }
        }
    }
    return 0;
}

static int run_service_mode(void *handle, int maxArg) {
    MTDeviceCreateFromServiceFn createFromService = (MTDeviceCreateFromServiceFn)dlsym(handle, "MTDeviceCreateFromService");
    MTDeviceCreateFromDeviceIDFn createFromDeviceID = (MTDeviceCreateFromDeviceIDFn)dlsym(handle, "MTDeviceCreateFromDeviceID");
    MTDeviceGetServiceFn getService = (MTDeviceGetServiceFn)dlsym(handle, "MTDeviceGetService");
    MTDeviceGetDeviceIDFn getDeviceID = (MTDeviceGetDeviceIDFn)dlsym(handle, "MTDeviceGetDeviceID");
    MTDeviceStartFn start = (MTDeviceStartFn)dlsym(handle, "MTDeviceStart");
    MTDeviceStopFn stop = (MTDeviceStopFn)dlsym(handle, "MTDeviceStop");
    MTDeviceIsBuiltInFn isBuiltIn = (MTDeviceIsBuiltInFn)dlsym(handle, "MTDeviceIsBuiltIn");
    MTDeviceBoolFn isAlive = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsAlive");
    MTDeviceBoolFn isAvailable = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsAvailable");
    MTDeviceBoolFn driverIsReady = (MTDeviceBoolFn)dlsym(handle, "MTDeviceDriverIsReady");
    MTDeviceBoolFn isRunning = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsRunning");

    if (!createFromService || !createFromDeviceID || !getService || !getDeviceID || !start || !stop) {
        fprintf(stderr, "missing service recreation symbols\n");
        return 3;
    }

    CFArrayRef devices = load_devices(handle, NULL);
    if (!devices) {
        return 4;
    }
    CFIndex count = CFArrayGetCount(devices);
    fprintf(stdout, "SERVICE_MODE devices=%ld maxArg=%d\n", (long)count, maxArg);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        uint64_t deviceID = 0;
        getDeviceID(dev, &deviceID);
        CFTypeRef service = getService(dev);
        MTDeviceRef fromService = createFromService(service);
        MTDeviceRef fromDeviceID = createFromDeviceID(deviceID);

        fprintf(stdout, "DEVICE[%ld] original=%p builtIn=%d service=%p deviceID=%llu ", (long)i, dev, isBuiltIn ? isBuiltIn(dev) : -1, service, (unsigned long long)deviceID);
        print_device_state(dev, isAlive, isAvailable, driverIsReady, isRunning);
        fprintf(stdout, "  RECREATE_SERVICE[%ld] ptr=%p ", (long)i, fromService);
        print_device_state(fromService, isAlive, isAvailable, driverIsReady, isRunning);
        fprintf(stdout, "  RECREATE_DEVICE_ID[%ld] ptr=%p ", (long)i, fromDeviceID);
        print_device_state(fromDeviceID, isAlive, isAvailable, driverIsReady, isRunning);

        for (int arg = 0; arg <= maxArg; arg++) {
            fprintf(stdout, "    START_ORIGINAL arg=%d rc=%d stop=%d\n", arg, start(dev, arg), stop(dev));
            fprintf(stdout, "    START_SERVICE arg=%d rc=%d stop=%d\n", arg, start(fromService, arg), stop(fromService));
            fprintf(stdout, "    START_DEVICE_ID arg=%d rc=%d stop=%d\n", arg, start(fromDeviceID, arg), stop(fromDeviceID));
        }
    }
    fflush(stdout);
    return 0;
}

static int run_advanced_mode(void *handle, int durationSeconds, const char *mode) {
    MTRegisterFullFrameCallbackFn registerFullFrame =
        (MTRegisterFullFrameCallbackFn)dlsym(handle, "MTRegisterFullFrameCallback");
    MTRegisterFrameHeaderCallbackFn registerFrameHeader =
        (MTRegisterFrameHeaderCallbackFn)dlsym(handle, "MTRegisterFrameHeaderCallback");
    MTRegisterInputDetectionCallbackFn registerInputDetection =
        (MTRegisterInputDetectionCallbackFn)dlsym(handle, "MTRegisterInputDetectionCallback");
    MTDeviceScheduleOnRunLoopFn scheduleOnRunLoop =
        (MTDeviceScheduleOnRunLoopFn)dlsym(handle, "MTDeviceScheduleOnRunLoop");
    MTDeviceCreateMultitouchRunLoopSourceFn createRunLoopSource =
        (MTDeviceCreateMultitouchRunLoopSourceFn)dlsym(handle, "MTDeviceCreateMultitouchRunLoopSource");
    MTDeviceSetInputDetectionModeFn setInputDetectionMode =
        (MTDeviceSetInputDetectionModeFn)dlsym(handle, "MTDeviceSetInputDetectionMode");
    MTDeviceSetTouchModeFn setTouchMode =
        (MTDeviceSetTouchModeFn)dlsym(handle, "MTDeviceSetTouchMode");
    MTDeviceSetSurfaceOrientationFn setSurfaceOrientation =
        (MTDeviceSetSurfaceOrientationFn)dlsym(handle, "MTDeviceSetSurfaceOrientation");
    MTDeviceBoolFn isAlive = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsAlive");
    MTDeviceBoolFn isAvailable = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsAvailable");
    MTDeviceBoolFn driverIsReady = (MTDeviceBoolFn)dlsym(handle, "MTDeviceDriverIsReady");
    MTDeviceBoolFn isRunning = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsRunning");
    MTDeviceStartFn start = (MTDeviceStartFn)dlsym(handle, "MTDeviceStart");
    MTDeviceStopFn stop = (MTDeviceStopFn)dlsym(handle, "MTDeviceStop");
    MTDeviceIsBuiltInFn isBuiltIn = (MTDeviceIsBuiltInFn)dlsym(handle, "MTDeviceIsBuiltIn");

    if (!start || !stop || !scheduleOnRunLoop || !createRunLoopSource) {
        fprintf(stderr, "missing advanced symbols\n");
        return 3;
    }

    CFArrayRef devices = load_devices(handle, NULL);
    if (!devices) {
        return 4;
    }

    CFIndex count = CFArrayGetCount(devices);
    fprintf(stdout, "%s_MODE devices=%ld duration=%d\n", mode, (long)count, durationSeconds);

    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        fprintf(stdout, "REGISTER[%ld] ptr=%p builtIn=%d ", (long)i, dev, isBuiltIn ? isBuiltIn(dev) : -1);
        print_device_state(dev, isAlive, isAvailable, driverIsReady, isRunning);

        scheduleOnRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRunLoopSourceRef source = createRunLoopSource(dev);
        fprintf(stdout, "SOURCE[%ld]=%p\n", (long)i, source);
        if (source) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        }

        if (setInputDetectionMode) {
            fprintf(stdout, "SET_INPUT_DETECTION[%ld]=%d\n", (long)i, setInputDetectionMode(dev, 1));
        }
        if (setTouchMode) {
            fprintf(stdout, "SET_TOUCH_MODE[%ld]=%d\n", (long)i, setTouchMode(dev, 1));
        }
        if (setSurfaceOrientation) {
            fprintf(stdout, "SET_SURFACE_ORIENTATION[%ld]=%d\n", (long)i, setSurfaceOrientation(dev, 0));
        }

        if (strcmp(mode, "fullframe") == 0 && registerFullFrame) {
            registerFullFrame(dev, full_frame_callback);
        } else if (strcmp(mode, "frameheader") == 0 && registerFrameHeader) {
            registerFrameHeader(dev, frame_header_callback);
        } else if (strcmp(mode, "inputdetect") == 0 && registerInputDetection) {
            registerInputDetection(dev, input_detection_callback);
        }

        fprintf(stdout, "START_RC[%ld]=%d\n", (long)i, start(dev, 0));
    }
    fflush(stdout);

    for (int second = 0; second < durationSeconds; second++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
        fprintf(stdout,
                "TICK second=%d fullFrame=%d frameHeader=%d inputDetect=%d\n",
                second + 1,
                gFullFrameCallbackCount,
                gFrameHeaderCallbackCount,
                gInputDetectionCallbackCount);
        fflush(stdout);
    }

    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        fprintf(stdout, "STOP_RC[%ld]=%d\n", (long)i, stop(dev));
    }
    fflush(stdout);
    return 0;
}

int main(int argc, char **argv) {
    void *handle = load_framework();
    if (!handle) {
        return 1;
    }

    const char *mode = argc > 1 ? argv[1] : "info";
    if (strcmp(mode, "info") == 0) {
        return run_info_mode(handle);
    }

    if (strcmp(mode, "contact") == 0) {
        int duration = 10;
        if (argc > 2) {
            duration = atoi(argv[2]);
            if (duration <= 0) {
                duration = 10;
            }
        }
        return run_contact_mode(handle, duration, false);
    }

    if (strcmp(mode, "path") == 0) {
        int duration = 10;
        if (argc > 2) {
            duration = atoi(argv[2]);
            if (duration <= 0) {
                duration = 10;
            }
        }
        return run_contact_mode(handle, duration, true);
    }

    if (strcmp(mode, "button") == 0 || strcmp(mode, "image") == 0 || strcmp(mode, "blob") == 0) {
        int duration = 10;
        if (argc > 2) {
            duration = atoi(argv[2]);
            if (duration <= 0) {
                duration = 10;
            }
        }
        return run_other_mode(handle, duration, mode);
    }

    if (strcmp(mode, "startscan") == 0 || strcmp(mode, "startscan-default") == 0) {
        int maxArg = 8;
        if (argc > 2) {
            maxArg = atoi(argv[2]);
            if (maxArg < 0) {
                maxArg = 8;
            }
        }
        return run_startscan_mode(handle, maxArg, strcmp(mode, "startscan-default") == 0);
    }

    if (strcmp(mode, "startscan-scheduled") == 0 || strcmp(mode, "startscan-scheduled-default") == 0) {
        int maxArg = 8;
        if (argc > 2) {
            maxArg = atoi(argv[2]);
            if (maxArg < 0) {
                maxArg = 8;
            }
        }
        return run_startscan_scheduled_mode(handle, maxArg, strcmp(mode, "startscan-scheduled-default") == 0);
    }

    if (strcmp(mode, "state") == 0) {
        return run_state_mode(handle);
    }

    if (strcmp(mode, "service") == 0) {
        int maxArg = 4;
        if (argc > 2) {
            maxArg = atoi(argv[2]);
            if (maxArg < 0) {
                maxArg = 4;
            }
        }
        return run_service_mode(handle, maxArg);
    }

    if (strcmp(mode, "fullframe") == 0 || strcmp(mode, "frameheader") == 0 || strcmp(mode, "inputdetect") == 0) {
        int duration = 10;
        if (argc > 2) {
            duration = atoi(argv[2]);
            if (duration <= 0) {
                duration = 10;
            }
        }
        return run_advanced_mode(handle, duration, mode);
    }

    fprintf(stderr, "usage: mt_rotation_probe [info|state|service|contact|path|button|image|blob|fullframe|frameheader|inputdetect|startscan|startscan-default|startscan-scheduled|startscan-scheduled-default] [seconds/maxArg]\n");
    return 64;
}
