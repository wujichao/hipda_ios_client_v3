//
//  HPNavigationController.m
//  HiPDA
//
//  Created by Jichao Wu on 15/5/6.
//  Copyright (c) 2015年 wujichao. All rights reserved.
//

#import "HPNavigationController.h"
#import "HPSetting.h"
#import "UIAlertView+Blocks.h"
#import "SSWDirectionalPanGestureRecognizer.h"

@interface HPNavigationController ()<UIGestureRecognizerDelegate>

@end

@implementation HPNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self fuckPopGestureRecognizer];
    
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barApp = [[UINavigationBarAppearance alloc] init];
        barApp.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
        self.navigationBar.scrollEdgeAppearance = barApp;
    }
}

//https://github.com/zys456465111/CustomPopAnimation/
//http://www.jianshu.com/p/d39f7d22db6c
- (void)fuckPopGestureRecognizer
{
    UIGestureRecognizer *gesture = self.interactivePopGestureRecognizer;
    gesture.enabled = NO;
    UIView *gestureView = gesture.view;
    SSWDirectionalPanGestureRecognizer *popRecognizer = [[SSWDirectionalPanGestureRecognizer alloc] init];
    popRecognizer.delegate = self;
    popRecognizer.direction = SSWPanDirectionRight;
    popRecognizer.maximumNumberOfTouches = 1;
    [gestureView addGestureRecognizer:popRecognizer];

    /**
     * 获取系统手势的target数组
     */
    NSMutableArray *_targets = [gesture valueForKey:@"_targets"];
    /**
     * 获取它的唯一对象，我们知道它是一个叫UIGestureRecognizerTarget的私有类，它有一个属性叫_target
     */
    id gestureRecognizerTarget = [_targets firstObject];
    /**
     * 获取_target:_UINavigationInteractiveTransition，它有一个方法叫handleNavigationTransition:
     */
    id navigationInteractiveTransition = [gestureRecognizerTarget valueForKey:@"_target"];
    /**
     * 通过前面的打印，我们从控制台获取出来它的方法签名。
     */
    SEL handleTransition = NSSelectorFromString(@"handleNavigationTransition:");
    /**
     * 创建一个与系统一模一样的手势，我们只把它的类改为UIPanGestureRecognizer
     */
    [popRecognizer addTarget:navigationInteractiveTransition action:handleTransition];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    /**
     * 这里有两个条件不允许手势执行，1、当前控制器为根控制器；2、如果这个push、pop动画正在执行（私有属性）
     */
    return self.viewControllers.count != 1 && ![[self valueForKey:@"_isTransitioning"] boolValue];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
