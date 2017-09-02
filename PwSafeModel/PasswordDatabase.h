//
//  PasswordDatabase.h
//
//
//  Created by Mark on 01/09/2015.
//
//

#ifndef _PasswordDatabase_h
#define _PasswordDatabase_h

#import <Foundation/Foundation.h>
#import "SafeItemViewModel.h"
#import "Node.h"

@interface PasswordDatabase : NSObject

+ (BOOL)isAValidSafe:(NSData *)candidate;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initNewWithoutPassword;
- (instancetype)initNewWithPassword:(NSString *)password;
- (instancetype)initExistingWithDataAndPassword:(NSData *)data password:(NSString *)password error:(NSError **)ppError;

- (NSData*)getAsData:(NSError**)error;

@property (nonatomic, readonly) Node* rootGroup;
@property (nonatomic) NSInteger keyStretchIterations;
@property (nonatomic, retain) NSString *masterPassword;
@property (nonatomic, readonly) NSDate *lastUpdateTime;
@property (nonatomic, readonly) NSString *lastUpdateUser;
@property (nonatomic, readonly) NSString *lastUpdateHost;
@property (nonatomic, readonly) NSString *lastUpdateApp;

// Helpers

@property (getter = getAllExistingUserNames, readonly, copy) NSSet *allExistingUserNames;
@property (getter = getAllExistingPasswords, readonly, copy) NSSet *allExistingPasswords;
@property (getter = getMostPopularUsername, readonly, copy) NSString *mostPopularUsername;
@property (getter = getMostPopularPassword, readonly, copy) NSString *mostPopularPassword;
@property (readonly, copy) NSString *generatePassword;

@end

#endif // ifndef _PasswordDatabase_h
