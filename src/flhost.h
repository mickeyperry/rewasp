// Minimal FL Studio native-plugin host (32-bit), enough to run old Fruity
// generators such as Wasp outside FL. Implements TFruityPlugHost from the
// official FL SDK headers in sdk/.
#pragma once
#define NOMINMAX
#include <windows.h>
#include <objidl.h>
#include <stdint.h>
#include <stdio.h>
#include <math.h>
#include <string>
#include <vector>
#include <list>
#include <mutex>
#include "../sdk/fp_plugclass.h"

typedef TFruityPlug *(__stdcall *TCreatePlugInstance)(TFruityPlugHost *Host, TPluginTag Tag);

void HostLog(const char *fmt, ...);

class FLHost : public TFruityPlugHost {
public:
    FLHost();
    ~FLHost();

    // load the plugin DLL & create one instance; returns false on failure
    bool Load(const wchar_t *dllPath);
    void Unload();

    void SetSampleRate(double sr);
    void SetBlockSize(int n);
    void SetTempo(double bpm);
    void SetPlaying(bool playing);

    // notes (called from the audio thread, between renders)
    void NoteOn(int note, float velocity);   // velocity 0..1
    void NoteOff(int note);
    void AllNotesOff();
    void PitchBend(float cents);             // channel pitch, cents

    // renders `frames` stereo-interleaved float samples (replaces out)
    void Render(float *out, int frames);

    TFruityPlug *plug = nullptr;
    HMODULE dll = nullptr;
    double sampleRate = 44100;
    int blockSize = 1024;
    double tempo = 130;
    std::recursive_mutex mix;   // LockMix / UnlockMix
    std::wstring pluginDir;
    std::string pluginDirA;

    // -- TFruityPlugHost --
    intptr_t _stdcall Dispatcher(TPluginTag Sender, intptr_t ID, intptr_t Index, intptr_t Value) override;
    void _stdcall OnParamChanged(TPluginTag Sender, int Index, int Value) override;
    void _stdcall OnHint(TPluginTag Sender, char *Text) override;
    void _stdcall ComputeLRVol_Old(float &LVol, float &RVol, int Pan, float Volume) override;
    void _stdcall Voice_Release(intptr_t Sender) override;
    void _stdcall Voice_Kill(intptr_t Sender, BOOL KillHandle) override;
    int _stdcall Voice_ProcessEvent(intptr_t Sender, intptr_t EventID, intptr_t EventValue, intptr_t Flags) override;
    void _stdcall LockMix() override;
    void _stdcall UnlockMix() override;
    void _stdcall MIDIOut_Delayed(TPluginTag Sender, intptr_t Msg) override;
    void _stdcall MIDIOut(TPluginTag Sender, intptr_t Msg) override;
    void _stdcall AddWave_32FM_32FS_Ramp(void *SourceBuffer, void *DestBuffer, int Length, float LVol, float RVol, float &LastLVol, float &LastRVol) override;
    void _stdcall AddWave_32FS_32FS_Ramp(void *SourceBuffer, void *DestBuffer, int Length, float LVol, float RVol, float &LastLVol, float &LastRVol) override;
    bool _stdcall LoadSample(TSampleHandle &Handle, char *FileName, PWaveFormatExtensible NeededFormat, int Flags) override;
    void *_stdcall GetSampleData(TSampleHandle Handle, int &Length) override;
    void _stdcall CloseSample(TSampleHandle Handle) override;
    int _stdcall GetSongMixingTime() override;
    double _stdcall GetSongMixingTime_A() override;
    double _stdcall GetSongPlayingTime() override;
    void _stdcall OnControllerChanged(TPluginTag Sender, intptr_t Index, intptr_t Value) override;
    void *_stdcall GetSendBuffer(intptr_t Num) override;
    void _stdcall PlugMsg_Delayed(TPluginTag Sender, intptr_t Msg) override;
    void _stdcall PlugMsg_Kill(TPluginTag Sender, intptr_t MSg) override;
    void _stdcall GetSampleInfo(TSampleHandle Handle, PSampleInfo Info) override;
    void _stdcall DistWave_32FM(int DistType, int DistThres, void *SourceBuffer, int Length, float DryVol, float WetVol, float Mul) override;
    void *_stdcall GetMixBuffer(int Num) override;
    void *_stdcall GetInsBuffer(TPluginTag Sender, int Ofs) override;
    bool _stdcall PromptEdit(int x, int y, char *SetCaption, char *s, int &c) override;
    void _stdcall SuspendOutput() override;
    void _stdcall ResumeOutput() override;
    void _stdcall GetSampleRegion(TSampleHandle Handle, int RegionNum, PSampleRegion Region) override;
    void _stdcall ComputeLRVol(float &LVol, float &RVol, float Pan, float Volume) override;
    void _stdcall LockPlugin(TPluginTag Sender) override;
    void _stdcall UnlockPlugin(TPluginTag Sender) override;
    void _stdcall LockMix_Shared_Old() override;
    void _stdcall UnlockMix_Shared_Old() override;
    void _stdcall GetInBuffer(TPluginTag Sender, intptr_t Index, PIOBuffer IBuffer) override;
    void _stdcall GetOutBuffer(TPluginTag Sender, intptr_t Index, PIOBuffer OBuffer) override;
    TOutVoiceHandle _stdcall TriggerOutputVoice(TVoiceParams *VoiceParams, intptr_t SetIndex, intptr_t SetTag) override;
    void _stdcall OutputVoice_Release(TOutVoiceHandle Handle) override;
    void _stdcall OutputVoice_Kill(TOutVoiceHandle Handle) override;
    int _stdcall OutputVoice_ProcessEvent(TOutVoiceHandle Handle, intptr_t EventID, intptr_t EventValue, intptr_t Flags) override;

private:
    struct Voice {
        intptr_t tag;            // our id, passed to TriggerVoice as SetTag
        TVoiceHandle handle;     // plugin's handle
        int note;
        float velocity;
        bool released;
        TVoiceParams params;
        TVoiceParams_Old oldParams;   // for plugins without FPF_NewVoiceParams (Wasp)
        float lastL, lastR;      // ramp state for hybrid rendering
    };
    std::list<Voice> voices;   // list: the plugin keeps pointers to each voice's params
    intptr_t nextTag = 1;
    float pitchBend = 0;
    double mixTicks = 0;         // song position, ticks
    std::vector<float> waveTables[6];
    std::vector<float> tempBuf;  // 4 contiguous stereo buffers
    std::vector<float> voiceBuf;
    bool inRender = false;
    std::vector<TVoiceHandle> pendingKill;
    Voice *FindVoice(intptr_t tag);
    void SyncOldParams(Voice &v);
    bool OldParams() const { return plug && !(plug->Info->Flags & FPF_NewVoiceParams); }
    void RemoveVoice(intptr_t tag, bool killInPlugin);
    void BuildWaveTables();
    void AllocBuffers();
};
