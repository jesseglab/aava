// Standalone CEF integration harness. Link with Main.o, Engine.o and ChromeHost.o.
// Run only in a dedicated test bundle with AAVA_DATA_DIRECTORY set to an empty temporary directory.
#import <Cocoa/Cocoa.h>
#include "Engine.h"
#include "include/cef_app.h"
#include "include/cef_cookie.h"
#include "include/cef_request_context_handler.h"
#include <string>

namespace {
const char* target = "6D608592-F116-48EF-9622-49DD62C8372A";
const char* other = "245CCABA-C25A-42F9-9954-FAEDCFC97AD9";
NSString* root;
bool persisted = false;
void Finish(bool ok, NSString* detail) {
  NSDictionary* report = @{@"passed": @(ok), @"phase": persisted ? @"restart" : @"transfer", @"detail": detail};
  [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]
      writeToFile:[root stringByAppendingPathComponent:persisted ? @"restart-result.json" : @"transfer-result.json"] atomically:YES];
  CefQuitMessageLoop();
}
void Inspect(const char* profile, int stage);
class Visitor final : public CefCookieVisitor {
 public:
  explicit Visitor(int stage) : stage_(stage) {}
  bool Visit(const CefCookie& cookie, int count, int total, bool&) override {
    ++count_;
    std::string name = CefString(&cookie.name), domain = CefString(&cookie.domain), value = CefString(&cookie.value);
    if (stage_ == 0 || stage_ == 3) {
      if (name == "session") valid_ &= domain == "example.test" && value == "synthetic-session" && cookie.secure && cookie.httponly && cookie.same_site == CEF_COOKIE_SAME_SITE_LAX_MODE && !cookie.has_expires;
      else if (name == "persistent") valid_ &= domain == ".example.test" && value == "synthetic-persistent" && cookie.has_expires && cookie.same_site == CEF_COOKIE_SAME_SITE_STRICT_MODE;
      else valid_ = false;
    } else if (stage_ == 1) valid_ &= name == "persistent";
    return true;
  }
  ~Visitor() override {
    int expected = stage_ == 2 ? 0 : stage_ == 1 ? 1 : 2;
    if (!valid_ || count_ != expected) { Finish(false, @"Cookie scope, flags, count or value mismatch."); return; }
    if (stage_ == 0 || stage_ == 3) Inspect(target, 1);
    else if (stage_ == 1) Inspect(other, 2);
    else Finish(true, @"Host-only and domain scope, HttpOnly, Secure, SameSite, persistence and second-profile isolation verified.");
  }
 private:
  int stage_, count_ = 0; bool valid_ = true;
  IMPLEMENT_REFCOUNTING(Visitor);
};
class Ready final : public CefCompletionCallback {
 public:
  Ready(CefRefPtr<CefRequestContext> context, int stage) : context_(context), stage_(stage) {}
  void OnComplete() override {
    std::string url = stage_ == 1 ? "https://sub.example.test/" : "https://example.test/";
    if (!context_->GetCookieManager(nullptr)->VisitUrlCookies(url, true, new Visitor(stage_))) Finish(false, @"Cookie visitor rejected.");
  }
 private:
  CefRefPtr<CefRequestContext> context_; int stage_;
  IMPLEMENT_REFCOUNTING(Ready);
};
class ContextReady final : public CefRequestContextHandler {
 public:
  explicit ContextReady(int stage) : stage_(stage) {}
  void OnRequestContextInitialized(CefRefPtr<CefRequestContext> context) override { context->GetCookieManager(new Ready(context, stage_)); }
 private:
  int stage_;
  IMPLEMENT_REFCOUNTING(ContextReady);
};
// Retain contexts until process shutdown so asynchronous initialization stays alive.
CefRefPtr<CefRequestContext> contexts[4];
void Inspect(const char* profile, int stage) {
  CefRequestContextSettings settings;
  CefString(&settings.cache_path) = [[root stringByAppendingPathComponent:@"Chromium"] stringByAppendingPathComponent:@(profile)].UTF8String;
  settings.persist_session_cookies = true;
  contexts[stage] = CefRequestContext::CreateContext(settings, new ContextReady(stage));
}
void Event(const char* token, const char* event, const char* json) {
  if (std::string(event) != "arc-cookies") return;
  NSDictionary* result = [NSJSONSerialization JSONObjectWithData:[@(json) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
  if (std::string(token) == "fresh") {
    if ([result[@"saved"] intValue] != 2 || [result[@"failed"] intValue] != 1 || result[@"error"]) { Finish(false, @"Unexpected SetCookie completion counts."); return; }
    AavaEngineImportArcCookies(target, "[]", "overwrite");
  } else if (std::string(token) == "overwrite") {
    if (!result[@"error"]) { Finish(false, @"Existing-profile overwrite was not rejected."); return; }
    Inspect(target, persisted ? 3 : 0);
  }
}
}
extern "C" bool AavaDismissSurface() { return false; }
extern "C" void AavaFocus() {}
extern "C" bool AavaCanOfferLinkChoice(const char*, const char*, const char*) { return false; }
extern "C" bool AavaOfferLinkChoice(const char*, const char*, const char*) { return false; }
extern "C" void AavaStart() {
  root = NSProcessInfo.processInfo.environment[@"AAVA_DATA_DIRECTORY"];
  if (![root hasPrefix:@"/private/tmp/aava-cookie-integration-"]) { CefQuitMessageLoop(); return; }
  persisted = [NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"transfer-result.json"]];
  AavaEngineSetCallback(Event);
  if (persisted) { AavaEngineImportArcCookies(target, "[]", "overwrite"); return; }
  AavaEngineImportArcCookies(target, R"json([
    {"host":"example.test","name":"session","value":"synthetic-session","path":"/","secure":true,"httpOnly":true,"persistent":false,"expires":"0","sameSite":1},
    {"host":".example.test","name":"persistent","value":"synthetic-persistent","path":"/","secure":true,"httpOnly":false,"persistent":true,"expires":"14712289200000000","sameSite":2},
    {"host":"example.test","name":"invalid;name","value":"rejected","path":"/","secure":true,"httpOnly":false,"persistent":false,"expires":"0","sameSite":1}
  ])json", "fresh");
}
