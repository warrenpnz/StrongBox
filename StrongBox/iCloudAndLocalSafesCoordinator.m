//
//  Hybrid.m
//  Strongbox
//
//  Created by Mark on 25/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "iCloudAndLocalSafesCoordinator.h"
#import "Settings.h"
#import "AppleICloudProvider.h"
#import "LocalDeviceStorageProvider.h"
#import "Strongbox.h"
#import "SafesCollection.h"
#import "JNKeychain.h"

@implementation iCloudAndLocalSafesCoordinator

// TODO:
// IDea to PUSH Safes... perhaps change the safe collection in here directly and the notify SafeView so it can update...
// Migration ... Need to support UI Progress Indicator

NSURL * _iCloudRoot;
NSMetadataQuery * _query;
BOOL _iCloudURLsReady;
NSMutableArray<AppleICloudOrLocalSafeFile*> * _iCloudFiles;
BOOL _pleaseCopyiCloudToLocalWhenReady;
BOOL _pleaseMoveLocalToiCloudWhenReady;


+ (instancetype)sharedInstance {
    static iCloudAndLocalSafesCoordinator *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[iCloudAndLocalSafesCoordinator alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    if(self = [super init]) {
        _iCloudFiles = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void)initializeiCloudAccessWithCompletion:(void (^)(BOOL available)) completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        _iCloudRoot = [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:kStrongboxICloudContainerIdentifier];
        if (_iCloudRoot != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"iCloud available at: %@", _iCloudRoot);
                completion(TRUE);
            });
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"iCloud not available");
                completion(FALSE);
            });
        }
    });
}

- (void)migrateLocalToiCloud {
    if (_iCloudURLsReady) {
        [self localToiCloudImpl];
    }
    else {
        _pleaseMoveLocalToiCloudWhenReady = YES;
    }
}

- (void)migrateiCloudToLocal {
    NSLog(@"iCloud => local");
    
    if (_iCloudURLsReady) {
        [self iCloudToLocalImpl];
    } else {
        _pleaseCopyiCloudToLocalWhenReady = YES;
    }
}

- (void)migrateLocalSafeToICloud:(SafeMetaData *)safe {
    NSURL *fileURL = [[LocalDeviceStorageProvider sharedInstance] getFileUrl:safe];
    
    NSString * displayName = safe.nickName;
    NSURL *destURL = [self getDocURL:[self getDocFilename:displayName uniqueInObjects:NO]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        NSError * error;
        BOOL success = [[NSFileManager defaultManager] setUbiquitous:[Settings sharedInstance].iCloudOn itemAtURL:fileURL destinationURL:destURL error:&error];
        if (success) {
            NSLog(@"Moved %@ to %@", fileURL, destURL);
            NSString* newNickName = [self displayNameFromUrl:destURL];
            
            // Migrate any touch ID entry for this safe
            
            NSString *password = [JNKeychain loadValueForKey:displayName];
            if(password) {
                [JNKeychain saveValue:password forKey:newNickName];
            }
            
            safe.nickName = newNickName;
            safe.storageProvider = kiCloud;
            safe.fileIdentifier = destURL.absoluteString;
            safe.fileName = [destURL lastPathComponent];
            [SafesCollection.sharedInstance save];
        }
        else {
            NSLog(@"Failed to move %@ to %@: %@", fileURL, destURL, error.localizedDescription);
        }
    });
}

- (void)localToiCloudImpl {
    [_query disableUpdates];
    
    NSArray<SafeMetaData*> *localSafes = [SafesCollection.sharedInstance getSafesOfProvider:kLocalDevice];
    
    for(SafeMetaData *safe in localSafes) {
        [self migrateLocalSafeToICloud:safe];
    }
    
     self.updateSafesCollection();
    
    [_query enableUpdates];
}

- (void)createLocalDeviceSafe:(NSData *)data
                       newURL:(NSURL *)newURL
                     nickName:(NSString *)nickName
             isTouchIdEnabled:(BOOL)isTouchIdEnabled
         isEnrolledForTouchId:(BOOL)isEnrolledForTouchId
{
    [[LocalDeviceStorageProvider sharedInstance] create:nickName data:data parentFolder:nil viewController:nil completion:^(SafeMetaData *metadata, NSError *error)
     {
         if (error == nil) {
             NSLog(@"Copied %@ to %@ (%d)", newURL, metadata.fileIdentifier, [Settings sharedInstance].iCloudOn);
             
             metadata.isEnrolledForTouchId = isEnrolledForTouchId;
             metadata.isTouchIdEnabled = isTouchIdEnabled;
             
             [SafesCollection.sharedInstance add:metadata];
         }
         else {
             NSLog(@"An error occurred: %@", error);
             NSLog(@"Failed to copy %@ to %@: %@", newURL, metadata.fileIdentifier, error.localizedDescription);
             // TODO:
         }
     }];
}

- (void)migrateICloudSafeToLocal:(AppleICloudOrLocalSafeFile *)file {
    SafeMetaData* metadata = [self tryToFindMetadataForiCloudFile:file.fileUrl]; // Try to preserve metadata
    
    if(metadata) {
        [SafesCollection.sharedInstance removeSafe:metadata]; // Remove this safe so we can add local with same nick name
    }
    
    NSFileCoordinator* fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [fileCoordinator coordinateReadingItemAtURL:file.fileUrl options:NSFileCoordinatorReadingWithoutChanges error:nil byAccessor:^(NSURL *newURL) {
        NSData* data = [NSData dataWithContentsOfURL:newURL];
        NSString *nickName = metadata ? metadata.nickName : [self displayNameFromUrl:newURL];
        BOOL isTouchIdEnabled = metadata ? metadata.isTouchIdEnabled : YES;
        BOOL isEnrolledForTouchId = metadata ? metadata.isEnrolledForTouchId : NO;
    
        NSString *touchIdPassword = [JNKeychain loadValueForKey:metadata.nickName];
        if(touchIdPassword) {
            [JNKeychain saveValue:touchIdPassword forKey:nickName];
        }
    
        [self createLocalDeviceSafe:data newURL:newURL nickName:nickName isTouchIdEnabled:isTouchIdEnabled isEnrolledForTouchId:isEnrolledForTouchId];
    }];
}

- (void)iCloudToLocalImpl {
    NSLog(@"iCloud => local impl");
 
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        for (AppleICloudOrLocalSafeFile *file in [_iCloudFiles copy]) {
            [self migrateICloudSafeToLocal:file];
        }
        
        [self removeAllICloudSafes];
        self.updateSafesCollection();
    });
}

- (SafeMetaData*)tryToFindMetadataForiCloudFile:(NSURL*) url {
    for(SafeMetaData *metadata in [SafesCollection.sharedInstance getSafesOfProvider:kiCloud]) {
        if([metadata.fileIdentifier isEqualToString:url.absoluteString]) {
            NSLog(@"Found existing metadata for iCloud File: %@", metadata);
            return metadata;
        }
    }
    
    return nil;
}
    
- (void)removeAllICloudSafes {
    NSArray<SafeMetaData*> *icloudSafesToRemove = [SafesCollection.sharedInstance getSafesOfProvider:kiCloud];
    
    for (SafeMetaData *item in icloudSafesToRemove) {
        [SafesCollection.sharedInstance removeSafe:item];
    }
}

- (NSMetadataQuery *)documentQuery {
    NSMetadataQuery * query = [[NSMetadataQuery alloc] init];
    
    if (query) {
        [query setSearchScopes:[NSArray arrayWithObject:NSMetadataQueryUbiquitousDocumentsScope]];
        
        [query setPredicate:[NSPredicate predicateWithFormat:@"%K LIKE %@",
                             NSMetadataItemFSNameKey, @"*"]];
    }
    
    return query;
}

- (void)stopQuery {
    if (_query) {
        NSLog(@"No longer watching iCloud dir...");
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidFinishGatheringNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidUpdateNotification object:nil];
        [_query stopQuery];
        _query = nil;
    }
}

- (void)startCoordinating {
    [self stopQuery];
    
    _iCloudURLsReady = NO;
    [_iCloudFiles removeAllObjects];
    
    NSLog(@"Starting to watch iCloud dir...");
    
    _query = [self documentQuery];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(processiCloudFiles:)
                                                 name:NSMetadataQueryDidFinishGatheringNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(processiCloudFiles:)
                                                 name:NSMetadataQueryDidUpdateNotification
                                               object:nil];
    
    [_query startQuery];
}

- (NSString*)displayNameFromUrl:(NSURL*)url {
    return [url.lastPathComponent stringByDeletingPathExtension];
}

- (void)logAllCloudStorageKeysForMetadataItem:(NSMetadataItem *)item
{
    NSString* displayName = [item valueForAttribute:NSMetadataItemDisplayNameKey];
    NSDate* contentChangeDate = [item valueForAttribute:NSMetadataItemFSContentChangeDateKey];
    NSNumber *isUbiquitous = [item valueForAttribute:NSMetadataItemIsUbiquitousKey];
    NSNumber *hasUnresolvedConflicts = [item valueForAttribute:NSMetadataUbiquitousItemHasUnresolvedConflictsKey];
    NSNumber *downloadStatus = [item valueForAttribute:NSMetadataUbiquitousItemDownloadingStatusKey];
    NSNumber *isUploaded = [item valueForAttribute:NSMetadataUbiquitousItemIsUploadedKey];
    NSNumber *isUploading = [item valueForAttribute:NSMetadataUbiquitousItemIsUploadingKey];
    NSNumber *percentDownloaded = [item valueForAttribute:NSMetadataUbiquitousItemPercentDownloadedKey];
    NSNumber *percentUploaded = [item valueForAttribute:NSMetadataUbiquitousItemPercentUploadedKey];
    NSURL *url = [item valueForAttribute:NSMetadataItemURLKey];
    
    NSNumber * hidden = nil;
    [url getResourceValue:&hidden forKey:NSURLIsHiddenKey error:nil];
    
    //BOOL documentExists = [[NSFileManager defaultManager] fileExistsAtPath:[url path]];
    
    NSLog(@"%@ change:%@ hidden:%@ isUbiquitous:%@ hasUnresolvedConflicts:%@ downloadStatus:%@(%@%%) isUploaded:%@ isUploading:%@ (%@%%) - %@",
          displayName, contentChangeDate, hidden, isUbiquitous, hasUnresolvedConflicts, downloadStatus, percentDownloaded, isUploaded, isUploading, percentUploaded, url);
}

- (void)processiCloudFiles:(NSNotification *)notification {
    [_query disableUpdates];
    [_iCloudFiles removeAllObjects];
    
    // The query reports all files found, every time.
    //
    //    NSLog(@"*********************************************************************************************************");
    //
    //    NSArray* added = [notification.userInfo objectForKey:NSMetadataQueryUpdateAddedItemsKey];
    //    NSArray* changed = [notification.userInfo objectForKey:NSMetadataQueryUpdateChangedItemsKey];
    //    NSArray* removed = [notification.userInfo objectForKey:NSMetadataQueryUpdateRemovedItemsKey];
    //
    //    NSLog(@"+%lu /%lu -%lu", (unsigned long)added.count, (unsigned long)changed.count, (unsigned long)removed.count);
    //
    //    for(NSMetadataItem *item in changed) {
    //        NSLog(@"Changed: %@", item);
    //    }
    //
    //    NSLog(@"*********************************************************************************************************");
    //
    NSArray<NSMetadataItem*> * queryResults = [_query results];
    
    for (NSMetadataItem * result in queryResults) {
        NSURL * fileURL = [result valueForAttribute:NSMetadataItemURLKey];
        
        //[self logAllCloudStorageKeysForMetadataItem:result];
        
        // Don't include hidden files
        
        NSNumber * hidden = nil;
        [fileURL getResourceValue:&hidden forKey:NSURLIsHiddenKey error:nil];
        
        if (hidden == nil || ![hidden boolValue]) {
            NSString* displayName = [result valueForAttribute:NSMetadataItemDisplayNameKey];
            NSString* dn = displayName ? displayName : [self displayNameFromUrl:fileURL];
            
            NSNumber *hasUnresolvedConflicts = [result valueForAttribute:NSMetadataUbiquitousItemHasUnresolvedConflictsKey];
            BOOL huc = hasUnresolvedConflicts ? [hasUnresolvedConflicts boolValue] : NO;
            
            [_iCloudFiles addObject:[[AppleICloudOrLocalSafeFile alloc] initWithDisplayName:dn fileUrl:fileURL hasUnresolvedConflicts:huc]];
        }
    }
    //NSLog(@"*********************************************************************************************************");
    
    //NSLog(@"Found %lu iCloud files.", (unsigned long)_iCloudFiles.count);
    
    _iCloudURLsReady = YES;
    
    if ([Settings sharedInstance].iCloudOn) {
        [self iCloudFilesDidChange:_iCloudFiles];
    }

    if (_pleaseMoveLocalToiCloudWhenReady) {
        _pleaseMoveLocalToiCloudWhenReady = NO;
        [self localToiCloudImpl];
    }
    else if (_pleaseCopyiCloudToLocalWhenReady) {
        _pleaseCopyiCloudToLocalWhenReady = NO;
        [self iCloudToLocalImpl];
    }
    
    [_query enableUpdates];
}

- (NSURL *)getDocURL:(NSString *)filename {
    NSURL * docsDir = [_iCloudRoot URLByAppendingPathComponent:@"Documents" isDirectory:YES];
    return [docsDir URLByAppendingPathComponent:filename];
}

- (NSString*)docNameFromDisplayName:(NSString*)displayName {
    return [NSString stringWithFormat:@"%@.%@", displayName, kDefaultFileExtension];
}

- (BOOL)docNameExistsIniCloudURLs:(NSString *)docName {
    BOOL nameExists = NO;
    for (AppleICloudOrLocalSafeFile *file in _iCloudFiles) {
        if ([[file.fileUrl lastPathComponent] isEqualToString:docName]) {
            nameExists = YES;
            break;
        }
    }
    return nameExists;
}

- (BOOL)docNameExistsInObjects:(NSString *)docName {
    BOOL nameExists = NO;
    
    for (SafeMetaData *entry in [SafesCollection sharedInstance].sortedSafes) {
        if (entry.storageProvider == kiCloud && [entry.fileName isEqualToString:docName]) {
            nameExists = YES;
            break;
        }
    }
    
    return nameExists;
}

-(NSString*)getDocFilename:(NSString *)prefix uniqueInObjects:(BOOL)uniqueInObjects {
    NSInteger docCount = 0;
    NSString* newDocName = nil;
    
    // At this point, the document list should be up-to-date.
    BOOL done = NO;
    BOOL first = YES;
    while (!done) {
        if (first) {
            first = NO;
            newDocName = [NSString stringWithFormat:@"%@.%@",
                          prefix, kDefaultFileExtension];
        } else {
            newDocName = [NSString stringWithFormat:@"%@ %ld.%@",
                          prefix, (long)docCount, kDefaultFileExtension];
        }
        
        BOOL nameExists;
        if (uniqueInObjects) {
            nameExists = [self docNameExistsInObjects:newDocName];
        } else {
            nameExists = [self docNameExistsIniCloudURLs:newDocName];
        }
        
        if (!nameExists) {
            break;
        } else {
            docCount++;
        }
    }
    
    return newDocName;
}

- (void)iCloudFilesDidChange:(NSArray<AppleICloudOrLocalSafeFile*>*)files {
    BOOL removed = [self removeAnyDeletedICloudSafes:files];
    BOOL updated = [self updateAnyICloudSafes:files];
    BOOL added = [self addAnyNewICloudSafes:files];
    
    if(added || removed || updated) {
        self.updateSafesCollection();
    }
}

- (BOOL)updateAnyICloudSafes:(NSArray<AppleICloudOrLocalSafeFile*> *)files {
    BOOL updated = NO;
    
    NSMutableDictionary<NSString*, AppleICloudOrLocalSafeFile*>* theirs = [self getAllICloudSafeFileNamesFromMetadataFilesList:files];
    NSDictionary<NSString*, SafeMetaData*>* mine = [self getAllMyICloudSafeFileNames];
    
    for(NSString* fileName in mine.allKeys) {
        AppleICloudOrLocalSafeFile *match = [theirs objectForKey:fileName];
        
        if(match) {
            [mine objectForKey:fileName].fileIdentifier = [match.fileUrl absoluteString];
            [mine objectForKey:fileName].hasUnresolvedConflicts = match.hasUnresolvedConflicts;
            updated = YES;
        }
    }
    
    if(updated) {
        [[SafesCollection sharedInstance] save];
    }
    
    return updated;
}

-(BOOL)addAnyNewICloudSafes:(NSArray<AppleICloudOrLocalSafeFile*> *)files {
    BOOL added = NO;
    
    NSMutableDictionary<NSString*, AppleICloudOrLocalSafeFile*>* theirs = [self getAllICloudSafeFileNamesFromMetadataFilesList:files];
    
    NSDictionary<NSString*, SafeMetaData*>* mine = [self getAllMyICloudSafeFileNames];
    
    for(NSString* fileName in mine.allKeys) {
        [theirs removeObjectForKey:fileName];
    }
    
    for (AppleICloudOrLocalSafeFile* safeFile in theirs.allValues) {
        NSString *fileName = [safeFile.fileUrl lastPathComponent];
        NSString *displayName = safeFile.displayName;
        
        SafeMetaData *newSafe = [[SafeMetaData alloc] initWithNickName:displayName storageProvider:kiCloud fileName:fileName fileIdentifier:[safeFile.fileUrl absoluteString]];
        newSafe.hasUnresolvedConflicts = safeFile.hasUnresolvedConflicts;
        
        NSLog(@"Got New Safe... Adding [%@]", newSafe);
        
        [[SafesCollection sharedInstance] add:newSafe];
        
        added = YES;
    }
    
    return added;
}

- (BOOL)removeAnyDeletedICloudSafes:(NSArray<AppleICloudOrLocalSafeFile*>*)files {
    BOOL removed = NO;
    
    NSMutableDictionary<NSString*, SafeMetaData*> *safeFileNamesToBeRemoved = [self getAllMyICloudSafeFileNames];
    NSMutableDictionary<NSString*, AppleICloudOrLocalSafeFile*>* theirs = [self getAllICloudSafeFileNamesFromMetadataFilesList:files];
    
    for(NSString* fileName in theirs.allKeys) {
        [safeFileNamesToBeRemoved removeObjectForKey:fileName];
    }
    
    for(SafeMetaData* safe in safeFileNamesToBeRemoved.allValues) {
        NSLog(@"Safe Removed: %@", safe);
        
        [SafesCollection.sharedInstance removeSafe:safe];
        removed = YES;
    }
    
    return removed;
}

-(NSMutableDictionary<NSString*, SafeMetaData*>*)getAllMyICloudSafeFileNames {
    NSMutableDictionary<NSString*, SafeMetaData*>* ret = [NSMutableDictionary dictionary];
    
    for(SafeMetaData *safe in [[SafesCollection sharedInstance] getSafesOfProvider:kiCloud]) {
        [ret setValue:safe forKey:safe.fileName];
    }
    
    return ret;
}

-(NSMutableDictionary<NSString*, AppleICloudOrLocalSafeFile*>*)getAllICloudSafeFileNamesFromMetadataFilesList:(NSArray<AppleICloudOrLocalSafeFile*>*)files {
    NSMutableDictionary<NSString*, AppleICloudOrLocalSafeFile*>* ret = [NSMutableDictionary dictionary];
    
    for(AppleICloudOrLocalSafeFile *item in files) {
        [ret setObject:item forKey:[item.fileUrl lastPathComponent]];
    }
    
    return ret;
}

@end
