#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static const NSInteger DKAIButtonTag = 0xD311;
static const NSInteger DKToastTag = 0xD312;

static IMP DKSpaceOriginal = NULL;
static IMP DKToolbarLayoutOriginal = NULL;
static IMP DKToolCellLayoutOriginal = NULL;

static NSString *DKLower(NSString *s) {
    return [s isKindOfClass:[NSString class]] ? s.lowercaseString : @"";
}

static BOOL DKContainsAny(NSString *value, NSArray<NSString *> *needles) {
    NSString *lower = DKLower(value);
    for (NSString *needle in needles) {
        if ([lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

static NSString *DKVisibleText(UIView *view) {
    NSMutableString *text = [NSMutableString string];
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *v = ((UILabel *)view).text;
        if (v.length) [text appendFormat:@" %@", v];
    }
    if ([view isKindOfClass:[UIButton class]]) {
        NSString *v = [((UIButton *)view) titleForState:UIControlStateNormal];
        if (v.length) [text appendFormat:@" %@", v];
    }
    if (view.accessibilityLabel.length) [text appendFormat:@" %@", view.accessibilityLabel];
    for (UIView *subview in view.subviews) [text appendString:DKVisibleText(subview)];
    return text;
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

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 40, MAX(120, root.bounds.size.width - 24), 36)];
    label.tag = DKToastTag;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = message;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    label.layer.cornerRadius = 10;
    label.layer.masksToBounds = YES;
    [root addSubview:label];
    [root bringSubviewToFront:label];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.18 animations:^{ label.alpha = 0; } completion:^(__unused BOOL done) {
            [label removeFromSuperview];
        }];
    });
}

static NSString *DKAPIKey(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"deafkey.gemini.key"];
}

static void DKSaveAPIKeyFromClipboard(UIView *root) {
    NSString *value = [UIPasteboard generalPasteboard].string;
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if (value.length < 12) {
        DKToast(root, @"Copy Gemini API key first, then hold AI");
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:value forKey:@"deafkey.gemini.key"];
    DKToast(root, @"Gemini key saved ✓");
}

static void DKGemini(NSString *apiKey,
                     NSString *instruction,
                     NSString *text,
                     NSInteger maxTokens,
                     void (^completion)(NSString *result)) {
    NSURL *url = [NSURL URLWithString:@"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 20;
    [request setValue:apiKey forHTTPHeaderField:@"x-goog-api-key"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"systemInstruction": @{@"parts": @[@{@"text": instruction}]},
        @"contents": @[@{@"role": @"user", @"parts": @[@{@"text": text}]}],
        @"generationConfig": @{@"maxOutputTokens": @(maxTokens)}
    };

    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *result = nil;
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];

        if (!error && statusCode >= 200 && statusCode < 300 && data.length) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *candidates = json[@"candidates"];
            NSDictionary *content = [candidates.firstObject objectForKey:@"content"];
            NSArray *parts = content[@"parts"];
            NSString *raw = [parts.firstObject objectForKey:@"text"];

            if ([raw isKindOfClass:[NSString class]]) {
                result = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    }] resume];
}

static BOOL DKNeedsDeepPass(NSString *text) {
    NSString *lower = text.lowercaseString;
    NSArray *markers = @[
        @"spero", @"voglio", @"vorrei", @"forse", @" se ", @"perché", @"penso", @"credo",
        @"hope", @"want", @"wish", @"maybe", @" if ", @"because", @"think"
    ];

    for (NSString *marker in markers) {
        if ([lower containsString:marker]) return YES;
    }

    NSArray *parts = [text componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    NSInteger wordCount = 0;
    NSInteger shortWordCount = 0;

    for (NSString *word in parts) {
        if (!word.length) continue;
        wordCount++;
        if (word.length <= 3) shortWordCount++;
    }

    if (wordCount <= 5) return YES;

    NSInteger punctuation = 0;
    NSCharacterSet *punctuationSet = [NSCharacterSet characterSetWithCharactersInString:@".,!?;:"];
    for (NSUInteger i = 0; i < text.length; i++) {
        if ([punctuationSet characterIsMember:[text characterAtIndex:i]]) punctuation++;
    }

    return punctuation == 0 && shortWordCount >= MAX(3, wordCount / 3);
}

static NSString *DKSemanticPrompt(void) {
    return @"Analyze the fragmented message before rewriting it. Build a compact semantic map with: "
    "SPEAKER_GOAL; ENTITIES_AND_REFERENCES; SEMANTIC_ROLES (who does/thinks/wants what, to/about whom, when, where, why, condition and result); "
    "RELATION_GRAPH; MODALITY_SCOPE; DESIRED_OR_FEARED_OUTCOME; EVENT_STATUS (fact, plan, hypothetical, possibility, wish, fear, command, question, unknown); "
    "POLARITY; IMPLICIT_QUESTIONS; OMITTED_LINKS; UNCERTAINTY. "
    "Do not merge nearby fragments automatically. Preserve negation, conditions, actor/target relationships and event status. Do not invent facts. Be concise.";
}

static NSString *DKFinalPrompt(void) {
    return @"Rewrite the original fragmented message into the most likely natural message using the semantic map only as an interpretation aid. "
    "The original text is the source of truth. Preserve language, names, places, numbers, slang, tone and concrete facts. "
    "Preserve who does/thinks/wants/asks what, toward whom or what, and preserve negation, tense, conditions, causes and whether each event is a fact, wish, fear, possibility, question, command or plan. "
    "If multiple intentions are present, keep them separate. Turn implicit questions into natural explicit questions only when supported. "
    "Do not invent facts. If a relation is uncertain, use conservative wording. Output ONLY the reconstructed message.";
}

static void DKReplaceContext(UIInputViewController *controller, NSString *context, NSString *replacement) {
    id<UITextDocumentProxy> proxy = controller.textDocumentProxy;
    __block NSInteger composedCount = 0;

    [context enumerateSubstringsInRange:NSMakeRange(0, context.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(__unused NSString *substring,
                                          __unused NSRange substringRange,
                                          __unused NSRange enclosingRange,
                                          __unused BOOL *stop) {
        composedCount++;
    }];

    for (NSInteger i = 0; i < composedCount; i++) [proxy deleteBackward];
    [proxy insertText:replacement];
}

static void DKRunFix(UIButton *button) {
    UIInputViewController *controller = DKInputController(button);
    UIView *root = controller.view ?: button.superview;

    if (!controller) {
        DKToast(root, @"Keyboard context unavailable");
        return;
    }

    NSString *apiKey = DKAPIKey();
    if (!apiKey.length) {
        DKToast(root, @"Copy Gemini key, then HOLD AI once");
        return;
    }

    NSString *context = controller.textDocumentProxy.documentContextBeforeInput ?: @"";
    if (!context.length) {
        DKToast(root, @"Type something first");
        return;
    }

    button.enabled = NO;
    [button setTitle:@"…" forState:UIControlStateNormal];

    void (^finish)(NSString *) = ^(NSString *result) {
        button.enabled = YES;
        [button setTitle:@"AI" forState:UIControlStateNormal];

        if (!result.length) {
            DKToast(root, @"Deaf AI request failed");
            return;
        }

        DKReplaceContext(controller, context, result);
    };

    if (!DKNeedsDeepPass(context)) {
        NSString *quickPrompt =
            @"Correct spelling, grammar, punctuation and obvious typing mistakes. "
             "Preserve exact meaning, language, names, slang, tone, negation, tense and who is doing what to whom. "
             "Return only the corrected text.";

        DKGemini(apiKey, quickPrompt, context, 320, finish);
    } else {
        DKGemini(apiKey, DKSemanticPrompt(), context, 240, ^(NSString *semanticMap) {
            if (!semanticMap.length) {
                DKGemini(apiKey, DKFinalPrompt(), context, 420, finish);
                return;
            }

            NSString *combined = [NSString stringWithFormat:
                @"ORIGINAL TEXT:\n%@\n\nSEMANTIC MAP:\n%@", context, semanticMap];

            DKGemini(apiKey, DKFinalPrompt(), combined, 420, finish);
        });
    }
}

@interface DKActionTarget : NSObject
+ (instancetype)shared;
- (void)aiTap:(UIButton *)sender;
- (void)aiHold:(UILongPressGestureRecognizer *)sender;
@end

@implementation DKActionTarget

+ (instancetype)shared {
    static DKActionTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [DKActionTarget new];
    });
    return target;
}

- (void)aiTap:(UIButton *)sender {
    DKRunFix(sender);
}

- (void)aiHold:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        DKSaveAPIKeyFromClipboard(sender.view);
    }
}

@end

static void DKHideCopilotControls(UIView *root) {
    NSArray *blocked = @[@"copilot", @"bing"];

    for (UIView *subview in root.subviews) {
        NSString *text = DKVisibleText(subview);

        if ([subview isKindOfClass:[UIControl class]] && DKContainsAny(text, blocked)) {
            subview.hidden = YES;
            subview.userInteractionEnabled = NO;
        } else {
            DKHideCopilotControls(subview);
        }
    }
}

static void DKInstallAIButton(UIView *toolbar) {
    DKHideCopilotControls(toolbar);

    UIButton *button = (UIButton *)[toolbar viewWithTag:DKAIButtonTag];
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = DKAIButtonTag;
        [button setTitle:@"AI" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        button.backgroundColor = [UIColor colorWithRed:0.25 green:0.20 blue:0.35 alpha:0.98];
        button.layer.cornerRadius = 10;
        button.accessibilityLabel = @"Deaf AI Fix";

        [button addTarget:[DKActionTarget shared]
                   action:@selector(aiTap:)
         forControlEvents:UIControlEventTouchUpInside];

        UILongPressGestureRecognizer *hold =
            [[UILongPressGestureRecognizer alloc] initWithTarget:[DKActionTarget shared]
                                                          action:@selector(aiHold:)];
        hold.minimumPressDuration = 0.55;
        [button addGestureRecognizer:hold];

        [toolbar addSubview:button];
    }

    CGFloat height = MAX(30, MIN(38, toolbar.bounds.size.height - 6));
    button.frame = CGRectMake(4,
                              MAX(2, (toolbar.bounds.size.height - height) * 0.5),
                              44,
                              height);

    [toolbar bringSubviewToFront:button];
}

static void DKToolbarLayout(id self, SEL _cmd) {
    if (DKToolbarLayoutOriginal) {
        ((void(*)(id,SEL))DKToolbarLayoutOriginal)(self, _cmd);
    }

    if ([self isKindOfClass:[UIView class]]) {
        DKInstallAIButton((UIView *)self);
    }
}

static void DKDrawSpace(id self,
                        SEL _cmd,
                        id key,
                        NSString *imageName,
                        NSString *enabledLanguages,
                        CGRect frame,
                        CGContextRef context,
                        NSString *attribute) {
    if (!DKSpaceOriginal) return;

    ((void(*)(id,SEL,id,NSString*,NSString*,CGRect,CGContextRef,NSString *))DKSpaceOriginal)
        (self, _cmd, key, nil, @"EN IT", frame, context, attribute);
}

static BOOL DKToolCellIsBlocked(UIView *cell) {
    return DKContainsAny(DKVisibleText(cell), @[
        @"rewards", @"microsoft rewards", @"messages", @"messaggi",
        @"copilot", @"compose", @"componi", @"chat", @"tone", @"tono",
        @"editor", @"create", @"crea", @"images", @"immagini", @"meme"
    ]);
}

static void DKToolCellLayout(id self, SEL _cmd) {
    if (DKToolCellLayoutOriginal) {
        ((void(*)(id,SEL))DKToolCellLayoutOriginal)(self, _cmd);
    }

    if (![self isKindOfClass:[UIView class]]) return;

    UIView *cell = (UIView *)self;
    if (DKToolCellIsBlocked(cell)) {
        cell.alpha = 0;
        cell.userInteractionEnabled = NO;
        cell.accessibilityElementsHidden = YES;
    } else {
        cell.alpha = 1;
        cell.userInteractionEnabled = YES;
        cell.accessibilityElementsHidden = NO;
    }
}

static BOOL DKAlwaysNo(id self, SEL _cmd) {
    return NO;
}

static void DKMarkOnboardingDone(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"reachedEndOfOnboardingFlow"];
    [defaults setBool:YES forKey:@"ReachedEndOfOnboardingFlow"];
    [defaults setBool:YES forKey:@"didFinishOnboardingFlow"];
    [defaults setBool:NO forKey:@"shouldPresentOnboarding"];
}

static Method DKDirectMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method result = NULL;

    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) {
            result = methods[i];
            break;
        }
    }

    free(methods);
    return result;
}

static IMP DKInstallSafeOverride(Class cls, SEL selector, IMP replacement) {
    if (!cls) return NULL;

    Method direct = DKDirectMethod(cls, selector);
    if (direct) {
        IMP original = method_getImplementation(direct);
        method_setImplementation(direct, replacement);
        return original;
    }

    Method inherited = class_getInstanceMethod(cls, selector);
    if (!inherited) return NULL;

    IMP original = method_getImplementation(inherited);
    const char *types = method_getTypeEncoding(inherited);

    if (class_addMethod(cls, selector, replacement, types)) {
        return original;
    }

    return class_replaceMethod(cls, selector, replacement, types);
}

static Class DKFirstClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (cls) return cls;
    }
    return Nil;
}

static void DKInstallKeyboardHooks(void) {
    Class renderer = DKFirstClass(@[
        @"SKKeyboardKeyRenderer",
        @"SKKit.SKKeyboardKeyRenderer"
    ]);

    SEL spaceSelector =
        NSSelectorFromString(@"drawSpaceKey:withImage:enabledLangText:inFrame:inContext:attribute:");

    DKSpaceOriginal = DKInstallSafeOverride(renderer, spaceSelector, (IMP)DKDrawSpace);

    Class toolbar = DKFirstClass(@[
        @"SKCandidateToolbarView",
        @"SKKit.SKCandidateToolbarView"
    ]);

    DKToolbarLayoutOriginal =
        DKInstallSafeOverride(toolbar, @selector(layoutSubviews), (IMP)DKToolbarLayout);

    Class toolCell = DKFirstClass(@[
        @"SkToolBarMenuGridCVCell",
        @"SKKit.SkToolBarMenuGridCVCell"
    ]);

    DKToolCellLayoutOriginal =
        DKInstallSafeOverride(toolCell, @selector(layoutSubviews), (IMP)DKToolCellLayout);
}

static void DKInstallHostHooks(void) {
    DKMarkOnboardingDone();

    Class choreographer = DKFirstClass(@[
        @"SwiftKeyApp.OnboardingChoreographer",
        @"_TtC11SwiftKeyApp23OnboardingChoreographer"
    ]);

    SEL shouldPresentSelector = NSSelectorFromString(@"shouldPresentOnboarding");

    if (choreographer && class_getInstanceMethod(choreographer, shouldPresentSelector)) {
        DKInstallSafeOverride(choreographer, shouldPresentSelector, (IMP)DKAlwaysNo);
    }
}

__attribute__((constructor))
static void DKStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL isExtension = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"NSExtension"] != nil;

        if (isExtension) {
            DKInstallKeyboardHooks();
        } else {
            DKInstallHostHooks();
        }
    });
}
