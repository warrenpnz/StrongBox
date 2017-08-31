//
//  Node.h
//  MacBox
//
//  Created by Mark on 31/08/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Record.h"
#import "NodeFields.h"

@interface Node : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initAsGroup:(NSString *)title
            serializationId:(NSString *)serializationId NS_DESIGNATED_INITIALIZER;

- (instancetype)initAsRecord:(NSString *)title
             serializationId:(NSString *)serializationId
                      fields:(NodeFields*)fields
        originalLinkedRecord:(Record*)originalLinkedRecord NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) BOOL isGroup;
@property (nonatomic, strong, readonly, nonnull) NSString *title;
@property (nonatomic, strong, readonly, nonnull) NSString *serializationId; // Must remain save across serializations
@property (nonatomic, strong, readonly, nonnull) NodeFields *fields;
@property (nonatomic, strong, readonly, nullable) Node* parent;
@property (nonatomic, strong, readonly, nonnull) NSArray<Node*>* children;

- (BOOL)setTitle:(NSString*_Nonnull)title;
- (BOOL)addChild:(Node* _Nonnull)child;
- (void)removeChild:(Node* _Nonnull)child;
- (BOOL)modifyParent:(Node* _Nullable)parent;

// Required for any fields we ignore/are not aware of so that we don't overwrite them on save, we carry them here
@property (nonatomic, strong, readonly, nullable) Record *originalLinkedRecord;

@end
