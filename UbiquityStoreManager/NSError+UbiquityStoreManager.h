/**
 * Copyright Maarten Billemont (http://www.lhunath.com, lhunath@lyndir.com)
 *
 * See the enclosed file LICENSE for license information (LASGPLv3).
 *
 * @author   Maarten Billemont <lhunath@lyndir.com>
 * @license  Lesser-AppStore General Public License
 */


#import <Foundation/Foundation.h>


extern NSString *const UbiquityManagedStoreDidDetectCorruptionNotification;
extern NSString *const USMStoreURLsErrorKey;

@interface NSError(UbiquityStoreManager)

- (id)init_USM_WithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)dict;

@end
