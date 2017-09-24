//
//  AppleICloudOrLocalSafeFile.m
//  Strongbox
//
//  Created by Mark on 24/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "AppleICloudOrLocalSafeFile.h"

@implementation AppleICloudOrLocalSafeFile

- (instancetype)initWithDisplayName:(NSString*)displayName fileUrl:(NSURL*)fileUrl {
    if(self = [super init]) {
        self.displayName = displayName;
        self.fileUrl = fileUrl;
    }
    
    return self;
}

@end
