#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static IMP gShouldPresentOriginal = NULL;

static BOOL DKReturnNo(id self, SEL _cmd) {
    return NO;
}

static Class DKFindHostClass(NSString *shortName) {
    Class direct = NSClassFromString(shortName);
    if (direct) return direct;

    Class swiftName = NSClassFromString([@"SwiftKeyApp." stringByAppendingString:shortName]);
    if (swiftName) return swiftName;

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return Nil;

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);

    Class found = Nil;

    for (int i = 0; i < count; i++) {
        const char *raw = class_getName(classes[i]);
        if (!raw) continue;

        NSString *name = [NSString stringWithUTF8String:raw];

        if ([name hasSuffix:shortName]) {
            found = classes[i];
            break;
        }
    }

    free(classes);
    return found;
}

static BOOL DKMethodIsDirect(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL result = NO;

    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) {
            result = YES;
            break;
        }
    }

    free(methods);
    return result;
}

static IMP DKHook(Class cls, SEL selector, IMP replacement) {
    if (!cls) return NULL;

    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NULL;

    IMP original = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);

    if (!DKMethodIsDirect(cls, selector)) {
        if (class_addMethod(cls, selector, replacement, types)) {
            return original;
        }
    }

    method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    return original;
}

static void DKPrimeOnboardingFlags(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setBool:YES forKey:@"reachedEndOfOnboardingFlow"];
    [defaults setBool:YES forKey:@"ReachedEndOfOnboardingFlow"];
    [defaults setBool:YES forKey:@"didFinishOnboardingFlow"];
    [defaults setBool:YES forKey:@"_didFinishOnboardingFlow"];
    [defaults setInteger:999 forKey:@"onboardingVersion"];
}

static void DKTryHookOnboarding(NSInteger attempt) {
    Class choreographer = DKFindHostClass(@"OnboardingChoreographer");
    SEL selector = NSSelectorFromString(@"shouldPresentOnboarding");

    if (choreographer && class_getInstanceMethod(choreographer, selector)) {
        gShouldPresentOriginal =
            DKHook(choreographer, selector, (IMP)DKReturnNo);

        if (gShouldPresentOriginal) return;
    }

    if (attempt >= 40) return;

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            DKTryHookOnboarding(attempt + 1);
        });
}

__attribute__((constructor))
static void DKHostStart(void) {
    @autoreleasepool {
        DKPrimeOnboardingFlags();

        dispatch_async(dispatch_get_main_queue(), ^{
            DKTryHookOnboarding(0);
        });
    }
}
