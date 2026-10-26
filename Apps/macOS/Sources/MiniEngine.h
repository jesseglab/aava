#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*AavaMiniCallback)(const char* request, const char* json);
void AavaMiniSetCallback(AavaMiniCallback callback);
void AavaMiniStart(void);
void AavaMiniStop(void);
void AavaMiniWatch(bool watch);
void AavaMiniCommand(const char* request, const char* json);
void AavaMiniPointer(int x, int y, int kind, int delta);
void AavaMiniKey(const char* text, int code, bool character);
void AavaMiniDialog(bool allow);
#ifdef __cplusplus
}
#endif
