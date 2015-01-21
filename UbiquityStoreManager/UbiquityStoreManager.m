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
//  UbiquityStoreManager.m
//  UbiquityStoreManager
//

#import "UbiquityStoreManager.h"
#import "JRSwizzle.h"
#import "NSError+UbiquityStoreManager.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>

#else
#import <Cocoa/Cocoa.h>
#endif

#define IfOut(__out, __value) ({ __typeof__(*__out) __var = __value; if (__out) { *__out = __var; }; __var; })

NSString *const USMStoreWillChangeNotification = @"USMStoreWillChangeNotification";
NSString *const USMStoreDidChangeNotification = @"USMStoreDidChangeNotification";
NSString *const USMStoreDidImportChangesNotification = @"USMStoreDidImportChangesNotification";

NSString *const USMCloudEnabledKey = @"USMCloudEnabledKey";
NSString *const USMCloudVersionKey = @"USMCloudVersionKey";
NSString *const USMCloudCurrentKey = @"USMCloudCurrentKey";
NSString *const USMCloudUUIDKey = @"USMCloudUUIDKey";

NSString *const USMCloudContentName = @"UbiquityStore";
NSString *const USMCloudStoreDirectory = @"CloudStore";
NSString *const USMCloudStoreMigrationSource = @"MigrationSource.sqlite";
NSString *const USMCloudContentDirectory = @"CloudLogs";
NSString *const USMCloudContentStoreUUID = @"StoreUUID";
NSString *const USMCloudContentCorruptedUUID = @"CorruptedUUID";

extern NSString *NSStringFromUSMCause(UbiquityStoreErrorCause cause) {

    switch (cause) {
        case UbiquityStoreErrorCauseNoError:
            return @"UbiquityStoreErrorCauseNoError";
        case UbiquityStoreErrorCauseDeleteStore:
            return @"UbiquityStoreErrorCauseDeleteStore";
        case UbiquityStoreErrorCauseCreateStorePath:
            return @"UbiquityStoreErrorCauseCreateStorePath";
        case UbiquityStoreErrorCauseClearStore:
            return @"UbiquityStoreErrorCauseClearStore";
        case UbiquityStoreErrorCauseOpenActiveStore:
            return @"UbiquityStoreErrorCauseOpenActiveStore";
        case UbiquityStoreErrorCauseOpenSeedStore:
            return @"UbiquityStoreErrorCauseOpenSeedStore";
        case UbiquityStoreErrorCauseSeedStore:
            return @"UbiquityStoreErrorCauseSeedStore";
        case UbiquityStoreErrorCauseImportChanges:
            return @"UbiquityStoreErrorCauseImportChanges";
        case UbiquityStoreErrorCauseConfirmActiveStore:
            return @"UbiquityStoreErrorCauseConfirmActiveStore";
        case UbiquityStoreErrorCauseCorruptActiveStore:
            return @"UbiquityStoreErrorCauseCorruptActiveStore";
        case UbiquityStoreErrorCauseEnumerateStores:
            return @"UbiquityStoreErrorCauseEnumerateStores";
    }

    return [NSString stringWithFormat:@"UnsupportedCause:%d", cause];
}

typedef NS_ENUM(NSUInteger, USMEnabledStore) {
    USMEnabledStoreNone,
    USMEnabledStoreLocal,
    USMEnabledStoreCloud
};

/** USMFilePresenter monitors a file for NSFilePresenter related changes. */
@interface USMFilePresenter : NSObject<NSFilePresenter>

@property(nonatomic, weak, readonly) UbiquityStoreManager *delegate;
@property(nonatomic, strong, readonly) NSFileCoordinator *coordinator;

- (id)initWithURL:(NSURL *)presentedItemURL delegate:(UbiquityStoreManager *)delegate;

- (void)start;
- (void)stop;

@end

/** USMFileContentPresenter extends USMFilePresenter to add metadata change monitoring. */
@interface USMFileContentPresenter : USMFilePresenter

@property(nonatomic, strong) NSMetadataQuery *query;

- (void)handleConflicts;

@end

/** USMLocalStoreFilePresenter monitors our active store file. */
@interface USMLocalStoreFilePresenter : USMFilePresenter

- (id)initWithUSM:(UbiquityStoreManager *)manager;
@end

/** USMLocalStoreFilePresenter monitors the file that contains the active store UUID.
 * Changes to this file mean the active store has changed and we need to load the new store.
 */
@interface USMStoreUUIDPresenter : USMFileContentPresenter

- (id)initWithUSM:(UbiquityStoreManager *)manager;

@end

/** USMLocalStoreFilePresenter monitors the file that contains the corrupted store UUID.
 * Changes to this file mean a device has detected cloud corruption and we try to fix it.
 */
@interface USMCorruptedUUIDPresenter : USMFileContentPresenter

- (id)initWithUSM:(UbiquityStoreManager *)manager;

@end

@interface UbiquityStoreManager()

@property(nonatomic, copy) NSString *contentName;
@property(nonatomic, strong) NSManagedObjectModel *model;
@property(nonatomic, copy) NSString *containerIdentifier;
@property(nonatomic, copy) NSDictionary *storeOptions;
@property(nonatomic, readonly) NSString *storeUUID;
@property(nonatomic, strong) NSString *tentativeStoreUUID;
@property(nonatomic, strong) NSOperationQueue *persistentStorageQueue;
@property(nonatomic, readonly) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property(nonatomic, strong) id<NSObject, NSCopying, NSCoding> currentIdentityToken;
@property(nonatomic, strong) NSURL *migrationStoreURL;
@property(nonatomic) BOOL attemptCloudRecovery;
@property(nonatomic) NSString *localCloudStoreCorruptedUUID;
@property(nonatomic) NSString *activeCloudStoreUUID;
@property(nonatomic) USMEnabledStore enabledStore;
@property(nonatomic, strong) USMLocalStoreFilePresenter *storeFilePresenter;
@property(nonatomic, strong) USMStoreUUIDPresenter *storeUUIDPresenter;
@property(nonatomic, strong) USMCorruptedUUIDPresenter *corruptedUUIDPresenter;
@property(nonatomic, strong) NSBlockOperation *finishedLoadingOperation;

@end

@implementation UbiquityStoreManager {
    NSPersistentStoreCoordinator *_persistentStoreCoordinator;
}

+ (void)initialize {

    if (self != [UbiquityStoreManager class])
        return;

    if (![self respondsToSelector:@selector(jr_swizzleMethod:withMethod:error:)]) {
        NSLog( @"UbiquityStoreManager: Warning: JRSwizzle not present, won't be able to detect desync issues." );
        return;
    }

    NSError *error = nil;
    if (![NSError jr_swizzleMethod:@selector(initWithDomain:code:userInfo:)
                        withMethod:@selector(init_USM_WithDomain:code:userInfo:)
                             error:&error])
        NSLog( @"UbiquityStoreManager: Warning: Failed to swizzle, won't be able to detect desync issues.  Cause: %@", error );
}

- (id)initWithDelegate:(id<UbiquityStoreManagerDelegate>)delegate {

    return [self initStoreNamed:nil withManagedObjectModel:nil localStoreURL:nil containerIdentifier:nil
             storeConfiguration:nil storeOptions:nil delegate:delegate];
}

- (id)initStoreNamed:(NSString *)contentName withManagedObjectModel:(NSManagedObjectModel *)model localStoreURL:(NSURL *)localStoreURL
 containerIdentifier:(NSString *)containerIdentifier storeConfiguration:(NSString *)storeConfiguration
        storeOptions:(NSDictionary *)storeOptions
            delegate:(id<UbiquityStoreManagerDelegate>)delegate {

    if (!(self = [super init]))
        return nil;

    // Parameters.
    _delegate = delegate;
    _contentName = contentName == nil? USMCloudContentName: contentName;
    _model = model == nil? [NSManagedObjectModel mergedModelFromBundles:nil]: model;
    if (!localStoreURL)
        localStoreURL = [[[self URLForApplicationContainer]
                URLByAppendingPathComponent:[self localContentName] isDirectory:NO]
                URLByAppendingPathExtension:@"sqlite"];
    _localStoreURL = localStoreURL;
    _containerIdentifier = containerIdentifier;
    _storeConfiguration = storeConfiguration;
    _storeOptions = storeOptions == nil? @{ }: storeOptions;

    // Private vars.
    _currentIdentityToken = [[NSFileManager defaultManager] respondsToSelector:@selector(ubiquityIdentityToken)]?
                            [[NSFileManager defaultManager] ubiquityIdentityToken]: nil;
    _migrationStrategy = &NSPersistentStoreUbiquitousContainerIdentifierKey?
                         UbiquityStoreMigrationStrategyIOS: UbiquityStoreMigrationStrategyCopyEntities;
    _persistentStorageQueue = [NSOperationQueue new];
    _persistentStorageQueue.name = [NSString stringWithFormat:@"%@PersistenceQueue", NSStringFromClass( [self class] )];
    _persistentStorageQueue.maxConcurrentOperationCount = 1;

    // Observe application events.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ubiquityStoreManagerDidDetectCorruption:)
                                                 name:UbiquityManagedStoreDidDetectCorruptionNotification
                                               object:nil];
#if TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDefaultsDidChange:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];
#else
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];
#endif
    if (&NSUbiquityIdentityDidChangeNotification)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cloudStoreChanged:)
                                                     name:NSUbiquityIdentityDidChangeNotification
                                                   object:nil];

    [self reloadStore];

    return self;
}

- (void)dealloc {

    // Stop listening for store changes.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.storeFilePresenter stop];
    [self.storeUUIDPresenter stop];
    [self.corruptedUUIDPresenter stop];

    // Unload the store.
    [self enqueue:^{ [self clearStore]; } waitUntilFinished:YES];
}

#pragma mark - File Handling

- (NSString *)localContentName {

    return _contentName;
}

/**
 * Get the name of the cloud content for the given cloud store.
 *
 * For version 0 (iOS 6) this defaults to USMCloudContentName, for version 1 this is the StoreUUID.
 */
- (NSString *)cloudContentNameForStoreURL:(NSURL *)storeURL {

    int cloudVersion = [self cloudVersionForStoreURL:storeURL];
    return [self cloudContentNameForStoreURL:storeURL andCloudVersion:cloudVersion];
}

/**
 * Get the name of the cloud content for the given cloud store.
 *
 * For version 0 (iOS 6) this defaults to USMCloudContentName, for version 1 this is the StoreUUID.
 */
- (NSString *)cloudContentNameForStoreURL:(NSURL *)storeURL andCloudVersion:(int)cloudVersion {

    if (cloudVersion == 0)
        return _contentName;

    return storeURL? [[storeURL URLByDeletingPathExtension] lastPathComponent]: self.storeUUID;
}

/**
 * Get a versioned version of the identifier by appending +'s to it.  The version to use is determined from the storeURL.
 */
- (NSString *)cloudVersionedIdentifier:(NSString *)identifier forStoreURL:(NSURL *)storeURL {

    return [self versionedIdentifier:identifier version:[self cloudVersionForStoreURL:storeURL]];
}

/**
 * Get a versioned version of the identifier by appending +'s to it.
 */
- (NSString *)versionedIdentifier:(NSString *)identifier version:(int)version {

    for (int v = 0; v < version; ++v)
        identifier = [identifier stringByAppendingString:@"+"];

    return identifier;
}

/**
 * The version preferred for cloud content by the current platform when not in compatibility mode (eg. for new stores).
 *
 * For iOS 6, this returns 0.  For iOS 7+, the version is 1.
 */
- (int)desiredCloudVersion {

    if (&NSPersistentStoreUbiquitousContainerIdentifierKey)
        return 1;

    return 0;
}

/**
 * Determine the version of the cloud store at the given URL.
 *
 * We find a StoreUUID file that mentions the cloud store's UUID and return its version.
 * If there isn't one, this is deemed a new store and we return the desired version.
 */
- (int)cloudVersionForStoreURL:(NSURL *)storeURL {

    // Determine the cloud version to use by trying the desired version for the platform and backing down
    // until a StoreUUID for the version is found.
    int desiredCloudVersion = [self desiredCloudVersion];
    int cloudVersion = desiredCloudVersion;
    NSString *forStoreUUID = [[storeURL URLByDeletingPathExtension] lastPathComponent];

    for (; cloudVersion >= 0; --cloudVersion) {
        NSString *storeUUIDPath = [self URLForCloudStoreUUIDForVersion:cloudVersion].path;
        if ([[NSFileManager defaultManager] fileExistsAtPath:storeUUIDPath] &&
            (!forStoreUUID ||
             [[NSString stringWithContentsOfFile:storeUUIDPath encoding:NSUTF8StringEncoding error:nil]
                     isEqualToString:forStoreUUID]))
            break;
    }
    if (cloudVersion < 0)
        return desiredCloudVersion;

    return cloudVersion;
}

- (NSURL *)URLForApplicationContainer {

    NSURL *applicationSupportURL = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                           inDomains:NSUserDomainMask] lastObject];

#if TARGET_OS_IPHONE
    // On iOS, each app is in a sandbox so we don't need to app-scope this directory.
    return applicationSupportURL;
#else
    // The directory is shared between all apps on the system so we need to scope it for the running app.
    applicationSupportURL = [applicationSupportURL URLByAppendingPathComponent:[NSRunningApplication currentApplication].bundleIdentifier isDirectory:YES];

    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:applicationSupportURL
                                  withIntermediateDirectories:YES attributes:nil error:&error])
        [self error:error cause:UbiquityStoreErrorCauseCreateStorePath context:applicationSupportURL.path];

    return applicationSupportURL;
#endif
}

- (NSURL *)URLForCloudContainer {

    return [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:self.containerIdentifier];
}

/**
 * The directory where cloud store files are kept.
 *
 * For iOS 6, this is in a .nosync in the cloud container.  For iOS 7+ in the application sandbox.
 */
- (NSURL *)URLForCloudStoreDirectory {

    return [self URLForCloudStoreDirectoryForCloudVersion:[self desiredCloudVersion]];
}

/**
 * The directory where cloud store files are kept.
 *
 * For iOS 6, this is in a .nosync in the cloud container.  For iOS 7+ in the application sandbox.
 */
- (NSURL *)URLForCloudStoreDirectoryForCloudVersion:(int)version {

    if (version == 0)
            // iOS 6
            // We put the database in the ubiquity container with a .nosync extension (must not be synced by iCloud),
            // so that its presence is tied closely to whether iCloud is enabled or not on the device
            // and the user can delete the store by deleting his iCloud data for the app from Settings.
        return [[[self URLForCloudContainer] URLByAppendingPathComponent:USMCloudStoreDirectory isDirectory:YES]
                URLByAppendingPathExtension:@"nosync"];

    // On iOS7+ the store needs to be in the application container and is managed by the iCloud framework.
    return [[self URLForApplicationContainer] URLByAppendingPathComponent:USMCloudStoreDirectory isDirectory:YES];
}

- (NSURL *)URLForCloudStore {

    return [self URLForCloudStoreWithUUID:self.storeUUID];
}

- (NSURL *)URLForCloudStoreWithUUID:(NSString *)storeUUID {

    // Our cloud store is in the cloud store databases directory and is identified by the active storeUUID.
    return [[[self URLForCloudStoreDirectory] URLByAppendingPathComponent:storeUUID isDirectory:NO]
            URLByAppendingPathExtension:@"sqlite"];
}

- (NSURL *)URLForCloudContentDirectory {

    // The transaction logs are in the ubiquity container and are synced by iCloud.
    return [[self URLForCloudContainer] URLByAppendingPathComponent:USMCloudContentDirectory isDirectory:YES];
}

- (id)URLForCloudContent {

    return [self URLForCloudContentForStoreURL:nil];
}

- (id)URLForCloudContentForStoreURL:(NSURL *)storeURL {

    NSString *storeUUID = storeURL? [[storeURL URLByDeletingPathExtension] lastPathComponent]: self.storeUUID;
    if (&NSPersistentStoreUbiquitousContainerIdentifierKey)
        return [USMCloudContentDirectory stringByAppendingPathComponent:storeUUID];

    // Our cloud store's logs are in the cloud store transaction logs directory and is identified by the active storeUUID.
    return [[self URLForCloudContentDirectory] URLByAppendingPathComponent:storeUUID isDirectory:YES];
}

/**
 * Contrary to -URLForCloudContent, this method can return nil, in which case the location of the cloud content has not yet been established.
 */
- (id)URLForCloudContent_ThreadSafe {

    NSString *storeUUID = [self storeUUID_ThreadSafe];
    if (!storeUUID)
        return nil;

    if (&NSPersistentStoreUbiquitousContainerIdentifierKey)
        return [USMCloudContentDirectory stringByAppendingPathComponent:storeUUID];

    // Our cloud store's logs are in the cloud store transaction logs directory and is identified by the active storeUUID.
    return [[self URLForCloudContentDirectory] URLByAppendingPathComponent:storeUUID isDirectory:YES];
}

- (NSURL *)URLForCloudStoreUUID {

    // The UUID of the active cloud store is in the cloud store transaction logs directory.
    return [[self URLForCloudContentDirectory]
            URLByAppendingPathComponent:[self cloudVersionedIdentifier:USMCloudContentStoreUUID forStoreURL:nil]
                            isDirectory:NO];
}

- (NSURL *)URLForCloudStoreUUIDForVersion:(int)version {

    // The UUID of the active cloud store is in the cloud store transaction logs directory.
    return [[self URLForCloudContentDirectory]
            URLByAppendingPathComponent:[self versionedIdentifier:USMCloudContentStoreUUID version:version]
                            isDirectory:NO];
}

- (NSURL *)URLForCloudCorruptedUUID {

    // The UUID of the corrupted cloud store is in the cloud store transaction logs directory.
    return [[self URLForCloudContentDirectory]
            URLByAppendingPathComponent:[self cloudVersionedIdentifier:USMCloudContentCorruptedUUID forStoreURL:nil]
                            isDirectory:NO];
}

- (NSURL *)URLForCloudCorruptedUUIDForVersion:(int)version {

    // The UUID of the corrupted cloud store is in the cloud store transaction logs directory.
    return [[self URLForCloudContentDirectory]
            URLByAppendingPathComponent:[self versionedIdentifier:USMCloudContentCorruptedUUID version:version]
                            isDirectory:NO];
}

- (NSURL *)URLForLocalStoreDirectory {

    return [self.localStoreURL URLByDeletingLastPathComponent];
}

- (NSURL *)URLForLocalStore {

    return self.localStoreURL;
}

- (NSDictionary *)enumerateCloudStores {

    NSURL *cloudContentDirectory = [self URLForCloudContentDirectory];
    if (!cloudContentDirectory)
        return nil;

    NSError *error = nil;
    NSArray *cloudContentURLs = [[NSFileManager defaultManager]
            contentsOfDirectoryAtURL:cloudContentDirectory includingPropertiesForKeys:nil
                             options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
    if (!cloudContentURLs) {
        [self error:error cause:UbiquityStoreErrorCauseEnumerateStores context:cloudContentDirectory.path];
        return nil;
    }

    int maxCloudVersion = [self desiredCloudVersion];
    NSMutableDictionary *cloudStores = [NSMutableDictionary dictionary];
    for (NSURL *cloudContentURL in cloudContentURLs) {
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:cloudContentURL.path isDirectory:&isDirectory] && !isDirectory)
            continue;

        NSString *storeUUID = [cloudContentURL lastPathComponent];
        NSURL *storeURL = [self URLForCloudStoreWithUUID:storeUUID];

        NSMutableArray *cloudStoreOptionSets = [NSMutableArray array];
        NSArray *peerURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:cloudContentURL includingPropertiesForKeys:nil
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
        for (NSURL *peerURL in peerURLs) {
            NSArray *cloudContentNameURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:peerURL includingPropertiesForKeys:nil
                                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                               error:&error];
            for (NSURL *cloudContentNameURL in cloudContentNameURLs) {
                NSMutableDictionary *cloudStoreOptions = [self optionsForCloudStoreURL:storeURL];
                NSString *cloudContentName = [cloudContentNameURL lastPathComponent];

                for (int cloudVersion = maxCloudVersion; cloudVersion >= 0; --cloudVersion)
                    if ([cloudContentName isEqualToString:[self cloudContentNameForStoreURL:storeURL andCloudVersion:cloudVersion]]) {
                        cloudStoreOptions[NSPersistentStoreUbiquitousContentNameKey] = cloudContentName;
                        cloudStoreOptions[USMCloudVersionKey] = @(cloudVersion);
                        cloudStoreOptions[USMCloudCurrentKey] = @([[self storeUUID_ThreadSafe] isEqualToString:storeUUID] &&
                                                                  [self cloudVersionForStoreURL:storeURL] == cloudVersion);
                        cloudStoreOptions[USMCloudUUIDKey] = storeUUID;
                        [cloudStoreOptionSets addObject:cloudStoreOptions];
                        break;
                    }
            }
        }
        cloudStores[storeURL] = cloudStoreOptionSets;
    }

    return cloudStores;
}

- (void)switchToCloudStoreWithOptions:(NSDictionary *)cloudStoreOptions {

    [self setStoreUUID:cloudStoreOptions[USMCloudUUIDKey] withCloudVersion:[cloudStoreOptions[USMCloudVersionKey] intValue]];

    if (self.cloudEnabled)
        [self reloadStore];
}


#pragma mark - Utilities

- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2) {

    va_list argList;
    va_start(argList, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:argList];
    va_end(argList);

    if ([self.delegate respondsToSelector:@selector(ubiquityStoreManager:log:)])
        [self.delegate ubiquityStoreManager:self log:message];
    else
        NSLog( @"UbiquityStoreManager: %@", message );
}

- (void)logError:(NSString *)error cause:(UbiquityStoreErrorCause)cause context:(id)context {

    [self error:[NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:@{ NSLocalizedFailureReasonErrorKey : error }]
          cause:cause context:context];
}

- (void)error:(NSError *)error cause:(UbiquityStoreErrorCause)cause context:(id)context {

    if ([self.delegate respondsToSelector:@selector(ubiquityStoreManager:didEncounterError:cause:context:)])
        [self.delegate ubiquityStoreManager:self didEncounterError:error cause:cause context:context];
    else {
        [self log:@"Error (cause:%@): %@", NSStringFromUSMCause( cause ), error];

        if (context)
            [self log:@"    - Context   : %@", context];
        NSError *underlyingError = [error userInfo][NSUnderlyingErrorKey];
        if (underlyingError)
            [self log:@"    - Underlying: %@", underlyingError];
        NSArray *detailedErrors = [error userInfo][NSDetailedErrorsKey];
        for (NSError *detailedError in detailedErrors)
            [self log:@"    - Detail    : %@", detailedError];
    }
}

- (void)assertQueued {

    NSAssert([NSOperationQueue currentQueue] == self.persistentStorageQueue, @"This call may only be invoked from the persistence queue.");
}

/**
 * @return YES if we are currently on the persistence queue.  NO if we aren't and the enqueueBlock has been submitted to it.
 */
- (BOOL)ensureQueued:(void (^)())enqueueBlock {

    if ([NSOperationQueue currentQueue] == self.persistentStorageQueue)
        return YES;

    [self enqueue:enqueueBlock];
    return NO;
}

- (void)enqueue:(void (^)())enqueueBlock {

    [self enqueue:enqueueBlock waitUntilFinished:NO];
}

- (void)enqueue:(void (^)())enqueueBlock waitUntilFinished:(BOOL)wait {

    [self enqueue:enqueueBlock waitUntilFinished:NO lock:YES];
}

- (void)enqueue:(void (^)())enqueueBlock waitUntilFinished:(BOOL)wait lock:(BOOL)lock {

    [self.persistentStorageQueue addOperations:@[
            [NSBlockOperation blockOperationWithBlock:^{
                @try {
                    if (lock)
                        [self.persistentStoreCoordinator lock];
                    enqueueBlock();
                }
                @catch (NSException *exception) {
                    [self logError:[(id<NSObject>)exception description]
                             cause:UbiquityStoreErrorCauseOpenActiveStore context:exception];
                }
                @finally {
                    if (lock)
                        [self.persistentStoreCoordinator unlock];
                }
            }]
    ]                        waitUntilFinished:wait];
}

#pragma mark - Store Management

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {

    [self assertQueued];

    if (!_persistentStoreCoordinator) {
        _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
        if (&NSPersistentStoreDidImportUbiquitousContentChangesNotification)
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didImportChanges:)
                                                         name:NSPersistentStoreDidImportUbiquitousContentChangesNotification
                                                       object:_persistentStoreCoordinator];
        if (&NSPersistentStoreCoordinatorStoresWillChangeNotification)
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storesWillChange:)
                                                         name:NSPersistentStoreCoordinatorStoresWillChangeNotification
                                                       object:_persistentStoreCoordinator];
        if (&NSPersistentStoreCoordinatorStoresDidChangeNotification)
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storesDidChange:)
                                                         name:NSPersistentStoreCoordinatorStoresDidChangeNotification
                                                       object:_persistentStoreCoordinator];
    }

    return _persistentStoreCoordinator;
}

- (void)resetPersistentStoreCoordinator {

    [self assertQueued];

    if (_persistentStoreCoordinator) {
        [_persistentStoreCoordinator unlock];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:_persistentStoreCoordinator];
        _persistentStoreCoordinator = nil;
    }

    [self.persistentStoreCoordinator lock];
}

- (void)clearStore {

    [self log:@"Clearing stores..."];
    [self assertQueued];

    // Stop listening for store changes.
    [self.storeFilePresenter stop];
    [self.storeUUIDPresenter stop];
    [self.corruptedUUIDPresenter stop];

    // Let the application clean up its MOCs.
    [self.persistentStoreCoordinator unlock];
    [self fireBeginLoadingLogReason:@"Will clear stores"];

    // Remove the store from the coordinator.
    NSError *error = nil;
    self.activeCloudStoreUUID = nil;
    for (NSPersistentStore *store in self.persistentStoreCoordinator.persistentStores)
        if (![self.persistentStoreCoordinator removePersistentStore:store error:&error])
            [self error:error cause:UbiquityStoreErrorCauseClearStore context:store];

    // If we failed to remove all the stores, throw away the PSC and create a new one.
    if ([[self.persistentStoreCoordinator persistentStores] count])
        [self resetPersistentStoreCoordinator];
    else
        [self.persistentStoreCoordinator lock];

    // Set up the file presenters.
    self.storeUUIDPresenter = [[USMStoreUUIDPresenter alloc] initWithUSM:self];
    self.corruptedUUIDPresenter = [[USMCorruptedUUIDPresenter alloc] initWithUSM:self];
    self.storeFilePresenter = [[USMLocalStoreFilePresenter alloc] initWithUSM:self];
    if (self.cloudEnabled) {
        [self.storeUUIDPresenter start];
        [self.corruptedUUIDPresenter start];
    }
    else {
        [self.storeFilePresenter start];
    }
}

- (void)reloadStore {

    if (![self ensureQueued:^{ [self reloadStore]; }])
        return;

    [self log:@"%@ store...", [[self.persistentStoreCoordinator persistentStores] count]? @"Reloading": @"Loading"];

    // If user is not logged into iCloud, don't try to cloud cloud store: It will fail and not due to corruption.
    BOOL cloudEnabled = self.cloudEnabled;
    if (cloudEnabled && !self.cloudAvailable) {
        [self log:@"Cannot load cloud store: User is not logged into iCloud.  Falling back to local store."];
        if (self.enabledStore == USMEnabledStoreLocal)
                // The local store is already active.
            return;

        if ([self.delegate respondsToSelector:@selector(ubiquityStoreManagerHandleCloudDisabled:)] &&
            [self.delegate ubiquityStoreManagerHandleCloudDisabled:self])
            // Handled by application.
            return;

        cloudEnabled = NO;
    }

    // Load the requested store.  If the cloud store fails to load, mark it corrupt so we can try to recover it.
    if (cloudEnabled) {
        if (![self tryLoadCloudStore]) {
            // Failed to load regardless of recovery attempt.  Mark store as corrupt.
            [self log:@"Failed to load cloud store. Marking cloud store as corrupt. Store will be unavailable."];
            [self markCloudStoreCorrupted];
        }
    }
    else
        [self tryLoadLocalStore];
}

- (BOOL)tryLoadCloudStore {

    [self log:@"Will load cloud store."];
    [self assertQueued];

    // Check if the user is logged into iCloud on the device.
    if (!self.cloudAvailable) {
        [self log:@"Could not load cloud store: User is not logged into iCloud."];
        return NO;
    }

    // Clear the active persistence store and mark cloud as enabled.
    self.enabledStore = USMEnabledStoreCloud;
    [self clearStore];
    self.activeCloudStoreUUID = nil;

    // Begin loading the cloud store 'atomically'.
    id context = nil;
    UbiquityStoreErrorCause cause = UbiquityStoreErrorCauseNoError;
    @try {
        NSURL *cloudStoreURL = [self URLForCloudStore];
        [self log:@"Loading cloud store: %@, v%d (%@).", [self storeUUIDForLog], [self cloudVersionForStoreURL:cloudStoreURL],
                  _tentativeStoreUUID? @"tentative": @"definite"];

        // Check if we need to seed the store by migrating another store into it.
        UbiquityStoreMigrationStrategy migrationStrategy = self.migrationStrategy;
        [self log:@"[DEBUG] migrationStoreURL: %@", self.migrationStoreURL];
        NSURL *migrationStoreURL = self.migrationStoreURL? self.migrationStoreURL: [self localStoreURL];
        NSMutableDictionary *migrationStoreOptions = [self optionsForMigrationStoreURL:migrationStoreURL];
        [self log:@"[DEBUG] migrationStoreOptions: %@", migrationStoreOptions];
        [self log:@"[DEBUG] cloudSafeForSeeding: %d", [self cloudSafeForSeeding]];
        if (migrationStrategy == UbiquityStoreMigrationStrategyNone ||
            !migrationStoreOptions || ![self cloudSafeForSeeding] ||
            // We want to migrate from migrationStoreURL, check with application.
            ([self.delegate respondsToSelector:@selector(ubiquityStoreManager:shouldMigrateFromStoreURL:toStoreURL:isCloud:)] &&
             ![self.delegate ubiquityStoreManager:self
                        shouldMigrateFromStoreURL:migrationStoreURL toStoreURL:cloudStoreURL
                                          isCloud:YES])) {
            [self log:@"[DEBUG] Will NOT migrate to cloud store from: %@ (strategy: %d).", [migrationStoreURL lastPathComponent],
                      migrationStrategy];
            migrationStrategy = UbiquityStoreMigrationStrategyNone;
            migrationStoreURL = nil;
        }
        else
            [self log:@"Will migrate to cloud store from: %@ (strategy: %d).", [migrationStoreURL lastPathComponent],
                      migrationStrategy];

        // Load the cloud store.
        NSMutableDictionary *cloudStoreOptions = [self optionsForCloudStoreURL:cloudStoreURL];
        if (self.attemptCloudRecovery) {
            if (&NSPersistentStoreRebuildFromUbiquitousContentOption)
                    // iOS 7+
                cloudStoreOptions[NSPersistentStoreRebuildFromUbiquitousContentOption] = @YES;
            else
                    // iOS 6
                [self deleteCloudStoreLocalOnly:YES];
        }
        [self loadStoreAtURL:cloudStoreURL withOptions:cloudStoreOptions
         migratingStoreAtURL:migrationStoreURL withOptions:migrationStoreOptions
               usingStrategy:migrationStrategy cause:&cause context:&context];
    }
    @catch (id exception) {
        [self logError:[(id<NSObject>)exception description]
                 cause:cause = UbiquityStoreErrorCauseOpenActiveStore context:context = exception];
    }
    @finally {
        if (cause == UbiquityStoreErrorCauseNoError) {
            // Store loaded successfully.
            [self confirmTentativeStoreUUID];
            self.activeCloudStoreUUID = [self storeUUID];
            self.attemptCloudRecovery = NO;
            self.migrationStoreURL = nil;

            [self updateStoreUUIDAsynchronously:YES];
            [self log:@"Successfully loaded cloud store."];
        }
        else {
            // An error occurred in the @try block.
            [self logError:@"Failed to load cloud store." cause:cause context:context];
            [self unsetTentativeStoreUUID];
            [self clearStore];

            // If we haven't attempted recovery yet (ie. delete the cloud store file), try that first.
            if (!self.attemptCloudRecovery) {
                [self log:@"Attempting recovery by rebuilding from cloud content."];
                self.attemptCloudRecovery = YES;
                return [self tryLoadCloudStore];
            }
            self.attemptCloudRecovery = NO;

            self.enabledStore = USMEnabledStoreNone;
        }
    }

    // Notify the application.
    [self fireFinishedLoadingLogReason:@"Finished loading cloud store" cause:cause context:context];
    return cause == UbiquityStoreErrorCauseNoError;
}

- (BOOL)tryLoadLocalStore {

    [self log:@"Will load local store."];
    [self assertQueued];

    // Clear the active persistence store and mark cloud as disabled.
    self.enabledStore = USMEnabledStoreLocal;
    [self clearStore];

    id context = nil;
    UbiquityStoreErrorCause cause = UbiquityStoreErrorCauseNoError;
    @try {
        NSURL *localStoreURL = [self URLForLocalStore];
        NSURL *migrationStoreURL = self.migrationStoreURL;

        UbiquityStoreMigrationStrategy migrationStrategy = self.migrationStrategy;
        NSMutableDictionary *migrationStoreOptions = [self optionsForMigrationStoreURL:migrationStoreURL];
        if (migrationStrategy == UbiquityStoreMigrationStrategyNone ||
            !migrationStoreOptions ||
            // We want to migrate from migrationStoreURL, check with application.
            ([self.delegate respondsToSelector:@selector(ubiquityStoreManager:shouldMigrateFromStoreURL:toStoreURL:isCloud:)] &&
             ![self.delegate ubiquityStoreManager:self
                        shouldMigrateFromStoreURL:migrationStoreURL toStoreURL:localStoreURL
                                          isCloud:NO]) ||
            // Migration OK'ed by application, make sure destination store doesn't exist.
            [[NSFileManager defaultManager] fileExistsAtPath:localStoreURL.path])
            migrationStrategy = UbiquityStoreMigrationStrategyNone;
        else
            [self log:@"Will migrate to local store from: %@ (strategy: %d).", [migrationStoreURL lastPathComponent], migrationStrategy];

        // Load the local store.
        [self loadStoreAtURL:localStoreURL withOptions:[self optionsForLocalStore]
         migratingStoreAtURL:migrationStoreURL withOptions:migrationStoreOptions
               usingStrategy:migrationStrategy cause:&cause context:&context];
    }
    @catch (id exception) {
        [self logError:[(id<NSObject>)exception description]
                 cause:cause = UbiquityStoreErrorCauseOpenActiveStore context:context = exception];
    }
    @finally {
        if (cause == UbiquityStoreErrorCauseNoError) {
            // Store loaded successfully.
            self.migrationStoreURL = nil;

            [self log:@"Successfully loaded local store."];
        }
        else {
            // An error occurred in the @try block.
            [self logError:@"Failed to load local store." cause:cause context:context];
            [self clearStore];

            self.enabledStore = USMEnabledStoreNone;
        }

        // Notify the application.
        [self fireFinishedLoadingLogReason:@"Finished loading local store" cause:cause context:context];
    }

    return cause == UbiquityStoreErrorCauseNoError;
}

- (void)fireBeginLoadingLogReason:(NSString *)reason {

    [self log:@"%@.  Notifying application to reset its UI.", reason];
    if ([self.delegate respondsToSelector:@selector(ubiquityStoreManager:willLoadStoreIsCloud:)])
        [self.delegate ubiquityStoreManager:self willLoadStoreIsCloud:self.cloudEnabled];
    [[NSNotificationCenter defaultCenter] postNotificationName:USMStoreWillChangeNotification object:self userInfo:nil];

    // Invalidate any previous finished notifications.
    [self.finishedLoadingOperation cancel];
}

- (void)fireFinishedLoadingLogReason:(NSString *)reason cause:(UbiquityStoreErrorCause)cause context:(id)context {

    [self.finishedLoadingOperation cancel];
    self.finishedLoadingOperation = [NSBlockOperation blockOperationWithBlock:^{
        [self log:@"%@ (%@).  Notifying application to refresh its UI.", reason, NSStringFromUSMCause( cause )];
        if (cause == UbiquityStoreErrorCauseNoError && self.persistentStoreCoordinator) {
            if ([self.delegate respondsToSelector:@selector(ubiquityStoreManager:didLoadStoreForCoordinator:isCloud:)])
                [self.delegate ubiquityStoreManager:self didLoadStoreForCoordinator:self.persistentStoreCoordinator
                                            isCloud:self.cloudEnabled];
            [[NSNotificationCenter defaultCenter] postNotificationName:USMStoreDidChangeNotification object:self userInfo:nil];

            // A cloud store that is ubiquitized or has just completed the initial import is deemed healthy if it survives for 30s.
            // The delay is to allow importing pending transaction logs.
            // A healthy store can be used to bump the cloud version or resolve cloud corruption.
            if (self.cloudEnabled &&
                ((&NSPersistentStoreUbiquitousTransitionTypeKey &&
                  [context isKindOfClass:[NSNotification class]] &&
                  [((NSNotification *)context).userInfo[NSPersistentStoreUbiquitousTransitionTypeKey] unsignedIntegerValue] ==
                  NSPersistentStoreUbiquitousTransitionTypeInitialImportCompleted) ||
                 ([((NSPersistentStore *)[self.persistentStoreCoordinator.persistentStores lastObject])
                         .metadata[@"com.apple.coredata.ubiquity.ubiquitized"] boolValue])))
                dispatch_after( dispatch_time( DISPATCH_TIME_NOW, NSEC_PER_SEC * 30 ),
                        dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0 ), ^{
                            [self enqueue:^{
                                if ([self cloudVersionForStoreURL:nil] != [self desiredCloudVersion]) {
                                    [self log:@"Cloud store is healthy but version is below desired.  Will rebuild to upgrade."];
                                    [self rebuildCloudContentFromCloudStoreOrLocalStore:NO];
                                }

                                else if (self.activeCloudStoreUUID && ![self.localCloudStoreCorruptedUUID isEqualToString:self.storeUUID])
                                    [self handleCloudContentCorruption];
                            }];
                        } );
        }
        else {
            if ([self.delegate respondsToSelector:@selector(ubiquityStoreManager:failedLoadingStoreWithCause:context:wasCloud:)])
                [self.delegate ubiquityStoreManager:self failedLoadingStoreWithCause:cause context:context wasCloud:self.cloudEnabled];
        }
    }];
    [self.persistentStorageQueue addOperation:self.finishedLoadingOperation];
}

- (NSMutableDictionary *)optionsForLocalStore {

    NSMutableDictionary *localStoreOptions = [@{
            NSMigratePersistentStoresAutomaticallyOption : @YES,
            NSInferMappingModelAutomaticallyOption       : @YES
    } mutableCopy];
    [localStoreOptions addEntriesFromDictionary:self.storeOptions];

    return localStoreOptions;
}

- (NSMutableDictionary *)optionsForCloudStoreURL:(NSURL *)cloudStoreURL {

    NSString *cloudContentName = [self cloudContentNameForStoreURL:cloudStoreURL];
    NSURL *cloudStoreContentURL = [self URLForCloudContentForStoreURL:cloudStoreURL];
    NSMutableDictionary *cloudStoreOptions = [@{
            NSPersistentStoreUbiquitousContentNameKey    : cloudContentName,
            NSPersistentStoreUbiquitousContentURLKey     : cloudStoreContentURL,
            NSMigratePersistentStoresAutomaticallyOption : @YES,
            NSInferMappingModelAutomaticallyOption       : @YES
    } mutableCopy];

    if (&NSPersistentStoreUbiquitousContainerIdentifierKey) {
        // iOS 7+
        // Cloud store loading options.
        if (self.containerIdentifier)
            cloudStoreOptions[NSPersistentStoreUbiquitousContainerIdentifierKey] = self.containerIdentifier;
    }
    else {
        // iOS 6
        // Clean up the cloud store if the cloud content got deleted.
        BOOL storeExists = [[NSFileManager defaultManager] fileExistsAtPath:cloudStoreURL.path];
        BOOL storeContentExists = [[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:cloudStoreContentURL error:nil];
        if (storeExists && !storeContentExists) {
            // We have a cloud store but no cloud content.  The cloud content was deleted:
            // The existing store cannot sync anymore and needs to be recreated.
            [self log:@"Deleting cloud store: it has no cloud content."];
            [[NSFileManager defaultManager] removeItemAtURL:cloudStoreURL error:nil];
        }
    }

    [cloudStoreOptions addEntriesFromDictionary:self.storeOptions];
    return cloudStoreOptions;
}

- (NSMutableDictionary *)optionsForMigrationStoreURL:(NSURL *)migrationStoreURL {

    if (!migrationStoreURL)
        return nil;

    NSMutableDictionary *migrationStoreOptions;
    if ([[migrationStoreURL lastPathComponent] isEqualToString:USMCloudStoreMigrationSource]) {
        // Migration store is a migration cloud store.  We want to treat it as a local store.
        migrationStoreOptions = [@{
                NSMigratePersistentStoresAutomaticallyOption : @YES,
                NSInferMappingModelAutomaticallyOption       : @YES
        } mutableCopy];
        if (&NSPersistentStoreRemoveUbiquitousMetadataOption)
            migrationStoreOptions[NSPersistentStoreRemoveUbiquitousMetadataOption] = @YES;
        [migrationStoreOptions addEntriesFromDictionary:self.storeOptions];
    }
    else if ([[migrationStoreURL absoluteString] rangeOfString:USMCloudStoreDirectory].location != NSNotFound)
            // Migration store is a regular cloud store.
        migrationStoreOptions = [self optionsForCloudStoreURL:migrationStoreURL];
    else if ([[NSFileManager defaultManager] fileExistsAtPath:migrationStoreURL.path]) {
        // Migration store is something else.
        migrationStoreOptions = [self optionsForLocalStore];
        migrationStoreOptions[NSReadOnlyPersistentStoreOption] = @YES;
    }
    else
            // Migration store doesn't exist and is not a cloud store.
        return nil;

    return migrationStoreOptions;
}

- (void)loadStoreAtURL:(NSURL *)targetStoreURL withOptions:(NSDictionary *)targetStoreOptions
   migratingStoreAtURL:(NSURL *)migrationStoreURL withOptions:(NSDictionary *)migrationStoreOptions
         usingStrategy:(UbiquityStoreMigrationStrategy)migrationStrategy
                 cause:(UbiquityStoreErrorCause *)cause context:(__autoreleasing id *)context {

    [self assertQueued];
    NSAssert([self.persistentStoreCoordinator.persistentStores count] == 0, @"PSC should have no stores before trying to load one.");

    NSError *error = nil;
    @try {
        // Migrating migration store if necessary.
        if (![self migrateStore:migrationStoreURL withOptions:migrationStoreOptions
                        toStore:targetStoreURL withOptions:targetStoreOptions
                       strategy:migrationStrategy error:&error cause:cause context:context])
            return;

        // Ready, loading target store.
        if ([[self.persistentStoreCoordinator persistentStores] count] == 1 &&
            [[[[[self.persistentStoreCoordinator persistentStores] lastObject] URL] lastPathComponent]
                    isEqual:[targetStoreURL lastPathComponent]])
                // Target store already loaded as a result of migration.
            return;

        NSAssert([self.persistentStoreCoordinator.persistentStores count] == 0, @"PSC should have no stores before trying to load one.");
        [self log:@"Loading store: %@", [targetStoreURL lastPathComponent]];
        if (![self.persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:self.storeConfiguration
                                                                     URL:targetStoreURL options:targetStoreOptions
                                                                   error:&error])
            [self error:error cause:IfOut(cause, UbiquityStoreErrorCauseOpenActiveStore)
                context:IfOut(context, targetStoreURL.path)];
    }
    @catch (id exception) {
        [self logError:[(id<NSObject>)exception description]
                 cause:IfOut(cause, UbiquityStoreErrorCauseOpenActiveStore) context:IfOut(context, exception)];
    }
}

- (BOOL)migrateStore:(NSURL *)migrationStoreURL withOptions:(NSDictionary *)migrationStoreOptions
             toStore:(NSURL *)targetStoreURL withOptions:(NSDictionary *)targetStoreOptions
            strategy:(UbiquityStoreMigrationStrategy)migrationStrategy
               error:(__autoreleasing NSError **)outError cause:(UbiquityStoreErrorCause *)cause context:(__autoreleasing id *)context {

    if (!migrationStoreOptions)
        migrationStoreOptions = [self optionsForMigrationStoreURL:migrationStoreURL];
    if (migrationStrategy == 0)
        migrationStrategy = self.migrationStrategy;

    NSError *error = nil;
    NSURL *migrationWorkStoreURL = nil;
    @try {
        IfOut(cause, UbiquityStoreErrorCauseNoError);

        // If the migration store is read-only, copy it so we can open it without read-only to migrate its model if necessary.
        if ([migrationStoreOptions[NSReadOnlyPersistentStoreOption] isEqual:@YES] &&
            [[NSFileManager defaultManager] fileExistsAtPath:migrationStoreURL.path]) {
            NSMutableDictionary *migrationWorkStoreOptions = [migrationStoreOptions mutableCopy];
            migrationWorkStoreURL = [[[migrationStoreURL URLByDeletingLastPathComponent]
                    URLByAppendingPathComponent:@"CopyMigrationStore" isDirectory:NO] URLByAppendingPathExtension:@"sqlite"];
            [[NSFileManager defaultManager] removeItemAtURL:migrationWorkStoreURL error:nil];
            if (![[NSFileManager defaultManager] copyItemAtURL:migrationStoreURL toURL:migrationWorkStoreURL error:&error]) {
                [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseOpenSeedStore)
                    context:IfOut(context, migrationStoreURL.path)];
                return NO;
            }
            migrationWorkStoreOptions[NSReadOnlyPersistentStoreOption] = @NO;
            migrationWorkStoreOptions[NSMigratePersistentStoresAutomaticallyOption] = @YES;
            migrationWorkStoreOptions[NSInferMappingModelAutomaticallyOption] = @YES;
            migrationStoreOptions = migrationWorkStoreOptions;
            migrationStoreURL = migrationWorkStoreURL;
        }

        // If the migration store is not opened ubiquitously, remove its ubiquitous metadata during migration.
        if (&NSPersistentStoreRemoveUbiquitousMetadataOption && !targetStoreOptions[NSPersistentStoreUbiquitousContentNameKey]) {
            NSMutableDictionary *mutableTargetStoreOptions = [targetStoreOptions mutableCopy];
            mutableTargetStoreOptions[NSPersistentStoreRemoveUbiquitousMetadataOption] = @YES;
            targetStoreOptions = mutableTargetStoreOptions;
        }

        // Make sure the store directories exist.
        NSURL *migrationStoreDirectoryURL = [migrationStoreURL URLByDeletingLastPathComponent];
        if (migrationStoreDirectoryURL &&
            ![[NSFileManager defaultManager] createDirectoryAtURL:migrationStoreDirectoryURL
                                      withIntermediateDirectories:YES attributes:nil error:&error]) {
            [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseCreateStorePath)
                context:IfOut(context, migrationStoreDirectoryURL.path)];
            return NO;
        }
        NSURL *targetStoreDirectoryURL = [targetStoreURL URLByDeletingLastPathComponent];
        if (targetStoreDirectoryURL &&
            ![[NSFileManager defaultManager] createDirectoryAtURL:targetStoreDirectoryURL
                                      withIntermediateDirectories:YES attributes:nil error:&error]) {
            [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseCreateStorePath)
                context:IfOut(context, targetStoreDirectoryURL.path)];
            return NO;
        }

        // Migrate using the desired strategy.
        switch (migrationStrategy) {
            case UbiquityStoreMigrationStrategyCopyEntities: {
                [self log:@"Seeding store (strategy: UbiquityStoreMigrationStrategyCopyEntities): %@ -> %@",
                          [migrationStoreURL lastPathComponent], [targetStoreURL lastPathComponent]];
                NSAssert(migrationStoreURL, @"Cannot migrate: No migration store specified.");

                // Handle failure by cleaning up the target store.
                if (![self copyMigrateStore:migrationStoreURL withOptions:migrationStoreOptions
                                    toStore:targetStoreURL withOptions:targetStoreOptions
                                      error:&error cause:cause context:context]) {
                    IfOut(outError, error);
                    [[NSFileManager defaultManager] removeItemAtURL:targetStoreURL error:nil];
                    return NO;
                }

                return YES;
            }

            case UbiquityStoreMigrationStrategyIOS: {
                [self log:@"Seeding store (strategy: UbiquityStoreMigrationStrategyIOS): %@ -> %@",
                          [migrationStoreURL lastPathComponent], [targetStoreURL lastPathComponent]];
                NSAssert(migrationStoreURL, @"Cannot migrate: No migration store specified.");

                // Add the store to migrate.
                NSPersistentStore *migrationStore = [self.persistentStoreCoordinator
                        addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                               URL:migrationStoreURL options:migrationStoreOptions
                                             error:&error];
                if (!migrationStore) {
                    [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseOpenSeedStore)
                        context:IfOut(context, migrationStoreURL.path)];
                    return NO;
                }

                if (![self.persistentStoreCoordinator migratePersistentStore:migrationStore
                                                                       toURL:targetStoreURL options:targetStoreOptions
                                                                    withType:NSSQLiteStoreType error:&error]) {
                    [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseSeedStore)
                        context:IfOut(context, targetStoreURL.path)];
                    [[NSFileManager defaultManager] removeItemAtURL:targetStoreURL error:nil];
                    return NO;
                }

                return YES;
            }

            case UbiquityStoreMigrationStrategyManual: {
                [self log:@"Seeding store (strategy: UbiquityStoreMigrationStrategyManual): %@ -> %@",
                          [migrationStoreURL lastPathComponent], [targetStoreURL lastPathComponent]];
                NSAssert(migrationStoreURL, @"Cannot migrate: No migration store specified.");

                // Instruct the delegate to migrate the migration store to the target store.
                if (![self.delegate ubiquityStoreManager:self
                                    manuallyMigrateStore:migrationStoreURL withOptions:migrationStoreOptions
                                                 toStore:targetStoreURL withOptions:targetStoreOptions error:&error]) {
                    // Handle failure by cleaning up the target store.
                    [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseSeedStore)
                        context:IfOut(context, migrationStoreURL.path)];
                    [[NSFileManager defaultManager] removeItemAtURL:targetStoreURL error:nil];
                    return NO;
                }

                return YES;
            }

            case UbiquityStoreMigrationStrategyNone:
                return YES;
        }
    }
    @catch (id exception) {
        [self logError:[(id<NSObject>)exception description]
                 cause:IfOut(cause, UbiquityStoreErrorCauseSeedStore) context:IfOut(context, exception)];
    }
    @finally {
        if (migrationWorkStoreURL)
            [[NSFileManager defaultManager] removeItemAtURL:migrationWorkStoreURL error:nil];
    }

    return NO;
}

- (BOOL)copyMigrateStore:(NSURL *)migrationStoreURL withOptions:(NSDictionary *)migrationStoreOptions
                 toStore:(NSURL *)targetStoreURL withOptions:(NSDictionary *)targetStoreOptions
                   error:(__autoreleasing NSError **)outError cause:(UbiquityStoreErrorCause *)cause context:(__autoreleasing id *)context {

    [self assertQueued];

    // Open migration store.
    NSError *error = nil;
    NSPersistentStoreCoordinator *migrationCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
    NSPersistentStore *migrationStore = [migrationCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                                                                     URL:migrationStoreURL options:migrationStoreOptions
                                                                                   error:&error];
    if (!migrationStore) {
        [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseOpenSeedStore)
            context:IfOut(context, migrationStoreURL.path)];
        return NO;
    }

    // Open target store.
    NSPersistentStoreCoordinator *targetCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
    NSPersistentStore *targetStore = [targetCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                                                               URL:targetStoreURL options:targetStoreOptions
                                                                             error:&error];
    if (!targetStore) {
        [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseOpenActiveStore)
            context:IfOut(context, targetStoreURL.path)];
        return NO;
    }

    // Set up contexts for them.
    NSManagedObjectContext *migrationContext = [NSManagedObjectContext new];
    NSManagedObjectContext *targetContext = [NSManagedObjectContext new];
    migrationContext.persistentStoreCoordinator = migrationCoordinator;
    targetContext.persistentStoreCoordinator = targetCoordinator;

    // Migrate metadata.
    NSMutableDictionary *metadata = [[migrationCoordinator metadataForPersistentStore:migrationStore] mutableCopy];
    for (NSString *key in [[metadata allKeys] copy])
        if ([key hasPrefix:@"com.apple.coredata.ubiquity"])
                // Don't migrate ubiquitous metadata.
            [metadata removeObjectForKey:key];
    [metadata addEntriesFromDictionary:[targetCoordinator metadataForPersistentStore:targetStore]];
    [targetCoordinator setMetadata:metadata forPersistentStore:targetStore];

    // Migrate entities.
    BOOL migrationFailure = NO;
    NSMutableDictionary *migratedIDsBySourceID = [[NSMutableDictionary alloc] initWithCapacity:500];
    for (NSEntityDescription *entity in self.model.entities) {
        NSFetchRequest *fetch = [NSFetchRequest new];
        fetch.entity = entity;
        fetch.fetchBatchSize = 500;
        fetch.relationshipKeyPathsForPrefetching = entity.relationshipsByName.allKeys;

        NSArray *localObjects = [migrationContext executeFetchRequest:fetch error:&error];
        if (!localObjects) {
            [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseSeedStore)
                context:IfOut(context, migrationStoreURL.path)];
            migrationFailure = YES;
            break;
        }

        for (NSManagedObject *localObject in localObjects)
            [self copyMigrateObject:localObject toContext:targetContext usingMigrationCache:migratedIDsBySourceID];
    }

    // Save migrated entities and unload the stores.
    if (!migrationFailure && ![targetContext save:&error]) {
        [self error:IfOut(outError, error) cause:IfOut(cause, UbiquityStoreErrorCauseSeedStore)
            context:IfOut(context, migrationStoreURL.path)];
        migrationFailure = YES;
    }
    if (![migrationCoordinator removePersistentStore:migrationStore error:&error])
        [self error:error cause:IfOut(cause, UbiquityStoreErrorCauseClearStore) context:IfOut(context, migrationStore)];
    if (![targetCoordinator removePersistentStore:targetStore error:&error])
        [self error:error cause:IfOut(cause, UbiquityStoreErrorCauseClearStore) context:IfOut(context, targetStore)];
    return !migrationFailure;
}

- (id)copyMigrateObject:(NSManagedObject *)sourceObject toContext:(NSManagedObjectContext *)destinationContext
    usingMigrationCache:(NSMutableDictionary *)migratedIDsBySourceID {

    [self assertQueued];

    if (!sourceObject)
        return nil;

    NSManagedObjectID *destinationObjectID = migratedIDsBySourceID[sourceObject.objectID];
    if (destinationObjectID)
        return [destinationContext objectWithID:destinationObjectID];

    @autoreleasepool {
        // Create migrated object.
        NSEntityDescription *entity = sourceObject.entity;
        NSManagedObject *destinationObject = [NSEntityDescription insertNewObjectForEntityForName:entity.name
                                                                           inManagedObjectContext:destinationContext];
        migratedIDsBySourceID[sourceObject.objectID] = destinationObject.objectID;

        // Set attributes
        for (NSString *key in entity.attributesByName.allKeys)
            [destinationObject setPrimitiveValue:[sourceObject primitiveValueForKey:key] forKey:key];

        // Set relationships recursively
        for (NSRelationshipDescription *relationDescription in entity.relationshipsByName.allValues) {
            NSString *key = relationDescription.name;
            id value = nil;

            if (relationDescription.isToMany) {
                value = [[destinationObject primitiveValueForKey:key] mutableCopy];

                for (NSManagedObject *element in [sourceObject primitiveValueForKey:key])
                    [(NSMutableArray *)value addObject:[self copyMigrateObject:element toContext:destinationContext
                                                           usingMigrationCache:migratedIDsBySourceID]];
            }
            else
                value = [self copyMigrateObject:[sourceObject primitiveValueForKey:key] toContext:destinationContext
                            usingMigrationCache:migratedIDsBySourceID];

            [destinationObject setPrimitiveValue:value forKey:key];
        }

        return destinationObject;
    }
}

- (BOOL)cloudSafeForSeeding {

    if (!self.tentativeStoreUUID && [self storeUUID_ThreadSafe])
            // Migration is not safe when the store UUID is set and not tentative.
        return NO;

    return YES;
}

- (BOOL)removeItemAtURL:(NSURL *)directoryURL localOnly:(BOOL)localOnly {

    // The file coordination below fails without an error, when the file at directoryURL doesn't exist.  We ignore this.
    __block BOOL success = NO;
    NSError *error = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter:nil]
            coordinateWritingItemAtURL:directoryURL options:NSFileCoordinatorWritingForDeleting
                                 error:&error byAccessor:
            ^(NSURL *newURL) {
                if (![[NSFileManager defaultManager] fileExistsAtPath:newURL.path]) {
                    success = YES;
                    return;
                }

                NSError *error_ = nil;
                if (localOnly && [[NSFileManager defaultManager] isUbiquitousItemAtURL:newURL]) {
                    if (![[NSFileManager defaultManager] evictUbiquitousItemAtURL:newURL error:&error_])
                        [self error:error_ cause:UbiquityStoreErrorCauseDeleteStore context:newURL.path];
                }
                else {
                    if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&error_])
                        [self error:error_ cause:UbiquityStoreErrorCauseDeleteStore context:newURL.path];
                }

                success = YES;
            }];

    if (error)
        [self error:error cause:UbiquityStoreErrorCauseDeleteStore context:directoryURL.path];

    return success;
}

- (void)deleteCloudContainerLocalOnly:(BOOL)localOnly {

    if (![self ensureQueued:^{ [self deleteCloudContainerLocalOnly:localOnly]; }])
        return;

    [self log:@"Will delete the cloud container %@.", localOnly? @"on this device": @"on this device and in the cloud"];
    @try {
        if (self.cloudEnabled)
            [self clearStore];

        // Delete the whole cloud container.
        [self removeItemAtURL:[self URLForCloudContainer] localOnly:localOnly];

        // Unset the storeUUID so a new one will be created.
        if (!localOnly) {
            [self createTentativeStoreUUID];
            NSUbiquitousKeyValueStore *cloud = [NSUbiquitousKeyValueStore defaultStore];
            [cloud synchronize];
            for (id key in [[cloud dictionaryRepresentation] allKeys])
                [cloud removeObjectForKey:key];
            // Don't synchronize.  Otherwise another devices might recreate the cloud store before we do.
        }
    }
    @finally {
        if (self.cloudEnabled)
            [self reloadStore];
    }
}

- (void)deleteCloudStoreLocalOnly:(BOOL)localOnly {

    [self deleteCloudStoreUUID:self.storeUUID_ThreadSafe localOnly:localOnly];

    if (self.cloudEnabled)
        [self reloadStore];
}

- (BOOL)deleteCloudStoreUUID:(NSString *)storeUUID localOnly:(BOOL)localOnly {

    if (![self ensureQueued:^{ [self deleteCloudStoreUUID:storeUUID localOnly:localOnly]; }])
        return NO;

    [self log:@"Will delete the cloud store (UUID:%@) %@.", storeUUID,
              localOnly? @"on this device": @"on this device and in the cloud"];
    NSString *activeStoreUUID = self.storeUUID_ThreadSafe;
    if (self.cloudEnabled && [activeStoreUUID isEqualToString:storeUUID])
        [self clearStore];

    // Clean up any cloud stores and transaction logs.
    NSURL *cloudStoreURL = [self URLForCloudStoreWithUUID:storeUUID];
    if ([NSPersistentStoreCoordinator respondsToSelector:@selector(removeUbiquitousContentAndPersistentStoreAtURL:options:error:)]) {
        // iOS 7+
        NSError *error = nil;
        NSDictionary *options = [self optionsForCloudStoreURL:cloudStoreURL];
        if (localOnly) {
            // Rebuild store from content.
            NSMutableDictionary *rebuildOptions = [options mutableCopy];
            rebuildOptions[NSPersistentStoreRebuildFromUbiquitousContentOption] = @YES;
            if (![[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model]
                    addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                           URL:cloudStoreURL options:rebuildOptions error:&error]) {
                [self error:error cause:UbiquityStoreErrorCauseDeleteStore context:cloudStoreURL];
                return NO;
            }
        }
        else {
            // Remove store content.
            if (![NSPersistentStoreCoordinator removeUbiquitousContentAndPersistentStoreAtURL:cloudStoreURL options:options
                                                                                        error:&error]) {
                [self error:error cause:UbiquityStoreErrorCauseDeleteStore context:cloudStoreURL];
                return NO;
            }
        }

        return YES;
    }
    else {
        // iOS 6
        if (![self removeItemAtURL:cloudStoreURL localOnly:localOnly])
            return NO;
        if (![self removeItemAtURL:[self URLForCloudContentForStoreURL:cloudStoreURL] localOnly:localOnly])
            return NO;

        // Create a tentative StoreUUID so a new cloud store will be created.
        if (!localOnly && [activeStoreUUID isEqualToString:storeUUID])
            [self createTentativeStoreUUID];

        return YES;
    }
}

- (void)deleteLocalStore {

    if (![self ensureQueued:^{ [self deleteLocalStore]; }])
        return;

    [self log:@"Will delete the local store."];
    @try {
        if (!self.cloudEnabled)
            [self clearStore];

        // Remove just the local store.
        NSError *coordinationError = nil;
        [self.storeFilePresenter.coordinator coordinateWritingItemAtURL:[self URLForLocalStore] options:NSFileCoordinatorWritingForDeleting
                                                                  error:&coordinationError byAccessor:^(NSURL *newURL) {
            NSError *error = nil;
            if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&error])
                [self error:error cause:UbiquityStoreErrorCauseDeleteStore context:[newURL path]];
        }];
        if (coordinationError)
            [self error:coordinationError cause:UbiquityStoreErrorCauseDeleteStore context:[[self URLForLocalStore] path]];
    }
    @finally {
        if (!self.cloudEnabled)
            [self reloadStore];
    }
}

- (void)revertMigration:(BOOL)cloudWasEnabled {

    [self log:@"Reverting migration attempt of %@, will %@ cloud.",
              [self.migrationStoreURL lastPathComponent], cloudWasEnabled? @"enable": @"disable"];

    self.migrationStoreURL = nil;

    if (cloudWasEnabled)
        [self tryLoadCloudStore];
    else
        [self tryLoadLocalStore];
}

- (BOOL)migrateCloudToLocal {

    if (![self ensureQueued:^{ [self migrateCloudToLocal]; }])
        return NO;

    [self log:@"Will overwrite the local store with the cloud store (using cloud logs)."];
    self.migrationStoreURL = [self URLForCloudStore];
    [self deleteLocalStore];

    BOOL cloudWasEnabled = self.cloudEnabled;
    if (![self tryLoadLocalStore]) {
        // Migration failed, revert to previous store.
        [self revertMigration:cloudWasEnabled];
        return NO;
    }

    return YES;
}

- (BOOL)migrateLocalToCloud {

    if (![self ensureQueued:^{ [self migrateLocalToCloud]; }])
        return NO;

    NSURL *localStoreURL = self.localStoreURL;
    if (![[NSFileManager defaultManager] fileExistsAtPath:localStoreURL.path]) {
        [self logError:@"Cannot migrate local to cloud: Local store doesn't exist."
                 cause:UbiquityStoreErrorCauseSeedStore context:localStoreURL.path];
        return NO;
    }

    [self log:@"Will overwrite the cloud store with the local store."];
    self.migrationStoreURL = localStoreURL;

    BOOL cloudWasEnabled = self.cloudEnabled;
    NSString *oldStoreUUID = self.storeUUID_ThreadSafe;
    [self createTentativeStoreUUID];
    if (![self tryLoadCloudStore]) {
        // Migration failed, revert to previous store.
        [self revertMigration:cloudWasEnabled];
        return NO;
    }

    NSString *newStoreUUID = self.storeUUID_ThreadSafe;
    if (newStoreUUID && oldStoreUUID && ![newStoreUUID isEqualToString:oldStoreUUID])
        [self deleteCloudStoreUUID:oldStoreUUID localOnly:NO];

    return YES;
}

- (BOOL)rebuildCloudContentFromCloudStoreOrLocalStore:(BOOL)allowRebuildFromLocalStore {

    if (![self ensureQueued:^{ [self rebuildCloudContentFromCloudStoreOrLocalStore:allowRebuildFromLocalStore]; }])
        return NO;

    BOOL cloudWasEnabled = self.cloudEnabled;
    NSURL *cloudStoreURL = [self URLForCloudStore];
    NSURL *cloudContentURL = [self URLForCloudContentForStoreURL:cloudStoreURL];
    if ([cloudContentURL isKindOfClass:[NSString class]])
        cloudContentURL = [[self URLForCloudContentDirectory] URLByAppendingPathComponent:self.storeUUID isDirectory:YES];

    if (![[NSFileManager defaultManager] fileExistsAtPath:cloudContentURL.path] &&
        ![[NSFileManager defaultManager] fileExistsAtPath:cloudStoreURL.path]) {
        // Cloud content not found.
        if (allowRebuildFromLocalStore) {
            [self log:@"Cannot rebuild cloud content: Cloud store doesn't exist.  Will rebuild from local store."];
            return [self migrateLocalToCloud];
        }
        else {
            [self log:@"Cannot rebuild cloud content: Cloud store doesn't exist.  Giving up."];
            [self reloadStore];
            return NO;
        }
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:cloudStoreURL.path]) {
        // iOS 7+
        [self log:@"Will rebuild cloud content from the cloud store (using cloud logs)."];
        self.migrationStoreURL = [self URLForCloudStore];
        [self createTentativeStoreUUID];
        if (![self tryLoadCloudStore]) {
            // Migration failed, revert to previous store.
            [self revertMigration:cloudWasEnabled];
            return NO;
        }

        return YES;
    }
    else {
        // iOS 6
        [self log:@"Will rebuild cloud content from the cloud store (ignoring cloud logs)."];
        [self clearStore];

        NSError *error = nil;
        self.migrationStoreURL = [[self URLForCloudStoreDirectory] URLByAppendingPathComponent:USMCloudStoreMigrationSource isDirectory:NO];
        [[NSFileManager defaultManager] removeItemAtURL:self.migrationStoreURL error:nil];
        if (![[NSFileManager defaultManager] copyItemAtURL:cloudStoreURL toURL:self.migrationStoreURL error:&error]) {
            [self error:error cause:UbiquityStoreErrorCauseSeedStore context:self.migrationStoreURL.path];
            // Migration failed, revert to previous store.
            [self revertMigration:cloudWasEnabled];
            return NO;
        }

        NSString *oldStoreUUID = self.storeUUID_ThreadSafe;
        if (![self tryLoadCloudStore]) {
            // Migration failed, revert to previous store.
            [self revertMigration:cloudWasEnabled];
            return NO;
        }

        NSString *newStoreUUID = self.storeUUID_ThreadSafe;
        if (newStoreUUID && oldStoreUUID && ![newStoreUUID isEqualToString:oldStoreUUID])
            [self deleteCloudStoreUUID:oldStoreUUID localOnly:NO];

        return YES;
    }
}

#pragma mark - Properties

- (BOOL)cloudEnabled {

    return [[NSUserDefaults standardUserDefaults] boolForKey:USMCloudEnabledKey];
}

- (void)setCloudEnabled:(BOOL)enabled {

    if (self.cloudEnabled == enabled)
            // No change, do nothing to avoid a needless store reload.
        return;

    if (![self ensureQueued:^{ [self setCloudEnabled:enabled]; }])
        return;

    BOOL cloudWasEnabled = self.cloudEnabled;
    if (cloudWasEnabled == enabled)
            // No change, do nothing to avoid a needless store reload.
        return;

    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:USMCloudEnabledKey];
    [self log:@"Switching cloud %@ -> %@", cloudWasEnabled? @"enabled": @"disabled", enabled? @"enabled": @"disabled"];

    [self reloadStore];
}

- (void)setEnabledStore:(USMEnabledStore)enabledStore {

    _enabledStore = enabledStore;

    switch (enabledStore) {
        case USMEnabledStoreNone:
            break;
        case USMEnabledStoreLocal:
            if (self.cloudEnabled)
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:USMCloudEnabledKey];
            break;
        case USMEnabledStoreCloud:
            if (!self.cloudEnabled)
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USMCloudEnabledKey];
            break;
    }
}

- (BOOL)setCloudEnabledAndOverwriteCloudWithLocalIfConfirmed:(void (^)(void (^setConfirmationAnswer)(BOOL answer)))confirmationBlock {

    if (self.cloudEnabled)
        return YES;

    if (![self ensureQueued:^{ [self setCloudEnabledAndOverwriteCloudWithLocalIfConfirmed:confirmationBlock]; }])
        return NO;

    // Copy local to cloud store?
    BOOL overwriteCloud = ![self cloudSafeForSeeding];
    if (overwriteCloud) {
        [self.persistentStoreCoordinator unlock];
        overwriteCloud = [self dispatchAndWaitFor:confirmationBlock];
        [self.persistentStoreCoordinator lock];
    }

    // Load cloud store (with or without migration).
    [self log:@"Will enable cloud, %@ cloud store.", overwriteCloud? @"overwriting": @"using existing"];
    if (overwriteCloud)
        return [self migrateLocalToCloud];

    self.cloudEnabled = YES;

    return YES;
}

- (BOOL)setCloudDisabledAndOverwriteLocalWithCloudIfConfirmed:(void (^)(void (^setConfirmationAnswer)(BOOL answer)))confirmationBlock {

    if (!self.cloudEnabled)
        return YES;

    if (![self ensureQueued:^{ [self setCloudDisabledAndOverwriteLocalWithCloudIfConfirmed:confirmationBlock]; }])
        return NO;

    // Copy cloud to local store?
    BOOL overwriteLocal = [[NSFileManager defaultManager] fileExistsAtPath:self.localStoreURL.path];
    if (overwriteLocal) {
        [self.persistentStoreCoordinator unlock];
        overwriteLocal = [self dispatchAndWaitFor:confirmationBlock];
        [self.persistentStoreCoordinator lock];
    }

    // Load local store (with or without migration).
    [self log:@"Will disable cloud, %@ local store.", overwriteLocal? @"overwriting": @"using existing"];
    if (overwriteLocal)
        return [self migrateCloudToLocal];

    if (![self tryLoadLocalStore]) {
        // Local store failed, can't recover from that automatically.  Revert to cloud store.
        [self tryLoadCloudStore];
        return NO;
    }
    return YES;
}

- (BOOL)dispatchAndWaitFor:(void (^)(void (^setConfirmationAnswer)(BOOL answer)))confirmationBlock {

    NSAssert(![[NSThread currentThread] isMainThread], @"Cannot dispatch a confirmation from the main thread.");

    __block BOOL confirmation = NO;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter( group );
    dispatch_async( dispatch_get_main_queue(), ^{
        confirmationBlock( ^(BOOL answer) {
            confirmation = answer;
            dispatch_group_leave( group );
        } );
    } );
    dispatch_group_wait( group, DISPATCH_TIME_FOREVER );

    return confirmation;
}

- (BOOL)cloudAvailable {

    return self.currentIdentityToken != nil;
}

/**
 * Contrary to -storeUUID, this method can return nil, in which case a cloud UUID has not yet been established.
 */
- (NSString *)storeUUID_ThreadSafe {

    if (self.tentativeStoreUUID)
            // A tentative StoreUUID is set; this means a new cloud store is being created.
        return self.tentativeStoreUUID;

    NSString *storeUUID = [[NSUserDefaults standardUserDefaults] stringForKey:[[self URLForCloudStoreUUID] path]];
    if (![storeUUID length])
        storeUUID = [self readStoreUUID];

    return storeUUID;
}

- (void)updateStoreUUIDAsynchronously:(BOOL)asynchronous {

    if (asynchronous)
        dispatch_async( dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0 ), ^{
            [self updateStoreUUIDAsynchronously:NO];
        } );
    else {
        NSString *storeUUID = [self readStoreUUID], *activeStoreUUID = [self activeCloudStoreUUID];
        if (activeStoreUUID && ![activeStoreUUID isEqualToString:storeUUID] && self.cloudEnabled)
            [self reloadStore];
    }
}

- (NSString *)readStoreUUID {

    NSURL *storeUUIDFile = [self URLForCloudStoreUUID];
    __block NSString *storeUUID = nil;

    // Store UUID is not coordinated, first get into a coordinator block.
    NSAssert(self.storeUUIDPresenter.coordinator, @"Missing StoreUUID coordinator");
    NSError *coordinationError = nil;
    [self.storeUUIDPresenter.coordinator coordinateReadingItemAtURL:storeUUIDFile options:0
                                                              error:&coordinationError byAccessor:^(NSURL *newURL) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:[newURL path]])
            return;

        NSError *readError = nil;
        storeUUID = [[NSString alloc] initWithContentsOfURL:storeUUIDFile encoding:NSASCIIStringEncoding error:&readError];
        if (readError)
            [self error:readError cause:UbiquityStoreErrorCauseOpenActiveStore context:[storeUUIDFile path]];
    }];
    if (coordinationError)
        [self error:coordinationError cause:UbiquityStoreErrorCauseOpenActiveStore context:[storeUUIDFile path]];

    [[NSUserDefaults standardUserDefaults] setObject:storeUUID forKey:[storeUUIDFile path]];
    return storeUUID;
}

- (NSString *)storeUUIDForLog {

    @try {
        return [self storeUUID_ThreadSafe];
    }
    @catch (NSException *exception) {
        return [NSString stringWithFormat:@"<Error:%@>", [exception reason]];
    }
}

- (NSString *)storeUUID {

    [self assertQueued];

    NSString *storeUUID = [self storeUUID_ThreadSafe];

    if (!storeUUID)
            // No StoreUUID is set; this means there is no cloud store yet.  Set a new tentative StoreUUID to create one.
        return [self createTentativeStoreUUID];

    return storeUUID;
}

- (void)setStoreUUID:(NSString *)newStoreUUID {

    [self setStoreUUID:newStoreUUID withCloudVersion:[self desiredCloudVersion]];
}

- (void)setStoreUUID:(NSString *)newStoreUUID withCloudVersion:(int)cloudVersion {

    if (![self ensureQueued:^{ [self setStoreUUID:newStoreUUID withCloudVersion:cloudVersion]; }])
        return;

    // Tell all other devices about our new cloud store's UUID.
    __block BOOL success = NO;
    NSURL *storeUUIDFile = [self URLForCloudStoreUUIDForVersion:cloudVersion];
    [self log:@"Writing new StoreUUID:%@ to %@ (v%d).", newStoreUUID, [storeUUIDFile lastPathComponent], cloudVersion];
    [self.storeUUIDPresenter.coordinator coordinateWritingItemAtURL:storeUUIDFile options:NSFileCoordinatorWritingForMerging
                                                              error:nil byAccessor:^(NSURL *newURL) {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:[newURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES
                                                       attributes:nil error:&error])
            [self error:error cause:UbiquityStoreErrorCauseConfirmActiveStore context:[[newURL URLByDeletingLastPathComponent] path]];
        if (!(success = [newStoreUUID writeToURL:newURL atomically:NO encoding:NSASCIIStringEncoding error:&error]))
            [self error:error cause:UbiquityStoreErrorCauseConfirmActiveStore context:[newURL path]];
    }];
    if (!success)
        return;

    // Remove all store UUIDs of supported cloud versions higher than the one we are setting.
    for (int highCloudVersion = [self desiredCloudVersion]; highCloudVersion > cloudVersion; --highCloudVersion) {
        NSURL *obsoleteStoreUUIDFile = [self URLForCloudStoreUUIDForVersion:highCloudVersion];
        if (![obsoleteStoreUUIDFile isEqual:storeUUIDFile]) {
            [self log:@"Removing %@ (v%d) to force version down to %d.", //
                      [obsoleteStoreUUIDFile lastPathComponent], highCloudVersion, cloudVersion];
            [self.storeUUIDPresenter.coordinator coordinateWritingItemAtURL:obsoleteStoreUUIDFile
                                                                    options:NSFileCoordinatorWritingForDeleting error:nil byAccessor:
                    ^(NSURL *newURL) {
                        [[NSFileManager defaultManager] removeItemAtURL:newURL error:nil];
                    }];
        }
    }

    // A new cloud store went live: clear any old cloud corruption.
    [self.corruptedUUIDPresenter.coordinator coordinateWritingItemAtURL:[self URLForCloudCorruptedUUIDForVersion:cloudVersion]
                                                                options:NSFileCoordinatorWritingForDeleting error:nil byAccessor:
            ^(NSURL *newURL) {
                [[NSFileManager defaultManager] removeItemAtURL:newURL error:nil];
            }];
}

/**
 * When a tentative StoreUUID is set, this operation confirms it and writes it as the new StoreUUID to the iCloud KVS.
 */
- (void)confirmTentativeStoreUUID {

    [self assertQueued];

    if (!self.tentativeStoreUUID)
        return;

    [self log:@"Confirming tentative StoreUUID: %@", self.tentativeStoreUUID];
    [self setStoreUUID:self.tentativeStoreUUID];
    [self unsetTentativeStoreUUID];
}

/**
 * Creates a new a tentative StoreUUID.  This will result in a new cloud store being created.
 */
- (NSString *)createTentativeStoreUUID {

    [self assertQueued];

    return self.tentativeStoreUUID = [[NSUUID UUID] UUIDString];
}

/**
 * Creates a new a tentative StoreUUID.  This will result in a new cloud store being created.
 */
- (void)unsetTentativeStoreUUID {

    [self assertQueued];

    self.tentativeStoreUUID = nil;
}

#pragma mark - Notifications

- (void)storeUUIDDidChange {

    if (![self ensureQueued:^{ [self storeUUIDDidChange]; }])
        return;

    // Read the new store UUID and check whether it's actually changed.
    [self updateStoreUUIDAsynchronously:NO];
    if ([self.activeCloudStoreUUID isEqualToString:self.storeUUID])
        return;

    // The UUID of the active store changed.  We need to switch to the newly activated store.
    [self log:@"StoreUUID changed %@ -> %@", self.activeCloudStoreUUID, [self storeUUIDForLog]];
    [self unsetTentativeStoreUUID];
    [self cloudStoreChanged:nil];
}

// Cloud content corruption was detected or cleared.
- (void)corruptedUUIDDidChange {

    if (!self.cloudEnabled)
        return;

    if (![self ensureQueued:^{ [self corruptedUUIDDidChange]; }])
        return;

    if (![self handleCloudContentCorruption] && !self.activeCloudStoreUUID)
            // Corruption was removed and our cloud store is not yet loaded.  Try loading the store again.
        [self reloadStore];
}

- (void)accommodateLocalDeletionWithCompletionHandler:(void (^)(NSError *))completionHandler {

    // Clean up.
    [self       enqueue:^{
        if (!self.cloudEnabled)
            [self clearStore];
    } waitUntilFinished:YES];

    // Accommodate deletion.
    completionHandler( nil );

    // Recover.
    if (!self.cloudEnabled)
        [self reloadStore];
}

- (void)accommodateCloudDeletionWithCompletionHandler:(void (^)(NSError *))completionHandler {

    [self log:@"Handling cloud deletion."];

    // Clean up.
    [self       enqueue:^{
        if (self.cloudEnabled)
            [self clearStore];

        NSError *error = nil;
        NSURL *cloudStoreURL = [self URLForCloudStore];
        if ([[NSFileManager defaultManager] fileExistsAtPath:[cloudStoreURL path]] &&
            ![[NSFileManager defaultManager] removeItemAtURL:cloudStoreURL error:&error])
            [self error:error cause:UbiquityStoreErrorCauseDeleteStore context:[cloudStoreURL path]];
        [self removeItemAtURL:cloudStoreURL localOnly:NO];
        [self.storeUUIDPresenter.coordinator coordinateWritingItemAtURL:[self URLForCloudStoreUUID]
                                                                options:NSFileCoordinatorWritingForDeleting
                                                                  error:nil byAccessor:^(NSURL *newURL) {
            NSError *error_ = nil;
            if ([[NSFileManager defaultManager] fileExistsAtPath:[newURL path]] &&
                ![[NSFileManager defaultManager] removeItemAtURL:newURL error:&error_])
                [self error:error_ cause:UbiquityStoreErrorCauseDeleteStore context:[newURL path]];
        }];
        [self.corruptedUUIDPresenter.coordinator coordinateWritingItemAtURL:[self URLForCloudCorruptedUUID]
                                                                    options:NSFileCoordinatorWritingForDeleting
                                                                      error:nil byAccessor:^(NSURL *newURL) {
            NSError *error_ = nil;
            if ([[NSFileManager defaultManager] fileExistsAtPath:[newURL path]] &&
                ![[NSFileManager defaultManager] removeItemAtURL:newURL error:&error_])
                [self error:error_ cause:UbiquityStoreErrorCauseDeleteStore context:[newURL path]];
        }];
    } waitUntilFinished:YES];

    // Accommodate deletion.
    completionHandler( nil );

    // Recover.
    if ([self.delegate respondsToSelector:@selector(ubiquityStoreManagerHandleCloudContentDeletion:)])
        [self.delegate ubiquityStoreManagerHandleCloudContentDeletion:self];
    else if (self.cloudEnabled) {
        [self log:@"Recovering from cloud deletion.  Falling back to local store."];
        self.cloudEnabled = NO;
    }
}

- (void)userDefaultsDidChange:(NSNotification *)note {

    [self enqueue:^{
        switch (self.enabledStore) {
            case USMEnabledStoreNone:
                [self reloadStore];
                break;
            case USMEnabledStoreLocal:
                if (self.cloudEnabled)
                    [self reloadStore];
                break;
            case USMEnabledStoreCloud:
                if (!self.cloudEnabled)
                    [self reloadStore];
                break;
        }
    }];
}

- (void)applicationDidBecomeActive:(NSNotification *)note {

    // Check for iCloud identity changes (ie. user logs into another iCloud account).
    if ([[NSFileManager defaultManager] respondsToSelector:@selector(ubiquityIdentityToken)] &&
        ![self.currentIdentityToken isEqual:[[NSFileManager defaultManager] ubiquityIdentityToken]])
        [self cloudStoreChanged:nil];
}

/**
 * Triggered when:
 * 1. An NSError is created describing a transaction log import failure (UbiquityManagedStoreDidDetectCorruptionNotification).
 */
- (void)ubiquityStoreManagerDidDetectCorruption:(NSNotification *)note {

    NSMutableArray *storeURLs = [note.object valueForKey:USMStoreURLsErrorKey];
    if (storeURLs && (id)storeURLs != [NSNull null]) {
        BOOL isForActiveStore = NO;
        NSString *activeStoreUUID = self.storeUUID_ThreadSafe;
        if (!activeStoreUUID)
                // Import failure was not for our store: We don't even have a StoreUUID yet.
            return;
        for (NSURL *storeURL in storeURLs)
            if ((isForActiveStore = ([[storeURL absoluteString] rangeOfString:activeStoreUUID].location != NSNotFound)))
                break;
        if (!isForActiveStore)
                // Import failure was not for our store: Its store URL doesn't contain our StoreUUID.
            return;
    }

    [self logError:@"Detected iCloud transaction log import failure."
             cause:UbiquityStoreErrorCauseCorruptActiveStore context:note.object];
    [self markCloudStoreCorrupted];
}

- (void)markCloudStoreCorrupted {

    self.localCloudStoreCorruptedUUID = self.storeUUID_ThreadSafe;
    if (!self.localCloudStoreCorruptedUUID) {
        NSAssert(self.localCloudStoreCorruptedUUID, @"Corruption detected on a tentative store?");
        return;
    }

    NSURL *corruptedUUIDFile = [self URLForCloudCorruptedUUID];
    [self.corruptedUUIDPresenter.coordinator coordinateWritingItemAtURL:corruptedUUIDFile options:NSFileCoordinatorWritingForMerging
                                                                  error:nil byAccessor:^(NSURL *newURL) {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:[newURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES
                                                       attributes:nil error:&error])
            [self error:error cause:UbiquityStoreErrorCauseCorruptActiveStore context:[[newURL URLByDeletingLastPathComponent] path]];
        if (![self.localCloudStoreCorruptedUUID writeToURL:newURL atomically:NO encoding:NSASCIIStringEncoding error:&error])
            [self error:error cause:UbiquityStoreErrorCauseCorruptActiveStore context:[newURL path]];
    }];

    [self enqueue:^{ [self handleCloudContentCorruption]; }];
}

- (BOOL)handleCloudContentCorruption {

    [self assertQueued];

    if (!self.cloudEnabled)
            // Cloud not enabled: cannot handle corruption.
        return NO;

    NSError *error = nil;
    __block NSError *error_ = nil;
    __block NSString *corruptedUUID = nil;
    NSURL *corruptedUUIDFile = [self URLForCloudCorruptedUUID];
    [self.corruptedUUIDPresenter.coordinator coordinateReadingItemAtURL:corruptedUUIDFile options:0 error:&error byAccessor:
            ^(NSURL *newURL) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:[newURL path]])
                    corruptedUUID = [[NSString alloc] initWithContentsOfURL:newURL encoding:NSASCIIStringEncoding error:&error_];
            }];

    if (error)
        [self error:error cause:UbiquityStoreErrorCauseCorruptActiveStore context:[corruptedUUIDFile path]];
    if (error_)
        [self error:error_ cause:UbiquityStoreErrorCauseCorruptActiveStore context:[corruptedUUIDFile path]];

    if (![corruptedUUID isEqualToString:self.storeUUID])
            // Active store is not corrupt.
        return NO;

    // Unload the cloud store if it's loaded and corrupt.
    BOOL localStoreCorrupted = [self.localCloudStoreCorruptedUUID isEqualToString:self.storeUUID];
    if (localStoreCorrupted) {
        [self clearStore];
    }

    // Notify the delegate of corruption.
    [self log:@"Cloud content corruption detected (device store is %@).", localStoreCorrupted? @"corrupt": @"healthy"];
    BOOL defaultStrategy = YES;
    if ([self.delegate respondsToSelector:@selector(ubiquityStoreManager:handleCloudContentCorruptionWithHealthyStore:)])
        defaultStrategy = ![self.delegate ubiquityStoreManager:self handleCloudContentCorruptionWithHealthyStore:!localStoreCorrupted];

    // Handle corruption.
    if (!defaultStrategy)
        [self log:@"Application handled cloud corruption."];

    else {
        if (localStoreCorrupted)
                // Store is corrupt: no store available.
            [self log:@"Handling cloud corruption with default strategy: Wait for a remote rebuild."];
        else {
            // Store is healthy: rebuild cloud store.
            [self log:@"Handling cloud corruption with default strategy: Rebuilding cloud content."];
            [self rebuildCloudContentFromCloudStoreOrLocalStore:NO];
        }
    }

    return YES;
}

/**
 * Triggered when:
 * 1. Ubiquity identity changed (NSUbiquityIdentityDidChangeNotification).
 * 2. Store file was deleted (eg. iCloud container deleted in settings).
 * 3. StoreUUID changed (eg. switched to a new cloud store on another device).
 */
- (void)cloudStoreChanged:(NSNotification *)note {

    // Update the identity token in case it changed.
    id newIdentityToken = [[NSFileManager defaultManager] ubiquityIdentityToken];
    if (![self.currentIdentityToken isEqual:newIdentityToken] || (self.currentIdentityToken == nil && newIdentityToken)) {
        [self log:@"Identity token changed: %@ -> %@", self.currentIdentityToken, newIdentityToken];
        self.currentIdentityToken = newIdentityToken;
    }

    // If the cloud store was active, reload it.
    if (self.cloudEnabled)
        [self reloadStore];
}

- (void)didImportChanges:(NSNotification *)note {

    NSManagedObjectContext *moc = nil;
    if ([self.delegate respondsToSelector:@selector(ubiquityStoreManager:managedObjectContextForUbiquityChanges:)])
        moc = [self.delegate ubiquityStoreManager:self managedObjectContextForUbiquityChanges:note];

    if (moc) {
        [self log:@"Importing ubiquity changes into application's MOC.  Changes:\n%@", note.userInfo];
        [moc performBlockAndWait:^{
            [moc mergeChangesFromContextDidSaveNotification:note];

            NSError *error = nil;
            if ([moc hasChanges] && ![moc save:&error]) {
                [self error:error cause:UbiquityStoreErrorCauseImportChanges context:note];
                [self reloadStore];
                return;
            }
        }];
    }
    else
        [self log:@"Application did not specify an import MOC, not importing ubiquity changes:\n%@", note.userInfo];

    dispatch_async( dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:USMStoreDidImportChangesNotification
                                                            object:self userInfo:[note userInfo]];
    } );
}

- (void)storesWillChange:(NSNotification *)note {

    [self fireBeginLoadingLogReason:@"Stores will change"];
}

- (void)storesDidChange:(NSNotification *)note {

    if ([((NSPersistentStoreCoordinator *)note.object).persistentStores count])
        [self fireFinishedLoadingLogReason:@"Stores changed" cause:UbiquityStoreErrorCauseNoError context:note];
}

@end

// The presenters used to monitor files.

@implementation USMLocalStoreFilePresenter

- (id)initWithUSM:(UbiquityStoreManager *)manager {

    return [self initWithURL:[manager URLForLocalStore] delegate:manager];
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *))completionHandler {

    [self.delegate accommodateLocalDeletionWithCompletionHandler:completionHandler];
}

@end

@implementation USMStoreUUIDPresenter

- (id)initWithUSM:(UbiquityStoreManager *)manager {

    return [self initWithURL:[manager URLForCloudStoreUUID] delegate:manager];
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *))completionHandler {

    [self.delegate accommodateCloudDeletionWithCompletionHandler:completionHandler];
}

- (void)presentedItemDidChange {

    [self handleConflicts];
    [self.delegate storeUUIDDidChange];
}

- (void)presentedItemDidGainVersion:(NSFileVersion *)version {

    [self handleConflicts];
}

- (void)presentedItemDidLoseVersion:(NSFileVersion *)version {

    [self handleConflicts];
}

- (void)presentedItemDidResolveConflictVersion:(NSFileVersion *)version {

    [self handleConflicts];
}

- (NSFileVersion *)resolutionVersionForConflictVersions:(NSArray *)conflictVersions {

    // First (earliest) version wins.
    return [[conflictVersions sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [[obj1 modificationDate] compare:[obj2 modificationDate]];
    }] firstObject];
}

@end

@implementation USMCorruptedUUIDPresenter

- (id)initWithUSM:(UbiquityStoreManager *)manager {

    return [self initWithURL:[manager URLForCloudCorruptedUUID] delegate:manager];
}

- (void)presentedItemDidChange {

    [self.delegate corruptedUUIDDidChange];
}

- (void)presentedItemDidGainVersion:(NSFileVersion *)version {

    [self handleConflicts];
}

- (void)presentedItemDidLoseVersion:(NSFileVersion *)version {

    [self handleConflicts];
}

- (void)presentedItemDidResolveConflictVersion:(NSFileVersion *)version {

    [self handleConflicts];
}

- (NSFileVersion *)resolutionVersionForConflictVersions:(NSArray *)conflictVersions {

    // Last (latest) version wins.
    return [[conflictVersions sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [[obj1 modificationDate] compare:[obj2 modificationDate]];
    }] lastObject];
}

@end

// Monitoring implementation.

@implementation USMFilePresenter {
    NSURL *_presentedItemURL;
    NSOperationQueue *_presentedItemOperationQueue;
}

- (id)initWithURL:(NSURL *)presentedItemURL delegate:(UbiquityStoreManager *)delegate {

    if (!(self = [super init]))
        return nil;

    _delegate = delegate;
    _presentedItemURL = presentedItemURL;
    _presentedItemOperationQueue = [NSOperationQueue new];
    _presentedItemOperationQueue.name = [NSString stringWithFormat:@"%@PresenterQueue", NSStringFromClass( [self class] )];
    _coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];

    return self;
}

- (void)start {

    [NSFileCoordinator addFilePresenter:self];
}

- (void)stop {

    [NSFileCoordinator removeFilePresenter:self];
}

- (NSURL *)presentedItemURL {

    return _presentedItemURL;
}

- (NSOperationQueue *)presentedItemOperationQueue {

    return _presentedItemOperationQueue;
}

@end

@implementation USMFileContentPresenter

- (id)initWithURL:(NSURL *)presentedItemURL delegate:(UbiquityStoreManager *)delegate {

    if (!(self = [super initWithURL:presentedItemURL delegate:delegate]))
        return nil;

    if (presentedItemURL) {
        _query = [NSMetadataQuery new];
        _query.searchScopes = @[ NSMetadataQueryUbiquitousDataScope ];
        _query.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSMetadataItemFSNameKey, [presentedItemURL lastPathComponent]];
    }

    return self;
}

- (void)start {

    [self handleConflicts];
    [super start];

    [[NSNotificationCenter defaultCenter] addObserverForName:NSMetadataQueryDidUpdateNotification object:_query queue:nil usingBlock:
            ^(NSNotification *note) {
                [self.query disableUpdates];
                for (NSUInteger r = 0; r < [self.query resultCount]; ++r)
                    if ([[self.query valueOfAttribute:NSMetadataItemURLKey forResultAtIndex:r] isEqual:[self presentedItemURL]])
                        [self presentedItemDidChange];
                [self.query enableUpdates];
            }];

    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        if (![self.query startQuery])
            [self.delegate log:@"Couldn't start monitor query for %@, already running?", [self.presentedItemURL lastPathComponent]];
    }];
}

- (void)stop {

    [super stop];

    [self.query stopQuery];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleConflicts {

    NSMutableArray *conflictVersions = [[NSFileVersion unresolvedConflictVersionsOfItemAtURL:self.presentedItemURL] mutableCopy];
    if (![conflictVersions count]) {
        // No conflicts.
        return;
    }

    // Resolve conflict by using the oldest version.
    [conflictVersions addObject:[NSFileVersion currentVersionOfItemAtURL:self.presentedItemURL]];
    NSFileVersion *resolutionVersion = [self resolutionVersionForConflictVersions:conflictVersions];
    if (!resolutionVersion) {
        // Not resolving conflict.
        return;
    }

    NSError *error = nil;
    [resolutionVersion replaceItemAtURL:self.presentedItemURL options:0 error:&error];
    if (error)
        [self.delegate error:error cause:UbiquityStoreErrorCauseOpenActiveStore context:[self.presentedItemURL path]];
    else
            // Mark all conflicts as resolved.
        [conflictVersions enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [obj setResolved:YES];
        }];
}

- (NSFileVersion *)resolutionVersionForConflictVersions:(NSArray *)conflictVersions {

    return nil;
}

@end
