//
//  AppleICloudProvider.m
//  Strongbox
//
//  Created by Mark on 20/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "AppleICloudProvider.h"
#import "PasswordSafeUIDocument.h"

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
        
        return self;
    }
    else {
        return nil;
    }
}

- (BOOL)iCloudOn {
    return NO;
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
        // TODO
        return nil;
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
    NSURL * fileURL = [self getDocURL:[self getDocFilename:@"Photo" uniqueInObjects:YES]];
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

- (void)      list:(NSObject *)parentFolder
    viewController:(UIViewController *)viewController
        completion:(void (^)(NSArray<StorageBrowserItem *> *items, NSError *error))completion {
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

- (void)      read:(SafeMetaData *)safeMetaData
    viewController:(UIViewController *)viewController
        completion:(void (^)(NSData *data, NSError *error))completion {
    
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
