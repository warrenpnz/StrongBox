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
        _icon = @"iCloud"; // TODO:
        _storageId = kiCloud;
        _cloudBased = YES;
        _providesIcons = YES;
        _browsable = YES;
        
        
        [self initializeiCloudAccessWithCompletion:^(BOOL available) {
            _iCloudAvailable = available;
            //
            //        // TODO
            //
            //        if (![self iCloudOn]) {
            //            [self loadLocal];
            //        }
        }];

        return self;
    }
    else {
        return nil;
    }
}

- (BOOL)iCloudOn {
    return YES;
}

// TODO: Add new private instance variable
NSURL * _iCloudRoot;
BOOL _iCloudAvailable;

// Add to end of "Helpers" section
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
        NSURL * docsDir = [_iCloudRoot URLByAppendingPathComponent:@"Documents" isDirectory:YES];
        return [docsDir URLByAppendingPathComponent:filename];
    } else {
        return [self.localRoot URLByAppendingPathComponent:filename];
    }
}

- (BOOL)docNameExistsInObjects:(NSString *)docName {
//    BOOL nameExists = NO;
//    for (PTKEntry * entry in _objects) {
//        if ([[entry.fileURL lastPathComponent] isEqualToString:docName]) {
//            nameExists = YES;
//            break;
//        }
//    }
//    return nameExists;

    return NO; // TODO
}

- (NSString*)getDocFilename:(NSString *)prefix uniqueInObjects:(BOOL)uniqueInObjects {
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
    
    // Determine a unique filename to create
    NSURL * fileURL = [self getDocURL:[self getDocFilename:nickName uniqueInObjects:YES]];
    NSLog(@"Want to create file at %@", fileURL);
    
    // Create new document and save to the filename
    
    PasswordSafeUIDocument * doc = [[PasswordSafeUIDocument alloc] initWithData:data fileUrl:fileURL];
    [doc saveToURL:fileURL forSaveOperation:UIDocumentSaveForCreating completionHandler:^(BOOL success) {
        if (!success) {
            NSLog(@"Failed to create file at %@", fileURL);
            return;
        }
        
        NSLog(@"File created at %@", fileURL);
        
        //        NSURL * fileURL = doc.fileURL;
        //        UIDocumentState state = doc.documentState;
        
        
        SafeMetaData *metadata = [[SafeMetaData alloc] initWithNickName:nickName storageProvider:self.storageId offlineCacheEnabled:NO];
        
        metadata.fileIdentifier = fileURL.absoluteString;
        metadata.fileName = fileURL.lastPathComponent;
        
        completion(metadata, nil);
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

BOOL _iCloudURLsReady;
NSMutableArray * _iCloudURLs;

- (void)      list:(NSObject *)parentFolder
    viewController:(UIViewController *)viewController
        completion:(void (^)(NSArray<StorageBrowserItem *> *items, NSError *error))completion {
    if([self iCloudOn]) {
        NSLog(@"Starting to watch iCloud dir...");
        
        NSMetadataQuery * query = [self documentQuery];
        
        NSNotificationCenter * __weak center = [NSNotificationCenter defaultCenter];

        id __block token = [center addObserverForName:NSMetadataQueryDidFinishGatheringNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification * _Nonnull note) {
                                                               // Always disable updates while processing results
                                                               [query disableUpdates];
                                                          
                                                          _iCloudURLs = [NSMutableArray array];
                                                               
                                                               // The query reports all files found, every time.
                                                               NSArray * queryResults = [query results];
                                                               for (NSMetadataItem * result in queryResults) {
                                                                   NSURL * fileURL = [result valueForAttribute:NSMetadataItemURLKey];
                                                                   NSNumber * aBool = nil;
                                                                   
                                                                   NSLog(@"Found File: %@",fileURL);
                                                                   
                                                                   // Don't include hidden files
                                                                   [fileURL getResourceValue:&aBool forKey:NSURLIsHiddenKey error:nil];
                                                                   if (aBool && ![aBool boolValue]) {
                                                                       [_iCloudURLs addObject:fileURL];
                                                                   }
                                                                   
                                                               }
                                                               
                                                               NSLog(@"Found %lu iCloud files.", (unsigned long)_iCloudURLs.count);
                                                               _iCloudURLsReady = YES;

                                                               NSLog(@"No longer watching iCloud dir...");
                                                          
                                                                [center removeObserver:token];
                                                               [query stopQuery];
                                                           }];
        
        (void)token; // Compiler warning
        [query startQuery];
    }
    else {
        NSArray * localDocuments = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.localRoot includingPropertiesForKeys:nil options:0 error:nil];

        NSLog(@"Found %lu local files.", (unsigned long)localDocuments.count);
        
        NSMutableArray<StorageBrowserItem *> *ret = [[NSMutableArray alloc]initWithCapacity:localDocuments.count];

        for (int i=0; i < localDocuments.count; i++) {
            NSURL * fileURL = [localDocuments objectAtIndex:i];
            NSLog(@"Found local file: %@", fileURL);
        
            StorageBrowserItem *mapped = [StorageBrowserItem alloc];
            
            mapped.name = fileURL.lastPathComponent;
            mapped.folder = [self urlIsDirectory:fileURL]; //.hasDirectoryPath;
            mapped.providerData = fileURL;
            
            [ret addObject:mapped];
        }
    }
}

- (void)      read:(SafeMetaData *)safeMetaData
    viewController:(UIViewController *)viewController
        completion:(void (^)(NSData *data, NSError *error))completion {
    NSURL *fileUrl = [NSURL URLWithString:safeMetaData.fileIdentifier];
    
    PasswordSafeUIDocument *document = [[PasswordSafeUIDocument alloc] initWithFileURL:fileUrl];
    [document openWithCompletionHandler:^(BOOL success) {
        NSLog(@"Success Open");
    
        completion(document.data, nil);
    }];
}

- (void)update:(SafeMetaData *)safeMetaData
          data:(NSData *)data
    completion:(void (^)(NSError *error))completion {
    
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
