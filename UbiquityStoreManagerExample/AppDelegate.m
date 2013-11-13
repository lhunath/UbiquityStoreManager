//
//  AppDelegate.m
//  UbiquityStoreManagerExample
//
//  Created by Aleksey Novicov on 3/27/12.
//  Copyright (c) 2012 Yodel Code LLC. All rights reserved.
//

#import <CoreGraphics/CoreGraphics.h>
#import "AppDelegate.h"
#import "MasterViewController.h"
#import "DetailViewController.h"
#import "User.h"

@implementation AppDelegate {
    UIAlertView *cloudContentCorruptedAlert;
    UIAlertView *cloudContentHealingAlert;
    UIAlertView *handleCloudContentWarningAlert;
    UIAlertView *handleLocalStoreAlert;
    MasterViewController *masterViewController;
}

+ (AppDelegate *)sharedAppDelegate {

    return (AppDelegate *)[[UIApplication sharedApplication] delegate];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    NSLog( @"Starting UbiquityStoreManagerExample on device: %@\n\n", [UIDevice currentDevice].name );

    // STEP 1 - Initialize the UbiquityStoreManager
    _ubiquityStoreManager = [[UbiquityStoreManager alloc] initStoreNamed:nil withManagedObjectModel:nil
                                                           localStoreURL:nil containerIdentifier:nil additionalStoreOptions:nil
                                                                delegate:self];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];

    // Override point for customization after application launch.
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        masterViewController = [[MasterViewController alloc] initWithNibName:@"MasterViewController_iPhone" bundle:nil];
        self.navigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
        self.window.rootViewController = self.navigationController;
    }
    else {
        masterViewController = [[MasterViewController alloc] initWithNibName:@"MasterViewController_iPad" bundle:nil];
        UINavigationController
                *masterNavigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];

        DetailViewController *detailViewController = [[DetailViewController alloc] initWithNibName:@"DetailViewController_iPad" bundle:nil];
        UINavigationController
                *detailNavigationController = [[UINavigationController alloc] initWithRootViewController:detailViewController];

        masterViewController.detailViewController = detailViewController;

        self.splitViewController = [UISplitViewController new];
        self.splitViewController.delegate = detailViewController;
        self.splitViewController.viewControllers = @[ masterNavigationController, detailNavigationController ];
        self.window.rootViewController = self.splitViewController;
    }

    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {

    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    [managedObjectContext performBlockAndWait:^{
        NSError *error = nil;
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error])
            NSLog( @"Unresolved error: %@\n%@", error, [error userInfo] );
    }];
}

#pragma mark - Entities

- (User *)primaryUser {

    User *primaryUser = [User primaryUserInContext:self.managedObjectContext];
    if (!primaryUser) {
        // Create the primary user
        primaryUser = [User insertUserInManagedObjectContext:self.managedObjectContext primary:YES];
    }

    return primaryUser;
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {

    if (alertView == cloudContentHealingAlert) {
        if (buttonIndex == [alertView firstOtherButtonIndex]) {
            // Disable
            self.ubiquityStoreManager.cloudEnabled = NO;
        }
    }

    if (alertView == cloudContentCorruptedAlert) {
        if (buttonIndex == [alertView firstOtherButtonIndex]) {
            // Disable
            self.ubiquityStoreManager.cloudEnabled = NO;
        }
        else if (buttonIndex == [alertView firstOtherButtonIndex] + 1) {
            // Fix Now
            handleCloudContentWarningAlert = [[UIAlertView alloc] initWithTitle:@"Fix iCloud Now" message:
                    @"This problem can usually be auto‑corrected by opening the app on another device where you recently made changes.\n"
                            @"If you wish to correct the problem from this device anyway, it is possible that recent changes on another device will be lost."
                                                                       delegate:self
                                                              cancelButtonTitle:@"Back"
                                                              otherButtonTitles:@"Fix Anyway", nil];
            [handleCloudContentWarningAlert show];
        }
    }

    if (alertView == handleCloudContentWarningAlert) {
        if (buttonIndex == alertView.cancelButtonIndex) {
            // Back
            [cloudContentCorruptedAlert show];
        }
        else if (buttonIndex == alertView.firstOtherButtonIndex) {
            // Fix Anyway
            [self.ubiquityStoreManager rebuildCloudContentFromCloudStoreOrLocalStore:YES];
        }
    }

    if (alertView == handleLocalStoreAlert) {
        if (buttonIndex == [alertView firstOtherButtonIndex]) {
            // Recreate
            [self.ubiquityStoreManager deleteLocalStore];
        }
    }
}


#pragma mark - UbiquityStoreManagerDelegate

// STEP 2 - Implement the UbiquityStoreManager delegate methods
- (NSManagedObjectContext *)managedObjectContextForUbiquityChangesInManager:(UbiquityStoreManager *)manager {

    return self.managedObjectContext;
}

- (void)ubiquityStoreManager:(UbiquityStoreManager *)manager willLoadStoreIsCloud:(BOOL)isCloudStore {

    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    [managedObjectContext performBlockAndWait:^{
        NSError *error = nil;
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error])
            NSLog( @"Unresolved error: %@\n%@", error, [error userInfo] );

        [managedObjectContext reset];
    }];

    _managedObjectContext = nil;
}

- (void)ubiquityStoreManager:(UbiquityStoreManager *)manager didLoadStoreForCoordinator:(NSPersistentStoreCoordinator *)coordinator
                     isCloud:(BOOL)isCloudStore {

    NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    moc.persistentStoreCoordinator = coordinator;
    moc.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    _managedObjectContext = moc;

    dispatch_async( dispatch_get_main_queue(), ^{
        [cloudContentCorruptedAlert dismissWithClickedButtonIndex:[cloudContentCorruptedAlert cancelButtonIndex] animated:YES];
        [handleCloudContentWarningAlert dismissWithClickedButtonIndex:[handleCloudContentWarningAlert cancelButtonIndex] animated:YES];
    } );
}

- (void)ubiquityStoreManager:(UbiquityStoreManager *)manager failedLoadingStoreWithCause:(UbiquityStoreErrorCause)cause context:(id)context
                    wasCloud:(BOOL)wasCloudStore {

    dispatch_async( dispatch_get_main_queue(), ^{
        [masterViewController.iCloudSwitch setEnabled:YES];
        [masterViewController.iCloudSwitch setOn:wasCloudStore animated:YES];
        [masterViewController.storeLoadingActivity stopAnimating];

        if (!wasCloudStore && ![handleLocalStoreAlert isVisible]) {
            handleLocalStoreAlert = [[UIAlertView alloc] initWithTitle:@"Local Store Problem"
                                                               message:@"Your datastore got corrupted and needs to be recreated."
                                                              delegate:self
                                                     cancelButtonTitle:nil otherButtonTitles:@"Recreate", nil];
            [handleLocalStoreAlert show];
        }
    } );
}

- (BOOL)ubiquityStoreManager:(UbiquityStoreManager *)manager handleCloudContentCorruptionWithHealthyStore:(BOOL)storeHealthy {

    if (storeHealthy) {
        dispatch_async( dispatch_get_main_queue(), ^{
            if ([cloudContentHealingAlert isVisible])
                return;

            cloudContentHealingAlert = [[UIAlertView alloc]
                    initWithTitle:@"iCloud Store Corruption"
                          message:@"\n\n\n\nRebuilding cloud store to resolve corruption."
                         delegate:self cancelButtonTitle:nil otherButtonTitles:@"Disable iCloud", nil];

            UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            activityIndicator.center = CGPointMake( 142, 90 );
            [activityIndicator startAnimating];
            [cloudContentHealingAlert addSubview:activityIndicator];
            [cloudContentHealingAlert show];
        } );

        return YES;
    }
    else {
        dispatch_async( dispatch_get_main_queue(), ^{
            if ([cloudContentHealingAlert isVisible] || [handleCloudContentWarningAlert isVisible])
                return;

            cloudContentCorruptedAlert = [[UIAlertView alloc]
                    initWithTitle:@"iCloud Store Corruption"
                          message:@"\n\n\n\nWaiting for another device to auto-correct the problem..."
                         delegate:self cancelButtonTitle:nil otherButtonTitles:@"Disable iCloud", @"Fix Now", nil];

            UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            activityIndicator.center = CGPointMake( 142, 90 );
            [activityIndicator startAnimating];
            [cloudContentCorruptedAlert addSubview:activityIndicator];
            [cloudContentCorruptedAlert show];
        } );

        return NO;
    }
}

@end
