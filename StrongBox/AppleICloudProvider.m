//
//  AppleICloudProvider.m
//  Strongbox
//
//  Created by Mark on 20/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "AppleICloudProvider.h"
#import "PasswordSafeUIDocument.h"
#import "Strongbox.h"
#import "Utils.h"
#import "SafesCollection.h"
#import "Settings.h"

#define FILE_EXTENSION @"psafe3"

// TODO: Add new private variables to interface
NSURL * _localRoot;

@implementation AppleICloudProvider

+ (instancetype)sharedInstance {
    static AppleICloudProvider *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AppleICloudProvider alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _displayName = @"iCloud";
        _icon = @"icloud-32";
        _storageId = kiCloud;
        _cloudBased = YES;
        _providesIcons = NO;
        _browsable = NO;
        
        return self;
    }
    else {
        return nil;
    }
}

// TODO: Add new private instance variable
NSURL * _iCloudRoot;

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

#pragma mark Helpers

- (BOOL)iCloudOn {
    return [Settings sharedInstance].iCloudOn;
}

- (NSURL *)localRoot {
    if (_localRoot != nil) {
        return _localRoot;
    }
    
    NSArray * paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    _localRoot = [paths objectAtIndex:0];
    return _localRoot;
}

- (NSURL *)getDocURL:(NSString *)filename {
    if ([self iCloudOn]) {
        NSURL * docsDir = [_iCloudRoot URLByAppendingPathComponent:@"Documents" isDirectory:YES]; // TODO: Documents?
        return [docsDir URLByAppendingPathComponent:filename];
    } else {
        return [self.localRoot URLByAppendingPathComponent:filename];
    }
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
        
        // Look for an existing document with the same name. If one is
        // found, increment the docCount value and try again.
        BOOL nameExists;
        if (uniqueInObjects) {
            nameExists = [self docNameExistsInObjects:newDocName];
        } else {
            // TODO
            return nil;
        }
        if (!nameExists) {
            break;
        } else {
            docCount++;
        }
        
    }
    
    return newDocName;
}




- (void)    create:(NSString *)nickName
              data:(NSData *)data
      parentFolder:(NSObject *)parentFolder
    viewController:(UIViewController *)viewController
        completion:(void (^)(SafeMetaData *metadata, NSError *error))completion {

    NSURL * fileURL = [self getDocURL:[self getDocFilename:nickName uniqueInObjects:YES]];
    
    NSLog(@"Want to create file at %@", fileURL);
    
    PasswordSafeUIDocument * doc = [[PasswordSafeUIDocument alloc] initWithData:data fileUrl:fileURL];
    
    [doc saveToURL:fileURL forSaveOperation:UIDocumentSaveForCreating completionHandler:^(BOOL success) {
        if (!success) {
            NSLog(@"Failed to create file at %@", fileURL);
            completion(nil, [Utils createNSError:@"Failed to create file" errorCode:-5]);
            return;
        }
        
        NSLog(@"File created at %@", fileURL);
    
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

        NSLog(@"Loaded File URL: %@", [doc.fileURL lastPathComponent]);

        completion(doc.data, nil);
    }];
}

- (void)update:(SafeMetaData *)safeMetaData
          data:(NSData *)data
    completion:(void (^)(NSError *error))completion {
    NSLog(@"NOTIMPL: Update");
}

- (void)delete:(SafeMetaData*)safeMetaData
    completion:(void (^)(NSError *error))completion {
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
                                             // Simple delete to start
                                             NSFileManager* fileManager = [[NSFileManager alloc] init];
                                             [fileManager removeItemAtURL:entry.fileURL error:nil];
                                         }];
    });
    
    // Fixup view
    [self removeEntryWithURL:entry.fileURL];
}



- (void)      list:(NSObject *)parentFolder
    viewController:(UIViewController *)viewController
        completion:(void (^)(NSArray<StorageBrowserItem *> *items, NSError *error))completion {
    // NOTIMPL
    
    
//    if([self iCloudOn]) {
//        NSLog(@"Starting to watch iCloud dir...");
//
//        NSMetadataQuery * query = [self documentQuery];
//
//        NSNotificationCenter * __weak center = [NSNotificationCenter defaultCenter];
//
//        id __block token = [center addObserverForName:NSMetadataQueryDidFinishGatheringNotification
//                                                          object:nil
//                                                           queue:nil
//                                                      usingBlock:^(NSNotification * _Nonnull note) {
//                                                               // Always disable updates while processing results
//                                                               [query disableUpdates];
//
//                                                          _iCloudURLs = [NSMutableArray array];
//
//                                                               // The query reports all files found, every time.
//                                                               NSArray * queryResults = [query results];
//                                                               for (NSMetadataItem * result in queryResults) {
//                                                                   NSURL * fileURL = [result valueForAttribute:NSMetadataItemURLKey];
//                                                                   NSNumber * aBool = nil;
//
//                                                                   NSLog(@"Found File: %@",fileURL);
//
//                                                                   // Don't include hidden files
//                                                                   [fileURL getResourceValue:&aBool forKey:NSURLIsHiddenKey error:nil];
//                                                                   if (aBool && ![aBool boolValue]) {
//                                                                       [_iCloudURLs addObject:fileURL];
//                                                                   }
//
//                                                               }
//
//                                                               NSLog(@"Found %lu iCloud files.", (unsigned long)_iCloudURLs.count);
//                                                               _iCloudURLsReady = YES;
//
//                                                               NSLog(@"No longer watching iCloud dir...");
//
//                                                                [center removeObserver:token];
//                                                               [query stopQuery];
//                                                           }];
//
//        (void)token; // Compiler warning
//        [query startQuery];
//    }
//    else {
//        NSArray * localDocuments = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.localRoot includingPropertiesForKeys:nil options:0 error:nil];
//
//        NSLog(@"Found %lu local files.", (unsigned long)localDocuments.count);
//
//        NSMutableArray<StorageBrowserItem *> *ret = [[NSMutableArray alloc]initWithCapacity:localDocuments.count];
//
//        for (int i=0; i < localDocuments.count; i++) {
//            NSURL * fileURL = [localDocuments objectAtIndex:i];
//            NSLog(@"Found local file: %@", fileURL);
//
//            StorageBrowserItem *mapped = [StorageBrowserItem alloc];
//
//            mapped.name = fileURL.lastPathComponent;
//            mapped.folder = [self urlIsDirectory:fileURL]; //.hasDirectoryPath;
//            mapped.providerData = fileURL;
//
//            [ret addObject:mapped];
//        }
//    }
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
//
//- (BOOL)urlIsDirectory:(NSURL *)url {
//    NSNumber *isDirectory;
//
//    BOOL success = [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
//
//    return (success && [isDirectory boolValue]);
//}

@end
