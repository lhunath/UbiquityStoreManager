//
//  Event.h
//  UbiquityStoreManagerExample
//
//  Created by Aleksey Novicov on 3/27/12.
//  Copyright (c) 2012 Yodel Code LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class User;

@interface Event : NSManagedObject

@property(nonatomic, strong) NSString *creater;
@property(nonatomic, strong) NSDate *timeStamp;
@property(nonatomic, strong) User *user;

@end
