#import "OpenNestopiaController.h"
#import "OpenNestopiaPreferences.h"
#import "DebuggerWindowController.h"


@implementation OpenNestopiaController

- (void)windowWillMiniaturize:(NSNotification *)aNotification 
{ 
    [nesView copyGLToBackingStore]; 
} 

- (void)windowWillClose:(NSNotification *)aNotification
{
	[nesView powerOff];
}

-(IBAction)buttonChanged:(id)sender
{
	NSInteger row;
	
	[sender getNumberOfRows:&row columns:nil];
	
	for (NSInteger i = 0; i<row; i++) {
		[sender cellAtRow:i column:1];
		// NSPopUpButtonCell* temp = [sender cellAtRow:i column:1];
        // 
	}
}

-(IBAction)testDips:(id)sender
{	
//	if([nestopiaView numOfDips]>0)
//	{
//		NSTextFieldCell* tempCell;
//		NSPopUpButtonCell* popupCell;
//		NSArray* test;
//		
//		int i;
//		int numOfRows = [dipSwitchLabels numberOfRows];
//		for(i = 0;i<numOfRows;i++)
//		{
//			[dipSwitchLabels removeRow:0];
//		}
//		
//		for(i = 0;i<[nestopiaView numOfDips];i++)
//		{
//			tempCell = [[NSTextFieldCell alloc] initTextCell: [nestopiaView getDipName:i]];
//			//[tempStr release];
//			popupCell = [[NSPopUpButtonCell alloc] init];
//			[popupCell setPullsDown:false];
//			[popupCell setTarget:self];
//			[popupCell setAction:@selector(buttonChanged:)];
//		
//			[popupCell  addItemsWithTitles:[nestopiaView getDipValues:i]];
//			[popupCell selectItemAtIndex:[nestopiaView getSelectedValue:i]];
//			[popupCell setEnabled:YES];	
//			
//			test = [NSArray arrayWithObjects:tempCell,popupCell, nil];
//			[dipSwitchLabels addRowWithCells:test];
//		}
//		
//		[dipSwitchLabels sizeToCells];
//		[dipSwitchLabels sizeToFit];
//		NSRect labelFrame = [dipSwitchLabels frame];
//		[dipSwitchPanel setContentSize:NSMakeSize(labelFrame.size.width+40,labelFrame.size.height+40)];
//		[dipSwitchLabels setFrameOrigin:NSMakePoint(20,20)];
//		[dipSwitchPanel makeKeyAndOrderFront:nil];
//	}
//	else
//	{
//		NSAlert *alert = [[NSAlert alloc] init];
//		[alert addButtonWithTitle:@"Ok"];
//		[alert setMessageText:@"This game does not have any DIP switches."];
//		[alert setAlertStyle:NSWarningAlertStyle];
//		[alert beginSheetModalForWindow:mainWindow modalDelegate:nil didEndSelector:nil contextInfo:nil];
//	}
}

- (IBAction)openPreferencesWindow:(id)sender
{	
	[[OpenNestopiaPreferences sharedPrefsWindowController] showWindow:nil];
}

- (IBAction)openDebugConsole:(id)sender
{
    DebuggerWindowController *debuggerWindowController = [[DebuggerWindowController alloc] initWithEmu:nesView.emu];
    if (debuggerWindowController) {
        [debuggerWindowController showWindow:self];
    }
}


@end
