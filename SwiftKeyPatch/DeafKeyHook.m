#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const NSInteger DKAIButtonTag = 0xDA8201;
static const NSInteger DKToastTag = 0xDA8202;

static IMP gToolbarLayoutOriginal = NULL;
static IMP gRendererSpaceOriginal = NULL;
static IMP gMenuSizeOriginal = NULL;
static IMP gGridCellLayoutOriginal = NULL;
static IMP gGridCellTapOriginal = NULL;

static BOOL gToolbarHooked = NO;
static BOOL gRendererHooked = NO;
static BOOL gMenuHooked = NO;
static BOOL gGridCellHooked = NO;

static NSString *DKLower(NSString *s) {
    return [s isKindOfClass:[NSString class]] ? s.lowercaseString : @"";
}

static BOOL DKContains(NSString *value, NSArray<NSString *> *needles) {
    NSString *lower = DKLower(value);
    for (NSString *needle in needles) {
        if ([lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

static NSString *DKText(UIView *view) {
    if (!view) return @"";

    NSMutableString *out = [NSMutableString string];

    if ([view isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)view).text;
        if (t.length) [out appendFormat:@" %@", t];
    }

    if ([view isKindOfClass:[UIButton class]]) {
        NSString *t = [((UIButton *)view) titleForState:UIControlStateNormal];
        if (t.length) [out appendFormat:@" %@", t];
    }

    if (view.accessibilityLabel.length) {
        [out appendFormat:@" %@", view.accessibilityLabel];
    }

    if (view.accessibilityIdentifier.length) {
        [out appendFormat:@" %@", view.accessibilityIdentifier];
    }

    for (UIView *sub in view.subviews) {
        [out appendString:DKText(sub)];
    }

    return out;
}

static Class DKFindClass(NSString *shortName) {
    Class direct = NSClassFromString(shortName);
    if (direct) return direct;

    Class swiftName = NSClassFromString([@"SKKit." stringByAppendingString:shortName]);
    if (swiftName) return swiftName;

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return Nil;

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);

    Class exactSuffix = Nil;

    for (int i = 0; i < count; i++) {
        const char *raw = class_getName(classes[i]);
        if (!raw) continue;

        NSString *name = [NSString stringWithUTF8String:raw];

        if ([name hasSuffix:shortName]) {
            exactSuffix = classes[i];
            break;
        }
    }

    free(classes);
    return exactSuffix;
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

static UIInputViewController *DKInputController(UIResponder *responder) {
    UIResponder *current = responder;

    while (current) {
        if ([current isKindOfClass:[UIInputViewController class]]) {
            return (UIInputViewController *)current;
        }
        current = current.nextResponder;
    }

    return nil;
}

static void DKToast(UIView *root, NSString *message) {
    if (!root) return;

    [[root viewWithTag:DKToastTag] removeFromSuperview];

    UILabel *label = [[UILabel alloc] initWithFrame:
        CGRectMake(12, 40, MAX(120, root.bounds.size.width - 24), 36)];

    label.tag = DKToastTag;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = message;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.97];
    label.layer.cornerRadius = 10;
    label.layer.masksToBounds = YES;

    [root addSubview:label];
    [root bringSubviewToFront:label];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.16 animations:^{
            label.alpha = 0;
        } completion:^(__unused BOOL done) {
            [label removeFromSuperview];
        }];
    });
}

static NSString *DKAPIKey(void) {
    return [[NSUserDefaults standardUserDefaults]
        stringForKey:@"deafkey.gemini.key"];
}

static void DKSaveAPIKey(UIView *root) {
    NSString *value = [UIPasteboard generalPasteboard].string;

    value = [value stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if (value.length < 12) {
        DKToast(root, @"Copy Gemini API key, then hold AI");
        return;
    }

    [[NSUserDefaults standardUserDefaults]
        setObject:value
           forKey:@"deafkey.gemini.key"];

    DKToast(root, @"Gemini key saved ✓");
}

static BOOL DKNeedsDeepPass(NSString *text) {
    NSString *lower = text.lowercaseString;

    NSArray *markers = @[
        @"spero", @"voglio", @"vorrei", @"forse", @" se ",
        @"perché", @"penso", @"credo",
        @"hope", @"want", @"wish", @"maybe", @" if ",
        @"because", @"think"
    ];

    for (NSString *marker in markers) {
        if ([lower containsString:marker]) return YES;
    }

    NSArray *parts = [text componentsSeparatedByCharactersInSet:
        [[NSCharacterSet alphanumericCharacterSet] invertedSet]];

    NSInteger words = 0;
    NSInteger shortWords = 0;

    for (NSString *word in parts) {
        if (!word.length) continue;
        words++;
        if (word.length <= 3) shortWords++;
    }

    if (words <= 5) return YES;

    NSInteger punctuation = 0;
    NSCharacterSet *set =
        [NSCharacterSet characterSetWithCharactersInString:@".,!?;:"];

    for (NSUInteger i = 0; i < text.length; i++) {
        if ([set characterIsMember:[text characterAtIndex:i]]) punctuation++;
    }

    return punctuation == 0 && shortWords >= MAX(3, words / 3);
}

static NSString *DKSemanticPrompt(void) {
    return @"Analyze the fragmented message before rewriting it. "
    "Build a compact semantic map containing SPEAKER_GOAL, ENTITIES_AND_REFERENCES, "
    "SEMANTIC_ROLES (who does/thinks/wants what, to/about whom, when, where, why, "
    "condition and result), RELATION_GRAPH, MODALITY_SCOPE, DESIRED_OR_FEARED_OUTCOME, "
    "EVENT_STATUS (fact, plan, hypothetical, possibility, wish, fear, command, question, unknown), "
    "POLARITY, IMPLICIT_QUESTIONS, OMITTED_LINKS and UNCERTAINTY. "
    "Do not merge nearby fragments automatically. Preserve negation, conditions, "
    "actor/target relationships and whether something happened or is only desired. "
    "Do not invent facts. Be concise.";
}

static NSString *DKFinalPrompt(void) {
    return @"Rewrite the original fragmented message into the most likely natural message. "
    "Use the semantic map only as an interpretation aid; ORIGINAL TEXT is the source of truth. "
    "Preserve language, names, places, numbers, slang, tone and concrete facts. "
    "Preserve who does/thinks/wants/asks what, toward whom or what, negation, tense, "
    "conditions, causes and whether each event is a fact, wish, fear, possibility, "
    "question, command or plan. Keep separate intentions separate. "
    "Turn implicit questions into natural explicit questions only when supported. "
    "Do not invent facts. If uncertain, use conservative wording. "
    "Output ONLY the reconstructed message.";
}

static void DKGemini(NSString *key,
                     NSString *instruction,
                     NSString *text,
                     NSInteger maxTokens,
                     void (^completion)(NSString *)) {

    NSURL *url = [NSURL URLWithString:
        @"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent"];

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"POST";
    request.timeoutInterval = 20;

    [request setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    [request setValue:@"application/json"
   forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"systemInstruction": @{
            @"parts": @[@{@"text": instruction}]
        },
        @"contents": @[@{
            @"role": @"user",
            @"parts": @[@{@"text": text}]
        }],
        @"generationConfig": @{
            @"maxOutputTokens": @(maxTokens)
        }
    };

    request.HTTPBody =
        [NSJSONSerialization dataWithJSONObject:body
                                        options:0
                                          error:nil];

    [[[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data,
                            NSURLResponse *response,
                            NSError *error) {

        NSString *result = nil;
        NSInteger status =
            [(NSHTTPURLResponse *)response statusCode];

        if (!error && status >= 200 && status < 300 && data.length) {
            NSDictionary *json =
                [NSJSONSerialization JSONObjectWithData:data
                                                 options:0
                                                   error:nil];

            NSArray *candidates = json[@"candidates"];
            NSDictionary *content =
                [candidates.firstObject objectForKey:@"content"];
            NSArray *parts = content[@"parts"];
            NSString *raw =
                [parts.firstObject objectForKey:@"text"];

            if ([raw isKindOfClass:[NSString class]]) {
                result =
                    [raw stringByTrimmingCharactersInSet:
                        NSCharacterSet.whitespaceAndNewlineCharacterSet];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });

    }] resume];
}

static void DKReplaceContext(UIInputViewController *controller,
                             NSString *context,
                             NSString *replacement) {

    id<UITextDocumentProxy> proxy =
        controller.textDocumentProxy;

    __block NSInteger count = 0;

    [context enumerateSubstringsInRange:NSMakeRange(0, context.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(__unused NSString *substring,
                                          __unused NSRange substringRange,
                                          __unused NSRange enclosingRange,
                                          __unused BOOL *stop) {
        count++;
    }];

    for (NSInteger i = 0; i < count; i++) {
        [proxy deleteBackward];
    }

    [proxy insertText:replacement];
}

static void DKRunFix(UIButton *button) {
    UIInputViewController *controller = DKInputController(button);
    UIView *root = controller.view ?: button.window;

    if (!controller) {
        DKToast(root, @"Keyboard context unavailable");
        return;
    }

    NSString *key = DKAPIKey();

    if (!key.length) {
        DKToast(root, @"Copy Gemini key, then hold AI once");
        return;
    }

    NSString *context =
        controller.textDocumentProxy.documentContextBeforeInput ?: @"";

    if (!context.length) {
        DKToast(root, @"Type something first");
        return;
    }

    button.enabled = NO;
    [button setTitle:@"…" forState:UIControlStateNormal];

    void (^finish)(NSString *) =
        ^(NSString *result) {

        button.enabled = YES;
        [button setTitle:@"AI" forState:UIControlStateNormal];

        if (!result.length) {
            DKToast(root, @"Deaf AI request failed");
            return;
        }

        DKReplaceContext(controller, context, result);
    };

    if (!DKNeedsDeepPass(context)) {
        NSString *quick =
            @"Correct spelling, grammar, punctuation and obvious typing mistakes. "
             "Preserve exact meaning, language, names, slang, tone, negation, tense "
             "and who is doing what to whom. Return only corrected text.";

        DKGemini(key, quick, context, 320, finish);

    } else {

        DKGemini(key,
                 DKSemanticPrompt(),
                 context,
                 240,
                 ^(NSString *map) {

            if (!map.length) {
                DKGemini(key,
                         DKFinalPrompt(),
                         context,
                         420,
                         finish);
                return;
            }

            NSString *combined =
                [NSString stringWithFormat:
                    @"ORIGINAL TEXT:\n%@\n\nSEMANTIC MAP:\n%@",
                    context,
                    map];

            DKGemini(key,
                     DKFinalPrompt(),
                     combined,
                     420,
                     finish);
        });
    }
}

@interface DKActionTarget : NSObject
+ (instancetype)shared;
- (void)tapAI:(UIButton *)sender;
- (void)holdAI:(UILongPressGestureRecognizer *)sender;
@end

@implementation DKActionTarget

+ (instancetype)shared {
    static DKActionTarget *target;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        target = [DKActionTarget new];
    });
    return target;
}

- (void)tapAI:(UIButton *)sender {
    DKRunFix(sender);
}

- (void)holdAI:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        DKSaveAPIKey(sender.view);
    }
}

@end

static UIView *DKFindLeftToolbarControl(UIView *root) {
    for (UIView *sub in root.subviews) {
        NSString *identifier = sub.accessibilityIdentifier ?: @"";
        NSString *label = sub.accessibilityLabel ?: @"";
        NSString *text = DKText(sub);

        if ([identifier isEqualToString:@"id_toolbar_left_button"]
            || DKContains(identifier, @[@"copilot", @"bing"])
            || DKContains(label, @[@"copilot", @"bing"])
            || DKContains(text, @[@"toolbarCopilotButton", @"copilot"])) {
            return sub;
        }

        UIView *nested = DKFindLeftToolbarControl(sub);
        if (nested) return nested;
    }

    return nil;
}

static void DKInstallAIButton(UIView *toolbar) {
    if (!toolbar || toolbar.bounds.size.width < 100) return;

    UIView *leftControl = DKFindLeftToolbarControl(toolbar);

    CGRect targetFrame = CGRectMake(2.0,
                                    2.0,
                                    40.0,
                                    MAX(28.0, toolbar.bounds.size.height - 4.0));

    if (leftControl && leftControl.superview) {
        targetFrame = [leftControl.superview convertRect:leftControl.frame
                                                  toView:toolbar];
        leftControl.hidden = YES;
        leftControl.alpha = 0.0;
        leftControl.userInteractionEnabled = NO;
    }

    UIButton *button = (UIButton *)[toolbar viewWithTag:DKAIButtonTag];

    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = DKAIButtonTag;

        [button setTitle:@"AI" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];

        button.titleLabel.font =
            [UIFont systemFontOfSize:13 weight:UIFontWeightBold];

        button.backgroundColor =
            [UIColor colorWithWhite:0.17 alpha:1.0];

        button.layer.cornerRadius = 9;
        button.layer.masksToBounds = YES;
        button.accessibilityLabel = @"Deaf AI Fix";

        [button addTarget:[DKActionTarget shared]
                   action:@selector(tapAI:)
         forControlEvents:UIControlEventTouchUpInside];

        UILongPressGestureRecognizer *hold =
            [[UILongPressGestureRecognizer alloc]
                initWithTarget:[DKActionTarget shared]
                        action:@selector(holdAI:)];

        hold.minimumPressDuration = 0.55;
        [button addGestureRecognizer:hold];

        [toolbar addSubview:button];
    }

    if (targetFrame.size.width < 28 || targetFrame.size.width > 72) {
        targetFrame.size.width = 40;
    }

    if (targetFrame.size.height < 24 || targetFrame.size.height > 44) {
        targetFrame.size.height = 32;
    }

    button.frame = CGRectIntegral(targetFrame);
    [toolbar bringSubviewToFront:button];
}

static void DKToolbarLayout(id self, SEL _cmd) {
    if (gToolbarLayoutOriginal) {
        ((void(*)(id,SEL))gToolbarLayoutOriginal)(self, _cmd);
    }

    if ([self isKindOfClass:[UIView class]]) {
        DKInstallAIButton((UIView *)self);
    }
}

static void DKDrawSpace(id self,
                        SEL _cmd,
                        id key,
                        NSString *imageName,
                        NSString *enabledLangText,
                        CGRect frame,
                        CGContextRef context,
                        NSString *attribute) {

    if (!gRendererSpaceOriginal) return;

    ((void(*)(id,SEL,id,NSString*,NSString*,CGRect,CGContextRef,NSString *))
        gRendererSpaceOriginal)
        (self,
         _cmd,
         key,
         @"",
         enabledLangText,
         frame,
         context,
         attribute);
}

static UICollectionView *DKCollectionViewForCell(UIView *cell) {
    UIView *view = cell.superview;

    while (view) {
        if ([view isKindOfClass:[UICollectionView class]]) {
            return (UICollectionView *)view;
        }
        view = view.superview;
    }

    return nil;
}

static BOOL DKBlockedToolCell(UIView *cell) {
    return DKContains(DKText(cell), @[
        @"rewards",
        @"microsoft rewards",
        @"messages",
        @"messaggi",
        @"messaging centre",
        @"messaging center"
    ]);
}

static BOOL DKSettingsCell(UIView *cell) {
    return DKContains(DKText(cell), @[
        @"impostazioni",
        @"settings"
    ]);
}

static NSMutableSet<NSIndexPath *> *DKHiddenPathsForDataSource(id dataSource) {
    static char key;

    NSMutableSet *set =
        objc_getAssociatedObject(dataSource, &key);

    if (!set) {
        set = [NSMutableSet set];

        objc_setAssociatedObject(dataSource,
                                 &key,
                                 set,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return set;
}

static void DKGridCellLayout(id self, SEL _cmd) {
    if (gGridCellLayoutOriginal) {
        ((void(*)(id,SEL))gGridCellLayoutOriginal)(self, _cmd);
    }

    if (![self isKindOfClass:[UIView class]]) return;

    UIView *cell = (UIView *)self;

    if (!DKBlockedToolCell(cell)) {
        cell.alpha = 1.0;
        cell.hidden = NO;
        cell.userInteractionEnabled = YES;
        return;
    }

    cell.alpha = 0.0;
    cell.hidden = YES;
    cell.userInteractionEnabled = NO;
    cell.accessibilityElementsHidden = YES;

    UICollectionView *collection = DKCollectionViewForCell(cell);
    NSIndexPath *path = collection ? [collection indexPathForCell:(id)cell] : nil;
    id dataSource = collection.dataSource;

    if (path && dataSource) {
        NSMutableSet *hidden =
            DKHiddenPathsForDataSource(dataSource);

        if (![hidden containsObject:path]) {
            [hidden addObject:path];

            dispatch_async(dispatch_get_main_queue(), ^{
                [collection.collectionViewLayout invalidateLayout];
            });
        }
    }
}

static CGSize DKMenuSize(id self,
                         SEL _cmd,
                         UICollectionView *collectionView,
                         UICollectionViewLayout *layout,
                         NSIndexPath *indexPath) {

    if ([DKHiddenPathsForDataSource(self) containsObject:indexPath]) {
        return CGSizeMake(0.1, 0.1);
    }

    return ((CGSize(*)(id,SEL,id,id,id))
        gMenuSizeOriginal)(self,
                           _cmd,
                           collectionView,
                           layout,
                           indexPath);
}

static void DKOpenSwiftKeySettings(UIView *cell) {
    UIInputViewController *controller = DKInputController(cell);

    if (!controller) return;

    Class deepLink = NSClassFromString(@"SKDeepLink");
    SEL actionSelector =
        NSSelectorFromString(@"performAction:source:withResponder:withWebUrl:");

    BOOL opened = NO;

    if (deepLink && [deepLink respondsToSelector:actionSelector]) {
        opened =
            ((BOOL(*)(id,SEL,id,id,id,id))objc_msgSend)(
                deepLink,
                actionSelector,
                @"settings",
                @"toolbar_panel",
                controller,
                nil
            );
    }

    if (opened) return;

    NSURL *fallback = [NSURL URLWithString:@"swiftkey://settings"];

    [controller.extensionContext
        openURL:fallback
        completionHandler:^(__unused BOOL success) {}];
}

static void DKGridCellTap(id self, SEL _cmd) {
    if ([self isKindOfClass:[UIView class]]
        && DKSettingsCell((UIView *)self)) {

        DKOpenSwiftKeySettings((UIView *)self);
        return;
    }

    if (gGridCellTapOriginal) {
        ((void(*)(id,SEL))gGridCellTapOriginal)(self, _cmd);
    }
}

static void DKTryInstallHooks(void) {
    Class toolbar = DKFindClass(@"SKCandidateToolbarView");

    if (toolbar && !gToolbarHooked) {
        gToolbarLayoutOriginal =
            DKHook(toolbar,
                   @selector(layoutSubviews),
                   (IMP)DKToolbarLayout);

        gToolbarHooked = (gToolbarLayoutOriginal != NULL);
    }

    Class renderer = DKFindClass(@"SKKeyboardKeyRenderer");

    if (renderer && !gRendererHooked) {
        SEL selector =
            NSSelectorFromString(
                @"drawSpaceKey:withImage:enabledLangText:inFrame:inContext:attribute:");

        gRendererSpaceOriginal =
            DKHook(renderer,
                   selector,
                   (IMP)DKDrawSpace);

        gRendererHooked = (gRendererSpaceOriginal != NULL);
    }

    Class menu = DKFindClass(@"SKToolBarMenuController");

    if (menu && !gMenuHooked) {
        SEL sizeSelector =
            @selector(collectionView:layout:sizeForItemAtIndexPath:);

        gMenuSizeOriginal =
            DKHook(menu,
                   sizeSelector,
                   (IMP)DKMenuSize);

        gMenuHooked = (gMenuSizeOriginal != NULL);
    }

    Class gridCell = DKFindClass(@"SkToolBarMenuGridCVCell");

    if (gridCell && !gGridCellHooked) {
        gGridCellLayoutOriginal =
            DKHook(gridCell,
                   @selector(layoutSubviews),
                   (IMP)DKGridCellLayout);

        gGridCellTapOriginal =
            DKHook(gridCell,
                   NSSelectorFromString(@"cellTapped"),
                   (IMP)DKGridCellTap);

        gGridCellHooked =
            (gGridCellLayoutOriginal != NULL
             && gGridCellTapOriginal != NULL);
    }
}

static void DKRetryInstall(NSInteger attempt) {
    DKTryInstallHooks();

    if (gToolbarHooked
        && gRendererHooked
        && gMenuHooked
        && gGridCellHooked) {
        return;
    }

    if (attempt >= 40) return;

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(0.25 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            DKRetryInstall(attempt + 1);
        });
}

__attribute__((constructor))
static void DKStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DKRetryInstall(0);
    });
}
