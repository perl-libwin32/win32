#if !defined(my_snprintf)
#  define my_snprintf S_my_snprintf
static int S_my_snprintf(char *buffer, const Size_t len, const char *format, ...)
{
    int retval;
    va_list ap;
    va_start(ap, format);
#ifdef HAS_VSNPRINTF
    retval = vsnprintf(buffer, len, format, ap);
#else
    retval = vsprintf(buffer, format, ap);
#endif
    va_end(ap);
    if (retval < 0 || (len > 0 && (Size_t)retval >= len))
        Perl_croak_nocontext("panic: my_snprintf buffer overflow");
    return retval;
}
#endif

#ifndef newSVpvs
#  define newSVpvs(str)                  newSVpvn(str "", sizeof(str) - 1)
#endif

#if defined(MULTIPLICITY) || defined(PERL_OBJECT) || \
    defined(PERL_CAPI)    || defined(PERL_IMPLICIT_CONTEXT)

#ifndef START_MY_CXT

/* This must appear in all extensions that define a my_cxt_t structure,
 * right after the definition (i.e. at file scope).  The non-threads
 * case below uses it to declare the data as static. */
#define START_MY_CXT

#if (PERL_BCDVERSION < 0x5004068)
/* Fetches the SV that keeps the per-interpreter data. */
#define dMY_CXT_SV \
        SV *my_cxt_sv = get_sv(MY_CXT_KEY, FALSE)
#else /* >= perl5.004_68 */
#define dMY_CXT_SV \
        SV *my_cxt_sv = *hv_fetch(PL_modglobal, MY_CXT_KEY,             \
                                  sizeof(MY_CXT_KEY)-1, TRUE)
#endif /* < perl5.004_68 */

/* This declaration should be used within all functions that use the
 * interpreter-local data. */
#define dMY_CXT \
        dMY_CXT_SV;                                                     \
        my_cxt_t *my_cxtp = INT2PTR(my_cxt_t*,SvUV(my_cxt_sv))

/* Creates and zeroes the per-interpreter data.
 * (We allocate my_cxtp in a Perl SV so that it will be released when
 * the interpreter goes away.) */
#define MY_CXT_INIT \
        dMY_CXT_SV;                                                     \
        /* newSV() allocates one more than needed */                    \
        my_cxt_t *my_cxtp = (my_cxt_t*)SvPVX(newSV(sizeof(my_cxt_t)-1));\
        Zero(my_cxtp, 1, my_cxt_t);                                     \
        sv_setuv(my_cxt_sv, PTR2UV(my_cxtp))

/* This macro must be used to access members of the my_cxt_t structure.
 * e.g. MYCXT.some_data */
#define MY_CXT          (*my_cxtp)

/* Judicious use of these macros can reduce the number of times dMY_CXT
 * is used.  Use is similar to pTHX, aTHX etc. */
#define pMY_CXT         my_cxt_t *my_cxtp
#define pMY_CXT_        pMY_CXT,
#define _pMY_CXT        ,pMY_CXT
#define aMY_CXT         my_cxtp
#define aMY_CXT_        aMY_CXT,
#define _aMY_CXT        ,aMY_CXT

#endif /* START_MY_CXT */

#ifndef MY_CXT_CLONE
/* Clones the per-interpreter data. */
#define MY_CXT_CLONE \
        dMY_CXT_SV;                                                     \
        my_cxt_t *my_cxtp = (my_cxt_t*)SvPVX(newSV(sizeof(my_cxt_t)-1));\
        Copy(INT2PTR(my_cxt_t*, SvUV(my_cxt_sv)), my_cxtp, 1, my_cxt_t);\
        sv_setuv(my_cxt_sv, PTR2UV(my_cxtp))
#endif

#else /* single interpreter */

#ifndef START_MY_CXT

#define START_MY_CXT    static my_cxt_t my_cxt;
#define dMY_CXT_SV      dNOOP
#define dMY_CXT         dNOOP
#define MY_CXT_INIT     NOOP
#define MY_CXT          my_cxt

#define pMY_CXT         void
#define pMY_CXT_
#define _pMY_CXT
#define aMY_CXT
#define aMY_CXT_
#define _aMY_CXT

#endif /* START_MY_CXT */

#ifndef MY_CXT_CLONE
#define MY_CXT_CLONE    NOOP
#endif

#endif

#ifndef PERL_UNUSED_ARG
#  define PERL_UNUSED_ARG(x) ((void)x)
#endif

#ifndef SE_PRIVILEGE_REMOVED
#define SE_PRIVILEGE_REMOVED 0x00000004
#endif

#ifndef RRF_RT_REG_DWORD
#define RRF_RT_REG_DWORD       0x00000010
#endif

#ifndef KEY_WOW64_64KEY
#define KEY_WOW64_64KEY        0x0100
#endif


#if !defined(_MSC_VER) || !(defined(_MSC_VER) && _MSC_VER >= 1300)
#  define SHFOLDER_API_DLL 1
#endif

#if defined(__GNUC__) && !(defined(_WIN32_IE) && _WIN32_IE >= 0x0400)
/* SHGetSpecialFolderPathW missing */
#  define SHELL32_API_DLL 1
#endif

#ifdef SHFOLDER_API_DLL
typedef HRESULT (__stdcall * PFNSHGetFolderPathW)(HWND, int, HANDLE, DWORD, LPWSTR);
#endif

#ifdef USERENV_API_DLL
typedef BOOL(__stdcall * PFNDestroyEnvironmentBlock)(LPVOID  lpEnvironment);
typedef BOOL(__stdcall * PFNCreateEnvironmentBlock)(
    LPVOID *lpEnvironment,
    HANDLE  hToken,
    BOOL    bInherit);
#endif

#ifdef SHELL32_API_DLL
typedef BOOL (__stdcall * PFNSHGetSpecialFolderPathW)(
        HWND   hwnd,
  LPWSTR pszPath,
  int    csidl,
  BOOL   fCreate
);
#endif

#ifdef USER32_API_DLL
typedef int (__stdcall * PFNMessageBoxW)(
   HWND    hWnd,
   LPCWSTR lpText,
   LPCWSTR lpCaption,
             UINT    uType
);
typedef int (__stdcall * PFNGetSystemMetrics)(int nIndex);
typedef HWND (__stdcall * PFNGetActiveWindow)();
#endif

#ifdef NETAPI32_API_DLL
typedef NET_API_STATUS (__stdcall * PFNNetWkstaGetInfo)(
    LMSTR  servername,
    DWORD  level,
   LPBYTE *bufptr
);
typedef NET_API_STATUS (__stdcall * PFNNetApiBufferFree)(LPVOID Buffer);
#endif

#ifdef VERSION_API_DLL
typedef BOOL (__stdcall * PFNGetFileVersionInfoA)(
    LPCSTR lptstrFilename,
        DWORD  dwHandle,
    DWORD  dwLen,
   LPVOID lpData
);
typedef DWORD (__stdcall * PFNGetFileVersionInfoSizeA)(
LPCSTR  lptstrFilename,
   LPDWORD lpdwHandle
);
typedef BOOL (__stdcall * PFNVerQueryValueA)(
    LPCVOID pBlock,
    LPCSTR  lpSubBlock,
   LPVOID  *lplpBuffer,
   PUINT   puLen
);
#endif

#ifdef OLE32_API_DLL
typedef HRESULT (__stdcall * PFNCoCreateGuid)(GUID *pguid);
typedef void (__stdcall * PFNCoTaskMemFree)(LPVOID pv);
typedef HRESULT (__stdcall * PFNStringFromCLSID)(REFCLSID rclsid,LPOLESTR *lplpsz);
#endif

#ifdef WINHTTPAPI
typedef BOOL (__stdcall * PFNWinHttpCrackUrl) (
LPCWSTR pwszUrl,
DWORD dwUrlLength,
DWORD dwFlags,
LPURL_COMPONENTS lpUrlComponents
);

typedef HINTERNET (__stdcall * PFNWinHttpOpen) (
LPCWSTR pszAgentW,
DWORD dwAccessType,
LPCWSTR pszProxyW,
LPCWSTR pszProxyBypassW,
DWORD dwFlags
);

typedef BOOL (__stdcall * PFNWinHttpCloseHandle) (
HINTERNET hInternet
);

typedef HINTERNET (__stdcall * PFNWinHttpConnect) (
HINTERNET hSession,
LPCWSTR pswzServerName,
INTERNET_PORT nServerPort,
DWORD dwReserved
);

typedef BOOL (__stdcall * PFNWinHttpReadData) (
HINTERNET hRequest,
LPVOID lpBuffer,
DWORD dwNumberOfBytesToRead,
LPDWORD lpdwNumberOfBytesRead
);

typedef BOOL (__stdcall * PFNWinHttpSetOption) (
HINTERNET hInternet,
DWORD dwOption,
LPVOID lpBuffer,
DWORD dwBufferLength
);

typedef HINTERNET (__stdcall * PFNWinHttpOpenRequest) (
HINTERNET hConnect,
LPCWSTR pwszVerb,
LPCWSTR pwszObjectName,
LPCWSTR pwszVersion,
LPCWSTR pwszReferrer OPTIONAL,
LPCWSTR FAR * ppwszAcceptTypes,
DWORD dwFlags
);

typedef BOOL (__stdcall * PFNWinHttpAddRequestHeaders) (
HINTERNET hRequest,
LPCWSTR lpszHeaders,
DWORD dwHeadersLength,
DWORD dwModifiers
);

typedef BOOL (__stdcall * PFNWinHttpSendRequest) (
HINTERNET hRequest,
LPCWSTR lpszHeaders,
DWORD dwHeadersLength,
LPVOID lpOptional,
DWORD dwOptionalLength,
DWORD dwTotalLength,
DWORD_PTR dwContext
);

typedef BOOL (__stdcall * PFNWinHttpReceiveResponse) (
HINTERNET hRequest,
LPVOID lpReserved
);

typedef BOOL (__stdcall * PFNWinHttpQueryHeaders) (
 HINTERNET hRequest,
 DWORD dwInfoLevel,
 LPCWSTR   pwszName,
 LPVOID lpBuffer,
 LPDWORD   lpdwBufferLength,
 LPDWORD   lpdwIndex
);

typedef BOOL (__stdcall * PFNWinHttpGetProxyForUrl) (
    HINTERNET                   hSession,
    LPCWSTR                     lpcwszUrl,
    WINHTTP_AUTOPROXY_OPTIONS * pAutoProxyOptions,
    WINHTTP_PROXY_INFO *        pProxyInfo
);
#endif
