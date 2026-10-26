#import <Cocoa/Cocoa.h>
#include "Engine.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

@interface AavaApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation AavaApplication
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent scope;
  if (event.type == NSEventTypeKeyDown) {
    NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
    NSString* key = event.charactersIgnoringModifiers.lowercaseString;
    if ((event.keyCode == 53 && flags == 0) || (flags == NSEventModifierFlagCommand && [key isEqualToString:@"w"])) {
      if (AavaDismissSurface()) return;
    }
    SEL action = NULL;
    if (flags == (NSEventModifierFlagCommand | NSEventModifierFlagShift) && [key isEqualToString:@"c"]) action = NSSelectorFromString(@"copyURL");
    if (flags == NSEventModifierFlagCommand && [key isEqualToString:@"d"]) action = NSSelectorFromString(@"savePage");
    if (flags == (NSEventModifierFlagCommand | NSEventModifierFlagOption)) {
      if (event.keyCode == 124 || event.keyCode == 30 || [key isEqualToString:@"]"]) action = NSSelectorFromString(@"nextSpace");
      if (event.keyCode == 123 || event.keyCode == 33 || [key isEqualToString:@"["]) action = NSSelectorFromString(@"previousSpace");
    }
    if (action && [self.delegate respondsToSelector:action]) { [self sendAction:action to:self.delegate from:self]; return; }
  }
  [super sendEvent:event];
}
- (void)terminate:(id)sender {
    id delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(quit)]) [delegate performSelector:@selector(quit)];
    else AavaEngineQuit();
}
@end

class AavaApp final : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
  CefRefPtr<CefClient> GetDefaultClient() override { return AavaEngineDefaultClient(); }
  void OnContextInitialized() override { AavaStart(); }
  bool OnAlreadyRunningAppRelaunch(CefRefPtr<CefCommandLine> command_line, const CefString& current_directory) override {
    AavaFocus();
    CefCommandLine::ArgumentList arguments; command_line->GetArguments(arguments);
    for (auto& arg : arguments) {
      NSString* value = [NSString stringWithUTF8String:arg.ToString().c_str()];
      if ([value hasPrefix:@"http://"] || [value hasPrefix:@"https://"]) {
        NSURL* url = [NSURL URLWithString:value];
        if (url && [NSApp.delegate respondsToSelector:@selector(application:openURLs:)]) [NSApp.delegate application:NSApp openURLs:@[url]];
      }
    }
    return true;
  }
 private:
  IMPLEMENT_REFCOUNTING(AavaApp);
};

int main(int argc, char* argv[]) {
  CefScopedLibraryLoader loader;
  if (!loader.LoadInMain()) return 1;
  @autoreleasepool {
    [AavaApplication sharedApplication];
    CefMainArgs args(argc, argv);
    CefSettings settings;
    settings.windowless_rendering_enabled = true;
    NSString* appName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"Aava";
    CefString(&settings.keychain_service_name) = [appName stringByAppendingString:@" Safe Storage"].UTF8String;
    CefString(&settings.keychain_account_name) = appName.UTF8String;
    NSString* data = NSProcessInfo.processInfo.environment[@"AAVA_DATA_DIRECTORY"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Aava"];
    NSString* root = [data stringByAppendingPathComponent:@"Chromium"];
    [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    CefString(&settings.root_cache_path) = root.UTF8String;
    CefString(&settings.log_file) = [root stringByAppendingPathComponent:@"engine.log"].UTF8String;
    settings.log_severity = LOGSEVERITY_WARNING;
    settings.persist_session_cookies = true;
    CefRefPtr<AavaApp> app = new AavaApp();
    if (!CefInitialize(args, settings, app, nullptr)) return CefGetExitCode();
    CefRunMessageLoop();
    CefShutdown();
  }
  return 0;
}
