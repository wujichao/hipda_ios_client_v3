//
//  HPBaseCompostionViewController.m
//  HiPDA
//
//  Created by wujichao on 14-3-5.
//  Copyright (c) 2014年 wujichao. All rights reserved.
//

#import "HPBaseCompostionViewController.h"
#import "SWRevealViewController.h"

#import "WUDemoKeyboardBuilder.h"

#import "UIButton+Additions.h"
#import "UIImageView+Additions.h"
#import "HPTheme.h"
#import "HPSetting.h"

#import "UIAlertView+Blocks.h"
#import "HPImagePickerViewController.h"

#define TOOLBAR_HEIGHT 40.f

@interface HPBaseCompostionViewController () <UITextViewDelegate, HPImagePickerUploadDelegate>



@end

@implementation HPBaseCompostionViewController {
    
    UIView *toolbar;
    UIButton *photoBnt;
    UIButton *emotionBnt;
    UIButton *mentionBnt;
    UIButton *sendBnt;
    UIButton *recoverBnt; NSString *lastContent;
    UIActivityIndicatorView *tokenIndicator;
    UILabel *tokenLabel;
    
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    _contentTextFiled = [[UITextView alloc] initWithFrame:self.view.bounds];
    _contentTextFiled.font = [UIFont systemFontOfSize:16.0f];
    _contentTextFiled.delegate = self;
    _contentTextFiled.text = @"content here...";
    _contentTextFiled.keyboardAppearance = [HPTheme keyboardAppearance];

    
    UIColor *backgroudColor = [HPTheme backgroundColor];
    if (![Setting boolForKey:HPSettingNightMode]) {
        _contentTextFiled.textColor = [UIColor blackColor];
        
    } else {
        _contentTextFiled.textColor = [UIColor colorWithRed:109.f/255.f green:109.f/255.f blue:109.f/255.f alpha:1.f];
    }
  
    _contentTextFiled.backgroundColor = backgroudColor;
    [self.view addSubview:_contentTextFiled];
    
    [self.view setBackgroundColor:[HPTheme backgroundColor]];
    
    toolbar = [[UIView alloc] init];
    toolbar.backgroundColor = backgroudColor;
    toolbar.userInteractionEnabled = YES;
    [self.view addSubview:toolbar];
    

    UIView *separator = [UIView new];
    separator.frame = CGRectMake(10, 0, HP_SCREEN_WIDTH-20, 1);
    separator.backgroundColor = [UIColor colorWithRed:206.f/255.f green:206.f/255.f blue:206.f/255.f alpha:1.f];
    [toolbar addSubview:separator];
    
    
    photoBnt = [[UIButton alloc] init];
    [toolbar addSubview:photoBnt];
    [photoBnt addTarget:self action:@selector(photoButtonTouched) forControlEvents:UIControlEventTouchUpInside];
    [photoBnt setImage:[UIImage imageNamed:@"compose_camera"] forState:UIControlStateNormal];
    photoBnt.showsTouchWhenHighlighted = YES;
    [photoBnt sizeToFit];
    photoBnt.center = CGPointMake(25, 20);
    photoBnt.hitTestEdgeInsets = UIEdgeInsetsMake(0, -5, 0, -5);
    
    emotionBnt = [[UIButton alloc] init];
    [toolbar addSubview:emotionBnt];
    [emotionBnt setTapTarget:self action:@selector(emotionButtonTouched)];
    [emotionBnt setImage:[UIImage imageNamed:@"compose_emotion"] forState:UIControlStateNormal];
    
    emotionBnt.showsTouchWhenHighlighted = YES;
    [emotionBnt sizeToFit];
    emotionBnt.center = CGPointMake(75, 20);
    emotionBnt.hitTestEdgeInsets = UIEdgeInsetsMake(0, -5, 0, -5);
    
    mentionBnt = [[UIButton alloc] init];
    //[toolbar addSubview:mentionBnt];
    [mentionBnt setTapTarget:self action:@selector(mentionButtonTouched)];
    [mentionBnt setImage:[UIImage imageNamed:@"compose_at"] forState:UIControlStateNormal];
    mentionBnt.showsTouchWhenHighlighted = YES;
    [mentionBnt sizeToFit];
    mentionBnt.center = CGPointMake(125, 20);
    mentionBnt.hitTestEdgeInsets = UIEdgeInsetsMake(0, -5, 0, -5);
    
    
    recoverBnt = [UIButton buttonWithType:UIButtonTypeRoundedRect];

    [toolbar addSubview:recoverBnt];
    [recoverBnt setTapTarget:self action:@selector(recoverButtonTouched)];
    [recoverBnt setTitle:@"R" forState:UIControlStateNormal];
    [recoverBnt setTitleColor:rgb(111.f,111.f,111.f) forState:UIControlStateNormal];
    recoverBnt.titleLabel.font = [UIFont systemFontOfSize:18.f];
    [recoverBnt sizeToFit];
    recoverBnt.center = CGPointMake(HP_SCREEN_WIDTH-20, 20);
    lastContent = [NSStandardUserDefaults objectForKey:HPDraft];
    if (!lastContent || [lastContent isEqualToString:@""]) {
        [recoverBnt removeFromSuperview];
    }
    
    sendBnt = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    
    [toolbar addSubview:sendBnt];
    [sendBnt setTapTarget:self action:@selector(send:)];
    [sendBnt setTitle:@"发送" forState:UIControlStateNormal];
    [sendBnt setTitleColor:rgb(111.f,111.f,111.f) forState:UIControlStateNormal];
    sendBnt.titleLabel.font = [UIFont systemFontOfSize:17.f];
    [sendBnt sizeToFit];
    sendBnt.center = CGPointMake(HP_SCREEN_WIDTH-HP_CONVERT_WIDTH(70), 20);
    
    /*
    tokenLabel = [UILabel new];
    tokenLabel.text = @"正在获取Token...";
    tokenLabel.textColor = [UIColor colorWithRed:97.f/255.f green:103.f/255.f blue:108.f/255.f alpha:1.f];
    [tokenLabel sizeToFit];
    CGRect frame = tokenLabel.frame;
    frame.origin.y = 10.f;
    frame.origin.x = self.view.frame.size.width - frame.size.width - 5.f;
    tokenLabel.frame = frame;
    [toolbar addSubview:tokenLabel];

    tokenIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    frame = tokenIndicator.frame;
    frame.origin.y = 10.f;
    frame.origin.x = tokenLabel.frame.origin.x - 25.f;
    tokenIndicator.frame = frame;
    [toolbar addSubview:tokenIndicator];
    tokenIndicator.hidesWhenStopped = NO;
    */
     
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWasShown:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    
    /*
    if ([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    */
    
    _indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    //_indicator.hidesWhenStopped = NO;
    
    UIBarButtonItem *indicatorBtn = [[UIBarButtonItem alloc] initWithCustomView:_indicator];
    
    UIBarButtonItem *sendBtn = [[UIBarButtonItem alloc]
                                initWithTitle:@"发送"
                                style:UIBarButtonItemStylePlain target:self action:@selector(send:)];
    
    UIBarButtonItem *cancelBtn = [[UIBarButtonItem alloc]
                                  initWithTitle:@"取消"
                                  style:UIBarButtonItemStylePlain target:self action:@selector(cancelCompose:)];
    
    [[self navigationItem] setRightBarButtonItems:@[sendBtn,indicatorBtn]];
    self.navigationItem.leftBarButtonItem = cancelBtn;
}


-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _contentTextFiled.delegate = nil;
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - actions

- (void)send:(id)sender {
    
    NSLog(@"send: need implement");
    NSParameterAssert(0);
}

- (void)doneWithError:(NSError *)error {
    
    [self close:nil];
    NSLog(@"doneWithError %@", [error localizedDescription]);
    [self.delegate compositionDoneWithType:_actionType error:error];
}

- (void)addImage:(id)sender {
    [HPImagePickerViewController authorizationPresentAlbumViewController:self delegate:self qcloud:NO];
}

- (void)close {
    [self close:nil];
}

- (void)close:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancelCompose:(id)sender {
    
    if (_contentTextFiled.text.length > 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"放弃编辑?"
                                                        message:@"放弃后，下次您可以点击键盘顶部工具栏右边的 R按钮来恢复上次输入的内容"
                                                       delegate:nil
                                              cancelButtonTitle:@"放弃"
                                              otherButtonTitles:@"继续编辑", nil];
        
        [alert showWithHandler:^(UIAlertView *alertView, NSInteger buttonIndex) {
            if (alertView.cancelButtonIndex == buttonIndex) {
                // todo draft
                [self dismissViewControllerAnimated:YES completion:nil];
            }
        }];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}


#pragma mark - imageUploadDelegate

- (void)completeWithAttachString:(NSString *)string error:(NSError *)error {
    
    NSString *text = _contentTextFiled.text;
    _contentTextFiled.text = [NSString stringWithFormat:@"%@\n[attachimg]%@[/attachimg]\n", text, string];
    
    // add to images array
    if (!_imagesString) {
        _imagesString = [NSMutableArray arrayWithCapacity:3];
    }
    [_imagesString addObject:string];
    
    NSLog(@"completeWithAttachString %@", string);
}


#pragma mark - UITextViewDelegate

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    NSLog(@"textViewDidBeginEditing");
    if ([_contentTextFiled.text isEqualToString:@"content here..."]) {
        //以下两行代码用来绕过iOS15上粘贴时的闪退问题
        textView.text = @" ";
        textView.text = @"";
        
        // dark
        //textView.textColor = [UIColor blackColor];
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    //NSLog(@"%@", _contentTextFiled.text);
    [NSStandardUserDefaults saveObject:_contentTextFiled.text forKey:HPDraft];
}

#pragma mark - keyborad

// keyborad height
- (void)keyboardWasShown:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // Get the size of the keyboard.
        CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
        
        //NSLog(@"height %f", keyboardSize.height);
        
        //CGFloat toolbar_height = 40;
        //toolbar.frame = CGRectMake(0, contentTV.bottom, self.view.width, toolbar_height);
        
        
        [UIView animateWithDuration:0.2f animations:^{
            
            
            
            float height = [self.view bounds].size.height - _contentTextFiled.frame.origin.y - keyboardSize.height - TOOLBAR_HEIGHT;
            _contentTextFiled.frame =
            CGRectMake(_contentTextFiled.frame.origin.x,
                       _contentTextFiled.frame.origin.y,
                       _contentTextFiled.frame.size.width,
                       height);
            
            toolbar.frame = CGRectMake(0, _contentTextFiled.frame.origin.y + _contentTextFiled.frame.size.height, self.view.frame.size.width, TOOLBAR_HEIGHT);
        }];
    });
}


- (void)photoButtonTouched {
    [self addImage:nil];
}

- (void)emotionButtonTouched {
    
    if (!self.contentTextFiled.emoticonsKeyboard) {
        [emotionBnt setImage:[UIImage imageNamed:@"compose_emotion_on"] forState:UIControlStateNormal];
    } else {
        [emotionBnt setImage:[UIImage imageNamed:@"compose_emotion"] forState:UIControlStateNormal];
    }
    
    if (self.contentTextFiled.isFirstResponder) {
        if (self.contentTextFiled.emoticonsKeyboard) [self.contentTextFiled switchToDefaultKeyboard];
        else [self.contentTextFiled switchToEmoticonsKeyboard:[WUDemoKeyboardBuilder sharedEmoticonsKeyboard]];
    } else {
        [self.contentTextFiled switchToEmoticonsKeyboard:[WUDemoKeyboardBuilder sharedEmoticonsKeyboard]];
        [self.contentTextFiled becomeFirstResponder];
    }
}

- (void)mentionButtonTouched {
    ;
}

- (void)recoverButtonTouched {
    //NSString *last = [NSStandardUserDefaults objectForKey:HPDraft];
    [UIAlertView showConfirmationDialogWithTitle:@"确认恢复为"
                                         message:S(@"%@", lastContent)
                                         handler:^(UIAlertView *alertView, NSInteger buttonIndex)
    {
        if (buttonIndex == [alertView cancelButtonIndex]) {
            ;
        } else {
            _contentTextFiled.text = lastContent;
        }
    }];
}

@end
