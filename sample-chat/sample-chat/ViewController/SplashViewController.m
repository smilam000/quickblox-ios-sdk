//
//  SplashViewController.m
//  sample-chat
//
//  Created by Igor Khomenko on 10/16/13.
//  Copyright (c) 2013 Igor Khomenko. All rights reserved.
//

#import "SplashViewController.h"

#define demoUserLogin @"igorquickblox"
#define demoUserPassword @"igorquickblox"

#import <Quickblox/QBASession.h>
#import "QBServiceManager.h"

@interface SplashViewController ()

@end

@implementation SplashViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    QBUUser* user = [QBUUser new];
    user.login = demoUserLogin;
    user.password = demoUserPassword;
    
    __weak __typeof(self)weakSelf = self;

    [[QBServiceManager instance].authService logInWithUser:user completion:^(QBResponse *response, QBUUser *userProfile) {
        __typeof(self) strongSelf = weakSelf;
        if (userProfile != nil) {
            [[LocalStorageService shared] setCurrentUser:userProfile];
            [[QBServiceManager instance].chatService logIn:^(NSError *error) {
                // hide alert after delay
                double delayInSeconds = 1.0;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    [strongSelf dismissViewControllerAnimated:YES completion:nil];
                });
            }];
        }
    }];
}

@end
