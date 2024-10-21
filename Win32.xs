#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0500
#include <wchar.h>
#include <wctype.h>
#include <windows.h>
#include <shlobj.h>
#include <wchar.h>

#if !defined(_MSC_VER) || (defined(_MSC_VER) && _MSC_VER >= 1300)
#  include <userenv.h>
#else
#  define USERENV_API_DLL 1
#endif

#include <lm.h>

#if (defined(_MSC_VER) && _MSC_VER >= 1400) || (((100000 * __GNUC__) + (1000 * __GNUC_MINOR__)) >= 408000)
#  include <winhttp.h>
#else
#  define WINHTTP_API_DLL 1
#endif

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "w32ppport.h"

#ifndef countof
#  define countof(array) (sizeof (array) / sizeof (*(array)))
#endif

/* 128KB minus some breathing room to actually touch/alloc/vivify 128KB, only
   right under that amount. We don't want byte 0x20000 to be alloced or
   writeable since 4096-1 will be wasted.

   "alloca((_l)+PTRSIZE)" guards against off-by-one, and
   writing a ASCII or WIDE NULL into theoretical unalloced mem.
   If the croak executes, something is really wrong, since the entire Win32
   revolves around struct UNICODE_STRING and its USHORT Length field.
   Depending on WinOS version, MS API bugs, legacy behaviour, and specific
   API func name, 0x7FFF or 0xFFFF is max legal input.

   Lets just cap this API at 0xFFFF-PTRSIZE, unless a good reason is found
   to delivery a 0xFFFF long string to the Win API.

   128KB limit allows about 2 ASCII strings, or 1 WIDE string at almost
   MAX LEN. And you can combine 2 buffers into 1 chkstk()/alloca() func call.

   128KB limit is also to prevent too much C stack expansion/vivify
   and anti-abuse, since the C stack wont shrink after expansion, and Win32
   default limit is 1 MB.

   If production code hits the croak, it needs to be refactored with a
   C stack buf initial buf len MAX_PATH+1, or 4096 initial length.
   If API retval failure/buf overflow error, then
   do a "FetchLength(NULL, &my_strlen)", and "malloc()" something and retry,
   or if string length in context is unreasonable, do a "croak()".
*/
#define SAFE_ALLOCA(_l,_t) ((_l)*sizeof(_t) > (((0xFFFF-PTRSIZE)*2)-PTRSIZE) ? \
    (croak_sub_glr(cv, "alloca", ERROR_BUFFER_OVERFLOW),NULL) \
    : alloca(((_l)*sizeof(_t))+PTRSIZE))

#define SE_SHUTDOWN_NAMEA   "SeShutdownPrivilege"

#ifndef WC_NO_BEST_FIT_CHARS
#  define WC_NO_BEST_FIT_CHARS 0x00000400
#endif


#define croak_sub(_cv, _pv) S_croak_sub((_cv), (_pv))
STATIC void S_croak_sub(const CV *const cv, const char *const params);

#define dll_ref_inc(_cv, _hm) S_dll_ref_inc((_cv),(_hm))
static void S_dll_ref_inc(CV * cv, HMODULE hmod) {
    HANDLE h;
    WCHAR buf [MAX_PATH*2]; /* times 2 why not? 32KB paths one day lol*/
    DWORD r = GetModuleFileNameW(hmod, (WCHAR *)buf, (sizeof(buf)/sizeof(WCHAR))-1);
    if(!r)
      croak_sub(cv, "dll_ref_inc");
    h = LoadLibraryW((WCHAR *)buf);
    if(!h)
      croak_sub(cv, "dll_ref_inc");
}

#define dll_ref_dec(_cv, _hm) S_dll_ref_dec((_cv),(_hm))
static void S_dll_ref_dec(CV * cv, HMODULE * hmod) {
    HMODULE h = *hmod;
    if(h) {
        *hmod = NULL;
        if(!FreeLibrary(h))
            croak_sub(cv, "dll_ref_dec");
    }
}

#define MY_CXT_KEY "Win32::Win32pm_guts"

typedef struct {
    WCHAR * s32dir;
#ifdef WINHTTPAPI
    HMODULE winhttp;
#endif
#ifdef USERENV_API_DLL
    HMODULE userenv;
    PFNDestroyEnvironmentBlock pfnDestroyEnvironmentBlock;
    PFNCreateEnvironmentBlock pfnCreateEnvironmentBlock;
#endif
#ifdef SHFOLDER_API_DLL
    HMODULE shfolder; /* Win2k probably and up, shell32.dll will be here */
    PFNSHGetFolderPathW pfnSHGetFolderPathW;
#endif
#ifdef SHELL32_API_DLL
    HMODULE shell32;
    PFNSHGetSpecialFolderPathW pfnSHGetSpecialFolderPathW;
#endif
#ifdef USER32_API_DLL
    HMODULE user32;
    PFNMessageBoxW pfnMessageBoxW;
    PFNGetSystemMetrics pfnGetSystemMetrics;
    PFNGetActiveWindow pfnGetActiveWindow;
#endif
#ifdef NETAPI32_API_DLL
    HMODULE netapi32;
    PFNNetWkstaGetInfo pfnNetWkstaGetInfo;
    PFNNetApiBufferFree pfnNetApiBufferFree;
#endif
#ifdef VERSION_API_DLL
    HMODULE version;
    PFNGetFileVersionInfoA pfnGetFileVersionInfoA;
    PFNGetFileVersionInfoSizeA pfnGetFileVersionInfoSizeA;
    PFNVerQueryValueA pfnVerQueryValueA;
#endif
#ifdef OLE32_API_DLL
    HMODULE ole32;
    PFNCoCreateGuid pfnCoCreateGuid;
    PFNCoTaskMemFree pfnCoTaskMemFree;
    PFNStringFromCLSID pfnStringFromCLSID;
#endif
    USHORT s32dirlen;
} my_cxt_t;

START_MY_CXT;

typedef struct {
    WCHAR * s32dir;
#ifdef WINHTTPAPI
    WCHAR *winhttp;
#endif
#ifdef USERENV_API_DLL
    WCHAR *userenv;
    char * pfnDestroyEnvironmentBlock;
    char * pfnCreateEnvironmentBlock;
#endif
#ifdef SHFOLDER_API_DLL
    WCHAR *shfolder; /* Win2k probably and up, shell32.dll will be here */
    char * pfnSHGetFolderPathW;
#endif
#ifdef SHELL32_API_DLL
    WCHAR *shell32;
    char * pfnSHGetSpecialFolderPathW;
#endif
#ifdef USER32_API_DLL
    WCHAR *user32;
    char * pfnMessageBoxW;
    char * pfnGetSystemMetrics;
    char * pfnGetActiveWindow;
#endif
#ifdef NETAPI32_API_DLL
    WCHAR *netapi32;
    char * pfnNetWkstaGetInfo;
    char * pfnNetApiBufferFree;
#endif
#ifdef VERSION_API_DLL
    WCHAR *version;
    char * pfnGetFileVersionInfoA;
    char * pfnGetFileVersionInfoSizeA;
    char * pfnVerQueryValueA;
#endif
#ifdef OLE32_API_DLL
    WCHAR *ole32;
    char * pfnCoCreateGuid;
    char * pfnCoTaskMemFree;
    char * pfnStringFromCLSID;
#endif
    USHORT s32dirlen;
} fntable_t;

static const fntable_t fntable = {
    L"",
#ifdef WINHTTPAPI
    L"winhttp",
#endif
#ifdef USERENV_API_DLL
    L"userenv",
    "DestroyEnvironmentBlock",
    "CreateEnvironmentBlock",
#endif
#ifdef SHFOLDER_API_DLL
    L"shfolder", /* Win2k probably and up, shell32.dll will be here */
    "SHGetFolderPathW",
#endif
#ifdef SHELL32_API_DLL
    L"shell32",
    "SHGetSpecialFolderPathW",
#endif
#ifdef USER32_API_DLL
    L"user32",
    "MessageBoxW",
    "GetSystemMetrics",
    "GetActiveWindow",
#endif
#ifdef NETAPI32_API_DLL
    L"netapi32",
    "NetWkstaGetInfo",
    "NetApiBufferFree",
#endif
#ifdef VERSION_API_DLL
    L"version",
    "GetFileVersionInfoA",
    "GetFileVersionInfoSizeA",
    "VerQueryValueA",
#endif
#ifdef OLE32_API_DLL
    L"ole32",
    "CoCreateGuid",
    "CoTaskMemFree",
    "StringFromCLSID",
#endif
    0
};

#define CALLFN(_fn) (MY_CXT.pfn##_fn \
                    ? MY_CXT.pfn##_fn \
                    : (PFN##_fn)(get_fn(aTHX_ cv, ((void **)(&MY_CXT.pfn##_fn)))))

static void * get_fn(pTHX_ CV * cv, void ** p_to_pfn) {
  dMY_CXT;
  void * fn;
  DWORD idxfn = ((char**)p_to_pfn)-((char**)&MY_CXT);
  char ** fnname = ((char **)&fntable)+idxfn;
  char ** widedll = ((char **)&fntable)+idxfn;
  while(widedll != (char **)&fntable) {
      if(!(*widedll)[1]) {/* if 2nd byte this is a wide DLL name */
          DWORD idxhmod = ((char**)widedll)-((char **)&fntable);
          HMODULE h = ((HMODULE *)&MY_CXT)[idxhmod];
          if(!h) {
              WCHAR * trydll = (WCHAR *)*widedll;
              /* Ancient redundant stub >= 2K, search the probably
                 already in address space shell32 first. */
              if(trydll == L"shfolder") {
                  trydll = L"shell32";
                  h = LoadLibraryW((WCHAR *)*widedll);
                  if(!h)
                      croak_sub(cv, "LoadLibraryW");
                  fn = (void *)GetProcAddress(h,*fnname);
                  if(!fn) {
                      FreeLibrary(h);
                      h = LoadLibraryW(L"shfolder");
                      if(!h)
                          croak_sub(cv, "LoadLibraryW");
                      else
                          ((HMODULE *)&MY_CXT)[idxhmod] = h;
                      fn = (void *)GetProcAddress(h,*fnname);
                      if(!fn)
                          croak_sub(cv, "GetProcAddress");
                      else {
                          *p_to_pfn = fn;
                          return fn;
                      }
                  }
                  else {
                      ((HMODULE *)&MY_CXT)[idxhmod] = h;
                      *p_to_pfn = fn;
                      return fn;
                  }
              }
              else {
                  h = LoadLibraryW((WCHAR *)*widedll);
                  if(!h)
                      croak_sub(cv, "LoadLibraryW");
                  else
                      ((HMODULE *)&MY_CXT)[idxhmod] = h;
              }
          }
          fn = (void *)GetProcAddress(h,*fnname);
          if(!fn)
              croak_sub(cv, "GetProcAddress");
          else {
              *p_to_pfn = fn;
              return fn;
          }
      }
      else
        widedll--;
  }
  croak_sub(cv, "fntable");
  return NULL;
}

#ifdef WINHTTPAPI
XS(w32_HttpGetFile);
#endif

#define GETPROC(fn) pfn##fn = (PFN##fn)GetProcAddress(module, #fn)

typedef int (__stdcall *PFNDllRegisterServer)(void);
typedef int (__stdcall *PFNDllUnregisterServer)(void);
typedef BOOL (__stdcall *PFNIsUserAnAdmin)(void);
typedef BOOL (WINAPI *PFNGetProductInfo)(DWORD, DWORD, DWORD, DWORD, DWORD*);
typedef void (WINAPI *PFNGetNativeSystemInfo)(LPSYSTEM_INFO lpSystemInfo);
typedef LONG (WINAPI *PFNRegGetValueA)(HKEY, LPCSTR, LPCSTR, DWORD, LPDWORD, PVOID, LPDWORD);

#ifdef WINHTTPAPI

/* Pump perl's event loop as a good citizen, Win32 GUIs or SIG ALRM
   GetTickCount() is extremely fast but slow updates (15 ms or worse) since it
   fetchs a value from shared RO global kernel memory, but 30 ms or 60 ms
   resolution is much more than we need.  If GetTickCount() overflows after
   45 days (don't ask how that happened), because unsigned comparison,
   conditional still triggers, new time stored, and hgf_async_check() runs
   1x only, needlessly, at less than every 333 ms. */
#define HGF_ASYNC_CHECK if( (cur = GetTickCount())-last > 333 \
                            || PL_sig_pending) {\
    last = cur; \
    hgf_async_check(aTHX); \
}


volatile LONG WinHttpRefCnt = 0;
volatile LONG WinHttpLoaded = 0;
PFNWinHttpCrackUrl pfnWinHttpCrackUrl = NULL;
PFNWinHttpOpen pfnWinHttpOpen = NULL;
PFNWinHttpCloseHandle pfnWinHttpCloseHandle = NULL;
PFNWinHttpConnect pfnWinHttpConnect = NULL;
PFNWinHttpReadData pfnWinHttpReadData = NULL;
PFNWinHttpSetOption pfnWinHttpSetOption = NULL;
PFNWinHttpOpenRequest pfnWinHttpOpenRequest = NULL;
PFNWinHttpAddRequestHeaders pfnWinHttpAddRequestHeaders = NULL;
PFNWinHttpSendRequest pfnWinHttpSendRequest = NULL;
PFNWinHttpReceiveResponse pfnWinHttpReceiveResponse = NULL;
PFNWinHttpQueryHeaders pfnWinHttpQueryHeaders = NULL;
PFNWinHttpGetProxyForUrl pfnWinHttpGetProxyForUrl = NULL;

typedef struct {
    /* first 4 fields are NULL inited, so they are in a row for
       SSE/AVX memset() instrinsic friendly */
    HINTERNET hSession;
    HINTERNET hConnect;
    HINTERNET hRequest;
    WCHAR *file;
    HANDLE hOut;
} HGF_DTOR_T;

typedef struct {
    WINHTTP_AUTOPROXY_OPTIONS  AutoProxyOptions;
    WINHTTP_PROXY_INFO         ProxyInfo;
} HGF_PXYINFO_T;

static int hgf_free(pTHX_ SV* sv, MAGIC* mg) {
    HANDLE h;
    WCHAR *file;
    DWORD e = GetLastError();
    HGF_DTOR_T * dtor = (HGF_DTOR_T *)mg->mg_ptr;
    HINTERNET hi = dtor->hRequest;
    if(hi) {
      dtor->hRequest = NULL;
      pfnWinHttpCloseHandle(hi);
    }
    hi = dtor->hConnect;
    if(hi) {
      dtor->hConnect = NULL;
      pfnWinHttpCloseHandle(hi);
    }
    hi = dtor->hSession;
    if(hi) {
      dtor->hSession = NULL;
      pfnWinHttpCloseHandle(hi);
    }
    h = dtor->hOut;
    if(h != INVALID_HANDLE_VALUE) {
      dtor->hOut = INVALID_HANDLE_VALUE;
      CloseHandle(h);
      if(dtor->file) {
          DeleteFileW(dtor->file);
      }
    }
    file = dtor->file;
    if(file) {
      dtor->file = NULL;
      Safefree(file);
    }
    SetLastError(e);
    return 0;
}

static int hgf_dup(pTHX_ MAGIC *mg, CLONE_PARAMS *param) {
    /* nothing can survive a ithread/psuedofork, no WinHttpDuplicateHandle() */
    HGF_DTOR_T * dtor = (HGF_DTOR_T *)mg->mg_ptr;
    /*4 NULLs in a row, SSE/AVX memset() instrinsic friendly */
    dtor->hRequest = NULL;
    dtor->hConnect = NULL;
    dtor->hSession = NULL;
    dtor->file = NULL;
    dtor->hOut = INVALID_HANDLE_VALUE;
    return 0;
}

const MGVTBL hgf_mg_vtbl = { 0, 0, 0, 0, hgf_free, 0, hgf_dup, 0 };

static void hgf_async_check(pTHX) {
    DWORD e = GetLastError();
    win32_async_check(aTHX);
    SetLastError(e);
}

static void DecRefWinHttp() {
    LONG old = InterlockedDecrement(&WinHttpRefCnt);
    if(old == 0) {
        old = InterlockedExchange(&WinHttpLoaded,1);
        if(old != 1) {
          pfnWinHttpCrackUrl = NULL;
          pfnWinHttpOpen = NULL;
          pfnWinHttpCloseHandle = NULL;
          pfnWinHttpConnect = NULL;
          pfnWinHttpReadData = NULL;
          pfnWinHttpSetOption = NULL;
          pfnWinHttpOpenRequest = NULL;
          pfnWinHttpAddRequestHeaders = NULL;
          pfnWinHttpSendRequest = NULL;
          pfnWinHttpReceiveResponse = NULL;
          pfnWinHttpQueryHeaders = NULL;
          pfnWinHttpGetProxyForUrl = NULL;
          InterlockedExchange(&WinHttpLoaded,0);
        }
    }
}

#endif


#ifndef CSIDL_MYMUSIC
#   define CSIDL_MYMUSIC              0x000D
#endif
#ifndef CSIDL_MYVIDEO
#   define CSIDL_MYVIDEO              0x000E
#endif
#ifndef CSIDL_LOCAL_APPDATA
#   define CSIDL_LOCAL_APPDATA        0x001C
#endif
#ifndef CSIDL_COMMON_FAVORITES
#   define CSIDL_COMMON_FAVORITES     0x001F
#endif
#ifndef CSIDL_INTERNET_CACHE
#   define CSIDL_INTERNET_CACHE       0x0020
#endif
#ifndef CSIDL_COOKIES
#   define CSIDL_COOKIES              0x0021
#endif
#ifndef CSIDL_HISTORY
#   define CSIDL_HISTORY              0x0022
#endif
#ifndef CSIDL_COMMON_APPDATA
#   define CSIDL_COMMON_APPDATA       0x0023
#endif
#ifndef CSIDL_WINDOWS
#   define CSIDL_WINDOWS              0x0024
#endif
#ifndef CSIDL_PROGRAM_FILES
#   define CSIDL_PROGRAM_FILES        0x0026
#endif
#ifndef CSIDL_MYPICTURES
#   define CSIDL_MYPICTURES           0x0027
#endif
#ifndef CSIDL_PROFILE
#   define CSIDL_PROFILE              0x0028
#endif
#ifndef CSIDL_PROGRAM_FILES_COMMON
#   define CSIDL_PROGRAM_FILES_COMMON 0x002B
#endif
#ifndef CSIDL_COMMON_TEMPLATES
#   define CSIDL_COMMON_TEMPLATES     0x002D
#endif
#ifndef CSIDL_COMMON_DOCUMENTS
#   define CSIDL_COMMON_DOCUMENTS     0x002E
#endif
#ifndef CSIDL_COMMON_ADMINTOOLS
#   define CSIDL_COMMON_ADMINTOOLS    0x002F
#endif
#ifndef CSIDL_ADMINTOOLS
#   define CSIDL_ADMINTOOLS           0x0030
#endif
#ifndef CSIDL_COMMON_MUSIC
#   define CSIDL_COMMON_MUSIC         0x0035
#endif
#ifndef CSIDL_COMMON_PICTURES
#   define CSIDL_COMMON_PICTURES      0x0036
#endif
#ifndef CSIDL_COMMON_VIDEO
#   define CSIDL_COMMON_VIDEO         0x0037
#endif
#ifndef CSIDL_CDBURN_AREA
#   define CSIDL_CDBURN_AREA          0x003B
#endif
#ifndef CSIDL_FLAG_CREATE
#   define CSIDL_FLAG_CREATE          0x8000
#endif

/* Use explicit struct definition because wSuiteMask and
 * wProductType are not defined in the VC++ 6.0 headers.
 * WORD type has been replaced by unsigned short because
 * WORD is already used by Perl itself.
 */
struct g_osver_t {
    DWORD dwOSVersionInfoSize;
    DWORD dwMajorVersion;
    DWORD dwMinorVersion;
    DWORD dwBuildNumber;
    DWORD dwPlatformId;
    CHAR  szCSDVersion[128];
    unsigned short wServicePackMajor;
    unsigned short wServicePackMinor;
    unsigned short wSuiteMask;
    BYTE  wProductType;
    BYTE  wReserved;
} g_osver = {0, 0, 0, 0, 0, "", 0, 0, 0, 0, 0};
BOOL g_osver_ex = TRUE;

/* Croak with XSUB's name prefixed, and any suffix string, taken from
   croak_xs_usage */
STATIC void
S_croak_sub(const CV *const cv, const char *const params)
{
/* This executes so rarely, avoid overhead of passing my_perl in callers. */
    dTHX;
    const GV *const gv = CvGV(cv);

    if (gv) {
        const char *const gvname = GvNAME(gv);
        const HV *const stash = GvSTASH(gv);
        const char *const hvname = stash ? HvNAME(stash) : NULL;

        if (hvname)
          Perl_croak_nocontext("%s::%s: %s", hvname, gvname, params);
        else
          Perl_croak_nocontext("%s: %s", gvname, params);
    } else {
        /* Pants. I don't think that it should be possible to get here. */
        Perl_croak_nocontext("CODE(0x%" UVxf "): %s", PTR2UV(cv), params);
    }
}

/* Croak with XSUB's name prefixed, taken from croak_xs_usage */
#define croak_sub_glr(_cv, _syscallpv, _e) S_croak_sub_glr((_cv), (_syscallpv), (_e))
STATIC void
S_croak_sub_glr(const CV *const cv, const char *const syscallpv, DWORD err)
{
    char buf [128+sizeof("%s GetLastError=%u %x ")+12+9];
    my_snprintf((char *)buf, sizeof(buf)-1, "%s GetLastError=%u %x ",
                syscallpv, err, err);
    croak_sub(cv, (const char *)buf);
}

#define ONE_K_BUFSIZE	1024

/* Convert SV to wide character string.  The return value must be
 * freed using Safefree().
 */
static WCHAR*
sv_to_wstr_len(pTHX_ const CV *const cv, SV *sv, STRLEN *plen)
{
    DWORD wlen;
    WCHAR *wstr;
    STRLEN len;
    DWORD e;
    char *str = SvPV(sv, len);
    UINT cp = SvUTF8(sv) ? CP_UTF8 : CP_ACP;
    DWORD wlen_guess = len + 1;

    New(0, wstr, wlen_guess, WCHAR);
    if (len == 0) { /* output WIDE string is obvious */
        *plen = 0;
        wstr[0] = 0;
        return wstr;
    }

    wlen = MultiByteToWideChar(cp, 0, str, (int)(len+1), wstr, wlen_guess);
    if(wlen == 0) {
        e = GetLastError();
        if(e == ERROR_INSUFFICIENT_BUFFER) { /* not BMP ??? */
            wlen = MultiByteToWideChar(cp, 0, str, (int)(len+1), NULL, 0);
            if(wlen == 0) /* probably illegal code point in some code page */
                goto croak;
            /* null or paranoia, are inputs from supposed to have a
               narrow nul byte that comes out as output*/
            wlen++;
            Renew(wstr, wlen, WCHAR);
            wlen = MultiByteToWideChar(cp, 0, str, (int)(len+1), wstr, wlen);
            if (wlen == 0) { /* unknown err, but we have no output */
                goto croak;
            }
            *plen = wlen-1;
            return wstr;
        }
        else /* probably illegal code point in some code page */
            goto croak_err;
    }
    *plen = wlen-1;
    return wstr;

    croak:
    e = GetLastError();

    croak_err:
    Safefree(wstr);
    croak_sub_glr(cv, "MultiByteToWideChar", e);
    return NULL;
}

static WCHAR*
sv_to_wstr(pTHX_ const CV *const cv, SV *sv) {
    STRLEN len;
    return sv_to_wstr_len(aTHX_ cv, sv, &len);
}

/* Convert wide character string to mortal SV.  Use UTF8 encoding
 * if the string cannot be represented in the system codepage.
 * Arg len is in units of WCHAR not including WIDE null, just like MS APIs.
 * Arg len IS NOT in units of bytes. If len is 0, wcslen() is called instead.
 */
static SV *
wstr_to_sv(pTHX_ WCHAR *wstr, STRLEN len)
{
    /* 2 GB-1 max, do len = 0 on overflow instead of croak for now, too rare */
    int wlen =  len ?
        ((((int)len) < 0 || len > (0x7FFFFFFF-1)) ? 1 : ((int)len)+1)
        : ((int)wcslen(wstr)+1);
    BOOL use_default = FALSE;
    SV *sv;
    if(wlen == 1) { /* empty string */
      return sv_2mortal(newSVpvs(""));
    }
    len = WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, wstr, wlen, NULL, 0, NULL, NULL);
    sv = sv_2mortal(newSV(len));

    len = WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, wstr, wlen, SvPVX(sv), len, NULL, &use_default);
    if (use_default) {
        len = WideCharToMultiByte(CP_UTF8, 0, wstr, wlen, NULL, 0, NULL, NULL);
        sv_grow(sv, len);
        len = WideCharToMultiByte(CP_UTF8, 0, wstr, wlen, SvPVX(sv), len, NULL, NULL);
        SvUTF8_on(sv);
    }
    /* Shouldn't really ever fail since we ask for the required length first, but who knows... */
    if (len) {
        SvPOK_on(sv);
        SvCUR_set(sv, len-1);
    }
    return sv;
}

/* Retrieve a variable from the Unicode environment in a mortal SV.
 *
 * Recreates the Unicode environment because a bug in earlier Perl versions
 * overwrites it with the ANSI version, which contains replacement
 * characters for the characters not in the ANSI codepage.
 */
static SV*
get_unicode_env(pTHX_ CV* cv, const WCHAR *name)
{
#ifdef USERENV_API_DLL
    dMY_CXT;
#endif
    SV *sv = NULL;
    void *env;
    HANDLE token;

    /* Get security token for the current process owner */
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_DUPLICATE, &token))
    {
        return NULL;
    }

    /* Create a Unicode environment block for this process */

#ifdef USERENV_API_DLL
    if (CALLFN(CreateEnvironmentBlock)(&env, token, FALSE))
#else
    if (CreateEnvironmentBlock(&env, token, FALSE))
#endif
    {
        size_t name_len = wcslen(name);
        WCHAR *entry = (WCHAR *)env;
        while (*entry) {
            size_t i;
            size_t entry_len = wcslen(entry);
            BOOL equal = (entry_len > name_len) && (entry[name_len] == '=');

            for (i=0; equal && i < name_len; ++i)
                equal = (towupper(entry[i]) == towupper(name[i]));

            if (equal) {
                sv = wstr_to_sv(aTHX_ entry+name_len+1, 0);
                break;
            }
            entry += entry_len+1;
        }
#ifdef USERENV_API_DLL
        CALLFN(DestroyEnvironmentBlock)(env);
#else
        DestroyEnvironmentBlock(env);
#endif
    }
    CloseHandle(token);
    return sv;
}

#define CHAR_T            WCHAR
#define WIN32_FIND_DATA_T WIN32_FIND_DATAW
#define FN_FINDFIRSTFILE  FindFirstFileW
#define FN_STRLEN         wcslen
#define FN_STRCPY         wcscpy
#define LONGPATH          my_longpathW
#include "longpath.inc"

/* The my_ansipath() function takes a Unicode filename and converts it
 * into the current Windows codepage. If some characters cannot be mapped,
 * then it will convert the short name instead.
 *
 * The buffer to the ansi pathname must be freed with Safefree() when it
 * it no longer needed.
 *
 * The argument to my_ansipath() must exist before this function is
 * called; otherwise there is no way to determine the short path name.
 *
 * Ideas for future refinement:
 * - Only convert those segments of the path that are not in the current
 *   codepage, but leave the other segments in their long form.
 * - If the resulting name is longer than MAX_PATH, start converting
 *   additional path segments into short names until the full name
 *   is shorter than MAX_PATH.  Shorten the filename part last!
 */

/* This is a modified version of core Perl win32/win32.c(win32_ansipath).
 * It uses New() etc. instead of win32_malloc().
 */

char *
my_ansipath(const WCHAR *widename)
{
    char *name;
    BOOL use_default = FALSE;
    int widelen = (int)wcslen(widename)+1;
    int len = WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, widename, widelen,
                                  NULL, 0, NULL, NULL);
    New(0, name, len, char);
    WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, widename, widelen,
                        name, len, NULL, &use_default);
    if (use_default) {
        DWORD shortlen = GetShortPathNameW(widename, NULL, 0);
        if (shortlen) {
            WCHAR *shortname;
            New(0, shortname, shortlen, WCHAR);
            shortlen = GetShortPathNameW(widename, shortname, shortlen)+1;

            len = WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, shortname, shortlen,
                                      NULL, 0, NULL, NULL);
            Renew(name, len, char);
            WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, shortname, shortlen,
                                name, len, NULL, NULL);
            Safefree(shortname);
        }
    }
    return name;
}

/* Convert wide character path to ANSI path and return as mortal SV. */
SV*
wstr_to_ansipath(pTHX_ WCHAR *wstr)
{
    char *ansi = my_ansipath(wstr);
    SV *sv = sv_2mortal(newSVpvn(ansi, strlen(ansi)));
    Safefree(ansi);
    return sv;
}

#if defined(__CYGWIN__) || !(PERL_VERSION >= 8 || (PERL_VERSION == 7 && PERL_SUBVERSION >= 3))

char*
get_childdir(void)
{
    dTHX;
    WCHAR filename[MAX_PATH+1];

    GetCurrentDirectoryW(MAX_PATH+1, filename);
    return my_ansipath(filename);
}

void
free_childdir(char *d)
{
    dTHX;
    Safefree(d);
}

void*
get_childenv(void)
{
    return NULL;
}

void
free_childenv(void *d)
{
  PERL_UNUSED_ARG(d);
}

#ifdef __CYGWIN__
#  define PerlDir_mapA(dir) (dir)
#endif

#endif

XS(w32_ExpandEnvironmentStrings)
{
    dXSARGS;
    WCHAR value[31*1024];
    WCHAR *source;

    if (items != 1)
	croak("usage: Win32::ExpandEnvironmentStrings($String)");

    source = sv_to_wstr(aTHX_ cv, ST(0));
    ExpandEnvironmentStringsW(source, value, countof(value)-1);
    ST(0) = wstr_to_sv(aTHX_ value, 0);
    Safefree(source);
    XSRETURN(1);
}

XS(w32_IsAdminUser)
{
    dXSARGS;
    HMODULE                     module;
    PFNIsUserAnAdmin            pfnIsUserAnAdmin;
    HANDLE                      hTok;
    DWORD                       dwTokInfoLen;
    TOKEN_GROUPS                *lpTokInfo;
    SID_IDENTIFIER_AUTHORITY    NtAuth = SECURITY_NT_AUTHORITY;
    PSID                        pAdminSid;
    int                         iRetVal;
    unsigned int                i;

    if (items)
        croak("usage: Win32::IsAdminUser()");

    /* Use IsUserAnAdmin() when available.  On Vista this will only return TRUE
     * if the process is running with elevated privileges and not just when the
     * process owner is a member of the "Administrators" group.
     */
    module = GetModuleHandleA("shell32.dll");
    GETPROC(IsUserAnAdmin);
    if (pfnIsUserAnAdmin) {
        EXTEND(SP, 1);
        ST(0) = sv_2mortal(newSViv(pfnIsUserAnAdmin() ? 1 : 0));
        XSRETURN(1);
    }

    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, FALSE, &hTok)) {
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hTok)) {
            warn("Cannot open thread token or process token");
            XSRETURN_UNDEF;
        }
    }

    GetTokenInformation(hTok, TokenGroups, NULL, 0, &dwTokInfoLen);
    if (!New(1, lpTokInfo, dwTokInfoLen, TOKEN_GROUPS)) {
        warn("Cannot allocate token information structure");
        CloseHandle(hTok);
        XSRETURN_UNDEF;
    }

    if (!GetTokenInformation(hTok, TokenGroups, lpTokInfo, dwTokInfoLen,
            &dwTokInfoLen))
    {
        warn("Cannot get token information");
        Safefree(lpTokInfo);
        CloseHandle(hTok);
        XSRETURN_UNDEF;
    }

    if (!AllocateAndInitializeSid(&NtAuth, 2, SECURITY_BUILTIN_DOMAIN_RID,
            DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &pAdminSid))
    {
        warn("Cannot allocate administrators' SID");
        Safefree(lpTokInfo);
        CloseHandle(hTok);
        XSRETURN_UNDEF;
    }

    iRetVal = 0;
    for (i = 0; i < lpTokInfo->GroupCount; ++i) {
        if (EqualSid(lpTokInfo->Groups[i].Sid, pAdminSid)) {
            iRetVal = 1;
            break;
        }
    }

    FreeSid(pAdminSid);
    Safefree(lpTokInfo);
    CloseHandle(hTok);

    EXTEND(SP, 1);
    ST(0) = sv_2mortal(newSViv(iRetVal));
    XSRETURN(1);
}

XS(w32_LookupAccountName)
{
    dXSARGS;
    char SID[400];
    DWORD SIDLen;
    SID_NAME_USE snu;
    char Domain[256];
    DWORD DomLen;
    BOOL bResult;

    if (items != 5)
	croak("usage: Win32::LookupAccountName($system, $account, $domain, "
	      "$sid, $sidtype)");

    SIDLen = sizeof(SID);
    DomLen = sizeof(Domain);

    bResult = LookupAccountNameA(SvPV_nolen(ST(0)),	/* System */
                                 SvPV_nolen(ST(1)),	/* Account name */
                                 &SID,			/* SID structure */
                                 &SIDLen,		/* Size of SID buffer */
                                 Domain,		/* Domain buffer */
                                 &DomLen,		/* Domain buffer size */
                                 &snu);			/* SID name type */
    if (bResult) {
	sv_setpv(ST(2), Domain);
	sv_setpvn(ST(3), SID, SIDLen);
	sv_setiv(ST(4), snu);
	XSRETURN_YES;
    }
    XSRETURN_NO;
}


XS(w32_LookupAccountSID)
{
    dXSARGS;
    PSID sid;
    char Account[256];
    DWORD AcctLen = sizeof(Account);
    char Domain[256];
    DWORD DomLen = sizeof(Domain);
    SID_NAME_USE snu;
    BOOL bResult;

    if (items != 5)
	croak("usage: Win32::LookupAccountSID($system, $sid, $account, $domain, $sidtype)");

    sid = SvPV_nolen(ST(1));
    if (IsValidSid(sid)) {
        bResult = LookupAccountSidA(SvPV_nolen(ST(0)),	/* System */
                                    sid,		/* SID structure */
                                    Account,		/* Account name buffer */
                                    &AcctLen,		/* name buffer length */
                                    Domain,		/* Domain buffer */
                                    &DomLen,		/* Domain buffer length */
                                    &snu);		/* SID name type */
	if (bResult) {
	    sv_setpv(ST(2), Account);
	    sv_setpv(ST(3), Domain);
	    sv_setiv(ST(4), (IV)snu);
	    XSRETURN_YES;
	}
    }
    XSRETURN_NO;
}

XS(w32_InitiateSystemShutdown)
{
    dXSARGS;
    HANDLE hToken;              /* handle to process token   */
    TOKEN_PRIVILEGES tkp;       /* pointer to token structure  */
    BOOL bRet;
    char *machineName, *message;

    if (items != 5)
	croak("usage: Win32::InitiateSystemShutdown($machineName, $message, "
	      "$timeOut, $forceClose, $reboot)");

    machineName = SvPV_nolen(ST(0));

    if (OpenProcessToken(GetCurrentProcess(),
			 TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
			 &hToken))
    {
        LookupPrivilegeValueA(machineName,
                              SE_SHUTDOWN_NAMEA,
                              &tkp.Privileges[0].Luid);

	tkp.PrivilegeCount = 1; /* only setting one */
	tkp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

	/* Get shutdown privilege for this process. */
	AdjustTokenPrivileges(hToken, FALSE, &tkp, 0,
			      (PTOKEN_PRIVILEGES)NULL, 0);
    }

    message = SvPV_nolen(ST(1));
    bRet = InitiateSystemShutdownA(machineName, message, (DWORD)SvIV(ST(2)),
                                   (BOOL)SvIV(ST(3)), (BOOL)SvIV(ST(4)));

    /* Disable shutdown privilege. */
    tkp.Privileges[0].Attributes = 0;
    AdjustTokenPrivileges(hToken, FALSE, &tkp, 0,
			  (PTOKEN_PRIVILEGES)NULL, 0);
    CloseHandle(hToken);
    XSRETURN_IV(bRet);
}

XS(w32_AbortSystemShutdown)
{
    dXSARGS;
    HANDLE hToken;              /* handle to process token   */
    TOKEN_PRIVILEGES tkp;       /* pointer to token structure  */
    BOOL bRet;
    char *machineName;

    if (items != 1)
	croak("usage: Win32::AbortSystemShutdown($machineName)");

    machineName = SvPV_nolen(ST(0));

    if (OpenProcessToken(GetCurrentProcess(),
			 TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
			 &hToken))
    {
        LookupPrivilegeValueA(machineName,
                              SE_SHUTDOWN_NAMEA,
                              &tkp.Privileges[0].Luid);

	tkp.PrivilegeCount = 1; /* only setting one */
	tkp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

	/* Get shutdown privilege for this process. */
	AdjustTokenPrivileges(hToken, FALSE, &tkp, 0,
			      (PTOKEN_PRIVILEGES)NULL, 0);
    }

    bRet = AbortSystemShutdownA(machineName);

    /* Disable shutdown privilege. */
    tkp.Privileges[0].Attributes = 0;
    AdjustTokenPrivileges(hToken, FALSE, &tkp, 0,
			  (PTOKEN_PRIVILEGES)NULL, 0);
    CloseHandle(hToken);
    XSRETURN_IV(bRet);
}


XS(w32_MsgBox)
{
    dXSARGS;
    DWORD flags = MB_ICONEXCLAMATION;
    I32 result;
    WCHAR *title = NULL, *msg;

    if (items < 1 || items > 3)
	croak("usage: Win32::MsgBox($message [, $flags [, $title]])");

    msg = sv_to_wstr(aTHX_ cv, ST(0));
    if (items > 1)
        flags = (DWORD)SvIV(ST(1));
    if (items > 2)
        title = sv_to_wstr(aTHX_ cv, ST(2));

    result = MessageBoxW(GetActiveWindow(), msg, title ? title : L"Perl", flags);

    Safefree(msg);
    if (title)
        Safefree(title);

    XSRETURN_IV(result);
}

XS(w32_LoadLibrary)
{
    dXSARGS;
    HANDLE hHandle;

    if (items != 1)
	croak("usage: Win32::LoadLibrary($libname)\n");
    hHandle = LoadLibraryA(SvPV_nolen(ST(0)));
#ifdef _WIN64
    XSRETURN_IV((DWORD_PTR)hHandle);
#else
    XSRETURN_IV((DWORD)hHandle);
#endif
}

XS(w32_FreeLibrary)
{
    dXSARGS;

    if (items != 1)
	croak("usage: Win32::FreeLibrary($handle)\n");
    if (FreeLibrary(INT2PTR(HINSTANCE, SvIV(ST(0))))) {
	XSRETURN_YES;
    }
    XSRETURN_NO;
}

XS(w32_GetProcAddress)
{
    dXSARGS;

    if (items != 2)
	croak("usage: Win32::GetProcAddress($hinstance, $procname)\n");
    XSRETURN_IV(PTR2IV(GetProcAddress(INT2PTR(HINSTANCE, SvIV(ST(0))), SvPV_nolen(ST(1)))));
}

XS(w32_RegisterServer)
{
    dXSARGS;
    BOOL result = FALSE;
    HMODULE module;

    if (items != 1)
	croak("usage: Win32::RegisterServer($libname)\n");

    module = LoadLibraryA(SvPV_nolen(ST(0)));
    if (module) {
	PFNDllRegisterServer pfnDllRegisterServer;
        GETPROC(DllRegisterServer);
	if (pfnDllRegisterServer && pfnDllRegisterServer() == 0)
	    result = TRUE;
	FreeLibrary(module);
    }
    ST(0) = boolSV(result);
    XSRETURN(1);
}

XS(w32_UnregisterServer)
{
    dXSARGS;
    BOOL result = FALSE;
    HINSTANCE module;

    if (items != 1)
	croak("usage: Win32::UnregisterServer($libname)\n");

    module = LoadLibraryA(SvPV_nolen(ST(0)));
    if (module) {
	PFNDllUnregisterServer pfnDllUnregisterServer;
        GETPROC(DllUnregisterServer);
	if (pfnDllUnregisterServer && pfnDllUnregisterServer() == 0)
	    result = TRUE;
	FreeLibrary(module);
    }
    ST(0) = boolSV(result);
    XSRETURN(1);
}

/* XXX rather bogus */
XS(w32_GetArchName)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetArchName()");
    XSRETURN_PV(getenv("PROCESSOR_ARCHITECTURE"));
}

XS(w32_GetChipArch)
{
    dXSARGS;
    SYSTEM_INFO sysinfo;
    HMODULE module;
    PFNGetNativeSystemInfo pfnGetNativeSystemInfo;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetChipArch()");

    Zero(&sysinfo,1,SYSTEM_INFO);
    module = GetModuleHandle("kernel32.dll");
    GETPROC(GetNativeSystemInfo);
    if (pfnGetNativeSystemInfo)
        pfnGetNativeSystemInfo(&sysinfo);
    else
        GetSystemInfo(&sysinfo);

    XSRETURN_IV(sysinfo.wProcessorArchitecture);
}

XS(w32_GetChipName)
{
    dXSARGS;
    SYSTEM_INFO sysinfo;
    HMODULE module;
    PFNGetNativeSystemInfo pfnGetNativeSystemInfo;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetChipName()");

    Zero(&sysinfo,1,SYSTEM_INFO);
    module = GetModuleHandle("kernel32.dll");
    GETPROC(GetNativeSystemInfo);
    if (pfnGetNativeSystemInfo)
        pfnGetNativeSystemInfo(&sysinfo);
    else
        GetSystemInfo(&sysinfo);

    /* XXX docs say dwProcessorType is deprecated on NT */
    XSRETURN_IV(sysinfo.dwProcessorType);
}

XS(w32_GuidGen)
{
    dXSARGS;
    GUID guid;
    char szGUID[50] = {'\0'};
    HRESULT  hr;
#ifdef OLE32_API_DLL
    dMY_CXT;
#endif
    if (items)
       Perl_croak(aTHX_ "usage: Win32::GuidGen()");
#ifdef OLE32_API_DLL
    hr     = CALLFN(CoCreateGuid)(&guid);
#else
    hr     = CoCreateGuid(&guid);
#endif
    if (SUCCEEDED(hr)) {
	LPOLESTR pStr = NULL;
#ifdef OLE32_API_DLL
	if (SUCCEEDED(CALLFN(StringFromCLSID)(&guid, &pStr))) {
#else
#ifdef __cplusplus
	if (SUCCEEDED(StringFromCLSID(guid, &pStr))) {
#else
	if (SUCCEEDED(StringFromCLSID(&guid, &pStr))) {
#endif
#endif
            WideCharToMultiByte(CP_ACP, 0, pStr, (int)wcslen(pStr), szGUID,
                                sizeof(szGUID), NULL, NULL);
#ifdef OLE32_API_DLL
            CALLFN(CoTaskMemFree)(pStr);
#else
            CoTaskMemFree(pStr);
#endif
            XSRETURN_PV(szGUID);
        }
    }
    XSRETURN_UNDEF;
}

XS(w32_GetFolderPath)
{
#if defined(SHFOLDER_API_DLL) || defined (SHELL32_API_DLL)
    dMY_CXT;
#endif
    dXSARGS;
    WCHAR wpath[MAX_PATH+1];
    int folder;
    int create = 0;

    if (items != 1 && items != 2)
	croak("usage: Win32::GetFolderPath($csidl [, $create])\n");

    folder = (int)SvIV(ST(0));
    if (items == 2)
        create = SvTRUE(ST(1)) ? CSIDL_FLAG_CREATE : 0;
#ifdef SHFOLDER_API_DLL
    if (SUCCEEDED(CALLFN(SHGetFolderPathW)(NULL, folder|create, NULL, 0, wpath))) {
#else
    if (SUCCEEDED(SHGetFolderPathW(NULL, folder|create, NULL, 0, wpath))) {
#endif
        ST(0) = wstr_to_ansipath(aTHX_ wpath);
        XSRETURN(1);
    }

#ifdef SHELL32_API_DLL
    if (CALLFN(SHGetSpecialFolderPathW)(NULL, wpath, folder, !!create)) {
#else
    if (SHGetSpecialFolderPathW(NULL, wpath, folder, !!create)) {
#endif
        ST(0) = wstr_to_ansipath(aTHX_ wpath);
        XSRETURN(1);
    }

    /* SHGetFolderPathW() and SHGetSpecialFolderPathW() may fail on older
     * Perl versions that have replaced the Unicode environment with an
     * ANSI version.  Let's go spelunking in the registry now...
     */
    {
        SV *sv;
        HKEY hkey;
        HKEY root = HKEY_CURRENT_USER;
        const WCHAR *name = NULL;

        switch (folder) {
        case CSIDL_ADMINTOOLS:                  name = L"Administrative Tools";        break;
        case CSIDL_APPDATA:                     name = L"AppData";                     break;
        case CSIDL_CDBURN_AREA:                 name = L"CD Burning";                  break;
        case CSIDL_COOKIES:                     name = L"Cookies";                     break;
        case CSIDL_DESKTOP:
        case CSIDL_DESKTOPDIRECTORY:            name = L"Desktop";                     break;
        case CSIDL_FAVORITES:                   name = L"Favorites";                   break;
        case CSIDL_FONTS:                       name = L"Fonts";                       break;
        case CSIDL_HISTORY:                     name = L"History";                     break;
        case CSIDL_INTERNET_CACHE:              name = L"Cache";                       break;
        case CSIDL_LOCAL_APPDATA:               name = L"Local AppData";               break;
        case CSIDL_MYMUSIC:                     name = L"My Music";                    break;
        case CSIDL_MYPICTURES:                  name = L"My Pictures";                 break;
        case CSIDL_MYVIDEO:                     name = L"My Video";                    break;
        case CSIDL_NETHOOD:                     name = L"NetHood";                     break;
        case CSIDL_PERSONAL:                    name = L"Personal";                    break;
        case CSIDL_PRINTHOOD:                   name = L"PrintHood";                   break;
        case CSIDL_PROGRAMS:                    name = L"Programs";                    break;
        case CSIDL_RECENT:                      name = L"Recent";                      break;
        case CSIDL_SENDTO:                      name = L"SendTo";                      break;
        case CSIDL_STARTMENU:                   name = L"Start Menu";                  break;
        case CSIDL_STARTUP:                     name = L"Startup";                     break;
        case CSIDL_TEMPLATES:                   name = L"Templates";                   break;
            /* XXX L"Local Settings" */
        }

        if (!name) {
            root = HKEY_LOCAL_MACHINE;
            switch (folder) {
            case CSIDL_COMMON_ADMINTOOLS:       name = L"Common Administrative Tools"; break;
            case CSIDL_COMMON_APPDATA:          name = L"Common AppData";              break;
            case CSIDL_COMMON_DESKTOPDIRECTORY: name = L"Common Desktop";              break;
            case CSIDL_COMMON_DOCUMENTS:        name = L"Common Documents";            break;
            case CSIDL_COMMON_FAVORITES:        name = L"Common Favorites";            break;
            case CSIDL_COMMON_PROGRAMS:         name = L"Common Programs";             break;
            case CSIDL_COMMON_STARTMENU:        name = L"Common Start Menu";           break;
            case CSIDL_COMMON_STARTUP:          name = L"Common Startup";              break;
            case CSIDL_COMMON_TEMPLATES:        name = L"Common Templates";            break;
            case CSIDL_COMMON_MUSIC:            name = L"CommonMusic";                 break;
            case CSIDL_COMMON_PICTURES:         name = L"CommonPictures";              break;
            case CSIDL_COMMON_VIDEO:            name = L"CommonVideo";                 break;
            }
        }
        /* XXX todo
         * case CSIDL_SYSTEM               # GetSystemDirectory()
         * case CSIDL_RESOURCES            # %windir%\Resources\, For theme and other windows resources.
         * case CSIDL_RESOURCES_LOCALIZED  # %windir%\Resources\<LangID>, for theme and other windows specific resources.
         */

#define SHELL_FOLDERS "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders"

        if (name && RegOpenKeyEx(root, SHELL_FOLDERS, 0, KEY_QUERY_VALUE, &hkey) == ERROR_SUCCESS) {
            WCHAR data[MAX_PATH+1];
            DWORD cb = sizeof(data)-sizeof(WCHAR);
            DWORD type = REG_NONE;
            long rc = RegQueryValueExW(hkey, name, NULL, &type, (BYTE*)&data, &cb);
            RegCloseKey(hkey);
            if (rc == ERROR_SUCCESS && type == REG_SZ && cb > sizeof(WCHAR) && data[0]) {
                /* Make sure the string is properly terminated */
                data[cb/sizeof(WCHAR)] = '\0';
                ST(0) = wstr_to_ansipath(aTHX_ data);
                XSRETURN(1);
            }
        }

#undef SHELL_FOLDERS

        /* Unders some circumstances the registry entries seem to have a null string
         * as their value even when the directory already exists.  The environment
         * variables do get set though, so try re-create a Unicode environment and
         * check if they are there.
         */
        sv = NULL;
        switch (folder) {
        case CSIDL_APPDATA:              sv = get_unicode_env(aTHX_ cv, L"APPDATA");            break;
        case CSIDL_PROFILE:              sv = get_unicode_env(aTHX_ cv, L"USERPROFILE");        break;
        case CSIDL_PROGRAM_FILES:        sv = get_unicode_env(aTHX_ cv, L"ProgramFiles");       break;
        case CSIDL_PROGRAM_FILES_COMMON: sv = get_unicode_env(aTHX_ cv, L"CommonProgramFiles"); break;
        case CSIDL_WINDOWS:              sv = get_unicode_env(aTHX_ cv, L"SystemRoot");         break;
        }
        if (sv) {
            ST(0) = sv;
            XSRETURN(1);
        }
    }

    XSRETURN_UNDEF;
}

XS(w32_GetFileVersion)
{
    dXSARGS;
    DWORD size;
    DWORD handle;
    char *filename;
    char *data;
#ifdef VERSION_API_DLL
    dMY_CXT;
#endif

    if (items != 1)
	croak("usage: Win32::GetFileVersion($filename)");

    filename = SvPV_nolen(ST(0));
#ifdef VERSION_API_DLL
    size = CALLFN(GetFileVersionInfoSizeA)(filename, &handle);
#else
    size = GetFileVersionInfoSize(filename, &handle);
#endif
    if (!size)
        XSRETURN_UNDEF;

    New(0, data, size, char);
    if (!data)
        XSRETURN_UNDEF;
#ifdef VERSION_API_DLL
    if (CALLFN(GetFileVersionInfoA)(filename, handle, size, data)) {
#else
    if (GetFileVersionInfo(filename, handle, size, data)) {
#endif
        VS_FIXEDFILEINFO *info;
        UINT len;
#ifdef VERSION_API_DLL
        if (CALLFN(VerQueryValueA)(data, "\\", (void**)&info, &len)) {
#else
        if (VerQueryValue(data, "\\", (void**)&info, &len)) {
#endif
            int dwValueMS1 = (info->dwFileVersionMS>>16);
            int dwValueMS2 = (info->dwFileVersionMS&0xffff);
            int dwValueLS1 = (info->dwFileVersionLS>>16);
            int dwValueLS2 = (info->dwFileVersionLS&0xffff);

            if (GIMME_V == G_ARRAY) {
                EXTEND(SP, 4);
                XST_mIV(0, dwValueMS1);
                XST_mIV(1, dwValueMS2);
                XST_mIV(2, dwValueLS1);
                XST_mIV(3, dwValueLS2);
                items = 4;
            }
            else {
                char version[50];
                sprintf(version, "%d.%d.%d.%d", dwValueMS1, dwValueMS2, dwValueLS1, dwValueLS2);
                XST_mPV(0, version);
            }
        }
    }
    else
        items = 0;

    Safefree(data);
    XSRETURN(items);
}

#ifdef __CYGWIN__
XS(w32_SetChildShowWindow)
{
    /* This function doesn't do anything useful for cygwin.  In the
     * MSWin32 case it modifies w32_showwindow, which is used by
     * win32_spawnvp().  Since w32_showwindow is an internal variable
     * inside the thread_intern structure, the MSWin32 implementation
     * lives in win32/win32.c in the core Perl distribution.
     */
    dSP;
    I32 ax = POPMARK;
    EXTEND(SP,1);
    XSRETURN_UNDEF;
}
#endif

XS(w32_GetCwd)
{
    dXSARGS;
    char* ptr;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetCwd()");

    /* Make the host for current directory */
    ptr = PerlEnv_get_childdir();
    /*
     * If ptr != Nullch
     *   then it worked, set PV valid,
     *   else return 'undef'
     */
    if (ptr) {
	SV *sv = sv_newmortal();
	sv_setpv(sv, ptr);
	PerlEnv_free_childdir(ptr);

#ifndef INCOMPLETE_TAINTS
	SvTAINTED_on(sv);
#endif

	EXTEND(SP,1);
	ST(0) = sv;
	XSRETURN(1);
    }
    XSRETURN_UNDEF;
}

XS(w32_SetCwd)
{
    dXSARGS;
    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::SetCwd($cwd)");

    if (SvUTF8(ST(0))) {
        WCHAR *wide = sv_to_wstr(aTHX_ cv, ST(0));
        char *ansi = my_ansipath(wide);
        int rc = PerlDir_chdir(ansi);
        Safefree(wide);
        Safefree(ansi);
        if (!rc)
            XSRETURN_YES;
    }
    else {
        if (!PerlDir_chdir(SvPV_nolen(ST(0))))
            XSRETURN_YES;
    }

    XSRETURN_NO;
}

XS(w32_GetNextAvailDrive)
{
    dXSARGS;
    char ix = 'C';
    char root[] = "_:\\";

    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetNextAvailDrive()");
    EXTEND(SP,1);
    while (ix <= 'Z') {
	root[0] = ix++;
	if (GetDriveType(root) == 1) {
	    root[2] = '\0';
	    XSRETURN_PV(root);
	}
    }
    XSRETURN_UNDEF;
}

XS(w32_GetLastError)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetLastError()");
    EXTEND(SP,1);
    XSRETURN_IV(GetLastError());
}

XS(w32_SetLastError)
{
    dXSARGS;
    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::SetLastError($error)");
    SetLastError((DWORD)SvIV(ST(0)));
    XSRETURN_EMPTY;
}

XS(w32_LoginName)
{
    dXSARGS;
    WCHAR name[128];
    DWORD size = countof(name);

    if (items)
	Perl_croak(aTHX_ "usage: Win32::LoginName()");

    EXTEND(SP,1);

    if (GetUserNameW(name, &size)) {
        ST(0) = wstr_to_sv(aTHX_ name, 0);
        XSRETURN(1);
    }

    XSRETURN_UNDEF;
}

XS(w32_NodeName)
{
    dXSARGS;
    char name[MAX_COMPUTERNAME_LENGTH+1];
    DWORD size = sizeof(name);
    if (items)
	Perl_croak(aTHX_ "usage: Win32::NodeName()");
    EXTEND(SP,1);
    if (GetComputerName(name,&size)) {
	/* size does NOT include NULL :-( */
	ST(0) = sv_2mortal(newSVpvn(name,size));
	XSRETURN(1);
    }
    XSRETURN_UNDEF;
}


XS(w32_DomainName)
{
    dXSARGS;
    char dname[256];
    DWORD dnamelen = sizeof(dname);
    WKSTA_INFO_100 *pwi;
    DWORD retval;

    if (items)
	Perl_croak(aTHX_ "usage: Win32::DomainName()");

    EXTEND(SP,1);

    retval = NetWkstaGetInfo(NULL, 100, (LPBYTE*)&pwi);
    /* NERR_Success *is* 0*/
    if (retval == 0) {
        if (pwi->wki100_langroup && *(pwi->wki100_langroup)) {
            WideCharToMultiByte(CP_ACP, 0, pwi->wki100_langroup,
                                -1, (LPSTR)dname, dnamelen, NULL, NULL);
        }
        else {
            WideCharToMultiByte(CP_ACP, 0, pwi->wki100_computername,
                                -1, (LPSTR)dname, dnamelen, NULL, NULL);
        }
        NetApiBufferFree(pwi);
        XSRETURN_PV(dname);
    }
    SetLastError(retval);
    XSRETURN_UNDEF;
}

XS(w32_FsType)
{
    dXSARGS;
    char fsname[256];
    DWORD flags, filecomplen;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::FsType()");
    if (GetVolumeInformation(NULL, NULL, 0, NULL, &filecomplen,
                             &flags, fsname, sizeof(fsname))) {
	if (GIMME_V == G_ARRAY) {
	    XPUSHs(sv_2mortal(newSVpvn(fsname,strlen(fsname))));
	    XPUSHs(sv_2mortal(newSViv(flags)));
	    XPUSHs(sv_2mortal(newSViv(filecomplen)));
	    PUTBACK;
	    return;
	}
	EXTEND(SP,1);
	XSRETURN_PV(fsname);
    }
    XSRETURN_EMPTY;
}

XS(w32_GetOSVersion)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetOSVersion()");

    if (GIMME_V == G_SCALAR) {
        XSRETURN_IV(g_osver.dwPlatformId);
    }
    XPUSHs(sv_2mortal(newSVpvn(g_osver.szCSDVersion, strlen(g_osver.szCSDVersion))));

    XPUSHs(sv_2mortal(newSViv(g_osver.dwMajorVersion)));
    XPUSHs(sv_2mortal(newSViv(g_osver.dwMinorVersion)));
    XPUSHs(sv_2mortal(newSViv(g_osver.dwBuildNumber)));
    XPUSHs(sv_2mortal(newSViv(g_osver.dwPlatformId)));
    if (g_osver_ex) {
        XPUSHs(sv_2mortal(newSViv(g_osver.wServicePackMajor)));
        XPUSHs(sv_2mortal(newSViv(g_osver.wServicePackMinor)));
        XPUSHs(sv_2mortal(newSViv(g_osver.wSuiteMask)));
        XPUSHs(sv_2mortal(newSViv(g_osver.wProductType)));
    }
    PUTBACK;
}

XS(w32_IsWinNT)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::IsWinNT()");
    EXTEND(SP,1);
    XSRETURN_IV(g_osver.dwPlatformId == VER_PLATFORM_WIN32_NT);
}

XS(w32_IsWin95)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::IsWin95()");
    EXTEND(SP,1);
    XSRETURN_IV(g_osver.dwPlatformId == VER_PLATFORM_WIN32_WINDOWS);
}

XS(w32_FormatMessage)
{
    dXSARGS;
    DWORD source = 0;
    char msgbuf[ONE_K_BUFSIZE];

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::FormatMessage($errno)");

    if (FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM,
                       &source, (DWORD)SvIV(ST(0)), 0,
                       msgbuf, sizeof(msgbuf)-1, NULL))
    {
        XSRETURN_PV(msgbuf);
    }

    XSRETURN_UNDEF;
}

XS(w32_Spawn)
{
    dXSARGS;
    char *cmd, *args;
    void *env;
    char *dir;
    PROCESS_INFORMATION stProcInfo;
    STARTUPINFO stStartInfo;
    BOOL bSuccess = FALSE;

    if (items != 3)
	Perl_croak(aTHX_ "usage: Win32::Spawn($cmdName, $args, $PID)");

    cmd = SvPV_nolen(ST(0));
    args = SvPV_nolen(ST(1));

    env = PerlEnv_get_childenv();
    dir = PerlEnv_get_childdir();

    memset(&stStartInfo, 0, sizeof(stStartInfo));   /* Clear the block */
    stStartInfo.cb = sizeof(stStartInfo);	    /* Set the structure size */
    stStartInfo.dwFlags = STARTF_USESHOWWINDOW;	    /* Enable wShowWindow control */
    stStartInfo.wShowWindow = SW_SHOWMINNOACTIVE;   /* Start min (normal) */

    if (CreateProcess(
		cmd,			/* Image path */
		args,	 		/* Arguments for command line */
		NULL,			/* Default process security */
		NULL,			/* Default thread security */
		FALSE,			/* Must be TRUE to use std handles */
		NORMAL_PRIORITY_CLASS,	/* No special scheduling */
		env,			/* Inherit our environment block */
		dir,			/* Inherit our currrent directory */
		&stStartInfo,		/* -> Startup info */
		&stProcInfo))		/* <- Process info (if OK) */
    {
	int pid = (int)stProcInfo.dwProcessId;
	sv_setiv(ST(2), pid);
	CloseHandle(stProcInfo.hThread);/* library source code does this. */
	bSuccess = TRUE;
    }
    PerlEnv_free_childenv(env);
    PerlEnv_free_childdir(dir);
    XSRETURN_IV(bSuccess);
}

XS(w32_GetTickCount)
{
    dXSARGS;
    DWORD msec = GetTickCount();
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetTickCount()");
    EXTEND(SP,1);
    if ((IV)msec > 0)
	XSRETURN_IV(msec);
    XSRETURN_NV(msec);
}

XS(w32_GetShortPathName)
{
    dXSARGS;
    DWORD len;
    WCHAR wshort[MAX_PATH+1], *wlong;

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::GetShortPathName($longPathName)");

    wlong = sv_to_wstr(aTHX_ cv, ST(0));
    len = GetShortPathNameW(wlong, wshort, countof(wshort));
    Safefree(wlong);

    if (len && len < sizeof(wshort)) {
        ST(0) = wstr_to_sv(aTHX_ wshort, 0);
        XSRETURN(1);
    }

    XSRETURN_UNDEF;
}

XS(w32_GetFullPathName)
{
    dXSARGS;
    char *fullname;
    char *ansi = NULL;

/* The code below relies on the fact that PerlDir_mapX() returns an
 * absolute path, which is only true under PERL_IMPLICIT_SYS when
 * we use the virtualization code from win32/vdir.h.
 * Without it PerlDir_mapX() is a no-op and we need to use the same
 * code as we use for Cygwin.
 */
#if __CYGWIN__ || !defined(PERL_IMPLICIT_SYS)
    char buffer[2*MAX_PATH];
#endif

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::GetFullPathName($filename)");

#if __CYGWIN__ || !defined(PERL_IMPLICIT_SYS)
    {
        WCHAR *filename = sv_to_wstr(aTHX_ cv, ST(0));
        WCHAR full[2*MAX_PATH];
        DWORD len = GetFullPathNameW(filename, countof(full), full, NULL);
        Safefree(filename);
        if (len == 0 || len >= countof(full))
            XSRETURN_EMPTY;
        ansi = fullname = my_ansipath(full);
    }
#else
    /* Don't use my_ansipath() unless the $filename argument is in Unicode.
     * If the relative path doesn't exist, GetShortPathName() will fail and
     * my_ansipath() will use the long name with replacement characters.
     * In that case we will be better off using PerlDir_mapA(), which
     * already uses the ANSI name of the current directory.
     *
     * XXX The one missing case is where we could downgrade $filename
     * XXX from UTF8 into the current codepage.
     */
    if (SvUTF8(ST(0))) {
        WCHAR *filename = sv_to_wstr(aTHX_ cv, ST(0));
        WCHAR *mappedname = PerlDir_mapW(filename);
        Safefree(filename);
        ansi = fullname = my_ansipath(mappedname);
    }
    else {
        fullname = PerlDir_mapA(SvPV_nolen(ST(0)));
    }
#  if PERL_VERSION < 8
    {
        /* PerlDir_mapX() in Perl 5.6 used to return forward slashes */
        char *str = fullname;
        while (*str) {
            if (*str == '/')
                *str = '\\';
            ++str;
        }
    }
#  endif
#endif

    /* GetFullPathName() on Windows NT drops trailing backslash */
    if (g_osver.dwMajorVersion == 4 && *fullname) {
        STRLEN len;
        char *pv = SvPV(ST(0), len);
        char *lastchar = fullname + strlen(fullname) - 1;
        /* If ST(0) ends with a slash, but fullname doesn't ... */
        if (len && (pv[len-1] == '/' || pv[len-1] == '\\') && *lastchar != '\\') {
            /* fullname is the MAX_PATH+1 sized buffer returned from PerlDir_mapA()
             * or the 2*MAX_PATH sized local buffer in the __CYGWIN__ case.
             */
            if (lastchar - fullname < MAX_PATH - 1)
                strcpy(lastchar+1, "\\");
        }
    }

    if (GIMME_V == G_ARRAY) {
        char *filepart = strrchr(fullname, '\\');

        EXTEND(SP,1);
        if (filepart) {
            XST_mPV(1, ++filepart);
            *filepart = '\0';
        }
        else {
            XST_mPVN(1, "", 0);
        }
        items = 2;
    }
    XST_mPV(0, fullname);

    if (ansi)
        Safefree(ansi);
    XSRETURN(items);
}

XS(w32_GetLongPathName)
{
    dXSARGS;
    WCHAR *wstr, *long_path, wide_path[MAX_PATH+1];

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::GetLongPathName($pathname)");

    wstr = sv_to_wstr(aTHX_ cv, ST(0));

    if (wcslen(wstr) < (size_t)countof(wide_path)) {
        wcscpy(wide_path, wstr);
        long_path = my_longpathW(wide_path);
        if (long_path) {
            Safefree(wstr);
            ST(0) = wstr_to_sv(aTHX_ long_path, 0);
            XSRETURN(1);
        }
    }
    Safefree(wstr);
    XSRETURN_EMPTY;
}

XS(w32_GetANSIPathName)
{
    dXSARGS;
    WCHAR *wide_path;

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::GetANSIPathName($pathname)");

    wide_path = sv_to_wstr(aTHX_ cv, ST(0));
    ST(0) = wstr_to_ansipath(aTHX_ wide_path);
    Safefree(wide_path);
    XSRETURN(1);
}

XS(w32_Sleep)
{
    dXSARGS;
    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::Sleep($milliseconds)");
    Sleep((DWORD)SvIV(ST(0)));
    XSRETURN_YES;
}

XS(w32_CopyFile)
{
    dXSARGS;
    BOOL bResult;
    char *pszSourceFile;
    char szSourceFile[MAX_PATH+1];

    if (items != 3)
	Perl_croak(aTHX_ "usage: Win32::CopyFile($from, $to, $overwrite)");

    pszSourceFile = PerlDir_mapA(SvPV_nolen(ST(0)));
    if (strlen(pszSourceFile) < sizeof(szSourceFile)) {
        strcpy(szSourceFile, pszSourceFile);
        bResult = CopyFileA(szSourceFile, PerlDir_mapA(SvPV_nolen(ST(1))), !SvTRUE(ST(2)));
        if (bResult)
            XSRETURN_YES;
    }
    XSRETURN_NO;
}

XS(w32_OutputDebugString)
{
    dXSARGS;
    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::OutputDebugString($string)");

    if (SvUTF8(ST(0))) {
        WCHAR *str = sv_to_wstr(aTHX_ cv, ST(0));
        OutputDebugStringW(str);
        Safefree(str);
    }
    else
        OutputDebugStringA(SvPV_nolen(ST(0)));

    XSRETURN_EMPTY;
}

XS(w32_GetCurrentProcessId)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetCurrentProcessId()");
    EXTEND(SP,1);
    XSRETURN_IV(GetCurrentProcessId());
}

XS(w32_GetCurrentThreadId)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetCurrentThreadId()");
    EXTEND(SP,1);
    XSRETURN_IV(GetCurrentThreadId());
}

XS(w32_CreateDirectory)
{
    dXSARGS;
    BOOL result;

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::CreateDirectory($dir)");

    if (SvUTF8(ST(0))) {
        WCHAR *dir = sv_to_wstr(aTHX_ cv, ST(0));
        result = CreateDirectoryW(dir, NULL);
        Safefree(dir);
    }
    else {
        result = CreateDirectoryA(SvPV_nolen(ST(0)), NULL);
    }

    ST(0) = boolSV(result);
    XSRETURN(1);
}

XS(w32_CreateFile)
{
    dXSARGS;
    HANDLE handle;

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::CreateFile($file)");

    if (SvUTF8(ST(0))) {
        WCHAR *file = sv_to_wstr(aTHX_ cv, ST(0));
        handle = CreateFileW(file, GENERIC_WRITE, FILE_SHARE_WRITE,
                             NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
        Safefree(file);
    }
    else {
        handle = CreateFileA(SvPV_nolen(ST(0)), GENERIC_WRITE, FILE_SHARE_WRITE,
                             NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    }

    if (handle != INVALID_HANDLE_VALUE)
        CloseHandle(handle);

    ST(0) = boolSV(handle != INVALID_HANDLE_VALUE);
    XSRETURN(1);
}

XS(w32_GetSystemMetrics)
{
    dXSARGS;

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::GetSystemMetrics($index)");

    XSRETURN_IV(GetSystemMetrics((int)SvIV(ST(0))));
}

XS(w32_GetProductInfo)
{
    dXSARGS;
    DWORD type;
    HMODULE module;
    PFNGetProductInfo pfnGetProductInfo;

    if (items != 4)
	Perl_croak(aTHX_ "usage: Win32::GetProductInfo($major,$minor,$spmajor,$spminor)");

    module = GetModuleHandle("kernel32.dll");
    GETPROC(GetProductInfo);
    if (pfnGetProductInfo &&
        pfnGetProductInfo((DWORD)SvIV(ST(0)), (DWORD)SvIV(ST(1)),
                          (DWORD)SvIV(ST(2)), (DWORD)SvIV(ST(3)), &type))
    {
        XSRETURN_IV(type);
    }

    /* PRODUCT_UNDEFINED */
    XSRETURN_IV(0);
}

XS(w32_GetACP)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetACP()");
    EXTEND(SP,1);
    XSRETURN_IV(GetACP());
}

XS(w32_GetConsoleCP)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetConsoleCP()");
    EXTEND(SP,1);
    XSRETURN_IV(GetConsoleCP());
}

XS(w32_GetConsoleOutputCP)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetConsoleOutputCP()");
    EXTEND(SP,1);
    XSRETURN_IV(GetConsoleOutputCP());
}

XS(w32_GetOEMCP)
{
    dXSARGS;
    if (items)
	Perl_croak(aTHX_ "usage: Win32::GetOEMCP()");
    EXTEND(SP,1);
    XSRETURN_IV(GetOEMCP());
}

XS(w32_SetConsoleCP)
{
    dXSARGS;

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::SetConsoleCP($id)");

    XSRETURN_IV(SetConsoleCP((int)SvIV(ST(0))));
}

XS(w32_SetConsoleOutputCP)
{
    dXSARGS;

    if (items != 1)
	Perl_croak(aTHX_ "usage: Win32::SetConsoleOutputCP($id)");

    XSRETURN_IV(SetConsoleOutputCP((int)SvIV(ST(0))));
}

XS(w32_GetProcessPrivileges)
{
    dXSARGS;
    BOOL ret;
    HV *priv_hv;
    HANDLE proc_handle, token;
    char *priv_name = NULL;
    TOKEN_PRIVILEGES *privs = NULL;
    DWORD i, pid, priv_name_len = 100, privs_len = 300;

    if (items > 1)
        Perl_croak(aTHX_ "usage: Win32::GetProcessPrivileges([$pid])");

    if (items == 0) {
        EXTEND(SP, 1);
        pid = GetCurrentProcessId();
    }
    else {
        pid = (DWORD)SvUV(ST(0));
    }

    proc_handle = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, pid);

    if (!proc_handle)
        XSRETURN_NO;

    ret = OpenProcessToken(proc_handle, TOKEN_QUERY, &token);
    CloseHandle(proc_handle);

    if (!ret)
        XSRETURN_NO;

    do {
        Renewc(privs, privs_len, char, TOKEN_PRIVILEGES);
        ret = GetTokenInformation(
            token, TokenPrivileges, privs, privs_len, &privs_len
        );
    } while (!ret && GetLastError() == ERROR_INSUFFICIENT_BUFFER);

    CloseHandle(token);

    if (!ret) {
        Safefree(privs);
        XSRETURN_NO;
    }

    priv_hv = newHV();
    New(0, priv_name, priv_name_len, char);

    for (i = 0; i < privs->PrivilegeCount; ++i) {
        DWORD ret_len = 0;
        LUID_AND_ATTRIBUTES *priv = &privs->Privileges[i];
        BOOL is_enabled = !!(priv->Attributes & SE_PRIVILEGE_ENABLED);

        if (priv->Attributes & SE_PRIVILEGE_REMOVED)
            continue;

        do {
            ret_len = priv_name_len;
            ret = LookupPrivilegeNameA(
                NULL, &priv->Luid, priv_name, &ret_len
            );

            if (ret_len > priv_name_len) {
                priv_name_len = ret_len + 1;
                Renew(priv_name, priv_name_len, char);
            }
        } while (!ret && GetLastError() == ERROR_INSUFFICIENT_BUFFER);

        if (!ret) {
            SvREFCNT_dec((SV*)priv_hv);
            Safefree(privs);
            Safefree(priv_name);
            XSRETURN_NO;
        }

        hv_store(priv_hv, priv_name, ret_len, newSViv(is_enabled), 0);
    }

    Safefree(privs);
    Safefree(priv_name);

    ST(0) = sv_2mortal(newRV_noinc((SV*)priv_hv));
    XSRETURN(1);
}

XS(w32_IsDeveloperModeEnabled)
{
    dXSARGS;
    LONG status;
    DWORD val, val_size = sizeof(val);
    PFNRegGetValueA pfnRegGetValueA;
    HMODULE module;

    if (items)
        Perl_croak(aTHX_ "usage: Win32::IsDeveloperModeEnabled()");

    EXTEND(SP, 1);

    /* developer mode was introduced in Windows 10 */
    if (g_osver.dwMajorVersion < 10)
        XSRETURN_NO;

    module = GetModuleHandleA("advapi32.dll");
    GETPROC(RegGetValueA);
    if (!pfnRegGetValueA)
        XSRETURN_NO;

    status = pfnRegGetValueA(
        HKEY_LOCAL_MACHINE,
        "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock",
        "AllowDevelopmentWithoutDevLicense",
        RRF_RT_REG_DWORD | KEY_WOW64_64KEY,
        NULL,
        &val,
        &val_size
    );

    if (status == ERROR_SUCCESS && val == 1)
        XSRETURN_YES;

    XSRETURN_NO;
}

XS(w32_CLONE)
{
    dXSARGS;
    HMODULE h;
    WCHAR buf [MAX_PATH*2]; /* times 2 why not? 32KB paths one day lol*/
    WCHAR * wp;
    WCHAR * wpnew;
    DWORD len;
    MY_CXT_CLONE; /* a redundant memcpy() on this line */
    wp = MY_CXT.s32dir;
    if(wp) {
      len = MY_CXT.s32dirlen+1;
      New(0, wpnew, len, WCHAR);
      MY_CXT.s32dir = wpnew;
      Move(wp, wpnew, len, WCHAR);
    }
#ifdef WINHTTPAPI
    h = MY_CXT.winhttp;
    if(h) { /* bump ref count on dll */
        InterlockedIncrement(&WinHttpRefCnt);
        if(!GetModuleFileNameW(h, (WCHAR *)buf, (sizeof(buf)/sizeof(WCHAR))-1)) {
            DecRefWinHttp();
            Perl_croak_nocontext("Win32.pm WinHttp DLL load failed %u", GetLastError());
        }
        h = LoadLibraryW((WCHAR *)buf);
        MY_CXT.winhttp = h;
        if(!h) {
            DecRefWinHttp();
            Perl_croak_nocontext("Win32.pm WinHttp DLL load failed %u", GetLastError());
        }
    }
#endif
#ifdef USERENV_API_DLL
    dll_ref_inc(cv, MY_CXT.userenv);
#endif
#ifdef SHFOLDER_API_DLL
    dll_ref_inc(cv, MY_CXT.shfolder);
#endif
#ifdef SHELL32_API_DLL
    dll_ref_inc(cv, MY_CXT.shell32);
#endif
#ifdef USER32_API_DLL
    dll_ref_inc(cv, MY_CXT.user32);
#endif
#ifdef NETAPI32_API_DLL
    dll_ref_inc(cv, MY_CXT.netapi32);
#endif
#ifdef VERSION_API_DLL
    dll_ref_inc(cv, MY_CXT.version);
#endif
#ifdef OLE32_API_DLL
    dll_ref_inc(cv, MY_CXT.ole32);
#endif
}

XS(w32_END)
{
    dXSARGS;
    {
        dMY_CXT;
        HMODULE h;
        WCHAR * wp;
        wp = MY_CXT.s32dir;
        if(wp) {
          MY_CXT.s32dir = NULL;
          MY_CXT.s32dirlen = 0;
          Safefree(wp);
        }
#ifdef WINHTTPAPI
        h = MY_CXT.winhttp;
        if(h) {
            MY_CXT.winhttp = NULL;
            DecRefWinHttp();
            FreeLibrary(h);
        }
#endif
#ifdef USERENV_API_DLL
    dll_ref_dec(cv, &MY_CXT.userenv);
#endif
#ifdef SHFOLDER_API_DLL
    dll_ref_dec(cv, &MY_CXT.shfolder);
#endif
#ifdef SHELL32_API_DLL
    dll_ref_dec(cv, &MY_CXT.shell32);
#endif
#ifdef USER32_API_DLL
    dll_ref_dec(cv, &MY_CXT.user32);
#endif
#ifdef NETAPI32_API_DLL
    dll_ref_dec(cv, &MY_CXT.netapi32);
#endif
#ifdef VERSION_API_DLL
    dll_ref_dec(cv, &MY_CXT.version);
#endif
#ifdef OLE32_API_DLL
    dll_ref_dec(cv, &MY_CXT.ole32);
#endif
    }
}

#ifdef WINHTTPAPI

XS(w32_StubLoadWinHttp) {
    HMODULE module;
    LONG old;
    old = InterlockedCompareExchange(&WinHttpLoaded, 1, 0);
    if(old) {
        retry:
        if(old == 1) {
            Sleep(1);
            old = WinHttpLoaded;
            goto retry;
        }
        else if(old == 2) {
            InterlockedIncrement(&WinHttpRefCnt);
            module = LoadLibraryW(L"winhttp");
            if(!module) {
                DecRefWinHttp();
                Perl_croak_nocontext("Win32.pm WinHttp DLL load failed %u", GetLastError());
            }
            else {
                dMY_CXT;
                MY_CXT.winhttp = module;
                CvXSUB(cv) = w32_HttpGetFile;
                w32_HttpGetFile(aTHX_ cv);
                return;
            }
        }
        else {
            Perl_croak_nocontext("Win32.pm WinHttp thread race load failure state %u", old);
        }
    }
    InterlockedIncrement(&WinHttpRefCnt);
    module = LoadLibraryW(L"winhttp");
    if(!module) {
        InterlockedExchange(&WinHttpLoaded, 3);
        DecRefWinHttp();
        InterlockedExchange(&WinHttpLoaded, 3);
        Perl_croak_nocontext("Win32.pm WinHttp DLL load failed %u", GetLastError());
    }
    GETPROC(WinHttpCrackUrl);
    GETPROC(WinHttpOpen);
    GETPROC(WinHttpCloseHandle);
    GETPROC(WinHttpConnect);
    GETPROC(WinHttpReadData);
    GETPROC(WinHttpSetOption);
    GETPROC(WinHttpOpenRequest);
    GETPROC(WinHttpAddRequestHeaders);
    GETPROC(WinHttpSendRequest);
    GETPROC(WinHttpReceiveResponse);
    GETPROC(WinHttpQueryHeaders);
    GETPROC(WinHttpGetProxyForUrl);
    old = InterlockedExchange(&WinHttpLoaded, 2);
    if(old != 1) {
        DecRefWinHttp();
        FreeLibrary(module);
        Perl_croak_nocontext("Win32.pm WinHttp thread race load failure state %u", old);
    }
    else {
        dMY_CXT;
        MY_CXT.winhttp = module;
        CvXSUB(cv) = w32_HttpGetFile;
        w32_HttpGetFile(aTHX_ cv);
        return;
    }
}

XS(w32_HttpGetFile)
{
    dXSARGS;
    U8 gimme_v;
    MAGIC * mg;
    HGF_DTOR_T * dtor;
    WCHAR *url = NULL, *file = NULL, *hostName = NULL, *urlPath = NULL;
    STRLEN url_len, file_len;
    bool bIgnoreCertErrors = FALSE;
    WCHAR msgbuf[ONE_K_BUFSIZE];
    BOOL  bResults = FALSE;
    HINTERNET  hSession = NULL,
               hConnect = NULL,
               hRequest = NULL;
    HANDLE hOut = INVALID_HANDLE_VALUE;
    BOOL   bParsed = FALSE,
           bAborted = FALSE,
           bFileError = FALSE,
           bHttpError = FALSE;
    DWORD error = 0;
    DWORD cur = 0;
    DWORD last = 0;
    URL_COMPONENTS urlComp;
    static const LPCWSTR acceptTypes[] = { L"*/*", NULL };
    DWORD dwHttpStatusCode = 0, dwQuerySize = 0;

    msgbuf[0] = '\0'; /* only first WCHAR, not entire buf, don't = {0} */
    if (items < 2 || items > 3)
        croak_xs_usage(cv, "url, file [, ignore_cert_errors]");
    mg  = sv_magicext(  sv_newmortal(), NULL, PERL_MAGIC_ext, &hgf_mg_vtbl,
                        NULL, 0);
    New(0, dtor, 1 , HGF_DTOR_T);
    mg->mg_ptr = (char *)dtor;
    mg->mg_len = sizeof(HGF_DTOR_T);
    mg->mg_flags |= MGf_DUP;
    /* init struct with empty values */
    hgf_dup(aTHX_ mg, NULL);

    XSprePUSH;
    SP++;
    url = sv_to_wstr_len(aTHX_ cv, *SP, &url_len);
    SAVEFREEPV(url);
    SP++;
    dtor->file = file = sv_to_wstr_len(aTHX_ cv, *SP, &file_len);
    if (items == 3) {
        SP++;
        bIgnoreCertErrors = (BOOL)SvIV(*SP);
    }
    /* rewind SP, prep stack for retvals later, dont need incoming SV*s anymore */
    XSprePUSH;
    /* paranoia, no PP callbacks or maybe PL stack realloc API calls, but w/e */
    PUTBACK;

    /* Initialize the URL_COMPONENTS structure, setting the required
     * component lengths to non-zero so that they get populated.
     */
    ZeroMemory(&urlComp, sizeof(urlComp));
    urlComp.dwStructSize = sizeof(urlComp);
    urlComp.dwSchemeLength    = (DWORD)-1;
    urlComp.dwHostNameLength  = (DWORD)-1;
    urlComp.dwUrlPathLength   = (DWORD)-1;
    urlComp.dwExtraInfoLength = (DWORD)-1;

    /* Parse the URL. */
    bParsed = pfnWinHttpCrackUrl(url, (DWORD)url_len, 0, &urlComp);

    /* Only support http and htts, not ftp, gopher, etc. */
    if (bParsed
        && !(urlComp.nScheme == INTERNET_SCHEME_HTTPS
             || urlComp.nScheme == INTERNET_SCHEME_HTTP)) {
        SetLastError(12006); /* not a recognized protocol */
        bParsed = FALSE;
    }

    if (bParsed) {
        hostName = SAFE_ALLOCA(urlComp.dwHostNameLength + 1
                    + urlComp.dwUrlPathLength + urlComp.dwExtraInfoLength + 1,
                    WCHAR);
        Move( urlComp.lpszHostName, hostName,
              urlComp.dwHostNameLength, WCHAR);
        urlPath = hostName+urlComp.dwHostNameLength;
        urlPath[0] = '\0';
        urlPath++;

        /* Note shortcut, we assume NOTHING is removed in URL
         * "/Acme-Module-0.1.tar.gz?sessionid=12345" between "tar.gz" and "?".
         * We don't use the urlComp.lpszExtraInfo WCHAR *, but we are using
         * urlComp.dwExtraInfoLength length */
        Move( urlComp.lpszUrlPath, urlPath,
              urlComp.dwUrlPathLength + urlComp.dwExtraInfoLength, WCHAR);
        urlPath[urlComp.dwUrlPathLength + urlComp.dwExtraInfoLength] = '\0';

        /* XXX Add perl version to UA or metadata is bad? */
        /* Use WinHttpOpen to obtain a session handle. */
        hSession = pfnWinHttpOpen(L"Perl",
                               WINHTTP_ACCESS_TYPE_NO_PROXY,
                               WINHTTP_NO_PROXY_NAME,
                               WINHTTP_NO_PROXY_BYPASS,
                               0);
    }

    /* Specify an HTTP server. */
    if (hSession) {
        dtor->hSession = hSession;
        hConnect = pfnWinHttpConnect(hSession,
                                  hostName,
                                  urlComp.nPort,
                                  0);
    }

    HGF_ASYNC_CHECK;
    /* Create an HTTP request handle. */
    if (hConnect) {
        dtor->hConnect = hConnect;
        hRequest = pfnWinHttpOpenRequest(hConnect,
                                      L"GET",
                                      urlPath,
                                      NULL,
                                      WINHTTP_NO_REFERER,
                                      /* MS API wrong decl, this is RO input */
                                      (LPCWSTR *)acceptTypes,
                                      urlComp.nScheme == INTERNET_SCHEME_HTTPS
                                                      ? WINHTTP_FLAG_SECURE
                                                      : 0);
    }

    HGF_ASYNC_CHECK;
    if(hRequest)
      dtor->hRequest = hRequest;

    /* If specified, disable certificate-related errors for https connections. */
    if (hRequest
        && bIgnoreCertErrors
        && urlComp.nScheme == INTERNET_SCHEME_HTTPS) {
        DWORD secFlags = SECURITY_FLAG_IGNORE_CERT_CN_INVALID
                         | SECURITY_FLAG_IGNORE_CERT_DATE_INVALID
                         | SECURITY_FLAG_IGNORE_UNKNOWN_CA
                         | SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE;
        if(!pfnWinHttpSetOption(hRequest,
                             WINHTTP_OPTION_SECURITY_FLAGS,
                             &secFlags,
                             sizeof(secFlags))) {
            bAborted = TRUE;
        }
    }

    /* Call WinHttpGetProxyForUrl with our target URL. If auto-proxy succeeds,
     * then set the proxy info on the request handle. If auto-proxy fails,
     * ignore the error and attempt to send the HTTP request directly to the
     * target server (using the default WINHTTP_ACCESS_TYPE_NO_PROXY
     * configuration, which the request handle will inherit from the session).
     */
    if (hRequest && !bAborted) {
        HGF_PXYINFO_T pi;

        ZeroMemory(&pi, sizeof(pi)); /* null fill 2 structs, 1 func call */
        pi.AutoProxyOptions.dwFlags = WINHTTP_AUTOPROXY_AUTO_DETECT;
        pi.AutoProxyOptions.dwAutoDetectFlags =
                                    WINHTTP_AUTO_DETECT_TYPE_DHCP |
                                    WINHTTP_AUTO_DETECT_TYPE_DNS_A;
        pi.AutoProxyOptions.fAutoLogonIfChallenged = TRUE;

        if(pfnWinHttpGetProxyForUrl(hSession,
                                url,
                                &pi.AutoProxyOptions,
                                &pi.ProxyInfo)) {
            LPWSTR wProxyStr;
            if(!pfnWinHttpSetOption(hRequest,
                                WINHTTP_OPTION_PROXY,
                                &pi.ProxyInfo,
                                sizeof(pi.ProxyInfo))) {
                bAborted = TRUE;
                Perl_warn(aTHX_ "Win32::HttpGetFile: setting proxy options failed");
            }
/* bug fixed, perl's Safefree() is not GlobalFree(), different mem pools,
   different malloc-type headers before "your pointer" */
            wProxyStr = pi.ProxyInfo.lpszProxy;
            if(wProxyStr) {
                pi.ProxyInfo.lpszProxy = NULL;
                GlobalFree(wProxyStr);
            }
            wProxyStr = pi.ProxyInfo.lpszProxyBypass;
            if(wProxyStr) {
                pi.ProxyInfo.lpszProxyBypass = NULL;
                GlobalFree(wProxyStr);
            }
        }
        HGF_ASYNC_CHECK;
    }

    /* Send a request. */
    if (hRequest && !bAborted)
        bResults = pfnWinHttpSendRequest(hRequest,
                                      WINHTTP_NO_ADDITIONAL_HEADERS,
                                      0,
                                      WINHTTP_NO_REQUEST_DATA,
                                      0,
                                      0,
                                      0);

    HGF_ASYNC_CHECK;
    /* End the request. */
    if (bResults)
        bResults = pfnWinHttpReceiveResponse(hRequest, NULL);

    HGF_ASYNC_CHECK;
    /* Retrieve HTTP status code. */
    if (bResults) {
        dwQuerySize = sizeof(dwHttpStatusCode);
        bResults = pfnWinHttpQueryHeaders(hRequest,
                                       WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                                       WINHTTP_HEADER_NAME_BY_INDEX,
                                       &dwHttpStatusCode,
                                       &dwQuerySize,
                                       WINHTTP_NO_HEADER_INDEX);
    }

    /* Retrieve HTTP status text. Note this may be a success message. */
    if (bResults) {
        dwQuerySize = (ONE_K_BUFSIZE * sizeof(WCHAR)) - sizeof(WCHAR);
        bResults = pfnWinHttpQueryHeaders(hRequest,
                                       WINHTTP_QUERY_STATUS_TEXT,
                                       WINHTTP_HEADER_NAME_BY_INDEX,
                                       msgbuf,
                                       &dwQuerySize,
                                       WINHTTP_NO_HEADER_INDEX);
        if(bResults) {
            msgbuf[dwQuerySize/sizeof(WCHAR)] = '\0';
        } else {
            msgbuf[0] = '\0';
        }
    }

    /* There is no point in successfully downloading an error page from
     * the server, so consider HTTP errors to be failures.
     */
    if (bResults) {
        if (dwHttpStatusCode < 200 || dwHttpStatusCode > 299) {
            bResults = FALSE;
            bHttpError = TRUE;
        }
    }

    HGF_ASYNC_CHECK;
    /* Create output file for download. */
    if (bResults) {
        hOut = CreateFileW(file,
                           GENERIC_WRITE,
                           FILE_SHARE_READ | FILE_SHARE_WRITE,
                           NULL,
                           CREATE_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL,
                           NULL);

        if (hOut == INVALID_HANDLE_VALUE) {
            bFileError = TRUE;
        }
        else {
          dtor->hOut = hOut;
        }
    }

    if (!bFileError && bResults) {
        DWORD dwDownloaded = 0;
        DWORD dwBytesWritten = 0;
        char OutBuffer [0xFFFF];
        DWORD dwSize = sizeof(OutBuffer);
        char * pszOutBuffer = (char *)OutBuffer;

        /* Keep checking for data until there is nothing left. */
        while (1) {
            HGF_ASYNC_CHECK;
            if (!pfnWinHttpReadData(hRequest,
                                 (LPVOID)pszOutBuffer,
                                 dwSize,
                                 &dwDownloaded)) {
                bAborted = TRUE;
                break;
            }
            if (!dwDownloaded)
                break;

            /* Write what we just read to the output file */
            if (!WriteFile(hOut,
                           pszOutBuffer,
                           dwDownloaded,
                           &dwBytesWritten,
                           NULL)) {
                bAborted = TRUE;
                bFileError = TRUE;
                break;
            }

        }

    }
    else {
        bAborted = TRUE;
    }

    /* Clean-up may lose this. */
    if (bAborted)
        error = GetLastError();

    /* If we successfully opened the output file but failed later, mark
     * the file for deletion.
     */
    if (bAborted && hOut != INVALID_HANDLE_VALUE) {
        HANDLE h = hOut;
        hOut = INVALID_HANDLE_VALUE;
        dtor->hOut = INVALID_HANDLE_VALUE;
        CloseHandle(h);
        (void) DeleteFileW(file);
    }

    /* Close any open handles. */
    /* Do ASAP to flush disk file handle, and release all file locks.
       FILE_SHARE_READ | FILE_SHARE_WRITE, are file locks themselves and
       can block a future CreateFile/open().  When the SV mortal MG dtor
       actually runs is questionable.  It WILL run, but when vs open() ?*/
    if (hOut != INVALID_HANDLE_VALUE) {
      HANDLE h = hOut;
      hOut = INVALID_HANDLE_VALUE;
      dtor->hOut = INVALID_HANDLE_VALUE;
      CloseHandle(h);
    }

    /* Just let the SV MG dtor do it
    if (hRequest) pfnWinHttpCloseHandle(hRequest);
    if (hConnect) pfnWinHttpCloseHandle(hConnect);
    if (hSession) pfnWinHttpCloseHandle(hSession);
    if (file) Safefree(file);
    */

    /* Retrieve system and WinHttp error messages, or compose a user-defined
     * error code if we got a failed HTTP status text above.  Conveniently, adding
     * 1e9 to the HTTP status sets bit 29, denoting a user-defined error code,
     * and also makes it easy to lop off the upper part and just get HTTP status.
     */
    if (bAborted) {
        if (bHttpError) {
            SetLastError(dwHttpStatusCode + 1000000000);
        }
        else {
            DWORD msg_len;
            dMY_CXT;
            DWORD msgFlags = bFileError
                            ? FORMAT_MESSAGE_FROM_SYSTEM
                            : FORMAT_MESSAGE_FROM_HMODULE;
            msgFlags |= FORMAT_MESSAGE_IGNORE_INSERTS;
/* "The WinHTTP Web Proxy Auto-Discovery Service detected a non- local RPC
request (Transport Type = %1); Access Denied. There may have been an rogue
attempt to gain access to the service through the network." at ~204 chars
is probably the longest, but i8ln. */
            msg_len = FormatMessageW(msgFlags,
                                MY_CXT.winhttp, /* HMODULE */
                                error,
                                0,
                                msgbuf,
                                ONE_K_BUFSIZE - 1, /* TCHARs, not bytes */
                                NULL);
            if(msg_len) {
                msgbuf[msg_len] = '\0'; /* paranoia */
            }
            else {
                DWORD msg_len = sizeof(L"unable to format error message");
                if(msg_len > sizeof(msgbuf)-1) /* assert will optimize out */
                    croak_sub_glr(cv, "msgbuf", ERROR_BUFFER_OVERFLOW);
                Move(L"unable to format error message", msgbuf, msg_len/2, WCHAR);
            }
            SetLastError(error);
        }
    }

    gimme_v = GIMME_V;
    SPAGAIN; /* paranoia */
    if(gimme_v != G_VOID) {
        /* no EXTEND, 2 arg min check above */
        SV * sv = !bAborted ? &PL_sv_yes : &PL_sv_no;
        PUSHs(sv);
        if (gimme_v == G_ARRAY) {
            if(msgbuf[0]) {
                error = GetLastError();
                sv = wstr_to_sv(aTHX_ msgbuf, 0);
                SetLastError(error);
            }
            else
                sv = &PL_sv_no;
            PUSHs(sv);
        }
    }
    PUTBACK;
    return;
}

#endif

MODULE = Win32            PACKAGE = Win32

PROTOTYPES: DISABLE

BOOT:
{
    char *file = (char *)__FILE__; /* silence const warnings 5.6 */
    if(sizeof(my_cxt_t) != sizeof(fntable_t)) /* assert optize away*/
        croak_sub_glr(cv, "my_cxt_t fntable_t mismatch", ERROR_INSUFFICIENT_BUFFER);
    if (g_osver.dwOSVersionInfoSize == 0) {
        g_osver.dwOSVersionInfoSize = sizeof(g_osver);
        if (!GetVersionExA((OSVERSIONINFOA*)&g_osver)) {
            g_osver_ex = FALSE;
            g_osver.dwOSVersionInfoSize = sizeof(OSVERSIONINFOA);
            GetVersionExA((OSVERSIONINFOA*)&g_osver);
        }
    }

    newXS("Win32::LookupAccountName", w32_LookupAccountName, file);
    newXS("Win32::LookupAccountSID", w32_LookupAccountSID, file);
    newXS("Win32::InitiateSystemShutdown", w32_InitiateSystemShutdown, file);
    newXS("Win32::AbortSystemShutdown", w32_AbortSystemShutdown, file);
    newXS("Win32::ExpandEnvironmentStrings", w32_ExpandEnvironmentStrings, file);
    newXS("Win32::MsgBox", w32_MsgBox, file);
    newXS("Win32::LoadLibrary", w32_LoadLibrary, file);
    newXS("Win32::FreeLibrary", w32_FreeLibrary, file);
    newXS("Win32::GetProcAddress", w32_GetProcAddress, file);
    newXS("Win32::RegisterServer", w32_RegisterServer, file);
    newXS("Win32::UnregisterServer", w32_UnregisterServer, file);
    newXS("Win32::GetArchName", w32_GetArchName, file);
    newXS("Win32::GetChipArch", w32_GetChipArch, file);
    newXS("Win32::GetChipName", w32_GetChipName, file);
    newXS("Win32::GuidGen", w32_GuidGen, file);
    newXS("Win32::GetFolderPath", w32_GetFolderPath, file);
    newXS("Win32::IsAdminUser", w32_IsAdminUser, file);
    newXS("Win32::GetFileVersion", w32_GetFileVersion, file);

    newXS("Win32::GetCwd", w32_GetCwd, file);
    newXS("Win32::SetCwd", w32_SetCwd, file);
    newXS("Win32::GetNextAvailDrive", w32_GetNextAvailDrive, file);
    newXS("Win32::GetLastError", w32_GetLastError, file);
    newXS("Win32::SetLastError", w32_SetLastError, file);
    newXS("Win32::LoginName", w32_LoginName, file);
    newXS("Win32::NodeName", w32_NodeName, file);
    newXS("Win32::DomainName", w32_DomainName, file);
    newXS("Win32::FsType", w32_FsType, file);
    newXS("Win32::GetOSVersion", w32_GetOSVersion, file);
    newXS("Win32::IsWinNT", w32_IsWinNT, file);
    newXS("Win32::IsWin95", w32_IsWin95, file);
    newXS("Win32::FormatMessage", w32_FormatMessage, file);
    newXS("Win32::Spawn", w32_Spawn, file);
    newXS("Win32::GetTickCount", w32_GetTickCount, file);
    newXS("Win32::GetShortPathName", w32_GetShortPathName, file);
    newXS("Win32::GetFullPathName", w32_GetFullPathName, file);
    newXS("Win32::GetLongPathName", w32_GetLongPathName, file);
    newXS("Win32::GetANSIPathName", w32_GetANSIPathName, file);
    newXS("Win32::CopyFile", w32_CopyFile, file);
    newXS("Win32::Sleep", w32_Sleep, file);
    newXS("Win32::OutputDebugString", w32_OutputDebugString, file);
    newXS("Win32::GetCurrentProcessId", w32_GetCurrentProcessId, file);
    newXS("Win32::GetCurrentThreadId", w32_GetCurrentThreadId, file);
    newXS("Win32::CreateDirectory", w32_CreateDirectory, file);
    newXS("Win32::CreateFile", w32_CreateFile, file);
    newXS("Win32::GetSystemMetrics", w32_GetSystemMetrics, file);
    newXS("Win32::GetProductInfo", w32_GetProductInfo, file);
    newXS("Win32::GetACP", w32_GetACP, file);
    newXS("Win32::GetConsoleCP", w32_GetConsoleCP, file);
    newXS("Win32::GetConsoleOutputCP", w32_GetConsoleOutputCP, file);
    newXS("Win32::GetOEMCP", w32_GetOEMCP, file);
    newXS("Win32::SetConsoleCP", w32_SetConsoleCP, file);
    newXS("Win32::SetConsoleOutputCP", w32_SetConsoleOutputCP, file);
    newXS("Win32::GetProcessPrivileges", w32_GetProcessPrivileges, file);
    newXS("Win32::IsDeveloperModeEnabled", w32_IsDeveloperModeEnabled, file);
#ifdef __CYGWIN__
    newXS("Win32::SetChildShowWindow", w32_SetChildShowWindow, file);
#endif
#ifdef WINHTTPAPI
    newXS("Win32::HttpGetFile", w32_StubLoadWinHttp, file);
#endif
    newXS("Win32::CLONE", w32_CLONE, file);
    newXS("Win32::END", w32_END, file);
    MY_CXT_INIT;
    XSRETURN_YES;
}
