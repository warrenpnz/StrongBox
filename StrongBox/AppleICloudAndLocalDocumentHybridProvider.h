//
//  AppleICloudProvider.h
//  Strongbox
//
//  Created by Mark on 20/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SafeStorageProvider.h"
#import "AppleICloudOrLocalSafeFile.h"
    
@interface AppleICloudAndLocalDocumentHybridProvider : NSObject <SafeStorageProvider>

+ (instancetype)sharedInstance;

- (void)initializeiCloudAccessWithCompletion:(void (^)(BOOL available)) completion;

- (void)monitorICloudFiles; // TODO: Is there a Point to this?

- (void)migrateLocalToiCloud;
- (void)migrateiCloudToLocal;

@property (strong, nonatomic, readonly) NSString *displayName;
@property (strong, nonatomic, readonly) NSString *icon;
@property (nonatomic, readonly) StorageProvider storageId;
@property (nonatomic, readonly) BOOL cloudBased;
@property (nonatomic, readonly) BOOL providesIcons;
@property (nonatomic, readonly) BOOL browsable;

@property (nonatomic, copy) void (^filesUpdatesListener)(NSArray<AppleICloudOrLocalSafeFile*>* filesMetadata);

- (void)delete:(SafeMetaData*)safeMetaData
    completion:(void (^)(NSError *error))completion;

@end
