//
//  Settings.m
//  MacBox
//
//  Created by Mark on 15/08/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "Settings.h"

#define kRevealDetailsImmediately @"revealDetailsImmediately"
#define kFullVersion @"fullVersion"
#define kEndFreeTrialDate @"endFreeTrialDate"
#define kAutoLockTimeout @"autoLockTimeout"

@implementation Settings

+ (instancetype)sharedInstance {
    static Settings *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Settings alloc] init];
    });
    return sharedInstance;
}

- (BOOL)revealDetailsImmediately {
    return [self getBool:kRevealDetailsImmediately];
}

- (void)setRevealDetailsImmediately:(BOOL)value {
    [self setBool:kRevealDetailsImmediately value:value];
}

- (BOOL)fullVersion {
    return [self getBool:kFullVersion];
}

- (void)setFullVersion:(BOOL)value {
    [self setBool:kFullVersion value:value];
}

- (BOOL)freeTrial {
    NSDate* date = self.endFreeTrialDate;
    
    if(date == nil) {
        return YES;
    }
    
    return !([date timeIntervalSinceNow] < 0);
}

- (NSInteger)freeTrialDaysRemaining {
    NSDate* date = self.endFreeTrialDate;
    
    if(date == nil) {
        return -1;
    }
    
    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    NSDateComponents *components = [gregorian components:NSCalendarUnitDay
                                                fromDate:[NSDate date]
                                                  toDate:date
                                                 options:0];
    
    NSInteger days = [components day];
    
    return days;
}

- (NSDate*)endFreeTrialDate {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    return [userDefaults objectForKey:kEndFreeTrialDate];
}

- (void)setEndFreeTrialDate:(NSDate *)endFreeTrialDate {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    [userDefaults setObject:endFreeTrialDate forKey:kEndFreeTrialDate];
    
    [userDefaults synchronize];
}

- (BOOL)getBool:(NSString*)key {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    return [userDefaults boolForKey:key];
}

- (void)setBool:(NSString*)key value:(BOOL)value {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    [userDefaults setBool:value forKey:key];
    
    [userDefaults synchronize];
}

- (NSInteger)autoLockTimeoutSeconds {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    return [userDefaults integerForKey:kAutoLockTimeout];
}

- (void)setAutoLockTimeoutSeconds:(NSInteger)autoLockTimeoutSeconds {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    [userDefaults setInteger:autoLockTimeoutSeconds forKey:kAutoLockTimeout];
    
    [userDefaults synchronize];
}

@end
