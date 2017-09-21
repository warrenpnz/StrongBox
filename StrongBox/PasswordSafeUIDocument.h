//
//  PasswordSafeUIDocument.h
//  Strongbox
//
//  Created by Mark on 20/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PasswordDatabase.h"

@interface PasswordSafeUIDocument : UIDocument

- (instancetype _Nullable)initWithData:(NSData* _Nonnull)data fileUrl:(NSURL*_Nonnull)fileUrl NS_DESIGNATED_INITIALIZER;

@property (nonatomic) NSData * _Nonnull data;

@end
