//
//  MasterViewController.h
//  UbiquityStoreManagerExample
//
//  Created by Aleksey Novicov on 3/27/12.
//  Copyright (c) 2012 Yodel Code LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DetailViewController;

#import <CoreData/CoreData.h>

@interface MasterViewController : UITableViewController<NSFetchedResultsControllerDelegate>

@property(strong, nonatomic) DetailViewController *detailViewController;

@property(strong, nonatomic) NSFetchedResultsController *fetchedResultsController;
@property(strong, nonatomic) IBOutlet UISwitch *iCloudSwitch;
@property(strong, nonatomic) IBOutlet UIView *tableHeaderView;
@property(strong, nonatomic) IBOutlet UIButton *clearButton;
@property(strong, nonatomic) IBOutlet UIActivityIndicatorView *storeLoadingActivity;

- (IBAction)setiCloudState:(id)sender;
- (IBAction)cleariCloud:(id)sender;
- (IBAction)rebuildiCloud:(id)sender;

@end
