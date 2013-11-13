//
//  User.m
//  UbiquityStoreManagerExample
//
//  Created by Aleksey Novicov on 3/27/12.
//  Copyright (c) 2012 Yodel Code LLC. All rights reserved.
//

#import "User.h"

@implementation User

@dynamic timestamp;
@dynamic primary;
@dynamic events;

+ (User *)primaryUserInContext:(NSManagedObjectContext *)context {

    NSError *error = nil;
    NSFetchRequest *fetchRequest = [context.persistentStoreCoordinator.managedObjectModel fetchRequestTemplateForName:@"primaryUser"];
    NSArray *results = [context executeFetchRequest:fetchRequest error:&error];
    if (!results)
        NSLog( @"Error while trying to get primary user: %@\n%@", error, [error userInfo] );

    return [results firstObject];
}

+ (User *)insertUserInManagedObjectContext:(NSManagedObjectContext *)context primary:(BOOL)primary {

    NSError *error = nil;
    User *newUser = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass( [User class] ) inManagedObjectContext:context];
    newUser.primary = primary;
    if (![context save:&error])
        NSLog( @"Error while saving insert of new user: %@\n%@", error, [error userInfo] );

    return newUser;
}

- (User *)userInContext:(NSManagedObjectContext *)context {

    if (context == self.managedObjectContext)
        return self;

    return (User *)[context objectWithID:[self objectID]];
}

@end
