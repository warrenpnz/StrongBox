//
//  VersionConflictController.m
//  Strongbox
//
//  Created by Mark on 25/09/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "VersionConflictController.h"
#import "Utils.h"

@interface VersionConflictController ()

@property NSMutableArray<NSFileVersion*> *versions;

@end

@implementation VersionConflictController

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self.navigationItem setPrompt:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController.toolbar setHidden:YES];
    
    NSMutableArray * fileVersions = [NSMutableArray array];
    
    NSURL* theUrl = [NSURL URLWithString:self.url];
    NSFileVersion * currentVersion = [NSFileVersion currentVersionOfItemAtURL:theUrl];
    [fileVersions addObject:currentVersion];
    
    NSArray * otherVersions = [NSFileVersion otherVersionsOfItemAtURL:theUrl];
    [fileVersions addObjectsFromArray:otherVersions];
    
    for (NSFileVersion * fileVersion in fileVersions) {
        [self.versions addObject:fileVersion];
    }
    
    [self.tableView reloadData];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //self.navigationItem.prompt = @"Please select the correct version of the safe to use";

    self.versions = [NSMutableArray array];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.versions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"versionCellIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    // Configure the cell...
    //UIImageView * imageView = (UIImageView *) [cell viewWithTag:1];
    
    NSFileVersion * entry = [self.versions objectAtIndex:indexPath.row];
    
    cell.textLabel.text = [NSString stringWithFormat:@"Modified on %@", entry.localizedNameOfSavingComputer];
    cell.detailTextLabel.text = entry.modificationDate.description;
    
    return cell;
}
@end
