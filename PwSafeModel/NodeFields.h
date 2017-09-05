//
//  NodeFields.h
//  MacBox
//
//  Created by Mark on 31/08/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PasswordHistory.h"

@interface NodeFields : NSObject

- (instancetype _Nullable)init;

- (instancetype _Nullable)initWithUsername:(NSString*_Nonnull)username
                                       url:(NSString*_Nonnull)url
                                  password:(NSString*_Nonnull)password
                                     notes:(NSString*_Nonnull)notes
                           passwordHistory:(PasswordHistory*_Nonnull)passwordHistory NS_DESIGNATED_INITIALIZER;

@property (nonatomic, strong, nonnull) NSString *password;
@property (nonatomic, strong, nonnull) NSString *username;
@property (nonatomic, strong, nonnull) NSString *url;
@property (nonatomic, strong, nonnull) NSString *notes;
@property (nonatomic, retain, nonnull) PasswordHistory *passwordHistory;

@end
