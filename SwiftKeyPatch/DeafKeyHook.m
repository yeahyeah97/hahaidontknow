#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static const NSInteger DKAIButtonTag = 0xD311;
static const NSInteger DKToastTag = 0xD312;
static IMP DKSpaceOriginal = NULL;
static IMP DKToolbarLayoutOriginal = NULL;
static IMP DKMenuCellOriginal = NULL;
static IMP DKMenuSizeOriginal = NULL;

static NSString *DKLower(NSString *s) {
    return [s isKindOfClass:[NSString class]] ? s.lowercaseString : @"";
}

static BOOL DKContainsAny(NSString *value, NSArray<NSString *> *needles) {
    NSString *lower = DKLower(value);
    for (NSString *n in needles) if ([lower containsString:n.lowercaseString]) return YES;
    return NO;
}

static NSString *DKVisibleText(UIView *v) {
    NSMutableString *s = [NSMutableString string];
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)v).text;
        if (t.length) [s appendFormat:@" %@", t];
    }
    if ([v isKindOfClass:[UIButton class]]) {
        NSString *t = [((UIButton *)v) titleForState:UIControlStateNormal];
        if (t.length) [s appendFormat:@" %@", t];
    }
    if (v.accessibilityLabel.length) [s appendFormat:@" %@", v.accessibilityLabel];
    for (UIView *sub in v.subviews) [s appendString:DKVisibleText(sub)];
    return s;
}

static BOOL DKShouldHideToolCell(UIView *cell) {
    return DKContainsAny(DKVisibleText(cell), @[
        @"rewards", @"microsoft rewards", @"messages", @"messaggi",
        @"copilot", @"compose", @"componi", @"chat", @"tone", @"tono",
        @"editor", @"create", @"crea", @"images", @"immagini", @"meme"
    ]);
}

static UIInputViewController *DKInputController(UIResponder *r) {
    UIResponder *cur = r;
    while (cur) {
        if ([cur isKindOfClass:[UIInputViewController class]]) return (UIInputViewController *)cur;
        cur = cur.nextResponder;
    }
    return nil;
}

static void DKToast(UIView *root, NSString *text) {
    if (!root) return;
    [[root viewWithTag:DKToastTag] removeFromSuperview];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 42, MAX(100, root.bounds.size.width - 24), 34)];
    label.tag = DKToastTag;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = text;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.96];
    label.layer.cornerRadius = 10;
    label.layer.masksToBounds = YES;
    [root addSubview:label];
    [root bringSubviewToFront:label];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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

static void DKGemini(NSString *apiKey, NSString *instruction, NSString *text, NSInteger maxTokens, void (^completion)(NSString *)) {
    NSURL *url = [NSURL URLWithString:@"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 20;
    [req setValue:apiKey forHTTPHeaderField:@"x-goog-api-key"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{
        @"systemInstruction": @{@"parts": @[@{@"text": instruction}]},
        @"contents": @[@{@"role": @"user", @"parts": @[@{@"text": text}]}],
        @"generationConfig": @{@"maxOutputTokens": @(maxTokens)}
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *result = nil;
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (!error && status >= 200 && status < 300 && data.length) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *candidates = json[@"candidates"];
            NSDictionary *content = [candidates.firstObject objectForKey:@"content"];
            NSArray *parts = content[@"parts"];
            NSString *raw = [parts.firstObject objectForKey:@"text"];
            if ([raw isKindOfClass:[NSString class]]) {
                result = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    }] resume];
}

static BOOL DKNeedsDeepPass(NSString *text) {
    NSString *lower = text.lowercaseString;
    NSArray *markers = @[@"spero", @"voglio", @"vorrei", @"forse", @" se ", @"perché", @"penso", @"credo",
                         @"hope", @"want", @"wish", @"maybe", @" if ", @"because", @"think"];
    for (NSString *m in markers) if ([lower containsString:m]) return YES;
    NSArray *parts = [text componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    NSInteger words = 0, shortWords = 0;
    for (NSString *w in parts) {
        if (!w.length) continue;
        words++;
        if (w.length <= 3) shortWords++;
    }
    if (words <= 5) return YES;
    NSInteger punctuation = 0;
    NSCharacterSet *punctSet = [NSCharacterSet characterSetWithCharactersInString:@".,!?;:"];
    for (NSUInteger i = 0; i < text.length; i++) if ([punctSet characterIsMember:[text characterAtIndex:i]]) punctuation++;
    return punctuation == 0 && shortWords >= MAX(3, words / 3);
}

static NSString *DKSemanticPrompt(void) {
    return @"Analyze the fragmented message before rewriting it. Build a compact semantic map: "
    "SPEAKER_GOAL; ENTITIES_AND_REFERENCES; SEMANTIC_ROLES (who does/thinks/wants what, to/about whom, when, where, why, condition and result); "
    "RELATION_GRAPH; MODALITY_SCOPE; DESIRED_OR_FEARED_OUTCOME; EVENT_STATUS (fact, plan, hypothetical, possibility, wish, fear, command, question, unknown); "
    "POLARITY; IMPLICIT_QUESTIONS; OMITTED_LINKS; UNCERTAINTY. "
    "Do not merge nearby fragments automatically. Preserve negation, conditions and actor/target relationships. Do not invent facts. Be concise.";
}

static NSString *DKFinalPrompt(void) {
    return @"Rewrite the original fragmented message into the most likely natural message using the semantic map as an interpretation aid. "
    "The original text is the source of truth. Preserve language, names, places, numbers, slang, tone and concrete facts. "
    "Preserve who does/thinks/wants/asks what, toward whom or what, and preserve negation, tense, conditions, causes and whether each event is a fact, wish, fear, possibility, question, command or plan. "
    "If there are multiple intentions, keep them separate. Turn implied questions into natural explicit questions only when supported. "
    "Do not invent facts. If a relation is uncertain, use conservative wording. Output ONLY the reconstructed message.";
}

static void DKReplaceContext(UIInputViewController *controller, NSString *context, NSString *replacement) {
    id<UITextDocumentProxy> proxy = controller.textDocumentProxy;
    __block NSInteger count = 0;
    [context enumerateSubstringsInRange:NSMakeRange(0, context.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(__unused NSString *substring, __unused NSRange subRange, __unused NSRange enclosingRange, __unused BOOL *stop) {
        count++;
    }];
    for (NSInteger i = 0; i < count; i++) [proxy deleteBackward];
    [proxy insertText:replacement];
}

static void DKRunFix(UIButton *button) {
    UIInputViewController *controller = DKInputController(button);
    UIView *root = controller.view ?: button.superview;
    NSString *key = DKAPIKey();
    if (!key.length) {
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
        NSString *quick = @"Correct spelling, grammar, punctuation and obvious typing mistakes. Preserve exact meaning, language, names, slang, tone, negation, tense and who is doing what to whom. Return only corrected text.";
        DKGemini(key, quick, context, 320, finish);
    } else {
        DKGemini(key, DKSemanticPrompt(), context, 260, ^(NSString *map) {
            if (!map.length) {
                DKGemini(key, DKFinalPrompt(), context, 420, finish);
                return;
            }
            NSString *combined = [NSString stringWithFormat:@"ORIGINAL TEXT:\n%@\n\nSEMANTIC MAP:\n%@", context, map];
            DKGemini(key, DKFinalPrompt(), combined, 420, finish);
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
    static DKActionTarget *x;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ x = [DKActionTarget new]; });
    return x;
}
- (void)aiTap:(UIButton *)sender { DKRunFix(sender); }
- (void)aiHold:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) DKSaveAPIKeyFromClipboard(sender.view);
}
@end

static void DKInstallAIButton(UIView *view) {
    UIButton *button = (UIButton *)[view viewWithTag:DKAIButtonTag];
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = DKAIButtonTag;
        [button setTitle:@"AI" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        button.backgroundColor = [UIColor colorWithRed:0.25 green:0.20 blue:0.35 alpha:0.98];
        button.layer.cornerRadius = 10;
        button.accessibilityLabel = @"Deaf AI Fix";
        [button addTarget:[DKActionTarget shared] action:@selector(aiTap:) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:[DKActionTarget shared] action:@selector(aiHold:)];
        hold.minimumPressDuration = 0.55;
        [button addGestureRecognizer:hold];
        [view addSubview:button];
    }
    CGFloat h = MAX(30, MIN(38, view.bounds.size.height - 6));
    button.frame = CGRectMake(4, MAX(2, (view.bounds.size.height - h) * 0.5), 44, h);
    [view bringSubviewToFront:button];
}

static void DKToolbarLayout(id self, SEL _cmd) {
    if (DKToolbarLayoutOriginal) ((void(*)(id,SEL))DKToolbarLayoutOriginal)(self,_cmd);
    if ([self isKindOfClass:[UIView class]]) DKInstallAIButton((UIView *)self);
}

static void DKDrawSpace(id self, SEL _cmd, id key, NSString *imageName, NSString *languages, CGRect frame, CGContextRef context, NSString *attribute) {
    if (!DKSpaceOriginal) return;
    ((void(*)(id,SEL,id,NSString*,NSString*,CGRect,CGContextRef,NSString*))DKSpaceOriginal)(self,_cmd,key,nil,@"EN IT",frame,context,attribute);
}

static NSMutableSet *DKHiddenIndexPaths(id controller) {
    static char associationKey;
    NSMutableSet *set = objc_getAssociatedObject(controller, &associationKey);
    if (!set) {
        set = [NSMutableSet set];
        objc_setAssociatedObject(controller, &associationKey, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return set;
}

static id DKMenuCell(id self, SEL _cmd, UICollectionView *collection, NSIndexPath *indexPath) {
    id cell = ((id(*)(id,SEL,id,id))DKMenuCellOriginal)(self,_cmd,collection,indexPath);
    if ([cell isKindOfClass:[UIView class]] && DKShouldHideToolCell(cell)) {
        [DKHiddenIndexPaths(self) addObject:indexPath];
        UIView *v = (UIView *)cell;
        v.hidden = YES;
        v.alpha = 0;
        v.userInteractionEnabled = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ [collection.collectionViewLayout invalidateLayout]; });
    }
    return cell;
}

static CGSize DKMenuSize(id self, SEL _cmd, UICollectionView *collection, UICollectionViewLayout *layout, NSIndexPath *indexPath) {
    if ([DKHiddenIndexPaths(self) containsObject:indexPath]) return CGSizeMake(0.1, 0.1);
    return ((CGSize(*)(id,SEL,id,id,id))DKMenuSizeOriginal)(self,_cmd,collection,layout,indexPath);
}

static Class DKClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        Class c = NSClassFromString(name);
        if (c) return c;
    }
    return Nil;
}

static void DKInstall(void) {
    Class renderer = DKClass(@[@"SKKeyboardKeyRenderer", @"SKKit.SKKeyboardKeyRenderer"]);
    SEL spaceSel = NSSelectorFromString(@"drawSpaceKey:withImage:enabledLangText:inFrame:inContext:attribute:");
    Method spaceMethod = class_getInstanceMethod(renderer, spaceSel);
    if (spaceMethod) {
        DKSpaceOriginal = method_getImplementation(spaceMethod);
        method_setImplementation(spaceMethod, (IMP)DKDrawSpace);
    }

    Class toolbarView = DKClass(@[@"SKCandidateToolbarView", @"SKKit.SKCandidateToolbarView"]);
    Method layout = class_getInstanceMethod(toolbarView, @selector(layoutSubviews));
    if (layout) {
        DKToolbarLayoutOriginal = method_getImplementation(layout);
        method_setImplementation(layout, (IMP)DKToolbarLayout);
    }

    Class menu = DKClass(@[@"SKToolBarMenuController", @"SKKit.SKToolBarMenuController"]);
    SEL cellSel = @selector(collectionView:cellForItemAtIndexPath:);
    Method cellMethod = class_getInstanceMethod(menu, cellSel);
    if (cellMethod) {
        DKMenuCellOriginal = method_getImplementation(cellMethod);
        method_setImplementation(cellMethod, (IMP)DKMenuCell);
    }

    SEL sizeSel = @selector(collectionView:layout:sizeForItemAtIndexPath:);
    Method sizeMethod = class_getInstanceMethod(menu, sizeSel);
    if (sizeMethod) {
        DKMenuSizeOriginal = method_getImplementation(sizeMethod);
        method_setImplementation(sizeMethod, (IMP)DKMenuSize);
    }
}

__attribute__((constructor))
static void DKStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ DKInstall(); });
}
