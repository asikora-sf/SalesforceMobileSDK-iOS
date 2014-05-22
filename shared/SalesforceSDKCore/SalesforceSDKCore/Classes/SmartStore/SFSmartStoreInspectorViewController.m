/*
 Copyright (c) 2014, salesforce.com, inc. All rights reserved.
 
 Redistribution and use of this software in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of
 conditions and the following disclaimer in the documentation and/or other materials provided
 with the distribution.
 * Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
 endorse or promote products derived from this software without specific prior written
 permission of salesforce.com, inc.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <UIKit/UITextInputTraits.h>

#import "SFSmartStoreInspectorViewController.h"
#import "SFSDKResourceUtils.h"
#import "SFRootViewManager.h"
#import "SFSmartStore.h"
#import "SFQuerySpec.h"
#import "SFJsonUtils.h"

// Nav bar
static CGFloat      const kNavBarHeight          = 44.0;
// Query field
static NSString *   const kQueryFieldFontName    = @"Courier";
static CGFloat      const kQueryFieldFontSize    = 12.0;
static CGFloat      const kQueryFieldHeight      = 96.0;
static CGFloat      const kQueryFieldBorderWidth = 3.0;
// Buttons
static NSString *   const kButtonFontName        = @"HelveticaNeue-Bold";
static CGFloat      const kButtonFontSize        = 16.0;
static CGFloat      const kButtonHeight          = 48.0;
static CGFloat      const kButtonBorderWidth     = 3.0;
// Results
static CGFloat      const kResultGridBorderWidth = 3.0;
static NSString *   const kResultTextFontName    = @"Courier";
static CGFloat      const kResultTextFontSize    = 12.0;
static CGFloat      const kResultCellHeight      = 24.0;
static CGFloat      const kResultCellBorderWidth = 1.0;
static NSString *   const kCellIndentifier       = @"cellIdentifier";
static NSUInteger   const kLabelTag              = 99;

@interface SFSmartStoreInspectorViewController ()

@property (nonatomic, strong) UINavigationBar *navBar;
@property (nonatomic, strong) UITextView *queryField;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *soupsButton;
@property (nonatomic, strong) UIButton *indicesButton;
@property (nonatomic, strong) UICollectionView *resultGrid;
@property (nonatomic, strong) NSArray *results;
@property (readonly, atomic, assign) NSUInteger countColumns;
@property (readonly, atomic, assign) NSUInteger countRows;

@end

@implementation SFSmartStoreInspectorViewController

#pragma mark - Singleton

+ (SFSmartStoreInspectorViewController *) sharedInstance
{
    static SFSmartStoreInspectorViewController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,
                  ^{
                      sharedInstance = [[SFSmartStoreInspectorViewController alloc] init];
                  });
    return sharedInstance;
}

#pragma mark - Present / dimiss

+ (void) present
{
    [[SFSmartStoreInspectorViewController sharedInstance] onClear];
    [[SFRootViewManager sharedManager] pushViewController:[SFSmartStoreInspectorViewController sharedInstance]];
}

+ (void) dismiss
{
    [[SFRootViewManager sharedManager] popViewController:[SFSmartStoreInspectorViewController sharedInstance]];
}

#pragma mark - Results setter

-(void) setResults:(NSArray *)results
{
    if (_results != results) {
        _results = results;
        _countColumns = _results && _results[0] ? [_results[0] count] : 0;
        _countRows = _results ? [_results count] : 0;
        dispatch_async(dispatch_get_main_queue(), ^
                       {
                           [self.resultGrid reloadData];
                       });
    }
}

#pragma mark - Actions handlers

- (void) onBack
{
    [SFSmartStoreInspectorViewController dismiss];
}


- (void) onQuery
{
    [self stopEditing];
    NSString* smartSql = self.queryField.text;
    SFSmartStore* store = [SFSmartStore sharedStoreWithName:kDefaultSmartStoreName];
    @try {
        self.results = [store queryWithQuerySpec:[SFQuerySpec newSmartQuerySpec:smartSql withPageSize:100] pageIndex:0];
    }
    @catch (NSException *exception) {
        [[[UIAlertView alloc] initWithTitle:@"Query failed" message:[exception description] delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
    
}

- (void) onSoups
{
    SFSmartStore* store = [SFSmartStore sharedStoreWithName:kDefaultSmartStoreName];
    NSArray* names = [store allSoupNames];
    
    if ([names count] > 10) {
        self.queryField.text = @"SELECT soupName from soup_names";
    }
    else {
        NSMutableString* q = [NSMutableString string];
        BOOL first = YES;
        for (NSString* name in names) {
            if (!first)
                [q appendString:@" union "];
            [q appendFormat:@"SELECT '%@', count(*) FROM {%@}", name, name];
            first = false;
        }
        self.queryField.text = q;
    }
    [self onQuery];
}

- (void) onIndices
{
    self.queryField.text = @"select soupName, path, columnType from soup_index_map";
    [self onQuery];
}

- (void) onClear
{
    [self stopEditing];
    self.queryField.text = @"";
    self.results = nil;
}

- (void) stopEditing
{
    [self.queryField endEditing:YES];
}



#pragma mark - View layout

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

// TODO get strings from [SFSDKResourceUtils localizedString:@"..."]
- (void)loadView
{
    [super loadView];
    
    // Nav bar
    self.navBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, kNavBarHeight)];
    self.navBar.delegate = self;
    UINavigationItem *navItem = [[UINavigationItem alloc] initWithTitle:@"Inspector"];
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(onBack)];
    UIBarButtonItem *runItem = [[UIBarButtonItem alloc] initWithTitle:@"Run" style:UIBarButtonItemStylePlain target:self action:@selector(onQuery)];
    [navItem setLeftBarButtonItem:backItem];
    [navItem setRightBarButtonItem:runItem];
    [self.navBar setItems:@[navItem] animated:YES];
    [self.view addSubview:self.navBar];
    
    // Query field
    self.queryField = [[UITextView alloc] initWithFrame:CGRectZero];
    self.queryField.delegate = self;
    self.queryField.textColor = [UIColor blackColor];
    self.queryField.font = [UIFont fontWithName:kQueryFieldFontName size:kQueryFieldFontSize];
    self.queryField.text = @"";
    self.queryField.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.queryField.layer.borderWidth = kQueryFieldBorderWidth;
    [self.view addSubview:self.queryField];

    // Buttons
    self.clearButton = [self createButtonWithLabel:@"Clear" action:@selector(onClear)];
    self.soupsButton = [self createButtonWithLabel:@"Soups" action:@selector(onSoups)];
    self.indicesButton = [self createButtonWithLabel:@"Indices" action:@selector(onIndices)];

    // Results grid
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    self.resultGrid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    layout.minimumInteritemSpacing = 0;
    layout.minimumLineSpacing = 0;
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    self.resultGrid.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.resultGrid.layer.borderWidth = kResultGridBorderWidth;
    [self.resultGrid registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:kCellIndentifier];
    [self.resultGrid setBackgroundColor:[UIColor whiteColor]];
    [self.resultGrid setDataSource:self];
    [self.resultGrid setDelegate:self];
    [self.view addSubview:self.resultGrid];
}

- (UIButton*) createButtonWithLabel:(NSString*) label action:(SEL)action
{
    UIButton* button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:label forState:UIControlStateNormal];
    button.backgroundColor = [UIColor whiteColor];
    [button.titleLabel setTextAlignment:NSTextAlignmentCenter];
    [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.titleLabel.font = [UIFont fontWithName:kButtonFontName size:kButtonFontSize];
    button.layer.borderColor = [UIColor lightGrayColor].CGColor;
    button.layer.borderWidth = kButtonBorderWidth;
    [self.view addSubview:button];
    return button;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self layoutSubviews];
}

- (void)viewWillLayoutSubviews
{
    [self layoutSubviews];
    [super viewWillLayoutSubviews];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}

- (void)layoutSubviews
{
    [self layoutNavBar];
    [self layoutQueryField];
    [self layoutButtons];
    [self layoutResultGrid];
    [self.resultGrid reloadData];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (CGFloat) belowFrame:(CGRect) frame {
    return frame.origin.y + frame.size.height;
}

- (void) layoutNavBar
{
    CGFloat x = 0;
    CGFloat y = 0;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = kNavBarHeight;
    self.navBar.frame = CGRectMake(x, y, w, h);
}

- (void)layoutQueryField
{
    CGFloat x = 0;
    CGFloat y = [self belowFrame:self.navBar.frame];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = kQueryFieldHeight;
    self.queryField.frame = CGRectMake(x, y, w, h);
}

- (void)layoutButtons
{
    CGFloat w = self.view.bounds.size.width / 3.0;
    CGFloat y = [self belowFrame:self.queryField.frame];
    CGFloat h = kButtonHeight;
    self.clearButton.frame = CGRectMake(0, y, w, h);
    self.soupsButton.frame = CGRectMake(w, y, w, h);
    self.indicesButton.frame = CGRectMake(w * 2.0, y, w, h);
}

- (void) layoutResultGrid
{
    CGFloat x = 0;
    CGFloat y = [self belowFrame:self.clearButton.frame];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height - y;
    self.resultGrid.frame = CGRectMake(x, y, w, h);
}

#pragma mark - Text view delegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if ( [text isEqualToString:@"\n"] ) {
        [self onQuery];
    }
    
    return YES;
}

#pragma mark - Collection view delegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSString* label = [[self cellDatawithIndexPath:indexPath] description];
    [[[UIAlertView alloc] initWithTitle:nil message:label delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewCell *cell=[collectionView dequeueReusableCellWithReuseIdentifier:kCellIndentifier forIndexPath:indexPath];
    UILabel* labelView = [self cellViewWithIndexPath:indexPath];
    labelView.tag = kLabelTag;
    [[cell.contentView viewWithTag:kLabelTag] removeFromSuperview];
    [cell.contentView addSubview:labelView];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat w = [self cellWidthWithIndexPath:indexPath];
    CGFloat h = [self cellHeightWithIndexPath:indexPath];
    return CGSizeMake(w, h);
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return self.countRows;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.countColumns; // * self.countRows;
}

- (NSString*) compactDescription:(id)obj
{
    NSString* str = [obj description];
    return [str stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, [str length])];
}

-(UILabel *)cellViewWithIndexPath:(NSIndexPath*) indexPath
{
    CGFloat w = [self cellWidthWithIndexPath:indexPath];
    CGFloat h = [self cellHeightWithIndexPath:indexPath];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0,0,w,h)];
    title.textColor = [UIColor blackColor];
    title.layer.borderColor = [UIColor lightGrayColor].CGColor;
    title.layer.borderWidth = kResultCellBorderWidth;
    title.font = [UIFont fontWithName:kResultTextFontName size:kResultTextFontSize];
    title.textAlignment = NSTextAlignmentCenter;
    title.text = [self compactDescription:[self cellDatawithIndexPath:indexPath]];
    return title;
}

- (CGFloat) cellWidthWithIndexPath:(NSIndexPath*) indexPath
{
    return self.countColumns > 0 ? self.resultGrid.frame.size.width / self.countColumns : 0;
}

- (CGFloat) cellHeightWithIndexPath:(NSIndexPath*) indexPath
{
    return kResultCellHeight;
}

- (NSObject*) cellDatawithIndexPath:(NSIndexPath*) indexPath
{
    return ((NSArray*) self.results[indexPath.section])[indexPath.row];
}

@end

