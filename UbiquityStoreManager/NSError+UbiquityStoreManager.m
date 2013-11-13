/**
 * Copyright Maarten Billemont (http://www.lhunath.com, lhunath@lyndir.com)
 *
 * See the enclosed file LICENSE for license information (LASGPLv3).
 *
 * @author   Maarten Billemont <lhunath@lyndir.com>
 * @license  Lesser-AppStore General Public License
 */


#import <CoreData/CoreData.h>
#import "NSError+UbiquityStoreManager.h"

NSString *const UbiquityManagedStoreDidDetectCorruptionNotification = @"UbiquityManagedStoreDidDetectCorruptionNotification";
NSString *const USMStoreURLsErrorKey = @"USMStoreURLsErrorKey";

@implementation NSError(UbiquityStoreManager)

- (id)init_USM_WithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)dict {

    self = [self init_USM_WithDomain:domain code:code userInfo:dict];
    if ([domain isEqualToString:NSCocoaErrorDomain] && code == 134302) {
        if (![self handleError:self]) {
            NSLog( @"===" );
            NSLog( @"Detected unknown ubiquity import error." );
            NSLog( @"Please report this at http://lhunath.github.io/UbiquityStoreManager" );
            NSLog( @"and provide details of the conditions and whether or not you notice" );
            NSLog( @"any sync issues afterwards.  Error userInfo:" );
            for (id key in dict) {
                id value = dict[key];
                NSLog( @"[%@] %@ => [%@] %@", [key class], key, [value class], value );
            }
            NSLog( @"Error Debug Description:\n%@", [self debugDescription] );
            NSLog( @"===" );
        }
    }

    return self;
}

- (BOOL)handleError:(NSError *)error {

    if (!error)
        return NO;
    
    if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSValidationMissingMandatoryPropertyError) {
        // Severity: Critical To Cloud Content
        // Cause: Validation Error -- non-optional property with a nil value.  The other end of a required relationship is missing from the store.
        // Action: Mark corrupt, request rebuild.
        NSManagedObject *object = [error userInfo][NSValidationObjectErrorKey];
        NSPersistentStoreCoordinator *psc = object.managedObjectContext.persistentStoreCoordinator;
        NSMutableArray *storeURLs = [NSMutableArray arrayWithCapacity:[psc.persistentStores count]];
        for (NSPersistentStore *store in psc.persistentStores)
            [storeURLs addObject:[psc URLForPersistentStore:store]];
        [[NSNotificationCenter defaultCenter] postNotificationName:UbiquityManagedStoreDidDetectCorruptionNotification object:@{
                NSUnderlyingErrorKey : self,
                USMStoreURLsErrorKey : storeURLs,
        }];
        return YES;
    }
    if ([(NSString *)(error.userInfo)[@"reason"] hasPrefix:@"Error reading the log file at location: (null)"]) {
        // Severity: Delayed Import?
        // Cause: Log file failed to download?
        // Action: Ignore.
        return YES;
    }

    if ([self handleError:(error.userInfo)[NSUnderlyingErrorKey]])
        return YES;
    if ([self handleError:(error.userInfo)[@"underlyingError"]])
        return YES;

    NSArray *errors = (error.userInfo)[@"NSDetailedErrors"];
    for (NSError *error_ in errors)
        if ([self handleError:error_])
            return YES;

    return NO;
}

@end
