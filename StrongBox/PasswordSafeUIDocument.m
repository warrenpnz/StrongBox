//
//  PasswordSafeUIDocument.m
//  Strongbox
//
//  Created by Mark on 20/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "PasswordSafeUIDocument.h"

@implementation PasswordSafeUIDocument

- (instancetype)initWithData:(NSData*)data fileUrl:(NSURL*)fileUrl {
    if(self = [super initWithFileURL:fileUrl]) {
        self.data = data;
    }
    
    return self;
}

- (id)contentsForType:(NSString *)typeName error:(NSError * _Nullable __autoreleasing *)outError {
    return self.data; // [self.passwordDatabase getAsData:outError];
}

- (BOOL)loadFromContents:(id)contents ofType:(NSString *)typeName error:(NSError * _Nullable __autoreleasing *)outError {
//    self.passwordDatabase =
//        [[PasswordDatabase alloc] initExistingWithDataAndPassword:contents password:@"Todo" error:outError]; // TODO
//
    
    self.data = contents;
    
    return YES;
}

@end
