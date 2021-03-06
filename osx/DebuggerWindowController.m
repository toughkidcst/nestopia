//
//  DebuggerController.m
//  OpenNestopia
//
//  Created by Kefu Chai on 04/09/12.
//
//

#import "DebuggerWindowController.h"
#import "Breakpoint.h"
#import "DebuggerBridge.h"
#import "NESGameCore.h"
#import "CommandParser.h"
#import "DisassembledTableController.h"
#import "DisplayTableController.h"
#import "NSFont+DebugConsole.h"


@interface DebuggerWindowController ()
@property(nonatomic) id pausedObserver;
@property(nonatomic) id resumedObserver;
@end

@implementation DebuggerWindowController

- (void)setGameCore:(NESGameCore *)gameCore
{
    _gameCore = gameCore;
    self.debugger = [[DebuggerBridge alloc] initWithEmu:gameCore.nesEmu];
    _disassembledController.debugger = self.debugger;
    _displayController.debugger = self.debugger;
}


- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        _commandParser = [[CommandParser alloc] initWithRunner:self];
    }
    
    return self;
}

- (void)awakeFromNib {
    _disassembledController =
        [[DisassembledTableController alloc] initWithNibName:@"DisassembledTableController" bundle:nil];
    [_disassembledView addSubview:_disassembledController.view];
    _disassembledController.view.frame = _disassembledView.bounds;

    _displayController =
        [[DisplayTableController alloc] initWithNibName:@"WatchTableController" bundle:nil];
    [_displayView addSubview:_displayController.view];
    _displayController.view.frame = _displayView.bounds;

    self.consoleView.font = [NSFont debugConsoleInputFont];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    if (self.gameCore.pauseEmulation) {
        // already paused
        [self pausedAtPc:self.gameCore.pc withPrompt:YES];
        if (!self.pausedObserver) {
            [self attachToGameCore:self.gameCore];
        }
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    [self detachFromGameCore:self.gameCore];
}

#pragma mark -
#pragma mark DebuggerDelegate

- (void)willStepToAddress:(NSUInteger)pc
{
    [self pausedAtPc:pc withPrompt:YES];
}

- (void)breakpoint:(NSUInteger)index triggeredAt:(NSUInteger)pc {
    [self pausedAtPc:pc withPrompt:NO];
    Breakpoint * breakpoint = [self.debugger breakpointAtIndex:index];
    NSAssert(breakpoint, @"breakpoint #%ld not found", index);
    [self printStoppedByBreakpoint:breakpoint at:pc];
}

- (void)printConsole:(NSString *)fmt, ...
{
    va_list args;
    va_start(args, fmt);
    NSString *msg =
    [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    [self.consoleView insertText:msg];
    [self.consoleView insertNewline:self];
    NSRange range = NSMakeRange(committedLength, msg.length);
    [self.consoleView setFont:[NSFont debugConsoleOutputFont]
                        range:range];
    committedLength = self.consoleView.string.length;
}

#pragma mark -
#pragma mark private
- (void)pausedAtPc:(NSUInteger)pc withPrompt:(BOOL)prompt {
    @synchronized(self) {
        [_disassembledController updateWithPc:pc];
        [_displayController update];
        if (prompt) {
            [self printPrompt];
        }
    }
}

- (void)attachToGameCore:(NESGameCore *)gameCore {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    self.pausedObserver =
        [center addObserverForName:NESEmulatorDidPauseNotification
                            object:nil
                             queue:mainQueue
                        usingBlock:^(NSNotification *note) {
                            NSLog(@"received pause message");
                            NESGameCore *gameCore = [note object];
                            [self pausedAtPc:gameCore.pc withPrompt:YES];
                        }];
    self.resumedObserver =
        [center addObserverForName:NESEmulatorDidResumeNotification
                            object:nil
                             queue:mainQueue
                        usingBlock:^(NSNotification *note) {
                            NSLog(@"received resume message");
                            [self printConsole:@"Emulator resuming"];
                        }];

    gameCore.execCondition = ^ {
        return [self.debugger shouldExec];
    };
    [self.debugger pause];
//    if (!gameCore.pauseEmulation)
//        gameCore.pauseEmulation = YES;
}

- (void)detachFromGameCore:(NESGameCore *)gameCore {
    [self.debugger resume];
    gameCore.execCondition = nil;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self.pausedObserver];
    [center removeObserver:self.resumedObserver];
}

#pragma mark -
#pragma mark CommandRunner
- (void)printVar:(NSUInteger)address {
    uint8_t value = [self.debugger peek8:address];
    // this is fake $(n) variable 8P
    [self printConsole:@"$%d = %d", _printCount, value];
}

- (void)set:(uint16_t)address withValue:(uint8_t)value {
    [self.debugger poke8:address with:value];
    // no news is good news
}

- (void)setBreakpoint:(Breakpoint *)bp {
    int index = [self.debugger setBreakpoint:bp];
    [self printConsole:@"Breakpoint %d: %@", index, bp];
}

- (void)removeBreakpoint:(NSUInteger)index {
    if ([self.debugger resetBreakpoint:index])
        return;
    [self checkBreakpointAt:index];
}

- (void)disableBreakpoint:(NSUInteger)index {
    if ([self.debugger disableBreakpoint:index])
        return;
    [self checkBreakpointAt:index];
}

- (void)enableBreakpoint:(NSUInteger)index {
    if ([self.debugger enableBreakpoint:index])
        return;
    [self checkBreakpointAt:index];
}

- (void)checkBreakpointAt:(NSUInteger)index {
    if (![self.debugger breakpointAtIndex:index]) {
        [self printConsole:@"No breakpoint number %d", index];
    } else {
        [self printConsole:@"Ops"];
    }
}

- (void)next {
//    self.gameCore.pauseEmulation = NO;
    [self.debugger next];
}

- (void)stepIn {
//    self.gameCore.pauseEmulation = NO;
    [self.debugger stepInto];
}

- (void)until {
//    self.gameCore.pauseEmulation = NO;
    [self.debugger until:self.gameCore.pc];
}

- (void)resume {
    self.gameCore.pauseEmulation = NO;
    [self.debugger resume];
}

- (void)untilHitAddress:(NSUInteger)address {
    self.gameCore.pauseEmulation = NO;
    [self.debugger until:address];
}

- (void)display:(NSString *)var {
    [_displayController addDisplay:var];
}

- (void)undisplay:(NSUInteger)index {
    [_displayController removeDisplay:index];
}

- (void)searchBytes:(NSData *)bytes {
    // TODO
}

- (void)repeatLastCommand {
    if (_lastCommand) {
        [_commandParser parse:_lastCommand];
    } else {
        [self printPrompt];
    }
}

#pragma mark -
#pragma mark NSTextView delegate methods

- (void)printPrompt {
    NSString *prompt = @"(ndb) ";
    [self.consoleView insertText:prompt];
    NSRange range = NSMakeRange(committedLength, prompt.length-1);
    [self.consoleView setTextColor:[NSColor colorWithSRGBRed:0.34
                                                       green:0.43
                                                        blue:1
                                                       alpha:1]
                             range:range];
    NSLog(@"pc = %#06lx", self.gameCore.pc);
    committedLength = self.consoleView.string.length;
}

- (void)printStoppedByBreakpoint:(Breakpoint*)breakpoint at:(NSUInteger)pc
{
    // see for colored string
    [self.consoleView insertText:[NSString stringWithFormat:@"Breakpoint %ld, at %#04lx",
                      breakpoint.index, pc]];
    committedLength = self.consoleView.string.length;
}

- (void)runCommand:(NSString *)command {
    if (command.length > 0) {
        _lastCommand = command;
        [_commandParser parse:command];
        if (_commandParser.error) {
            [self printConsole:@"Undefined command: \"%@\".", command];
            [self printPrompt];
        }
    } else {
        [self repeatLastCommand];
    }
}

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString {
    // Allow changes only for uncommitted text
    return affectedCharRange.location >= committedLength;
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    BOOL retval = NO;

    // When return is entered, record and color the newly committed text
    if (@selector(insertNewline:) == commandSelector) {

        NSUInteger textLength = textView.string.length;
        [textView setSelectedRange:NSMakeRange(textLength, 0)];
        NSString *command = [[textView.string substringFromIndex:committedLength] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [textView insertText:@"\n"];
        textLength++;
        committedLength = textLength;
        [self runCommand:command];
        retval = YES;
    }
    return retval;
}

@end
