//
//  HPReadViewController.m
//  HiPDA
//
//  Created by wujichao on 14-2-27.
//  Copyright (c) 2014年 wujichao. All rights reserved.
//

#import "HPReadViewController.h"
#import "HPReplyTopicViewController.h"
#import "HPReplyViewController.h"
#import "HPRearViewController.h"

#import "HPNewPost.h"
#import "HPDatabase.h"
#import "HPUser.h"
#import "HPThread.h"
#import "HPAccount.h"
#import "HPCache.h"
#import "HPFavorite.h"
#import "HPMessage.h"
#import "HPHttpClient.h"
#import "HPTheme.h"
#import "HPSetting.h"

#import "SDURLCache.h"


#import "IBActionSheet.h"
#import <SVProgressHUD.h>
#import "NSUserDefaults+Convenience.h"
#import "IDMPhotoBrowser.h"
#import "DZWebBrowser.h"
#import "NSString+Additions.h"
#import "NSString+HTML.h"

#import "UIViewController+KNSemiModal.h"
#import "UIAlertView+Blocks.h"
#import <ALActionBlocks/ALActionBlocks.h>
#import "UIBarButtonItem+ImageItem.h"
#import "UIView+AnchorPoint.h"

#import "EGORefreshTableFooterView.h"


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


@interface HPReadViewController () <UIWebViewDelegate, IBActionSheetDelegate, IDMPhotoBrowserDelegate, UIScrollViewDelegate, HPCompositionDoneDelegate>
@property (nonatomic, strong) NSArray *posts;

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

@end

@implementation HPReadViewController {
@private
    UIRefreshControl *_refreshControl;
    
    // for action
    HPNewPost *_current_action_post;
    NSInteger _current_author_uid;
    UISlider *_pageSlider;
    UILabel *_pageLabel;
    
    UIButton *_favButton;
    UIButton *_pageInfoButton;
    
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
        
        
        _current_page = page;
        _forceFullPage = forceFullPage;
        _find_pid = find_pid;
    }
    return self;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
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
}


- (void)loadView {
    CGRect screenFrame = [[UIScreen mainScreen] applicationFrame];
    UIWebView *wv = [[UIWebView alloc] initWithFrame:screenFrame];
    [wv setScalesPageToFit:YES];
    wv.dataDetectorTypes = UIDataDetectorTypeNone;
    wv.delegate = self;
    wv.backgroundColor = [HPTheme backgroundColor];
   
    for(UIView *view in [[[wv subviews] objectAtIndex:0] subviews]) {
        if([view isKindOfClass:[UIImageView class]]) {
            view.hidden = YES; }
    }
    [wv setOpaque:NO];
    
    // scrollView
    wv.scrollView.delegate = self;
    [wv.scrollView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:(__bridge void *)(self)];
    
    [self setView:wv];
}


- (UIWebView *)webView {
    return (UIWebView *)[self view];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)dealloc
{
    // deal with web view special needs
    NSLog(@"UIWebViewVC dealloc");
    [(UIWebView*)self.view stopLoading];
    [(UIWebView*)self.view setDelegate:nil];
   
    [self.webView.scrollView removeObserver:self forKeyPath:@"contentOffset" context:(__bridge void *)self];
}

#pragma mark - prepare view

- (void)setActionButton {
    
    [self updateFavButton];
    UIBarButtonItem* favBI = [[UIBarButtonItem alloc] initWithCustomView:_favButton];
    
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
    
    self.navigationItem.rightBarButtonItems = @[negativeSeperator, moreBI, pageBI, commentBI, favBI];
}

- (void)updateFavButton {
    
    if (!_favButton) {
        _favButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _favButton.bounds = CGRectMake(0, 0, 40.f, 40.f);
        [_favButton addTarget:self action:@selector(favorite:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    UIImage *favImg = [HPFavorite isFavoriteWithTid:_thread.tid] ?
        [UIImage imageNamed:@"love_selected.png"] : [UIImage imageNamed:@"love.png"];
    
    [_favButton setImage:favImg forState:UIControlStateNormal];
}

- (void)updatePageButton {
    if (!_pageInfoButton) {
        _pageInfoButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _pageInfoButton.bounds = CGRectMake(0, 0, 30.f, 30.f);
        [_pageInfoButton addTarget:self action:@selector(showPageView:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    NSString *attrTitle =
        _thread.pageCount != 0 ?
            [NSString stringWithFormat:@"%ld/%ld", _current_page, _thread.pageCount] :
            [NSString stringWithFormat:@"%ld/?", _current_page];
    
    if (_current_page == NSIntegerMax) attrTitle = @"?/?";
    
    
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

- (void)addGuesture {
    UISwipeGestureRecognizer *rightSwipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(back:)];
    rightSwipeGesture.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:rightSwipeGesture];
    
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
    
    /*
    NSURL *laoFontURL = [[NSBundle mainBundle] URLForResource:@"FZLanTingHei-R-GBK" withExtension:@"TTF"];
    NSArray *fontPostScriptNames = [UIFont registerFontFromURL:laoFontURL];
    NSLog(@"%@", fontPostScriptNames);
    */
     
    // clear
    [self.webView stringByEvaluatingJavaScriptFromString:@"document.open();document.close();"];
    
    NSMutableString *string = nil;
    if (![Setting boolForKey:HPSettingNightMode]) {
        string = [[NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"post_view" ofType:@"html"] encoding:NSUTF8StringEncoding error:nil] mutableCopy];
    } else {
        string = [[NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"post_view_dark" ofType:@"html"] encoding:NSUTF8StringEncoding error:nil] mutableCopy];
    }
    
    if (_thread.title)
        [string replaceOccurrencesOfString:@"##title##" withString:_thread.title options:0 range:NSMakeRange(0, string.length)];
    
    NSString *targetFontSize = [NSString stringWithFormat:@"%i.000001%%",_currentFontSize];
    [string replaceOccurrencesOfString:@"**[txtadjust]**" withString:targetFontSize options:0 range:NSMakeRange(0, string.length)];
    
    [string replaceOccurrencesOfString:@"**[lineHeight]**" withString:S(@"%i%%", _currentLineHeight) options:0 range:NSMakeRange(0, string.length)];
    
    [self.webView loadHTMLString:string baseURL:[NSURL URLWithString:@"http://www.hi-pda.com/forum/"]];
    
    BOOL printable = !_forceFullPage && (_current_page == 1 && _current_author_uid == 0);
    
    [HPNewPost loadThreadWithTid:_thread.tid
                            page:_current_page
                    forceRefresh:refresh
                       printable:printable
                        authorid:_current_author_uid
                 redirectFromPid:_find_pid ? _find_pid:0
                           block:
     ^(NSArray *posts, NSDictionary *parameters, NSError *error) {
         
        if (!error) {
            
            // save posts
            _posts = posts;
            
            // save parameters
            [self refreshThreadInfo:parameters
                           find_pid:_find_pid];
            
            // update title
            [string replaceOccurrencesOfString:@"##title##" withString:_thread.title options:0 range:NSMakeRange(0, string.length)];
            
            //
            __block NSMutableString *lists = [NSMutableString stringWithCapacity:42];
            [posts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                
                HPNewPost *post = (HPNewPost *)obj;
                
                NSString *list = nil;
                if ([Setting boolForKey:HPSettingShowAvatar]) {
                    list = [NSString stringWithFormat:@"<li class=\"\" data-id=\"floor://%ld\" ><a name=\"floor_%ld\"></a><div class=\"info\"><span class=\"avatar\"><img data-id='user://%@' src=\"%@\" onerror=\"this.onerror=null;this.src=''\" ></span><span class=\"author\">%@</span><span class=\"floor\">%ld#</span><span class=\"time-ago\">%@</span></div><div class=\"content\">%@</div></li>", post.floor, post.floor,  post.user.username, [post.user.avatarImageURL absoluteString], post.user.username, post.floor, [HPNewPost dateString:post.date], post.body_html];
                    
                } else {
                    
                    list = [NSString stringWithFormat:@"<li class=\"\" data-id=\"floor://%ld\" ><a name=\"floor_%ld\"></a><div class=\"info\"><span class=\"author\" style=\"left: 0;\">%@</span><span class=\"floor\">%ld#</span><span class=\"time-ago\">%@</span></div><div class=\"content\">%@</div></li>", post.floor, post.floor, post.user.username, post.floor, [HPNewPost dateString:post.date], post.body_html];
                }
                
                [lists appendString:list];
            }];
            
            
            [string replaceOccurrencesOfString:@"<span style=\"display:none\">##lists##</span>" withString:lists options:0 range:NSMakeRange(0, string.length)];
            
            
            NSString *final = [HPNewPost preProcessHTML:string];
            
            //NSLog(@"%@", string);
            [self.webView loadHTMLString:final baseURL:[NSURL URLWithString:@"http://www.hi-pda.com/forum/"]];
            
            [self endLoad:YES];
            
        } else {
            
            [self endLoad:NO];
            
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
    
    NSInteger page = [[parameters objectForKey:@"current_page"] integerValue];
    
    
    if (!_thread) {
        _thread = [[HPThread alloc]init];
    }
    
    if (formhash) _thread.formhash = formhash;
    if (title) _thread.title = title;
    if (fid) _thread.fid = fid;
    
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
    
    [self performSelector:@selector(indicatorStop) withObject:nil afterDelay:1.f];
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
            _refreshHeaderView = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.webView.scrollView.bounds.size.height, 320.0f, self.webView.scrollView.bounds.size.height)];
            _refreshHeaderView.backgroundColor = [UIColor clearColor];
        }
        
        [_refreshControl removeFromSuperview];
        [self.webView.scrollView addSubview:_refreshHeaderView];
    }
}

- (void)updateFooterView {
    
    if (!_refreshFooterView) {
        _refreshFooterView = [[EGORefreshTableFooterView alloc] initWithFrame:CGRectMake(0.0f, [self contentSize], 320.0f, 600.0f)];
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


#pragma mark - webView delegte

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    
    NSString *urlString = [[request URL] absoluteString];
    NSLog(@"%@ %ld %@",urlString, navigationType, request.URL.scheme);
    
    
    if ([request.URL.scheme isEqualToString:@"floor"]) {
        // 在帖子中 打开小尾巴, 特别是iOS客户端的小尾巴, 不知为何会触发floor
        // 暂时在未加载好是禁用
        if (_reloadingFooter) return NO;
        
        [self actionForFloor:[[urlString substringFromIndex:8] integerValue]];
        return NO;
        
    } else if ([request.URL.scheme isEqualToString:@"image"]) {
        
        NSString *src = [request.URL.absoluteString stringByReplacingOccurrencesOfString:@"image://http//" withString:@"http://"];
        [self openImage:src];
        NSLog(@"here");
        return NO;
        
    } else if ([request.URL.scheme isEqualToString:@"user"]) {
        
        // todo
        //[SVProgressHUD showErrorWithStatus:urlString];
        
        return NO;
        
    } else if ([request.URL.scheme isEqualToString:@"gotofloor"]) {
        
        [self gotoFloorWithUrl:urlString];
        return NO;
        
    } else if ([request.URL.scheme isEqualToString:@"video"]) {
        
        //NSLog(@"%@ %@", urlString, request.URL);
        NSString *url = [urlString stringByReplacingOccurrencesOfString:@"video://" withString:@"http://"];
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
        return NO;
        
    } else if (navigationType == UIWebViewNavigationTypeLinkClicked) {
        
        RxMatch* match = [urlString firstMatchWithDetails:RX(@"hi-pda\\.com/forum/viewthread\\.php\\?tid=(\\d+)")];
        
        if (match) {
            
            RxMatchGroup *m1 = [match.groups objectAtIndex:1];
            
            HPThread *t = [HPThread new];
            t.tid = [m1.value integerValue];
            HPReadViewController *readVC = [[HPReadViewController alloc] initWithThread:t];
            NSLog(@"[self.navigationController pushViewController:readVC animated:YES];");
            [self.navigationController pushViewController:readVC animated:YES];
            
        } else {
            NSLog(@"here w");
            [self openUrl:request.URL];
        }
        
        return NO;
        
    } else if ([urlString isEqualToString:@"http://www.hi-pda.com/forum/"]){
        
        return YES;
        
    } else if ([urlString hasPrefix:@"http://www.hi-pda.com/forum/#floor_"]){
    
        return YES;
        
    } else {
        
        [SVProgressHUD showErrorWithStatus:urlString];
        return YES;
    }
    
    return YES;
}

- (void)webViewDidStartLoad:(UIWebView *)webView {
    
}
- (void)webViewDidFinishLoad:(UIWebView *)webView {
   
   NSLog(@"webViewDidFinishLoad isisLoading %@", self.webView.isLoading?@"YES":@"NO");
    
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    
}

- (void)webViewDidAppear {
    
    NSLog(@"webViewDidAppear");

}

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
    
    NSInteger floor = [_posts[0] floor] + _posts.count - 1;

    NSString *js = [NSString stringWithFormat:@"location.href='#floor_%ld'",floor];
    [self.webView stringByEvaluatingJavaScriptFromString:js];
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
    
    IBActionSheet *actionSheet = [[IBActionSheet alloc]
                                  initWithTitle:nil
                                  delegate:self cancelButtonTitle:@"取消"
                                  destructiveButtonTitle:
                                  _current_page == 1 ? @"举报" : @"刷新"
                                  otherButtonTitles:
                                  _current_author_uid != 0 ? @"查看全部" : @"只看楼主",
                                  @"浏览器打开",
                                  @"复制链接", @"细节调整",nil];
   
    [actionSheet setButtonBackgroundColor:rgb(25.f, 25.f, 25.f)];
    [actionSheet setButtonTextColor:rgb(216.f, 216.f, 216.f)];
    [actionSheet setFont:[UIFont fontWithName:@"STHeitiSC-Light" size:20.f]];
    actionSheet.tag = 1;
    [actionSheet showInView:self.navigationController.view];
}

- (void)actionForFloor:(NSInteger)floor {
    
    if (_posts.count < 1) {
        NSLog(@"not ready");
        return;
    }
    
    NSInteger s = [_posts[0] floor];
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
                                  destructiveButtonTitle:@"举报"
                                  otherButtonTitles:
                                  @"回复",
                                  @"引用",
                                  @"发送短消息",
                                  _current_author_uid != 0 ? @"查看全部" : @"只看该作者", nil];
   
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
                    if (_current_page == 1) {
                       [self report];
                    } else {
                        [self reload:nil];
                    }
                    break;
                }
                case 1://只看该作者
                {
                    [self toggleOnlySomeone:_thread.user];
                    break;
                }
                case 2://浏览器打开
                {
                    NSString *url = [NSString stringWithFormat:@"http://www.hi-pda.com/forum/viewthread.php?tid=%ld&extra=&page=%ld", _thread.tid, _current_page];
                    [self openUrl:[NSURL URLWithString:url]];
                    break;
                }
                case 3://copy link
                {
                    NSString *url = [NSString stringWithFormat:@"http://www.hi-pda.com/forum/viewthread.php?tid=%ld&extra=&page=%ld", _thread.tid, _current_page];
                    UIPasteboard *pasteBoard = [UIPasteboard generalPasteboard];
                    [pasteBoard setString:url];
                    [SVProgressHUD showSuccessWithStatus:@"拷贝成功"];
                    break;
                }
                case 4://text adjust
                {
                    [self showAdjustView:nil];
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
                    [self report];
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
                case 3://发送短消息
                    [self promptForSendMessage:_current_action_post];
                    break;
                case 4://只看该作者
                    [self toggleOnlySomeone:_current_action_post.user];
                    break;
                default:
                    NSLog(@"error buttonIndex index, %ld", buttonIndex);
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

- (void)openUrl:(NSURL *)url {
    
    // todo
    // setting safari
    
    DZWebBrowser *webBrowser = [[DZWebBrowser alloc] initWebBrowserWithURL:url];
    webBrowser.showProgress = YES;
    webBrowser.allowSharing = YES;
    
    NSLog(@"open browser");
    UINavigationController *webBrowserNC = [[UINavigationController alloc] initWithRootViewController:webBrowser];
    [self presentViewController:webBrowserNC animated:YES completion:NULL];
}

- (void)openImage:(NSString *)src {
    NSLog(@"openImage %@", src);
    
    __block NSArray *images = nil;
    __block NSUInteger index = 0;
    [_posts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        HPNewPost *post = (HPNewPost *)obj;
        if (post.images && (index = [post.images indexOfObject:src]) != NSNotFound) {
            images = post.images;
            *stop = YES;
        }
        
    }];
    
    if (!images) {
        images = @[src];
        index = 0;
    }
    
    
    IDMPhotoBrowser *browser = [[IDMPhotoBrowser alloc] initWithPhotoURLs:images];
    
    browser.displayActionButton = YES;
    browser.displayArrowButton = YES;
    browser.displayCounterLabel = YES;
    [browser setInitialPageIndex: index];
    
    browser.wantsFullScreenLayout = NO; // iOS 5 & 6 only: Decide if you want the photo browser full screen, i.e. whether the status bar is affected (defaults to YES)
    // Present
    [self presentViewController:browser animated:YES completion:nil];
    
}

- (void)back:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
    
    if (_current_page == 1) {
        [HPNewPost cancelRequstOperationWithTid:_thread.tid];
    }
}


- (void)reply:(id)sender {
    
    HPReplyTopicViewController *sendvc = [[HPReplyTopicViewController alloc] initWithThread:_thread delegate:self];
    
    [self presentViewController:[HPCommon NVCWithRootVC:sendvc] animated:YES completion:nil];
}

- (void)replySomeone:(id)sender {
    
    HPReplyViewController *sendvc =
    [[HPReplyViewController alloc] initWithPost:_current_action_post
                                     actionType:ActionTypeReply
                                         thread:_thread
                                           page:_current_page
                                       delegate:self];
    
    [self presentViewController:[HPCommon NVCWithRootVC:sendvc] animated:YES completion:nil];
}

- (void)quoteSomeone:(id)sender {
    
    HPReplyViewController *sendvc =
    [[HPReplyViewController alloc] initWithPost:_current_action_post
                                     actionType:ActionTypeQuote
                                         thread:_thread
                                           page:_current_page
                                       delegate:self];
    
    [self presentViewController:[HPCommon NVCWithRootVC:sendvc] animated:YES completion:nil];
}

- (void)favorite:(id)sender {
    
    BOOL flag = [HPFavorite isFavoriteWithTid:_thread.tid];
    
    if (!flag) {
        [SVProgressHUD showWithStatus:@"收藏中..."];
        
        [[HPFavorite sharedFavorite] favoriteWith:_thread block:^(BOOL isSuccess, NSError *error) {
            if (isSuccess) {
                NSLog(@"favorate success");
                [SVProgressHUD showSuccessWithStatus:@"收藏成功"];
                [self updateFavButton];
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
                [self updateFavButton];
            } else {
                NSLog(@"un favorate error %@", [error localizedDescription]);
                [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
            }
        }];
    }
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
        [self load:YES];
    }
}




- (void)jumpToFloor:(NSInteger)floor {
    
    if (!floor) floor = _gotoFloor;
   
   
    
    NSString *js = [NSString stringWithFormat:@"location.href='#floor_%ld'",floor];
    [self.webView stringByEvaluatingJavaScriptFromString:js];
    
    _gotoFloor = 0;
}

- (void)gotoFloorWithUrl:(NSString *)url {
    NSArray *arr = [[url substringFromIndex:12] componentsSeparatedByString:@"_"];
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
        HPReadViewController *rvc = [[HPReadViewController alloc]   initWithThread:_thread
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
}

- (void)topPage {
    [self jumpToPage:1];
}

- (void)tailPage {
    [self jumpToPage:_thread.pageCount];
}



- (void)sendMessageTo:(NSString *)username
              message:(NSString *)message {
    
    if (!message || [message isEqualToString:@""]) {
        [SVProgressHUD showErrorWithStatus:@"消息内容不能为空"];
        return;
    }
    
    [SVProgressHUD showWithStatus:@"发送中..."];
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
}

# pragma mark - pageView

- (UIView *)pageView {
    
    if (!_pageView) {
        
        _pageView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, self.view.bounds.size.width, 82.0f)];
        
        if (![Setting boolForKey:HPSettingNightMode]) {
            _pageView.backgroundColor = [UIColor whiteColor];
        } else {
            _pageView.backgroundColor = [HPTheme backgroundColor];
        }
       
        _pageSlider = [[UISlider alloc] initWithFrame:CGRectMake(10.0f,5.0f,260.0f,30.0f)];
        _pageSlider.continuous = YES ;
        [_pageSlider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
        _pageSlider.userInteractionEnabled = YES;
        _pageSlider.maximumValue = 100.0f;
        _pageSlider.minimumValue = 0.0f;
        _pageSlider.value = 1.0f;
        
        UIButton *goButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        goButton.frame = CGRectMake(270, 0, 50, 40.f);
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
        
        CGFloat height = 150.f;
        
        _adjustView = [[UIView alloc] initWithFrame:CGRectMake(0.f, self.view.bounds.size.height - height, self.view.bounds.size.width, height)];
    
        _adjustView.alpha = 0.f;
        [self.webView addSubview:[self adjustView]];
        
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
		nightSwitch.tag = 10242014;
        nightSwitch.on = [Setting boolForKey:HPSettingNightMode];
        
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

        
    } else if (actualStepper.tag == lineHeightStepperTag) {
        
        _currentLineHeight = (int)actualStepper.value;
        [Setting saveInteger:_currentLineHeight forKey:HPSettingLineHeightAdjust];
        
        _lineHeightLabel.text = S(@"%ld%%", _currentLineHeight);
        [_lineHeightLabel sizeToFit];
        
        [self changeLineHeight];
        
    } else {
        ;
    }
}

- (void)switchAction:(id)sender
{
	NSLog(@"switchAction: value = %d", [sender isOn]);
    
    [Setting saveBool:[sender isOn] forKey:HPSettingNightMode];
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
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%i%%'",
                          _currentFontSize];
    [self.webView stringByEvaluatingJavaScriptFromString:jsString];
}

- (void)changeLineHeight
{
    NSString *jsString = [[NSString alloc] initWithFormat:@"addNewStyle('body {line-height:%i%% !Important;}')",
                          _currentLineHeight];
    
    [self.webView stringByEvaluatingJavaScriptFromString:jsString];
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
}
- (void)dragToNextPage {
    
    [self nextPage:nil];
    [self transition:StoryTransitionTypeNext];
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
	
	if (scrollView.isDragging && !_lastPage) {
        
        
		if (_refreshHeaderView.state == EGOOPullRefreshPulling && scrollView.contentOffset.y > -65.0f && scrollView.contentOffset.y < 0.0f && !_reloadingHeader) {
			[_refreshHeaderView setState:EGOOPullRefreshNormal];
		} else if (_refreshHeaderView.state == EGOOPullRefreshNormal && scrollView.contentOffset.y < -65.0f && !_reloadingHeader) {
			[_refreshHeaderView setState:EGOOPullRefreshPulling];
		}
        
        float endOfTable = [self endOfTableView:scrollView];
        if (_refreshFooterView.state == EGOOPullRefreshPulling && endOfTable < 0.0f && endOfTable > -65.0f && !_reloadingFooter) {
			[_refreshFooterView setState:EGOOPullRefreshNormal];
		} else if (_refreshFooterView.state == EGOOPullRefreshNormal && endOfTable < -65.0f && !_reloadingFooter) {
			[_refreshFooterView setState:EGOOPullRefreshPulling];
		}
	}
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate{
	
    
	if (scrollView.contentOffset.y <= - 65.0f && !_reloadingHeader) {
        _reloadingHeader = YES;
        [self dragToPreviousPage];
	}
    
    
    if ([self endOfTableView:scrollView] <= -65.0f && !_reloadingFooter) {
        
        if (!_lastPage) {
            _reloadingFooter = YES;
            _refreshFooterView.hidden = YES;
            [self dragToNextPage];
        }
	}
}

- (CGFloat)contentSize {
	
    // return height of table view
    return [self.webView.scrollView contentSize].height;
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
    
    _reloadingForReply = YES;
    _current_page = _thread.pageCount;
    [self reload:nil];
}

#pragma mark - theme
- (void)themeDidChanged {
   
    [[HPRearViewController sharedRearVC] themeDidChanged];
    //http://stackoverflow.com/questions/21652957/uinavigationbar-appearance-refresh
    self.navigationController.navigationBar.barStyle = [UINavigationBar appearance].barStyle;
    self.view.backgroundColor = [HPTheme backgroundColor];
    [self reload:nil];
    
}


@end
