#pragma once
#include "include/cef_client.h"
bool AavaChromeCreate(void* parent, const std::string& id, CefRefPtr<CefClient> client,
                      CefRefPtr<CefRequestContext> context, const std::string& url);
void AavaChromeSync(const std::string& id);
void AavaChromeOverlay(bool visible);
void AavaChromeToolbar(const std::string& id);
void AavaChromePopout(const std::string& id, bool floating);

void AavaChromeURL(const std::string& id, const std::string& url);

void AavaChromeLock(const std::string& id, bool locked);
