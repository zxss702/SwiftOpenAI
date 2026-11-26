#pragma once
#include <windows.h>
#include <winhttp.h>

static inline BOOL SOAIWinHttpSetCallback(HINTERNET request, WINHTTP_STATUS_CALLBACK callback, DWORD flags)
{
    return WinHttpSetStatusCallback(request, callback, flags, 0) != WINHTTP_INVALID_STATUS_CALLBACK;
}
