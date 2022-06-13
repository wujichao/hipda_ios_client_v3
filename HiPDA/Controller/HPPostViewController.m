//
//  HPPostViewController.m
//  HiPDA
//
//  Created by wujichao on 14-2-27.
//  Copyright (c) 2014年 wujichao. All rights reserved.
//


#import "HPPostViewController.h"
#import "HPReplyTopicViewController.h"
#import "HPReplyViewController.h"
#import "HPRearViewController.h"
#import "HPUserViewController.h"
#import "HPEditPostViewController.h"
#import "HPSFSafariViewController.h"
#import "HPViewHTMLController.h"
#import "HPViewSignatureViewController.h"
#import "HPAttachmentService.h"
#import "HPNewPost.h"
#import "HPDatabase.h"
#import "HPUser.h"
#import "HPThread.h"
#import "HPAccount.h"
#import "HPCache.h"
#import "HPFavorite.h"
#import "HPAttention.h"
#import "HPMessage.h"
#import "HPHttpClient.h"
#import "HPTheme.h"
#import "HPSetting.h"
#import "HPStupidBar.h"

#import "IBActionSheet.h"
#import <SVProgressHUD.h>
#import "NSUserDefaults+Convenience.h"
#import "IDMPhotoBrowser.h"

#import "NSString+Additions.h"
#import "NSString+HTML.h"
#import "NSString+CDN.h"
#import "WKWebView+HPSafeLoadString.h"

#import "UIViewController+KNSemiModal.h"
#import "UIAlertView+Blocks.h"
#import <ALActionBlocks/ALActionBlocks.h>
#import "UIBarButtonItem+ImageItem.h"
#import "UIView+AnchorPoint.h"

#import "EGORefreshTableFooterView.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <UIImageView+WebCache.h>

#import "HPActivity.h"
#import "HPBlockService.h"

#import <KVOController/KVOController.h>
#import "NJKWebViewProgressView.h"
#import "WKWebView+Synchronize.h"
#import "HPJSMessage.h"
#import "FLWeakProxy.h"
#import "SDImageCache+URLCache.h"
#import "HPPDFPrintPageRenderer.h"
#import "HPPDFPreviewViewController.h"

#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]



#define refreshControlTag 35483548
#define fontSizeStepperTag 2011
#define lineHeightStepperTag 2012

typedef NS_ENUM(NSInteger, StoryTransitionType)
{
    StoryTransitionTypeNext,
    StoryTransitionTypePrevious
};


/*
 
 required
    fid
    tid
    user(只看某人, 举报) 在 refreshThreadInfo 试着获得了一个
 
 need
    title -> ##title##
    pagecount -> 1/?
 
 optional
 
*/

@interface PostWebView : WKWebView
//@property (nonatomic, weak) UIView *navigationControllerView;
@end

@implementation PostWebView

+ (void)load
{
    
    // https://mp.weixin.qq.com/s/rhYKLIbXOsUJC_n6dt9UfA
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"WKBrowsingContextController");
        SEL sel = NSSelectorFromString(@"registerSchemeForCustomProtocol:");
        if ([(id)cls respondsToSelector:sel]) {
            // 注册http(s) scheme, 把 http和https请求交给 NSURLProtocol处理
#pragma clang diagnostic push
#pragma clang diagnostic ignored"-Warc-performSelector-leaks"
            [(id)cls performSelector:sel withObject:@"http"];
            [(id)cls performSelector:sel withObject:@"https"];
#pragma clang diagnostic pop
        }
    });
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        if (IOS9_OR_LATER) {
            self.allowsLinkPreview = NO;
        }
        //不要改, 改成和tableview一样的UIScrollViewDecelerationRateNormal, 反而奇怪
        //self.scrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hitView = [super hitTest:point withEvent:event];
    // 有些被表格撑宽的页面, 无法滑动返回
    if (point.x < 20) {
        return nil;//self.navigationControllerView;
    }
    return hitView;
}

@end

@interface HPPostViewController () <
WKScriptMessageHandler, WKNavigationDelegate,
IBActionSheetDelegate,
IDMPhotoBrowserDelegate,
UIScrollViewDelegate,
HPCompositionDoneDelegate,
HPStupidBarDelegate
>

@property (nonatomic, strong) PostWebView *webView;
@property (nonatomic, strong) NJKWebViewProgressView *progressView;

@property (nonatomic, strong) HPThread *thread;
@property (nonatomic, strong) NSArray *posts;
@property (nonatomic, strong) NSString *htmlString;

@property (nonatomic, assign) NSInteger current_page;
@property (nonatomic, assign) BOOL forceFullPage;
@property (nonatomic, assign) NSInteger gotoFloor;
@property (nonatomic, assign) NSInteger find_pid;

@property (nonatomic, strong) UIActivityIndicatorView *indicator;
@property (nonatomic, strong) UIView *pageView;

@property (nonatomic, strong) UIView *adjustView;
@property (nonatomic, strong) UIView *semiTransparentView;
@property (nonatomic, strong) UIStepper *fontsizeStepper;
@property (nonatomic, strong) UILabel *fontSizeLabel;
@property (nonatomic, assign) NSInteger currentFontSize;
@property (nonatomic, strong) UIStepper *lineHeightStepper;
@property (nonatomic, strong) UILabel *lineHeightLabel;
@property (nonatomic, assign) NSInteger currentLineHeight;

@property (nonatomic, assign) NSInteger current_floor;

@property (nonatomic, weak) IBActionSheet *currentActionSheet;

@property (nonatomic, strong) HPAttachmentService *temp_attachmentService;

@end

@implementation HPPostViewController {
@private
    UIRefreshControl *_refreshControl;
    
    // for action
    HPNewPost *_current_action_post;
    NSInteger _current_author_uid;
    UISlider *_pageSlider;
    UILabel *_pageLabel;
    
    UIButton *_favButton;
    UIButton *_attentionButton;
    UIButton *_pageInfoButton;
    
    UIButton *_buttomInVisibleBtn;
    
    //
    EGORefreshTableHeaderView *_refreshHeaderView;
    EGORefreshTableFooterView *_refreshFooterView;
	BOOL _reloadingHeader;
    BOOL _reloadingFooter;
    BOOL _lastPage;
    
    //
    BOOL _reloadingForReply;
}

#pragma mark - life cycle





- (id)initWithThread:(HPThread *)thread {
    return [self initWithThread:thread
                           page:1
                  forceFullPage:NO];
}

- (id)initWithThread:(HPThread *)thread
                page:(NSInteger)page
       forceFullPage:(BOOL)forceFullPage {
    
    id instance = [self initWithThread:thread
                                  page:page
                         forceFullPage:forceFullPage
                              find_pid:0];
    
    
    // 处理最新回复
    if (instance && _current_page == NSIntegerMax) _reloadingForReply = YES;
    
    return instance;
}

- (id)initWithThread:(HPThread *)thread
            find_pid:(NSInteger)find_pid {
    
    return [self initWithThread:thread
                           page:1
                  forceFullPage:YES
                       find_pid:find_pid];
}

- (id)initWithThread:(HPThread *)thread
                page:(NSInteger)page
       forceFullPage:(BOOL)forceFullPage
            find_pid:(NSInteger)find_pid
{
    
    self = [super init];
    if (self) {
        
        _thread = thread;
        
//        if (_thread && _thread.tid!=0 && _thread.title.length > 0) {
//            [Flurry logEvent:@"Read Open" withParameters:@{@"tid":@(_thread.tid), @"title":_thread.title}];
//        }
        
        _current_page = page;
        _forceFullPage = forceFullPage;
        _find_pid = find_pid;
    }
    return self;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupWebview];
    
    //
    _currentFontSize = [Setting integerForKey:HPSettingFontSizeAdjust];
    _currentLineHeight = [Setting integerForKey:HPSettingLineHeightAdjust];
    
    // action
    [self setActionButton];
    
    // gesture
    [self addGuesture];
    
    NSLog(@"start load");
    // load
    //[self performSelector:@selector(load:) withObject:nil afterDelay:0.01f];
    [self load];
    
    // add stupid bar
    if (![Setting boolForKey:HPSettingStupidBarDisable]) {
        HPStupidBar *stupidBar = [[HPStupidBar alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height-20.f-[UIDevice hp_safeAreaInsets].bottom, self.view.frame.size.width, 20.f)];
        stupidBar.tag = 2020202;
        stupidBar.delegate = self;
        [self.view addSubview:stupidBar];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self indicatorStop];
    
    [self.currentActionSheet dismissWithClickedButtonIndex:110 animated:YES];
}


- (void)setupWebview
{
    // First create a WKWebViewConfiguration object so we can add a controller
    // pointing back to this ViewController.
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc]
                                             init];
    
    if (IOS9_OR_LATER) {
        // 实测有用
        configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    }
    
    WKUserContentController *controller = [[WKUserContentController alloc]
                                           init];
    
    // Add a script handler for the "observe" call. This is added to every frame
    // in the document (window.webkit.messageHandlers.NAME).
    FLWeakProxy *weakProxy = [FLWeakProxy weakProxyForObject:self];
    [controller addScriptMessageHandler:(id<WKScriptMessageHandler>)weakProxy name:@"observe"];
    configuration.userContentController = controller;
    
    // Initialize the WKWebView with the current frame and the configuration
    // setup above
    PostWebView *wv = [[PostWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
//    [wv setScalesPageToFit:YES];
//    wv.dataDetectorTypes = UIDataDetectorTypeNone;
//    wv.delegate = self;
    wv.backgroundColor = [HPTheme backgroundColor];
//    wv.navigationControllerView = self.navigationController.view;
   
    for(UIView *view in [[[wv subviews] objectAtIndex:0] subviews]) {
        if([view isKindOfClass:[UIImageView class]]) {
            view.hidden = YES; }
    }
    [wv setOpaque:NO];
    
    // scrollView
    wv.scrollView.delegate = self;
    [wv.scrollView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:(__bridge void *)(self)];
    
    //
    wv.navigationDelegate = self;
    
    [self.view addSubview:wv];
    self.webView = wv;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)dealloc
{
    // deal with web view special needs
    NSLog(@"HPPostViewController dealloc");
    [self.webView stopLoading];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"observe"];
    
    self.webView.scrollView.delegate = nil;
    self.webView.navigationDelegate = nil;
   
    [self.webView.scrollView removeObserver:self forKeyPath:@"contentOffset" context:(__bridge void *)self];
    
    [[HPHttpClient sharedClient] cancelOperationsWithThread:self.thread];
}

#pragma mark - prepare view

- (void)setActionButton {
    
    [self updateFavButton];
    [self updateAttentionButton];
    
    UIBarButtonItem *favBI = [[UIBarButtonItem alloc] initWithCustomView:_favButton];
    
    UIBarButtonItem *attentionBI = [[UIBarButtonItem alloc] initWithCustomView:_attentionButton];
    
    UIBarButtonItem *commentBI = [UIBarButtonItem barItemWithImage:[UIImage imageNamed:@"talk.png"]
                                                              size:CGSizeMake(40.f, 40.f)
                                                            target:self
                                                            action:@selector(reply:)];
    
    UIBarButtonItem *moreBI = [UIBarButtonItem barItemWithImage:[UIImage imageNamed:@"more.png"]
                                                           size:CGSizeMake(40.f, 40.f)
                                                         target:self
                                                         action:@selector(action:)];
    
    [self updatePageButton];
    UIBarButtonItem* pageBI = [[UIBarButtonItem alloc] initWithCustomView:_pageInfoButton];
    
    
    UIBarButtonItem *negativeSeperator = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    
    if (IOS7_OR_LATER) negativeSeperator.width = -12;
    
    
    UIBarButtonItem *item = [Setting boolForKey:HPSettingPreferNotice] ?
                            attentionBI : favBI ;
    self.navigationItem.rightBarButtonItems = @[negativeSeperator, moreBI, pageBI, commentBI, item];
}

- (void)updateFavButton {
    
    if (!_favButton) {
        _favButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _favButton.bounds = CGRectMake(0, 0, 20.f, 20.f);
        [_favButton addTarget:self action:@selector(favorite:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    UIImage *favImg = [HPFavorite isFavoriteWithTid:_thread.tid] ?
        [UIImage imageNamed:@"love_selected.png"] : [UIImage imageNamed:@"love.png"];
    
    [_favButton setImage:favImg forState:UIControlStateNormal];
}

- (void)updateAttentionButton {
    
    if (!_attentionButton) {
        _attentionButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _attentionButton.bounds = CGRectMake(0, 0, 20.f, 20.f);
        [_attentionButton addTarget:self action:@selector(attention:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    UIImage *attentionImg = [HPAttention isAttention:_thread.tid] ?
        [UIImage imageNamed:@"love_selected.png"] : [UIImage imageNamed:@"love.png"];
    
    [_attentionButton setImage:attentionImg forState:UIControlStateNormal];
}

- (void)updatePageButton {
    if (!_pageInfoButton) {
        _pageInfoButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _pageInfoButton.bounds = CGRectMake(0, 0, 30.f, 30.f);
        [_pageInfoButton addTarget:self action:@selector(showPageView:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    NSString *attrTitle = [self pageInfoString];
    
    NSMutableAttributedString *subAttrString =
    [[NSMutableAttributedString alloc] initWithString:attrTitle];
    
    UIFont *subtitleFont = [UIFont fontWithName:@"Georgia" size:15.f];
    [subAttrString setAttributes:@{
                                   NSForegroundColorAttributeName:[UIColor colorWithRed:164.f/255.f green:164.f/255.f blue:164.f/255.f alpha:1.f],
                                   NSFontAttributeName:subtitleFont}
                           range:NSMakeRange(0, [attrTitle length])];
    [_pageInfoButton setAttributedTitle:subAttrString forState:UIControlStateNormal];
    [_pageInfoButton sizeToFit];
}

- (NSString *)pageInfoString {
    NSString *attrTitle =
    _thread.pageCount != 0 ?
    [NSString stringWithFormat:@"%ld/%ld", _current_page, _thread.pageCount] :
    [NSString stringWithFormat:@"%ld/?", _current_page];
    
    if (_current_page == NSIntegerMax) attrTitle = @"?/?";
    return attrTitle;
}

- (void)addGuesture {
    if (!IOS7_OR_LATER) {
        UISwipeGestureRecognizer *rightSwipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(back:)];
        rightSwipeGesture.direction = UISwipeGestureRecognizerDirectionRight;
        [self.view addGestureRecognizer:rightSwipeGesture];
    }
    
    UISwipeGestureRecognizer *leftSwipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(nextPage:)];
    leftSwipeGesture.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.view addGestureRecognizer:leftSwipeGesture];
}

#pragma mark - load
- (void)load {
    [self load:NO];
}

//block:(void (^)(NSError *error))block
- (void)load:(BOOL)refresh {
    
    NSLog(@"load sender refresh %d", refresh);
    
    //
    if (!refresh) [self.indicator startAnimating];
    _reloadingHeader = YES;
    _reloadingFooter = YES;
    
#if DEBUG && 0 /*直接下拉刷新即可刷新模板 cd /HiPDA/View/; python -m SimpleHTTPServer*/
    NSData *___d = [NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://localhost:8000/post_view_wk.html"]];
    NSMutableString *string = [[[NSString alloc] initWithData:___d encoding:NSUTF8StringEncoding] mutableCopy];
#else
    NSMutableString *string = [[NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"post_view_wk" ofType:@"html"] encoding:NSUTF8StringEncoding error:nil] mutableCopy];
#endif
    
    if (_thread.title && !refresh)
        [string replaceOccurrencesOfString:@"##title##" withString:_thread.title options:0 range:NSMakeRange(0, string.length)];
   
    /* iOS9之后才有苹方字体
        PingFangSC-Ultralight,
        PingFangSC-Regular,
        PingFangSC-Semibold,
        PingFangSC-Thin,
        PingFangSC-Light,
        PingFangSC-Medium
     */
    NSString *boldFont = IOS9_OR_LATER ? @"PingFangSC-Medium" : @"STHeitiSC-Medium";
    BOOL regularMode = [Setting boolForKey:HPSettingRegularFontMode];
    NSString *regularFont = IOS9_OR_LATER ? (regularMode ? @"PingFangSC-Regular" : @"PingFangSC-Light") :
                                            @"STHeitiSC-Light"; //没有STHeitiSC-Regular这种字体
    
    NSDictionary *replace = @{
        @"**[txtadjust]**": S(@"%@.000001%%",@(self.currentFontSize)),
        @"**[lineHeight]**": S(@"%@%%", @(self.currentLineHeight)),
        @"**[screen_width]**": @(HP_SCREEN_WIDTH).stringValue,
        @"**[screen_height]**": @(HP_SCREEN_HEIGHT).stringValue,
        @"**[min-height]**" : @((int)(HP_SCREEN_WIDTH * 0.618)).stringValue,
        @"**[style]**": [Setting boolForKey:HPSettingNightMode] ?
                                ([UIDevice hp_isiPhoneX] ? @"dark oled" : @"dark") :
                                @"light",
        @"**[fontsize]**": (IS_IPAD && IOS10_OR_LATER) ?
                                [NSString stringWithFormat:@"%dpx", (int)(self.currentFontSize/100.f*16)] :
                                @"16px !Important",
        @"**[fontfamily]**": (IOS8_OR_LATER && UIAccessibilityIsBoldTextEnabled()) ?
            [NSString stringWithFormat:@"\"%@\",\"HelveticaNeue-Bold\"", boldFont] :
            [NSString stringWithFormat:@"\"%@\",\"HelveticaNeue\"", regularFont]
        ,
#if DEBUG && 0
        @"**[debug_script]**": @"<script src=\"http://wechatfe.github.io/vconsole/lib/vconsole.min.js?v=1.3.0\"></script>",
#else
        @"**[debug_script]**": @"",
#endif
    };
    [replace enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [string replaceOccurrencesOfString:key withString:value options:0 range:NSMakeRange(0, string.length)];
    }];
    
    
    self.htmlString = string;
    [self.webView hp_safeLoadHTMLString:string baseURL:[NSURL URLWithString:S(@"%@/forum/", HP_BASE_URL)]];
    
    BOOL printable = !_forceFullPage && (_current_page == 1 && _current_author_uid == 0);
    
    __typeof__(self) __weak weakSelf = self;
    [HPNewPost loadThreadWithTid:_thread.tid
                            page:_current_page
                    forceRefresh:refresh
                       printable:printable
                        authorid:_current_author_uid
                 redirectFromPid:_find_pid ? _find_pid:0
                           block:
     ^(NSArray *posts, NSDictionary *parameters, NSError *error) {
        
        if (!weakSelf) return;
         
        if (!error) {
            
            // save posts
            weakSelf.posts = posts;
            
            // save parameters
            [weakSelf refreshThreadInfo:parameters
                           find_pid:weakSelf.find_pid];
            
            [[HPCache sharedCache] readThread:weakSelf.thread];
            
            // update title
            [string replaceOccurrencesOfString:@"##title##" withString:weakSelf.thread.title options:0 range:NSMakeRange(0, string.length)];
            
            //
            __block NSMutableString *lists = [NSMutableString stringWithCapacity:42];
            [posts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                
                HPNewPost *post = (HPNewPost *)obj;
                
                NSString *liClass = (post.floor == weakSelf.gotoFloor) ? @"gotoFloor" : @"";
                
                NSString *list = nil;
                BOOL isBlocked = [[HPBlockService shared] isUserInBlockList:post.user.username];
                NSString *avatarURLSrc = post.user.avatarImageURL ?
                    [NSString stringWithFormat:@"src=\"%@\"", [post.user.avatarImageURL absoluteString]]
                    : @"";
                
                if ([Setting boolForKey:HPSettingShowAvatar]) {
                    list = [NSString stringWithFormat:@"<li class=\"%@\" data-id=\"floor://%ld\" ><a name=\"floor_%ld\"></a><div class=\"info\"><span class=\"avatar\"><img data-id='user://%@' %@ onerror=\"this.onerror=null;this.src='%@/forum/uc_server/images/noavatar_middle.gif'\" ></span><span class=\"author\" data-id='user://%@'>%@</span><span class=\"floor\">%ld#</span><span class=\"time-ago\">%@</span></div><div class=\"content%@\">%@</div></li>", liClass, post.floor, post.floor,  [post.user.username URLEncode], avatarURLSrc, HP_BASE_URL, [post.user.username URLEncode], post.user.username, post.floor, [HPNewPost dateString:post.date], isBlocked?@" blocked":@"", isBlocked?@"- <i>blocked</i> - ":post.body_html];
                    
                } else {
                    
                    list = [NSString stringWithFormat:@"<li class=\"%@\" data-id=\"floor://%ld\" ><a name=\"floor_%ld\"></a><div class=\"info\"><span class=\"author\" data-id='user://%@' style=\"left: 0;\">%@</span><span class=\"floor\">%ld#</span><span class=\"time-ago\">%@</span></div><div class=\"content%@\">%@</div></li>", liClass, post.floor, post.floor, [post.user.username URLEncode], post.user.username, post.floor, [HPNewPost dateString:post.date], isBlocked?@" blocked":@"", isBlocked?@"- <i>blocked</i> - ":post.body_html];
                }
                
                // 解决由于一些tag未闭合造成的影响
                list = [list stringByReplacingOccurrencesOfString:@"</li>" withString:@"</table></strong></font></blockquote></b></i></em></li>"];
                
                [lists appendString:list];
            }];
            
            
            [string replaceOccurrencesOfString:@"<span style=\"display:none\">##lists##</span>" withString:lists options:0 range:NSMakeRange(0, string.length)];
            
            
            NSString *final = [HPNewPost preProcessHTML:string];
            
            //NSLog(@"%@", final);
            // https
            [weakSelf.webView hp_safeLoadHTMLString:final baseURL:[NSURL URLWithString:S(@"%@/forum/", HP_BASE_URL)]];
            if (!refresh) {
                [weakSelf setupProgressObserver];
            }
            [weakSelf endLoad:YES];
            
        } else {
            
            [weakSelf endLoad:NO];
            
            if (error.code == NSURLErrorUserAuthenticationRequired) {
                
                [SVProgressHUD showErrorWithStatus:@"重新登陆..."];
                
            } else if (error.code == NSURLErrorCancelled) {
                ;
                
            } else {
                [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
            }
        }
         
         /*
         if (block) {
             block(error);
         }*/
        
    }];
}

- (void)setupProgressObserver
{
    self.progressView = [[NJKWebViewProgressView alloc] initWithFrame:CGRectMake(0, self.webView.scrollView.contentInset.top, self.webView.frame.size.width, 1.f)];
    [self.webView addSubview:self.progressView];
    
    @weakify(self);
    [self.KVOController observe:self.webView
                        keyPath:@"estimatedProgress"
                        options:NSKeyValueObservingOptionNew
                          block:^(id observer, id object, NSDictionary *change) {
                              @strongify(self);
                              [self.progressView setProgress:self.webView.estimatedProgress animated:YES];
                          }];
}

- (void)reload:(id)sender {
    NSLog(@"reload sender %@", sender);
    [self load:YES];
}

- (void)refreshThreadInfo:(NSDictionary *)parameters
                 find_pid:(NSInteger)find_pid
{
    
    NSString *formhash = [parameters objectForKey:@"formhash"];
    NSInteger pageCount = [[parameters objectForKey:@"pageCount"] integerValue];
    NSString *title = [parameters objectForKey:@"title"];
    NSInteger fid = [[parameters objectForKey:@"fid"] integerValue];
    NSInteger tid = [[parameters objectForKey:@"tid"] integerValue];
    
    NSInteger page = [[parameters objectForKey:@"current_page"] integerValue];
    if ( find_pid == 0) find_pid = [[parameters objectForKey:@"find_pid"] integerValue];
    
    if (!_thread) {
        _thread = [[HPThread alloc]init];
    }
    
    if (formhash) _thread.formhash = formhash;
    if (title) _thread.title = title;
    if (fid) _thread.fid = fid;
    if (tid) _thread.tid = tid;
    
    if (pageCount) _thread.pageCount = pageCount;
    
    // add author
    if (_thread.user == nil) {
        
        if (_posts.count >= 1) {
            HPNewPost *author_post = _posts[0];
            _thread.user = author_post.user;
        } else {
            NSLog(@"#error _posts.count < 1");
            _thread.user = [HPUser new];
        }
    }
    

    // 处理 由 find_pid 跳转
    if (page) _current_page = page;
    if (find_pid) {
        [_posts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            HPNewPost *post = (HPNewPost *)obj;
            NSLog(@"%ld vs %ld", find_pid, post.pid);
            if (post.pid == find_pid) {
                _gotoFloor = post.floor;
                NSLog(@"find floor %ld pid %ld", _gotoFloor, post.pid);
                *stop = YES;
            }
        }];
        _find_pid = 0;
    }
    
    
    [self updatePageButton];
}

- (void)endLoad:(BOOL)success {
    
    [_refreshControl endRefreshing];
    [SVProgressHUD performSelector:@selector(dismiss) withObject:nil afterDelay:1.f];
    
    [self updateHeaderView];
    
    [self performSelector:@selector(indicatorStop) withObject:nil afterDelay:.3f];
    [self performSelector:@selector(updateFooterView) withObject:nil afterDelay:2.f];
    
    if (_reloadingForReply) {
        _reloadingForReply = NO;
        
        [SVProgressHUD showSuccessWithStatus:@"正在跳转..."];
        [self performSelector:@selector(webViewScrollToBottom:) withObject:nil afterDelay:1.f];
    } else if (_gotoFloor != 0) {
        
        [SVProgressHUD showSuccessWithStatus:@"正在跳转..."];
        [self performSelector:@selector(jumpToFloor:) withObject:nil afterDelay:1.f];
    }
}

- (void)updateHeaderView {
    
    if (_current_page == 1) {
        
        // _refreshControl
        if (!_refreshControl) {
            _refreshControl = [[UIRefreshControl alloc] init];
            _refreshControl.tag = refreshControlTag;
            [_refreshControl addTarget:self action:@selector(reload:) forControlEvents:UIControlEventValueChanged];
        }
        
        [_refreshHeaderView removeFromSuperview];
        [self.webView.scrollView addSubview:_refreshControl];
        
    } else {
        
        _reloadingHeader = NO;
        
        if (!_refreshHeaderView) {
            _refreshHeaderView = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.webView.scrollView.bounds.size.height, CGRectGetWidth([[UIScreen mainScreen] bounds]), self.webView.scrollView.bounds.size.height)];
            _refreshHeaderView.backgroundColor = [UIColor clearColor];
        }
        
        [_refreshControl removeFromSuperview];
        [self.webView.scrollView addSubview:_refreshHeaderView];
    }
}

- (void)updateFooterView {
    
    if (!_refreshFooterView) {
        _refreshFooterView = [[EGORefreshTableFooterView alloc] initWithFrame:CGRectMake(0.0f, [self contentSize], CGRectGetWidth([[UIScreen mainScreen] bounds]), 600.0f)];
        _refreshFooterView.backgroundColor = [UIColor clearColor];
        [self.webView.scrollView addSubview:_refreshFooterView];
    }
    
    _reloadingFooter = NO;
    _refreshFooterView.hidden = NO;
    
    if ([self canNext]) {
        _lastPage = NO;
        [_refreshFooterView setState:EGOOPullRefreshNormal];
    } else {
        _lastPage = YES;
        [_refreshFooterView setState:EGOOPullRefreshNoMore];
    }
}


#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    NSError *error = nil;
    HPJSMessage *m = [MTLJSONAdapter modelOfClass:HPJSMessage.class
                               fromJSONDictionary:message.body
                                            error:&error];
    if (error) {
        NSLog(@"error: %@", error);
        return;
    }
    
    if ([m.method isEqualToString:@"floor"]) {
        // 在帖子中 打开小尾巴, 特别是iOS客户端的小尾巴, 不知为何会触发floor
        // 暂时在未加载好是禁用
        if (_reloadingFooter) return;
        
        [self actionForFloor:[m.object integerValue]];
        
    } else if ([m.method isEqualToString:@"image"]) {
        [self openImage:m.object];
    } else if ([m.method isEqualToString:@"user"]) {
        
        HPUserViewController *uvc = [HPUserViewController new];
        uvc.username = [m.object URLDecode];
        
        [self.navigationController pushViewController:uvc animated:YES];
        
    } else if ([m.method isEqualToString:@"gotofloor"]) {
        
        [self gotoFloorWithUrl:m.object];
        
    } else if ([m.method isEqualToString:@"video"]) {
        // TODO: 对video不做特殊处理
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;
    NSString *urlString = url.absoluteString;
    
    NSLog(@"url %@, type %ld",urlString, navigationAction.navigationType);
    
    WKNavigationActionPolicy policy = WKNavigationActionPolicyAllow;
    
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        policy = WKNavigationActionPolicyCancel;
        // NEW_DOMAIN
        RxMatch *match = [urlString firstMatchWithDetails:RX(@"/forum/viewthread\\.php\\?tid=(\\d+)")];
        if (match) {
            RxMatchGroup *m1 = [match.groups objectAtIndex:1];
            
            HPThread *t = [HPThread new];
            t.tid = [m1.value integerValue];
            HPPostViewController *readVC = [[HPPostViewController alloc] initWithThread:t];
            NSLog(@"[self.navigationController pushViewController:readVC animated:YES];");
            [self.navigationController pushViewController:readVC animated:YES];
        } else if ([urlString indexOf:@"attachment.php?"] != -1) {
            self.temp_attachmentService = [[HPAttachmentService alloc] initWithUrl:urlString parentVC:self];
            [self.temp_attachmentService start];
        } else {
            [self openUrl:url];
        }
    } else if ([urlString isEqualToString:S(@"%@/forum/", HP_BASE_URL)]) {
        ;
    } else if ([urlString rangeOfString:@"#floor_"].location != NSNotFound) {
        ;
    } else {
        NSAssert(0, urlString);
    }
    
    decisionHandler(policy);
}

#pragma mark - 滚动到最底部

// call after webViewDidFinishLoad
- (void)webViewScrollToBottom:(id)sender
{
    /*
    CGFloat scrollHeight = self.webView.scrollView.contentSize.height - self.webView.bounds.size.height;
    if (0.0f > scrollHeight) scrollHeight = 0.0f;
    //webView.scrollView.contentOffset = CGPointMake(0.0f, scrollHeight);
    [self.webView.scrollView setContentOffset:CGPointMake(0.0f, scrollHeight) animated:YES];
     */
    /*
    NSInteger height = [[self.webView stringByEvaluatingJavaScriptFromString:@"document.body.offsetHeight;"] intValue];
    NSString* javascript = [NSString stringWithFormat:@"window.scrollBy(0, %d);", height];
    [self.webView stringByEvaluatingJavaScriptFromString:javascript];
    */
    
    if (_posts.count < 1) {
        return;
        NSLog(@"not ready");
    }
    
    NSInteger floor = [(HPNewPost *)_posts[0] floor] + _posts.count - 1;

    NSString *js = [NSString stringWithFormat:@"location.href='#floor_%ld'",floor];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}


#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if ((__bridge id)context != self) {
        return;
    }
    if (!_refreshFooterView) {
        return;
    }
   
    CGRect f = _refreshFooterView.frame;
    f.origin.y = [self contentSize];
    _refreshFooterView.frame = f;
}

#pragma mark - action sheet

- (void)action:(id)sender {
    //NSLog(@"%@", sender);
    
    NSString *theTitle = nil;
    if ([Setting boolForKey:HPSettingPreferNotice]) {
        theTitle = [HPFavorite isFavoriteWithTid:_thread.tid] ?
        @"取消收藏" : @"收藏";
    } else {
        theTitle = [HPAttention isAttention:_thread.tid] ?
        @"取消关注" : @"加关注";
    }
    
    NSString *firstTitle = nil;
    if (_posts.count>=1 && [self canEdit:_posts[0]]) {
        firstTitle = @"编辑";
    } else if (_current_page > 1) {
        firstTitle = @"刷新";
    } else {
        firstTitle = @"举报";
    }
    
    IBActionSheet *actionSheet = [[IBActionSheet alloc]
                                  initWithTitle:nil
                                  delegate:self cancelButtonTitle:@"取消"
                                  destructiveButtonTitle:firstTitle
                                  otherButtonTitles:
                                  theTitle,
                                  _current_author_uid != 0 ? @"查看全部" : @"只看楼主",
                                  @"浏览器打开",
                                  @"调整字体",
                                  @"更多",
                                  nil];
    self.currentActionSheet = actionSheet;
   
    [actionSheet setButtonBackgroundColor:rgb(25.f, 25.f, 25.f)];
    [actionSheet setButtonTextColor:rgb(216.f, 216.f, 216.f)];
    [actionSheet setFont:[UIFont fontWithName:@"STHeitiSC-Light" size:20.f]];
    actionSheet.tag = 1;
    [actionSheet showInView:self.navigationController.view];
}

- (void)actionForFloor:(NSInteger)floor {
    
    NSString *selectedText = [self.webView stringByEvaluatingJavaScriptFromString:@"getSelectedText()"];
    
    if (![selectedText isKindOfClass:NSString.class]) {
        NSAssert(0, @"");
        return;
    }
    
    if (selectedText.length) {
        NSLog(@"selectedText %@", selectedText);
        return;
    }
    
    if (_posts.count < 1) {
        NSLog(@"not ready");
        return;
    }
    
    NSInteger s = [(HPNewPost *)_posts[0] floor];
    floor = floor - s + 1;
    
    if (floor < 1 || floor > _posts.count) {
        NSLog(@"wrong floor %ld", floor);
        return;
    }
    
    _current_action_post = [_posts objectAtIndex:floor-1];
    NSLog(@"floor %ld %@", floor, _current_action_post.user.username);
    
    IBActionSheet *actionSheet = [[IBActionSheet alloc]
                                  initWithTitle:nil
                                  delegate:self cancelButtonTitle:@"取消"
                                  destructiveButtonTitle:
                                  [self canEdit:_current_action_post] ?
                                    @"编辑" : @"举报"
                                  otherButtonTitles:
                                  @"回复",
                                  @"引用",
                                  @"查看签名",
                                  @"发送短消息",
                                  _current_author_uid != 0 ? @"查看全部" : @"只看该作者", nil];
    self.currentActionSheet = actionSheet;
    
    [actionSheet setButtonBackgroundColor:rgb(25.f, 25.f, 25.f)];
    [actionSheet setButtonTextColor:rgb(216.f, 216.f, 216.f)];
    [actionSheet setFont:[UIFont fontWithName:@"STHeitiSC-Light" size:20.f]];
    actionSheet.tag = 2;
    [actionSheet showInView:self.navigationController.view];
}

- (void)actionSheet:(IBActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    
    //NSLog(@"%@",actionSheet);
    NSLog(@"buttonIndex = %ld", buttonIndex);
    
    switch (actionSheet.tag) {
        case 1:
        {
            switch (buttonIndex) {
                case 0://举报
                {
                    if (_posts.count>=1 && [self canEdit:_posts[0]]) {
                        [self editThread];
                    } else if (_current_page > 1) {
                        [self reload:nil];
                    } else {
                        [self report];
                    }
                    break;
                }
                case 1://关注 or 收藏
                {
                    if ([Setting boolForKey:HPSettingPreferNotice]) {
                        [self favorite:nil];
                    } else {
                        [self attention:nil];
                    }
                    
                    break;
                }
                case 2://只看该作者
                {
                    [self toggleOnlySomeone:_thread.user];
                    break;
                }
                case 3://浏览器打开
                {
                    [self openUrl:[self pageUrl]];
                    break;
                }
                case 4:// adjust
                {
                    [self showAdjustView:nil];
                    break;
                }
                case 5://更多
                {
                    if (IOS8_OR_LATER) {
                        [self share:actionSheet];
                    } else {
                        IBActionSheet *actionSheet = [[IBActionSheet alloc]
                                                      initWithTitle:nil
                                                      delegate:self cancelButtonTitle:@"取消"
                                                      destructiveButtonTitle:nil
                                                      otherButtonTitles:
                                                      @"复制链接", @"复制全文",nil];
                        self.currentActionSheet = actionSheet;
                        
                        [actionSheet setButtonBackgroundColor:rgb(25.f, 25.f, 25.f)];
                        [actionSheet setButtonTextColor:rgb(216.f, 216.f, 216.f)];
                        [actionSheet setFont:[UIFont fontWithName:@"STHeitiSC-Light" size:20.f]];
                        actionSheet.tag = 3;
                        [actionSheet showInView:self.navigationController.view];
                    }
                    break;
                }
                
                default:
                    NSLog(@"error buttonIndex index, %ld", buttonIndex);
                    break;
            }
            break;
        }
        case 2:
        {
            switch (buttonIndex) {
                case 0://举报
                    if ([self canEdit:_current_action_post]) {
                        [self editPost:_current_action_post];
                    } else {
                        [self report];
                    }
                    break;
                case 1://回复
                {
                    [self replySomeone:nil];
                    break;
                }
                case 2://引用
                {
                    [self quoteSomeone:nil];
                    break;
                }
                case 3://查看签名
                {
                    [self viewSignature:_current_action_post];
                    break;
                }
                case 4://发送短消息
                    [self promptForSendMessage:_current_action_post];
                    break;
                case 5://只看该作者
                    [self toggleOnlySomeone:_current_action_post.user];
                    break;
                default:
                    NSLog(@"error buttonIndex index, %ld", buttonIndex);
                    break;
            }
            
            break;
        }
        case 3:
        {
            switch (buttonIndex) {
                case 0://copy link
                {
                    [self copyLink];
                    break;
                }
                case 1://copy text
                {
                    [self copyContent];
                    break;
                }
                default:
                    break;
            }
            break;
        }
        default:
            NSLog(@"error actionSheet.tag %ld", actionSheet.tag);
            break;
    }
    
}


# pragma mark - actions

- (NSURL *)pageUrl {
    NSString *url = [NSString stringWithFormat:@"%@/forum/viewthread.php?tid=%@&extra=&page=%@", HP_BASE_URL, @(_thread.tid), @(_current_page)];
    return [NSURL URLWithString:url];
}

- (void)openUrl:(NSURL *)url {
    
    if ([url.absoluteString hasPrefix:@"video://"]) {
        url = [NSURL URLWithString:[url.absoluteString stringByReplacingOccurrencesOfString:@"video://" withString:@"http://"]];
        
        // iOS9之后 用 SFSafariViewController
        if (!IOS9_OR_LATER) {
            [[UIApplication sharedApplication] openURL:url];
            return;
        }
    }
    
    if (![url.absoluteString hasPrefix:@"http://"] &&
        ![url.absoluteString hasPrefix:@"https://"]) {
        DDLogError(@"非法的url: %@", url.absoluteString);
        return;
    }
    
    // todo
    // setting safari
    if (IOS9_2_OR_LATER) { //iOS 9.2 自带滑动返回
        
        SFSafariViewController *sfvc = [[SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:sfvc animated:YES completion:NULL];
        
    }
        
    HPSFSafariViewController *sfvc = [[HPSFSafariViewController alloc] initWithURL:url];
    [self presentViewController:[HPCommon swipeableNVCWithRootVC:sfvc] animated:YES completion:NULL];
   
    [Flurry logEvent:@"Read OpenUrl" withParameters:@{@"url":url.absoluteString}];
}

- (void)openImage:(NSDictionary *)object
{
    NSLog(@"openImage %@", object);
    
    NSString *src = object[@"src"];
    CGRect rect = ({
        CGRect rect;
        rect.origin.x = [object[@"x"] doubleValue];
        rect.origin.y = [object[@"y"] doubleValue];
        rect.size.width = [object[@"width"] doubleValue];
        rect.size.height = [object[@"height"] doubleValue];
        rect;
    });
    rect.origin.y += HP_NAVBAR_HEIGHT;
    
    // cdn -> 原图url
    // 现在的交互形式是 用户点击小图(CDN压缩图片), 然后加载大图, 加载好大图来替换小图
    if ([src indexOf:HP_CDN_BASE_HOST] != -1) {
        src = [src hp_originalURL];
    }

    __block NSArray *images = nil;
    __block NSUInteger index = 0;
    [_posts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        HPNewPost *post = (HPNewPost *)obj;
        HPImageNode *node = [[HPImageNode alloc] initWithURL:src];
        if (post.images && (index = [post.images indexOfObject:node]) != NSNotFound) {
            images = [post.images hp_imageThumbnailURLs];
            *stop = YES;
        }
    }];
    
    if (!images) {
        images = @[src];
        index = 0;
    }
    
    void (^show)(UIImage *scaleImage) = ^(UIImage *scaleImage){
        IDMPhotoBrowser *browser = [[IDMPhotoBrowser alloc] initWithPhotoURLs:images
                                                             animatedFromView:[[UIView alloc] initWithFrame:rect]];
        
        browser.scaleImage = scaleImage;
        browser.displayActionButton = YES;
        browser.displayArrowButton = NO;
        browser.displayCounterLabel = YES;
        [browser setInitialPageIndex: index];
        
        browser.delegate = self;
        
        [self presentViewController:browser animated:NO completion:nil];
    };
    
    NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:[NSURL URLWithString:src]];
    if ([[SDImageCache sharedImageCache] sd_imageExistsForWithKey:key]) {
        [[SDWebImageManager sharedManager] downloadImageWithURL:[NSURL URLWithString:src] options:0 progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
            show(image);
        }];
    } else {
        show(nil);
    }
}

- (void)photoBrowser:(IDMPhotoBrowser *)photoBrowser didDismissAtPageIndex:(NSUInteger)index {
}

- (void)copyLink {
    NSString *url = [NSString stringWithFormat:@"%@/forum/viewthread.php?tid=%ld&extra=&page=%ld", HP_BASE_URL, _thread.tid, _current_page];
    UIPasteboard *pasteBoard = [UIPasteboard generalPasteboard];
    [pasteBoard setString:url];
    [SVProgressHUD showSuccessWithStatus:@"拷贝成功"];
    
    [Flurry logEvent:@"Read CopyLink"];
}

- (void)copyContent {
    NSString *content = [self textForSharing];
    UIPasteboard *pasteBoard = [UIPasteboard generalPasteboard];
    [pasteBoard setString:content];
    [SVProgressHUD showSuccessWithStatus:@"拷贝成功"];
    
    [Flurry logEvent:@"Read CopyContent"];
}

#pragma mark -

- (void)back:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
    
    if (_current_page == 1) {
        [HPNewPost cancelRequstOperationWithTid:_thread.tid];
    }
}


- (void)reply:(id)sender {
    
    HPReplyTopicViewController *sendvc = [[HPReplyTopicViewController alloc] initWithThread:_thread delegate:self];
    
    [self presentViewController:[HPCommon swipeableNVCWithRootVC:sendvc] animated:YES completion:nil];
    
    [Flurry logEvent:@"Read Reply"];
}

- (void)viewSignature:(HPNewPost *)post
{
    void (^showSignature)(NSString *signature) = ^(NSString *signature){
        if (signature.length) {
            [SVProgressHUD dismiss];
            HPViewSignatureViewController *vc = [[HPViewSignatureViewController alloc] initWithSignature:signature];
            [self.navigationController pushViewController:vc animated:YES];
        } else {
            [SVProgressHUD showErrorWithStatus:@"没有签名"];
        }
    };
    
    NSString *signature = post.signature;
    if (signature == nil) {
        [SVProgressHUD show];
        [HPUser getUserUidWithUserName:post.user.username block:^(NSString *uid, NSError *error) {
            if (error) {
                [SVProgressHUD showErrorWithStatus:error.localizedDescription];
                return;
            }
            [HPUser getUserSignatureWithUid:uid block:^(NSString *signature, NSError *error) {
                if (error) {
                    [SVProgressHUD showErrorWithStatus:error.localizedDescription];
                    return;
                }
                NSLog(@"%@", signature);
                showSignature(signature);
            }];
        }];
    } else {
        showSignature(signature);
    }
}

- (void)replySomeone:(id)sender {
    
    HPReplyViewController *sendvc =
    [[HPReplyViewController alloc] initWithPost:_current_action_post
                                     actionType:ActionTypeReply
                                         thread:_thread
                                           page:_current_page
                                       delegate:self];
    
    [self presentViewController:[HPCommon swipeableNVCWithRootVC:sendvc] animated:YES completion:nil];
    
    [Flurry logEvent:@"Read ReplySomeone"];
}

- (void)editThread {
    HPEditPostViewController *evc = [[HPEditPostViewController alloc] initWithPost:[_posts objectAtIndex:0] actionType:ActionTypeEditThread thread:_thread page:_current_page delegate:self];
    [self presentViewController:[HPCommon swipeableNVCWithRootVC:evc] animated:YES completion:nil];
    
    [Flurry logEvent:@"Read EditThread"];
}

- (void)editPost:(HPNewPost *)post {
    HPEditPostViewController *evc = [[HPEditPostViewController alloc] initWithPost:post actionType:ActionTypeEditPost thread:_thread page:_current_page delegate:self];
    [self presentViewController:[HPCommon swipeableNVCWithRootVC:evc] animated:YES completion:nil];
    
    [Flurry logEvent:@"Read EditPost"];
}

- (void)quoteSomeone:(id)sender {
    
    HPReplyViewController *sendvc =
    [[HPReplyViewController alloc] initWithPost:_current_action_post
                                     actionType:ActionTypeQuote
                                         thread:_thread
                                           page:_current_page
                                       delegate:self];
    
    [self presentViewController:[HPCommon swipeableNVCWithRootVC:sendvc] animated:YES completion:nil];
    
    [Flurry logEvent:@"Read QuoteSomeone"];
}

- (void)favorite:(id)sender {
 
    BOOL flag = [HPFavorite isFavoriteWithTid:_thread.tid];
    __weak typeof(self) weakSelf = self;
    
    if (!flag) {
        [SVProgressHUD showWithStatus:@"收藏中..."];
        
        [[HPFavorite sharedFavorite] favoriteWith:_thread block:^(BOOL isSuccess, NSError *error) {
            if (isSuccess) {
                NSLog(@"favorate success");
                [SVProgressHUD showSuccessWithStatus:@"收藏成功"];
                [weakSelf updateFavButton];
            } else {
                NSLog(@"favorate error %@", [error localizedDescription]);
                [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
            }
        }];
    } else {
        [SVProgressHUD showWithStatus:@"删除中..."];
        [[HPFavorite sharedFavorite] removeFavoritesWithTid:_thread.tid block:^(NSString *msg, NSError *error) {
            if (!error) {
                NSLog(@"un favorate success");
                [SVProgressHUD showSuccessWithStatus:@"删除成功"];
                [weakSelf updateFavButton];
            } else {
                NSLog(@"un favorate error %@", [error localizedDescription]);
                [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
            }
        }];
    }
    
    [Flurry logEvent:@"Read Favorite" withParameters:@{@"flag":@(flag)}];
}

- (void)attention:(id)sender {
    
    BOOL flag = [HPAttention isAttention:_thread.tid];
    __weak typeof(self) weakSelf = self;
    
    if (!flag) {
        [SVProgressHUD showWithStatus:@"关注中..."];
        
        [HPAttention addAttention:_thread block:^(BOOL isSuccess, NSError *error) {
            if (isSuccess) {
                NSLog(@"favorate success");
                [SVProgressHUD showSuccessWithStatus:@"关注成功"];
                [weakSelf updateAttentionButton];
            } else {
                NSLog(@"favorate error %@", [error localizedDescription]);
                [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
            }
        }];
    } else {
        [SVProgressHUD showWithStatus:@"取消关注中..."];
        [HPAttention removeAttention:_thread.tid block:^(NSString *msg, NSError *error) {
            if (!error) {
                NSLog(@"un favorate success");
                [SVProgressHUD showSuccessWithStatus:@"取消关注成功"];
                [weakSelf updateAttentionButton];
            } else {
                NSLog(@"un favorate error %@", [error localizedDescription]);
                [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
            }
        }];
    }
    
    [Flurry logEvent:@"Read AddAttention" withParameters:@{@"flag":@(flag)}];
}

- (void)toggleOnlySomeone:(HPUser *)user {
    
    if (!user) {
        // 在帖子未载入之前, _thread.user = nil
        [SVProgressHUD showErrorWithStatus:@"请稍候"];
        return;
    }
    
    if (!_current_author_uid) {

        _current_author_uid = user.uid;
        NSLog(@"_current_author_uid %ld", _current_author_uid);
        
        [SVProgressHUD showWithStatus:[NSString stringWithFormat:@"只看%@的发言...", user.username]];
        [self load:YES];
        
    } else {
        
        _current_author_uid = 0;
        [SVProgressHUD showWithStatus:@"显示全部帖子..."];
        _thread.pageCount = 0;
        [self load:YES];
    }
    
    [Flurry logEvent:@"Read OnlySomeone" withParameters:@{@"flag":@(!_current_author_uid)}];
}




- (void)jumpToFloor:(NSInteger)floor {
    
    if (!floor) floor = _gotoFloor;
   
    [self callWebviewJumpToFloor:floor];
    
    _gotoFloor = 0;
}

- (void)callWebviewJumpToFloor:(NSInteger)floor {
    NSString *js = [NSString stringWithFormat:@"jumpToFloor(%ld, %@);", floor, @(IOS11_OR_LATER)];
    [self.webView stringByEvaluatingJavaScriptFromString:js];
}

- (void)gotoFloorWithUrl:(NSString *)url {
    NSArray *arr = [url componentsSeparatedByString:@"_"];
    if (arr.count != 2) {
        return;
    }
    NSInteger floor = [[arr objectAtIndex:0] integerValue];
    NSInteger pid = [[arr objectAtIndex:1] integerValue];
    __block BOOL flag = NO;
    
    //  检查本页是否有 这个 floor
    
    if (floor != 0) [_posts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        HPNewPost *post = (HPNewPost *)obj;
        if (post.floor == floor) {
            
            flag = YES;
            *stop = YES;
        }
    }];
    
    if (flag) {
        [SVProgressHUD showSuccessWithStatus:S(@"跳转到%ld楼", floor)];
        [self jumpToFloor:floor];
    } else {
        UIViewController *rvc = [[PostViewControllerClass() alloc]   initWithThread:_thread
            find_pid:pid];
        
        [self.navigationController pushViewController:rvc animated:YES];
    }
}


- (void)jumpToPage:(NSInteger)page {
    
    if (_current_page != page) {
        _current_page = page;
        [self load];
    } else {
        [SVProgressHUD showErrorWithStatus:@"当前页"];
    }
    
    [self dimissPageView:nil];
}

- (void)goToPage:(id)sender {
    
    float value = _pageSlider.value;
    int page = 0;
    if (value == _pageSlider.maximumValue) {
        page = (int)value;
    } else {
        page = (int)(value) + 1;
    }
    
    [self jumpToPage:page];
    
    int pageCount = _thread.pageCount?:0;
    [Flurry logEvent:@"Read GotoPage" withParameters:@{@"page":[NSString stringWithFormat:@"%d/%d", page, pageCount]}];
}

- (void)prevPage:(id)sender {
    
    if (_current_page <= 1) {
        [SVProgressHUD showErrorWithStatus:@"已经是第一页"];
    } else {
        _current_page--;
        [self load];
        
        if ([sender isKindOfClass:[UIButton class]]) {
            [self dimissPageView:nil];
        }
    }
    
    [Flurry logEvent:@"Read JumpPage" withParameters:@{@"action":@"PrevPage"}];
}

- (BOOL)canNext {
    
    if (_current_page < _thread.pageCount) {
        return YES;
    } else if (_thread.pageCount == 0) {
        return YES;
    }
    
    return NO;
}

- (void)nextPage:(id)sender {
    
    if (![self canNext]) {
        [SVProgressHUD showErrorWithStatus:@"已经是最后一页"];
    } else {
        
        _current_page++;
        [self load];
        
        if ([sender isKindOfClass:[UIButton class]]) {
            [self dimissPageView:nil];
        }
    }
    
    [Flurry logEvent:@"Read JumpPage" withParameters:@{@"action":@"NextPage"}];
}

- (void)topPage {
    [self jumpToPage:1];
    
    [Flurry logEvent:@"Read JumpPage" withParameters:@{@"action":@"TopPage"}];
}

- (void)tailPage {
    [self jumpToPage:_thread.pageCount];
    
    [Flurry logEvent:@"Read JumpPage" withParameters:@{@"action":@"TailPage"}];
}



- (void)sendMessageTo:(NSString *)username
              message:(NSString *)message {
    
    if (!message || [message isEqualToString:@""]) {
        [SVProgressHUD showErrorWithStatus:@"消息内容不能为空"];
        return;
    }
    
    [self.view endEditing:YES];
    [SVProgressHUD showWithStatus:@"发送中..." maskType:SVProgressHUDMaskTypeBlack];
    [HPMessage sendMessageWithUsername:username message:message block:^(NSError *error) {
        if (error) {
            [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
        } else {
            [SVProgressHUD showSuccessWithStatus:@"已送达"];
        }
    }];
}

- (void)promptForSendMessage:(HPNewPost *)post {
    NSString *title = [NSString stringWithFormat:@"收件人: %@", post.user.username];
    [UIAlertView showSendMessageDialogWithTitle:title handler:^(UIAlertView *alertView, NSInteger buttonIndex) {
        
        if (buttonIndex == [alertView cancelButtonIndex]) {
            
            ;
            
        } else {
            UITextField *content = [alertView textFieldAtIndex:0];
            NSString *message = content.text;
            [self sendMessageTo:post.user.username message:message];
        }
    }];
    
    [Flurry logEvent:@"Read SendMessage"];
}

- (void)report {
    
    [UIAlertView showConfirmationDialogWithTitle:@"举报"
                                         message:@"您确定要举报当前内容为不适合浏览吗?"
                                         handler:^(UIAlertView *alertView, NSInteger buttonIndex)
     {
         if (buttonIndex != [alertView cancelButtonIndex]) {
             
             HPUser *user = nil;
             if (!_current_action_post) user = _thread.user;
             else user = _current_action_post.user;
             
             [HPMessage report:user.username message:@"当前内容为不适合浏览"
                         block:^(NSError *error) {
                             [SVProgressHUD showSuccessWithStatus:@"已收到您的建议, 我们会尽快处理!"];
                         }];
         }
     }];
    
    [Flurry logEvent:@"Read Report"];
}

# pragma mark - pageView

- (UIView *)pageView {
    
    if (!_pageView) {
        
        _pageView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, self.view.bounds.size.width, 82.0f + [UIDevice hp_safeAreaInsets].bottom)];
        
        if (![Setting boolForKey:HPSettingNightMode]) {
            _pageView.backgroundColor = [UIColor whiteColor];
        } else {
            _pageView.backgroundColor = [HPTheme backgroundColor];
        }
       
        _pageSlider = [[UISlider alloc] initWithFrame:CGRectMake(10.0f,5.0f,HP_SCREEN_WIDTH-60,30.0f)];
        _pageSlider.continuous = YES ;
        [_pageSlider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
        _pageSlider.userInteractionEnabled = YES;
        _pageSlider.maximumValue = 100.0f;
        _pageSlider.minimumValue = 0.0f;
        _pageSlider.value = 1.0f;
        
        UIButton *goButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        goButton.frame = CGRectMake(_pageSlider.frame.size.width+_pageSlider.frame.origin.x, 0, 50, 40.f);
        [goButton setTitle:@"Go" forState:UIControlStateNormal];
        [goButton addTarget:self action:@selector(goToPage:) forControlEvents:UIControlEventTouchUpInside];
        
        
        CGFloat margin = 1.f;
        CGFloat width = ( self.view.bounds.size.width - margin * 4 ) / 5.f;
        
        UIButton *topPage = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        topPage.frame = CGRectMake(0, 40, width, 42);
        topPage.backgroundColor = [HPTheme backgroundColor];
        [topPage setTitle:@"首页" forState:UIControlStateNormal];
        [topPage addTarget:self action:@selector(topPage) forControlEvents:UIControlEventTouchUpInside];
        
        UIButton *prevPage = [UIButton buttonWithType:UIButtonTypeRoundedRect];//[UIButton buttonWithType:UIButtonTypeCustom];
        prevPage.frame = CGRectMake((width+margin)*1,  40, width, 42);
        prevPage.backgroundColor = [HPTheme backgroundColor];
        [prevPage setTitle:@"上一页" forState:UIControlStateNormal];
        [prevPage addTarget:self action:@selector(prevPage:) forControlEvents:UIControlEventTouchUpInside];
        
        _pageLabel = [[UILabel alloc]initWithFrame: CGRectMake((width+margin)*2,  40, width, 42)];
        _pageLabel.backgroundColor = [HPTheme backgroundColor];
        _pageLabel.text = @"0/0";
        _pageLabel.textAlignment = NSTextAlignmentCenter;
        _pageLabel.textColor = [UIColor colorWithRed:0.0f / 255.0 green:126.0f / 255.0 blue:245.0 / 255.0 alpha:1.0];
        
        UIButton *nextPage = [UIButton buttonWithType:UIButtonTypeRoundedRect];//[UIButton buttonWithType:UIButtonTypeCustom];
        nextPage.frame = CGRectMake((width+margin)*3,  40, width, 42);
        nextPage.backgroundColor = [HPTheme backgroundColor];
        [nextPage setTitle:@"下一页" forState:UIControlStateNormal];
        [nextPage addTarget:self action:@selector(nextPage:) forControlEvents:UIControlEventTouchUpInside];
        
        
        UIButton *tailPage = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        tailPage.frame = CGRectMake((width+margin)*4, 40, width, 42);
        tailPage.backgroundColor = [HPTheme backgroundColor];
        [tailPage setTitle:@"末页" forState:UIControlStateNormal];
        [tailPage addTarget:self action:@selector(tailPage) forControlEvents:UIControlEventTouchUpInside];
        
        [_pageView addSubview:goButton];
        [_pageView addSubview:_pageSlider];
        
        [_pageView addSubview:topPage];
        [_pageView addSubview:prevPage];
        [_pageView addSubview:_pageLabel];
        [_pageView addSubview:nextPage];
        [_pageView addSubview:tailPage];
    }
    return _pageView;
}

- (void)showPageView:(id)sender {
    [self presentSemiView:self.pageView withOptions:@{
                                                      KNSemiModalOptionKeys.pushParentBack : @(NO),
                                                      KNSemiModalOptionKeys.animationDuration : @(0.3)
                                                      }];
    
    _pageSlider.maximumValue = _thread.pageCount;
    _pageSlider.minimumValue = 0;
    _pageSlider.value = _current_page - 1;
    [self sliderValueChanged:nil];
    
    [Flurry logEvent:@"Read ShowPagePanel"];
}

- (void)dimissPageView:(id)sender {
    [self dismissSemiModalView];
}

- (void)sliderValueChanged:(id)sender{
    
    float value = _pageSlider.value;
    int page = 0;
    if (value == _pageSlider.maximumValue) {
        page = (int)value;
    } else {
        page = (int)(value) + 1;
    }
    
    //NSLog(@"value %f page %d", value, page);
    [_pageLabel setText:[NSString stringWithFormat:@"%d/%ld", page, _thread.pageCount]];
}


# pragma mark - adjustView

- (UIView *)adjustView {
    
    if (!_adjustView) {
        
        CGFloat height = 150.f + [UIDevice hp_safeAreaInsets].bottom;
        
        _adjustView = [[UIView alloc] initWithFrame:CGRectMake(0.f, self.view.bounds.size.height - height, self.view.bounds.size.width, height)];
    
        _adjustView.alpha = 0.f;
        [self.view addSubview:[self adjustView]];
        
        CGRect f = _adjustView.frame;
        
        if (![Setting boolForKey:HPSettingNightMode]) {
            _adjustView.backgroundColor = [UIColor whiteColor];
        } else {
            _adjustView.backgroundColor = [HPTheme backgroundColor];
        }
        
        
        UILabel *nightLabel = [UILabel new];
        [_adjustView addSubview:nightLabel];
        nightLabel.text = @"夜间模式";
        [nightLabel sizeToFit];
        nightLabel.textColor = [HPTheme  blackOrWhiteColor];
        nightLabel.backgroundColor = [UIColor clearColor];
        nightLabel.center = CGPointMake(nightLabel.frame.size.width/2 + 20.f, f.size.height/5*1);
        
        UISwitch *nightSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
        [_adjustView addSubview:nightSwitch];
        [nightSwitch addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
        nightSwitch.center = CGPointMake(nightLabel.frame.origin.x + nightLabel.frame.size.width +  nightSwitch.frame.size.width/2 + 10.f, f.size.height/5*1);
        nightSwitch.backgroundColor = [UIColor clearColor];
		[nightSwitch setAccessibilityLabel:@"夜间模式"];
        nightSwitch.on = [Setting boolForKey:HPSettingNightMode];
        
        UILabel *boldLabel = [UILabel new];
        [_adjustView addSubview:boldLabel];
        boldLabel.text = @"关闭细体";
        [boldLabel sizeToFit];
        boldLabel.textColor = [HPTheme  blackOrWhiteColor];
        boldLabel.backgroundColor = [UIColor clearColor];
        boldLabel.center = CGPointMake(nightSwitch.frame.origin.x +
                                       nightSwitch.frame.size.width +
                                       boldLabel.frame.size.width/2.f +
                                       + 40.f, f.size.height/5*1);
        
        UISwitch *boldSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
        [_adjustView addSubview:boldSwitch];
        [boldSwitch addTarget:self action:@selector(regularFontSwitchAction:) forControlEvents:UIControlEventValueChanged];
        boldSwitch.center = CGPointMake(boldLabel.frame.origin.x + boldLabel.frame.size.width +  boldSwitch.frame.size.width/2 + 10.f, f.size.height/5*1);
        boldSwitch.backgroundColor = [UIColor clearColor];
        [boldSwitch setAccessibilityLabel:@"关闭细体"];
        boldSwitch.on = [Setting boolForKey:HPSettingRegularFontMode];
        
        /*
        UILabel *brightnessLabel = [UILabel new];
        [_adjustView addSubview:brightnessLabel];
        brightnessLabel.text = @"亮度";
        [brightnessLabel sizeToFit];
        brightnessLabel.textColor = [HPTheme  blackOrWhiteColor];
        brightnessLabel.center = CGPointMake(nightSwitch.frame.origin.x + nightSwitch.frame.size.width + brightnessLabel.frame.size.width/2 + 15.f, f.size.height/5*1);
        
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(brightnessLabel.frame.origin.x + brightnessLabel.frame.size.width + 5.f, f.size.height/5*1 - 5.f, 120.0, 7.0)];
        [_adjustView addSubview:slider];
        [slider addTarget:self action:@selector(sliderAction:) forControlEvents:UIControlEventValueChanged];
        //slider.backgroundColor = [UIColor clearColor];
        slider.minimumValue = 0.0;
        slider.maximumValue = 100.0;
        slider.continuous = YES;
        slider.value = 50.0;
        */
        UILabel *label = [UILabel new];
        [_adjustView addSubview:label];
        label.text = @"字号调整";
        [label sizeToFit];
        label.textColor = [HPTheme  blackOrWhiteColor];
        label.backgroundColor = [UIColor clearColor];
        label.center = CGPointMake(label.frame.size.width/2 + 20.f, f.size.height/4*2);
        
        _fontSizeLabel = [UILabel new];
        [_adjustView addSubview:_fontSizeLabel];
        _fontSizeLabel.text = S(@"%ld%%", _currentFontSize);
        _fontSizeLabel.font = [UIFont fontWithName:@"STHeitiSC-Light" size:20.f];
        [_fontSizeLabel sizeToFit];
        _fontSizeLabel.textColor = [HPTheme  blackOrWhiteColor];
        _fontSizeLabel.backgroundColor = [UIColor clearColor];
        _fontSizeLabel.center = CGPointMake(label.frame.size.width + label.frame.origin.x + _fontSizeLabel.frame.size.width/2 + 10.f, f.size.height/4*2);
    
        
        _fontsizeStepper = [UIStepper new];
        [_adjustView addSubview:_fontsizeStepper];
        [_fontsizeStepper sizeToFit];
        _fontsizeStepper.center = CGPointMake(f.size.width - _fontsizeStepper.frame.size.width/2 - 20.f, f.size.height/4*2);
        _fontsizeStepper.tag = fontSizeStepperTag;
        
        _fontsizeStepper.minimumValue = 50;
        _fontsizeStepper.maximumValue = 200;
        _fontsizeStepper.stepValue = 5;
        _fontsizeStepper.value = _currentFontSize;
        
        [_fontsizeStepper addTarget:self action:@selector(stepperAction:) forControlEvents:UIControlEventValueChanged];
        
        
        UILabel *label2 = [UILabel new];
        [_adjustView addSubview:label2];
        label2.text = @"行距调整";
        [label2 sizeToFit];
        label2.textColor = [HPTheme  blackOrWhiteColor];
        label2.backgroundColor = [UIColor clearColor];
        label2.center = CGPointMake(label2.frame.size.width/2 + 20.f, f.size.height/4*3);
        
        _lineHeightLabel = [UILabel new];
        [_adjustView addSubview:_lineHeightLabel];
        _lineHeightLabel.text = S(@"%ld%%", _currentLineHeight);
        _lineHeightLabel.font = [UIFont fontWithName:@"STHeitiSC-Light" size:20.f];
        [_lineHeightLabel sizeToFit];
        _lineHeightLabel.textColor = [HPTheme  blackOrWhiteColor];
        _lineHeightLabel.backgroundColor = [UIColor clearColor];
        _lineHeightLabel.center = CGPointMake(label.frame.size.width + label.frame.origin.x + _lineHeightLabel.frame.size.width/2 + 10.f, f.size.height/4 * 3);
        
        
        _lineHeightStepper = [UIStepper new];
        [_adjustView addSubview:_lineHeightStepper];
        [_lineHeightStepper sizeToFit];
        _lineHeightStepper.center = CGPointMake(f.size.width - _lineHeightStepper.frame.size.width/2 - 20.f, f.size.height/4 * 3);
        _lineHeightStepper.tag = lineHeightStepperTag;
        
        _lineHeightStepper.minimumValue = 80;
        _lineHeightStepper.maximumValue = 200;
        _lineHeightStepper.stepValue = 5;
        _lineHeightStepper.value = _currentLineHeight;
        
        [_lineHeightStepper addTarget:self action:@selector(stepperAction:) forControlEvents:UIControlEventValueChanged];
    
    
    }
    
    return _adjustView;
}

- (void)stepperAction:(id)sender
{
    UIStepper *actualStepper = (UIStepper *)sender;
    NSLog(@"stepperAction: value = %f", [actualStepper value]);
    
    if (actualStepper.tag == fontSizeStepperTag) {
        
        _currentFontSize = (int)actualStepper.value;
        [Setting saveInteger:_currentFontSize forKey:HPSettingFontSizeAdjust];
        
        _fontSizeLabel.text = S(@"%ld%%", _currentFontSize);
        [_fontSizeLabel sizeToFit];
        
        [self changeFontSize];
        [Flurry logEvent:@"Read ChangeFontSize" withParameters:@{@"size":@(_currentFontSize)}];
        
    } else if (actualStepper.tag == lineHeightStepperTag) {
        
        _currentLineHeight = (int)actualStepper.value;
        [Setting saveInteger:_currentLineHeight forKey:HPSettingLineHeightAdjust];
        
        _lineHeightLabel.text = S(@"%ld%%", _currentLineHeight);
        [_lineHeightLabel sizeToFit];
        
        [self changeLineHeight];
        [Flurry logEvent:@"Read ChangeLineHeight" withParameters:@{@"height":@(_currentLineHeight)}];
        
    } else {
        ;
    }
}

- (void)switchAction:(id)sender
{
	NSLog(@"switchAction: value = %d", [sender isOn]);
    
    [Setting saveBool:[sender isOn] forKey:HPSettingNightMode];
    [self themeDidChanged];
    
    [Flurry logEvent:@"Read ToggleDarkTheme" withParameters:@{@"is_dark":@([sender isOn])}];
}

- (void)regularFontSwitchAction:(id)sender
{
    NSLog(@"switchAction: value = %d", [sender isOn]);
    
    [Setting saveBool:[sender isOn] forKey:HPSettingRegularFontMode];
    [self themeDidChanged];
}

/*
- (void)sliderAction:(id)sender
{
    UISlider *slider = (UISlider *)sender;
    NSLog(@"sliderAction: value = %f", [slider value]);
}
*/
- (void)changeFontSize
{
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%@%%'", @(self.currentFontSize)];
    
    // https://forums.developer.apple.com/thread/51079
    if (IS_IPAD && IOS10_OR_LATER) {
        jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.fontSize='%dpx'", (int)(self.currentFontSize/100.f*16)];
    }
    
    [self.webView evaluateJavaScript:jsString completionHandler:nil];
}

- (void)changeLineHeight
{
    NSString *jsString = [[NSString alloc] initWithFormat:@"addNewStyle('body {line-height:%i%% !Important;}')",
                          _currentLineHeight];
    
    [self.webView evaluateJavaScript:jsString completionHandler:nil];
}



- (void)showAdjustView:(id)sender {
    
    [self adjustView];
    
    if (!_semiTransparentView) {
        self.semiTransparentView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        UITapGestureRecognizer *cancelTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dimissAdjustView:)];
        [self.semiTransparentView addGestureRecognizer:cancelTap];
        self.semiTransparentView.backgroundColor = [UIColor blackColor];
        self.semiTransparentView.alpha = 0.0f;
        
        [self.view insertSubview:self.semiTransparentView belowSubview:_adjustView];
    }
    
    
    [UIView animateWithDuration:0.5f
                     animations:^() {
                         self.semiTransparentView.alpha = 0.2f;
                         self.adjustView.alpha = 1.0f;
                     }];
    
    [Flurry logEvent:@"Read ShowAjustPanel"];
}

- (void)dimissAdjustView:(id)sender {
    [UIView animateWithDuration:0.5f
                     animations:^() {
                         self.semiTransparentView.alpha = 0.0f;
                         self.adjustView.alpha = 0.0f;
                     }];
}


#pragma mark - indicator
// todo
// indicator 独立出来 类似 svprogress
- (UIActivityIndicatorView *)indicator {
    if (_indicator) {
        return _indicator;
    } else {
        _indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        CGRect frame = [UIScreen mainScreen].bounds;
        _indicator.frame = CGRectMake(frame.size.width / 2 - 20.0f, frame.size.height / 2 - 20.0f, 40.0f, 40.0f);
        [[UIApplication sharedApplication].keyWindow addSubview:_indicator];
        [_indicator setActivityIndicatorViewStyle:[HPTheme indicatorViewStyle]];
        return _indicator;
    }
}

- (void)indicatorStop {
    [self.indicator removeFromSuperview];
    self.indicator = nil;
}


#pragma mark - drag load pre & next

- (void)dragToPreviousPage {
    
    [self prevPage:nil];
    [self transition:StoryTransitionTypePrevious];
    
    [Flurry logEvent:@"Read DragToPage" withParameters:@{@"action":@"dragToPreviousPage"}];
}
- (void)dragToNextPage {
    
    [self nextPage:nil];
    [self transition:StoryTransitionTypeNext];
    [Flurry logEvent:@"Read DragToPage" withParameters:@{@"action":@"dragToNextPage"}];
}

- (void)transition:(StoryTransitionType)transitionType {
    
    CABasicAnimation *stretchAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale.y"];
    [stretchAnimation setToValue:[NSNumber numberWithFloat:1.02]];
    [stretchAnimation setRemovedOnCompletion:YES];
    [stretchAnimation setFillMode:kCAFillModeRemoved];
    [stretchAnimation setAutoreverses:YES];
    [stretchAnimation setDuration:0.15];
    [stretchAnimation setDelegate:self];
    
    [stretchAnimation setBeginTime:CACurrentMediaTime() + 0.35];
    
    [stretchAnimation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [self.view setAnchorPoint:CGPointMake(0.0, (transitionType==StoryTransitionTypeNext)?1:0) forView:self.view];
    [self.view.layer addAnimation:stretchAnimation forKey:@"stretchAnimation"];
    
    CATransition *animation = [CATransition animation];
    [animation setType:kCATransitionPush];
    [animation setSubtype:(transitionType == StoryTransitionTypeNext ? kCATransitionFromTop : kCATransitionFromBottom)];
    [animation setDuration:0.5f];
    [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [[self.webView layer] addAnimation:animation forKey:nil];
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    [self.view setAnchorPoint:CGPointMake(0.5, 0.5) forView:self.view];
}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView{
	
	if (scrollView.isDragging &&
        ([Setting boolForKey:HPSettingIsPullReply] || !_lastPage))
    {
		if (_refreshHeaderView.state == EGOOPullRefreshPulling && scrollView.contentOffset.y > TRIGGER_OFFSET_Y && scrollView.contentOffset.y < 0.0f && !_reloadingHeader) {
			[_refreshHeaderView setState:EGOOPullRefreshNormal];
		} else if (_refreshHeaderView.state == EGOOPullRefreshNormal && scrollView.contentOffset.y < TRIGGER_OFFSET_Y && !_reloadingHeader) {
			[_refreshHeaderView setState:EGOOPullRefreshPulling];
		}
        
        float endOfTable = [self endOfTableView:scrollView];
        if (_refreshFooterView.state == EGOOPullRefreshPulling && endOfTable < 0.0f && endOfTable > TRIGGER_OFFSET_Y && !_reloadingFooter) {
			[_refreshFooterView setState:EGOOPullRefreshNormal];
            
            if (_lastPage && [Setting boolForKey:HPSettingIsPullReply]) {
                [_refreshFooterView setState:EGOOPullRefreshNoMore];
            }
            
		} else if (_refreshFooterView.state == EGOOPullRefreshNormal && endOfTable < TRIGGER_OFFSET_Y && !_reloadingFooter) {
			[_refreshFooterView setState:EGOOPullRefreshPulling];
		}
	}
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate{
	
	if (scrollView.contentOffset.y <= TRIGGER_OFFSET_Y && !_reloadingHeader) {
        _reloadingHeader = YES;
        [self dragToPreviousPage];
	}
    
    
    if ([self endOfTableView:scrollView] <= TRIGGER_OFFSET_Y && !_reloadingFooter) {
        
        if (!_lastPage) {
            _reloadingFooter = YES;
            _refreshFooterView.hidden = YES;
            [self dragToNextPage];
        } else {
            if ([Setting boolForKey:HPSettingIsPullReply]) [self reply:nil];
        }
	}
}

- (CGFloat)contentSize {
    // return height of table view
    return [self.webView.scrollView contentSize].height + [UIDevice hp_safeAreaInsets].bottom;
}

- (float)endOfTableView:(UIScrollView *)scrollView {
    return [self contentSize] - scrollView.bounds.size.height - scrollView.bounds.origin.y;
}


#pragma mark - login

- (void)loginError:(NSNotification *)notification
{
    NSError *error = [[notification userInfo] objectForKey:@"error"];
    [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
}

- (void)loginSuccess:(NSNotification *)notification
{
    [SVProgressHUD showSuccessWithStatus:@"重新登录成功"];
    [self reload:nil];
}

# pragma mark - reply done
- (void)compositionDoneWithType:(ActionType)type error:(NSError *)error {
    
    if (type == ActionTypeEditThread || type == ActionTypeEditPost) {
        [self reload:nil];
        return;
    }
    
    void (^jumpBlock)(void) = ^void(void) {
        _reloadingForReply = YES;
        _current_page = _thread.pageCount;
        [self reload:nil];
    };
    
    BOOL isShowConfirm = [Setting boolForKey:HPSettingAfterSendShowConfirm];
    BOOL isAutoJump = [Setting boolForKey:HPSettingAfterSendJump];
    if (isShowConfirm) {
        [UIAlertView showConfirmationDialogWithTitle:@"发送成功"
                                             message:@"是否查看？"
                                             handler:^(UIAlertView *alertView, NSInteger buttonIndex)
         {
             if (buttonIndex != [alertView cancelButtonIndex]) {
                jumpBlock();
             }
         }];
    } else {
        if (isAutoJump) {
            jumpBlock();
        } else {
            ;
        }
    }
}

#pragma mark - theme
- (void)themeDidChanged {
   
    [[HPRearViewController sharedRearVC] themeDidChanged];
    //http://stackoverflow.com/questions/21652957/uinavigationbar-appearance-refresh
    self.navigationController.navigationBar.barStyle = [UINavigationBar appearance].barStyle;
    self.view.backgroundColor = [HPTheme backgroundColor];
    [self reload:nil];
    
}

#pragma mark - HPStupidBarDelegate

- (void)leftBtnTap {
    HPStupidBarAction type = [Setting integerForKey:HPSettingStupidBarLeftAction];
    [self actionForType:type];
    [Flurry logEvent:@"Read StupidBar" withParameters:@{@"pos":@"left", @"action":@(type)}];
}
- (void)centerBtnTap {
    HPStupidBarAction type = [Setting integerForKey:HPSettingStupidBarCenterAction];
    [self actionForType:type];
    [Flurry logEvent:@"Read StupidBar" withParameters:@{@"pos":@"center", @"action":@(type)}];
}
- (void)rightBtnTap {
    HPStupidBarAction type = [Setting integerForKey:HPSettingStupidBarRightAction];
    [self actionForType:type];
    [Flurry logEvent:@"Read StupidBar" withParameters:@{@"pos":@"right", @"action":@(type)}];
}

- (void)actionForType:(HPStupidBarAction)type {
    switch (type) {
        case HPStupidBarActionFavorite:
        {
            [self favorite:nil];
            [self updateFavButton];
            break;
        }
        case HPStupidBarActionAttention:
        {
            [self attention:nil];
            [self updateAttentionButton];
            break;
        }
        case HPStupidBarActionShowPageView:
        {
            [self showPageView:nil];
            break;
        }
        case HPStupidBarActionPrevPage:
        {
            [self prevPage:nil];
            break;
        }
        case HPStupidBarActionNextPage:
        {
            [self nextPage:nil];
            break;
        }
        case HPStupidBarActionReply:
        {
            [self reply:nil];
            break;
        }
        case HPStupidBarActionOnlyLz:
        {
            [self toggleOnlySomeone:_thread.user];
            break;
        }
        case HPStupidBarActionReload:
        {
            [self reload:nil];
            break;
        }
        case HPStupidBarActionScrollBottom:
        {
            [self webViewScrollToBottom:nil];
            break;
        }
        case HPStupidBarActionJ:
        {
            [self j];
            break;
        }
        case HPStupidBarActionK:
        {
            [self k];
            break;
        }
        default:
            break;
    }
}

#pragma mark - in memory of GR

- (void)reset {
    
    CGPoint p = self.webView.scrollView.contentOffset;
    
    NSString *floorString = [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:
          @"var y = %f;"
          @"var list = document.getElementsByClassName('info');"
          @"var r;"
          @"for (var i=0, len=list.length; i < len; i++) { if (list[i].offsetTop >= y) { r = list[i]; break;}}"
          @"var p = r.parentNode.getAttribute('data-id'); p;", p.y]];
    if ([floorString isKindOfClass:NSString.class] && floorString.length) {
        NSInteger f = [[floorString stringByReplacingOccurrencesOfString:@"floor://" withString:@""] integerValue];
        _current_floor = f;
    }
}

- (void)j {
    [self reset];
    _current_floor++;
    [self jump];
}

- (void)k {
    [self reset];
    _current_floor--;
    [self jump];
}

- (void)jump {
    
    if (_posts.count < 1) {
        return;
        NSLog(@"not ready");
    }

    int start = [(HPNewPost *)_posts[0] floor];
    int end = [(HPNewPost *)_posts[0] floor] + _posts.count - 1;
    
    if (_current_floor > end) {
        _current_floor =  end;
    }
    if (_current_floor < start) {
        _current_floor = start;
    }
    
    [self callWebviewJumpToFloor:_current_floor];
}

#pragma mark -
- (BOOL)canEdit:(HPNewPost *)post {
    return [[[NSStandardUserDefaults stringForKey:kHPAccountUserName or:@""] lowercaseString]
     isEqualToString:[post.user.username lowercaseString]];
}

#pragma mark -
- (void)exportPDF
{
    [SVProgressHUD show];
    [self.webView stringByEvaluatingJavaScriptFromString:@"clearBackgroudColor();"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewPrintFormatter *fmt = [self.webView viewPrintFormatter];
        HPPDFPrintPageRenderer *render = [[HPPDFPrintPageRenderer alloc] init];
        [render addPrintFormatter:fmt startingAtPageAtIndex:0];
        NSData *pdfData = [render printToPDF];
        
        [SVProgressHUD dismiss];
        [HPPDFPreviewViewController presentInViewController:self pdfData:pdfData];
        
        [self.webView stringByEvaluatingJavaScriptFromString:@"restoreBackgroudColor();"];
    });
}

- (void)share:(id)sender {
    NSMutableArray *activityItems = [@[] mutableCopy];
    [activityItems addObject:[self pageUrl]];
    //[activityItems addObject:self.htmlString];
    [activityItems addObject:[self textForSharing]];
    
    __weak typeof(self) weakSelf = self;
    UIActivity *copyLink = [HPActivity activityWithType:@"HPCopyLink"
                                             title:@"复制链接"
                                             image:[UIImage imageNamed:@"activity_copy_link"]
                                       actionBlock:^{
                                           [weakSelf copyLink];
                                       }];
    
    UIActivity *copyContent = [HPActivity activityWithType:@"HPCopyContent"
                                                title:@"复制全文"
                                                image:[UIImage imageNamed:@"activity_copy_content"]
                                          actionBlock:^{
                                              [weakSelf copyContent];
                                          }];
    
    UIActivity *exportPDF = [HPActivity activityWithType:@"HPExportPDF"
                                                   title:@"导出PDF"
                                                   image:[UIImage imageNamed:@"activity_export_pdf"]
                                             actionBlock:^{
                                                 [weakSelf exportPDF];
                                             }];
    UIActivity *viewHTML = [HPActivity activityWithType:@"HPViewHTML"
                                                  title:@"查看源代码"
                                                  image:[UIImage imageNamed:@"activity_copy_content"]
                                            actionBlock:^{
                                                HPViewHTMLController *vc = [HPViewHTMLController new];
                                                vc.html = weakSelf.htmlString;
                                                [weakSelf.navigationController pushViewController:vc animated:YES];
                                            }];
    
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:@[copyLink, copyContent, exportPDF, viewHTML]];
    
    activityViewController.excludedActivityTypes = @[UIActivityTypeCopyToPasteboard];
    
    if (IS_IPAD && IOS8_OR_LATER) {
        activityViewController.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems[1];
    }

    [activityViewController setCompletionHandler:^(NSString *activityType, BOOL completed) {
        NSLog(@"activityType %@, completed %d", activityType, completed);
    }];
    
    [self presentViewController:activityViewController animated:YES completion:nil];
}

- (NSString *)textForSharing {
    
    NSMutableString *string = [NSMutableString string];
    
    NSString *info =
    [NSString stringWithFormat:
     @"标题: %@\n"
     @"页码: %@\n"
     @"地址: %@\n"
     @"\n", self.thread.title, [self pageInfoString], [self pageUrl]];
   
    [string appendString:info];
    
    for (HPNewPost *post in self.posts) {
        NSString *item =
        [NSString stringWithFormat:
         @"#%@, %@, %@\n"
         @"%@\n"
         @"\n",
         @(post.floor), post.user.username, [HPNewPost fullDateString:post.date],
         [post.body_html stringByConvertingHTMLToPlainText]];
        
        [string appendString:item];
    }
    
    return [NSString stringWithString:string];
}

@end
