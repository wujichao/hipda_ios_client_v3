//
//  HPAppDelegate.m
//  HiPDA
//
//  Created by wujichao on 13-11-6.
//  Copyright (c) 2013年 wujichao. All rights reserved.
//

#import "HPAppDelegate.h"
#import "SWRevealViewController.h"
#import <AFNetworking.h>
#import "HPAccount.h"
#import "HPHttpClient.h"
#import "HPRearViewController.h"
#import "HPSetting.h"
#import "HPDatabase.h"
#import "HPURLProtocol.h"
#import "HPHotPatch.h"
#import "HPCrashReport.h"
#import "HPPushService.h"
#import <SDWebImage/SDImageCache.h>
#import "HPBackgroundFetchService.h"
#import "HPRouter.h"
#import "HPLabService.h"

#define UM_APP_KEY (@"543b7fe7fd98c59dcb0418ef")
#define UM_APP_KEY_DEV (UM_APP_KEY)

@interface HPAppDelegate()

@property (nonatomic, strong) HPRearViewController *rearViewController;

@end

@implementation HPAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    DDLogInfo(@"launching...");
    
    [HPCrashReport setUp];
    
    [[HPHotPatch shared] check];
    
    //
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    //
    NSURLCache *URLCache = [[NSURLCache alloc] initWithMemoryCapacity:10 * 1024 * 1024 diskCapacity:50 * 1024 * 1024 diskPath:nil];
    [NSURLCache setSharedURLCache:URLCache];
    
    //
    NSData *cookiesdata = [[NSUserDefaults standardUserDefaults] objectForKey:@"kUserDefaultsCookie"];
    if([cookiesdata length]) {
        NSArray *cookies = [NSKeyedUnarchiver unarchiveObjectWithData:cookiesdata];
        NSHTTPCookie *cookie;
        for (cookie in cookies) {
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:cookie];
        }
    }
    
    // NetworkActivityIndicator
    [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];
    
    
    // defualt setting
    //
    [Setting loadSetting];
    
    
    //
    [HPURLProtocol registerURLProtocolIfNeed];
    
    
    // reachabilty
    //
    HPHttpClient *client = [HPHttpClient sharedClient];
    [client setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        NSArray *names = @[@"Unknown ", @"NotReachable", @"WWAN", @"Wifi"];
        NSString *s = [names objectAtIndex:(status+1) % names.count];
        NSLog(@"ReachabilityStatusChange %@", s);
    }];
    
    
    //
    [HPDatabase prepareDb];
    
    //
    _rearViewController = [HPRearViewController sharedRearVC];
    [_rearViewController themeUpdate];
    UINavigationController *frontNavigationController = [HPRearViewController threadNavViewController];
    
	SWRevealViewController *revealController = [[SWRevealViewController alloc] initWithRearViewController:_rearViewController frontViewController:frontNavigationController];
    
    revealController.rearViewRevealWidth = 100.f;
    revealController.rearViewRevealOverdraw = 0.f;
    revealController.frontViewShadowRadius = 0.f;

    revealController.delegate = _rearViewController;
    
    self.viewController = revealController;
    self.window.rootViewController = self.viewController;
    self.window.backgroundColor = [UIColor blackColor];
    [self.window makeKeyAndVisible];
    
    if ([application applicationState] == UIApplicationStateBackground) {
        // backgroudFetch launching...
        DDLogInfo(@"backgroudFetch launching...");
    } else {
        [[HPAccount sharedHPAccount] startCheckWithDelay:10.f];
        DDLogInfo(@"normal launching...");
    }
    
    UILocalNotification *localNotification =
    [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];
    if (localNotification) {
        [[HPBackgroundFetchService instance] didReciveLocalNotification:localNotification];
    }
    
    NSDictionary *userInfo = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (userInfo) {
        [HPPushService didRecieveRemoteNotification:userInfo fromLaunching:YES];
    }

    // 友盟统计
    [self setupAnalytics];
    
    // 实验室
    [HPLabService instance];
    
    DDLogInfo(@"finish launching");
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    
    //
    NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL: [NSURL URLWithString:HP_BASE_URL]];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:cookies];
    //NSLog(@"save cookies %@", data);
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"kUserDefaultsCookie"];
    
    HPCrashLog(@"-> applicationWillResignActive");
    DDLogInfo(@"[APP] applicationWillResignActive");
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    
    // reset applicationIconBadgeNumber
    application.applicationIconBadgeNumber  = [[HPAccount sharedHPAccount] badgeNumber];
    
    HPCrashLog(@"-> applicationDidEnterBackground");
    DDLogInfo(@"[APP] applicationDidEnterBackground");
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.

    HPCrashLog(@"-> applicationWillEnterForeground");
    DDLogInfo(@"[APP] applicationWillEnterForeground");
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // 启动时执行的任务, 延迟到启动后
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[HPBackgroundFetchService instance] setupBgFetch];
        [HPPushService doRegisterIfGranted];
        
        // SDWebImage 缓存时长 默认一周, 改成三天
        [[SDImageCache sharedImageCache] setMaxCacheAge:60 * 60 * 24 * 3];
        // SDWebImage 最大缓存大小, 默认不限, 改成500m
        [[SDImageCache sharedImageCache] setMaxCacheSize:500 * 1024 * 1024];
        
        [Flurry trackUserIfNeeded];
    });
    
    [[HPRouter instance] checkPasteboard];
    
    HPCrashLog(@"-> applicationDidBecomeActive");
    DDLogInfo(@"[APP] applicationDidBecomeActive");
}

- (void)setupAnalytics
{
    BOOL dataTrackingEnable = [Setting boolForKey:HPSettingDataTrackEnable];
    if (dataTrackingEnable) {
       
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    DDLogInfo(@"[APP] applicationWillTerminate");
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    [[HPBackgroundFetchService instance] didReciveLocalNotification:notification];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    [HPPushService didRegisterForRemoteNotificationsWithDeviceToken:deviceToken error:nil];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    [HPPushService didRegisterForRemoteNotificationsWithDeviceToken:nil error:error];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    BOOL fromLaunching = YES;
    if (application.applicationState == UIApplicationStateActive) {
        fromLaunching = NO;
    }
    [HPPushService didRecieveRemoteNotification:userInfo fromLaunching:fromLaunching];
}

//http://stackoverflow.com/questions/17276898/mpmovieplayerviewcontroller-allow-landscape-mode
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window
{
    UIViewController *vc = [self hp_topViewController];
    if (IOS9_2_OR_LATER && [vc isKindOfClass:NSClassFromString(@"SFSafariViewController")]) {
        if (vc.isBeingDismissed) {
            return UIInterfaceOrientationMaskPortrait;
        }
        else {
            return UIInterfaceOrientationMaskAllButUpsideDown;
        }
    } else {
        return UIInterfaceOrientationMaskPortrait;
    }
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    DDLogInfo(@"[APP] performFetch");
    [[HPBackgroundFetchService instance] application:application performFetchWithCompletionHandler:completionHandler];
}

#pragma mark - topViewController
//http://stackoverflow.com/questions/6131205/iphone-how-to-find-topmost-view-controller/20515681#20515681
- (UIViewController*)hp_topViewController {
    return [self topViewControllerWithRootViewController:[UIApplication sharedApplication].keyWindow.rootViewController];
}

- (UIViewController*)topViewControllerWithRootViewController:(UIViewController*)rootViewController {
    
    if ([rootViewController isKindOfClass:[SWRevealViewController class]]) {
        SWRevealViewController *v = (SWRevealViewController *)rootViewController;
        return [self topViewControllerWithRootViewController:v.frontViewController];
    } else if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController* tabBarController = (UITabBarController*)rootViewController;
        return [self topViewControllerWithRootViewController:tabBarController.selectedViewController];
    } else if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController* navigationController = (UINavigationController*)rootViewController;
        return [self topViewControllerWithRootViewController:navigationController.visibleViewController];
    } else if (rootViewController.presentedViewController) {
        UIViewController* presentedViewController = rootViewController.presentedViewController;
        return [self topViewControllerWithRootViewController:presentedViewController];
    } else {
        return rootViewController;
    }
}

@end
