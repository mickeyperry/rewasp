// Shared-memory protocol between the 64-bit native FL plugin (native64.cpp,
// installed as Wasp_x64.dll) and the 32-bit helper (helper32.cpp, WaspHost32.exe)
// that runs the original 32-bit Wasp.dll. Fixed-size types only, so the layout
// is identical in both builds.
#pragma once
#include <stdint.h>

#define WB_MAGIC      0x57425333   // 'WBS3'
#define WB_MAXV       128          // voice slots
#define WB_MAXFRAMES  8192         // max frames per render call
#define WB_DATA       (256 * 1024) // per-channel data area (state, names)
#define WB_MAXCB      128
#define WB_QUEUE      256
#define WB_GUIFRAMES  8            // GUI requests can nest (re-entrancy through SendMessage), one frame per level
#define WM_WB_CALL    (0x8000 + 0x57)  // WM_APP-range message carrying a GUI request: wParam = frame index
#define WM_WB_HOST    (0x8000 + 0x58)  // helper -> 64-bit side: synchronous host dispatcher call, wParam = frame index
#define WM_WB_PARAM   (0x8000 + 0x59)  // helper -> 64-bit side, posted: OnParamChanged(wParam=index, lParam=value)
#define WM_WB_CTRL    (0x8000 + 0x5A)  // helper -> 64-bit side, posted: OnControllerChanged(wParam=index, lParam=value)
#define WB_HOST_ONHINT  (-1)           // WBHostCall.id pseudo-ID: host->OnHint(text)
enum WBOp {
    OP_DISPATCHER = 1,  // a=ID b=Index c=Value -> result
    OP_IDLE,
    OP_SAVE,            // -> data
    OP_LOAD,            // data ->
    OP_GETNAME,         // a=Section b=Index c=Value -> data (string)
    OP_PROCESSEVENT,    // a=EventID b=EventValue c=Flags -> result
    OP_PROCESSPARAM,    // a=Index b=Value c=RECFlags -> result
    OP_RENDER,          // a=frames -> render[], result=frames rendered
    OP_TRIGGER,         // a=slot -> result 1 ok / 0 refused
    OP_VRELEASE,        // a=slot
    OP_VKILL,           // a=slot
    OP_VEVENT,          // a=slot b=EventID c=EventValue d=Flags -> result
    OP_NEWTICK,
    OP_MIDIIN,          // a=msg -> result=msg
    OP_MSGIN,           // a=msg
    OP_DESTROY,
};

enum WBCallbackType {
    CB_VOICEKILL = 1,   // a=slot b=KillHandle
    CB_VOICERELEASE,    // a=slot
    CB_PARAMCHANGED,    // a=Index b=Value
    CB_DISPATCH,        // a=ID b=Index c=Value (scalar host dispatcher messages)
    CB_CONTROLLER,      // a=Index b=Value (OnControllerChanged)
};

#pragma pack(push, 8)
struct WBCallback { int32_t type, pad; int64_t a, b, c; };

struct WBVoice {
    int32_t active;
    int32_t handle;           // plugin's voice handle (32-bit)
    uint8_t params[40];       // TVoiceParams or TVoiceParams_Old (both 40 bytes), mirrored from FL
};

struct WBChannel {
    volatile int32_t req;     // bumped by the 64-bit side for each request
    volatile int32_t resp;    // set to req by the helper when done
    int32_t op, dataLen;
    int64_t a, b, c, d;
    int64_t result;
    int32_t nCb, pad;
    WBCallback cb[WB_MAXCB];  // callbacks raised by the plugin while serving this request
    uint8_t data[WB_DATA];
};

// Host dispatcher calls that need FL's answer right away (e.g. the knob right-click
// menu: FHD_GetParamMenuEntry / FHD_ParamMenu). The helper fills a frame and
// SendMessage's WM_WB_HOST to hostHwnd; the 64-bit side calls FL and fills the reply.
struct WBHostCall {
    int64_t id, index, value, result;
    int32_t hasEntry, entryFlags;   // FHD_GetParamMenuEntry: FL returned an entry
    int32_t textIn, pad;            // text[] is an input string: passed to FL as Value (or as the OnHint text)
    char entryName[256];            // in: text (textIn) / out: menu entry name
};

struct WBShared {
    int32_t magic, ready, error, pad;
    // plugin info, filled by the helper at startup
    int32_t sdk, flags, numParams, defPoly, numOutCtrls, numOutVoices;
    char longName[128], shortName[128];
    int64_t editorHwnd;       // plugin EditorHandle, refreshed after every GUI-channel op
    int64_t helperHwnd;       // helper's message window; GUI requests are SendMessage'd to it
    int64_t hostHwnd;         // 64-bit side's message window (FL's GUI thread); WM_WB_HOST goes to it
    volatile int32_t hostBusy[WB_GUIFRAMES];
    WBHostCall host[WB_GUIFRAMES];
    WBVoice voices[WB_MAXV];
    // callbacks raised outside any request (e.g. user turning a knob), drained by the 64-bit side on Idle
    volatile int32_t qHead, qTail;
    WBCallback queue[WB_QUEUE];
    // GUI requests travel as SendMessage(helperHwnd, WM_WB_CALL, frame): Windows then handles nested
    // calls in both directions exactly like in-process plugins (e.g. Wasp forwarding a key to FL,
    // FL saving the project in response and asking Wasp for its state).
    volatile int32_t guiBusy[WB_GUIFRAMES];
    WBChannel gui[WB_GUIFRAMES];
    WBChannel audio;
    float render[WB_MAXFRAMES * 2];
};
#pragma pack(pop)

// object names: Local\WaspBridge.<id>.mem / .audioReq / .audioResp / .ready
