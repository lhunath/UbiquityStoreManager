/**
 * Copyright 2012, Maarten Billemont (http://www.lhunath.com, lhunath@lyndir.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * @author   Maarten Billemont <lhunath@lyndir.com>
 * @license  Apache License, Version 2.0
 */


//
//  UbiquityStoreManager.h
//  UbiquityStoreManager
//
// UbiquityStoreManager is a controller for your Core Data persistence layer.
// It provides you with an NSPersistentStoreCoordinator and handles the stores for you.
// It encapsulates everything required to make Core Data integration with iCloud work as reliably as possible.
//
// Aside from this, it features the following functionality:
//
//  - Ability to switch between a separate cloud-synced and local store (an iCloud toggle).
//  - Automatically migrates local data to iCloud when the user has no iCloud store yet.
//  - Handles all iCloud related events such as:
//      - Account changes
//      - External deletion of the cloud data
//      - External deletion of the local store
//      - Importing of ubiquitous changes from other devices
//      - Recovering from exceptional events such as corrupted transaction logs
//  - Some maintenance functionality:
//      - Ability to rebuild the cloud store from transaction logs
//      - Ability to rebuild the transaction logs from the cloud store
//      - Ability to delete the cloud store (allowing it to be recreated from the local store)
//      - Ability to nuke the entire cloud container
//      - Migrate one store to another by copying all entities
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

/**
 * The store managed by the ubiquity manager's coordinator is about to change (eg. migrating or switching between iCloud and local).
 *
 * This notification is posted after the -ubiquityStoreManager:willLoadStoreIsCloud: message was posted to the delegate but before the PSC
 * is invalidated.  You should clean up your UI and disconnect your MOC so that your app can function with no persistence until
 * USMStoreDidChangeNotification is triggered.
 *
 * NOTE: This notification is posted from the persistence queue.  If you need to do UI work, you'll need to dispatch it to the main queue.
 */
extern NSString *const USMStoreWillChangeNotification;
/**
 * The store managed by the ubiquity manager's coordinator changed (eg. switching (no store) or switched to iCloud or local).
 *
 * This notification is posted after the -ubiquityStoreManager:didLoadStoreForCoordinator:isCloud: message was posted to the delegate and
 * the PSC has been reloaded.  Your app should refresh and re-validate its UI since persistence is now available again and the store might
 * have changed significantly (eg. a new iCloud user might have become active).
 *
 * NOTE: This notification is posted from the persistence queue.  If you need to do UI work, you'll need to dispatch it to the main queue.
 */
extern NSString *const USMStoreDidChangeNotification;
/**
 * The store managed by the ubiquity manager's coordinator imported changes from iCloud (eg. another device saved changes to iCloud).
 */
extern NSString *const USMStoreDidImportChangesNotification;
/**
 * The boolean value in the NSUserDefaults at this key specifies whether iCloud is enabled on this device.
 */
extern NSString *const USMCloudEnabledKey;
/**
 * The number in the cloud enumeration options dictionary that indicates the cloud version to use for loading the store.
 */
extern NSString *const USMCloudVersionKey;
/**
 * The boolean value in the cloud enumeration options dictionary specifies whether it is the currently active store in USM.
 */
extern NSString *const USMCloudCurrentKey;

typedef enum {
    UbiquityStoreErrorCauseNoError = noErr, // Nothing went wrong.  There is no context.
    UbiquityStoreErrorCauseDeleteStore, // Error occurred while deleting the store file or its transaction logs.  context = the path of the store.
    UbiquityStoreErrorCauseCreateStorePath, // Error occurred while creating the path where the store needs to be saved.  context = the path of the store.
    UbiquityStoreErrorCauseClearStore, // Error occurred while removing a store from the coordinator.  context = the store.
    UbiquityStoreErrorCauseOpenActiveStore, // Error occurred while opening the active store.  context = the path that couldn't be opened.
    UbiquityStoreErrorCauseOpenSeedStore, // Error occurred while opening the seed store.  context = the path of the store.
    UbiquityStoreErrorCauseSeedStore, // Error occurred while seeding the store.  context = the path of the seed store.
    UbiquityStoreErrorCauseImportChanges, // Error occurred while importing changes from the cloud into the application's context.  context = the DidImportUbiquitousContentChanges notification.
    UbiquityStoreErrorCauseConfirmActiveStore, // Error occurred while confirming a new active store.  context = The url that couldn't be created or updated to confirm the store.
    UbiquityStoreErrorCauseCorruptActiveStore, // Error occurred while handling store corruption.  context = The path that couldn't be read, created or updated.
    UbiquityStoreErrorCauseEnumerateStores, // Error occurred while attempting to enumerate the known cloud stores.  context = The path that couldn't be enumerated.
} UbiquityStoreErrorCause;
extern NSString *NSStringFromUSMCause(UbiquityStoreErrorCause cause);

typedef enum {
    UbiquityStoreMigrationStrategyCopyEntities = 1, // Migrate by copying all entities from the active store to the new store.
    UbiquityStoreMigrationStrategyIOS, // Migrate using iOS' migration routines (bugged for: cloud -> local on iOS 6.0, local -> cloud on iOS 6.1).
    UbiquityStoreMigrationStrategyManual, // Migrate using the delegate's -ubiquityStoreManager:manuallyMigrateStore:toStore:.
    UbiquityStoreMigrationStrategyNone, // Don't migrate, just create an empty destination store.
} UbiquityStoreMigrationStrategy;

@class UbiquityStoreManager;

@protocol UbiquityStoreManagerDelegate<NSObject>

/** When cloud changes are detected, the manager can merge these changes into your managed object context.
 *
 * If you don't implement this method or return nil, the manager will commit the changes to the store
 * (using NSMergeByPropertyObjectTrumpMergePolicy) but your application's context may not become aware of them.
 *
 * If you do implement this method, the changes will be merged into your managed object context
 * and the context will be saved afterwards.
 *
 * The standard implementation for this method is to just return your application's managed object context.
 *
 * Regardless of whether this method is implemented or not, a USMStoreDidImportChangesNotification will be
 * posted after the changes are successfully imported into the store.
 *
 * @param note The NSPersistentStoreDidImportUbiquitousContentChangesNotification that contains the changes
 *             that will be imported into the managed object context you return.
 */
@optional
- (NSManagedObjectContext *)ubiquityStoreManager:(UbiquityStoreManager *)manager
          managedObjectContextForUbiquityChanges:(NSNotification *)note;

/** Use -ubiquityStoreManager:managedObjectContextForUbiquityChanges: instead,
 *  this method is no longer called and will be removed. */
- (NSManagedObjectContext *)managedObjectContextForUbiquityChangesInManager:(UbiquityStoreManager *)manager
__attribute__((deprecated));

/** Triggered when the store manager begins loading a persistence store.
 *
 * After this and before -ubiquityStoreManager:didLoadStoreForCoordinator:isCloud:, the application should not be using the persistence
 * coordinator.  It is therefore a good idea to unset your managed contexts here.
 *
 * This method is useful for indicating in your user interface that the store is loading.
 * You should unset your managed object contexts here to prevent exceptions/hangs in your applications while the store changes.
 * Do this in a -performBlockAndWait: block, so that the execution of -ubiquityStoreManager:didLoadStoreForCoordinator:isCloud: is blocked
 * until your managed context's pending blocks have been processed and it is properly saved.  For example:
 *
 *     [self.moc performBlockAndWait:^{
 *         [self.moc save:nil];
 *         self.moc = nil;
 *     }];
 *
 * NOTE: This method will be invoked from the persistence queue.  What you do here will block the persistence loading progress.
 *       If you have migration work to do, do it here.
 *
 * The USMStoreWillChangeNotification notification is posted right after this method returns.
 * You can use it as an alternative to this method for resetting your UI.
 *
 * @param isCloudStore YES if the cloud store will be loaded.
 *                     NO if the local store will be loaded.
 */
@optional
- (void)ubiquityStoreManager:(UbiquityStoreManager *)manager willLoadStoreIsCloud:(BOOL)isCloudStore;

/** Triggered when the store manager loads a persistence store.
 *
 * The manager is done handling the attempt to load the store.  This is where you'll init/update your application's persistence layer.
 *
 * You should probably create your main managed object context here.
 *
 * NOTE: This method is invoked from the persistence queue.  If you need to do UI work, you'll need to dispatch it to the main queue.
 *
 * NOTE: The coordinator could change again during the application's lifetime (you'll get a new -ubiquityStoreManager:didLoadStoreForCoordinator:isCloud: if this happens).
 *
 * The USMStoreDidChangeNotification notification is posted right after this method returns.
 * You can use it as an alternative to this method for reloading your UI, however this method is the only way to get the PSC.
 *
 * @param isCloudStore YES if the cloud store was just loaded.
 *                     NO if the local store was just loaded.
 */
@required
- (void)ubiquityStoreManager:(UbiquityStoreManager *)manager didLoadStoreForCoordinator:(NSPersistentStoreCoordinator *)coordinator
                     isCloud:(BOOL)isCloudStore;

/** Triggered when the store manager fails to loads a persistence store.
 *
 * If wasCloudStore is YES, -ubiquityStoreManager:handleCloudContentCorruptionIsCloud: will also be called.  You should handle the
 * failure there, or here if you don't plan to.
 * If wasCloudStore is NO, the local store may be irreparably broken.  You should probably -deleteLocalStore to fix the persistence layer.
 *
 * This method will be invoked from the main queue.
 *
 * @param wasCloudStore YES if the error was caused while attempting to load the cloud store.
 *                      NO if the error was caused while attempting to load the local store.
 */
@optional
- (void)ubiquityStoreManager:(UbiquityStoreManager *)manager failedLoadingStoreWithCause:(UbiquityStoreErrorCause)cause
                     context:(id)context wasCloud:(BOOL)wasCloudStore;

/** Triggered when the store manager has detected that the cloud content has failed to import on one of the devices.
 *
 * TL;DR: The recommended way to implement this method is to return NO (so the default solution will be effected).
 * If storeHealthy is YES, you can show the user that iCloud is being fixed.
 * If storeHealthy is NO, you should tell the user this device is waiting and he should open the app on his other device(s) so they can
 * attempt to fix the situation.
 *
 * Why did this happen?
 *
 * When cloud content (transaction logs) fail to import into the cloud store on this device, the result is that the cloud store is no
 * longer guaranteed to be the same as the cloud store on other devices.  Moreover, there is no more guarantee that changes made to the
 * cloud store will sync to other devices.  iCloud sync for the cloud store is therefore effectively broken.
 *
 * When this happens, there is only one recovery: The cloud store must be recreated from scratch.
 *
 * Unfortunately, this situation tends to occur very easily because of an Apple bug with regards to synchronizing Core Data relationships:
 * When two devices simultaneously modify a relationship, the resulting transaction logs can cause an irreparable conflict.
 *
 * You can implement this method to be notified of when this situation occurs.  If you plan to handle the problem yourself and deal with
 * the corruption, return YES to disable the manager's default strategy.
 * If you want the manager to effect its default solution, return NO (or don't implement this method).
 *
 * The default solution to this problem is to unload the cloud store on all devices where transaction logs can no longer be imported into
 * the store.  A device that has not noticed any import problems will be notified of cloud corruption in other devices and initiate a
 * rebuild of the cloud content.
 *
 * If you want to handle the corruption yourself, you have a few options.  Keep in mind: To fix the situation you will need to create
 * a new cloud store; only a new cloud store can guarantee that all devices are back in-sync.  Here's what you could do:
 * - Switch to the local store (manager.cloudEnabled = NO).
 *      NOTE: The cloud data and cloud syncing will be unavailable.
 * - Delete the cloud data and recreate it by seeding it with the local store ([manager deleteCloudStoreLocalOnly:NO]).
 *      NOTE: The existing cloud data will be lost.
 * - Make the existing cloud data local and disable iCloud ([manager migrateCloudToLocal]).
 *      NOTE: The existing local store will be lost.
 *      NOTE: The cloud data known by this device will become available again.
 *      NOTE: The cloud store is still in a corrupt state.  The user can either re-try later, or you can rebuild the cloud store from
  *           the local store ([manager deleteCloudStoreLocalOnly:NO]).
 * - Rebuild the cloud content by seeding it with the cloud store of this device ([manager rebuildCloudContentFromCloudStoreOrLocalStore:YES]).
 *      NOTE: iCloud functionality will be completely restored with the cloud data known by this device.
 *      NOTE: Any cloud changes on other devices that failed to sync to this device will be lost.
 *      NOTE: If you specify YES for allowRebuildFromLocalStore and the cloud store on this device is unusable for repairing the cloud
  *           content, a new cloud store will be created from the local store instead.
 *
 * Keep in mind that if storeHealthy is YES, the cloud store will, if enabled, still be loaded.  If storeHealthy is NO, the cloud store
 * will, if enabled, have been unloaded before this method is called and no store will be available at this point.
 *
 * This method will be invoked from the persistence queue.  What you do here will block the persistence loading progress.  The cloud store
 * will have been unloaded and there will be no store loaded when this method is called unless when the cloud store is not enabled
 * (in which case the local store may be loaded).
 *
 * @param storeHealthy YES if this device has no loading or syncing problems with the cloud store.
 *                     NO if this device can no longer open or sync with the cloud store.
 * @return YES if you've handled the corruption yourself and want to disable the manager's default strategy for resolving corruption.
 *         NO if you just use this method to inform the user or your application and want the manager to handle the problem for you.
 */
@optional
- (BOOL)ubiquityStoreManager:(UbiquityStoreManager *)manager handleCloudContentCorruptionWithHealthyStore:(BOOL)storeHealthy;

/** Triggered when the cloud content is deleted while cloud is enabled.
 *
 * When the cloud store is deleted, it may be that the user has deleted his cloud data for the app from one of his devices.
 * It is therefore not necessarily desirable to immediately re-create a cloud store.  By default, the manager will unload the cloud store
 * and fall back to the local store.
 *
 * It may be desirable to show UI to the user allowing him to choose between re-enabling iCloud ([manager deleteCloudStoreLocalOnly:NO])
 * or disabling it and switching back to local data (manager.cloudEnabled = NO).
 *
 * This method will be invoked from a private queue.
 */
@optional
- (void)ubiquityStoreManagerHandleCloudContentDeletion:(UbiquityStoreManager *)manager;

/** Triggered when the store manager encounters an error.  Mainly useful to handle error conditions/logging in whatever way you see fit.
 *
 * If you don't implement this method, the manager will instead detail the error in a few log statements.
 *
 * This method will be invoked from the thread that experienced the error.  Avoid doing thread-sensitive or long-running tasks.
 */
@optional
- (void)ubiquityStoreManager:(UbiquityStoreManager *)manager didEncounterError:(NSError *)error
                       cause:(UbiquityStoreErrorCause)cause context:(id)context;

/** Triggered whenever the store manager has information to share about its operation.  Mainly useful to plug in your own logger.
 *
 * If you don't implement this method, the manager will just log the message using NSLog.
 *
 * This method will be invoked from the thread that logged the message.  Avoid doing thread-sensitive or long-running tasks.
 */
@optional
- (void)ubiquityStoreManager:(UbiquityStoreManager *)manager log:(NSString *)message;

/** Triggered when the store manager is about to migrate entities from one store to another.
 *
 * The migration store will be unaffected by the process.  If the destination store exists already, migration won't happen regardless of
 * what you return here.  You can force the migration to happen by manually deleting the destination store.
 *
 * This method will be invoked from the persistence queue.  What you do here will block the persistence loading progress.  Any stores have
 * been unloaded and there will be no store loaded when this method is called.
 *
 * @param migrationStoreURL The URL to the store where entities will be copied from.
 * @param destinationStoreURL The URL to the store where entities will be copied to.
 * @param toCloud YES if the migrating entities will be copied into a new cloud store, NO if they will be copied into a new local store.
 * @return YES to confirm that the manager may proceed with the migration.
 *         NO to abort the migration and instead just load the destination store as-is.  If there is no destination store yet, this will
 *         cause an empty one to be created instead.
 */
@optional
- (BOOL)ubiquityStoreManager:(UbiquityStoreManager *)manager
   shouldMigrateFromStoreURL:(NSURL *)migrationStoreURL
                  toStoreURL:(NSURL *)destinationStoreURL
                     isCloud:(BOOL)isCloudStore;

/** Triggered when the store manager needs to perform a manual store migration.
 *
 * Implementing this method is required if you set -migrationStrategy to UbiquityStoreMigrationStrategyManual.
 *
 * This method will be invoked from the persistence queue.  What you do here will block the persistence loading progress.  Any stores have
 * been unloaded and there will be no store loaded when this method is called.
 *
 * @param error If the migration fails, write out an error object that describes the problem.
 * @return YES when the migration was successful and the new store may be loaded.
 *         NO to error out and not load the new store (new store will be cleaned up if it exists).
 */
@optional
- (BOOL)ubiquityStoreManager:(UbiquityStoreManager *)manager
        manuallyMigrateStore:(NSURL *)oldStoreURL withOptions:(NSDictionary *)oldStoreOptions
                     toStore:(NSURL *)newStoreURL withOptions:(NSDictionary *)newStoreOptions error:(NSError **)error;

@end

@interface UbiquityStoreManager : NSObject

#pragma mark - Setup

/**
 * The delegate provides the managed object context to use and is informed of events in the ubiquity manager.
 *
 * You probably won't need to touch this (it is set from init).
 */
@property(nonatomic, weak) id<UbiquityStoreManagerDelegate> delegate;

/**
 * The URL where the local store will be loaded from.
 *
 * You probably won't need to touch this (it is set from init).
 *
 * NOTE: Use this only from the persistence queue (ie. see UbiquityStoreManagerDelegate method documentation).
 *       You probably want -ubiquityStoreManager:willLoadStoreIsCloud:
 */
@property(nonatomic, copy) NSURL *localStoreURL;

/**
 * Determines what strategy to use when migrating from one store to another (eg. local -> cloud).
 *
 * The default is UbiquityStoreMigrationStrategyCopyEntities.
 *
 * NOTE: Use this only from the persistence queue (see UbiquityStoreManagerDelegate method documentation).
 *       You probably want -ubiquityStoreManager:willLoadStoreIsCloud:
 */
@property(nonatomic, assign) UbiquityStoreMigrationStrategy migrationStrategy;

/**
 * Indicates whether iCloud is available for the current user.
 *
 * If iCloud is not available, the user probably hasn't yet configured their Apple ID on their account.
 * 
 * This property is Key-Value Observing compatible: observing this key will give you updates on the current user's iCloud availability.
 */
@property(nonatomic, readonly) BOOL cloudAvailable;

/**
 * Indicates whether the iCloud store or the local store is in use.
 *
 * Changing this property will cause a reload of the active store.
 *
 * NOTE: You are recommended to only set this as a result of a user action or
 *       from -ubiquityStoreManager:willLoadStoreIsCloud:
 */
@property(nonatomic) BOOL cloudEnabled;

@property(nonatomic, copy) NSString *storeConfiguration;

/** Start managing an optionally ubiquitous store coordinator.  Assumes nil for all the parameters in the full -init that aren't present here.
 *  @param delegate The application controller that will be handling the application's persistence responsibilities.
 */
- (id)initWithDelegate:(id<UbiquityStoreManagerDelegate>)delegate;

/** Start managing an optionally ubiquitous store coordinator.
 *  @param contentName The name of the local and cloud stores that this manager will create.  If nil, "UbiquityStore" will be used.
 *  @param model The managed object model the store should use.  If nil, all the main bundle's models will be merged.
 *  @param localStoreURL The location where the non-ubiquitous (local) store should be kept. If nil, the local store will be put in the application support directory.
 *  @param containerIdentifier The identifier of the ubiquity container to use for the ubiquitous store. If nil, the entitlement's primary container identifier will be used.
 *  @param storeConfiguration The persistence model's configuration to load the store with.  If nil, the default configuration is used.
 *  @param storeOptions Additional persistence options that the stores should be initialized with.  If nil or empty, no options will be added to those necessary to load the store.
 *  @param delegate The application controller that will be handling the application's persistence responsibilities.
 */
- (id)initStoreNamed:(NSString *)contentName withManagedObjectModel:(NSManagedObjectModel *)model localStoreURL:(NSURL *)localStoreURL
 containerIdentifier:(NSString *)containerIdentifier storeConfiguration:(NSString *)storeConfiguration storeOptions:(NSDictionary *)storeOptions
            delegate:(id<UbiquityStoreManagerDelegate>)delegate;

#pragma mark - Maintenance

/**
 * Clear and re-open the store.
 *
 * This is rarely useful if you want to re-try opening the active store.  You usually won't need to invoke this manually.
 */
- (void)reloadStore;

/**
 * Switch to the cloud store if not enabled already.
 *
 * If a cloud store already exists, the confirmationBlock will be triggered.
 * If you confirm with YES, the existing cloud store will be deleted and a new one will be created by migrating the local store.
 * If you confirm with NO, the existing cloud store will be loaded.
 *
 * This is an ideal method to use if you want to give your users a chance to "keep their current data" by popping an alert.
 * Make sure they understand that doing so will cause any existing cloud data to be lost.
 *
 * NOTE: For your convenience, the confirmationBlock is executed ON THE MAIN THREAD.
 * Call the block you're given when you have determined the confirmation answer.  The store manager will be blocked until you make the call!
 *
 * NOTE: If switching or migration fails, USM will try to revert to the previously active store.
 *
 * @param confirmationBlock The block that will be triggered when an existing cloud store exists and confirmation is needed to either overwrite it with the local store or load it as-is.
 *
 * @return YES if the operation was invoked from the persistence queue and the store was successfully switched or migrated.
 *         NO if the operation was asynchronous or the migration failed.
 */
- (BOOL)setCloudEnabledAndOverwriteCloudWithLocalIfConfirmed:(void (^)(void (^setConfirmationAnswer)(BOOL answer)))confirmationBlock;

/**
 * Switch to the local store if not enabled already.
 *
 * If a local store already exists, the confirmationBlock will be triggered.
 * If you confirm with YES, the existing local store will be deleted and a new one will be created by migrating the cloud store.
 * If you confirm with NO, the existing local store will be loaded.
 *
 * This is an ideal method to use if you want to give your users a chance to "keep their current data" by popping an alert.
 * Make sure they understand that doing so will cause any existing local data to be lost.
 *
 * NOTE: For your convenience, the confirmationBlock is executed ON THE MAIN THREAD.
 * Call the block you're given when you have determined the confirmation answer.  The store manager will be blocked until you make the call!
 *
 * NOTE: If switching or migration fails, USM will try to revert to the previously active store.
 *
 * @param confirmationBlock The block that will be triggered when an existing local store exists and confirmation is needed to either overwrite it with the cloud store or load it as-is.
 *
 * @return YES if the operation was invoked from the persistence queue and the store was successfully switched or migrated.
 *         NO if the operation was asynchronous or the migration failed.
 */
- (BOOL)setCloudDisabledAndOverwriteLocalWithCloudIfConfirmed:(void (^)(void (^setConfirmationAnswer)(BOOL answer)))confirmationBlock;

/**
 * This will delete the local store and migrate the cloud store to a new local store.  The device will subsequently load the new local store (disable cloud).
 *
 * NOTE: If migration fails, USM will try to revert to the previously active store.
 *
 * @return YES if the operation was invoked from the persistence queue and the store was successfully migrated.
 *         NO if the operation was asynchronous or the migration failed.
 */
- (BOOL)migrateCloudToLocal;

/**
 * This will delete the cloud store and migrate the local store to a new cloud store.  The device will subsequently load the new cloud store (enable cloud).
 *
 * NOTE: If migration fails, USM will try to revert to the previously active store.
 *
 * @return YES if the operation was invoked from the persistence queue and the store was successfully migrated.
 *         NO if the operation was asynchronous or the migration failed.
 */
- (BOOL)migrateLocalToCloud;

/**
 * This will delete the cloud content and recreate a new cloud store by seeding it with the current cloud store.
 * Any cloud content and cloud store changes on other devices that are not present on this device's cloud store will be lost.
 *
 * NOTE: If migration fails, USM will try to revert to the previously active store.
 *
 * @param allowRebuildFromLocalStore If YES and the cloud content cannot be rebuilt from the cloud store, the local store will be used
 * instead.  Beware: All former cloud content will be lost.
 *
 * @return YES if the operation was invoked from the persistence queue and the store was successfully migrated.
 *         NO if the operation was asynchronous or the migration failed.
 */
- (BOOL)rebuildCloudContentFromCloudStoreOrLocalStore:(BOOL)allowRebuildFromLocalStore;

/**
 * This will delete all the data from iCloud for this application.
 *
 * @param localOnly If YES, the iCloud data will be re-downloaded when needed.
 *                  If NO, the container's data will be permanently lost.
 *
 * Unless you intend to delete more than just the active cloud store, you should probably use -deleteCloudStoreLocalOnly: instead.
 */
- (void)deleteCloudContainerLocalOnly:(BOOL)localOnly;

/**
 * This will delete the iCloud store.
 *
 * @param localOnly If YES, the iCloud transaction logs will be re-downloaded and the store rebuilt.
 *                  If NO, the store will be permanently lost and a new one will be created by migrating the device's local store.
 */
- (void)deleteCloudStoreLocalOnly:(BOOL)localOnly;

/**
 * This will delete the local store.
 */
- (void)deleteLocalStore;

#pragma mark - Information

/**
 * Determine whether it's safe to seed the cloud store with a local store.
 */
- (BOOL)cloudSafeForSeeding;

/**
 * @return URL to the active app's ubiquity container.
 */
- (NSURL *)URLForCloudContainer;

/**
 * @return URL to the directory where we put cloud store databases for this app.
 */
- (NSURL *)URLForCloudStoreDirectory;

/**
 * NOTE: Use this only from the persistence queue (see UbiquityStoreManagerDelegate method documentation).
 *       You probably want -ubiquityStoreManager:willLoadStoreIsCloud:
 *
 * @return URL to the active cloud store's database.
 */
- (NSURL *)URLForCloudStore;

/**
 * NOTE: Use this only from the persistence queue (see UbiquityStoreManagerDelegate method documentation).
 *       You probably want -ubiquityStoreManager:willLoadStoreIsCloud:
 *
 * @return Value to use for NSPersistentStoreUbiquitousContentURLKey for the active cloud store's transaction logs.
 */
- (id)URLForCloudContent;

/**
 * @return URL to the directory where we put the local store database for this app.
 */
- (NSURL *)URLForLocalStoreDirectory;

/**
 * @return URL to the local store's database.
 */
- (NSURL *)URLForLocalStore;

/**
 * This method is designed for enumerating all the USM cloud stores that a user's container may contain.
 * It allows you to provide an emergency store switcher to your app, allowing people to revert to old stores
 * in case they unexpectedly switch to a new cloud store without having migrating the content they want.
 *
 * @return A dictionary that maps cloud store URLs to an array of options dictionaries that can be used to load them.
 */
- (NSDictionary *)enumerateCloudStores;

/**
 * This method is designed to allow you to manually switch to a different USM cloud store.  The options dictionary should be one
 * given to you by -enumerateCloudStores.
 */
- (void)switchToCloudStoreWithOptions:(NSDictionary *)cloudStoreOptions;

#pragma mark - Utilities

/**
 * Migrate entities from one store to another.
 *
 * NOTE: Use this only from the persistence queue (see UbiquityStoreManagerDelegate method documentation).
 *       You probably want -ubiquityStoreManager:willLoadStoreIsCloud:
 *
 * @param migrationStoreURL The URL to the store file of the store from which to copy data.
 * @param migrationStoreOptions The options to use when opening the migration store.  If they include NSReadOnlyPersistentStoreOption and
 * the store file is accessible, we'll migrate a copy of the store to allow store model migration if necessary.
 * May be nil, in which case we'll determine default options depending on what the migrationStoreURL is.
 * @param targetStoreURL The URL to the store file of the store into which the data should be copied.
 * @param targetStoreOptions The options to use when opening the target store.
 * May be nil, in which case we'll determine default options depending on what the targetStoreURL is.
 * @param migrationStrategy The strategy to use for performing the migration.
 * May be 0, in which case we'll use USM's default migration strategy.
 * @param outError When the migration fails, this will point to an NSError object that describes the failure.
 * @param cause When the migration fails, this will point to the cause of the problem which indicates when the failure occurred.
 * @param context See the documentation for the cause to determine what the context will be.
 *
 * @return NO if the migration was unsuccessful for any reason.  YES if the target store contains the migration store's entities.
 */
- (BOOL)migrateStore:(NSURL *)migrationStoreURL withOptions:(NSDictionary *)migrationStoreOptions
             toStore:(NSURL *)targetStoreURL withOptions:(NSDictionary *)targetStoreOptions
            strategy:(UbiquityStoreMigrationStrategy)migrationStrategy
               error:(__autoreleasing NSError **)outError cause:(UbiquityStoreErrorCause *)cause context:(__autoreleasing id *)context;

@end
