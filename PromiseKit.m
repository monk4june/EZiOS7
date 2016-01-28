#import "PromiseKit.h"
#import <Foundation/NSMethodSignature.h>

struct PMKBlockLiteral {
    void *isa; // initialized to &_NSConcreteStackBlock or &_NSConcreteGlobalBlock
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct block_descriptor {
        unsigned long int reserved;	// NULL
    	unsigned long int size;         // sizeof(struct Block_literal_1)
        // optional helper functions
    	void (*copy_helper)(void *dst, void *src);     // IFF (1<<25)
    	void (*dispose_helper)(void *src);             // IFF (1<<25)
        // required ABI.2010.3.16
        const char *signature;                         // IFF (1<<30)
    } *descriptor;
    // imported variables
};

typedef NS_OPTIONS(NSUInteger, PMKBlockDescriptionFlags) {
    PMKBlockDescriptionFlagsHasCopyDispose = (1 << 25),
    PMKBlockDescriptionFlagsHasCtor = (1 << 26), // helpers have C++ code
    PMKBlockDescriptionFlagsIsGlobal = (1 << 28),
    PMKBlockDescriptionFlagsHasStret = (1 << 29), // IFF BLOCK_HAS_SIGNATURE
    PMKBlockDescriptionFlagsHasSignature = (1 << 30)
};

// It appears 10.7 doesn't support quotes in method signatures. Remove them
// via @rabovik's method. See https://github.com/OliverLetterer/SLObjectiveCRuntimeAdditions/pull/2
#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_8
NS_INLINE static const char * pmk_removeQuotesFromMethodSignature(const char *str){
    char *result = malloc(strlen(str) + 1);
    BOOL skip = NO;
    char *to = result;
    char c;
    while ((c = *str++)) {
        if ('"' == c) {
            skip = !skip;
            continue;
        }
        if (skip) continue;
        *to++ = c;
    }
    *to = '\0';
    return result;
}
#endif

static NSMethodSignature *NSMethodSignatureForBlock(id block) {
    if (!block)
        return nil;

    struct PMKBlockLiteral *blockRef = (__bridge struct PMKBlockLiteral *)block;
    PMKBlockDescriptionFlags flags = (PMKBlockDescriptionFlags)blockRef->flags;

    if (flags & PMKBlockDescriptionFlagsHasSignature) {
        void *signatureLocation = blockRef->descriptor;
        signatureLocation += sizeof(unsigned long int);
        signatureLocation += sizeof(unsigned long int);

        if (flags & PMKBlockDescriptionFlagsHasCopyDispose) {
            signatureLocation += sizeof(void(*)(void *dst, void *src));
            signatureLocation += sizeof(void (*)(void *src));
        }

        const char *signature = (*(const char **)signatureLocation);
#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_8
        signature = pmk_removeQuotesFromMethodSignature(signature);
        NSMethodSignature *nsSignature = [NSMethodSignature signatureWithObjCTypes:signature];
        free((void *)signature);

        return nsSignature;
#endif
        return [NSMethodSignature signatureWithObjCTypes:signature];
    }
    return 0;
}
#import <dispatch/once.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSException.h>
#import <string.h>

#ifndef PMKLog
#define PMKLog NSLog
#endif

@interface PMKArray : NSObject {
@public
    id objs[3];
    NSUInteger count;
} @end

@implementation PMKArray

- (id)objectAtIndexedSubscript:(NSUInteger)idx {
    if (count <= idx) {
        // this check is necessary due to lack of checks in `pmk_safely_call_block`
        return nil;
    }
    return objs[idx];
}

@end

id __PMKArrayWithCount(NSUInteger count, ...) {
    PMKArray *this = [PMKArray new];
    this->count = count;
    va_list args;
    va_start(args, count);
    for (NSUInteger x = 0; x < count; ++x)
        this->objs[x] = va_arg(args, id);
    va_end(args);
    return this;
}


static inline id _PMKCallVariadicBlock(id frock, id result) {
    NSCAssert(frock, @"");

    NSMethodSignature *sig = NSMethodSignatureForBlock(frock);
    const NSUInteger nargs = sig.numberOfArguments;
    const char rtype = sig.methodReturnType[0];

    #define call_block_with_rtype(type) ({^type{ \
        switch (nargs) { \
            case 1: \
                return ((type(^)(void))frock)(); \
            case 2: { \
                const id arg = [result class] == [PMKArray class] ? result[0] : result; \
                return ((type(^)(id))frock)(arg); \
            } \
            case 3: { \
                type (^block)(id, id) = frock; \
                return [result class] == [PMKArray class] \
                    ? block(result[0], result[1]) \
                    : block(result, nil); \
            } \
            case 4: { \
                type (^block)(id, id, id) = frock; \
                return [result class] == [PMKArray class] \
                    ? block(result[0], result[1], result[2]) \
                    : block(result, nil, nil); \
            } \
            default: \
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"PromiseKit: The provided block’s argument count is unsupported." userInfo:nil]; \
        }}();})

    switch (rtype) {
        case 'v':
            call_block_with_rtype(void);
            return nil;
        case '@':
            return call_block_with_rtype(id) ?: nil;
        case '*': {
            char *str = call_block_with_rtype(char *);
            return str ? @(str) : nil;
        }
        case 'c': return @(call_block_with_rtype(char));
        case 'i': return @(call_block_with_rtype(int));
        case 's': return @(call_block_with_rtype(short));
        case 'l': return @(call_block_with_rtype(long));
        case 'q': return @(call_block_with_rtype(long long));
        case 'C': return @(call_block_with_rtype(unsigned char));
        case 'I': return @(call_block_with_rtype(unsigned int));
        case 'S': return @(call_block_with_rtype(unsigned short));
        case 'L': return @(call_block_with_rtype(unsigned long));
        case 'Q': return @(call_block_with_rtype(unsigned long long));
        case 'f': return @(call_block_with_rtype(float));
        case 'd': return @(call_block_with_rtype(double));
        case 'B': return @(call_block_with_rtype(_Bool));
        case '^':
            if (strcmp(sig.methodReturnType, "^v") == 0) {
                call_block_with_rtype(void);
                return nil;
            }
            // else fall through!
        default:
            @throw [NSException exceptionWithName:@"PromiseKit" reason:@"PromiseKit: Unsupported method signature." userInfo:nil];
    }
}

static id PMKCallVariadicBlock(id frock, id result) {
    @try {
        return _PMKCallVariadicBlock(frock, result);
    } @catch (id thrown) {
        return PMKProcessUnhandledException(thrown);
    }
}


static dispatch_once_t onceToken;
static NSError *(^PMKUnhandledExceptionHandler)(id);

NSError *PMKProcessUnhandledException(id thrown) {

    dispatch_once(&onceToken, ^{
        PMKUnhandledExceptionHandler = ^id(id reason){
            if ([reason isKindOfClass:[NSError class]])
                return reason;
            if ([reason isKindOfClass:[NSString class]])
                return [NSError errorWithDomain:PMKErrorDomain code:PMKUnexpectedError userInfo:@{NSLocalizedDescriptionKey: reason}];
            return nil;
        };
    });

    id err = PMKUnhandledExceptionHandler(thrown);
    if (!err) {
        NSLog(@"PromiseKit no longer catches *all* exceptions. However you can change this behavior by setting a new PMKProcessUnhandledException handler.");
        @throw thrown;
    }
    return err;
}

void PMKSetUnhandledExceptionHandler(NSError *(^newHandler)(id)) {
    dispatch_once(&onceToken, ^{
        PMKUnhandledExceptionHandler = newHandler;
    });
}
@import Dispatch;
#import <Foundation/NSDate.h>
#import <Foundation/NSValue.h>

AnyPromise *PMKAfter(NSTimeInterval duration) {
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC));
        dispatch_after(time, dispatch_get_global_queue(0, 0), ^{
            resolve(@(duration));
        });
    }];
}
#import <Foundation/NSKeyValueCoding.h>

NSString *const PMKErrorDomain = @"PMKErrorDomain";


@implementation AnyPromise (objc)

- (instancetype)initWithResolver:(PMKResolver __strong *)resolver {
    return [self initWithBridge:^(PMKResolver resolve){
        *resolver = resolve;
    }];
}

+ (instancetype)promiseWithResolverBlock:(void (^)(PMKResolver))resolveBlock {
    return [[self alloc] initWithBridge:resolveBlock];
}

+ (instancetype)promiseWithValue:(id)value {
    return [[self alloc] initWithBridge:^(PMKResolver resolve){
        resolve(value);
    }];
}

static inline AnyPromise *AnyPromiseWhen(AnyPromise *when, void(^then)(id, PMKResolver)) {
    return [[AnyPromise alloc] initWithBridge:^(PMKResolver resolve){
        [when pipe:^(id obj){
            then(obj, resolve);
        }];
    }];
}

static inline AnyPromise *__then(AnyPromise *self, dispatch_queue_t queue, id block) {
    return AnyPromiseWhen(self, ^(id obj, PMKResolver resolve) {
        if (IsError(obj)) {
            resolve(obj);
        } else dispatch_async(queue, ^{
            resolve(PMKCallVariadicBlock(block, obj));
        });
    });
}

- (AnyPromise *(^)(id))then {
    return ^(id block) {
        return __then(self, dispatch_get_main_queue(), block);
    };
}

- (AnyPromise *(^)(dispatch_queue_t, id))thenOn {
    return ^(dispatch_queue_t queue, id block) {
        return __then(self, queue, block);
    };
}

- (AnyPromise *(^)(id))thenInBackground {
    return ^(id block) {
        return __then(self, dispatch_get_global_queue(0, 0), block);
    };
}

static inline AnyPromise *__catch(AnyPromise *self, BOOL includeCancellation, id block) {
    return AnyPromiseWhen(self, ^(id obj, PMKResolver resolve) {
        if (IsError(obj) && (includeCancellation || ![obj cancelled])) {
            [obj pmk_consume];
            dispatch_async(dispatch_get_main_queue(), ^{
                resolve(PMKCallVariadicBlock(block, obj));
            });
        } else {
            resolve(obj);
        }
    });
}

- (AnyPromise *(^)(id))catch {
    return ^(id block) {
        return __catch(self, NO, block);
    };
}

- (AnyPromise *(^)(PMKCatchPolicy, id))catchWithPolicy {
    return ^(PMKCatchPolicy policy, id block) {
        return __catch(self, policy == PMKCatchPolicyAllErrors, block);
    };
}

static inline AnyPromise *__finally(AnyPromise *self, dispatch_queue_t queue, dispatch_block_t block) {
    return AnyPromiseWhen(self, ^(id obj, PMKResolver resolve) {
        dispatch_async(queue, ^{
            block();
            resolve(obj);
        });
    });
}

- (AnyPromise *(^)(dispatch_block_t))finally {
    return ^(dispatch_block_t block) {
        return __finally(self, dispatch_get_main_queue(), block);
    };
}

- (AnyPromise *(^)(dispatch_queue_t, dispatch_block_t))finallyOn {
    return ^(dispatch_queue_t queue, dispatch_block_t block) {
        return __finally(self, queue, block);
    };
}

- (id)value {
    id result = [self valueForKey:@"__value"];
    return [result isKindOfClass:[PMKArray class]]
        ? result[0]
        : result;
}

@end



@implementation AnyPromise (Adapters)

+ (instancetype)promiseWithAdapterBlock:(void (^)(PMKAdapter))block {
    return [self promiseWithResolverBlock:^(PMKResolver resolve) {
        block(^(id value, id error){
            resolve(error ?: value);
        });
    }];
}

+ (instancetype)promiseWithIntegerAdapterBlock:(void (^)(PMKIntegerAdapter))block {
    return [self promiseWithResolverBlock:^(PMKResolver resolve) {
        block(^(NSInteger value, id error){
            if (error) {
                resolve(error);
            } else {
                resolve(@(value));
            }
        });
    }];
}

+ (instancetype)promiseWithBooleanAdapterBlock:(void (^)(PMKBooleanAdapter adapter))block {
    return [self promiseWithResolverBlock:^(PMKResolver resolve) {
        block(^(BOOL value, id error){
            if (error) {
                resolve(error);
            } else {
                resolve(@(value));
            }
        });
    }];
}

@end
@import Dispatch;

AnyPromise *dispatch_promise(id block) {
    return dispatch_promise_on(dispatch_get_global_queue(0, 0), block);
}

AnyPromise *dispatch_promise_on(dispatch_queue_t queue, id block) {
    return [AnyPromise promiseWithValue:nil].thenOn(queue, block);
}
#import <CoreFoundation/CFRunLoop.h>

id PMKHang(AnyPromise *promise) {
    if (promise.pending) {
        static CFRunLoopSourceContext context;

        CFRunLoopRef runLoop = CFRunLoopGetCurrent();
        CFRunLoopSourceRef runLoopSource = CFRunLoopSourceCreate(NULL, 0, &context);
        CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);

        promise.finally(^{
            CFRunLoopStop(runLoop);
        });
        while (promise.pending) {
            CFRunLoopRun();
        }
        CFRunLoopRemoveSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);
        CFRelease(runLoopSource);
    }

    return promise.value;
}
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSNull.h>
#import <libkern/OSAtomic.h>

@implementation AnyPromise (join)

AnyPromise *PMKJoin(NSArray *promises) {
    if (promises == nil)
        return [AnyPromise promiseWithValue:[NSError errorWithDomain:PMKErrorDomain code:PMKInvalidUsageError userInfo:@{NSLocalizedDescriptionKey: @"PMKJoin(nil)"}]];

    if (promises.count == 0)
        return [AnyPromise promiseWithValue:promises];

    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        NSPointerArray *results = NSPointerArrayMake(promises.count);
        __block int32_t countdown = (int32_t)promises.count;
        __block BOOL rejected = NO;

        [promises enumerateObjectsUsingBlock:^(AnyPromise *promise, NSUInteger ii, BOOL *stop) {
            [promise pipe:^(id value) {

                if (IsError(value)) {
                    [value pmk_consume];
                    rejected = YES;
                }

                [results replacePointerAtIndex:ii withPointer:(__bridge void *)(value ?: [NSNull null])];

                if (OSAtomicDecrement32(&countdown) == 0) {
                    if (!rejected) {
                        resolve(results.allObjects);
                    } else {
                        id userInfo = @{PMKJoinPromisesKey: promises};
                        id err = [NSError errorWithDomain:PMKErrorDomain code:PMKJoinError userInfo:userInfo];
                        resolve(err);
                    }
                }
            }];
        }];
    }];
}

@end
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSProgress.h>
#import <Foundation/NSNull.h>
#import <libkern/OSAtomic.h>

// NSProgress resources:
//  * https://robots.thoughtbot.com/asynchronous-nsprogress
//  * http://oleb.net/blog/2014/03/nsprogress/
// NSProgress! Beware!
//  * https://github.com/AFNetworking/AFNetworking/issues/2261

AnyPromise *PMKWhen(id promises) {
    if (promises == nil)
        return [AnyPromise promiseWithValue:[NSError errorWithDomain:PMKErrorDomain code:PMKInvalidUsageError userInfo:@{NSLocalizedDescriptionKey: @"PMKWhen(nil)"}]];

    if ([promises isKindOfClass:[NSArray class]] || [promises isKindOfClass:[NSDictionary class]]) {
        if ([promises count] == 0)
            return [AnyPromise promiseWithValue:promises];
    } else if ([promises isKindOfClass:[AnyPromise class]]) {
        promises = @[promises];
    } else {
        return [AnyPromise promiseWithValue:promises];
    }

#ifndef PMKDisableProgress
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:[promises count]];
    progress.pausable = NO;
    progress.cancellable = NO;
#else
    struct PMKProgress {
        int completedUnitCount;
        int totalUnitCount;
    };
    __block struct PMKProgress progress;
#endif

    __block int32_t countdown = (int32_t)[promises count];
    BOOL const isdict = [promises isKindOfClass:[NSDictionary class]];

    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        NSInteger index = 0;

        for (__strong id key in promises) {
            AnyPromise *promise = isdict ? promises[key] : key;
            if (!isdict) key = @(index);

            if (![promise isKindOfClass:[AnyPromise class]])
                promise = [AnyPromise promiseWithValue:promise];

            [promise pipe:^(id value){
                if (progress.fractionCompleted >= 1)
                    return;

                if (IsError(value)) {
                    progress.completedUnitCount = progress.totalUnitCount;
                    resolve(NSErrorSupplement(value, @{PMKFailingPromiseIndexKey: key}));
                }
                else if (OSAtomicDecrement32(&countdown) == 0) {
                    progress.completedUnitCount = progress.totalUnitCount;

                    id results;
                    if (isdict) {
                        results = [NSMutableDictionary new];
                        for (id key in promises) {
                            id promise = promises[key];
                            results[key] = IsPromise(promise) ? ((AnyPromise *)promise).value : promise;
                        }
                    } else {
                        results = [NSMutableArray new];
                        for (AnyPromise *promise in promises) {
                            id value = IsPromise(promise) ? (promise.value ?: [NSNull null]) : promise;
                            [results addObject:value];
                        }
                    }
                    resolve(results);
                } else {
                    progress.completedUnitCount++;
                }
            }];
        }
    }];
}
