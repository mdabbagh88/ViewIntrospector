//
//  CBWindow.m
//  CBIntrospector
//
//  Created by Christopher Bess on 5/2/12.
//  Copyright (c) 2012 C. Bess. All rights reserved.
//

#import "CBIntrospectorWindow.h"
#import "CBUIViewManager.h"
#import "CBUIView.h"
#import "CBTreeView.h"
#import "CBProjectWindow.h"
#import "CBViewMessengerWindow.h"
#import "NSObject+JSON.h"
#import "CBTitleBarContentView.h"
#import "CBPathItem.h"

// option constants
static NSString * const kCBUserSettingShowAllSubviewsKey = @"show-subviews";
static NSString * const kCBUserSettingMessageActiveViewKey = @"message-active-view";

@interface CBIntrospectorWindow () <NSDraggingDestination, CBUIViewManagerDelegate, NSOutlineViewDataSource, 
    NSOutlineViewDelegate, NSTextFieldDelegate, NSWindowDelegate, NSSplitViewDelegate>
{
    // honored in [loadCurrentViewControls]
    BOOL _doUpdateSelectedViewFile;
}
@property (weak) IBOutlet NSMenuItem *showAllSubviewsMenuItem;
@property (weak) IBOutlet NSMenuItem *messageActiveViewMenuItem;
@property (unsafe_unretained) IBOutlet NSTextView *textView;
@property (weak) IBOutlet NSSplitView *splitView;
@property (weak) IBOutlet CBTreeView *treeView;
@property (weak) IBOutlet NSButton *headerButton;
@property (weak) IBOutlet NSButton *hiddenSwitch;
@property (weak) IBOutlet NSSlider *alphaSlider;
@property (weak) IBOutlet NSTextField *heightTextField;
@property (weak) IBOutlet NSTextField *widthTextField;
@property (weak) IBOutlet NSTextField *topPositionTextField;
@property (weak) IBOutlet NSTextField *leftPositionTextField;
@property (weak) IBOutlet CBProjectWindow *projectWindow;
@property (weak) IBOutlet CBViewMessengerWindow *messengerWindow;
@property (nonatomic, strong) CBTitleBarContentView *titleBarContentView;
@property (nonatomic, weak) NSTextField *focusedTextField;
@property (nonatomic, assign) BOOL doShowAllSubviews;
@property (nonatomic, assign) BOOL doMessageActiveView;
@property (nonatomic, copy) NSString *defaultTitle;
@property (nonatomic, readonly) NSRegularExpression *versionRegex;
- (IBAction)treeNodeClicked:(id)sender;
- (void)loadCurrentViewControls;
- (void)textFieldUpdated:(NSTextField *)textField;
@end

@implementation CBIntrospectorWindow
@synthesize showAllSubviewsMenuItem;
@synthesize messageActiveViewMenuItem;
@synthesize textView;
@synthesize splitView;
@synthesize treeView;
@synthesize headerButton;
@synthesize hiddenSwitch;
@synthesize alphaSlider;
@synthesize heightTextField;
@synthesize widthTextField;
@synthesize topPositionTextField;
@synthesize leftPositionTextField;
@synthesize projectWindow;
@synthesize messengerWindow;
@synthesize viewManager = _viewManager;
@synthesize treeContents = _treeContents;
@synthesize syncDirectoryPath;
@synthesize focusedTextField;
@synthesize doShowAllSubviews = _doShowAllSubviews;
@synthesize simulatorDirectoryPath;
@synthesize defaultTitle;
@synthesize doMessageActiveView = _doMessageActiveView;
@synthesize versionRegex = _versionRegex;


#pragma mark - Properties

- (CBUIViewManager *)viewManager
{
    if (_viewManager == nil)
    {
        _viewManager = [CBUIViewManager new];
        _viewManager.delegate = self;
    }
    return _viewManager;
}

- (NSString *)syncDirectoryPath
{
    return self.viewManager.syncDirectoryPath;
}

- (NSString *)simulatorDirectoryPath
{
    return [[CBUtility sharedInstance] simulatorDirectoryPath];
}

- (BOOL)doShowAllSubviews
{
    return (_doShowAllSubviews = [[NSUserDefaults standardUserDefaults] boolForKey:kCBUserSettingShowAllSubviewsKey]);
}

- (void)setDoShowAllSubviews:(BOOL)show
{
    _doShowAllSubviews = show;
    [[NSUserDefaults standardUserDefaults] setBool:show forKey:kCBUserSettingShowAllSubviewsKey];
}

- (BOOL)doMessageActiveView
{
    _doMessageActiveView = YES;
    if (nil == [[NSUserDefaults standardUserDefaults] objectForKey:kCBUserSettingMessageActiveViewKey])
        return _doMessageActiveView;
    
    return (_doMessageActiveView = [[NSUserDefaults standardUserDefaults] boolForKey:kCBUserSettingMessageActiveViewKey]);
}

- (void)setDoMessageActiveView:(BOOL)doMessageActiveView
{
    _doMessageActiveView = doMessageActiveView;
    [[NSUserDefaults standardUserDefaults] setBool:doMessageActiveView forKey:kCBUserSettingMessageActiveViewKey];
}

- (NSRegularExpression *)versionRegex
{
    if (_versionRegex == nil)
        _versionRegex = [[NSRegularExpression alloc] initWithPattern:@"^[0-9]\\.[0-9]" options:0 error:nil];
    return _versionRegex;
}

#pragma mark - General Overrides

- (void)awakeFromNib
{
    self.delegate = self;
    self.showAllSubviewsMenuItem.state = (self.doShowAllSubviews ? NSOnState : NSOffState);
    self.messageActiveViewMenuItem.state = (self.doMessageActiveView ? NSOnState : NSOffState);
    self.defaultTitle = self.title;
    
	// user can drag a string to create a new note from the initially dropped data
	[self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
    
    // setup text view
    self.textView.font = [NSFont fontWithName:@"Monaco" size:12];
    self.textView.textContainer.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.textView.textContainer.widthTracksTextView = NO;
    [self.textView setHorizontallyResizable:YES];
    
    [self setupWindowTitleBar];
}

- (BOOL)performKeyEquivalent:(NSEvent *)evt
{ // handles key down events
	int key = [evt keyCode];
	NSUInteger modFlag = [evt modifierFlags];
//    NSLog(@"main window key event: %d", key);
    BOOL shiftKey = (modFlag | NSShiftKeyMask);
    
    // ignore keys from the tree view
    if (self.treeView == self.firstResponder)
    {
        switch (key)
        {
            //case 49: // space
            case 36: // enter
                [self reselectCurrentlySelectedNode];
                break;
        }
        
        return NO;
    }
    
    switch (key)
    {
		case 36: // enter key
            if (self.focusedTextField)
                [self textFieldUpdated:self.focusedTextField];
            break;
            
        // arrow keys
        case 125: // down
            [[CBUtility sharedInstance] updateIntValueWithTextField:self.focusedTextField addValue:(shiftKey ? -10 : -1)];
            return YES;
            
        case 126: // up
            [[CBUtility sharedInstance] updateIntValueWithTextField:self.focusedTextField addValue:(shiftKey ? 10 : 1)];
            return YES;
    }
    
	if (modFlag | NSCommandKeyMask) switch (key)
	{		
		case 12: // Q (quit application)
            // confirm closing?
            return NO;
            
		case 13: // W (close window)
            [self orderOut:nil];
            return YES;
    }
    
    return NO;
}

#pragma mark - Drag & Drop

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    return NSDragOperationLink;
}

// provides ability to drag iOS simulator project directories, to open them as a project
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
	NSPasteboard *paste = [sender draggingPasteboard];
	
	if ([[paste types] containsObject:NSFilenamesPboardType])
	{		
		// get the dragged file/dir path
		NSArray *files = [paste propertyListForType:NSFilenamesPboardType];	
        NSString *filePath = files.lastObject;
        
        [self reloadTreeWithFilePath:filePath];
    }
    
    return NO;
}

#pragma mark - Events

- (IBAction)alphaSliderChanged:(id)sender 
{
    self.viewManager.currentView.alpha = self.alphaSlider.floatValue / 100;
}

- (IBAction)hiddenSwitchChanged:(id)sender 
{
    self.viewManager.currentView.hidden = self.hiddenSwitch.state;
}

- (IBAction)treeNodeClicked:(id)sender 
{
    [self reselectCurrentlySelectedNode];
}

- (IBAction)headerButtonClicked:(id)sender 
{
    if (self.viewManager.currentView)
    {
        [self.treeView reloadData];
        [self expandViewTree];
        
        [self selectTreeItemWithMemoryAddress:self.viewManager.currentView.memoryAddress];
    }
}

// menu item action
- (IBAction)reloadViewTreeClicked:(id)sender 
{
    [self reloadTree];
}

- (IBAction)showAllSubviewsClicked:(id)sender 
{
    self.doShowAllSubviews = !self.doShowAllSubviews;
    self.showAllSubviewsMenuItem.state = (self.doShowAllSubviews ? NSOnState : NSOffState);
    
    [self reloadTree];
}

- (IBAction)openSimulatorFolder:(id)sender 
{
    [[NSWorkspace sharedWorkspace] openFile:self.simulatorDirectoryPath];
}

- (IBAction)showProjectsWindowClicked:(id)sender 
{
    [self.projectWindow makeKeyAndOrderFront:nil];
}

- (IBAction)sendMessageButtonClicked:(id)sender
{
    self.messengerWindow.introspectorWindow = self;
    self.messengerWindow.receiverView = self.viewManager.currentView;
    [self.messengerWindow makeKeyAndOrderFront:nil];
}

- (IBAction)messageActiveViewClicked:(id)sender
{
    self.doMessageActiveView = !self.doMessageActiveView;
    self.messageActiveViewMenuItem.state = (self.doMessageActiveView ? NSOnState : NSOffState);
}

- (IBAction)clearMessengerHistory:(id)sender
{
    [self.messengerWindow clearHistory];
}

#pragma mark - Misc

- (void)expandViewTree
{
    // expand it all to allow the 'walking' tree logic to work as expected, being able to find/select any node
    [self.treeView expandItem:[self.treeView itemAtRow:0] expandChildren:YES];
}

- (void)reselectCurrentlySelectedNode
{
    NSDictionary *viewInfo = [self.treeView itemAtRow:self.treeView.selectedRow];
    CBDebugLog(@"selected: %@", [viewInfo valueForKey:kUIViewClassNameKey]);
    [self loadControlsWithJSON:viewInfo];
}

- (void)loadControlsWithJSON:(NSDictionary *)jsonInfo
{
    self.viewManager.currentView = [[CBUIView alloc] initWithJSON:jsonInfo];
    self.viewManager.currentView.syncFilePath = [self.syncDirectoryPath stringByAppendingPathComponent:kCBCurrentViewFileName];
    
    [self loadCurrentViewControls];
}

- (void)loadCurrentViewControls
{
    CBUIView *view = self.viewManager.currentView;
    
    if (_doUpdateSelectedViewFile)
    {
        [self.viewManager updateSelectedViewToView:view];
    }
    
    if (self.doMessageActiveView)
        self.messengerWindow.receiverView = view;
    self.headerButton.title = nssprintf(@"<%@: 0x%@>", view.className, view.memoryAddress);
    if (view.viewDescription)
        self.textView.string = view.viewDescription;
    
    self.leftPositionTextField.stringValue = nssprintf(@"%i", (int)NSMinX(view.frame));
    self.topPositionTextField.stringValue = nssprintf(@"%i", (int)NSMinY(view.frame));
    self.widthTextField.stringValue = nssprintf(@"%i", (int)NSWidth(view.frame));
    self.heightTextField.stringValue = nssprintf(@"%i", (int)NSHeight(view.frame));
    
    self.hiddenSwitch.state = view.hidden;
    self.alphaSlider.floatValue = view.alpha * 100;
}

- (void)reloadTree
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.syncDirectoryPath])
    {
        NSString *msg = [@"Unable to reload the tree.\nCheck path: " stringByAppendingString:self.syncDirectoryPath ?: @"None"];
        [[CBUtility sharedInstance] showMessageBoxWithString:msg];
        return;
    }
    
    // load json dictionary from disk
    NSString *filePath = [self.syncDirectoryPath stringByAppendingPathComponent:kCBTreeDumpFileName];
    NSDictionary *treeInfo = [[CBUtility sharedInstance] dictionaryWithJSONFilePath:filePath];
    self.treeContents = treeInfo;
    [self.treeView reloadData];
    
    // update the title, adding the bundle name
    self.title = nssprintf(@"%@ - %@", [self bundleNameForPath:self.syncDirectoryPath], self.defaultTitle);
    
    // make sure it is syncing
    if (!self.viewManager.syncing && treeInfo.count > 0)
        [self.viewManager sync];
    
    [self expandViewTree];
}

- (void)reloadTreeWithFilePath:(NSString *)filePath
{
    BOOL isDir;
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDir] && isDir)
    {
        self.viewManager.syncDirectoryPath = filePath;
        
        // process file and load into UIView controls
        NSString *syncFilePath = [filePath stringByAppendingPathComponent:kCBCurrentViewFileName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:syncFilePath])
        {
            NSError *error = nil;
            NSString *jsonString = [NSString stringWithContentsOfFile:syncFilePath
                                                             encoding:NSUTF8StringEncoding
                                                                error:&error];
            
            NSDictionary *jsonInfo = [jsonString objectFromJSONString];
            [self loadControlsWithJSON:jsonInfo];
            
            if (jsonInfo.count)
                [self.viewManager sync];
        }
        
        [self reloadTree];
    }
    else
    {
        [[CBUtility sharedInstance] showMessageBoxWithString:NSLocalizedString(@"Unable to load a UIView from the directory.", nil)];
    }
}

- (BOOL)allowChildrenWithJSON:(NSDictionary *)jsonInfo
{
    if (self.doShowAllSubviews)
        return YES;
    
    NSString *className = [jsonInfo valueForKey:kUIViewClassNameKey];
    
    // don't allow below class to be branches
    static NSMutableArray *items = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = [[NSMutableArray alloc] initWithObjects:
                 @"UITableViewCell",
                 @"UISegmentedControl",
                 @"UISlider",
                 @"UIPageControl",
                 @"UITextField",
                 @"UIProgressView",
                 @"UIActivityIndicatorView",
                 nil];
    });
    
    // try to find the class name
    for (NSString *name in items)
    {
        if ([name isEqualToString:className])
            return NO;
    }
    
    return YES;
}

- (void)switchProjectToDirectoryPath:(NSString *)bundlePath
{
    // strip off the last part of the path
    NSArray *components = [bundlePath pathComponents];
    NSString *path = [[components subarrayWithRange:NSMakeRange(0, components.count - 1)] componentsJoinedByString:@"/"];
    path = [path stringByAppendingPathComponent:@"Library/Caches"];
    
    // set the dir path and reload tree
    [self reloadTreeWithFilePath:path];
    
    [self makeKeyAndOrderFront:nil];
}

- (NSString *)bundleNameForPath:(NSString *)aPath
{
    if (!aPath)
        return nil;
    
    NSArray *components = [aPath pathComponents];
    NSString *guidPath = [[components subarrayWithRange:NSMakeRange(0, components.count - 2)] componentsJoinedByString:@"/"];
    
    // get the bundle
    NSArray *pathNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:guidPath error:nil];
    for (NSString *name in pathNames)
    {
        if ([name hasSuffix:@".app"])
            return name;
    }
    
    return nil;
}

- (void)textFieldUpdated:(NSTextField *)textField
{
    CBUIView *view = self.viewManager.currentView;
    NSRect frame = view.frame;
    
    if (self.leftPositionTextField == textField)
    {
        frame.origin.x = textField.intValue;
    }
    else if (self.topPositionTextField == textField)
    {
        frame.origin.y = textField.intValue;
    }
    else if (self.widthTextField == textField)
    {
        frame.size.width = textField.intValue;
    }
    else if (self.heightTextField == textField)
    {
        frame.size.height = textField.intValue;
    }
    
    view.frame = frame;
}

#pragma mark - Find in tree

- (NSDictionary *)itemFromJSON:(NSDictionary *)jsonInfo withMemoryAddress:(NSString *)memAddress
{
    if ([[jsonInfo valueForKey:kUIViewMemoryAddressKey] isEqualToString:memAddress])
        return jsonInfo;
    
    // check the subviews
    NSArray *subviewsInfo = [jsonInfo valueForKey:kUIViewSubviewsKey];
    for (NSDictionary *subviewInfo in subviewsInfo)
    {
        NSDictionary *info = [self itemFromJSON:subviewInfo withMemoryAddress:memAddress];
        if (info)
            return info;
    }
    
    return nil;
}

- (void)selectTreeItemWithMemoryAddress:(NSString *)memAddress
{
    // traverse tree
    NSDictionary *itemInfo = [self itemFromJSON:self.treeContents withMemoryAddress:memAddress];
    if (itemInfo == nil)
        return;
    
    NSInteger nRow = [self.treeView rowForItem:itemInfo];
    
    if (nRow < 0) 
    {
        // remove selection
        [self.treeView deselectRow:self.treeView.selectedRow];
        return;
    }
    
    // expand its parent to make sure it is visible
    NSDictionary *parentInfo = [self.treeView parentForItem:itemInfo];
    [self.treeView expandItem:parentInfo];
    
    // select it
    [self.treeView selectRowIndexes:[NSIndexSet indexSetWithIndex:nRow] byExtendingSelection:NO];
    
    [self.treeView scrollRowToVisible:nRow];
}

#pragma mark - CBUIViewManagerDelegate

- (void)viewManagerSavedViewToDisk:(CBUIViewManager *)manager
{
    
}

// typically called when the user selects a view in the simulator
- (void)viewManagerUpdatedViewFromDisk:(CBUIViewManager *)manager
{
    [self loadCurrentViewControls];
    
    // locate the view in the tree
    [self selectTreeItemWithMemoryAddress:manager.currentView.memoryAddress];
}

- (void)viewManagerClearedView:(CBUIViewManager *)manager
{
    self.messengerWindow.receiverView = nil;
    [self.headerButton setTitle:@"View Introspector"];
    self.leftPositionTextField.stringValue = self.topPositionTextField.stringValue = // below
    self.widthTextField.stringValue = self.heightTextField.stringValue = @"";
    
    self.alphaSlider.floatValue = 100;
    self.hiddenSwitch.state = NSOffState;
    self.textView.string = @"";
    
    // clear tree view
    self.treeContents = nil;
    [self.treeView reloadData];
    self.title = self.defaultTitle;
    
    [[NSFileManager defaultManager] removeItemAtPath:[self.syncDirectoryPath stringByAppendingPathComponent:kCBSelectedViewFileName] error:nil];
}

#pragma mark - NSOutlineDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (!item)
        item = self.treeContents;
    
    if (![self allowChildrenWithJSON:item])
        return 0;
    
    return [[item valueForKey:kUIViewSubviewsKey] count];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if (!item)
        item = self.treeContents;
    
    if (![self allowChildrenWithJSON:item])
        return NO;
    
    NSUInteger count = [[item valueForKey:kUIViewSubviewsKey] count];
    return count != 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if (!item)
        item = self.treeContents;
    
    NSArray *items = [item valueForKey:kUIViewSubviewsKey];
    return [items objectAtIndex:index];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    // not needed, the view is setup in [outlineView:willDisplayCell:...]
    return nil;
}

#pragma mark - NSOutlineViewDelegate

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(NSButtonCell *)cell forTableColumn:(NSTableColumn *)tableColumn item:(NSDictionary *)jsonInfo
{
    // get the name
    NSString *name = [jsonInfo valueForKey:kUIViewClassNameKey];
    if ([name hasPrefix:@"UI"])
        name = [name substringFromIndex:2]; // remove the class prefix
    
    // get the image
    cell.title = name;
    cell.image = [NSImage imageNamed:@"NSView.icns"];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    [self reselectCurrentlySelectedNode];
    _doUpdateSelectedViewFile = NO;
}

// only called when the user clicks or selects a node, not when selected programmactically
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    // tell the device to change its selected view
    _doUpdateSelectedViewFile = YES;
    return YES;
}

#pragma mark - NSTextFieldDelegate

- (void)controlDidBecomeFirstResponder:(NSResponder *)responder
{
    self.focusedTextField = (NSTextField*) responder;
}

#pragma mark - NSSplitView Delegate

- (CGFloat)splitView:(NSSplitView *)theSplitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
    return CGRectGetWidth(theSplitView.bounds) * .3f;
}

- (CGFloat)splitView:(NSSplitView *)theSplitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex
{
    return CGRectGetWidth(theSplitView.bounds) * .7f;
}

#if 0
- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex
{
    return 450;
}

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view
{
    return NO;
}
#endif

#pragma mark - NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    // check ahead of time to avoid the alert
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.syncDirectoryPath])
    {
        // assumes no selection means no tree contents loaded
        if (self.treeView.selectedRow < 0)
        {
            [self reloadTree];
        }
    }
}

#pragma mark - Window

- (void)setupWindowTitleBar
{
    self.titleBarHeight = 40.0;
	self.trafficLightButtonsLeftMargin = 13.0;

    self.titleBarContentView = [[CBUtility sharedInstance] objectWithClass:[CBTitleBarContentView class] inNibNamed:@"CBTitleBarContentView"];
    self.titleBarContentView.frame = self.titleBarView.bounds;
    [self.titleBarView addSubview:self.titleBarContentView];
    
    [self reloadTitleBar];
    
    /*
    self.titleBarDrawingBlock = ^(BOOL drawsAsMainWindow, CGRect drawingRect, CGPathRef clippingPath) {
        CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
        CGContextAddPath(ctx, clippingPath);
        CGContextClip(ctx);
        
        NSGradient *gradient = nil;
        if (drawsAsMainWindow)
        {
            gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0 green:0.319 blue:1 alpha:1]
                                                     endingColor:[NSColor colorWithCalibratedRed:0 green:0.627 blue:1 alpha:1]];
            [[NSColor darkGrayColor] setFill];
        }
        else
        { // inactive window
            // set the default non-main window gradient colors
            gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.851f alpha:1]
                                                     endingColor:[NSColor colorWithCalibratedWhite:0.929f alpha:1]];
            [[NSColor colorWithCalibratedWhite:0.6f alpha:1] setFill];
        }
        
        [gradient drawInRect:drawingRect angle:90];
        NSRectFill(NSMakeRect(NSMinX(drawingRect), NSMinY(drawingRect), NSWidth(drawingRect), 1));
    };
    */
    //    NSView *titleBarView = aWindow.titleBarView;
}

#pragma mark - TitleBar Content

- (void)reloadTitleBar
{
    NSArray *pathItems = [self projectPathItems];
    [self.titleBarContentView reloadWithPathItems:pathItems];
}

- (BOOL)textIsVersionString:(NSString *)string
{
    NSArray *matches = [self.versionRegex matchesInString:string options:NSMatchingReportCompletion range:NSMakeRange(0, string.length)];
    return (matches.count != 0);
}

- (NSArray *)projectPathItems
{
     NSRegularExpression *guidRegex = [NSRegularExpression regularExpressionWithPattern:@"([A-Z0-9]{8})-([A-Z0-9]{4})-([A-Z0-9]{4})-([A-Z0-9]{4})-([A-Z0-9]{12})"
                                                                               options:0 error:nil];
    // build the path items collection
    NSArray *pathItems = [CBPathItem pathItemsAtPath:[[CBUtility sharedInstance] simulatorDirectoryPath] recursive:YES block:^BOOL(CBPathItem *item) {
        BOOL isDir;
        if ([item.name hasSuffix:@".app"])
            return YES;
        else if ([item.name isEqualToString:@"Applications"])
            return YES;
        else if ([self textIsVersionString:item.name]
                 && ([[NSFileManager defaultManager] fileExistsAtPath:item.path isDirectory:&isDir] && isDir))
            return YES;
        else if ([guidRegex matchesInString:item.name options:NSMatchingReportCompletion range:NSMakeRange(0, item.name.length)].count)
            return YES;
        
        return NO; 
    }];
    
    return pathItems;
}

@end
