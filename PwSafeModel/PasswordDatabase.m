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

@end

@implementation PasswordDatabase

+ (BOOL)isAValidSafe:(NSData *)candidate {
    return [SafeTools isAValidSafe:candidate];
}

- (instancetype)initNewWithoutPassword {
    return [self initNewWithPassword:nil];
}

- (instancetype)initNewWithPassword:(NSString *)password {
    if (self = [super init]) {
        _dbHeaderFields = [[NSMutableArray alloc] init];

        [self setLastUpdateTime];
        [self setLastUpdateUser];
        [self setLastUpdateHost];
        [self setLastUpdateApp];
        
        self.keyStretchIterations = DEFAULT_KEYSTRETCH_ITERATIONS;
        self.masterPassword = password;
        
        _rootGroup = [[Node alloc] initAsRoot];
        return self;
    }
    else {
        return nil;
    }
}

- (instancetype)initExistingWithDataAndPassword:(NSData *)safeData
                                       password:(NSString *)password
                                          error:(NSError **)ppError {
    if (self = [super init]) {
        if (![SafeTools isAValidSafe:safeData]) {
            NSLog(@"Not a valid safe!");
            
            if (ppError != nil) {
                *ppError = [Utils createNSError:@"This is not a valid Password Safe (Invalid Format)." errorCode:-1];
            }
            
            return nil;
        }

        NSMutableArray<Field*> *headerFields;
        NSArray<Record*> *records = [self decryptSafe:safeData
                                             password:password
                                              headers:&headerFields
                                                error:ppError];

        if(!records) {
            return nil;
        }
        
        _dbHeaderFields = headerFields;
        self.masterPassword = password;
        self.keyStretchIterations = [SafeTools getKeyStretchIterations:safeData];
        
        _rootGroup = [self buildModel:records headers:headerFields];
        
        if(!self.rootGroup) {
            NSLog(@"Could not build model from records and headers?!");
            
            if (ppError != nil) {
                *ppError = [Utils createNSError:@"Could not parse this safe." errorCode:-1];
            }
            
            return nil;
        }
        
        return self;
    }
    else {
        return nil;
    }
}

- (Node*)buildModel:(NSArray<Record*>*)records headers:(NSArray<Field*>*)headers  {
    Node* root = [[Node alloc] initAsRoot];
    
    // Group Records into by their group
    
    NSMutableDictionary<NSArray<NSString*>*, NSMutableArray<Record*>*> *groupedByGroup =
        [[NSMutableDictionary<NSArray<NSString*>*, NSMutableArray<Record*>*> alloc] init];
    
    for (Record *r in records) {
        NSMutableArray<Record*>* recordsForThisGroup = [groupedByGroup objectForKey:r.group.pathComponents];
        
        if(!recordsForThisGroup) {
            recordsForThisGroup = [NSMutableArray<Record*> array];
            [groupedByGroup setObject:recordsForThisGroup forKey:r.group.pathComponents];
        }
     
        [recordsForThisGroup addObject:r];
    }

    NSMutableArray<NSArray<NSString*>*> *allKeys = [[groupedByGroup allKeys] mutableCopy];
    
    for (NSArray<NSString*>* groupComponents in allKeys) {
        Node* group = [self addGroupUsingGroupComponents:root groupComponents:groupComponents];
        
        NSMutableArray<Record*>* recordsForThisGroup = [groupedByGroup objectForKey:groupComponents];

        for(Record* record in recordsForThisGroup) {
            Node* recordNode = [[Node alloc] initWithExistingPasswordSafe3Record:record parent:group];
            [group addChild:recordNode];
        }
    }
    
    NSSet<Group*> *emptyGroups = [self getEmptyGroupsFromHeaders:headers];
    
    for (Group* emptyGroup in emptyGroups) {
        [self addGroupUsingGroupComponents:root groupComponents:emptyGroup.pathComponents];
    }
    
    return root;
}

- (NSSet<Group*>*)getEmptyGroupsFromHeaders:(NSArray<Field*>*)headers {
    NSMutableSet<Group*> *groups = [[NSMutableSet<Group*> alloc] init];
    
    for (Field *field in headers) {
        if (field.dbHeaderFieldType == HDR_EMPTYGROUP) {
            NSString *groupName = field.dataAsString;
            [groups addObject:[[Group alloc] initWithEscapedPathString:groupName]];
        }
    }
    
    return groups;
}

- (Node*)addGroupUsingGroupComponents:(Node*)root groupComponents:(NSArray<NSString*>*)groupComponents {
    Node* node = root;
    
    for(NSString* component in groupComponents) {
        Node* foo = [node getChildGroupWithTitle:component];
        
        if(!foo) {
            foo = [[Node alloc] initAsGroup:component parent:node];
            if(![node addChild:foo]) {
                NSLog(@"Problem adding child group [%@] to node [%@]", component, node.title);
                return nil;
            }
        }
        
        node = foo;
    }
    
    return node;
}

- (NSArray<Record*> *)decryptSafe:(NSData*)safeData
                         password:(NSString*)password
                          headers:(NSMutableArray<Field*> **)headerFields
                            error:(NSError **)ppError {
    
    PasswordSafe3Header header = [SafeTools getHeader:safeData];
    
    NSData *pBar;
    if (![SafeTools checkPassword:&header password:password pBar:&pBar]) {
        NSLog(@"Invalid password!");
        
        if (ppError != nil) {
            *ppError = [Utils createNSError:@"The password is incorrect." errorCode:-2];
        }
        
        return nil;
    }
    
    NSData *K;
    NSData *L;
    
    [SafeTools getKandL:pBar header:header K_p:&K L_p:&L];
    
    NSInteger numBlocks = [SafeTools getNumberOfBlocks:safeData];
    
    NSData *decData = [SafeTools decryptBlocks:K
                                            ct:(unsigned char *)&safeData.bytes[SIZE_OF_PASSWORD_SAFE_3_HEADER]
                                            iv:header.iv
                                     numBlocks:numBlocks];
    
    NSMutableArray<Record*> *records = [NSMutableArray array];
    NSData *dataForHmac = [SafeTools extractDbHeaderAndRecords:decData headerFields_p:headerFields records_p:&records];
    
    NSData *computedHmac = [SafeTools calculateRFC2104Hmac:dataForHmac key:L];
    
    unsigned char *actualHmac[CC_SHA256_DIGEST_LENGTH];
    [safeData getBytes:actualHmac range:NSMakeRange(safeData.length - CC_SHA256_DIGEST_LENGTH, CC_SHA256_DIGEST_LENGTH)];
    NSData *actHmac = [[NSData alloc] initWithBytes:actualHmac length:CC_SHA256_DIGEST_LENGTH];
    
    if (![actHmac isEqualToData:computedHmac]) {
        NSLog(@"HMAC is no good! Corrupted Safe!");
        
        if (ppError != nil) {
            *ppError = [Utils createNSError:@"The data is corrupted (HMAC incorrect)." errorCode:-3];
        }
        
        return nil;
    }
    
    //[SafeTools dumpDbHeaderAndRecords:headerFields records:records];

    return records;
}

////////////////////////////////////////////////////////////////////////////////////////////
// Convenience

- (NSArray<Node*>*)getAllRecords {
    return [self.rootGroup filterChildren:YES predicate:^BOOL(Node * _Nonnull node) {
        return !node.isGroup;
    }];
}

- (NSSet<NSString*> *)getUsernamesSet {
    NSMutableSet<NSString*> *bag = [[NSMutableSet alloc]init];

    for (Node *recordNode in [self getAllRecords]) {
        [bag addObject:recordNode.fields.username];
    }

    return bag;
}

- (NSSet<NSString*> *)getAllExistingPasswords {
    NSMutableSet<NSString*> *bag = [[NSMutableSet alloc]init];

    for (Node *record in [self getAllRecords]) {
        [bag addObject:record.fields.password];
    }

    return bag;
}

- (NSString *)getMostPopularUsername {
    NSCountedSet<NSString*> *bag = [[NSCountedSet alloc]init];

    for (Node *record in [self getAllRecords]) {
        if(record.fields.username.length) {
            [bag addObject:record.fields.username];
        }
    }
    
    return [self mostFrequentInCountedSet:bag];
}

- (NSString *)getMostPopularPassword {
    NSCountedSet<NSString*> *bag = [[NSCountedSet alloc]init];

    for (Node *record in [self getAllRecords]) {
        [bag addObject:record.fields.password];
    }

    return [self mostFrequentInCountedSet:bag];
}

- (NSString*)mostFrequentInCountedSet:(NSCountedSet<NSString*>*)bag {
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
    
    // TODO: Move to serialization - defaults if not exist
    
    //        // Version
    //
    //        unsigned char versionBytes[2];
    //        versionBytes[0] = 0x0B;
    //        versionBytes[1] = 0x03;
    //        NSData *versionData = [[NSData alloc] initWithBytes:&versionBytes length:2];
    //        Field *version = [[Field alloc] initNewDbHeaderField:HDR_VERSION withData:versionData];
    //        [_dbHeaderFields addObject:version];
    //
    //        // UUID
    //
    //        NSUUID *unique = [[NSUUID alloc] init];
    //        unsigned char bytes[16];
    //        [unique getUUIDBytes:bytes];
    //        Field *uuid = [[Field alloc] initNewDbHeaderField:HDR_UUID withData:[[NSData alloc] initWithBytes:bytes length:16]];
    //        [_dbHeaderFields addObject:uuid];
    //        

    
    
    
    
    
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
    
    NSArray* _records; // TODO
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

@end
