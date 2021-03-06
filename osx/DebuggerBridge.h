//
//  DebuggerBridge.h
//  OpenNestopia
//
//  Created by Kefu Chai on 16/09/12.
//
//

#import <Foundation/Foundation.h>

typedef enum : char {
    A = 'A',
    X = 'X',
    Y = 'Y',
    S = 'S',
    M = 'M',
    P = 'P',
    SP = 'S',
    PC = 'C',
    UNKNOWN = '-',
} Reg;

@interface Register : NSObject
+ (Reg)regWithName:(NSString*)name;
+ (NSString *)nameWithReg:(Reg)reg;
@end

@class Breakpoint, Decoded;

@interface DebuggerBridge : NSObject

- (id)initWithEmu:(void *)emu;

- (uint8_t)peek8:(uint16_t)addr;
- (void)poke8:(uint16_t)addr with:(uint8_t)data;
- (uint16_t)peekReg:(Reg)reg;
- (void)pokeReg:(Reg)reg with:(uint8_t)data;

- (int)setBreakpoint:(Breakpoint *)bp;
- (BOOL)resetBreakpoint:(int)index;
- (BOOL)disableBreakpoint:(int)index;
- (BOOL)enableBreakpoint:(int)index;
- (Breakpoint *)breakpointAtIndex:(NSUInteger)index;

- (void)next;
- (void)stepInto;
- (void)pause;
- (void)resume;
- (void)until:(NSUInteger)address;

- (BOOL)shouldExec;

- (Decoded *)disassemble:(NSUInteger *)addr;

@end
