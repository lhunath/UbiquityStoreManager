//
//  DetailViewController.h
//  UbiquityStoreManagerExample
//
//  Created by Aleksey Novicov on 3/27/12.
//  Copyright (c) 2012 Yodel Code LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DetailViewController : UITableViewController<UISplitViewControllerDelegate>

@property(strong, nonatomic) IBOutlet UILabel *detailDescriptionLabel;
@property(strong, nonatomic) NSArray *fileList;

@property(strong, nonatomic) id detailItem;

@end
