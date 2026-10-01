#import <UIKit/UIKit.h>

@interface DKAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation DKAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.025 blue:0.055 alpha:1.0];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"DeafKey";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:38 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"SwiftKey engine · Deaf AI";
    subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.62];
    subtitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    subtitle.textAlignment = NSTextAlignmentCenter;

    UILabel *body = [UILabel new];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.numberOfLines = 0;
    body.textAlignment = NSTextAlignmentLeft;
    body.textColor = [UIColor colorWithWhite:1 alpha:0.82];
    body.font = [UIFont systemFontOfSize:16];
    body.text =
        @"1. Open iOS Settings\n"
         "2. General → Keyboard → Keyboards\n"
         "3. Add New Keyboard → DeafKey\n"
         "4. Enable Allow Full Access\n\n"
         "In the keyboard:\n"
         "• Tap AI = Deaf AI Fix\n"
         "• Hold AI = save Gemini key from clipboard\n"
         "• EN IT stays on the spacebar";

    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
    settings.translatesAutoresizingMaskIntoConstraints = NO;
    [settings setTitle:@"Open Settings" forState:UIControlStateNormal];
    [settings setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    settings.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    settings.backgroundColor = [UIColor colorWithRed:0.42 green:0.22 blue:0.78 alpha:1.0];
    settings.layer.cornerRadius = 14;
    [settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];

    [vc.view addSubview:title];
    [vc.view addSubview:subtitle];
    [vc.view addSubview:body];
    [vc.view addSubview:settings];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:64],
        [title.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:24],
        [title.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-24],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [subtitle.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:24],
        [subtitle.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-24],

        [body.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:48],
        [body.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:30],
        [body.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-30],

        [settings.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:30],
        [settings.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-30],
        [settings.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-36],
        [settings.heightAnchor constraintEqualToConstant:52]
    ]];

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)openSettings {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([DKAppDelegate class]));
    }
}
