//
//  User.h
//  UbiquityStoreManagerExample
//
//  Created by Aleksey Novicov on 3/27/12.
//  Copyright (c) 2012 Yodel Code LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface User : NSManagedObject

@property (nonatomic) NSTimeInterval timestamp;
@property (nonatomic) BOOL primary;
@property (nonatomic, strong) NSSet *events;

+ (User *)primaryUserInContext:(NSManagedObjectContext *)context;
+ (User *)insertUserInManagedObjectContext:(NSManagedObjectContext *)context primary:(BOOL)primary;
- (User *)userInContext:(NSManagedObjectContext *)context;

@end

@interface User (CoreDataGeneratedAccessors)

- (void)addEventsObject:(NSManagedObject *)value;
- (void)removeEventsObject:(NSManagedObject *)value;
- (void)addEvents:(NSSet *)values;
- (void)removeEvents:(NSSet *)values;

@end
