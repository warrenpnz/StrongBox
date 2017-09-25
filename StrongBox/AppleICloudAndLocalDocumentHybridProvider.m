//
//  AppleICloudProvider.m
//  Strongbox
//
//  Created by Mark on 20/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "AppleICloudAndLocalDocumentHybridProvider.h"
#import "PasswordSafeUIDocument.h"
#import "Strongbox.h"
#import "Utils.h"
#import "SafesCollection.h"
#import "Settings.h"

#define FILE_EXTENSION @"psafe3"

NSURL * _iCloudRoot;
NSMetadataQuery * _query;
BOOL _iCloudURLsReady;
NSMutableArray<AppleICloudOrLocalSafeFile*> * _iCloudFiles;
BOOL _pleaseCopyiCloudToLocalWhenReady;
BOOL _pleaseMoveLocalToiCloudWhenReady;

@implementation AppleICloudAndLocalDocumentHybridProvider

+ (instancetype)sharedInstance {
    static AppleICloudAndLocalDocumentHybridProvider *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AppleICloudAndLocalDocumentHybridProvider alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _storageId = kiCloud;
        _cloudBased = YES;
        _providesIcons = NO;
        _browsable = NO;
        
        // TODO:
        _iCloudFiles = [[NSMutableArray alloc] init];
        
        return self;
    }
    else {
        return nil;
    }
}

- (NSString *)displayName {
    return Settings.sharedInstance.iCloudOn ? @"iCloud" : @"Local Device";
}

- (NSString *)icon {
    return Settings.sharedInstance.iCloudOn ? @"icloud-32" : @"phone";
}

- (NSURL *)localRoot { 
    NSArray * paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
//
//    NSArray * localDocuments = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:paths.lastObject includingPropertiesForKeys:nil options:0 error:nil];
//
//    for (int i=0; i < localDocuments.count; i++) {
//        NSURL * fileURL = [localDocuments objectAtIndex:i];
//        NSLog(@"%@", fileURL);
//    }
    
    //NSLog(@"LOCAL => %@" , paths.lastObject);
    
    return paths.lastObject;
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

- (void)    create:(NSString *)nickName
              data:(NSData *)data
      parentFolder:(NSObject *)parentFolder
    viewController:(UIViewController *)viewController
        completion:(void (^)(SafeMetaData *metadata, NSError *error))completion {

    NSURL * fileURL = [self getDocURL:[self getDocFilename:nickName uniqueInObjects:YES]];
    
    NSLog(@"Want to create file at %@", fileURL);
    
    PasswordSafeUIDocument * doc = [[PasswordSafeUIDocument alloc] initWithData:data fileUrl:fileURL];
    
    NSLog(@"Loaded File URL: %@ in state: [%@]", [doc.fileURL lastPathComponent], [self stringForDocumentState:doc.documentState]);

    [doc saveToURL:fileURL forSaveOperation:UIDocumentSaveForCreating completionHandler:^(BOOL success) {
        if (!success) {
            NSLog(@"Failed to create file at %@", fileURL);
            completion(nil, [Utils createNSError:@"Failed to create file" errorCode:-5]);
            return;
        }
        
        NSLog(@"File created at %@", fileURL);
    
        [doc closeWithCompletionHandler:^(BOOL success) {
            if (!success) {
                NSLog(@"Failed to close %@", fileURL);
            }
        }];
        
        SafeMetaData * metadata = [[SafeMetaData alloc] initWithNickName:nickName
                                                         storageProvider:kiCloud
                                                                fileName:[fileURL lastPathComponent]
                                                          fileIdentifier:[fileURL absoluteString]];
        
        completion(metadata, nil);
    }];
}

- (void)      read:(SafeMetaData *)safeMetaData
    viewController:(UIViewController *)viewController
        completion:(void (^)(NSData *data, NSError *error))completion {
    NSURL *fileUrl = [NSURL URLWithString:safeMetaData.fileIdentifier];
    PasswordSafeUIDocument * doc = [[PasswordSafeUIDocument alloc] initWithFileURL:fileUrl];
    
    [doc openWithCompletionHandler:^(BOOL success) {
        if (!success) {
            NSLog(@"Failed to open %@", fileUrl);
            completion(nil, [Utils createNSError:@"Failed to open" errorCode:-6]);
            return;
        }

        NSLog(@"Loaded File URL: %@ in state: [%@]", [doc.fileURL lastPathComponent], [self stringForDocumentState:doc.documentState]);
        
        NSData* data = doc.data;
        
        [doc closeWithCompletionHandler:^(BOOL success) {
            if (!success) {
                NSLog(@"Failed to open %@", fileUrl);
                completion(nil, [Utils createNSError:@"Failed to close after reading" errorCode:-6]);
                return;
            }
            
            completion(data, nil);
        }];
    }];
}

- (void)update:(SafeMetaData *)safeMetaData
          data:(NSData *)data
    completion:(void (^)(NSError *error))completion {
    NSURL *fileUrl = [NSURL URLWithString:safeMetaData.fileIdentifier];
    PasswordSafeUIDocument * doc = [[PasswordSafeUIDocument alloc] initWithFileURL:fileUrl];
    doc.data = data;
    
    NSLog(@"Opened File URL: %@ in state: [%@]", [doc.fileURL lastPathComponent], [self stringForDocumentState:doc.documentState]);

    [doc saveToURL:fileUrl forSaveOperation:UIDocumentSaveForOverwriting completionHandler:^(BOOL success) {
        if (!success) {
            NSLog(@"Failed to update file at %@", fileUrl);
            completion([Utils createNSError:@"Failed to update file" errorCode:-5]);
            return;
        }
        
        NSLog(@"File updated at %@", fileUrl);
        
        [doc closeWithCompletionHandler:^(BOOL success) {
            if (!success) {
                NSLog(@"Failed to close %@", fileUrl);
            }
            
            completion(nil);
        }];
    }];
}

- (void)delete:(SafeMetaData*)safeMetaData completion:(void (^)(NSError *error))completion {
    if(safeMetaData.storageProvider != kiCloud) {
        NSLog(@"Safe is not an Apple iCloud safe!");
        return;
    }
 
    NSURL *url = [NSURL URLWithString:safeMetaData.fileIdentifier];
    
    // Wrap in file coordinator
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        NSFileCoordinator* fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [fileCoordinator coordinateWritingItemAtURL:url
                                            options:NSFileCoordinatorWritingForDeleting
                                              error:nil
                                         byAccessor:^(NSURL* writingURL) {
                                             NSFileManager* fileManager = [[NSFileManager alloc] init];
                                             [fileManager removeItemAtURL:url error:nil];
                                         }];
    });
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

- (void)monitorICloudFiles {
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
    
    NSLog(@"*********************************************************************************************************");
    
    NSArray* added = [notification.userInfo objectForKey:NSMetadataQueryUpdateAddedItemsKey];
    NSArray* changed = [notification.userInfo objectForKey:NSMetadataQueryUpdateChangedItemsKey];
    NSArray* removed = [notification.userInfo objectForKey:NSMetadataQueryUpdateRemovedItemsKey];
    
    NSLog(@"+%lu /%lu -%lu", (unsigned long)added.count, (unsigned long)changed.count, (unsigned long)removed.count);
    
    for(NSMetadataItem *item in changed) {
        NSLog(@"Changed: %@", item);
    }
    
    NSLog(@"*********************************************************************************************************");
    
    NSArray<NSMetadataItem*> * queryResults = [_query results];
    
    for (NSMetadataItem * result in queryResults) {
        NSURL * fileURL = [result valueForAttribute:NSMetadataItemURLKey];
        
        [self logAllCloudStorageKeysForMetadataItem:result];
        
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
    NSLog(@"*********************************************************************************************************");
    
    NSLog(@"Found %lu iCloud files.", (unsigned long)_iCloudFiles.count);
    
    _iCloudURLsReady = YES;
    
    if ([Settings sharedInstance].iCloudOn) {
        self.filesUpdatesListener(_iCloudFiles);
    }
    
    if (_pleaseMoveLocalToiCloudWhenReady) {
        _pleaseMoveLocalToiCloudWhenReady = NO;
        [[AppleICloudAndLocalDocumentHybridProvider sharedInstance] localToiCloudImpl];
    }
    else if (_pleaseCopyiCloudToLocalWhenReady) {
        _pleaseCopyiCloudToLocalWhenReady = NO;
        [self iCloudToLocalImpl];
    }
    
    [_query enableUpdates];
}

- (void)migrateLocalToiCloud {
    NSLog(@"local => iCloud");
    
    if (_iCloudURLsReady) {
        [self localToiCloudImpl];
    }
    else {
        _pleaseMoveLocalToiCloudWhenReady = YES;
    }
}

- (void)migrateiCloudToLocal {
    if (_iCloudURLsReady) {
        [self iCloudToLocalImpl];
    } else {
        _pleaseCopyiCloudToLocalWhenReady = YES;
    }
}

- (void)localToiCloudImpl {
    NSLog(@"local => iCloud impl");
    NSArray * localDocuments = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.localRoot includingPropertiesForKeys:nil options:0 error:nil];
    
    for (int i=0; i < localDocuments.count; i++) {
        NSURL * fileURL = [localDocuments objectAtIndex:i];
        if ([[fileURL pathExtension] isEqualToString:FILE_EXTENSION]) {
            NSString * displayName = [[fileURL lastPathComponent] stringByDeletingPathExtension];
            
            if([self docNameExistsIniCloudURLs:[self docNameFromDisplayName:displayName]]) {
                displayName = [displayName stringByAppendingString:@"-Migrated"];
            }
            
            NSURL *destURL = [self getDocURL:[self getDocFilename:displayName uniqueInObjects:NO]];
            
            // Perform actual move in background thread
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
                NSError * error;
                BOOL success = [[NSFileManager defaultManager] setUbiquitous:[Settings sharedInstance].iCloudOn itemAtURL:fileURL destinationURL:destURL error:&error];
                if (success) {
                    NSLog(@"Moved %@ to %@", fileURL, destURL);
                } else {
                    NSLog(@"Failed to move %@ to %@: %@", fileURL, destURL, error.localizedDescription);
                }
            });
        }
    }
}

- (void)iCloudToLocalImpl {
    NSLog(@"iCloud => local impl");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        NSMutableArray<AppleICloudOrLocalSafeFile*>* updatedFiles = [NSMutableArray array];
        
        NSArray<AppleICloudOrLocalSafeFile*>* safesCollectionCopy = [_iCloudFiles copy];
        for (AppleICloudOrLocalSafeFile *file in safesCollectionCopy) {
            NSURL *destURL = [self getDocURL:[self getDocFilename:file.displayName uniqueInObjects:YES]];
            
            NSFileCoordinator* fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [fileCoordinator coordinateReadingItemAtURL:file.fileUrl options:NSFileCoordinatorReadingWithoutChanges error:nil byAccessor:^(NSURL *newURL) {
                NSFileManager * fileManager = [[NSFileManager alloc] init];
                NSError * error;
                BOOL success = [fileManager copyItemAtURL:file.fileUrl toURL:destURL error:&error];
                
                //BOOL success = [fileManager setUbiquitous:NO itemAtURL:file.fileUrl destinationURL:destURL error:&error];

                if (success) {
                    AppleICloudOrLocalSafeFile *localSafeFile =
                    [[AppleICloudOrLocalSafeFile alloc] initWithDisplayName:[self displayNameFromUrl:destURL] fileUrl:destURL hasUnresolvedConflicts:NO];
                    
                    [updatedFiles addObject:localSafeFile];
                    
                    NSLog(@"Copied %@ to %@ (%d)", file.fileUrl, destURL, [Settings sharedInstance].iCloudOn);
                } else {
                    NSLog(@"Failed to copy %@ to %@: %@", file.fileUrl, destURL, error.localizedDescription);
                }
            }];
        }
        
        self.filesUpdatesListener(updatedFiles);
    });
}

- (NSURL *)getDocURL:(NSString *)filename {
    if ([Settings sharedInstance].iCloudOn) {
        NSURL * docsDir = [_iCloudRoot URLByAppendingPathComponent:@"Documents" isDirectory:YES]; // TODO: Documents?
        return [docsDir URLByAppendingPathComponent:filename];
    } else {
        return [self.localRoot URLByAppendingPathComponent:filename];
    }
}

- (NSString*)docNameFromDisplayName:(NSString*)displayName {
    return [NSString stringWithFormat:@"%@.%@", displayName, FILE_EXTENSION];
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
    
    for (SafeMetaData *entry in [SafesCollection sharedInstance].safes) {
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
                          prefix, FILE_EXTENSION];
        } else {
            newDocName = [NSString stringWithFormat:@"%@ %ld.%@",
                          prefix, (long)docCount, FILE_EXTENSION];
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

- (NSString *)stringForDocumentState:(UIDocumentState)state {
    NSMutableArray * states = [NSMutableArray array];
    if (state == 0) {
        [states addObject:@"Normal"];
    }
    if (state & UIDocumentStateClosed) {
        [states addObject:@"Closed"];
    }
    if (state & UIDocumentStateInConflict) {
        [states addObject:@"In Conflict"];
    }
    if (state & UIDocumentStateSavingError) {
        [states addObject:@"Saving error"];
    }
    if (state & UIDocumentStateEditingDisabled) {
        [states addObject:@"Editing disabled"];
    }
    return [states componentsJoinedByString:@", "];
}

- (void)      list:(NSObject *)parentFolder
    viewController:(UIViewController *)viewController
        completion:(void (^)(NSArray<StorageBrowserItem *> *items, NSError *error))completion {
    // NOTIMPL
    NSLog(@"NOTIMPL: list");
}

- (void)readWithProviderData:(NSObject *)providerData
              viewController:(UIViewController *)viewController
                  completion:(void (^)(NSData *data, NSError *error))completionHandler {
        NSLog(@"NOTIMPL: readWithProviderData");
}

- (void)loadIcon:(NSObject *)providerData viewController:(UIViewController *)viewController
      completion:(void (^)(UIImage *image))completionHandler {
        NSLog(@"NOTIMPL: loadIcon");
}

- (SafeMetaData *)getSafeMetaData:(NSString *)nickName providerData:(NSObject *)providerData {
        NSLog(@"NOTIMPL: getSafeMetaData");
    return nil;
}

@end
