//
//  SafeViewModel.m
//  StrongBox
//
//  Created by Mark McGuill on 20/06/2014.
//  Copyright (c) 2014 Mark McGuill. All rights reserved.
//

#import "Model.h"
#import "Utils.h"

@interface Model ()

@property (readonly, strong, nonatomic) PasswordDatabase *passwordDatabase;

@end

@implementation Model {
    id <SafeStorageProvider> _storageProvider;
    LocalDeviceStorageProvider *_local;
    BOOL _isUsingOfflineCache;
    BOOL _isReadOnly;
}

- (instancetype)initWithSafeDatabase:(PasswordDatabase *)passwordDatabase
                            metaData:(SafeMetaData *)metaData
                     storageProvider:(id <SafeStorageProvider>)provider
                   usingOfflineCache:(BOOL)usingOfflineCache
                          isReadOnly:(BOOL)isReadOnly
                localStorageProvider:(LocalDeviceStorageProvider *)local
                               safes:(SafesCollection *)safes; {
    if (self = [super init]) {
        _passwordDatabase = passwordDatabase;
        _metadata = metaData;
        _storageProvider = provider;
        _isUsingOfflineCache = usingOfflineCache;
        _isReadOnly = isReadOnly;
        _local = local;
        _safes = safes;

        return self;
    }
    else {
        return nil;
    }
}

- (BOOL)isCloudBasedStorage {
    return _storageProvider.cloudBased;
}

- (BOOL)isUsingOfflineCache {
    return _isUsingOfflineCache;
}

- (BOOL)isReadOnly {
    return _isReadOnly;
}

- (void)update:(void (^)(NSError *error))handler {
    if (!_isUsingOfflineCache && !_isReadOnly) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void)
        {
            NSError *error;
            NSData *updatedSafeData = [self.passwordDatabase getAsData:&error];
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                if (updatedSafeData == nil) {
                    handler(error);
                    return;
                }

                [_storageProvider update:self.metadata
                                    data:updatedSafeData
                              completion:^(NSError *error) {
                                  [self updateOfflineCacheWithData:updatedSafeData];
                                  handler(error);
                              }];
            });
        });
    }
    else {
        if(_isReadOnly) {
            handler([Utils createNSError:@"You are in read-only mode. You will need to upgrade StrongBox to write to safes." errorCode:-1]);
        }
        else {
            handler([Utils createNSError:@"You are currently in offline mode. The safe cannot be modified." errorCode:-1]);
        }
    }
}

- (void)updateOfflineCache:(void (^)())handler {
    if (self.isCloudBasedStorage && !self.isUsingOfflineCache && _metadata.offlineCacheEnabled) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void)
        {
            NSError *error;
            NSData *updatedSafeData = [self.passwordDatabase getAsData:&error];

            dispatch_async(dispatch_get_main_queue(), ^(void) {
                if (updatedSafeData != nil && _metadata.offlineCacheEnabled) {
                    NSLog(@"Updating offline cache for safe.");
                    [self saveOfflineCacheFile:updatedSafeData safe:_metadata localProvider:_local];
                }

                handler();
            });
        });
    }
}

- (void)updateOfflineCacheWithData:(NSData *)data {
    if (self.isCloudBasedStorage && !self.isUsingOfflineCache && _metadata.offlineCacheEnabled) {
        NSLog(@"Updating offline cache for safe.");
        [self saveOfflineCacheFile:data safe:_metadata localProvider:_local];
    }
}

- (void)saveOfflineCacheFile:(NSData *)data
                        safe:(SafeMetaData *)safe
               localProvider:(LocalDeviceStorageProvider *)localProvider {
    // Store this safe locally
    // Do we already have a file?
    //      Yes-> Overwrite
    //      No-> Create New & Set location

    if (safe.offlineCacheAvailable) {
        [localProvider updateOfflineCachedSafe:safe
                                          data:data
                                viewController:nil
                                    completion:^(NSError *error) {
                                        [self  onStoredOfflineCacheFile:safe
                                        error:error];
                                    }];
    }
    else {
        // Create File Identifer

        safe.offlineCacheFileIdentifier = [[NSUUID alloc] init].UUIDString;

        [localProvider create:safe.offlineCacheFileIdentifier
                         data:data
                 parentFolder:nil
               viewController:nil
                   completion:^(SafeMetaData *metadata, NSError *error) {
                       [self  onStoredOfflineCacheFile:safe
                                      error:error];
                   }];
    }
}

- (void)onStoredOfflineCacheFile:(SafeMetaData *)safe error:(NSError *)error {
    if (error != nil) {
        NSLog(@"Error updating Offline Cache file. %@", error);

        safe.offlineCacheAvailable = NO;
        safe.offlineCacheFileIdentifier = @"";
    }
    else {
        //NSLog(@"Offline cache save with name: %@", safe.offlineCacheFileIdentifier);
        safe.offlineCacheAvailable = YES;
    }

    [self.safes save];
}

- (void)disableAndClearOfflineCache {
    [_local deleteOfflineCachedSafe:_metadata
                         completion:^(NSError *error) {
                             _metadata.offlineCacheEnabled = NO;
                             _metadata.offlineCacheAvailable = NO;
                             _metadata.offlineCacheFileIdentifier = @"";

                             [self.safes save];
                         }];
}

- (void)enableOfflineCache {
    _metadata.offlineCacheAvailable = NO;
    _metadata.offlineCacheEnabled = YES;
    _metadata.offlineCacheFileIdentifier = @"";

    [self.safes save];
}

//////////////////////////////////////////////////////////////////////////////////////////////////////
// Operations

- (Node*)addNewRecord:(Node *_Nonnull)parentGroup {
    NSString* password = [self generatePassword];
    
    NodeFields* fields = [[NodeFields alloc] initWithUsername:@"user123"
                                                          url:@"https://strongboxsafe.com"
                                                     password:password
                                                        notes:@"Sample Database Record. You can have any text here..."
                                              passwordHistory:[[PasswordHistory alloc] init]];
    
    Node* record = [[Node alloc] initAsRecord:@"New Untitled Record" parent:parentGroup fields:fields];
    
    if([parentGroup addChild:record]) {
        return record;
    }
    
    return nil;
}

- (Node*)addNewGroup:(Node *_Nonnull)parentGroup title:(NSString*)title {
    Node* newGroup = [[Node alloc] initAsGroup:title parent:parentGroup];
    if( [parentGroup addChild:newGroup]) {
        return newGroup;
    }

    return nil;
}

- (void)deleteItem:(Node *_Nonnull)child {
    [child.parent removeChild:child];
}

- (BOOL)validateChangeParent:(Node *_Nonnull)parent node:(Node *_Nonnull)node {
    return [node validateChangeParent:parent];
}

- (BOOL)changeParent:(Node *_Nonnull)parent node:(Node *_Nonnull)node {
    return [node changeParent:parent];
}

- (void)defaultLastUpdateFieldsToNow {
    [self.passwordDatabase defaultLastUpdateFieldsToNow];
}

//////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)getMasterPassword {
    return self.passwordDatabase.masterPassword;
}

- (void)setMasterPassword:(NSString *)value {
    self.passwordDatabase.masterPassword = value;
}

-(NSDate*)lastUpdateTime {
    return self.passwordDatabase.lastUpdateTime;
}
  
-(NSString*)lastUpdateUser {
    return self.passwordDatabase.lastUpdateUser;
}

-(NSString*)lastUpdateHost {
    return self.passwordDatabase.lastUpdateHost;
}
  
-(NSString*)lastUpdateApp {
    return self.passwordDatabase.lastUpdateApp;
}
    
-(NSData*)getSafeAsData:(NSError**)error {
    return [self.passwordDatabase getAsData:error];
}

////////////////////////////////////////////////////////////////////////////////////////////
// Convenience  / Helpers

- (NSSet *)getAllExistingUserNames {
    return self.passwordDatabase.getAllExistingUserNames;
}

- (NSSet *)getAllExistingPasswords {
    return self.passwordDatabase.getAllExistingPasswords;
}

- (NSString *)getMostPopularUsername {
    return self.passwordDatabase.getMostPopularUsername;
}

- (NSString *)getMostPopularPassword {
    return self.passwordDatabase.getMostPopularPassword;
}

- (NSString *)generatePassword {
    return [Utils generatePassword];
}

@end
