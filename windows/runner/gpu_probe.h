// REDLINE FX - GPU diagnostics (copied into windows\runner by setup.ps1).
// Writes gpu-log.txt next to the exe:
//  - remote desktop session or not
//  - every DXGI adapter (a "SOFTWARE" flag / "Microsoft Basic Render Driver" = no real GPU driver)
//  - 6 s after start: which graphics driver DLLs the process actually loaded.
//    d3d10warp.dll = Direct3D software rasterizer (WARP) -> Flutter draws on the CPU.
//    igd*.dll = Intel GPU driver, nvwgf2umx.dll = NVIDIA, amdxx64/aticfx64 = AMD.
// Also asks hybrid laptops to run this exe on the discrete GPU.
#pragma once

#include <windows.h>
#include <dxgi.h>
#include <psapi.h>

#include <cstdio>
#include <cwctype>
#include <string>

#pragma comment(lib, "dxgi.lib")

extern "C" {
__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}

namespace gpu_probe {

inline std::wstring ExeDir() {
  wchar_t exe[MAX_PATH] = {0};
  ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
  std::wstring p(exe);
  const size_t cut = p.find_last_of(L"\\/");
  return cut == std::wstring::npos ? std::wstring() : p.substr(0, cut + 1);
}

// Flutter 3.47 turned Impeller on for Windows. On this app it rasterises several times slower
// than Skia (no raster cache for the static textures), so Skia is used unless a file named
// "impeller-on.txt" sits next to the exe.
inline bool ImpellerWanted() {
  const DWORD a = ::GetFileAttributesW((ExeDir() + L"impeller-on.txt").c_str());
  return a != INVALID_FILE_ATTRIBUTES;
}

inline std::wstring LogPath() {
  wchar_t exe[MAX_PATH] = {0};
  ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
  std::wstring p(exe);
  const size_t cut = p.find_last_of(L"\\/");
  return (cut == std::wstring::npos ? std::wstring() : p.substr(0, cut + 1)) + L"gpu-log.txt";
}

inline void Write(const std::wstring& line, bool truncate) {
  FILE* f = nullptr;
  if (_wfopen_s(&f, LogPath().c_str(), truncate ? L"w" : L"a") != 0 || f == nullptr) return;
  // plain ASCII-ish output: non-ASCII chars become '?'
  std::string s;
  for (wchar_t ch : line) s.push_back(ch < 128 ? static_cast<char>(ch) : '?');
  std::fputs(s.c_str(), f);
  std::fputs("\n", f);
  std::fclose(f);
}

inline void Adapters() {
  wchar_t buf[512];
  swprintf_s(buf, L"remote_desktop=%d", ::GetSystemMetrics(SM_REMOTESESSION));
  Write(buf, false);
  IDXGIFactory1* factory = nullptr;
  if (FAILED(::CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory))) || factory == nullptr) {
    Write(L"DXGI factory: failed", false);
    return;
  }
  IDXGIAdapter1* a = nullptr;
  for (UINT i = 0; factory->EnumAdapters1(i, &a) != DXGI_ERROR_NOT_FOUND; ++i) {
    DXGI_ADAPTER_DESC1 d = {};
    a->GetDesc1(&d);
    swprintf_s(buf, L"adapter %u: %s | vendor %04X device %04X | vram %llu MB | shared %llu MB%s", i, d.Description,
               d.VendorId, d.DeviceId, static_cast<unsigned long long>(d.DedicatedVideoMemory >> 20),
               static_cast<unsigned long long>(d.SharedSystemMemory >> 20),
               (d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) ? L" | SOFTWARE" : L"");
    Write(buf, false);
    a->Release();
  }
  factory->Release();
}

inline DWORD WINAPI Modules(LPVOID) {
  ::Sleep(6000);
  Write(L"module scan...", false);
  HMODULE mods[1024];
  DWORD needed = 0;
  if (!::K32EnumProcessModules(::GetCurrentProcess(), mods, static_cast<DWORD>(sizeof(mods)), &needed)) return 0;
  const DWORD n = static_cast<DWORD>(needed / sizeof(HMODULE));
  std::wstring all = L"modules:";
  bool warp = false, hw = false;
  for (DWORD i = 0; i < n && i < 1024; ++i) {
    wchar_t name[MAX_PATH] = {0};
    if (!::K32GetModuleBaseNameW(::GetCurrentProcess(), mods[i], name, MAX_PATH)) continue;
    std::wstring s(name);
    for (auto& ch : s) ch = static_cast<wchar_t>(std::towlower(static_cast<wint_t>(ch)));
    if (s.find(L"d3d10warp") != std::wstring::npos) warp = true;
    if (s.rfind(L"igd", 0) == 0 || s.find(L"nvwgf2") != std::wstring::npos || s.find(L"nvoglv") != std::wstring::npos ||
        s.find(L"amdxx") != std::wstring::npos || s.find(L"aticfx") != std::wstring::npos ||
        s.find(L"atio6") != std::wstring::npos || s.find(L"ig9icd") != std::wstring::npos ||
        s.find(L"ig12icd") != std::wstring::npos || s.find(L"ig7icd") != std::wstring::npos)
      hw = true;
    all += L" " + s;
  }
  Write(std::wstring(L"RESULT: ") +
            (warp ? L"SOFTWARE (WARP) rendering - GPU is NOT used"
                  : hw ? L"hardware GPU driver loaded" : L"no GPU driver DLL found (software rendering likely)"),
        false);
  Write(all, false);
  return 0;
}

inline void Start() {
  Write(L"=== REDLINE FX gpu probe ===", true);
  Write(ImpellerWanted() ? L"renderer requested: impeller (impeller-on.txt found)" : L"renderer requested: skia", false);
  Adapters();
  HANDLE t = ::CreateThread(nullptr, 0, Modules, nullptr, 0, nullptr);
  if (t != nullptr) ::CloseHandle(t);
}

}  // namespace gpu_probe
