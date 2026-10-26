#pragma once
#include <stdbool.h>
#include "AavaGeometry.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*AavaEventCallback)(const char* tab, const char* event, const char* value);
void AavaEngineResolvePrompt(const char* token, bool allow, const char* value);
void AavaEngineImportArcCookies(const char* profile, const char* json, const char* token);
void AavaEngineSetCallback(AavaEventCallback callback);
void AavaEngineCreate(void* parent, const char* tab, const char* profile, const char* url);
void AavaEngineNavigate(const char* tab, const char* url);
void AavaEngineAction(const char* tab, const char* action);
void AavaEngineClose(const char* tab);
void AavaEngineArchive(const char* tab);
bool AavaEngineCloseFocused(void);
void AavaEngineExtensions(const char* profile);
void AavaEngineQuit(void);
void AavaEngineLockProfile(const char* profile, bool locked);
const char* AavaEngineFocusedProfile(void);
void AavaEngineNotifyCopied(const char* tab);
void AavaEngineRequestSearch(const char* tab);
void AavaEngineRequestSelect(const char* tab);
void AavaEngineDownloadAction(const char* token, const char* profile, const char* action);
void AavaEngineSync(const char* tab);
void AavaEngineOverlay(bool visible);
void AavaStart(void);
bool AavaDismissSurface(void);
void AavaFocus(void);
bool AavaOfferLinkChoice(const char* tab, const char* source, const char* target);
bool AavaCanOfferLinkChoice(const char* tab, const char* source, const char* target);
#ifdef __cplusplus
}
#endif

#include "MiniEngine.h"
