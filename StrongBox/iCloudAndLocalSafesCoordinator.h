//
//  Hybrid.h
//  Strongbox
//
//  Created by Mark on 25/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SafeStorageProvider.h"
#import "AppleICloudOrLocalSafeFile.h"

@interface iCloudAndLocalSafesCoordinator : NSObject

+ (instancetype)sharedInstance;

- (void)initializeiCloudAccessWithCompletion:(void (^)(BOOL available)) completion;
- (void)startCoordinating;

@property (nonatomic, copy) void (^updateSafesCollection)(void);
@property (nonatomic, copy) void (^showMigrationUi)(BOOL show);

// Name ok?
- (NSURL*)getDocURL:(NSString *)filename;
- (NSString*)getDocFilename:(NSString *)prefix uniqueInObjects:(BOOL)uniqueInObjects;

- (void)migrateLocalToiCloud:(void (^)(BOOL show)) completion;
- (void)migrateiCloudToLocal:(void (^)(BOOL show)) completion;

@end
