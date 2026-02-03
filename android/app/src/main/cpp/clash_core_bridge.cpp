#include <jni.h>

#include <android/log.h>
#include <dlfcn.h>

#include <cstdlib>
#include <cstring>
#include <mutex>

namespace {

// Android JNI 桥接库：负责在宿主侧加载核心 so，并注入回调函数指针。
// 该层只做通信与资源管理，不承载业务逻辑。

constexpr const char* kLogTag = "clash_core";

void logError(const char* msg) {
  __android_log_print(ANDROID_LOG_ERROR, kLogTag, "%s", msg);
}

void logInfo(const char* msg) {
  __android_log_print(ANDROID_LOG_INFO, kLogTag, "%s", msg);
}

void logMissingSymbol(const char* name) {
  __android_log_print(ANDROID_LOG_ERROR, kLogTag, "缺失符号: %s", name);
}

JavaVM* g_vm = nullptr;

jmethodID g_vpn_protect_method = nullptr;
jmethodID g_result_callback_method = nullptr;

struct ScopedEnv {
  JNIEnv* env = nullptr;
  bool need_detach = false;

  ScopedEnv() {
    if (g_vm == nullptr) {
      return;
    }

    void* raw_env = nullptr;
    const jint get_env_res = g_vm->GetEnv(&raw_env, JNI_VERSION_1_6);
    if (get_env_res == JNI_OK) {
      env = static_cast<JNIEnv*>(raw_env);
      need_detach = false;
      return;
    }

    if (get_env_res != JNI_EDETACHED) {
      return;
    }

    JNIEnv* attached_env = nullptr;
    if (g_vm->AttachCurrentThread(&attached_env, nullptr) != JNI_OK) {
      return;
    }
    env = attached_env;
    need_detach = true;
  }

  ~ScopedEnv() {
    if (need_detach && g_vm != nullptr) {
      g_vm->DetachCurrentThread();
    }
  }
};

void clearJniException(JNIEnv* env) {
  if (env == nullptr) {
    return;
  }
  if (!env->ExceptionCheck()) {
    return;
  }
  env->ExceptionDescribe();
  env->ExceptionClear();
}

jstring newJString(JNIEnv* env, const char* utf8) {
  if (env == nullptr) {
    return nullptr;
  }
  if (utf8 == nullptr) {
    return nullptr;
  }
  return env->NewStringUTF(utf8);
}

char* copyJStringToMalloc(JNIEnv* env, jstring value) {
  if (env == nullptr || value == nullptr) {
    return nullptr;
  }
  const char* utf = env->GetStringUTFChars(value, nullptr);
  if (utf == nullptr) {
    return nullptr;
  }
  const size_t len = std::strlen(utf);
  auto* out = static_cast<char*>(std::malloc(len + 1));
  if (out == nullptr) {
    env->ReleaseStringUTFChars(value, utf);
    return nullptr;
  }
  std::memcpy(out, utf, len);
  out[len] = '\0';
  env->ReleaseStringUTFChars(value, utf);
  // 该内存由核心侧通过 free_string_func 释放。
  return out;
}

void throwIllegalState(JNIEnv* env, const char* msg) {
  if (env == nullptr) {
    return;
  }
  jclass cls = env->FindClass("java/lang/IllegalStateException");
  if (cls == nullptr) {
    clearJniException(env);
    return;
  }
  env->ThrowNew(cls, msg);
}

using start_tun_fn = bool (*)(void*, int, char*, char*, char*);
using stop_tun_fn = void (*)();
using invoke_action_fn = void (*)(void*, char*);
using set_event_listener_fn = void (*)(void*);
using suspend_fn = void (*)(bool);
using force_gc_fn = void (*)();
using update_dns_fn = void (*)(char*);
using get_traffic_fn = char* (*)(bool);
using get_total_traffic_fn = char* (*)(bool);

struct CoreSymbols {
  void* handle = nullptr;
  start_tun_fn start_tun = nullptr;
  stop_tun_fn stop_tun = nullptr;
  invoke_action_fn invoke_action = nullptr;
  set_event_listener_fn set_event_listener = nullptr;
  suspend_fn suspend_core = nullptr;
  force_gc_fn force_gc = nullptr;
  update_dns_fn update_dns = nullptr;
  get_traffic_fn get_traffic = nullptr;
  get_total_traffic_fn get_total_traffic = nullptr;

  void (**release_object_func)(void*) = nullptr;
  void (**free_string_func)(char*) = nullptr;
  void (**protect_socket_func)(void*, int) = nullptr;
  void (**result_func)(void*, const char*) = nullptr;
};

CoreSymbols g_core;
std::mutex g_core_mu;

template <typename T>
T loadSymbol(void* handle, const char* name) {
  return reinterpret_cast<T>(dlsym(handle, name));
}

bool ensureCoreLoaded(JNIEnv* env, const char* core_path) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  if (g_core.handle != nullptr) {
    return true;
  }

  if (core_path == nullptr || core_path[0] == '\0') {
    throwIllegalState(env, "核心路径为空");
    return false;
  }

  __android_log_print(ANDROID_LOG_INFO, kLogTag, "正在加载核心库: %s",
                      core_path);

  void* handle = dlopen(core_path, RTLD_NOW | RTLD_GLOBAL);
  if (handle == nullptr) {
    const char* err = dlerror();
    logError(err != nullptr ? err : "dlopen 失败");
    throwIllegalState(env, "打开核心库失败");
    return false;
  }

  g_core.handle = handle;
  g_core.start_tun = loadSymbol<start_tun_fn>(handle, "startTUN");
  g_core.stop_tun = loadSymbol<stop_tun_fn>(handle, "stopTun");
  g_core.invoke_action = loadSymbol<invoke_action_fn>(handle, "invokeAction");
  g_core.set_event_listener =
      loadSymbol<set_event_listener_fn>(handle, "setEventListener");
  g_core.suspend_core = loadSymbol<suspend_fn>(handle, "suspend");
  g_core.force_gc = loadSymbol<force_gc_fn>(handle, "forceGC");
  g_core.update_dns = loadSymbol<update_dns_fn>(handle, "updateDns");
  g_core.get_traffic = loadSymbol<get_traffic_fn>(handle, "getTraffic");
  g_core.get_total_traffic =
      loadSymbol<get_total_traffic_fn>(handle, "getTotalTraffic");

  g_core.release_object_func =
      loadSymbol<void (**)(void*)>(handle, "release_object_func");
  g_core.free_string_func =
      loadSymbol<void (**)(char*)>(handle, "free_string_func");
  g_core.protect_socket_func =
      loadSymbol<void (**)(void*, int)>(handle, "protect_socket_func");
  g_core.result_func =
      loadSymbol<void (**)(void*, const char*)>(handle, "result_func");

  const bool ok = g_core.start_tun != nullptr && g_core.stop_tun != nullptr &&
                  g_core.invoke_action != nullptr &&
                  g_core.set_event_listener != nullptr &&
                  g_core.suspend_core != nullptr && g_core.force_gc != nullptr &&
                  g_core.update_dns != nullptr && g_core.get_traffic != nullptr &&
                  g_core.get_total_traffic != nullptr &&
                  g_core.release_object_func != nullptr &&
                  g_core.free_string_func != nullptr &&
                  g_core.protect_socket_func != nullptr &&
                  g_core.result_func != nullptr;

  if (!ok) {
    if (g_core.start_tun == nullptr) {
      logMissingSymbol("startTUN");
    }
    if (g_core.stop_tun == nullptr) {
      logMissingSymbol("stopTun");
    }
    if (g_core.invoke_action == nullptr) {
      logMissingSymbol("invokeAction");
    }
    if (g_core.set_event_listener == nullptr) {
      logMissingSymbol("setEventListener");
    }
    if (g_core.suspend_core == nullptr) {
      logMissingSymbol("suspend");
    }
    if (g_core.force_gc == nullptr) {
      logMissingSymbol("forceGC");
    }
    if (g_core.update_dns == nullptr) {
      logMissingSymbol("updateDns");
    }
    if (g_core.get_traffic == nullptr) {
      logMissingSymbol("getTraffic");
    }
    if (g_core.get_total_traffic == nullptr) {
      logMissingSymbol("getTotalTraffic");
    }
    if (g_core.release_object_func == nullptr) {
      logMissingSymbol("release_object_func");
    }
    if (g_core.free_string_func == nullptr) {
      logMissingSymbol("free_string_func");
    }
    if (g_core.protect_socket_func == nullptr) {
      logMissingSymbol("protect_socket_func");
    }
    if (g_core.result_func == nullptr) {
      logMissingSymbol("result_func");
    }
    logError("缺失必需符号");
    throwIllegalState(env, "核心库缺失必需符号");
    return false;
  }

  logInfo("核心库已加载");
  return true;
}

void releaseObjectImpl(void* obj) {
  if (obj == nullptr) {
    return;
  }
  ScopedEnv scoped;
  if (scoped.env == nullptr) {
    return;
  }
  scoped.env->DeleteGlobalRef(static_cast<jobject>(obj));
  clearJniException(scoped.env);
}

void freeStringImpl(char* data) {
  std::free(data);
}

void protectSocketImpl(void* tun_ctx, int fd) {
  if (tun_ctx == nullptr) {
    return;
  }
  ScopedEnv scoped;
  if (scoped.env == nullptr || g_vpn_protect_method == nullptr) {
    return;
  }

  scoped.env->CallBooleanMethod(static_cast<jobject>(tun_ctx),
                                g_vpn_protect_method, fd);
  clearJniException(scoped.env);
}

void resultImpl(void* callback, const char* data) {
  if (callback == nullptr) {
    return;
  }
  ScopedEnv scoped;
  if (scoped.env == nullptr || g_result_callback_method == nullptr) {
    return;
  }

  jstring j_data = newJString(scoped.env, data != nullptr ? data : "");
  scoped.env->CallVoidMethod(static_cast<jobject>(callback),
                             g_result_callback_method, j_data);
  clearJniException(scoped.env);
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  g_vm = vm;

  JNIEnv* env = nullptr;
  if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
    return JNI_ERR;
  }

  jclass vpn_cls = env->FindClass("android/net/VpnService");
  if (vpn_cls == nullptr) {
    clearJniException(env);
    return JNI_ERR;
  }
  g_vpn_protect_method = env->GetMethodID(vpn_cls, "protect", "(I)Z");

  jclass cb_cls =
      env->FindClass("io/github/stelliberty/android/clash_core/ClashCoreResultCallback");
  if (cb_cls == nullptr) {
    clearJniException(env);
    return JNI_ERR;
  }
  g_result_callback_method =
      env->GetMethodID(cb_cls, "onResult", "(Ljava/lang/String;)V");

  if (g_vpn_protect_method == nullptr || g_result_callback_method == nullptr) {
    clearJniException(env);
    return JNI_ERR;
  }

  return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT void JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeInit(
    JNIEnv* env,
    jobject /*thiz*/,
    jstring corePath) {
  if (corePath == nullptr) {
    throwIllegalState(env, "核心路径为空");
    return;
  }

  const char* path = env->GetStringUTFChars(corePath, nullptr);
  if (path == nullptr) {
    throwIllegalState(env, "获取字符串失败");
    return;
  }

  const bool loaded = ensureCoreLoaded(env, path);
  env->ReleaseStringUTFChars(corePath, path);

  if (!loaded) {
    return;
  }

  // 把宿主侧实现的回调函数指针注入到核心 so。
  *g_core.release_object_func = &releaseObjectImpl;
  *g_core.free_string_func = &freeStringImpl;
  *g_core.protect_socket_func = &protectSocketImpl;
  *g_core.result_func = &resultImpl;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeStartTun(
    JNIEnv* env,
    jobject /*thiz*/,
    jint fd,
    jobject vpnService,
    jstring stack,
    jstring address,
    jstring dns) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  logInfo("调用 nativeStartTun");

  if (g_core.handle == nullptr || g_core.start_tun == nullptr) {
    logError("核心未初始化");
    throwIllegalState(env, "核心未初始化");
    return JNI_FALSE;
  }
  if (vpnService == nullptr) {
    logError("VPN 服务为空");
    throwIllegalState(env, "VPN 服务为空");
    return JNI_FALSE;
  }

  jobject vpn_global = env->NewGlobalRef(vpnService);
  if (vpn_global == nullptr) {
    logError("创建全局引用失败");
    throwIllegalState(env, "创建全局引用失败");
    return JNI_FALSE;
  }

  char* stack_c = copyJStringToMalloc(env, stack);
  char* address_c = copyJStringToMalloc(env, address);
  char* dns_c = copyJStringToMalloc(env, dns);

  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "调用 start_tun: fd=%d stack=%s address=%s dns=%s",
                      fd, stack_c ? stack_c : "null",
                      address_c ? address_c : "null",
                      dns_c ? dns_c : "null");

  // vpn_global 由核心持有，核心会在 stopTun 时回调 release_object_func 释放
  const bool ok = g_core.start_tun(vpn_global, fd, stack_c, address_c, dns_c);

  __android_log_print(ok ? ANDROID_LOG_INFO : ANDROID_LOG_ERROR, kLogTag,
                      "start_tun 返回: %s", ok ? "true" : "false");

  return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeStopTun(
    JNIEnv* env,
    jobject /*thiz*/) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  if (g_core.handle == nullptr || g_core.stop_tun == nullptr) {
    throwIllegalState(env, "核心未初始化");
    return;
  }
  g_core.stop_tun();
}

extern "C" JNIEXPORT void JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeInvokeAction(
    JNIEnv* env,
    jobject /*thiz*/,
    jstring data,
    jobject cb) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  if (g_core.handle == nullptr || g_core.invoke_action == nullptr) {
    throwIllegalState(env, "核心未初始化");
    return;
  }
  if (data == nullptr) {
    throwIllegalState(env, "数据为空");
    return;
  }
  if (cb == nullptr) {
    throwIllegalState(env, "回调为空");
    return;
  }

  jobject cb_global = env->NewGlobalRef(cb);
  if (cb_global == nullptr) {
    throwIllegalState(env, "创建全局引用失败");
    return;
  }

  char* data_c = copyJStringToMalloc(env, data);
  g_core.invoke_action(cb_global, data_c);
}

extern "C" JNIEXPORT void JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeSetEventListener(
    JNIEnv* env,
    jobject /*thiz*/,
    jobject cb) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  if (g_core.handle == nullptr || g_core.set_event_listener == nullptr) {
    throwIllegalState(env, "核心未初始化");
    return;
  }

  if (cb == nullptr) {
    g_core.set_event_listener(nullptr);
    return;
  }

  jobject cb_global = env->NewGlobalRef(cb);
  if (cb_global == nullptr) {
    throwIllegalState(env, "创建全局引用失败");
    return;
  }

  g_core.set_event_listener(cb_global);
}

extern "C" JNIEXPORT void JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeSuspend(
    JNIEnv* env,
    jobject /*thiz*/,
    jboolean suspended) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  if (g_core.handle == nullptr || g_core.suspend_core == nullptr) {
    throwIllegalState(env, "核心未初始化");
    return;
  }
  g_core.suspend_core(suspended == JNI_TRUE);
}

extern "C" JNIEXPORT void JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeForceGc(
    JNIEnv* env,
    jobject /*thiz*/) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  if (g_core.handle == nullptr || g_core.force_gc == nullptr) {
    throwIllegalState(env, "核心未初始化");
    return;
  }
  g_core.force_gc();
}

extern "C" JNIEXPORT void JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeUpdateDns(
    JNIEnv* env,
    jobject /*thiz*/,
    jstring dns) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  if (g_core.handle == nullptr || g_core.update_dns == nullptr) {
    throwIllegalState(env, "核心未初始化");
    return;
  }
  if (dns == nullptr) {
    throwIllegalState(env, "DNS 为空");
    return;
  }

  char* dns_c = copyJStringToMalloc(env, dns);
  g_core.update_dns(dns_c);
}

extern "C" JNIEXPORT jstring JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeGetTraffic(
    JNIEnv* env,
    jobject /*thiz*/,
    jboolean onlyStatisticsProxy) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  if (g_core.handle == nullptr || g_core.get_traffic == nullptr) {
    throwIllegalState(env, "核心未初始化");
    return nullptr;
  }

  char* res = g_core.get_traffic(onlyStatisticsProxy == JNI_TRUE);
  jstring out = newJString(env, res != nullptr ? res : "");
  std::free(res);
  return out;
}

extern "C" JNIEXPORT jstring JNICALL
Java_io_github_stelliberty_android_clash_1core_ClashCoreBridge_nativeGetTotalTraffic(
    JNIEnv* env,
    jobject /*thiz*/,
    jboolean onlyStatisticsProxy) {
  std::lock_guard<std::mutex> lock(g_core_mu);
  if (g_core.handle == nullptr || g_core.get_total_traffic == nullptr) {
    throwIllegalState(env, "核心未初始化");
    return nullptr;
  }

  char* res = g_core.get_total_traffic(onlyStatisticsProxy == JNI_TRUE);
  jstring out = newJString(env, res != nullptr ? res : "");
  std::free(res);
  return out;
}
