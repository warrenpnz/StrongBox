//
//  AppleICloudOrLocalSafeFile.h
//  Strongbox
//
//  Created by Mark on 24/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AppleICloudOrLocalSafeFile : NSObject

- (instancetype _Nullable )init NS_UNAVAILABLE;
- (instancetype _Nullable )initWithDisplayName:(NSString*_Nonnull)displayName fileUrl:(NSURL*_Nonnull)fileUrl NS_DESIGNATED_INITIALIZER;

@property (nonatomic, nonnull) NSString* displayName;
@property (nonatomic, nonnull) NSURL* fileUrl;

@end
