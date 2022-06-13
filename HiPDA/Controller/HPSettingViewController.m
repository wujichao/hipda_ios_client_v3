//
//  HPSettingViewController.m
//  HiPDA
//
//  Created by wujichao on 13-11-20.
//  Copyright (c) 2013年 wujichao. All rights reserved.
//
#import "HPThread.h"
#import "HPPostViewController.h"
#import "HPSettingViewController.h"
#import "HPSetForumsViewController.h"
#import "HPRearViewController.h"
#import "HPBgFetchViewController.h"
#import "HPSetStupidBarController.h"
#import "HPSetImageSizeFilterViewController.h"
#import "HPBlockListViewController.h"
#import "HPLoginViewController.h"
#import "HPAppDelegate.h"
#import "HPLoggerViewerController.h"
#import "HPLabGuideViewController.h"

#import "MultilineTextItem.h"
#import "HPSetting.h"
#import "HPAccount.h"
#import "HPTheme.h"
#import "HPApiConfig.h"

#import "NSUserDefaults+Convenience.h"
#import "RETableViewManager.h"
#import "RETableViewOptionsController.h"
#import <SVProgressHUD.h>
#import "SWRevealViewController.h"
#import "UIAlertView+Blocks.h"
#import <SDWebImage/SDImageCache.h>
#import "HPCrashReport.h"
#import "HPURLProtocol.h"
#import "HPLogger.h"
#import "HPHttpClient.h"
#import "HPLabService.h"
#import "HPBlockThreadListViewController.h"

// mail
#import <MessageUI/MFMailComposeViewController.h>
#import "sys/utsname.h"

#define VERSION ([[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"])
#define BUILD ([[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"])

#ifdef DEBUG
    #define DEBUG_MODE 1
#else
    #define DEBUG_MODE 0
#endif

@interface HPSettingViewController ()

@property (strong, nonatomic) RETableViewManager *manager;
@property (strong, nonatomic) RETableViewSection *preferenceSection;
@property (strong, nonatomic) RETableViewSection *imageSection;
@property (strong, nonatomic) RETableViewSection *dataTrackingSection;
@property (strong, nonatomic) RETableViewSection *aboutSection;

@end

@implementation HPSettingViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"设置";
    [self.tableView setBackgroundColor:[HPTheme backgroundColor]];

    UIBarButtonItem *closeButtonItem = [
                                         [UIBarButtonItem alloc] initWithTitle:@"完成"
                                         style:UIBarButtonItemStylePlain
                                         target:self action:@selector(close:)];
    self.navigationItem.leftBarButtonItem = closeButtonItem;
    
    // clear btn
    UIBarButtonItem *clearButtonItem = [
                                        [UIBarButtonItem alloc] initWithTitle:@"重置"
                                        style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(reset:)];
    self.navigationItem.rightBarButtonItem = clearButtonItem;
    

    // Create manager
    //
    self.manager = [[RETableViewManager alloc] initWithTableView:self.tableView delegate:self];
    
    
    
    self.preferenceSection = [self addPreferenceControls];
    self.imageSection = [self addImageControls];
    
//    [self addLabSection];
    [self addBgFetchSection];

    self.dataTrackingSection = [self addDataTrackingControls];
    self.aboutSection = [self addAboutControls];
    
    @weakify(self);
    RETableViewSection *logoutSection = [RETableViewSection sectionWithHeaderTitle:nil];
    RETableViewItem *logoutItem = [RETableViewItem itemWithTitle:@"登出" accessoryType:UITableViewCellAccessoryNone selectionHandler:^(RETableViewItem *item) {
        
        [UIAlertView showConfirmationDialogWithTitle:@"登出"
                                             message:@"您确定要登出当前账号吗?\n该账号的设置不会丢失"
                                             handler:^(UIAlertView *alertView, NSInteger buttonIndex)
         {
             @strongify(self);
             if (buttonIndex == [alertView cancelButtonIndex]) {
                 ;
             } else {
                 
                 [Flurry logEvent:@"Account Logout"];
                 [[HPAccount sharedHPAccount] logout];
                 [self closeAndShowLoginVC];
             }
         }];
        
        [item deselectRowAnimated:YES];
    }];
    logoutItem.textAlignment = NSTextAlignmentCenter;
    [logoutSection addItem:logoutItem];
    [self.manager addSection:logoutSection];
    
    RETableViewSection *versionSection = [RETableViewSection section];
    RETableViewItem *versionItem = [RETableViewItem itemWithTitle:[NSString stringWithFormat:@"版本 %@ (%@)", VERSION, BUILD] accessoryType:UITableViewCellAccessoryNone selectionHandler:^(RETableViewItem *item) {
        
        [item deselectRowAnimated:YES];
    }];
    versionItem.selectionStyle = UITableViewCellSelectionStyleNone;
    versionItem.textAlignment = NSTextAlignmentCenter;
    [versionSection addItem:versionItem];
    
    [self.manager addSection:versionSection];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc {
    NSLog(@" -- dealloc");
}

- (RETableViewSection *)addPreferenceControls {
    
    RETableViewSection *section = [RETableViewSection sectionWithHeaderTitle:nil];

    //
    BOOL isNightMode = [Setting boolForKey:HPSettingNightMode];
    @weakify(self);
    REBoolItem *isNightModeItem = [REBoolItem itemWithTitle:@"夜间模式" value:isNightMode switchValueChangeHandler:^(REBoolItem *item) {
        
        NSLog(@"isNightMode Value: %@", item.value ? @"YES" : @"NO");
        [Setting saveBool:item.value forKey:HPSettingNightMode];

        if (item.value) {
            ;
        } else {
            ;
        }
        
        [[HPRearViewController sharedRearVC] themeDidChanged];
        @strongify(self);
        self.navigationController.navigationBar.barStyle = [UINavigationBar appearance].barStyle;
        [Flurry logEvent:@"Setting ToggleDarkMode" withParameters:@{@"flag":@(item.value)}];
    }];
    
    // isShowAvatar
    //
    BOOL isShowAvatar = [Setting boolForKey:HPSettingShowAvatar];
    REBoolItem *isShowAvatarItem = [REBoolItem itemWithTitle:@"显示头像" value:isShowAvatar switchValueChangeHandler:^(REBoolItem *item) {
        
        NSLog(@"isShowAvatar Value: %@", item.value ? @"YES" : @"NO");
        [Setting saveBool:item.value forKey:HPSettingShowAvatar];
        
        if (item.value) {
            ;
        } else {
            ;
        }
        
        
        [[HPRearViewController sharedRearVC] themeDidChanged];
        
        [Flurry logEvent:@"Setting ToggleShowAvatar" withParameters:@{@"flag":@(item.value)}];
    }];
    
    // isShowAvatar
    //
    BOOL isOnlineEnv = [HPApiConfig config].online;
    REBoolItem *isOnlineEnvItem = [REBoolItem itemWithTitle:@"online?" value:isOnlineEnv switchValueChangeHandler:^(REBoolItem *item) {
        [HPApiConfig config].online = item.value;
    }];
  
    //
    //
    NSString *postTail = [Setting objectForKey:HPSettingTail];
    RETextItem *postTailText = [RETextItem itemWithTitle:@"小尾巴" value:postTail placeholder:@"留空"];
    
    postTailText.returnKeyType = UIReturnKeyDone;
    postTailText.onEndEditing = ^(RETextItem *item) {
        NSLog(@"setPostTail _%@_", item.value);
        
        NSString *msg = [Setting isPostTailAllow:item.value];
        if (!msg) {
            [Setting setPostTail:item.value];
            
            [SVProgressHUD showSuccessWithStatus:@"已保存"];
        } else {
            [SVProgressHUD showErrorWithStatus:msg];
        }
        
        [Flurry logEvent:@"Setting SetTail" withParameters:@{@"text":item.value}];
    };
    
    // 域名
    //
    RETextItem *domainSettingText = [RETextItem itemWithTitle:@"域名" value:HP_BASE_HOST placeholder:HP_WWW_BASE_HOST];
    
    domainSettingText.returnKeyType = UIReturnKeyDone;
    domainSettingText.onEndEditing = ^(RETextItem *item) {
        NSLog(@"domainSettingText _%@_", item.value);
        if (item.value.length > 0) {
            [Setting saveObject:item.value forKey:HPSettingBaseURL];
            [SVProgressHUD showSuccessWithStatus:@"已保存, 重启app后生效"];
        } else {
            [SVProgressHUD showErrorWithStatus:@"域名不能为空"];
        }
        
        [Flurry logEvent:@"Setting domainSettingText" withParameters:@{@"text":item.value}];
    };
    
    //
    //
    RETableViewItem *setForumItem = [RETableViewItem itemWithTitle:@"板块设定" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        @strongify(self);
        HPSetForumsViewController *setForumsViewController = [[HPSetForumsViewController alloc] initWithStyle:UITableViewStylePlain];
        [self.navigationController pushViewController:setForumsViewController animated:YES];
        [item deselectRowAnimated:YES];
        
        [Flurry logEvent:@"Setting EnterSetForum"];
    }];
    
    //
    //
    RETableViewItem *blockListItem = [RETableViewItem itemWithTitle:@"屏蔽列表" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        @strongify(self);
        [self.navigationController pushViewController:[[HPBlockListViewController alloc] initWithStyle:UITableViewStyleGrouped] animated:YES];
        [item deselectRowAnimated:YES];
        
        [Flurry logEvent:@"Setting EnterBlockList"];
    }];
    
    
    RETableViewItem *blockThreadListItem = [RETableViewItem itemWithTitle:@"不感兴趣的的帖子" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        @strongify(self);
        [self.navigationController pushViewController:[[HPBlockThreadListViewController alloc] initWithStyle:UITableViewStyleGrouped] animated:YES];
        [item deselectRowAnimated:YES];
        
        [Flurry logEvent:@"Setting EnterBlockThreadList"];
    }];
    
    // preferFav
    //
    BOOL isPreferNotice = [Setting boolForKey:HPSettingPreferNotice];
    REBoolItem *isPreferNoticeItem = [REBoolItem itemWithTitle:@"常用加关注" value:isPreferNotice switchValueChangeHandler:^(REBoolItem *item) {
        
        NSLog(@"HPSettingPreferNotice Value: %@", item.value ? @"YES" : @"NO");
        [Setting saveBool:item.value forKey:HPSettingPreferNotice];
        
        [Flurry logEvent:@"Setting TogglePreferNotice" withParameters:@{@"flag":@(item.value)}];
    }];
    
    // 发送后提示
    //
    __typeof (&*self) __weak weakSelf = self;
    BOOL isShowConfirm = [Setting boolForKey:HPSettingAfterSendShowConfirm];
    BOOL isAutoJump = [Setting boolForKey:HPSettingAfterSendJump];
    NSArray *options = @[@"跳转到刚发的回帖", @"留在原处", @"每次都询问"];
    NSInteger i = isShowConfirm?2:(isAutoJump?0:1);
    RERadioItem *afterSendConfirmItem = [RERadioItem itemWithTitle:@"回帖成功后" value:options[i] selectionHandler:^(RERadioItem *item) {
        
        [item deselectRowAnimated:YES];
        
        // Present options controller
        //
        RETableViewOptionsController *optionsController = [[RETableViewOptionsController alloc] initWithItem:item options:options multipleChoice:NO completionHandler:^(RETableViewItem *vi) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
            
            [item reloadRowWithAnimation:UITableViewRowAnimationNone];
            
            NSInteger i = [options indexOfObject:item.value];
            switch (i) {
                case 0:
                case 1:
                    [Setting saveBool:!((BOOL)i) forKey:HPSettingAfterSendJump];
                    [Setting saveBool:NO forKey:HPSettingAfterSendShowConfirm];
                    break;
                case 2:
                    [Setting saveBool:YES forKey:HPSettingAfterSendShowConfirm];
                    break;
                default:
                    break;
            }
            
            [Flurry logEvent:@"Setting SetAfterSendConfirm" withParameters:@{@"option":@(i)}];
        }];
        
        optionsController.delegate = weakSelf;
        optionsController.style = section.style;
        if (weakSelf.tableView.backgroundView == nil) {
            optionsController.tableView.backgroundColor = weakSelf.tableView.backgroundColor;
            optionsController.tableView.backgroundView = nil;
        }
        
        [weakSelf.navigationController pushViewController:optionsController animated:YES];
    }];
    
    // 上拉回复
    //
    BOOL isPullReply = [Setting boolForKey:HPSettingIsPullReply];
    REBoolItem *isPullReplyItem = [REBoolItem itemWithTitle:@"上拉回复" value:isPullReply switchValueChangeHandler:^(REBoolItem *item) {
        
        NSLog(@"isPullReply Value: %@", item.value ? @"YES" : @"NO");
        [Setting saveBool:item.value forKey:HPSettingIsPullReply];
        
        [Flurry logEvent:@"Setting TogglePullReply" withParameters:@{@"flag":@(item.value)}];
    }];
    
    // 省流量模式
    //
    BOOL isPrint = [Setting boolForKey:HPSettingPrintPagePost];
    REBoolItem *isPrintItem = [REBoolItem itemWithTitle:@"省流量模式(加载打印版网页)" value:isPrint switchValueChangeHandler:^(REBoolItem *item) {
        
        NSLog(@"isSwipeBack Value: %@", item.value ? @"YES" : @"NO");
        [Setting saveBool:item.value forKey:HPSettingPrintPagePost];
        
        [Flurry logEvent:@"Setting Print" withParameters:@{@"flag":@(item.value)}];
    }];
    
    //
    //
    RETableViewItem *setStupidBarItem = [RETableViewItem itemWithTitle:@"StupidBar" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        @strongify(self);
        HPSetStupidBarController *svc = [HPSetStupidBarController new];
        [self.navigationController pushViewController:svc animated:YES];
        [item deselectRowAnimated:YES];
        
        [Flurry logEvent:@"Setting EnterStupidBar"];
    }];
    
    if ([HPAccount isMasterAccount]) {
        [section addItem:isOnlineEnvItem];
    }
    
    [section addItem:isNightModeItem];
    [section addItem:isShowAvatarItem];
    [section addItem:postTailText];
    [section addItem:domainSettingText];
    [section addItem:setForumItem];
    [section addItem:blockListItem];
    [section addItem:blockThreadListItem];
    [section addItem:isPreferNoticeItem];
    [section addItem:afterSendConfirmItem];
    [section addItem:isPullReplyItem];
    [section addItem:setStupidBarItem];
    [section addItem:isPrintItem];
    
    [_manager addSection:section];
    return section;
}

- (void)addBgFetchSection
{
    if (IOS7_OR_LATER && ![HPLabService instance].enableMessagePush) {
        RETableViewSection *bgFetchSection = [RETableViewSection sectionWithHeaderTitle:nil];
        @weakify(self);
        RETableViewItem *bgFetchItem = [RETableViewItem itemWithTitle:@"后台应用程序刷新" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
            @strongify(self);
            HPBgFetchViewController *vc = [[HPBgFetchViewController alloc] initWithStyle:UITableViewStylePlain];
            [self.navigationController pushViewController:vc animated:YES];
            
            [item deselectRowAnimated:YES];
            
            [Flurry logEvent:@"Account EnterBgFetch"];
        }];
        [bgFetchSection addItem:bgFetchItem];
        [self.manager addSection:bgFetchSection];
    }
}

- (void)addLabSection
{
    if ([HPAccount isAccountForReviewer]) {
        return;
    }
    
    RETableViewSection *section = [RETableViewSection sectionWithHeaderTitle:nil];
    @weakify(self);
    RETableViewItem *item = [RETableViewItem itemWithTitle:@"实验室(beta)" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        @strongify(self);
        HPLabGuideViewController *vc = [HPLabGuideViewController new];
        vc.isModal = NO;
        [self.navigationController pushViewController:vc animated:YES];
        
        [item deselectRowAnimated:YES];
        [Flurry logEvent:@"Account EnterLab"];
    }];
    [section addItem:item];
    [self.manager addSection:section];
}


- (RETableViewSection *) addImageControls {
    
    __typeof (&*self) __weak weakSelf = self;
    
    RETableViewSection *section = [RETableViewSection sectionWithHeaderTitle:nil];
    
    
    RETableViewItem *setImageSizeFilterItem = [RETableViewItem itemWithTitle:@"图片加载设置" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        
        HPSetImageSizeFilterViewController *svc = [HPSetImageSizeFilterViewController new];
        [weakSelf.navigationController pushViewController:svc animated:YES];
        [item deselectRowAnimated:YES];
        
        [Flurry logEvent:@"Setting ImageSizeFilter"];
    }];
    [section addItem:setImageSizeFilterItem];
    
        
    RETableViewItem *cleanItem = [RETableViewItem itemWithTitle:@"清理缓存" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        [item deselectRowAnimated:YES];
        
        [SVProgressHUD showWithStatus:@"清理中" maskType:SVProgressHUDMaskTypeBlack];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[NSURLCache sharedURLCache] removeAllCachedResponses];
            [[SDImageCache sharedImageCache] clearMemory];
            [[SDImageCache sharedImageCache] clearDiskOnCompletion:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showSuccessWithStatus:@"清理完成"];
                });
            }];
        });
        
        item.title = @"清理缓存";
        [item reloadRowWithAnimation:UITableViewRowAnimationAutomatic];
        
        [Flurry logEvent:@"Setting ClearCache"];
    }];
    
    
    [[SDImageCache sharedImageCache] calculateSizeWithCompletionBlock:^(NSUInteger fileCount, NSUInteger totalSize) {
        
        NSLog(@"%lu, %lu", fileCount, totalSize);
        //cleanItem.title = [NSString stringWithFormat:@"%d, %lld", fileCount, totalSize];
        cleanItem.title = [NSString stringWithFormat:@"清理缓存 %.1fm", totalSize/(1024.f*1024.f)];
        [cleanItem reloadRowWithAnimation:UITableViewRowAnimationAutomatic];
        
    }];
    
    [section addItem:cleanItem];
    
    [_manager addSection:section];
    return section;
}

- (RETableViewSection *)addDataTrackingControls {
    
    RETableViewSection *section = [RETableViewSection sectionWithHeaderTitle:nil];
    
    //
    BOOL dataTrackingEnable = [Setting boolForKey:HPSettingDataTrackEnable];
    REBoolItem *dataTrackingEnableItem = [REBoolItem itemWithTitle:@"使用行为统计" value:dataTrackingEnable switchValueChangeHandler:^(REBoolItem *item) {
        
        NSLog(@"dataTrackingEnable %@", item.value ? @"YES" : @"NO");
        
        if (item.value == NO) {
            UIAlertView *alert = [[UIAlertView alloc]
                                  initWithTitle:@"o(>﹏<)o不要关啊"
                                  message:@"这个会统计一些使用行为, 以帮助俺改进App, 比如读帖子时哪些按钮使用频繁俺就会根据统计放到更显眼的位置"
                                  delegate:nil
                                  cancelButtonTitle:@"关关关"
                                  otherButtonTitles:@"算了", nil];
            [alert showWithHandler:^(UIAlertView *alertView, NSInteger buttonIndex) {
                if (buttonIndex != alertView.cancelButtonIndex) {
                    item.value = YES;
                    [item reloadRowWithAnimation:UITableViewRowAnimationNone];
                    [Flurry logEvent:@"Setting DataTracking" withParameters:@{@"action":@"StopClose"}];
                } else {
                    [Setting saveBool:item.value forKey:HPSettingDataTrackEnable];
                    [Flurry logEvent:@"Setting DataTracking" withParameters:@{@"action":@"StillClose"}];
                }
            }];
        } else {
            [Setting saveBool:item.value forKey:HPSettingDataTrackEnable];
            [Flurry logEvent:@"Setting DataTracking" withParameters:@{@"action":@"Open"}];
        }
        
    }];
    
    //
    BOOL bugTrackingEnable = [HPCrashReport isCrashReportEnable];
    REBoolItem *bugTrackingEnableItem = [REBoolItem itemWithTitle:@"错误信息收集" value:bugTrackingEnable switchValueChangeHandler:^(REBoolItem *item) {
        
        NSLog(@"bugTrackingEnable %@", item.value ? @"YES" : @"NO");
        
        if (item.value == NO) {
            UIAlertView *alert = [[UIAlertView alloc]
                                  initWithTitle:@"o(>﹏<)o不要关啊"
                                  message:@"这个会发送App错误报告给俺\n帮助俺定位各种bug"
                                   delegate:nil
                                   cancelButtonTitle:@"关关关"
                                   otherButtonTitles:@"算了", nil];
            [alert showWithHandler:^(UIAlertView *alertView, NSInteger buttonIndex) {
                if (buttonIndex != alertView.cancelButtonIndex) {
                    item.value = YES;
                    [item reloadRowWithAnimation:UITableViewRowAnimationNone];
                    [Flurry logEvent:@"Setting BugTracking" withParameters:@{@"action":@"StopClose"}];
                } else {
                    [HPCrashReport setCrashReportEnable:NO];
                    [Flurry logEvent:@"Setting BugTracking" withParameters:@{@"action":@"StillClose"}];
                }
            }];
        } else {
            [HPCrashReport setCrashReportEnable:YES];
            [Flurry logEvent:@"Setting BugTracking" withParameters:@{@"action":@"Open"}];
        }
    }];
    
    // isForceLogin
    //
    BOOL isForceLogin = [Setting boolForKey:HPSettingForceLogin];
    REBoolItem *isForceLoginItem = [REBoolItem itemWithTitle:@"强制登录 (无法登录时可打开)" value:isForceLogin switchValueChangeHandler:^(REBoolItem *item) {
        NSLog(@"isForceLoginItem Value: %@", item.value ? @"YES" : @"NO");
        [Setting saveBool:item.value forKey:HPSettingForceLogin];
        
        [Flurry logEvent:@"Setting ToggleForceLogin" withParameters:@{@"flag":@(item.value)}];
    }];
    
    [section addItem:dataTrackingEnableItem];
    [section addItem:bugTrackingEnableItem];
    [section addItem:isForceLoginItem];
    
    [_manager addSection:section];
    return section;
}


- (RETableViewSection *)addAboutControls
{
    RETableViewSection *section = [RETableViewSection sectionWithHeaderTitle:nil];

    // 致谢
    //
    @weakify(self);
    RETableViewItem *aboutItem = [RETableViewItem itemWithTitle:@"致谢" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        [item deselectRowAnimated:YES];
        @strongify(self);
        WKWebView *webView=[[WKWebView alloc]initWithFrame:self.view.frame];
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"acknowledgement" withExtension:@"html"];
        
        [webView loadRequest:[NSURLRequest requestWithURL:url]];
        
        UIViewController *webViewController = [[UIViewController alloc] init];
        [webViewController.view addSubview: webView];
        
        webViewController.title = @"致谢";
        [self.navigationController pushViewController:webViewController animated:YES];
        
        [Flurry logEvent:@"Setting EnterAcknowledgement"];
    }];

    // Bug & 建议
    //
    RETableViewItem *reportItem = [RETableViewItem itemWithTitle:@"反馈问题" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        [item deselectRowAnimated:YES];
        @strongify(self);
        // 获得设备信息
        //
        /*!
         *  get the information of the device and system
         *  "i386"          simulator
         *  "iPod1,1"       iPod Touch
         *  "iPhone1,1"     iPhone
         *  "iPhone1,2"     iPhone 3G
         *  "iPhone2,1"     iPhone 3GS
         *  "iPad1,1"       iPad
         *  "iPhone3,1"     iPhone 4
         *  @return null
         */
        struct utsname systemInfo;
        uname(&systemInfo);
        //get the device model and the system version
        NSString *device_model = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
        NSString *system_version = [[UIDevice currentDevice] systemVersion];
        NSLog(@"device_model %@, system_version %@", device_model, system_version);
        
        
        MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
        if (!controller) {
            [SVProgressHUD showErrorWithStatus:@"请先在系统设置中配置一个邮箱账号, 再反馈问题\n或者您可以直接使用回帖建议来反馈问题"];
            return;
        }
        
        controller.mailComposeDelegate = self;
        [controller setToRecipients:@[@"wujichao.hpclient@gmail.com"]];
        [controller setSubject:@"HP论坛客户端反馈: "];
        [controller setMessageBody:[NSString stringWithFormat:@"\n\n\n网络(eg:移动2g): \n设备: %@ \niOS版本: %@ \n客户端版本: v%@", device_model, system_version, VERSION] isHTML:NO];
        
        [HPLogger getZipFile:^(NSString *path) {
            if (!path) {
                [self presentViewController:controller animated:YES completion:NULL];
                return;
            }
            NSData *data = [NSData dataWithContentsOfFile:path];
            [controller addAttachmentData:data mimeType:@"application/zip" fileName:@"日志.zip"];
            [self presentViewController:controller animated:YES completion:NULL];
        }];
    }];
    

    
    //
    //
    RETableViewItem *replyItem = [RETableViewItem itemWithTitle:@"回帖建议" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        @strongify(self);
        
        HPThread *thread = [HPThread new];
        thread.fid = 2;
        thread.tid = 1272557;
        thread.title = @"D版 iOS 客户端";
    
        UIViewController *rvc = [[PostViewControllerClass() alloc] initWithThread:thread];
        [self.navigationController pushViewController:rvc animated:YES];
        
        [item deselectRowAnimated:YES];
        
        [Flurry logEvent:@"Setting EnterAdvice"];
    }];
    
    //
    //
    RETableViewItem *githubItem = [RETableViewItem itemWithTitle:@"github/hipda_ios_client_v3" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/wujichao/hipda_ios_client_v3"]];
        
        [item deselectRowAnimated:YES];
        
        [Flurry logEvent:@"Setting EnterGithub"];
    }];
   
    RETableViewItem *logItem = [RETableViewItem itemWithTitle:@"查看日志" accessoryType:UITableViewCellAccessoryDisclosureIndicator selectionHandler:^(RETableViewItem *item) {
        @strongify(self);
        [self.navigationController pushViewController:[HPLoggerViewerController new] animated:YES];
        [item deselectRowAnimated:YES];
    }];
    
    
    [section addItem:reportItem];
    [section addItem:replyItem];
    [section addItem:aboutItem];
    [section addItem:githubItem];
    [section addItem:logItem];
    
    [_manager addSection:section];
    return section;
}

#pragma mark -

- (void)close:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)closeAndShowLoginVC {
    [self dismissViewControllerAnimated:YES completion:^{
        // 板块列表复原
        [[HPRearViewController sharedRearVC] forumDidChanged];
        // 换到帖子列表
        [[HPRearViewController sharedRearVC] switchToThreadVC];
        // 关闭侧边栏
        HPAppDelegate *d = [[UIApplication sharedApplication] delegate];
        [d.viewController revealToggle:d];
        // 弹出登录, 登录好了会刷新帖子列表
        HPLoginViewController *loginvc = [[HPLoginViewController alloc] init];
        UINavigationController *nvc = [HPCommon NVCWithRootVC:loginvc];
        nvc.modalPresentationStyle = UIModalPresentationFullScreen;
        [[[[UIApplication sharedApplication] keyWindow] rootViewController] presentViewController:nvc animated:YES completion:nil];
    }];
}


- (void)reset:(id)sender
{
    @weakify(self);
    [UIAlertView showConfirmationDialogWithTitle:@"重置设置"
                                         message:@"您确定要重置所有设置吗?"
                                         handler:^(UIAlertView *alertView, NSInteger buttonIndex)
     {
         @strongify(self);
         BOOL confirm = (buttonIndex != [alertView cancelButtonIndex]);
         if (confirm) {
             [Setting loadDefaults];
             [SVProgressHUD showSuccessWithStatus:@"设置已重置"];
             
             [self close:nil];
         }
         
         [Flurry logEvent:@"Setting Reset" withParameters:@{@"confirm":@(confirm)}];
     }];
}

#pragma mark mail delegate
- (void)mailComposeController:(MFMailComposeViewController*)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError*)error;
{
    if (result == MFMailComposeResultSent) {
        NSLog(@"sent");
    }
    [self dismissViewControllerAnimated:YES completion:NULL];
    
    [Flurry logEvent:@"Setting ContactAuthor" withParameters:@{@"result":@(result)}];
}

@end
