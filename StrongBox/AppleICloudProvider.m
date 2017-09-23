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
#import "iCloud.h"
#import "Utils.h"

#define FILE_EXTENSION @"dat"

// Add new private variables to interface
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

- (BOOL)iCloudOn {
    return YES;
}

- (void)    create:(NSString *)nickName
              data:(NSData *)data
      parentFolder:(NSObject *)parentFolder
    viewController:(UIViewController *)viewController
        completion:(void (^)(SafeMetaData *metadata, NSError *error))completion {
    NSString* filename = [NSString stringWithFormat:@"%@.dat", nickName]; // TODO: Conflicts?
    [[iCloud sharedCloud] saveAndCloseDocumentWithName:filename withContent:data completion:^(UIDocument *cloudDocument, NSData *documentData, NSError *error) {
        if (error == nil) {
            SafeMetaData *metadata = [[SafeMetaData alloc] initWithNickName:nickName
                                                            storageProvider:self.storageId
                                                                   fileName:cloudDocument.fileURL.lastPathComponent
                                                             fileIdentifier:cloudDocument.fileURL.absoluteString];
    
            completion(metadata, error);
        }
        else {
            NSLog(@"iCloud create failed: %@", error);
            completion(nil, error);
        }
    }];
}

- (void)      read:(SafeMetaData *)safeMetaData
    viewController:(UIViewController *)viewController
        completion:(void (^)(NSData *data, NSError *error))completion {
    BOOL fileExists = [[iCloud sharedCloud] doesFileExistInCloud:safeMetaData.fileName];
    if (!fileExists) {
        completion(nil, [Utils createNSError:@"Could not find the document on iCloud." errorCode:-5]);
    }
    else {
        [[iCloud sharedCloud] retrieveCloudDocumentWithName:safeMetaData.fileName completion:^(UIDocument *cloudDocument, NSData *documentData, NSError *error) {
            if (!error) {
                completion(documentData, error);
            }
            else {
                completion(nil, error);
            }
        }];
    }
}

- (void)update:(SafeMetaData *)safeMetaData
          data:(NSData *)data
    completion:(void (^)(NSError *error))completion {
    [[iCloud sharedCloud] saveAndCloseDocumentWithName:safeMetaData.fileName withContent:data completion:^(UIDocument *cloudDocument, NSData *documentData, NSError *error) {
        NSLog(@"Updated! [%@]", error);
        
        completion(error);
    }];
}

- (void)delete:(SafeMetaData*)safeMetaData
    completion:(void (^)(NSError *error))completion {
    if(safeMetaData.storageProvider != kiCloud) {
        NSLog(@"Safe is not an Apple iCloud safe!");
        return;
    }
    
    [[iCloud sharedCloud] deleteDocumentWithName:safeMetaData.fileName completion:^(NSError *error) {
        completion(error);
    }];
}






















- (NSMetadataQuery *)documentQuery {
    NSMetadataQuery * query = [[NSMetadataQuery alloc] init];
    if (query) {
        
        // Search documents subdir only
        [query setSearchScopes:[NSArray arrayWithObject:NSMetadataQueryUbiquitousDocumentsScope]];
        
        // Add a predicate for finding the documents
//        NSString * filePattern = [NSString stringWithFormat:@"*", PTK_EXTENSION];
//        [query setPredicate:[NSPredicate predicateWithFormat:@"%K LIKE %@",
//                             NSMetadataItemFSNameKey, filePattern]];
        
    }
    
    return query;
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
    
}

- (void)loadIcon:(NSObject *)providerData viewController:(UIViewController *)viewController
      completion:(void (^)(UIImage *image))completionHandler {
    
}

- (SafeMetaData *)getSafeMetaData:(NSString *)nickName providerData:(NSObject *)providerData {
    return nil;
}




- (BOOL)urlIsDirectory:(NSURL *)url {
    NSNumber *isDirectory;
    
    BOOL success = [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    
    return (success && [isDirectory boolValue]);
}

@end
