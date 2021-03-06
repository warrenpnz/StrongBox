//
//  RecordView.m
//  StrongBox
//
//  Created by Mark on 31/05/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import "RecordView.h"
#import "Field.h"
#import "PasswordHistoryViewController.h"
#import "PasswordHistory.h"
#import "Alerts.h"
#import "SVProgressHUD/SVProgressHUD.h"
#import "ISMessages/ISMessages.h"
#import "TextFieldAutoSuggest.h"
#import "Settings.h"

@interface RecordView ()

@property (nonatomic, strong) TextFieldAutoSuggest *passwordAutoSuggest;
@property (nonatomic, strong) TextFieldAutoSuggest *usernameAutoSuggest;
@property (nonatomic, strong) TextFieldAutoSuggest *emailAutoSuggest;
@property (nonatomic, strong) UITextField *textFieldTitle;

@end

@implementation RecordView {
    UIBarButtonItem *navBack;
    BOOL _hidePassword;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.buttonPasswordGenerationSettings.hidden = YES;
    
    [self setInitialTextFieldBordersAndColors];
    [self setupAutoComplete];
    
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
    _hidePassword = ![[Settings sharedInstance] isShowPasswordByDefaultOnEditScreen];
    [self hideOrShowPassword:_hidePassword];
    
    [self reloadFieldsFromRecord];
        
    [self setEditing:(self.record == nil) animated:YES];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if(self.record == nil) {
        [self.textFieldTitle becomeFirstResponder];
        [self.textFieldTitle selectAll:nil];
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Autocomplete

- (void)setupAutoComplete {
    self.passwordAutoSuggest = [[TextFieldAutoSuggest alloc]
                                initForTextField:self.textFieldPassword
                                viewController:self
                                suggestionsProvider:^NSArray<NSString *> *(NSString *text) {
                                    NSSet<NSString*> *allPasswords = self.viewModel.passwordSet;
                                    
                                    NSArray<NSString*> *filtered = [[allPasswords allObjects]
                                            filteredArrayUsingPredicate:[NSPredicate
                                                                         predicateWithFormat:@"SELF BEGINSWITH[c] %@", text]];
                                    
                                    return [filtered sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
                                }];
    
    self.usernameAutoSuggest = [[TextFieldAutoSuggest alloc]
                                initForTextField:self.textFieldUsername
                                viewController:self
                                suggestionsProvider:^NSArray<NSString *> *(NSString *text) {
                                    NSSet<NSString*> *allUsernames = self.viewModel.usernameSet;
                                    
                                    NSArray* filtered = [[allUsernames allObjects]
                                            filteredArrayUsingPredicate:[NSPredicate
                                                                         predicateWithFormat:@"SELF BEGINSWITH[c] %@", text]];
                                
                                    return [filtered sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
                                }];
    
    self.emailAutoSuggest = [[TextFieldAutoSuggest alloc]
                                initForTextField:self.textFieldEmail
                                viewController:self
                                suggestionsProvider:^NSArray<NSString *> *(NSString *text) {
                                    NSSet<NSString*> *allEmails = self.viewModel.emailSet;
                                    
                                    NSArray* filtered = [[allEmails allObjects]
                                                         filteredArrayUsingPredicate:[NSPredicate
                                                                                      predicateWithFormat:@"SELF BEGINSWITH[c] %@", text]];
                                    
                                    return [filtered sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
                                }];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setInitialTextFieldBordersAndColors {
    self.textFieldPassword.borderStyle = UITextBorderStyleRoundedRect;
    self.textFieldUsername.borderStyle = UITextBorderStyleRoundedRect;
    self.textFieldEmail.borderStyle = UITextBorderStyleRoundedRect;
    self.textFieldUrl.borderStyle = UITextBorderStyleRoundedRect;
    
    self.textViewNotes.layer.borderWidth = 1.0f;
    self.textFieldPassword.layer.borderWidth = 1.0f;
    self.textFieldUrl.layer.borderWidth = 1.0f;
    self.textFieldUsername.layer.borderWidth = 1.0f;
    self.textFieldEmail.layer.borderWidth = 1.0f;
    
    [self.buttonCopyAndLaunchUrl setTitle:@"" forState:UIControlStateNormal];
    
    self.textViewNotes.layer.cornerRadius = 5;
    self.textFieldPassword.layer.cornerRadius = 5;
    self.textFieldUrl.layer.cornerRadius = 5;
    self.textFieldUsername.layer.cornerRadius = 5;
    self.textFieldEmail.layer.cornerRadius = 5;
    
    self.textViewNotes.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.textFieldPassword.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.textFieldUrl.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.textFieldUsername.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.textFieldEmail.layer.borderColor = [UIColor lightGrayColor].CGColor;
    
    self.textViewNotes.delegate = self;
    
    // TODO: Magic values here?
    self.textFieldTitle = [[UITextField alloc] initWithFrame:CGRectMake(self.view.bounds.origin.x, 7, self.view.bounds.size.width, 31)];
    self.textFieldTitle.backgroundColor = [UIColor clearColor];
    self.textFieldTitle.textAlignment = NSTextAlignmentCenter;
    self.textFieldTitle.borderStyle = UITextBorderStyleNone;
    self.textFieldTitle.font = [UIFont boldSystemFontOfSize:20];
    self.textFieldTitle.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textFieldTitle.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    self.textFieldTitle.layer.masksToBounds = NO;
    self.textFieldTitle.enabled = NO;
    self.textFieldTitle.layer.shadowColor = [UIColor whiteColor].CGColor;
    self.textFieldTitle.layer.shadowOpacity = 0;
    self.textFieldTitle.layer.cornerRadius = 5;
    self.textFieldTitle.tag = 1;
    
    [self.textFieldTitle addTarget:self
                        action:@selector(textViewDidChange:)
              forControlEvents:UIControlEventEditingChanged];
    
    [self.textFieldPassword addTarget:self
                        action:@selector(textViewDidChange:)
              forControlEvents:UIControlEventEditingChanged];
    
    [self.textFieldUsername addTarget:self
                        action:@selector(textViewDidChange:)
              forControlEvents:UIControlEventEditingChanged];

    [self.textFieldEmail addTarget:self
                               action:@selector(textViewDidChange:)
                     forControlEvents:UIControlEventEditingChanged];
    
    [self.textFieldUrl addTarget:self
                               action:@selector(textViewDidChange:)
                     forControlEvents:UIControlEventEditingChanged];
    
    self.navigationItem.titleView = self.textFieldTitle;
}

- (void)reloadFieldsFromRecord {
    if (self.record) {
        self.textFieldPassword.text = self.record.fields.password;
        self.textFieldTitle.text = self.record.title;
        self.textFieldUrl.text = self.record.fields.url;
        self.textFieldUsername.text = self.record.fields.username;
        self.textFieldEmail.text = self.record.fields.email;
        self.textViewNotes.text = self.record.fields.notes;
        
        self.buttonPasswordGenerationSettings.enabled = NO;
        self.buttonHistory.enabled = YES;
    }
    else {
        self.textFieldPassword.text = [self.viewModel generatePassword];
        
        self.textFieldTitle.text = @"Untitled";
        self.textFieldUrl.text = @"";
        self.textFieldUsername.text = self.viewModel.mostPopularUsername;
        self.textFieldEmail.text = self.viewModel.mostPopularEmail;
        self.textViewNotes.text = @"";
        
        self.buttonPasswordGenerationSettings.enabled = NO;
        self.buttonHistory.enabled = NO;
    }
}

- (void)setEditing:(BOOL)flag animated:(BOOL)animated {
    [super setEditing:flag animated:animated];
    
    if (flag == YES) {
        navBack = self.navigationItem.leftBarButtonItem;
        self.editButtonItem.enabled = [self uiIsDirty];
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(onCancelBarButton)];
        self.buttonPasswordGenerationSettings.enabled = YES;
        self.buttonHistory.enabled = NO;
    }
    else {
        if ([self uiIsDirty]) { // Any other changes? Change the record and save the safe
            [self saveAfterEdit:^(NSError *error) {
                self.navigationItem.leftBarButtonItem = navBack;
                self.editButtonItem.enabled = YES;
                navBack = nil;
                
                if (error != nil) {
                    [Alerts   error:self
                              title:@"Problem Saving"
                              error:error];
                    
                    NSLog(@"%@", error);
                    
                    [self.navigationController popViewControllerAnimated:YES];
                }
                else {
                    [self reloadFieldsFromRecord];
                    [self updateFieldsForEditable];
                    
                    //[self.navigationController popViewControllerAnimated:YES];
                }
            }];
        }
        else {
            self.buttonPasswordGenerationSettings.enabled = NO; //(self.record != nil);
            self.buttonHistory.enabled = (self.record != nil);
            self.navigationItem.leftBarButtonItem = navBack;
            self.editButtonItem.enabled = !(self.viewModel.isUsingOfflineCache || self.viewModel.isReadOnly);
            self.textFieldTitle.borderStyle = UITextBorderStyleLine;
            navBack = nil;
        }
    }
    
    [self updateFieldsForEditable];
    
    if (flag == YES) {
        [self.textFieldTitle becomeFirstResponder];
    }
}

- (void)updateFieldsForEditable {
    self.textFieldTitle.enabled = self.editing;
    self.textFieldTitle.borderStyle = self.editing ? UITextBorderStyleLine : UITextBorderStyleNone;

    self.textFieldPassword.enabled = self.editing;
    self.textFieldPassword.layer.borderColor = self.editing ? [UIColor darkGrayColor].CGColor : [UIColor lightGrayColor].CGColor;
    self.textFieldPassword.backgroundColor = [UIColor whiteColor];
    
    self.textFieldUsername.enabled = self.editing;
    self.textFieldUsername.textColor = self.editing ? [UIColor blackColor] : [UIColor darkGrayColor];
    self.textFieldUsername.layer.borderColor = self.editing ? [UIColor blackColor].CGColor : [UIColor lightGrayColor].CGColor;
    self.textFieldUsername.backgroundColor = [UIColor whiteColor];
    
    self.textFieldEmail.enabled = self.editing;
    self.textFieldEmail.textColor = self.editing ? [UIColor blackColor] : [UIColor darkGrayColor];
    self.textFieldEmail.layer.borderColor = self.editing ? [UIColor blackColor].CGColor : [UIColor lightGrayColor].CGColor;
    self.textFieldEmail.backgroundColor = [UIColor whiteColor];
    
    self.textFieldUrl.enabled = self.editing;
    self.textFieldUrl.textColor = self.editing ? [UIColor blackColor] : [UIColor blueColor];
    self.textFieldUrl.layer.borderColor = self.editing ? [UIColor darkGrayColor].CGColor : [UIColor lightGrayColor].CGColor;
    self.textFieldUrl.backgroundColor = [UIColor whiteColor];
    
    self.textViewNotes.editable = self.editing;
    self.textViewNotes.textColor = self.editing ? [UIColor blackColor] : [UIColor grayColor];
    self.textViewNotes.layer.borderColor = self.editing ? [UIColor darkGrayColor].CGColor : [UIColor lightGrayColor].CGColor;
    
    UIImage *btnImage = [UIImage imageNamed:self.isEditing ? @"arrow_circle_left_64" : @"copy_64"];
    
    [self.buttonGeneratePassword setImage:btnImage forState:UIControlStateNormal];
    (self.buttonGeneratePassword).enabled = self.editing || (!self.isEditing && (self.record != nil && (self.record.fields.password).length));
    
    [self hideOrShowPassword:self.isEditing ? NO : _hidePassword];
    (self.buttonHidePassword).enabled = !self.isEditing;
    
    (self.buttonCopyUsername).enabled = !self.isEditing && (self.record != nil && (self.record.fields.username).length);
    (self.buttonCopyEmail).enabled = !self.isEditing && (self.record != nil && (self.record.fields.email).length);
    (self.buttonCopyUrl).enabled = !self.isEditing && (self.record != nil && (self.record.fields.url).length);
    (self.buttonCopyAndLaunchUrl).enabled = !self.isEditing;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.navigationController.toolbar.hidden = YES;
    self.navigationController.navigationBar.hidden = NO;
}

- (void)textViewDidChange:(UITextView *)textView {
    self.editButtonItem.enabled = [self uiIsDirty];
}

- (BOOL)uiIsDirty {
    return !([self.textViewNotes.text isEqualToString:self.record.fields.notes]
             &&   [trim(self.textFieldPassword.text) isEqualToString:self.record.fields.password]
             &&   [trim(self.textFieldTitle.text) isEqualToString:self.record.title]
             &&   [trim(self.textFieldUrl.text) isEqualToString:self.record.fields.url]
             &&   [trim(self.textFieldEmail.text) isEqualToString:self.record.fields.email]
             &&   [trim(self.textFieldUsername.text) isEqualToString:self.record.fields.username]);
}

NSString * trim(NSString *string) {
    return [string stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
}

- (void)copyToClipboard:(NSString *)value message:(NSString *)message {
    if (value.length == 0) {
        return;
    }
    
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = value;
    
    [ISMessages showCardAlertWithTitle:message
                               message:nil
                              duration:3.f
                           hideOnSwipe:YES
                             hideOnTap:YES
                             alertType:ISAlertTypeSuccess
                         alertPosition:ISAlertPositionTop
                               didHide:nil];
}

- (IBAction)onSettings:(id)sender {
}

- (IBAction)onGeneratePassword:(id)sender {
    if (self.editing) {
        self.textFieldPassword.text = [self.viewModel generatePassword];
        self.editButtonItem.enabled = [self uiIsDirty];
    }
    else if (self.record)
    {
        [self copyToClipboard:self.record.fields.password message:@"Password Copied"];
    }
}

- (IBAction)onCopyUrl:(id)sender {
    [self copyToClipboard:self.record.fields.url message:@"URL Copied"];
}

- (IBAction)onCopyUsername:(id)sender {
    [self copyToClipboard:self.record.fields.username message:@"Username Copied"];
}

- (IBAction)onCopyAndLaunchUrl:(id)sender {
    NSString *urlString = self.record.fields.url;

    if (!urlString.length) {
        return;
    }

    [self copyToClipboard:self.record.fields.password message:@"Password Copied. Launching URL..."];
    
    if (![urlString.lowercaseString hasPrefix:@"http://"] &&
        ![urlString.lowercaseString hasPrefix:@"https://"]) {
        urlString = [NSString stringWithFormat:@"http://%@", urlString];
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString]];
    });
}

- (IBAction)onCopyEmail:(id)sender {
    [self copyToClipboard:self.record.fields.email message:@"Email Copied"];
}

- (IBAction)onHide:(id)sender {
    _hidePassword = !_hidePassword;
    
    [self hideOrShowPassword:_hidePassword];
}

- (void)hideOrShowPassword:(BOOL)hide {
    if (hide) {
        [self.textFieldPassword setTextColor:[UIColor lightGrayColor]];
        self.textFieldPassword.text = @"****************";
        [self.buttonHidePassword setTitle:@"Show" forState:UIControlStateNormal];
    }
    else {
        [self.textFieldPassword setTextColor:[UIColor purpleColor]];
        self.textFieldPassword.text = self.record ? self.record.fields.password : [self.viewModel generatePassword];
        [self.buttonHidePassword setTitle:@"Hide" forState:UIControlStateNormal];
    }
}

- (void)onCancelBarButton {
    if (self.record == nil) {
        // Back to safe view if we just cancelled out of a new record
        [self.navigationController popViewControllerAnimated:YES];
    }
    else {
        [self reloadFieldsFromRecord];
        
        [self setEditing:NO animated:YES];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqual:@"segueToPasswordHistory"] && (self.record != nil))
    {
        PasswordHistoryViewController *vc = segue.destinationViewController;
        vc.model = self.record.fields.passwordHistory;
        vc.readOnly = self.viewModel.isReadOnly || self.viewModel.isUsingOfflineCache;
        
        vc.saveFunction = ^(PasswordHistory *changed, void (^onDone)(NSError *)) {
            self.record.fields.passwordHistory = changed;
            self.record.fields.accessed = [[NSDate alloc] init];
            self.record.fields.modified = [[NSDate alloc] init];

            [self.viewModel update:^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    onDone(error);
                });
            }];
        };
    }
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Hide Delete Buttons and Indentation during editing and autosize last row to fill available space

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 4 && indexPath.row == 0) {
        int cell1 = [super tableView:tableView heightForRowAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
        int cell2 = [super tableView:tableView heightForRowAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:1]];
        int cell3 = [super tableView:tableView heightForRowAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:2]];
        int cell4 = [super tableView:tableView heightForRowAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:3]];
        
        int otherCellsHeight = cell1 + cell2 + cell3 + cell4;
        
        int statusBarHeight = [UIApplication sharedApplication].statusBarFrame.size.height;
        int toolBarHeight = self.navigationController.toolbar.frame.size.height;
        int navBarHeight = self.navigationController.navigationBar.frame.size.height;
        
        int totalVisibleHeight = self.tableView.bounds.size.height - statusBarHeight - navBarHeight - toolBarHeight;
        
        int availableHeight = totalVisibleHeight - otherCellsHeight;
        
        availableHeight = (availableHeight > 80) ? availableHeight : 80;
        
        return availableHeight;
    }
    else {
        return [super tableView:tableView heightForRowAtIndexPath:indexPath];
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)saveAfterEdit:(void (^)(NSError *))completion {
    BOOL recordNeedsToBeAddedToSafe = (self.record == nil);
    
    if (recordNeedsToBeAddedToSafe) {
        NodeFields *nodeFields = [[NodeFields alloc] initWithUsername:trim(self.textFieldUsername.text)
                                                                  url:trim(self.textFieldUrl.text)
                                                             password:trim(self.textFieldPassword.text)
                                                                notes:self.textViewNotes.text
                                                                email:trim(self.textFieldEmail.text)];
        
        self.record = [[Node alloc] initAsRecord:trim(self.textFieldTitle.text)
                                          parent:self.parentGroup
                                          fields:nodeFields];

        self.record.fields.created = [[NSDate alloc] init];
        
        [self.parentGroup addChild:self.record];
    }
    else {
        self.record.fields.accessed = [[NSDate alloc] init];
        self.record.fields.modified = [[NSDate alloc] init];

        self.record.fields.notes = self.textViewNotes.text;
        self.record.fields.password = trim(self.textFieldPassword.text);
        self.record.title = trim(self.textFieldTitle.text);
        self.record.fields.url = trim(self.textFieldUrl.text);
        self.record.fields.username = trim(self.textFieldUsername.text);
        self.record.fields.email = trim(self.textFieldEmail.text);
    }
    
    [self.viewModel update:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            completion(error);
        });
    }];
}

@end
