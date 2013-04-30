//
//  idConsoleWindowController.h
//  id Tech Mac OS X
//
//  Copyright (c) 2013 Jeremiah Sypult. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface idConsoleWindowController : NSWindowController <NSTextViewDelegate, NSTextFieldDelegate>
{
	NSTextView	*_textView;
	NSTextField *_textField;
}

@property (assign) IBOutlet NSTextView *textView;
@property (assign) IBOutlet NSTextField *textField;

- (void)consoleCopy;
- (void)consoleClear;
- (void)consoleOutput:(NSString*)string;
- (IBAction)consoleInputLine:(id)sender;
- (IBAction)consoleSelector:(id)sender;

@end
