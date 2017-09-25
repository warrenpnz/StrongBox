//
//  Hybrid.m
//  Strongbox
//
//  Created by Mark on 25/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "iCloudOrLocalHybrid.h"
#import "Settings.h"
#import "AppleICloudProvider.h"
#import "LocalDeviceStorageProvider.h"

@implementation iCloudOrLocalHybrid

// TODO:
// IDea to PUSH Safes... perhaps change the safe collection in here directly and the notify SafeView so it can update...
// Migration ... Need to support UI Progress Indicator

+ (instancetype)sharedInstance {
    static iCloudOrLocalHybrid *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[iCloudOrLocalHybrid alloc] init];
    });
    
    return sharedInstance;
}

- (id<SafeStorageProvider>)provider {
    return [Settings sharedInstance].iCloudOn ? [AppleICloudProvider sharedInstance] : [LocalDeviceStorageProvider sharedInstance];
}

- (instancetype)init {
    if (self = [super init]) {
        _providesIcons = NO;
        _browsable = NO;
        
        return self;
    }
    else {
        return nil;
    }
}

- (StorageProvider)storageId {
    return self.provider.storageId;
}

- (BOOL)cloudBased {
    return self.provider.cloudBased;
}

- (NSString *)displayName {
    return self.provider.displayName;
}

- (NSString *)icon {
    return self.provider.icon;
}

- (void)    create:(NSString *)nickName
              data:(NSData *)data
      parentFolder:(NSObject *)parentFolder
    viewController:(UIViewController *)viewController
        completion:(void (^)(SafeMetaData *metadata, NSError *error))completion {
    return [self.provider create:nickName data:data parentFolder:parentFolder viewController:viewController completion:completion];
}

- (void)      read:(SafeMetaData *)safeMetaData
    viewController:(UIViewController *)viewController
        completion:(void (^)(NSData *data, NSError *error))completion {
    return [self.provider read:safeMetaData viewController:viewController completion:completion];
}

- (void)update:(SafeMetaData *)safeMetaData
          data:(NSData *)data
    completion:(void (^)(NSError *error))completion {
    return [self.provider update:safeMetaData data:data completion:completion];
}

- (void)delete:(SafeMetaData*)safeMetaData completion:(void (^)(NSError *error))completion {
    return [self.provider delete:safeMetaData completion:completion];
}

- (SafeMetaData *)getSafeMetaData:(NSString *)nickName providerData:(NSObject *)providerData {
    return [self.provider getSafeMetaData:nickName providerData:providerData];
}


- (void)list:(NSObject *)parentFolder viewController:(UIViewController *)viewController completion:(void (^)(NSArray<StorageBrowserItem *> *, NSError *))completion {
    return [self.provider list:parentFolder viewController:viewController completion:completion];
}


- (void)loadIcon:(NSObject *)providerData viewController:(UIViewController *)viewController completion:(void (^)(UIImage *))completionHandler {
    return [self.provider loadIcon:providerData viewController:viewController completion:completionHandler];
}


- (void)readWithProviderData:(NSObject *)providerData viewController:(UIViewController *)viewController completion:(void (^)(NSData *, NSError *))completionHandler {
    return [self.provider readWithProviderData:providerData viewController:viewController completion:completionHandler];
}


- (void)migrateLocalToiCloud {
//    NSLog(@"local => iCloud");
//
//    if (_iCloudURLsReady) {
//        [self localToiCloudImpl];
//    }
//    else {
//        _pleaseMoveLocalToiCloudWhenReady = YES;
//    }
}

- (void)migrateiCloudToLocal {
//    if (_iCloudURLsReady) {
//        [self iCloudToLocalImpl];
//    } else {
//        _pleaseCopyiCloudToLocalWhenReady = YES;
//    }
}

- (void)localToiCloudImpl {
    NSLog(@"local => iCloud impl");
//    NSArray * localDocuments = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.localRoot includingPropertiesForKeys:nil options:0 error:nil];
//
//    for (int i=0; i < localDocuments.count; i++) {
//        NSURL * fileURL = [localDocuments objectAtIndex:i];
//        if ([[fileURL pathExtension] isEqualToString:FILE_EXTENSION]) {
//            NSString * displayName = [[fileURL lastPathComponent] stringByDeletingPathExtension];
//
//            if([self docNameExistsIniCloudURLs:[self docNameFromDisplayName:displayName]]) {
//                displayName = [displayName stringByAppendingString:@"-Migrated"];
//            }
//
//            NSURL *destURL = [self getDocURL:[self getDocFilename:displayName uniqueInObjects:NO]];
//
//            // Perform actual move in background thread
//            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
//                NSError * error;
//                BOOL success = [[NSFileManager defaultManager] setUbiquitous:[Settings sharedInstance].iCloudOn itemAtURL:fileURL destinationURL:destURL error:&error];
//                if (success) {
//                    NSLog(@"Moved %@ to %@", fileURL, destURL);
//                } else {
//                    NSLog(@"Failed to move %@ to %@: %@", fileURL, destURL, error.localizedDescription);
//                }
//            });
//        }
//    }
}

- (void)iCloudToLocalImpl {
    NSLog(@"iCloud => local impl");
//
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
//        NSMutableArray<AppleICloudOrLocalSafeFile*>* updatedFiles = [NSMutableArray array];
//
//        NSArray<AppleICloudOrLocalSafeFile*>* safesCollectionCopy = [_iCloudFiles copy];
//        for (AppleICloudOrLocalSafeFile *file in safesCollectionCopy) {
//            NSURL *destURL = [self getDocURL:[self getDocFilename:file.displayName uniqueInObjects:YES]];
//
//            NSFileCoordinator* fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
//            [fileCoordinator coordinateReadingItemAtURL:file.fileUrl options:NSFileCoordinatorReadingWithoutChanges error:nil byAccessor:^(NSURL *newURL) {
//                NSFileManager * fileManager = [[NSFileManager alloc] init];
//                NSError * error;
//                BOOL success = [fileManager copyItemAtURL:file.fileUrl toURL:destURL error:&error];
//
//                //BOOL success = [fileManager setUbiquitous:NO itemAtURL:file.fileUrl destinationURL:destURL error:&error];
//
//                if (success) {
//                    AppleICloudOrLocalSafeFile *localSafeFile =
//                    [[AppleICloudOrLocalSafeFile alloc] initWithDisplayName:[self displayNameFromUrl:destURL] fileUrl:destURL hasUnresolvedConflicts:NO];
//
//                    [updatedFiles addObject:localSafeFile];
//
//                    NSLog(@"Copied %@ to %@ (%d)", file.fileUrl, destURL, [Settings sharedInstance].iCloudOn);
//                } else {
//                    NSLog(@"Failed to copy %@ to %@: %@", file.fileUrl, destURL, error.localizedDescription);
//                }
//            }];
//        }
//
//        self.filesUpdatesListener(updatedFiles);
//    });
}


@end
