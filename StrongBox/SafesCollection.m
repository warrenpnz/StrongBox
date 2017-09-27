//
//  SafesCollection.m
//  StrongBox
//
//  Created by Mark on 22/11/2014.
//  Copyright (c) 2014 Mark McGuill. All rights reserved.
//

#import "SafesCollection.h"
#import "SafeMetaData.h"
#import "Utils.h"

@interface SafesCollection ()

@property (atomic, nonnull) NSRecursiveLock *lock;
@property (nonatomic, nonnull) NSMutableDictionary<NSString*, SafeMetaData*> *theCollection;
@property (nonatomic, nonnull, readonly) NSArray<SafeMetaData*> *snapshot;

@end

@implementation SafesCollection

+ (instancetype)sharedInstance {
    static SafesCollection *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SafesCollection alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        self.lock = [[NSRecursiveLock alloc] init];
        self.theCollection = [[NSMutableDictionary alloc] init];
        
        [self load];
        
        return self;
    }
    else {
        return nil;
    }
}

- (NSArray<SafeMetaData *> *)snapshot {
    [self.lock lock];

    NSArray<SafeMetaData*> *copy = [self.theCollection.allValues copy];

    [self.lock unlock];

    return copy;
}

- (void)removeSafe:(NSString*)safeName {
    [self.lock lock];
    
    [self.theCollection removeObjectForKey:safeName];
    [self save];
    
    [self.lock unlock];

}

- (BOOL)add:(SafeMetaData *)safe {
    [self.lock lock];
    
    if ([self.theCollection objectForKey:safe.nickName] || ![self isValidNickName:safe.nickName]) {
        NSLog(@"Cannot Save Safe, as existing Safe exists with this nick name, or the name is invalid!");
        return NO;
    }
    
    [self.theCollection setObject:safe forKey:safe.nickName];
    [self save];
    
    [self.lock unlock];
    
    return YES;
}

//////////////////////////////////////////////////////////////////////////////////////////

- (void)load {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSArray *existingSafes = [userDefaults arrayForKey:@"safes"];
    
    [self.lock lock];
    
    for (NSDictionary *safeDict in existingSafes) {
        SafeMetaData *safe = [SafeMetaData fromDictionary:safeDict];
        
        // TODO: Failure should only ever happen on initial load of 1.12.0 where someone has somehow got 2 identically named safes...
        // virtually impossible
        
        if(![self add:safe]) {
            safe.nickName = [[NSUUID UUID] UUIDString];
            [self add:safe];
        }
    }
    
    [self.lock unlock];
}

- (void)save {
    [self.lock lock];
    
    NSMutableArray *sfs = [NSMutableArray arrayWithCapacity:(self.snapshot).count ];
    
    for (SafeMetaData *s in self.theCollection.allValues) {
        [sfs addObject:s.toDictionary];
    }
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:sfs forKey:@"safes"];
    [userDefaults synchronize];
    
    [self.lock unlock];
}

/////////////////////////////////////////////////////////////////////////////////////////

- (NSArray<SafeMetaData*>*)sortedSafes {
    return [self.snapshot sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        NSString* str1 = ((SafeMetaData*)obj1).nickName;
        NSString* str2 = ((SafeMetaData*)obj2).nickName;
        
        return [Utils finderStringCompare:str1 string2:str2];
    }];
}

- (NSSet *)getAllNickNamesLowerCase {
    NSMutableSet *set = [[NSMutableSet alloc] initWithCapacity:self.snapshot.count];
    
    for (SafeMetaData *safe in self.snapshot) {
        [set addObject:(safe.nickName).lowercaseString];
    }
    
    return set;
}

- (NSArray<SafeMetaData*>*)getSafesOfProvider:(StorageProvider)storageProvider {
    return [self.snapshot filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        SafeMetaData* item = (SafeMetaData*)evaluatedObject;
        return item.storageProvider == storageProvider;
    }]];
}

+ (NSString *)sanitizeSafeNickName:(NSString *)string {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    trimmed = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet controlCharacterSet]] componentsJoinedByString:@""];
    trimmed = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet illegalCharacterSet]] componentsJoinedByString:@""];
    trimmed = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet nonBaseCharacterSet]] componentsJoinedByString:@""];
    trimmed = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"±|/\\`~@<>:;£$%^&()=+{}[]!\"|?*"]] componentsJoinedByString:@""];
    
    return trimmed;
}

- (BOOL)isValidNickName:(NSString *)nickName {
    NSString *sanitized = [SafesCollection sanitizeSafeNickName:nickName];
    
    return [sanitized isEqualToString:nickName] && nickName.length > 0 && ![[self getAllNickNamesLowerCase] containsObject:nickName.lowercaseString];
}

- (BOOL)safeWithTouchIdIsAvailable {
    NSArray<SafeMetaData*> *touchIdEnabledSafes = [self.snapshot filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        SafeMetaData *safe = (SafeMetaData*)evaluatedObject;
        return safe.isTouchIdEnabled && safe.isEnrolledForTouchId;
    }]];
    
    return [touchIdEnabledSafes count] > 0;
}

@end
