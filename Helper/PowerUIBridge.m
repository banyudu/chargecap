#import "PowerUIBridge.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

// PowerUI.framework is private and has no public headers. The class below only
// mirrors the methods ChargeCap calls; it is resolved at runtime with
// NSClassFromString so the helper neither links against nor ships Apple's
// framework.
@interface PowerUISmartChargeClient : NSObject
- (instancetype)initWithClientName:(NSString *)clientName;
- (BOOL)isMCLSupported;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)error;
- (NSArray<NSNumber *> *)availableChargeLimitsWithError:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
@end

static PowerUISmartChargeClient *gClient = nil;
static BOOL gClientLoaded = NO;

static void setError(char **error, NSString *message) {
    if (error == NULL) {
        return;
    }
    NSString *text = message.length > 0 ? message : @"Unknown PowerUI error";
    *error = strdup(text.UTF8String);
}

static void setNSError(char **error, NSError *failure, NSString *fallback) {
    if (failure != nil && failure.localizedDescription.length > 0) {
        setError(error, failure.localizedDescription);
    } else {
        setError(error, fallback);
    }
}

static BOOL loadFramework(void) {
    static const char *candidates[] = {
        "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI",
        "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/Current/PowerUI",
        "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI",
    };

    for (size_t index = 0; index < sizeof(candidates) / sizeof(candidates[0]); index++) {
        if (dlopen(candidates[index], RTLD_NOW | RTLD_LOCAL) != NULL) {
            return YES;
        }
    }
    return NO;
}

static PowerUISmartChargeClient *client(void) {
    if (gClientLoaded) {
        return gClient;
    }
    gClientLoaded = YES;

    if (!loadFramework()) {
        return nil;
    }

    Class clientClass = NSClassFromString(@"PowerUISmartChargeClient");
    if (clientClass == Nil) {
        return nil;
    }

    id instance = [[clientClass alloc] initWithClientName:@"ChargeCap"];
    if (instance == nil) {
        return nil;
    }

    const char *selectors[] = {
        "isMCLSupported",
        "getMCLLimitWithError:",
        "setMCLLimit:error:",
        "isMCLCurrentlyEnabled:",
        "availableChargeLimitsWithError:",
        "disableMCL:",
    };
    for (size_t index = 0; index < sizeof(selectors) / sizeof(selectors[0]); index++) {
        if (![instance respondsToSelector:sel_registerName(selectors[index])]) {
            return nil;
        }
    }

    gClient = instance;
    return gClient;
}

int chargecap_powerui_is_supported(void) {
    @autoreleasepool {
        PowerUISmartChargeClient *instance = client();
        if (instance == nil) {
            return 0;
        }
        return [instance isMCLSupported] ? 1 : 0;
    }
}

int chargecap_powerui_copy_limits(int *limits, int capacity, int *count, char **error) {
    @autoreleasepool {
        PowerUISmartChargeClient *instance = client();
        if (instance == nil) {
            setError(error, @"PowerUI charge-limit client is unavailable");
            return -1;
        }
        if (limits == NULL || capacity <= 0 || count == NULL) {
            setError(error, @"Invalid output buffer");
            return -1;
        }

        NSError *failure = nil;
        NSArray<NSNumber *> *values = [instance availableChargeLimitsWithError:&failure];
        if (values == nil || ![values isKindOfClass:[NSArray class]]) {
            setNSError(error, failure, @"PowerUI did not return charge limits");
            return -1;
        }

        int written = 0;
        for (id value in values) {
            if (written >= capacity) {
                break;
            }
            if ([value respondsToSelector:@selector(intValue)]) {
                limits[written++] = [value intValue];
            }
        }
        *count = written;
        return 0;
    }
}

int chargecap_powerui_read_limit(int *limit, int *enabled, char **error) {
    @autoreleasepool {
        PowerUISmartChargeClient *instance = client();
        if (instance == nil) {
            setError(error, @"PowerUI charge-limit client is unavailable");
            return -1;
        }
        if (limit == NULL || enabled == NULL) {
            setError(error, @"Invalid output pointer");
            return -1;
        }

        NSError *failure = nil;
        unsigned char value = [instance getMCLLimitWithError:&failure];
        if (failure != nil) {
            setNSError(error, failure, @"Could not read the macOS charge limit");
            return -1;
        }

        failure = nil;
        unsigned long long active = [instance isMCLCurrentlyEnabled:&failure];
        if (failure != nil) {
            setNSError(error, failure, @"Could not read the macOS charge-limit state");
            return -1;
        }

        *limit = (int)value;
        *enabled = active != 0 ? 1 : 0;
        return 0;
    }
}

int chargecap_powerui_set_limit(int limit, char **error) {
    @autoreleasepool {
        PowerUISmartChargeClient *instance = client();
        if (instance == nil) {
            setError(error, @"PowerUI charge-limit client is unavailable");
            return -1;
        }
        if (limit < 0 || limit > 100) {
            setError(error, @"Charge limit must be between 0 and 100");
            return -1;
        }

        NSError *failure = nil;
        BOOL success = [instance setMCLLimit:(unsigned char)limit error:&failure];
        if (!success) {
            setNSError(error, failure, @"PowerUI rejected the charge limit");
            return -1;
        }
        return 0;
    }
}

int chargecap_powerui_disable(char **error) {
    @autoreleasepool {
        PowerUISmartChargeClient *instance = client();
        if (instance == nil) {
            setError(error, @"PowerUI charge-limit client is unavailable");
            return -1;
        }

        NSError *failure = nil;
        BOOL success = [instance disableMCL:&failure];
        if (!success) {
            setNSError(error, failure, @"PowerUI could not disable the charge limit");
            return -1;
        }
        return 0;
    }
}

void chargecap_powerui_free_error(char *error) {
    if (error != NULL) {
        free(error);
    }
}
