[![Gittip](http://img.shields.io/gittip/lhunath.png)](https://www.gittip.com/lhunath/)
[![Travis CI](http://img.shields.io/travis-ci/lhunath/UbiquityStoreManager.png)](https://travis-ci.org/lhunath/UbiquityStoreManager)

## I am no longer maintaining this project.  I'm relying on some of the users of this project to step up and keep this project alive under iOS 8+ if there is continued interest in it.

# About

`UbiquityStoreManager` is a controller that implements **iCloud integration with Core Data** for you, and takes away all the hardship.

When Apple first released the amazing Core Data integration with iCloud, it was a very simple API portrayed as trivial to integrate.  Unfortunately, the contrary was certainly true.  Apple has since made significant strides forward, especially in iOS 7.  Nonetheless, there are still many caveats, side-effects and undocumented behaviors that need to be handled to get a reliable implementation.

`UbiquityStoreManager` also provides an immensely useful set of migration utilities for those interested in more control over their user's data than the "default" choices Apple has made for you.

Unfortunately, your users on iOS 6 still suffer a bunch of serious bugs in iCloud, which can sometimes lead to cloud stores that become desynced or even irreparably broken.  `UbiquityStoreManager` handles these situations as best as possible.

The API has been kept as simple as possible while giving you, the application developer, the hooks you need to get the exact behavior you want.  Wherever possible, `UbiquityStoreManager` implements safe and sane default behavior to handle exceptional situations but lets you make different choices if desired.  The cases are well documented in the API documentation, as well as your ability to plug into the manager and implement your own custom behavior.

# Disclaimer

I provide `UbiquityStoreManager` and its example application to you for free and do not take any responsability for what it may do in your application.

Creating and maintaining `UbiquityStoreManager` takes a huge amount of work.  This code is provided to you free of cost, in the hopes that it will be useful to you in its current form or another.  If this solution is useful to you, send me a thank-you note, or consider donating to the cause.

# Note on iOS 7

Apple has significantly improved their Core Data integration with iCloud in iOS 7.  Applications that wish to benefit from these improvements need to become iOS 7 only.  `UbiquityStoreManager` has been updated with support for iOS 7.  Devices running iOS 7+ (or OS X 10.9+) will initially migrate their old data over to a new iOS 7+ only store, and will hence forth sync only amoung other iOS 7+/OS X 10.9+ devices.  iOS 6/OS X 10.8 devices will similarly only sync amoung each other.  `USM` behaves this way to isolate the buggy old implementation of iCloud from the improved new implementation.

With iOS 7's improvements, why should you still use `USM`?

  * iOS 6 support: Apple now recommends all iCloud using apps be iOS 7-only.  You may not necessarily agree.
  * Local Store: Apple has, for simplicity, decided that when the user enables iCloud on their phone in Settings, all apps that support iCloud will switch over to that iCloud account.  More importantly, when a user wants to stop using iCloud, all his data is gone.  `USM` gives you an application toggle that lets users switch between a ubiquitous store or a non-ubiquitous store.
  * Migration Utilities: `USM` comes with a vast amount of utilities to migrate between stores.  Its API is simple and solves the problems your app will face: If your user wants to stop using iCloud, toggling iCloud off can, with one call, cause `USM` to switch to the local store and - if the user chooses - bring his cloud data with him to the local store.
  * iCloud is still not trivial: There are still a lot of things you need to do right.  Just look at `USM`'s vast code-base.  If you use `USM`, all you do is `-init` an object, set a delegate and wait for us to give you a fully initialized `NSPersistentStoreCoordinator`.  Let us take care of the work so you can focus on your data model and your app.

# Getting Started

To get started with `UbiquityStoreManager`, all you need to do is instantiate it:

    [[UbiquityStoreManager alloc] initStoreNamed:nil
                          withManagedObjectModel:nil
                                   localStoreURL:nil
                             containerIdentifier:nil
                              storeConfiguration:nil
                                    storeOptions:nil
                                        delegate:self];

The `nil` parameters can all be used to customize `UbiquityStoreManager`'s behavior.  For instance, if you already have a local store, you can pass its URL as the localStoreURL.

And then wait in your delegate for the manager to bring up your persistence layer:

    - (void)ubiquityStoreManager:(UbiquityStoreManager *)manager willLoadStoreIsCloud:(BOOL)isCloudStore {
    
        self.moc = nil;
    }
    
    - (void)ubiquityStoreManager:(UbiquityStoreManager *)manager didLoadStoreForCoordinator:(NSPersistentStoreCoordinator *)coordinator isCloud:(BOOL)isCloudStore {
    
        self.moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [moc setPersistentStoreCoordinator:coordinator];
        [moc setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    }

That’s it!  The manager set up your `NSPersistentStoreCoordinator`, you created an `NSManagedObjectContext`, you’re ready to go.

Just keep in mind, as aparent from the code above, that your `moc` can be `nil`.  This happens when the manager is not (yet) ready with loading the store.  It can also occur after the store has been loaded (eg. cloud is turned on/off or the store needs to be re-loaded).  So just make sure that your application deals gracefully with your main `moc` being unavailable.  You can also observe the `UbiquityManagedStoreDidChangeNotification` which will be posted each time the availability of persistence stores changes (and always after your delegate is informed).

Initially, the manager will be using a local store.  To enable iCloud (you may want to do this after the user toggles iCloud on), just flip the switch:

    manager.cloudEnabled = YES;

If you prefer, you can use the `-setCloudEnabledAndOverwriteCloudWithLocalIfConfirmed:` and `-setCloudDisabledAndOverwriteLocalWithCloudIfConfirmed:` methods instead, which allow you to ask the user (via the confirmation block) if he wants to bring his current data with him when moving to the new (local or cloud) store.  The confirmation block will only be triggered if necessary (the new store already exists).  Data is migrated by default if the new store doesn't exist yet.

# Surely I’m not done yet!

That depends on how much you want to get involved with what `UbiquityStoreManager` does internally to handle your store, and how much feedback you want to give your user with regards to what’s going on.

For instance, you may want to implement visible feedback for while persistence is unavailable (eg. show an overlay with a loading spinner).  You’d bring this spinner up in `ubiquityStoreManager:willLoadStoreIsCloud:` and dismiss it in `ubiquityStoreManager:didLoadStoreForCoordinator:isCloud:`.

It’s probably also a good idea to update your main `moc` whenever ubiquity changes are getting imported into your store from other devices.  To do this, simply provide the manager with your `moc` by returning it from `-ubiquityStoreManager:managedObjectContextForUbiquityChanges:` and optionally register an observer for `UbiquityManagedStoreDidImportChangesNotification`.

# What if things go wrong?

And don’t be fooled: Things do go wrong.  There are still some kinks, especially for your iOS 6/OS X 10.8 users.  Some of these can cause the cloud store to become irreparably desynced.

`UbiquityStoreManager` does its best to deal with the issues, mostly automatically.  Because the manager takes great care to ensure no data-loss occurs there are some rare cases where the store cannot be automatically salvaged.  It is therefore important that you implement some failure handling, at least in the way recommended by the manager.

While it theoretically shouldn’t happen, sometimes ubiquity changes designed to sync your cloud store with the store on other devices can be incompatible with your cloud store.  Usually, this happens due to an Apple iCloud bug in dealing with relationships that are simultaneously edited from different devices, causing conflicts that can’t be handled.  Interestingly, the errors happen deep within Apple’s iCloud implementation and Apple doesn’t bother notifying you through any public API.  `UbiquityStoreManager` implements a way of detecting these issues when they occur and deals with them as best it can.  

Whenever problems occur with importing transaction logs (ubiquity changes), your application can be notified and optionally intervene by implementing `ubiquityStoreManager:handleCloudContentCorruptionWithHealthyStore:` in your delegate.  If you just want to be informed and let the manager handle the situation, return `NO`.  If you want to handle the situation in a different way than what the manager does by default, return `YES` after dealing with the problem yourself.

Essentially, the manager deals with import exceptions by unloading the store on the device where ubiquity changes conflict with the store and notifying all other devices that the store has entered a **”corrupted”** state.  Other devices may not experience any errors (they may be the authors of the corrupting logs, or they may not experience conflicts between their store and the logs).  When any of these **healthy** devices receive word of the store corruption, they will initiate a store rebuild causing a brand new cloud store to be created populated by the old cloud store’s entities.  At this point, all devices will switch over to the new cloud store and the corruption state will be cleared.

You are recommended to implement `ubiquityStoreManager:handleCloudContentCorruptionWithHealthyStore:` by returning `NO` but informing the user of what is going on.  Here’s an example implementation that displays an alert for the user if his device needs to wait for another device to fix the corruption:

    - (BOOL)ubiquityStoreManager:(UbiquityStoreManager *)manager
            handleCloudContentCorruptionWithHealthyStore:(BOOL)storeHealthy {
    
        if (![self.cloudAlert isVisible] && manager.cloudEnabled && !storeHealthy)
            dispatch_async( dispatch_get_main_queue(), ^{
                self.cloudAlert = [[UIAlertView alloc]
                        initWithTitle:@"iCloud Sync Problem"
                              message:@"\n\n\n\n"
                    @"Waiting for another device to auto‑correct the problem..."
                             delegate:self
                    cancelButtonTitle:nil otherButtonTitles:@"Fix Now", nil];
                UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc]
                        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
                activityIndicator.center = CGPointMake( 142, 90 );
                [activityIndicator startAnimating];
                [self.cloudAlert addSubview:activityIndicator];
                [self.cloudAlert show];
            } );
    
        return NO;
    }

The above code gives the user the option of hitting the `Fix Now` button, which would invoke `[manager rebuildCloudContentFromCloudStoreOrLocalStore:YES]`.  Essentially, it initiates the cloud store rebuild locally.  More about this later.

Your app can now deal with Apple’s iCloud bugs, congratulations!

Unless you want to get into the deep water, ***you’re done now***.  What follows is for brave souls or those seeking for maximum control.

# What else have you got?

`UbiquityStoreManager` tries its best to keep interested delegates informed of what’s going on, and even gives it the ability to intervene in non-standard ways.

If you use a logger, you can plug it in by implementing `ubiquityStoreManager:log:`.  This method is called whenever the manager has something to say about what it’s doing.  We’re pretty verbose, so you may even want to implement this just to shut the manager up in production.

If you’re interested in getting the full details about any error conditions, implement `ubiquityStoreManager:didEncounterError:cause:context:` and you shall receive.

If the cloud content gets deleted, the manager unloads the persistence stores.  This may happen, for instance, if the user has gone into `Settings` and deleted the iCloud data for your app, possibly in an attempt to make space on his iCloud account.  By default, this will leave your app without any persistence until the user restarts the app.  If iCloud is still enabled in the app, a new store will be created for him.  You could handle this a little differently, depending on what you think is right: You may want to just display a message to the user asking him whether he wants iCloud disabled or re-enabled.  Or you may want to just disable iCloud and switch to the local store.  You would handle this from `ubiquityStoreManagerHandleCloudContentDeletion:`.

If you read the previous section carefully, you should understand that problems may occur during the importing of ubiquitous changes made by other devices.  The default way of handling the situation can usually automatically resolve the situation but may take some time to completely come about and may involve user interaction.  You may choose to handle the situation differently by implementing `ubiquityStoreManager:handleCloudContentCorruptionWithHealthyStore:` and returning `YES` after dealing with the corruption yourself.  The manager provides the following methods for you, which you can use for some low-level maintenance of the stores:

  * `-reloadStore` — Just clear and re-open or retry opening the active store.
  * `-setCloudEnabledAndOverwriteCloudWithLocalIfConfirmed:` — Enable iCloud if not yet enabled.  If the user already has an iCloud store, your confirmation block is invoked allowing you to ask the user if he wants to either switch to the existing cloud data or overwrite it with his local data.
  * `-setCloudDisableAndOverwriteLocalWithCloudIfConfirmed:` — Disable iCloud if enabled.  If the user already has a local store, your confirmation block is invoked allowing you to ask the user if he wants to either switch to the existing local data or overwrite it with his cloud data.
  * `-migrateCloudToLocal` — Manually overwrite the user's local data with the data in his iCloud store.
  * `-migrateLocalToCloud` — Manually overwrite the user's cloud data with the data in the local store.
  * `-deleteCloudContainerLocalOnly:` — All iCloud data for your application will be deleted.  That’s ***not just your Core Data store***!
  * `-deleteCloudStoreLocalOnly:` — Your Core Data cloud store will be deleted.
  * `-deleteLocalStore` — This will delete your local store (ie. the store that’s active when `manager.cloudEnabled` is `NO`).
  * `-rebuildCloudContentFromCloudStoreOrLocalStore:` — This is where the cloud store rebuild magic happens.  Invoke this method to create a new cloud store and copy your current cloud data into it.

Many of these methods take a `localOnly` parameter.  Set it to `YES` if you don’t want to affect the user’s iCloud data.  The operation will happen on the local device only.  For instance, if you run `[manager deleteCloudStoreLocalOnly:YES]`, the cloud store on the device will be deleted.  If `cloudEnabled` is `YES`, the manager will subsequently re-open the cloud store which will cause a re-download of all iCloud’s transaction logs for the store.  These transaction logs will then get replayed locally causing your local store to be repopulated from what’s in iCloud.

`USM` will always try to be as non-destructive as possible.  If a migration or operation fails, it will revert the user back to the state he was in before.

## `parseLogs`

The [`parseLogs`](parseLogs) bash script allows you to analyse the output of Apple's verbose ubiquity log output and give you some feedback on it.  It is in a very young stage, but is aimed at aiding with debugging any iCloud related sync issues.

![parseLogs screenshot](http://stuff.lhunath.com/shots/shot.1368550601.png)

To use the script, just run it (while in the directory of the script or after copying its `bashlib` dependency into `PATH`), feeding it the ubiquity log over `STDIN`:

    ./parseLogs < myapp.logs

To make it more verbose, add `-v` options.  Verbose output will show unprocessed log lines as well.  It is the aim of this script to process all log lines output by Apple's ubiquity logging.  You can contribute either by amending the script or the [`LOGS`](LOGS) summary file.

# Under The Hood

`UbiquityStoreManager` tries hard to hide all the details from you, maintaining the persistentStoreCoordinator for you.  If you're interested in what it does and how things work, read on.

## Terminology

  * USM = `UbiquityStoreManager`, this project.
  * PSC = `Persistent Store Coordinator`, the object that coordinates between the store file, the store model, and managed contexts.
  * MOC = `Managed Object Context`, a "view" on the data store.  Each context has their own in-memory idea of what the store's objects look like.

## The Ideology

The idea behind USM was to create an implementation that hides all the details of loading the persistent store and allows an application to focus on simply using it.

To accomplish this, USM exposes only the API needed for an application to begin using a store, in addition to some lower-level API an application might need to handle exceptional situations in non-default ways.  USM implements sane and safe default behavior for everything that isn't just "using the store", but allows an application to make different choices if it wants to.

There are different ways one may want to set up and configure their persistence layer.  USM has made the following choices/assumptions for you:
  * There is a difference between the user's iCloud data and the user's local data:
      * When iCloud is **disabled**, an independant local store will be loaded.  The user will not see their iCloud data.
      * When iCloud is **enabled**, the iCloud store will be loaded.  This store will initially be a copy of the local store, but any changes will **not** be saved in the local store: they will only exist on the cloud.
  * The choice of whether iCloud is enabled or not is a **device-specific** one: enabling iCloud on one device does **not** cause all devices to suddenly switch over to iCloud.
      * Application developers are recommended to ask their user upon first start-up of the app whether they want iCloud enabled and allow them to switch it on or off with a setting.
  * When the user enables iCloud and there is no cloud store yet, a new iCloud store to be created and seeded by (filled up with) the data in the local store.
  * When the user enables iCloud on two devices at the same time, the **last device** that finishes seeding a cloud store will win, and **both devices** will begin using the winning cloud store.
  * When the user enables iCloud and there is already an active cloud store, the device will begin using the existing cloud store.
      * To allow users to re-seed the cloud store from a new device, USM provides utilities for deleting the cloud store.  After deletion of the cloud store, enabling iCloud will cause a new store to be seeded from the local store again. 
  * When a user manually deletes the cloud store from their iCloud account (eg. through their device's Settings), USM will clean up after it and switch back to the user's local store.  The intention of the user was clearly to delete the data in the cloud.
      * An application hook exists which allows the application to decide how to handle the case, if they don't want USM to switch to the local store.
  * USM immediately unloads the cloud store if the user logs out of their iCloud account on the device or switches to another user's iCloud account.  In the latter case, an iCloud store will be created on the new cloud account from the local store.

## How Things Work

When initialized, USM will begin loading a store.  Before any store is loaded, the application's delegate is first notified via `willLoadStoreIsCloud:`.  At this point, the application may still make any chances it wishes to USM's configuration, and since this method is called from the internal persistence queue, it is in fact the **recommended** place to perform any initial configuration of USM.  Do not do this from the method that called USM's init.

The `cloudEnabled` property determines what store will be loaded.  If `YES`, USM will begin loading the cloud store.  If `NO`, the local store.

The process of loading a local store is relatively simple.  The directory hierarchy to the store file is created if it didn't exist yet, same thing for the store file.  Automatic light-weight store model migration is enabled and mapping inference is as well.  You can specify additional store loading options via USM's init method, such as file security options.  If the store is loaded successfully, the application is notified and receives the PSC it needs to access the store via
`didLoadStoreForCoordinator:isCloud:`.  If the store fails to load for some reason, the application will not have access to persistence and is notified via `failedLoadingStoreWithCause:context:wasCloud:`.  It can choose to handle this failure in some way.

The process of loading a cloud store is somewhat more involved.  It's mostly the same as for the local store, but there is a bunch of extra logic:
  * If the cloud content no longer exists but the local cloud store file does, it is assumed the user wanted to delete their cloud data and the local store file is deleted.
  * If no cloud content exists, a new cloud store is created by migrating the local store's contents.
    * This new cloud store is identified by a random UUID.
    * The new UUID is kept locally until the migration and opening process for this store is a success.
    * Upon such success, this store is marked as the "active" cloud store by making its UUID ubiquitous.
  * If the cloud store fails to load once, a recovery attempt is made which deletes the local cloud store file and re-opens the cloud store, allowing iCloud to re-initialize the local cloud store file by importing all the cloud content again.
  * If the cloud store continues to fail loading, the store is marked as "corrupted".
  * If the store is successfully loaded, USM waits 20 seconds (to see if any cloud content will fail to import) and if no failure is detected, it checks to see if other devices have reported the cloud store as "corrupted".  If so, cloud content recovery is initiated from this device which is, due to its success in loading the store, deemed healthy.

When a store is loaded, USM monitors it for deletion.  When the cloud store is deleted, USM will clean up any "corruption" marker, the local cloud store file, and will fall back to the local store unless the application chooses to handle the situation via `ubiquityStoreManagerHandleCloudContentDeletion:`.  When the local store is deleted, USM just reloads causing a new local store to be created.

The `cloudEnabled` setting is stored in `NSUserDefaults` under the key `@"USMCloudEnabledKey"`.  When USM detects a change in this key's value, it will reload the active store allowing the change to take effect.  You can use this to add a preference in your `Settings.bundle` for iCloud.

Whenever the application becomes active, USM checks whether the iCloud identity has changed.  If a change is detected and iCloud is currently enabled, the store is reloaded allowing the change to take effect.  Similarly, when a change is detected to the active ubiquitous store UUID and iCloud is currently enabled, the store is also reloaded.

When ubiquitous changes are detected in the cloud store, your application's delegate can specify a custom MOC to use for importing these changes, so that it can become aware of the changes immediately.  To do this, the application should return its MOC via `-ubiquityStoreManager:managedObjectContextForUbiquityChanges:`.  If ubiquitous changes fail to import, the store is reloaded to retry the process and verify whether any corruption has occurred.  Upon successful completion,
the `UbiquityManagedStoreDidImportChangesNotification` notification is posted.

The cloud store is marked as "corrupted" when it fails to load or when cloud transaction logs fail to import.  To detect the failure of transaction log import attempts made by Apple's Core Data, USM swizzles `NSError`'s init method.  This way, it can detect when an `NSError` is created for transaction log import failures and act accordingly.

When cloud "corruption" is detected the cloud store is immediately unloaded to prevent further desync.  When the store is not healthy on the current device (the store failed to load or failed to import ubiquitous changes), USM will just wait and the persistence layer will remain unavailable.  When the store is healthy on the current device, USM will initiate a rebuild of the cloud content by deleting the cloud content from iCloud and creating a new cloud store with a new random UUID, which
will be seeded from the healthy local cloud store file.  The new cloud store will be filled with the old cloud store's data and healthy cloud content will be built for it.  Upon completion, the non-healthy devices that were waiting will notice a new cloud store becoming active, will load it, and will become healthy again.  The application can hook into this process and change what happens by implementing `handleCloudContentCorruptionWithHealthyStore:`.

Any store migration can be performed by one of four strategies:
  * `UbiquityStoreMigrationStrategyIOS`: This strategy performs the migration via a coordinated `migratePersistentStore:` of the PSC.  Some iOS versions have bugs here which makes this generally unreliable.  This is the default strategy on iOS 7.
  * `UbiquityStoreMigrationStrategyCopyEntities`: This strategy performs the migration by copying over any non-ubiquitous metadata and copying over all entities, properties and relationships from one store to the other.  This is the default strategy on iOS 6.
  * `UbiquityStoreMigrationStrategyManual`: This strategy allows the application's delegate to perform the migration by implementing `manuallyMigrateStore:`.  This may be necessary if you have a really huge or complex data model or want some more control over how exactly to migrate your entities.
  * `UbiquityStoreMigrationStrategyNone`: No migration is performed and the new store is opened as-is.

# License

`UbiquityStoreManager` is licensed under the [Apache License, Version 2.0](https://github.com/lhunath/UbiquityStoreManager/blob/master/LICENSE).

Feel free to use it in any of your applications.  I’m also happy to receive any comments, feedback or review any pull requests.


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/lhunath/ubiquitystoremanager/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

