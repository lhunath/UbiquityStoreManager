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
        if (![self _USM_handleError:self]) {
            NSLog( @"===" );
            NSLog( @"Detected unknown ubiquity import error." );
            NSLog( @"Please report this at http://lhunath.github.io/UbiquityStoreManager" );
            NSLog( @"and provide details of the conditions and whether or not you notice" );
            NSLog( @"any sync issues afterwards.  Error:\n%@", [self _USM_fullDescription] );
            NSLog( @"===" );
        }
    }

    return self;
}

- (BOOL)_USM_handleError:(NSError *)error {

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
    if ([(NSString *)error.userInfo[@"reason"] hasPrefix:@"Error reading the log file at location: (null)"]) {
        // Severity: Delayed Import?
        // Cause: Log file failed to download?
        // Action: Ignore.
        return YES;
    }

    if ([self _USM_handleException:error.userInfo[@"NSUnderlyingException"]])
        return YES;
    if ([self _USM_handleError:error.userInfo[NSUnderlyingErrorKey]])
        return YES;
    if ([self _USM_handleError:error.userInfo[@"underlyingError"]])
        return YES;

    NSArray *errors = error.userInfo[@"NSDetailedErrors"];
    for (NSError *error_ in errors)
        if ([self _USM_handleError:error_])
            return YES;

    return NO;
}

- (BOOL)_USM_handleException:(NSException *)exception {

    if (!exception)
        return NO;

    if (exception.userInfo[NSSQLiteErrorDomain]) {
        // Severity: Critical To Cloud Content
        // Cause: An internal SQLite inconsistency
        // Action: Mark corrupt, request rebuild.
        NSMutableArray *storeURLs = [NSMutableArray arrayWithObject:[NSURL URLWithString:[exception userInfo][@"NSFilePath"]?:@"nil://"]?:
                                                                    [NSURL URLWithString:@"badurl://"]];
        [[NSNotificationCenter defaultCenter] postNotificationName:UbiquityManagedStoreDidDetectCorruptionNotification object:@{
                NSUnderlyingErrorKey : self,
                USMStoreURLsErrorKey : storeURLs,
        }];
        return YES;
    }

    return NO;
}

- (NSString *)_USM_fullDescription {

    NSMutableString *fullDescription = [NSMutableString new];
    [fullDescription appendFormat:@"Error: %lu (%@): %@\n", (long)self.code, self.domain, self.localizedDescription];
    if (self.localizedRecoveryOptions)
        [fullDescription appendFormat:@" - RecoveryOptions: %@\n", self.localizedRecoveryOptions];
    if (self.localizedRecoverySuggestion)
        [fullDescription appendFormat:@" - RecoverySuggestion: %@\n", self.localizedRecoverySuggestion];
    if (self.localizedFailureReason)
        [fullDescription appendFormat:@" - FailureReason: %@\n", self.localizedFailureReason];
    if (self.helpAnchor)
        [fullDescription appendFormat:@" - HelpAnchor: %@\n", self.helpAnchor];
    if (self.userInfo) {
        for (id key in self.userInfo) {
            id info = self.userInfo[key];
            NSMutableString *infoString;
            if ([info respondsToSelector:@selector(_USM_fullDescription)])
                infoString = [[info _USM_fullDescription] mutableCopy];
            else if ([info isKindOfClass:[NSException class]])
                infoString = [NSMutableString stringWithFormat:@"%@: %@ %@", [info name], [info reason], [info userInfo]];
            else if ([info respondsToSelector:@selector(debugDescription)])
                infoString = [[info debugDescription] mutableCopy];
            else
                infoString = [[info description] mutableCopy];

            NSString *keyString = [NSString stringWithFormat:@" - Info %@: [%@] ", key, [info class]];
            NSString *indentedNewline = [@"\n" stringByPaddingToLength:[keyString length] + 1
                                                            withString:@" " startingAtIndex:0];
            [infoString replaceOccurrencesOfString:@"\n" withString:indentedNewline options:0
                                             range:NSMakeRange( 0, [infoString length] )];
            [fullDescription appendString:keyString];
            [fullDescription appendString:infoString];
            [fullDescription appendString:@"\n"];
        }
    }

    return fullDescription;
}

@end
