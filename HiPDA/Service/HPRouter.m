//
//  HPRouter.m
//  HiPDA
//
//  Created by Jiangfan on 2018/8/19.
//  Copyright © 2018年 wujichao. All rights reserved.
//

#import "HPRouter.h"
#import "UIAlertView+Blocks.h"
#import "NSString+Additions.h"
#import "SWRevealViewController.h"
#import "NSRegularExpression+HP.h"
#import "HPAppDelegate.h"
#import "HPThread.h"
#import "HPPostViewController.h"
#import "HPRearViewController.h"
#import "HPSubViewController.h"
#import "HPUserViewController.h"
#import "HPSetting.h"

@implementation HPRouter

+ (instancetype)instance
{
    static dispatch_once_t once;
    static HPRouter *singleton;
    dispatch_once(&once, ^ { singleton = [[HPRouter alloc] init]; });
    return singleton;
}

- (void)checkPasteboard
{
    if (@available(iOS 14.0, *)) {
        NSSet *patterns = [[NSSet alloc] initWithObjects:UIPasteboardDetectionPatternProbableWebURL, nil];
        [[UIPasteboard generalPasteboard] detectPatternsForPatterns:patterns completionHandler:^(NSSet<UIPasteboardDetectionPattern> *result, NSError *error) {
            if ([result containsObject:UIPasteboardDetectionPatternProbableWebURL]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self checkPasteboard0];
                });
            }
        }];
        return;
    }
    
    //[self routeTo:@{@"tid": @"1831924"}];
    [self checkPasteboard0];
}

- (void)checkPasteboard0 {
    UIPasteboard *appPasteBoard = [UIPasteboard generalPasteboard];
    NSString *content = appPasteBoard.string;
    if (!content.length) {
        return;
    }
    
    static NSString *PasteboardKey = @"PasteboardHistoryKey";
    
    // 去重
    static NSMutableSet *history = nil;
    if (!history) {
        history = [[NSMutableSet alloc] init];
        NSArray *a = [NSStandardUserDefaults objectForKey:PasteboardKey];
        for (NSString *k in a) {
            [history addObject:k];
        }
    }
    
    
    // match
    // NEW_DOMAIN
    NSString *pattern = [NSString stringWithFormat:@"%@/forum/viewthread\\.php\\?tid=(\\d+)", HP_BASE_HOST];
    NSString *tid = [RX(pattern) firstMatchValue:content];
    if (tid) {
        
        NSString *key = [@"tid_" stringByAppendingString:tid];
        if ([history containsObject:key]) {
            DDLogInfo(@"history hit %@", content);
            return;
        } else {
            [history addObject:key];
            [NSStandardUserDefaults addObjectToArray:key forKey:PasteboardKey];
        }
        
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"" message:[NSString stringWithFormat:@"是否进入id为%@的帖子", tid] delegate:nil cancelButtonTitle:@"取消" otherButtonTitles:@"进入", nil];
        [alertView showWithHandler:^(UIAlertView *alertView, NSInteger buttonIndex) {
            if (buttonIndex != alertView.cancelButtonIndex) {
                [Flurry logEvent:@"Pasteboard Tid"];
                [self routeTo:@{@"tid": tid}];
            }
        }];
        return;
    }
    // anything else
}

#pragma mark -
- (void)routeTo:(NSDictionary *)path
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DDLogInfo(@"routeTo %@", path);
        
        HPAppDelegate *app = (HPAppDelegate *)[[UIApplication sharedApplication] delegate];
        SWRevealViewController *revealController = app.viewController;
        UINavigationController *frontNavigationController = (id)revealController.frontViewController;
        
        // dismiss presentedViewController
        UIViewController *presentedViewController = revealController.rearViewController.presentedViewController;
        presentedViewController = presentedViewController ?: frontNavigationController.presentedViewController;
        presentedViewController = presentedViewController ?: revealController.presentedViewController;
        if (presentedViewController) {
            [presentedViewController dismissViewControllerAnimated:NO
                                                        completion:nil];
        }
        
        // close drawer
        if (revealController.frontViewPosition != FrontViewPositionLeft) {
            [revealController setFrontViewPosition:FrontViewPositionLeft animated:YES];
        }
        
        if ([path objectForKey:@"fid"]) { //板块
            ;
        } else if ([path objectForKey:@"tid"]) { //帖子
            
            HPThread *t = [HPThread new];
            t.tid = [path[@"tid"] integerValue];
            UIViewController *readVC = [[PostViewControllerClass() alloc] initWithThread:t];
            [frontNavigationController pushViewController:readVC animated:YES];
            
        } else if ([path objectForKey:@"pid"]) { //回复
            ;
        } else if ([path objectForKey:@"userCenter"]) {
            HPRearViewController *rearViewController = [HPRearViewController sharedRearVC];
            NSString *target = [path objectForKey:@"userCenter"];
            if ([target isEqualToString:@"sub"]) {
                [rearViewController switchTo:HPSubViewController.class];
            }
        } else if ([path objectForKey:@"uid"]) { //用户
            HPUserViewController *uvc = [HPUserViewController new];
            uvc.uid = [path[@"uid"] integerValue];
            [frontNavigationController pushViewController:uvc animated:YES];
        } else {
            ;
        }
    });
}

@end
