#include "emote_visibility.cpp"
#include <cassert>
struct Var
{
    alignas(8) unsigned char memory[0x90]{};
    char text[2048]{};
};
static Var request, url, accepted, key, session, state;
static void Init(Var &v, const char *s)
{
    *reinterpret_cast<void **>(v.memory + 0x38) = v.memory;
    *reinterpret_cast<char **>(v.memory + 0x48) = v.text;
    *reinterpret_cast<int64_t *>(v.memory + 0x50) = sizeof(v.text);
    strcpy(v.text, s);
}
static void *Find(void *, const char *n)
{
    if (!strcmp(n, "em_auth_request"))
        return request.memory;
    if (!strcmp(n, "em_url"))
        return url.memory;
    if (!strcmp(n, "em_auth_allowed_url"))
        return accepted.memory;
    if (!strcmp(n, "emkey"))
        return key.memory;
    if (!strcmp(n, "em_auth_session"))
        return session.memory;
    if (!strcmp(n, "em_auth_state"))
        return state.memory;
    return nullptr;
}
int main()
{
    void *vtable[16]{};
    vtable[15] = reinterpret_cast<void *>(&Find);
    void **object = vtable;
    consoleVariables = &object;
    Init(request, "123:one");
    Init(url, "https://relay.example.test");
    Init(accepted, "");
    Init(key, "public-key-at-least-24-chars");
    Init(session, "old-session");
    Init(state, "0000");
    EmoteAuth::Tick();
    assert(!EmoteAuth::running);
    assert(session.text[0] == 0);
    assert(*reinterpret_cast<int *>(state.memory + 0x5c) == 5);
    assert(EmoteAuth::JsonEscape("a\"b\\c") == "a\\\"b\\\\c");
    assert(EmoteAuth::JsonEscape("bad\ncode").empty());
    assert(EmoteAuth::Exchange("http://relay.example.test", key.text, "123", "not-a-real-code").empty());
    assert(
        EmoteAuth::Exchange("https://user@relay.example.test", key.text, "123", "not-a-real-code").empty());
    auto callback = std::make_shared<EmoteAuth::CodeRequest>();
    auto context = new std::shared_ptr<EmoteAuth::CodeRequest>(callback);
    const char *code = "test-code-only";
    EmoteAuth::ReceiveCode(context, &code, strlen(code), 0);
    assert(callback->done && callback->code == code);
    auto failed = std::make_shared<EmoteAuth::CodeRequest>();
    EmoteAuth::ReceiveCode(new std::shared_ptr<EmoteAuth::CodeRequest>(failed), &code, strlen(code), 1);
    assert(failed->done && failed->code.empty());
    EmoteAuth::WriteSession(std::string(64, 'a'));
    assert(strlen(session.text) == 64);
    EmoteAuth::WriteSession({});
    assert(session.text[0] == 0);
    puts("Auth native tests passed: consent required, HTTP/userinfo refused, JSON escaping, callback errors, "
         "session clearing. No EA/network calls made.");
}
