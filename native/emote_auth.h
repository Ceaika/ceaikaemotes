// fresh EA code in, emote session out. dont log the code.
#pragma once
#include <winhttp.h>
#include <string>
#include <memory>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <atomic>
#include <chrono>
#include <regex>
namespace EmoteAuth
{
// these values are read by the client script too.
enum AuthState
{
    Idle = 0,
    Waiting = 1,
    Ready = 2,
    OriginFailed = 3,
    ExchangeFailed = 4,
    InvalidSettings = 5
};

using Callback = void (*)(void *, const char **, size_t, int);
using RequestCode = int (*)(int64_t, const char *, Callback, void *, int, const char *);
struct CodeRequest
{
    std::mutex mutex;
    std::condition_variable cv;
    bool done = false;
    std::string code;
    ~CodeRequest()
    {
        if (!code.empty())
            SecureZeroMemory(code.data(), code.size());
    }
};
static std::mutex resultMutex;
static std::string completedToken;
static int completedState = 0;
static bool resultReady = false;
static std::atomic<bool> running{false};
static unsigned generation = 0;
static std::string lastRequest;
struct InternetHandle
{
    HINTERNET value;
    explicit InternetHandle(HINTERNET v) : value(v)
    {
    }
    ~InternetHandle()
    {
        if (value)
            WinHttpCloseHandle(value);
    }
};
static void ReceiveCode(void *context, const char **code, size_t length, int error)
{
    std::unique_ptr<std::shared_ptr<CodeRequest>> owner(static_cast<std::shared_ptr<CodeRequest> *>(context));
    auto state = *owner;
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!error && code && *code && length > 0 && length <= 4096)
    {
        state->code.assign(*code, strnlen(*code, length));
    }
    state->done = true;
    state->cv.notify_one();
}
static std::string JsonEscape(const std::string &s)
{
    std::string out;
    for (unsigned char c : s)
    {
        if (c < 33 || c > 126)
            return {};
        if (c == '"' || c == '\\')
            out += '\\';
        out += char(c);
    }
    return out;
}
static std::string Exchange(const std::string &base,
                            const std::string &key,
                            const std::string &uid,
                            const std::string &code,
                            DWORD *httpStatus = nullptr)
{
    if (httpStatus)
        *httpStatus = 0;
    // the code only goes to the HTTPS address the player accepted.
    if (base.size() > 1024 || base.rfind("https://", 0) != 0 ||
        base.find_first_of("?#@\r\n") != std::string::npos)
        return {};
    std::wstring url(base.begin(), base.end());
    while (!url.empty() && url.back() == L'/')
        url.pop_back();
    url += L"/auth";
    URL_COMPONENTS parts{};
    parts.dwStructSize = sizeof(parts);
    parts.dwHostNameLength = DWORD(-1);
    parts.dwUrlPathLength = DWORD(-1);
    if (!WinHttpCrackUrl(url.c_str(), 0, 0, &parts) || parts.nScheme != INTERNET_SCHEME_HTTPS)
        return {};
    InternetHandle session(WinHttpOpen(L"CeaikaEmotes/0.3",
                                       WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                       WINHTTP_NO_PROXY_NAME,
                                       WINHTTP_NO_PROXY_BYPASS,
                                       0));
    if (!session.value)
        return {};
    WinHttpSetTimeouts(session.value, 5000, 5000, 5000, 10000);
    std::wstring host(parts.lpszHostName, parts.dwHostNameLength),
        path(parts.lpszUrlPath, parts.dwUrlPathLength);
    InternetHandle connection(WinHttpConnect(session.value, host.c_str(), parts.nPort, 0));
    if (!connection.value)
        return {};
    InternetHandle request(WinHttpOpenRequest(connection.value,
                                              L"POST",
                                              path.c_str(),
                                              nullptr,
                                              WINHTTP_NO_REFERER,
                                              WINHTTP_DEFAULT_ACCEPT_TYPES,
                                              WINHTTP_FLAG_SECURE));
    if (!request.value)
        return {};
    DWORD policy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    if (!WinHttpSetOption(request.value, WINHTTP_OPTION_REDIRECT_POLICY, &policy, sizeof(policy)))
        return {};
    std::string escaped = JsonEscape(code);
    if (escaped.empty())
        return {};
    std::string body = "{\"uid\":\"" + uid + "\",\"code\":\"" + escaped + "\"}";
    std::wstring headers = L"Content-Type: application/json\r\nAuthorization: Bearer " +
                           std::wstring(key.begin(), key.end()) + L"\r\n";
    bool sent = WinHttpSendRequest(
        request.value, headers.c_str(), DWORD(-1), body.data(), DWORD(body.size()), DWORD(body.size()), 0);
    SecureZeroMemory(body.data(), body.size());
    SecureZeroMemory(escaped.data(), escaped.size());
    if (!sent || !WinHttpReceiveResponse(request.value, nullptr))
        return {};
    DWORD status = 0, length = sizeof(status);
    if (!WinHttpQueryHeaders(request.value,
                             WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX,
                             &status,
                             &length,
                             WINHTTP_NO_HEADER_INDEX))
        return {};
    if (httpStatus)
        *httpStatus = status;
    if (status != 200)
        return {};
    std::string reply;
    char buffer[1024];
    DWORD got = 0;
    while (WinHttpReadData(request.value, buffer, sizeof(buffer), &got) && got)
    {
        reply.append(buffer, got);
        if (reply.size() > 4096)
            return {};
    }
    std::smatch match;
    static const std::regex tokenPattern("\"token\"\\s*:\\s*\"([a-f0-9]{64})\"");
    if (!std::regex_search(reply, match, tokenPattern))
        return {};
    return match[1].str();
}
static void Start(std::string uid, std::string url, std::string key, unsigned ticket)
{
    if (running.exchange(true))
        return;
    std::thread(
        [uid, url, key, ticket]()
        {
            int status = OriginFailed;
            std::string token;
            auto module = GetModuleHandleW(L"OriginSDK.dll");
            auto getCode =
                module ? reinterpret_cast<RequestCode>(GetProcAddress(module, "OriginRequestAuthCode"))
                       : nullptr;
            if (getCode)
            {
                auto state = std::make_shared<CodeRequest>();
                auto context = new std::shared_ptr<CodeRequest>(state);
                int result = getCode(_strtoi64(uid.c_str(), nullptr, 10),
                                     "TITANFALL2-PC-SERVER",
                                     ReceiveCode,
                                     context,
                                     10000,
                                     nullptr);
                if (result)
                    delete context;
                else
                {
                    std::unique_lock<std::mutex> lock(state->mutex);
                    if (state->cv.wait_for(lock, std::chrono::seconds(12), [&] { return state->done; }) &&
                        !state->code.empty())
                    {
                        token = Exchange(url, key, uid, state->code);
                        status = token.empty() ? ExchangeFailed : Ready;
                    }
                }
            }
            {
                std::lock_guard<std::mutex> lock(resultMutex);
                // ignore a result if permission or the request changed while it ran.
                if (ticket == generation)
                {
                    completedToken = std::move(token);
                    completedState = status;
                    resultReady = true;
                }
            }
            running = false;
        })
        .detach();
}
static void WriteSession(const std::string &token)
{
    // write the buffer directly so the console never echoes the bearer.
    void *sessionVar = FindConVar("em_auth_session");
    if (!IsMemoryReadable(sessionVar, 0x40))
        return;
    void *parent = *reinterpret_cast<void **>(static_cast<char *>(sessionVar) + 0x38);
    if (!IsMemoryReadable(parent, 0x60))
        return;
    char *text = *reinterpret_cast<char **>(static_cast<char *>(parent) + 0x48);
    auto capacity = *reinterpret_cast<int64_t *>(static_cast<char *>(parent) + 0x50);
    if (capacity <= int64_t(token.size()) || capacity > 4096 || !IsMemoryReadable(text, size_t(capacity)))
        return;
    SecureZeroMemory(text, size_t(capacity));
    memcpy(text, token.c_str(), token.size());
}
static void Tick()
{
    static ULONGLONG nextCheck = 0;
    ULONGLONG now = GetTickCount64();
    if (now < nextCheck)
        return;
    nextCheck = now + 100;
    auto read = [](const char *n)
    {
        char *s = ReadConVarString(FindConVar(n));
        return s ? std::string(s, strnlen(s, 2048)) : std::string();
    };
    std::string request = read("em_auth_request");
    if (request != lastRequest)
    {
        lastRequest = request;
        {
            std::lock_guard<std::mutex> lock(resultMutex);
            ++generation;
            completedToken.clear();
            resultReady = false;
        }
        WriteSession({});
        SetDiagnosticValue("em_auth_state", Idle);
        if (running)
        {
            lastRequest = "";
            return;
        }
        if (!request.empty())
        {
            std::string url = read("em_url"), accepted = read("em_auth_allowed_url"), key = read("emkey");
            auto split = request.find(':');
            std::string uid = request.substr(0, split);
            if (url != accepted || url.rfind("https://", 0) != 0 || split == std::string::npos ||
                uid.empty() || uid.size() > 19 || uid.find_first_not_of("0123456789") != std::string::npos ||
                key.size() < 24 || key.size() > 128 ||
                key.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-") !=
                    std::string::npos)
            {
                SetDiagnosticValue("em_auth_state", InvalidSettings);
                return;
            }
            SetDiagnosticValue("em_auth_state", Waiting);
            Start(uid, url, key, generation);
        }
    }
    std::lock_guard<std::mutex> lock(resultMutex);
    if (resultReady)
    {
        WriteSession(completedToken);
        SetDiagnosticValue("em_auth_state", completedState);
        if (!completedToken.empty())
            SecureZeroMemory(completedToken.data(), completedToken.size());
        completedToken.clear();
        resultReady = false;
    }
}
} // namespace EmoteAuth
