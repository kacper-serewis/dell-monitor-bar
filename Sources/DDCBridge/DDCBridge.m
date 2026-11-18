#import "DDCBridge.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#include <unistd.h>

// Private Apple Silicon APIs, also used by m1ddc / MonitorControl.
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display);
extern CFTypeRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceWriteI2C(CFTypeRef service, uint32_t chip, uint32_t offset, void *data, uint32_t count);
extern IOReturn IOAVServiceReadI2C(CFTypeRef service, uint32_t chip, uint32_t offset, void *data, uint32_t count);

@interface DMBDisplay () {
    CFTypeRef _service;
    uint32_t _chip;
}
@property(nonatomic, readwrite) NSString *identifier;
@property(nonatomic, readwrite) NSString *name;
@property(nonatomic, readwrite) uint32_t displayID;
- (instancetype)initWithService:(CFTypeRef)service chip:(uint32_t)chip;
@end

@implementation DMBDisplay
- (instancetype)initWithService:(CFTypeRef)service chip:(uint32_t)chip {
    if ((self = [super init])) { _service = CFRetain(service); _chip = chip; }
    return self;
}
- (void)dealloc { if (_service) CFRelease(_service); }
- (NSData *)exchange:(NSData *)frame replyLength:(NSUInteger)length error:(NSError **)error {
    if (frame.length == 0 || frame.length > 128 || length > 128) {
        if (error) *error = [NSError errorWithDomain:@"DellMonitorBar" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid DDC packet size."}];
        return nil;
    }
    IOReturn status = kIOReturnSuccess;
    // Duplicate read requests only. An action such as KVM must never be retried.
    for (NSUInteger i = 0; i < (length ? 2 : 1); i++) {
        usleep(60000);
        status = IOAVServiceWriteI2C(_service, _chip, 0x51, (void *)frame.bytes, (uint32_t)frame.length);
        if (status != kIOReturnSuccess) break;
    }
    NSMutableData *reply = [NSMutableData dataWithLength:length];
    if (status == kIOReturnSuccess && length) {
        usleep(60000);
        status = IOAVServiceReadI2C(_service, _chip, 0x51, reply.mutableBytes, (uint32_t)length);
    }
    if (status != kIOReturnSuccess) {
        if (error) *error = [NSError errorWithDomain:@"DellMonitorBar.IOKit" code:status userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Monitor connection unavailable (0x%08x). Refresh after reconnecting.", status]
        }];
        return nil;
    }
    return reply;
}
@end

static id Search(io_registry_entry_t entry, CFStringRef key) {
    return CFBridgingRelease(IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key,
                             kCFAllocatorDefault, kIORegistryIterateRecursively));
}

// CoreDisplay identifies a framebuffer under e.g. "dispext1". The external
// DCP proxy's EPIC provider is named "dispext1:dcpav-service-epic:0". Match that
// exact port identity rather than depending on traversal order in the registry.
static DMBDisplay *Connect(io_registry_entry_t adapter) {
    io_registry_entry_t framebufferParent = IO_OBJECT_NULL;
    if (IORegistryEntryGetParentEntry(adapter, kIOServicePlane, &framebufferParent) != KERN_SUCCESS) return nil;
    io_name_t framebufferName = {0};
    kern_return_t named = IORegistryEntryGetName(framebufferParent, framebufferName);
    IOObjectRelease(framebufferParent);
    if (named != KERN_SUCCESS) return nil;
    NSString *port = [NSString stringWithUTF8String:framebufferName];
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) != KERN_SUCCESS) return nil;
    DMBDisplay *display = nil;
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        io_registry_entry_t parent = IO_OBJECT_NULL;
        if ([Search(entry, CFSTR("Location")) isEqual:@"External"] &&
            IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS) {
            io_name_t providerName = {0};
            if (IORegistryEntryGetName(parent, providerName) == KERN_SUCCESS) {
                NSString *providerPort = [[NSString stringWithUTF8String:providerName] componentsSeparatedByString:@":"].firstObject;
                if ([providerPort isEqual:port]) {
                    CFTypeRef service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry);
                    if (service) {
                        id provider = CFBridgingRelease(IORegistryEntryCreateCFProperty(parent, CFSTR("EPICProviderClass"), kCFAllocatorDefault, 0));
                        uint32_t chip = [provider isEqual:@"AppleDCPMCDP29XX"] ? 0xB7 : 0x37;
                        display = [[DMBDisplay alloc] initWithService:service chip:chip];
                        CFRelease(service);
                    }
                }
            }
            IOObjectRelease(parent);
        }
        IOObjectRelease(entry);
        if (display) break;
    }
    IOObjectRelease(iterator);
    return display;
}

NSArray<DMBDisplay *> *DMBDiscoverDisplays(void) {
    @autoreleasepool {
        NSMutableArray<DMBDisplay *> *displays = [NSMutableArray array];
        CGDirectDisplayID ids[32];
        CGDisplayCount count = 0;
        if (CGGetOnlineDisplayList(32, ids, &count) != kCGErrorSuccess) return displays;
        for (CGDisplayCount i = 0; i < count; i++) {
            // This app intentionally supports Dell hardware only.
            if (CGDisplayIsBuiltin(ids[i]) || CGDisplayVendorNumber(ids[i]) != 0x10AC) continue;
            NSDictionary *info = CFBridgingRelease(CoreDisplay_DisplayCreateInfoDictionary(ids[i]));
            NSString *location = info[@"IODisplayLocation"];
            NSString *uuid = info[@"kCGDisplayUUID"];
            if (![location isKindOfClass:NSString.class] || ![uuid isKindOfClass:NSString.class]) continue;
            io_registry_entry_t adapter = IORegistryEntryCopyFromPath(kIOMainPortDefault, (__bridge CFStringRef)location);
            if (!adapter) continue;
            NSDictionary *attributes = Search(adapter, CFSTR("DisplayAttributes"));
            DMBDisplay *display = Connect(adapter);
            IOObjectRelease(adapter);
            if (!display) continue;
            display.identifier = uuid;
            display.displayID = ids[i];
            display.name = attributes[@"ProductAttributes"][@"ProductName"] ?: @"Dell display";
            [displays addObject:display];
        }
        return displays;
    }
}
