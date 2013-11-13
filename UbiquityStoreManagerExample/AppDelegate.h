//
//  AppDelegate.h
//  UbiquityStoreManagerExample
//
//  Created by Aleksey Novicov on 3/27/12.
//  Copyright (c) 2012 Yodel Code LLC. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "UbiquityStoreManager.h"

@class User;

@interface AppDelegate : UIResponder<UIApplicationDelegate, UIAlertViewDelegate, UbiquityStoreManagerDelegate>

@property(strong, nonatomic) UIWindow *window;
@property(strong, nonatomic) UINavigationController *navigationController;
@property(strong, nonatomic) UISplitViewController *splitViewController;
@property(strong, nonatomic) UbiquityStoreManager *ubiquityStoreManager;

@property(readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;

+ (AppDelegate *)sharedAppDelegate;
- (User *)primaryUser;

@end
