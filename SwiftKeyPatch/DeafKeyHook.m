#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static IMP originalSpace = NULL;

static void patchedSpace(id self, SEL _cmd, id key, NSString *imageName, NSString *languages, CGRect frame, CGContextRef ctx, NSString *attr) {
    if (originalSpace) {
        ((void(*)(id,SEL,id,NSString*,NSString*,CGRect,CGContextRef,NSString*))originalSpace)(self,_cmd,key,nil,languages,frame,ctx,attr);
    }
}

__attribute__((constructor))
static void StartPatch(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"SKKeyboardKeyRenderer");
        SEL sel = NSSelectorFromString(@"drawSpaceKey:withImage:enabledLangText:inFrame:inContext:attribute:");
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            originalSpace = method_getImplementation(m);
            method_setImplementation(m, (IMP)patchedSpace);
        }
    });
}
