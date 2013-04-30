//
//  idConsoleWindowController.m
//  id Tech Mac OS X
//
//  Copyright (c) 2013 Jeremiah Sypult. All rights reserved.
//

#import "idConsoleWindowController.h"
#import "macosx_local.h"

extern char *va( const char *fmt, ... );

char		consoleText[1024] = {0};
char		returnedText[1024] = {0};

@implementation idConsoleWindowController

@synthesize textView = _textView;
@synthesize textField = _textField;

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if ( self ) {
        // Initialization code here.
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
	// TODO: preferences
	self.window.allowsConcurrentViewDrawing = YES;
	_textView.canDrawConcurrently = YES;

	//_textView.delegate = self;
	_textField.delegate = self;
	_textField.nextKeyView = _textField;
	[self.window makeFirstResponder:_textField];
}

- (void)consoleCopy
{
	// TODO:
}

- (void)consoleClear
{
	[_textView.textStorage replaceCharactersInRange:NSMakeRange(0, _textView.string.length)
												withString:@" "];
	[_textView scrollRangeToVisible:NSMakeRange(_textView.string.length, 0)];
	_textView.needsDisplay = YES;
}

- (void)consoleOutput:(NSString*)string
{
	static const int maxLength = 32768;
	static const int displayEvery = 8;
	static int displayCount = 0;

	if ( _textView.string.length >= maxLength ) {
		[self consoleClear];
	}

	// TODO: color with attributed strings? eep... :|
	if ( string && _textView ) {
		[_textView.textStorage replaceCharactersInRange:NSMakeRange(_textView.textStorage.length, 0)
													withString:string];
		[_textView scrollRangeToVisible:NSMakeRange(_textView.string.length, 0)];

		if ( _textView.window.isVisible ) {

			// force display updates
			if ( displayCount >= displayEvery ) {
				displayCount = 0;
				[_textView display];
			} else {
				_textView.needsDisplay = YES;
			}

			displayCount++;
		}
	}
}

- (IBAction)consoleInputLine:(id)sender
{
	char inputBuffer[1024] = {0};

	if ( sender == _textField ) {
		sprintf( inputBuffer, "%s\n", [_textField.stringValue cStringUsingEncoding:NSUTF8StringEncoding] );

		// clear the console
		_textField.stringValue = @"";

		strncpy( consoleText, inputBuffer, strlen(inputBuffer) );
		Sys_Printf( va( "]%s\n", inputBuffer ) );
	}
}

- (IBAction)consoleSelector:(id)sender
{
	NSInteger tag = [sender tag];

	switch ( tag ) {
		default: NSLog(@"idConsoleWindowController consoleSelector: unhandled tag %i", tag); break;
		case 1: [self consoleCopy]; break;
		case 2: [self consoleClear]; break;
	}
}

#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
	if ( commandSelector == @selector(insertTab:) ) {
		return NO;
	}

	return YES;
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
}

@end
