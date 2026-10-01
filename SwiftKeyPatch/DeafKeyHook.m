#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static const NSInteger DKAIButtonTag = 0xD411;
static const NSInteger DKToastTag = 0xD412;

static IMP DKSpaceOriginal = NULL;
static IMP DKToolbarLayoutOriginal = NULL;
static IMP DKMenuAddedOriginal = NULL;

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
    NSMutableString *result = [NSMutableString string];

    if ([view isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)view).text;
        if (t.length) [result appendFormat:@" %@", t];
    }

    if ([view isKindOfClass:[UIButton class]]) {
        NSString *t = [((UIButton *)view) titleForState:UIControlStateNormal];
        if (t.length) [result appendFormat:@" %@", t];
    }

    if (view.accessibilityLabel.length) {
        [result appendFormat:@" %@", view.accessibilityLabel];
    }

    for (UIView *sub in view.subviews) {
        [result appendString:DKVisibleText(sub)];
    }

    return result;
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
        CGRectMake(12, 40, MAX(100, root.bounds.size.width - 24), 34)];

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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.18 animations:^{
            label.alpha = 0;
        } completion:^(__unused BOOL finished) {
            [label removeFromSuperview];
        }];
    });
}

static NSString *DKAPIKey(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"deafkey.gemini.key"];
}

static void DKStoreAPIKey(UIView *root) {
    NSString *key = [UIPasteboard generalPasteboard].string;
    key = [key stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if (key.length < 12) {
        DKToast(root, @"Copy Gemini API key first, then hold AI");
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:key
                                             forKey:@"deafkey.gemini.key"];

    DKToast(root, @"Gemini key saved ✓");
}

static BOOL DKNeedsDeepPass(NSString *text) {
    NSString *lower = text.lowercaseString;

    NSArray *markers = @[
        @"spero", @"voglio", @"vorrei", @"forse", @" se ", @"perché",
        @"penso", @"credo", @"hope", @"want", @"wish", @"maybe",
        @" if ", @"because", @"think"
    ];

    for (NSString *marker in markers) {
        if ([lower containsString:marker]) return YES;
    }

    NSArray *pieces = [text componentsSeparatedByCharactersInSet:
        [[NSCharacterSet alphanumericCharacterSet] invertedSet]];

    NSInteger words = 0;
    NSInteger shortWords = 0;

    for (NSString *piece in pieces) {
        if (!piece.length) continue;
        words++;
        if (piece.length <= 3) shortWords++;
    }

    if (words <= 5) return YES;

    NSInteger punctuation = 0;
    NSCharacterSet *punctuationSet =
        [NSCharacterSet characterSetWithCharactersInString:@".,!?;:"];

    for (NSUInteger i = 0; i < text.length; i++) {
        if ([punctuationSet characterIsMember:[text characterAtIndex:i]]) {
            punctuation++;
        }
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
    "actor/target relationships and event status. Do not invent facts. Be concise.";
}

static NSString *DKFinalPrompt(void) {
    return @"Rewrite the original fragmented message into the most likely natural message "
    "using the semantic map only as an interpretation aid. The original text is the source "
    "of truth. Preserve language, names, places, numbers, slang, tone and concrete facts. "
    "Preserve who does/thinks/wants/asks what, toward whom or what, and preserve negation, "
    "tense, conditions, causes and whether each event is a fact, wish, fear, possibility, "
    "question, command or plan. If there are multiple intentions, keep them separate. "
    "Turn implicit questions into natural explicit questions only when supported. "
    "Do not invent facts. If a relation is uncertain, use conservative wording. "
    "Output ONLY the reconstructed message.";
}

static void DKGemini(NSString *key,
                     NSString *instruction,
                     NSString *text,
                     NSInteger maxTokens,
                     void (^completion)(NSString *)) {

    NSURL *url = [NSURL URLWithString:
        @"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent"];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 20;

    [request setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"systemInstruction": @{@"parts": @[@{@"text": instruction}]},
        @"contents": @[@{
            @"role": @"user",
            @"parts": @[@{@"text": text}]
        }],
        @"generationConfig": @{@"maxOutputTokens": @(maxTokens)}
    };

    request.HTTPBody =
        [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

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

    id<UITextDocumentProxy> proxy = controller.textDocumentProxy;

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
    UIInputViewController *controller =
        DKInputController(button);

    UIView *root =
        controller.view ?: button.superview;

    if (!controller) {
        DKToast(root, @"Keyboard context unavailable");
        return;
    }

    NSString *apiKey = DKAPIKey();

    if (!apiKey.length) {
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
             "and who is doing what to whom. Return only the corrected text.";

        DKGemini(apiKey, quick, context, 320, finish);

    } else {

        DKGemini(apiKey,
                 DKSemanticPrompt(),
                 context,
                 240,
                 ^(NSString *map) {

            if (!map.length) {
                DKGemini(apiKey,
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

            DKGemini(apiKey,
                     DKFinalPrompt(),
                     combined,
                     420,
                     finish);
        });
    }
}

@interface DKActions : NSObject
+ (instancetype)shared;
- (void)tapAI:(UIButton *)sender;
- (void)holdAI:(UILongPressGestureRecognizer *)sender;
@end

@implementation DKActions

+ (instancetype)shared {
    static DKActions *instance;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        instance = [DKActions new];
    });

    return instance;
}

- (void)tapAI:(UIButton *)sender {
    DKRunFix(sender);
}

- (void)holdAI:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        DKStoreAPIKey(sender.view);
    }
}

@end

static UIButton *DKExistingAIButton(UIView *view) {
    UIView *existing =
        [view viewWithTag:DKAIButtonTag];

    return [existing isKindOfClass:[UIButton class]]
        ? (UIButton *)existing
        : nil;
}

static void DKInstallAIButton(UIView *toolbar) {
    UIButton *button =
        DKExistingAIButton(toolbar);

    if (!button) {
        button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        button.tag = DKAIButtonTag;

        [button setTitle:@"AI"
                forState:UIControlStateNormal];

        [button setTitleColor:UIColor.whiteColor
                     forState:UIControlStateNormal];

        button.titleLabel.font =
            [UIFont systemFontOfSize:12
                              weight:UIFontWeightBold];

        button.backgroundColor =
            [UIColor colorWithRed:0.23
                            green:0.19
                             blue:0.32
                            alpha:0.98];

        button.layer.cornerRadius = 10;
        button.accessibilityLabel = @"Deaf AI Fix";

        [button addTarget:[DKActions shared]
                   action:@selector(tapAI:)
         forControlEvents:UIControlEventTouchUpInside];

        UILongPressGestureRecognizer *hold =
            [[UILongPressGestureRecognizer alloc]
                initWithTarget:[DKActions shared]
                        action:@selector(holdAI:)];

        hold.minimumPressDuration = 0.55;

        [button addGestureRecognizer:hold];

        [toolbar addSubview:button];
    }

    CGFloat height =
        MAX(28, MIN(36, toolbar.bounds.size.height - 6));

    button.frame =
        CGRectMake(3,
                   MAX(2, (toolbar.bounds.size.height - height) * 0.5),
                   45,
                   height);

    [toolbar bringSubviewToFront:button];
}

static void DKToolbarLayout(id self, SEL _cmd) {
    if (DKToolbarLayoutOriginal) {
        ((void(*)(id,SEL))
            DKToolbarLayoutOriginal)(self, _cmd);
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

    ((void(*)(id,SEL,id,NSString*,NSString*,CGRect,CGContextRef,NSString *))
        DKSpaceOriginal)
        (self,
         _cmd,
         key,
         nil,
         @"EN IT",
         frame,
         context,
         attribute);
}

static void DKHideBlockedToolCells(UIView *root) {
    NSArray *blocked = @[
        @"rewards",
        @"microsoft rewards",
        @"messages",
        @"messaggi",
        @"copilot"
    ];

    for (UIView *sub in root.subviews) {

        NSString *visible =
            DKVisibleText(sub);

        if ([sub isKindOfClass:[UICollectionViewCell class]]
            && DKContainsAny(visible, blocked)) {

            sub.hidden = YES;
            sub.alpha = 0;
            sub.userInteractionEnabled = NO;

        } else {
            DKHideBlockedToolCells(sub);
        }
    }
}

static void DKMenuAdded(id self, SEL _cmd) {
    if (DKMenuAddedOriginal) {
        ((void(*)(id,SEL))
            DKMenuAddedOriginal)(self, _cmd);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:@selector(view)]) {
            UIView *view = [self valueForKey:@"view"];
            if ([view isKindOfClass:[UIView class]]) {
                DKHideBlockedToolCells(view);
            }
        }
    });
}

static Class DKClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (cls) return cls;
    }
    return Nil;
}

static IMP DKReplaceDirectOrAdd(Class cls,
                                SEL selector,
                                IMP replacement) {

    if (!cls) return NULL;

    Method method =
        class_getInstanceMethod(cls, selector);

    if (!method) return NULL;

    IMP original =
        method_getImplementation(method);

    const char *types =
        method_getTypeEncoding(method);

    class_addMethod(cls,
                    selector,
                    replacement,
                    types);

    Method direct =
        class_getInstanceMethod(cls, selector);

    method_setImplementation(direct,
                             replacement);

    return original;
}

static void DKInstallHooks(void) {

    Class renderer =
        DKClass(@[
            @"SKKeyboardKeyRenderer",
            @"SKKit.SKKeyboardKeyRenderer"
        ]);

    SEL spaceSelector =
        NSSelectorFromString(
            @"drawSpaceKey:withImage:enabledLangText:inFrame:inContext:attribute:");

    DKSpaceOriginal =
        DKReplaceDirectOrAdd(renderer,
                             spaceSelector,
                             (IMP)DKDrawSpace);

    Class toolbar =
        DKClass(@[
            @"SKCandidateToolbarView",
            @"SKKit.SKCandidateToolbarView"
        ]);

    DKToolbarLayoutOriginal =
        DKReplaceDirectOrAdd(toolbar,
                             @selector(layoutSubviews),
                             (IMP)DKToolbarLayout);

    Class menu =
        DKClass(@[
            @"SKToolBarMenuController",
            @"SKKit.SKToolBarMenuController"
        ]);

    DKMenuAddedOriginal =
        DKReplaceDirectOrAdd(menu,
                             @selector(moduleWasAdded),
                             (IMP)DKMenuAdded);
}

__attribute__((constructor))
static void DKStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DKInstallHooks();
    });
}
