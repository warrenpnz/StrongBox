//
//  Node.m
//  MacBox
//
//  Created by Mark on 31/08/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "Node.h"

@interface Node ()

@property (nonatomic, strong) NSString *uniqueRecordId;
@property (nonatomic, strong) NSMutableArray<Node*> *mutableChildren;

@end

@implementation Node

- (instancetype)initAsRoot {
    if(self = [super init]) {
        _isGroup = YES;
        _parent = nil;
        _title = @"<ROOT>";
        _mutableChildren = [NSMutableArray array];
        return self;
    }
    
    return self;
}

- (instancetype _Nullable )initAsGroup:(NSString *_Nonnull)title
                                parent:(Node* _Nonnull)parent {
    if(self = [super init]) {
        for (Node* child in parent.children) {
            if (child.isGroup && [child.title isEqualToString:title]) {
                NSLog(@"Cannot create group as parent already has a group with this title. [%@-%@]", parent.title, title);
                return nil;
            }
        }
        
        _parent = parent;
        _title = title;
        _isGroup = YES;
        _mutableChildren = [NSMutableArray array];
        _fields = [[NodeFields alloc] init];

        return self;
    }
    
    return self;
}

- (instancetype _Nullable )initAsRecord:(NSString *_Nonnull)title
                                 parent:(Node* _Nonnull)parent
                                 fields:(NodeFields*_Nonnull)fields {
    if(self = [super init]) {
        _parent = parent;
        _title = title;
        _isGroup = NO;
        _mutableChildren = nil;
        _uniqueRecordId = [Node generateUniqueId];
        _fields = [[NodeFields alloc] init];

        return self;
    }
    
    return self;
}

- (instancetype _Nullable )initWithExistingPasswordSafe3Record:(Record*_Nonnull)record
                                                        parent:(Node* _Nonnull)parent {
    if(self = [super init]) {
        _isGroup = NO;
        _mutableChildren = nil;
        _fields = [[NodeFields alloc] init];
        _parent = parent;

        _title = record.title;
        self.fields.username = record.username;
        self.fields.password = record.password;
        self.fields.url = record.url;
        self.fields.notes = record.notes;
        _uniqueRecordId = record.uuid && record.uuid.length ? record.uuid : [Node generateUniqueId];

        return self;
    }
    
    return self;
}

- (NSArray<Node*>*)children {
    return self.isGroup ? _mutableChildren : [NSArray array];
}

- (BOOL)setTitle:(NSString*_Nonnull)title {
    if(self.isGroup) {
        for (Node* child in self.parent.children) {
            if (child.isGroup && [child.title isEqualToString:title]) {
                NSLog(@"Cannot create group as parent already has a group with this title. [%@-%@]", self.parent.title, title);
                return NO;
            }
        }
    }
    
    self.title = title;
    return YES;
}

- (BOOL)validateAddChild:(Node* _Nonnull)node {
    if(node.isGroup) {
        for (Node* child in self.children) {
            if (child.isGroup && [child.title isEqualToString:node.title]) {
                NSLog(@"Cannot add child group as we already have a group with this title. [%@-%@]", self.title, node.title);
                return NO;
            }
        }
    }
    
    return YES;
}

- (BOOL)addChild:(Node* _Nonnull)node {
    if(![self validateAddChild:node]) {
        return NO;
    }

    [_mutableChildren addObject:node];

    return YES;
}

- (void)removeChild:(Node* _Nonnull)node {
    [_mutableChildren removeObject:node];
}

- (NSString*)serializationId {
    NSString *identifier;
    if(self.isGroup) {
        NSArray<NSString*> *titleHierarchy = [Node getTitleHierarchy:self];

        identifier = [titleHierarchy componentsJoinedByString:@":"];
    }
    else {
        identifier = self.uniqueRecordId;
    }
    
    return [NSString stringWithFormat:@"%@%@", self.isGroup ? @"G" : @"R",  identifier];
}

- (Node*)getChildGroupWithTitle:(NSString*)title {
    for(Node* child in self.children) {
        if(child.isGroup && [child.title isEqualToString:title]) {
            return child;
        }
    }
    
    return nil;
}

+ (NSString*)generateUniqueId {
    NSUUID *unique = [[NSUUID alloc] init];
    
    return unique.UUIDString;
}

+ (NSArray<NSString*>*)getTitleHierarchy:(Node*)node {
    if(node.parent != nil) {
        NSMutableArray<NSString*> *parentHierarchy = [NSMutableArray arrayWithArray:[Node getTitleHierarchy:node.parent]];
        return parentHierarchy;
    }
    else {
        return [NSMutableArray array];
    }
}


@end
