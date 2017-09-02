//
//  NodeFields.m
//  MacBox
//
//  Created by Mark on 31/08/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "NodeFields.h"

@implementation NodeFields

- (instancetype _Nullable)init {
    return [self initWithUsername:@"" url:@"" password:@"" notes:@""];
}

- (instancetype _Nullable)initWithUsername:(NSString*_Nonnull)username
                                       url:(NSString*_Nonnull)url
                                  password:(NSString*_Nonnull)password
                                     notes:(NSString*_Nonnull)notes {
    if (self = [super init]) {
        self.username = username;
        self.url = url;
        self.password = password;
        self.notes = notes;
    }
    
    return self;
}

@end
