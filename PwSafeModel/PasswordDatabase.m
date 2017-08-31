//
//  PasswordDatabase.m
//
//
//  Created by Mark on 01/09/2015.
//
//

#import <Foundation/Foundation.h>
#import "PasswordDatabase.h"
#import "Utils.h"
#import "SafeTools.h"
#import <CommonCrypto/CommonHMAC.h>

#define kStrongBoxUser @"StrongBox User"

//////////////////////////////////////////////////////////////////////////////////////////////////////

@interface PasswordDatabase ()

@property (nonatomic, strong) NSMutableArray<Field*> *dbHeaderFields;
@property (nonatomic, strong) NSMutableArray<Record*> *records;
@property (nonatomic) NSInteger keyStretchIterations;
@property (nonatomic, strong) NSArray<Group*> *allGroupsCache;  // PERF/MEM

@end

@implementation PasswordDatabase

+ (BOOL)isAValidSafe:(NSData *)candidate {
    PasswordSafe3Header header;
    NSUInteger numBlocks;
    
    return [SafeTools isAValidSafe:candidate header:&header numBlocks:&numBlocks];
}

- (instancetype)initNewWithoutPassword {
    return [self initNewWithPassword:nil];
}

- (instancetype)initNewWithPassword:(NSString *)password {
    if (self = [super init]) {
        _dbHeaderFields = [[NSMutableArray alloc] init];
        
        // Version
        
        unsigned char versionBytes[2];
        versionBytes[0] = 0x0B;
        versionBytes[1] = 0x03;
        NSData *versionData = [[NSData alloc] initWithBytes:&versionBytes length:2];
        Field *version = [[Field alloc] initNewDbHeaderField:HDR_VERSION withData:versionData];
        [_dbHeaderFields addObject:version];
        
        // UUID
        
        NSUUID *unique = [[NSUUID alloc] init];
        unsigned char bytes[16];
        [unique getUUIDBytes:bytes];
        Field *uuid = [[Field alloc] initNewDbHeaderField:HDR_UUID withData:[[NSData alloc] initWithBytes:bytes length:16]];
        [_dbHeaderFields addObject:uuid];
        
        [self setLastUpdateTime];
        [self setLastUpdateUser];
        [self setLastUpdateHost];
        [self setLastUpdateApp];
        
        _records = [[NSMutableArray alloc] init];
        _keyStretchIterations = DEFAULT_KEYSTRETCH_ITERATIONS;
        
        self.masterPassword = password;
        return self;
    }
    else {
        return nil;
    }
}

- (instancetype)initExistingWithDataAndPassword:(NSData *)safeData password:(NSString *)password error:(NSError **)ppError {
    if (self = [super init]) {
        PasswordSafe3Header header;
        NSUInteger numBlocks;
        
        if (![SafeTools isAValidSafe:safeData header:&header numBlocks:&numBlocks]) {
            NSLog(@"Not a valid safe!");
            
            if (ppError != nil) {
                *ppError = [Utils createNSError:@"This is not a valid Password Safe (Invalid Format)." errorCode:-1];
            }
            
            return nil;
        }
        
        NSData *pBar;
        
        if (![SafeTools checkPassword:&header password:password pBar:&pBar]) {
            NSLog(@"Invalid password!");
            
            if (ppError != nil) {
                *ppError = [Utils createNSError:@"The password is incorrect." errorCode:-2];
            }
            
            return nil;
        }
        
        // We need to get K and L now...
        
        //NSLog(@"%@", pBar);
        
        NSData *K;
        NSData *L;
        
        [SafeTools getKandL:pBar header:header K_p:&K L_p:&L];
        
        //NSLog(@"INIT K: %@", K);
        //NSLog(@"INIT L: %@", L);
        
        NSData *decData = [SafeTools decryptBlocks:K ct:(unsigned char *)&safeData.bytes[SIZE_OF_PASSWORD_SAFE_3_HEADER] iv:header.iv numBlocks:numBlocks];
        
        //NSLog(@"DEC: %@", decData);
        
        NSMutableArray *records;
        NSMutableArray *headerFields;
        
        NSData *dataForHmac = [SafeTools extractDbHeaderAndRecords:decData headerFields_p:&headerFields records_p:&records];
        NSData *computedHmac = [SafeTools calculateRFC2104Hmac:dataForHmac key:L];
        
        unsigned char *actualHmac[CC_SHA256_DIGEST_LENGTH];
        [safeData getBytes:actualHmac range:NSMakeRange(safeData.length - CC_SHA256_DIGEST_LENGTH, CC_SHA256_DIGEST_LENGTH)];
        NSData *actHmac = [[NSData alloc] initWithBytes:actualHmac length:CC_SHA256_DIGEST_LENGTH];
        //NSLog(@"%@", actHmac);
        
        if (![actHmac isEqualToData:computedHmac]) {
            NSLog(@"HMAC is no good! Corrupted Safe!");
            
            if (ppError != nil) {
                *ppError = [Utils createNSError:@"The data is corrupted (HMAC incorrect)." errorCode:-3];
            }
            
            return nil;
        }
        
        //[SafeTools dumpDbHeaderAndRecords:headerFields records:records];
        
        _dbHeaderFields = headerFields;
        _records = records;
        self.masterPassword = password;
        _keyStretchIterations = [SafeTools littleEndian4BytesToInteger:header.iter];
        
        return self;
    }
    else {
        return nil;
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (SafeItemViewModel*)addRecord:(NSString*)title
                          group:(Group*)group
                       username:(NSString*)username
                            url:(NSString*)url
                       password:(NSString*)password
                          notes:(NSString*)notes {
    Record* record = [[Record alloc] init];
    
    record.title = title;
    record.username = username;
    record.password = password;
    record.url = url;
    record.notes = notes;
    record.group = group;
    
    return [self addRecord:record];
}

- (SafeItemViewModel*)addRecord:(Record *)newRecord {
    [self.records addObject:newRecord];
    
    // Remove any Empty Group field if it exists for this record's group
    
    NSMutableArray *fieldsToDelete = [[NSMutableArray alloc] init];
    for (Field *field in _dbHeaderFields) {
        if (field.dbHeaderFieldType == HDR_EMPTYGROUP) {
            Group *group = [[Group alloc] initWithEscapedPathString:field.dataAsString];
            
            if ([group isEqual:newRecord.group]) {
                [fieldsToDelete addObject:field];
            }
        }
    }
    
    [_dbHeaderFields removeObjectsInArray:fieldsToDelete];
    
    [self invalidateCaches];
    
    return [[SafeItemViewModel alloc] initWithRecord:newRecord];
}

- (SafeItemViewModel *)createGroupWithTitle:(Group *)parentGroup
                                      title:(NSString *)title
                               validateOnly:(BOOL)validateOnly {
    if (!title || title.length < 1) {
        return nil;
    }
    
    if (!parentGroup) {
        parentGroup = [[Group alloc] initAsRootGroup];
    }
    
    Group *retGroup = [parentGroup createChildGroupWithTitle:title];
    
    if([[self allGroups] containsObject:retGroup]) {
        //NSLog(@"This group already exists... not re-creating.");
        return nil;
    }
    
    if (!validateOnly) {
        Field *emptyGroupField = [[Field alloc] initNewDbHeaderField:HDR_EMPTYGROUP
                                                          withString:retGroup.escapedPathString];
        [_dbHeaderFields addObject:emptyGroupField];
        
        [self invalidateCaches];
    }
    
    if (retGroup != nil) {
        return [[SafeItemViewModel alloc] initWithGroup:retGroup];
    }

    return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray *)getSearchableItems {
    NSArray *records = [self getAllRecords];
    NSArray *allDisplayableGroups = [self getAllDisplayableGroups:nil];

    NSMutableArray *items = [[NSMutableArray alloc] initWithCapacity:records.count + allDisplayableGroups.count];

    for (Group *group in allDisplayableGroups) {
        //NSLog(@"Adding %@ in %@", group.suffixDisplayString, group.pathPrefixDisplayString);

        [items addObject:[[SafeItemViewModel alloc] initWithGroup:group]];
    }

    for (Record *record in records) {
        [items addObject:[[SafeItemViewModel alloc] initWithRecord:record]];
    }

    return items;
}

- (NSArray *)getAllDisplayableGroups:(Group *)root {
    NSMutableArray *allDisplayableGroups = [[NSMutableArray alloc] init];

    //NSLog(@"Getting subgroups for [%@]", root.escapedPathString);
    NSArray *groupsForThisLevel = [self getImmediateSubgroupsForParent:root withFilter:nil deepSearch:NO];

    [allDisplayableGroups addObjectsFromArray:groupsForThisLevel];

    for (Group *group in groupsForThisLevel) {
        //NSLog(@"Recursing into [%@]", group.escapedPathString);
        [allDisplayableGroups addObjectsFromArray:[self getAllDisplayableGroups:group]];
    }

    return allDisplayableGroups;
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Regular Displayable Items

- (NSArray<SafeItemViewModel*> *)getImmediateSubgroupsForParent:(Group *)group {
    NSMutableArray *items = [[NSMutableArray alloc] init];

    NSMutableArray *subgroupsForCurrentGroup = [[NSMutableArray alloc] initWithArray:
                                                [self getImmediateSubgroupsForParent:group
                                                                     withFilter:nil
                                                                     deepSearch:NO]];

    [subgroupsForCurrentGroup sortUsingComparator:^(id obj1, id obj2) {
                                  NSString *s1 = ((SafeItemViewModel *)obj1).title;
                                  NSString *s2 = ((SafeItemViewModel *)obj2).title;
                                  return [s1 compare:s2];
                              }];

    for (Group *grp in subgroupsForCurrentGroup) {
        [items addObject:[[SafeItemViewModel alloc] initWithGroup:grp]];
    }

    return items;
}

- (NSArray<SafeItemViewModel*> *)getItemsForGroup:(Group *)group {
    return [self getItemsForGroup:group withFilter:[[NSString alloc] init] deepSearch:NO];
}

- (NSArray<SafeItemViewModel*>  *)getItemsForGroup:(Group *)group
                   withFilter:(NSString *)filter {
    return [self getItemsForGroup:group withFilter:filter deepSearch:NO];
}

- (NSArray<SafeItemViewModel*>  *)getItemsForGroup:(Group *)group
                   withFilter:(NSString *)filter
                   deepSearch:(BOOL)deepSearch {
    NSMutableArray *items = [[NSMutableArray alloc] init];

    NSMutableArray *subgroupsForCurrentGroup = [[NSMutableArray alloc] initWithArray:
                                                [self getImmediateSubgroupsForParent:group
                                                                     withFilter:filter
                                                                     deepSearch:deepSearch]];

    [subgroupsForCurrentGroup sortUsingComparator:^(id obj1, id obj2) {
                                  NSString *s1 = ((SafeItemViewModel *)obj1).title;
                                  NSString *s2 = ((SafeItemViewModel *)obj2).title;
                                  return [s1 compare:s2];
                              }];

    NSMutableArray *recordsForCurrentGroup = [[NSMutableArray alloc] initWithArray:[self getRecordsForGroup:group withFilter:filter deepSearch:deepSearch]];

    [recordsForCurrentGroup sortUsingComparator:^(id obj1, id obj2) {
                                NSString *s1 = ((SafeItemViewModel *)obj1).title;
                                NSString *s2 = ((SafeItemViewModel *)obj2).title;
                                return [s1 compare:s2];
                            }];

    for (Group *grp in subgroupsForCurrentGroup) {
        [items addObject:[[SafeItemViewModel alloc] initWithGroup:grp]];
    }

    for (Record *record in recordsForCurrentGroup) {
        [items addObject:[[SafeItemViewModel alloc] initWithRecord:record]];
    }

    return items;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)validateMoveItems:(NSArray<SafeItemViewModel*> *)items destination:(Group *)group {
    return [self validateMoveItems:items destination:group checkIfMoveIntoSubgroupOfDestinationOk:NO];
}

- (BOOL)validateMoveItems:(NSArray<SafeItemViewModel*> *)items destination:(Group *)group checkIfMoveIntoSubgroupOfDestinationOk:(BOOL)checkIfMoveIntoSubgroupOfDestinationOk {
    BOOL directMove = [self moveOrValidateItems:items destination:group validateOnly:YES];

    if (!directMove && checkIfMoveIntoSubgroupOfDestinationOk) {
        NSArray *subGroups = [self getImmediateSubgroupsForParent:group withFilter:nil deepSearch:NO];

        for (Group *subgroup in subGroups) {
            if ([self moveOrValidateItems:items destination:subgroup validateOnly:YES]) {
                return YES;
            }
        }
    }

    return directMove;
}

- (void)moveItems:(NSArray<SafeItemViewModel*> *)items destination:(Group *)group {
    [self moveOrValidateItems:items destination:group validateOnly:NO];
}

- (BOOL)moveOrValidateItems:(NSArray<SafeItemViewModel*> *)items destination:(Group *)destination validateOnly:(BOOL)validateOnly {
    for (SafeItemViewModel *item in items) {
        if (item.isGroup) {
            if (![self moveGroup:item.group destination:destination validateOnly:validateOnly]) {
                return NO;
            }
        }
        else {
            if (![self moveRecord:item.record destination:destination validateOnly:validateOnly]) {
                return NO;
            }
        }
    }

    return YES;
}

- (SafeItemViewModel *)setItemTitle:(SafeItemViewModel *)item title:(NSString *)title {
    if(item == nil) {
        NSLog(@"WARN: nil sent to setItemTitle!"); // TODO: Raise?
        return nil;
    }
    
    if (item.isGroup) {
        Group *parentGroup = [item.group getParentGroup];
        
        SafeItemViewModel *newGroup = [self createGroupWithTitle:parentGroup title:title validateOnly:YES];
        
        if (newGroup != nil) {
            NSArray *childItems = [self getItemsForGroup:item.group];

            if ([self moveOrValidateItems:childItems destination:newGroup.group validateOnly:YES]) {
                //We could be renaming an empty group so create the empty group now in case it's not created by the move operation.
                
                SafeItemViewModel *newGroup = [self createGroupWithTitle:parentGroup title:title validateOnly:NO];

                if (![self moveOrValidateItems:childItems destination:newGroup.group validateOnly:NO]) {
                    NSLog(@"Could move child items into new destination group %@", newGroup.group.escapedPathString);

                    return nil;
                }

                // delete the old

                [self deleteGroup:item.group];

                return newGroup;
            }
            else {
                NSLog(@"Could move child items into new destination group %@", newGroup.group.escapedPathString);
                return nil;
            }
        }
        else {
            NSLog(@"Could not create destination group %@", newGroup.group.escapedPathString);
            return nil;
        }
    }
    else {
        item.record.title = title;
        return item;
    }
}

- (void)setItemUsername:(SafeItemViewModel *)item username:(NSString*)username {
    if(item.isGroup) {
        [NSException raise:@"Attempt to alter group like an record invalidly." format:@"Attempt to alter group like an record invalidly"];
    }
    
    item.record.username = username;
}

- (void)setItemUrl:(SafeItemViewModel *)item url:(NSString*)url {
    if(item.isGroup) {
        [NSException raise:@"Attempt to alter group like an record invalidly." format:@"Attempt to alter group like an record invalidly"];
    }

    item.record.url = url;
}

- (void)setItemPassword:(SafeItemViewModel *)item password:(NSString*)password {
    if(item.isGroup) {
        [NSException raise:@"Attempt to alter group like an record invalidly." format:@"Attempt to alter group like an record invalidly"];
    }
    
    item.record.password = password;
}

- (void)setItemNotes:(SafeItemViewModel *)item notes:(NSString*)notes {
    if(item.isGroup) {
        [NSException raise:@"Attempt to alter group like an record invalidly." format:@"Attempt to alter group like an record invalidly"];
    }
  
    item.record.notes = notes;
}

- (void)deleteItems:(NSArray<SafeItemViewModel *> *)items {
    for (SafeItemViewModel *item in items) {
        [self deleteItem:item];
    }
}

- (void)deleteItem:(SafeItemViewModel *)item {
    if (item.isGroup) {
        [self deleteGroup:item.group];
    }
    else {
        [self deleteRecord:item.record];
    }
}

////////////////////////////////////////////////////////////////////////////////////////////
// Auto complete helper

- (NSSet *)getAllExistingUserNames {
    NSMutableSet *bag = [[NSMutableSet alloc]init];

    for (Record *record in [self getAllRecords]) {
        [bag addObject:record.username];
    }

    return bag;
}

- (NSSet *)getAllExistingPasswords {
    NSMutableSet *bag = [[NSMutableSet alloc]init];

    for (Record *record in [self getAllRecords]) {
        [bag addObject:record.password];
    }

    return bag;
}

- (NSString *)getMostPopularUsername {
    NSCountedSet *bag = [[NSCountedSet alloc]init];

    for (Record *record in [self getAllRecords]) {
        if(record.username.length) {
            [bag addObject:record.username];
        }
    }
    
    NSString *mostOccurring = @"";
    NSUInteger highest = 0;

    for (NSString *s in bag) {
        if ([bag countForObject:s] > highest) {
            highest = [bag countForObject:s];
            mostOccurring = s;
        }
    }

    return mostOccurring;
}

- (NSString *)getMostPopularPassword {
    NSCountedSet *bag = [[NSCountedSet alloc]init];

    for (Record *record in [self getAllRecords]) {
        [bag addObject:record.password];
    }

    NSString *mostOccurring = @"";
    NSUInteger highest = 0;

    for (NSString *s in bag) {
        if ([bag countForObject:s] > highest) {
            highest = [bag countForObject:s];
            mostOccurring = s;
        }
    }

    return mostOccurring;
}

- (NSString *)generatePassword {
    NSString *letters = @"!@#$%*[];?()abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    NSUInteger len = 16;
    NSMutableString *randomString = [NSMutableString stringWithCapacity:len];

    for (int i = 0; i < len; i++) {
        [randomString appendFormat:@"%C", [letters characterAtIndex:arc4random_uniform((u_int32_t)letters.length)]];
    }

    return randomString;
}

- (NSData *)getAsData:(NSError**)error {
    if(!self.masterPassword) {
        if(error) {
            *error = [Utils createNSError:@"Master not set." errorCode:-3];
        }
        
        return nil;
    }
    
    [self setLastUpdateTime];
    [self setLastUpdateUser];
    [self setLastUpdateHost];
    [self setLastUpdateApp];
    
    NSMutableData *ret = [[NSMutableData alloc] init];
    
    NSData *K, *L;
    
    //NSLog(@"Key Stretch Iterations: %d", _keyStretchIterations);
    //[SafeTools dumpDbHeaderAndRecords:_dbHeaderFields records:_records];
    
    PasswordSafe3Header hdr = [SafeTools generateNewHeader:(int)self.keyStretchIterations
                                            masterPassword:self.masterPassword
                                                         K:&K
                                                         L:&L];
    // Header is done...
    
    [ret appendBytes:&hdr length:SIZE_OF_PASSWORD_SAFE_3_HEADER];
    
    // We fill data buffer with all fields to be encrypted
    
    NSMutableData *toBeEncrypted = [[NSMutableData alloc] init];
    NSMutableData *hmacData = [[NSMutableData alloc] init];
    
    // DB Header
    
    NSData *serializedField;
    
    for (Field *dbHeaderField in _dbHeaderFields) {
        //NSLog(@"SAVE HDR: %@ -> %@", dbHeaderField.prettyTypeString, dbHeaderField.prettyDataString);
        serializedField = [SafeTools serializeField:dbHeaderField];
        
        [toBeEncrypted appendData:serializedField];
        [hmacData appendData:dbHeaderField.data];
    }
    
    // Write HDR_END
    
    Field *hdrEnd = [[Field alloc] initEmptyDbHeaderField:HDR_END];
    serializedField = [SafeTools serializeField:hdrEnd];
    [toBeEncrypted appendData:serializedField];
    [hmacData appendData:hdrEnd.data];
    
    // DONE DB Header //
    
    // Now all other records
    
    for (Record *record in _records) {
        //NSLog(@"Serializing [%@]", record.title);
        
        // Add required fields if they're not present, UUID, Title and Password
        
        if ((record.title).length == 0) {
            record.title = @"<Untitled>";
        }
        
        if ((record.password).length == 0) {
            record.password = @"";
        }
        
        if ((record.uuid).length == 0) {
            [record generateNewUUID];
        }
        
        for (Field *field in [record getAllFields]) {
            serializedField = [SafeTools serializeField:field];
            [toBeEncrypted appendData:serializedField];
            [hmacData appendData:field.data];
        }
        
        // Write RECORD_END
        
        Field *end = [[Field alloc] initEmptyWithType:FIELD_TYPE_END];
        serializedField = [SafeTools serializeField:end];
        [toBeEncrypted appendData:serializedField];
        [hmacData appendData:end.data];
    }
    
    // Verify our data is a multiple of the block size
    
    if (toBeEncrypted.length % TWOFISH_BLOCK_SIZE != 0) {
        NSLog(@"Data to be encrypted is not a multiple of the block size. Actual Length: %lu", (unsigned long)toBeEncrypted.length);
        
        if(error) {
            *error = [Utils createNSError:@"Internal Error: Data to be encrypted is not a multiple of the block size.." errorCode:-4];
        }
        
        return nil;
    }
    
    //NSLog(@"TBE: %@", toBeEncrypted);
    NSData *ct = [SafeTools encryptCBC:K ptData:toBeEncrypted iv:hdr.iv];
    
    [ret appendData:ct];
    
    // We write Plaintext EOF marker - must consume a block
    
    NSData *eofMarker = [EOF_MARKER dataUsingEncoding:NSUTF8StringEncoding];
    [ret appendData:eofMarker];
    
    // we calculate the hmac with L and the pt (toBeEncrypted) using sha256
    
    //NSLog(@"SAVE L: %@", L);
    // NSLog(@"SAVE HMACDATA: %@", hmacData);
    NSData *hmac = [SafeTools calculateRFC2104Hmac:hmacData key:L];
    //NSLog(@"SAVE HMAC: %@", hmac);
    
    [ret appendData:hmac];
    
    return ret;
}

- (NSString*)getSerializationIdForItem:(SafeItemViewModel*)item {
    if(item == nil) {
        return nil;
    }
    
    if(item.isGroup) {
        return [NSString stringWithFormat:@"G%@", item.group.escapedPathString];
    }
    else {
        return [NSString stringWithFormat:@"R%@", item.record.uuid];
    }
}

- (SafeItemViewModel*)getItemFromSerializationId:(NSString*)serializationId {
    if(serializationId == nil || serializationId.length < 1) {
        return nil;
    }
    
    NSString *groupOrRecord = [serializationId substringToIndex:1];
    NSString *identifier = [serializationId substringFromIndex:1];

    if([groupOrRecord isEqualToString:@"R"]) {
        Record* record = [self getRecordByUuid:identifier];
        
        if(record) {
            return [[SafeItemViewModel alloc] initWithRecord:record];
        }
    }
    else if([groupOrRecord isEqualToString:@"G"]) {
        Group* group = [self getGroupByEscapedPathString:identifier];
        
        if(group) {
            return [[SafeItemViewModel alloc] initWithGroup:group];
        }
    }
    
    return nil;
}

- (NSDate *)lastUpdateTime {
    NSDate *ret = nil;
    
    for (Field *field in _dbHeaderFields) {
        if (field.type == HDR_LASTUPDATETIME) {
            ret = field.dataAsDate;
            break;
        }
    }
    
    return ret;
}

- (NSString *)lastUpdateUser {
    NSString *ret = @"<Unknown>";
    
    for (Field *field in _dbHeaderFields) {
        if (field.type == HDR_LASTUPDATEUSER) {
            ret = field.dataAsString;
            break;
        }
    }
    
    return ret;
}

- (NSString *)lastUpdateHost {
    NSString *ret = @"<Unknown>";
    
    for (Field *field in _dbHeaderFields) {
        if (field.type == HDR_LASTUPDATEHOST) {
            ret = field.dataAsString;
            break;
        }
    }
    
    return ret;
}

- (NSString *)lastUpdateApp {
    NSString *ret = @"<Unknown>";
    
    for (Field *field in _dbHeaderFields) {
        if (field.type == HDR_LASTUPDATEAPPLICATION) {
            ret = field.dataAsString;
            break;
        }
    }
    
    return ret;
}

- (void)setLastUpdateApp {
    Field *appField = nil;
    
    for (Field *field in _dbHeaderFields) {
        if (field.type == HDR_LASTUPDATEAPPLICATION) {
            appField = field;
            break;
        }
    }
    
    if (appField) {
        [appField setDataWithString:[Utils getAppName]];
    }
    else {
        appField = [[Field alloc] initNewDbHeaderField:HDR_LASTUPDATEAPPLICATION withString:[Utils getAppName]];
        [_dbHeaderFields addObject:appField];
    }
}

- (void)setLastUpdateHost {
    Field *appField = nil;
    
    for (Field *field in _dbHeaderFields) {
        if (field.type == HDR_LASTUPDATEHOST) {
            appField = field;
            break;
        }
    }
    
    NSString *hostName = [Utils hostname]; //[[NSProcessInfo processInfo] hostName];
    
    if (appField) {
        [appField setDataWithString:hostName];
    }
    else {
        Field *lastUpdateHost = [[Field alloc] initNewDbHeaderField:HDR_LASTUPDATEHOST withString:hostName];
        [_dbHeaderFields addObject:lastUpdateHost];
    }
}

- (void)setLastUpdateUser {
    Field *appField = nil;
    
    for (Field *field in _dbHeaderFields) {
        if (field.type == HDR_LASTUPDATEUSER) {
            appField = field;
            break;
        }
    }
    
    if (appField) {
        [appField setDataWithString:kStrongBoxUser];
    }
    else {
        Field *lastUpdateUser = [[Field alloc] initNewDbHeaderField:HDR_LASTUPDATEUSER withString:kStrongBoxUser];
        [_dbHeaderFields addObject:lastUpdateUser];
    }
}

- (void)setLastUpdateTime {
    Field *appField = nil;
    
    for (Field *field in _dbHeaderFields) {
        if (field.type == HDR_LASTUPDATETIME) {
            appField = field;
            break;
        }
    }
    
    NSDate *now = [[NSDate alloc] init];
    time_t timeT = (time_t)now.timeIntervalSince1970;
    NSData *dataTime = [[NSData alloc] initWithBytes:&timeT length:4];
    
    if (appField) {
        [appField setDataWithData:dataTime];
    }
    else {
        Field *lastUpdateTime = [[Field alloc] initNewDbHeaderField:HDR_LASTUPDATETIME withData:dataTime];
        [_dbHeaderFields addObject:lastUpdateTime];
    }
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)invalidateCaches {
    self.allGroupsCache = nil;
}

- (NSArray<Group*>*)allGroups {
    if(self.allGroupsCache == nil) {
        NSArray<Group*> *empty = [self emptyGroups];
        
        NSMutableSet<Group*> *groups = [[NSMutableSet<Group*> alloc] init];
        [groups addObjectsFromArray:empty];
        
        for (Record *r in _records) {
            [groups addObject:r.group];
        }
        
        self.allGroupsCache = groups.allObjects;
    }
    
    return self.allGroupsCache;
}

- (NSArray<Record*> *)getAllRecords {
    return [NSArray arrayWithArray:_records];
}

- (NSArray<Group*> *)getImmediateSubgroupsForParent:(Group *)parent
                                         withFilter:(NSString *)filter
                                         deepSearch:(BOOL)deepSearch {
    NSMutableSet<Group*> *ret = [[NSMutableSet alloc] init];
    
    for (Group *group in  [self getAllSubgroupsWithParent:parent]) {
        if (filter.length) {
            if([self getRecordsForGroup:group withFilter:filter deepSearch:deepSearch].count) {
                Group *immediateSubGroup = [group getDirectAncestorOfParent:parent];
                [ret addObject:immediateSubGroup];
                break;
            }
        }
        else {
            Group *immediateSubGroup = [group getDirectAncestorOfParent:parent];
            [ret addObject:immediateSubGroup];
        }
    }
    
    return ret.allObjects;
}

- (NSArray<Record*> *)getRecordsForGroup:(Group *)parent
                              withFilter:(NSString *)filter
                              deepSearch:(BOOL)deepSearch {
    if (!parent) {
        parent = [[Group alloc] initAsRootGroup];
    }
    
    NSMutableArray<Record*> *ret = [[NSMutableArray alloc] init];
    
    for (Record *record in _records) {
        if ([self recordMatchesFilter:record filter:filter deepSearch:deepSearch] && [record.group isEqual:parent]) {
            [ret addObject:record];
        }
    }
    
    return ret;
}

- (BOOL)moveGroup:(Group *)src destination:(Group *)destination validateOnly:(BOOL)validateOnly {
    if (src == nil || src.isRootGroup) {
        return NO;
    }
    
    if (destination == nil) {
        destination = [[Group alloc] initAsRootGroup];
    }
    
    if (![src.parentGroup isEqual:destination] && ![src isEqual:destination] && ![destination isSubgroupOf:src]) {
        SafeItemViewModel *movedGroup = [self createGroupWithTitle:destination title:src.title validateOnly:validateOnly];
        
        if (movedGroup == nil) {
            NSLog(@"Group already exists at destination. Will not overwrite.");
            return NO;
        }
        
        // Direct records
        
        NSArray *records = [self getRecordsForGroup:src withFilter:nil deepSearch:NO];
        
        for (Record *record in records) {
            if (![self moveRecord:record destination:movedGroup.group validateOnly:validateOnly]) {
                return NO;
            }
        }
        
        // Direct subgroubs
        
        NSArray *subgroups = [self getImmediateSubgroupsForParent:src withFilter:nil deepSearch:NO];
        
        for (Group *subgroup in subgroups) {
            if (![self moveGroup:subgroup destination:movedGroup.group validateOnly:validateOnly]) {
                return NO;
            }
        }
        
        // Delete the src
        
        if (!validateOnly) {
            [self deleteGroup:src];
            [self invalidateCaches];
        }
        
        return YES;
    }
    
    return NO;
}

- (BOOL)moveRecord:(Record *)src destination:(Group *)destination validateOnly:(BOOL)validateOnly {
    if (destination == nil) {
        destination = [[Group alloc] initAsRootGroup];
    }
    
    if ([src.group isEqual:destination]) {
        return NO;
    }
    
    if (!validateOnly) {
        src.group = destination;
        [self invalidateCaches];
    }
    
    return YES;
}

- (void)deleteGroup:(Group *)group {
    // We need to find all this empty group + empty groups that are a subgroup of this and delete them
    
    NSMutableArray *fieldsToBeDeleted = [[NSMutableArray alloc] init];
    
    for (Field *field in _dbHeaderFields) {
        if (field.dbHeaderFieldType == HDR_EMPTYGROUP) {
            NSString *groupName = field.dataAsString;
            Group *g = [[Group alloc] initWithEscapedPathString:groupName];
            
            if ([g isEqual:group] || [g isSubgroupOf:group]) {
                [fieldsToBeDeleted addObject:field];
            }
        }
    }
    
    [_dbHeaderFields removeObjectsInArray:fieldsToBeDeleted];
    
    // We need to find all records that are part of this group and delete them!
    
    NSMutableArray *recordsToBeDeleted = [[NSMutableArray alloc] init];
    
    for (Record *record in _records) {
        if ([record.group isEqual:group] || [record.group isSubgroupOf:group]) {
            [recordsToBeDeleted addObject:record];
        }
    }
    
    [_records removeObjectsInArray:recordsToBeDeleted];
    
    [self invalidateCaches];
}

- (void)deleteRecord:(Record *)record {
    [_records removeObject:record];
    
    // We'd like to keep the empty group around for convenience/display purposes -
    // until user explicitly deletes so we'll put it
    // in the empty groups list in the DB header if it's not there
    
    if (![self groupContainsAnything:record.group] &&
        ![[self emptyGroups] containsObject:record.group]) {
        Field *emptyGroupField = [[Field alloc] initNewDbHeaderField:HDR_EMPTYGROUP withString:record.group.escapedPathString];
        [_dbHeaderFields addObject:emptyGroupField];
    }
    
    [self invalidateCaches];
}

- (Record*)getRecordByUuid:(NSString*)uuid {
    NSArray<Record*>* filtered = [_records filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        return [((Record*)evaluatedObject).uuid isEqualToString:uuid];
    }]];
    
    return [filtered firstObject];
}

- (Group*)getGroupByEscapedPathString:(NSString*)escapedPathString {
    if(escapedPathString == nil || escapedPathString.length == 0) {
        return [[Group alloc] initAsRootGroup];
    }
    
    NSArray<Group*> *allGroups = [self allGroups];
    
    NSArray<Group*> *filtered = [allGroups filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        Group* group = (Group*)(evaluatedObject);
        return [group.escapedPathString isEqualToString:escapedPathString]; // TODO: Case Sensitive?
    }]];
    
    return [filtered firstObject];
}

- (NSArray<Group *>*)emptyGroups {
    NSMutableSet<Group*> *groups = [[NSMutableSet<Group*> alloc] init];
    
    for (Field *field in _dbHeaderFields) {
        if (field.dbHeaderFieldType == HDR_EMPTYGROUP) {
            NSString *groupName = field.dataAsString;
            [groups addObject:[[Group alloc] initWithEscapedPathString:groupName]];
        }
    }
    
    return groups.allObjects;
}

- (NSArray<Group*> *)getAllSubgroupsWithParent:(Group*)parent {
    return [[self allGroups] filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        return [((Group*)evaluatedObject) isSubgroupOf:parent];
    }]];
}

- (BOOL)recordMatchesFilter:(Record *)record
                     filter:(NSString *)filter
                 deepSearch:(BOOL)deepSearch {
    if (!deepSearch) {
        return filter.length == 0 || ([record.title rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound);
    }
    else {
        return (filter.length == 0 ||
                ([record.title rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) ||
                ([record.username rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) ||
                ([record.password rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) ||
                ([record.url rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) ||
                ([record.notes rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound));
    }
}

- (BOOL)groupContainsAnything:(Group*)group {
    for (Record *r in _records) {
        if ([r.group isEqual:group] || [r.group isSubgroupOf:group]) {
            return NO;
            break;
        }
    }
    
    return [self getAllSubgroupsWithParent:group].count > 0;
}

@end
