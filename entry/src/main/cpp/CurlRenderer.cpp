#include <ace/xcomponent/native_interface_xcomponent.h>
#include <napi/native_api.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <native_vsync/native_vsync.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <hilog/log.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>
#include "CurlGeometry.h"
#include "CurlShaders.h"

namespace {
constexpr size_t MAX_TEXTURE_PIXELS = 4194304;
constexpr size_t MAX_TEXTURE_BYTES = 33554432;
constexpr size_t MAX_CACHE_BYTES = 100663296;
struct Texture { GLuint id = 0; size_t bytes = 0; };
struct Upload {
    std::string key;
    uint32_t width = 0, height = 0;
    std::vector<uint8_t> pixels;
    std::mutex mutex;
    std::condition_variable signal;
    bool done = false, ok = false;
    void Finish(bool value) {
        { std::lock_guard<std::mutex> lock(mutex); ok = value; done = true; }
        signal.notify_all();
    }
};
struct Frame {
    std::string front, behind;
    float progress = 0, corner = 1, fingerY = 1, velocity = 0, margin = 0.025f;
    bool reverse = false, book = false, visible = false;
    uint64_t sequence = 0;
};
class Renderer {
public:
    Renderer(void* nativeWindow, uint64_t w, uint64_t h) : window(nativeWindow), width(w), height(h) {
        worker = std::thread([this]() { Run(); });
    }
    ~Renderer() { Stop(); }
    void Stop() {
        { std::lock_guard<std::mutex> lock(mutex); alive = false; tick = true; }
        wake.notify_all();
        if (worker.joinable()) { worker.join(); }
    }
    void Resize(uint64_t w, uint64_t h) {
        std::lock_guard<std::mutex> lock(mutex); width = w; height = h; dirty = true; wake.notify_all();
    }
    bool Cache(const std::shared_ptr<Upload>& job) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            if (!alive || failed || allowed.count(job->key) == 0) { return false; }
            uploads.push_back(job); dirty = true;
        }
        wake.notify_all();
        std::unique_lock<std::mutex> lock(job->mutex);
        return job->signal.wait_for(lock,std::chrono::seconds(5),[&]() { return job->done; }) && job->ok;
    }
    void Retain(const std::string& text) {
        std::lock_guard<std::mutex> lock(mutex);
        allowed.clear(); size_t start = 0;
        while (start < text.size()) {
            size_t end = text.find('|',start);
            allowed.insert(text.substr(start,end == std::string::npos ? end : end-start));
            if (end == std::string::npos) { break; } start = end+1;
        }
        dirty = true; wake.notify_all();
    }
    uint64_t Present(Frame next) {
        std::lock_guard<std::mutex> lock(mutex);
        if (!alive || failed || resident.count(next.front) == 0 || resident.count(next.behind) == 0) { return 0; }
        next.visible = true; next.sequence = ++submitted; frame = next; dirty = true; wake.notify_all();
        return submitted;
    }
    void Clear() {
        std::lock_guard<std::mutex> lock(mutex); frame.visible = false; dirty = true; wake.notify_all();
    }
    uint64_t Presented() const { return presented.load(); }
    std::string Metrics() {
        std::lock_guard<std::mutex> lock(mutex);
        return std::string(failed ? "failed" : "ok") + ";frames=" + std::to_string(frames) +
            ";mesh=" + std::to_string(columns) + "x" + std::to_string(rows) +
            ";gpuBytes=" + std::to_string(cacheBytes) + ";slowDraws=" + std::to_string(slowDraws);
    }
private:
    void* window;
    uint64_t width, height;
    std::mutex mutex;
    std::condition_variable wake;
    std::thread worker;
    bool alive = true, failed = false, dirty = false, tick = false;
    Frame frame;
    std::deque<std::shared_ptr<Upload>> uploads;
    std::set<std::string> allowed, resident;
    std::unordered_map<std::string,Texture> textures;
    std::atomic<uint64_t> presented {0};
    uint64_t submitted = 0, frames = 0, slowDraws = 0;
    size_t cacheBytes = 0;
    int columns = 160, rows = 96, indexCount = 0;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    GLuint program = 0, vao = 0, vbo = 0, ebo = 0;
    OH_NativeVSync* vsync = nullptr;
    static void Vsync(long long, void* data) {
        auto* self = static_cast<Renderer*>(data);
        { std::lock_guard<std::mutex> lock(self->mutex); self->tick = true; }
        self->wake.notify_all();
    }
    GLuint Shader(GLenum type, const char* source) {
        GLuint shader = glCreateShader(type); glShaderSource(shader,1,&source,nullptr); glCompileShader(shader);
        GLint ok = GL_FALSE; glGetShaderiv(shader,GL_COMPILE_STATUS,&ok);
        if (!ok) { glDeleteShader(shader); return 0; } return shader;
    }
    bool Initialize() {
        display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display == EGL_NO_DISPLAY || !eglInitialize(display,nullptr,nullptr)) { return false; }
        EGLint attrs[] = {EGL_SURFACE_TYPE,EGL_WINDOW_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT,
            EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_DEPTH_SIZE,16,EGL_NONE};
        EGLConfig config; EGLint count = 0;
        if (!eglChooseConfig(display,attrs,&config,1,&count) || !count) { return false; }
        EGLint contextAttrs[] = {EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE};
        context = eglCreateContext(display,config,EGL_NO_CONTEXT,contextAttrs);
        surface = eglCreateWindowSurface(display,config,reinterpret_cast<EGLNativeWindowType>(window),nullptr);
        if (context == EGL_NO_CONTEXT || surface == EGL_NO_SURFACE || !eglMakeCurrent(display,surface,surface,context)) { return false; }
        eglSwapInterval(display,1);
        GLuint vertex = Shader(GL_VERTEX_SHADER,CurlShaders::Vertex);
        GLuint fragment = Shader(GL_FRAGMENT_SHADER,CurlShaders::Fragment);
        if (!vertex || !fragment) { if (vertex) glDeleteShader(vertex); if (fragment) glDeleteShader(fragment); return false; }
        program = glCreateProgram(); glAttachShader(program,vertex); glAttachShader(program,fragment); glLinkProgram(program);
        glDeleteShader(vertex); glDeleteShader(fragment);
        GLint linked = GL_FALSE; glGetProgramiv(program,GL_LINK_STATUS,&linked);
        if (!linked) { return false; }
        Mesh(); glDisable(GL_CULL_FACE); glEnable(GL_DEPTH_TEST); glDepthFunc(GL_LEQUAL);
        glUseProgram(program); glUniform1i(glGetUniformLocation(program,"uFront"),0); glUniform1i(glGetUniformLocation(program,"uBehind"),1);
        vsync = OH_NativeVSync_Create("manga-curl",10);
        if (!vsync) { return false; }
        OH_NativeVSync_ExpectedRateRange range {60,120,120};
        OH_NativeVSync_SetExpectedFrameRateRange(vsync,&range);
        return true;
    }
    void Mesh() {
        std::vector<float> vertices; vertices.reserve((columns+1)*(rows+1)*2);
        std::vector<uint16_t> indices; indices.reserve(columns*rows*6);
        for (int y=0;y<=rows;y++) for (int x=0;x<=columns;x++) {
            vertices.push_back(static_cast<float>(x)/columns); vertices.push_back(static_cast<float>(y)/rows);
        }
        for (int y=0;y<rows;y++) for (int x=0;x<columns;x++) {
            uint16_t a=y*(columns+1)+x,b=a+1,c=a+columns+1,d=c+1;
            indices.insert(indices.end(),{a,c,b,b,c,d});
        }
        indexCount = indices.size();
        if (!vao) { glGenVertexArrays(1,&vao); glGenBuffers(1,&vbo); glGenBuffers(1,&ebo); }
        glBindVertexArray(vao); glBindBuffer(GL_ARRAY_BUFFER,vbo);
        glBufferData(GL_ARRAY_BUFFER,vertices.size()*sizeof(float),vertices.data(),GL_STATIC_DRAW);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,ebo); glBufferData(GL_ELEMENT_ARRAY_BUFFER,indices.size()*sizeof(uint16_t),indices.data(),GL_STATIC_DRAW);
        glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,2*sizeof(float),nullptr); glEnableVertexAttribArray(0);
    }
    bool UploadTexture(const std::shared_ptr<Upload>& job) {
        if (textures.count(job->key)) { return true; }
        GLint maxSize; glGetIntegerv(GL_MAX_TEXTURE_SIZE,&maxSize);
        if (job->width > static_cast<uint32_t>(maxSize) || job->height > static_cast<uint32_t>(maxSize) ||
            cacheBytes+job->pixels.size() > MAX_CACHE_BYTES) { return false; }
        GLuint texture; glGenTextures(1,&texture); glBindTexture(GL_TEXTURE_2D,texture);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
        glPixelStorei(GL_UNPACK_ALIGNMENT,1);
        glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,job->width,job->height,0,GL_RGBA,GL_UNSIGNED_BYTE,job->pixels.data());
        if (glGetError()!=GL_NO_ERROR) { glDeleteTextures(1,&texture); return false; }
        std::lock_guard<std::mutex> lock(mutex);
        if (!alive || allowed.count(job->key)==0) { glDeleteTextures(1,&texture); return false; }
        textures.emplace(job->key,Texture {texture,job->pixels.size()}); cacheBytes+=job->pixels.size();
        resident.insert(job->key); return true;
    }
    void Uniform(const char* name,float value) { glUniform1f(glGetUniformLocation(program,name),value); }
    void Draw(const Frame& state,uint64_t w,uint64_t h) {
        glViewport(0,0,w,h); glClearColor(0,0,0,0); glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
        if (!state.visible || !w || !h || !textures.count(state.front) || !textures.count(state.behind)) { return; }
        glUseProgram(program); glBindVertexArray(vao);
        glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_2D,textures.at(state.front).id);
        glActiveTexture(GL_TEXTURE1); glBindTexture(GL_TEXTURE_2D,textures.at(state.behind).id);
        const float aspect=static_cast<float>(h)/w;
        const float margin=state.book ? state.margin : 0;
        const float leaf=state.book ? 0.5f-margin : 1.0f;
        const float origin=state.book ? 0.5f : state.reverse ? 1.0f : 0.0f;
        const auto fold=CurlMakeFold(1,aspect/leaf,state.progress,state.corner,state.fingerY,state.velocity);
        glUniform2f(glGetUniformLocation(program,"uScreen"),1,aspect);
        glUniform4f(glGetUniformLocation(program,"uFold"),fold.nx,fold.ny,fold.axisX,fold.axisY);
        Uniform("uRadius",fold.radius); Uniform("uBook",state.book); Uniform("uProgress",state.progress);
        // Base quads always cover the viewport. Their own local origin is zero;
        // the fold's leaf parameters are restored before the deforming pass.
        glUniform2f(glGetUniformLocation(program,"uLeaf"),origin,leaf); Uniform("uReverse",state.reverse); Uniform("uSheet",0);
        Uniform("uBase",state.progress>=0.99999f ? 0 : state.progress<=0.00001f ? 1 : state.book ? 3 : 0);
        glDrawElements(GL_TRIANGLES,indexCount,GL_UNSIGNED_SHORT,nullptr);
        if (state.progress<=0.00001f) {
            return;
        }
        if (state.progress>=0.99999f) { return; }
        Uniform("uReverse",state.reverse); glUniform2f(glGetUniformLocation(program,"uLeaf"),origin,leaf);
        Uniform("uSheet",1); glDrawElements(GL_TRIANGLES,indexCount,GL_UNSIGNED_SHORT,nullptr);
    }
    void Run() {
        if (!Initialize()) {
            OH_LOG_Print(LOG_APP,LOG_ERROR,0xD004700,"PageCurl","EGL/shader initialization failed");
            { std::lock_guard<std::mutex> lock(mutex); failed=true; }
            Cleanup(); return;
        }
        bool waiting=false;
        while (true) {
            Frame current; uint64_t w,h; bool shouldDraw=false;
            {
                std::unique_lock<std::mutex> lock(mutex);
                wake.wait(lock,[&]() { return !alive || tick || !uploads.empty() || (dirty && !waiting); });
                if (!alive) { break; }
                for (auto it=textures.begin();it!=textures.end();) {
                    if (!allowed.count(it->first) && (!frame.visible || (it->first!=frame.front && it->first!=frame.behind))) {
                        glDeleteTextures(1,&it->second.id); cacheBytes-=it->second.bytes; resident.erase(it->first); it=textures.erase(it);
                    } else { ++it; }
                }
                while (!uploads.empty()) {
                    auto job=uploads.front(); uploads.pop_front();
                    const bool wanted=allowed.count(job->key)!=0;
                    // A large glTexImage2D must not hold the command mutex:
                    // finger updates on ArkUI's thread only publish parameters.
                    lock.unlock();
                    const bool uploaded=wanted && UploadTexture(job);
                    job->Finish(uploaded);
                    lock.lock();
                }
                if (dirty && !waiting) {
                    waiting = OH_NativeVSync_RequestFrame(vsync,Vsync,this)==0;
                    if (!waiting) { tick=true; }
                }
                if (tick) { tick=false; waiting=false; shouldDraw=dirty; dirty=false; current=frame; w=width; h=height; }
                else { continue; }
            }
            if (!shouldDraw) { continue; }
            auto started=std::chrono::steady_clock::now();
            Draw(current,w,h);
            const bool ok=eglSwapBuffers(display,surface)==EGL_TRUE;
            {
                std::lock_guard<std::mutex> lock(mutex);
                if (!ok) { failed=true; alive=false; break; }
                if (current.visible) { presented.store(current.sequence); frames++; }
                auto ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-started).count();
                if (ms>20) { slowDraws++; }
                // Reduce geometry only; texture resolution remains unchanged.
                if (slowDraws==12 && columns>96) { columns=96; rows=64; Mesh(); }
                if (slowDraws==24 && columns>64) { columns=64; rows=40; Mesh(); }
            }
        }
        { std::lock_guard<std::mutex> lock(mutex); for (auto& job:uploads) { job->Finish(false); } uploads.clear(); }
        Cleanup();
    }
    void Cleanup() {
        if (vsync) { OH_NativeVSync_Destroy(vsync); vsync=nullptr; }
        if (display!=EGL_NO_DISPLAY && context!=EGL_NO_CONTEXT) {
            for (auto& pair:textures) { glDeleteTextures(1,&pair.second.id); }
            glDeleteBuffers(1,&vbo); glDeleteBuffers(1,&ebo); glDeleteVertexArrays(1,&vao); if (program) glDeleteProgram(program);
            eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
            if (surface!=EGL_NO_SURFACE) eglDestroySurface(display,surface);
            eglDestroyContext(display,context);
        }
        // EGL_DEFAULT_DISPLAY is shared with ArkUI. Never eglTerminate it here.
    }
};
std::mutex registryMutex;
std::unordered_map<std::string,std::shared_ptr<Renderer>> registry;
std::string ComponentId(OH_NativeXComponent* component) {
    char buffer[OH_XCOMPONENT_ID_LEN_MAX+1] {}; uint64_t size=sizeof(buffer);
    return OH_NativeXComponent_GetXComponentId(component,buffer,&size)==0 ? std::string(buffer) : "";
}
std::shared_ptr<Renderer> Find(const std::string& id) {
    std::lock_guard<std::mutex> lock(registryMutex); auto it=registry.find(id); return it==registry.end() ? nullptr : it->second;
}
void Created(OH_NativeXComponent* component,void* window) {
    uint64_t w=0,h=0; OH_NativeXComponent_GetXComponentSize(component,window,&w,&h);
    auto renderer=std::make_shared<Renderer>(window,w,h);
    std::lock_guard<std::mutex> lock(registryMutex); registry[ComponentId(component)]=renderer;
}
void Changed(OH_NativeXComponent* component,void* window) {
    uint64_t w=0,h=0; OH_NativeXComponent_GetXComponentSize(component,window,&w,&h);
    auto renderer=Find(ComponentId(component)); if (renderer) renderer->Resize(w,h);
}
void Destroyed(OH_NativeXComponent* component,void*) {
    std::shared_ptr<Renderer> renderer;
    { std::lock_guard<std::mutex> lock(registryMutex); auto it=registry.find(ComponentId(component)); if(it!=registry.end()) { renderer=it->second; registry.erase(it); } }
    if (renderer) { renderer->Stop(); }
}
void Touch(OH_NativeXComponent*,void*) {}
OH_NativeXComponent_Callback callbacks {Created,Changed,Destroyed,Touch};
std::string String(napi_env env,napi_value value) {
    size_t size=0; if(napi_get_value_string_utf8(env,value,nullptr,0,&size)!=napi_ok || size>4096) return "";
    std::string result(size+1,'\0'); napi_get_value_string_utf8(env,value,result.data(),result.size(),&size); result.resize(size); return result;
}
double Number(napi_env env,napi_value value) { double v=0; napi_get_value_double(env,value,&v); return std::isfinite(v) ? v : 0; }
napi_value Bool(napi_env env,bool value) { napi_value result; napi_get_boolean(env,value,&result); return result; }
struct CacheWork {
    napi_env env; napi_async_work work=nullptr; napi_deferred deferred; napi_ref retained;
    OH_PixelmapNative* map=nullptr;
    std::shared_ptr<Renderer> renderer;
    std::shared_ptr<Upload> upload=std::make_shared<Upload>();
    bool ok=false;
};
void CacheExecute(napi_env,void* data) {
    auto* job=static_cast<CacheWork*>(data);
    OH_Pixelmap_ImageInfo* info=nullptr;
    if (OH_PixelmapImageInfo_Create(&info)!=IMAGE_SUCCESS) return;
    uint32_t stride=0; int32_t format=0;
    bool valid=OH_PixelmapNative_GetImageInfo(job->map,info)==IMAGE_SUCCESS;
    OH_PixelmapImageInfo_GetWidth(info,&job->upload->width); OH_PixelmapImageInfo_GetHeight(info,&job->upload->height);
    OH_PixelmapImageInfo_GetRowStride(info,&stride); OH_PixelmapImageInfo_GetPixelFormat(info,&format); OH_PixelmapImageInfo_Release(info);
    size_t bytes=static_cast<size_t>(stride)*job->upload->height;
    if (!valid || !job->upload->width || !job->upload->height || stride<job->upload->width*4 ||
        static_cast<size_t>(job->upload->width)*job->upload->height>MAX_TEXTURE_PIXELS ||
        bytes>MAX_TEXTURE_BYTES || (format!=PIXEL_FORMAT_RGBA_8888 && format!=PIXEL_FORMAT_BGRA_8888)) return;
    std::vector<uint8_t> source(bytes);
    if (OH_PixelmapNative_ReadPixels(job->map,source.data(),&bytes)!=IMAGE_SUCCESS) return;
    job->upload->pixels.resize(static_cast<size_t>(job->upload->width)*job->upload->height*4);
    for(uint32_t y=0;y<job->upload->height;y++) for(uint32_t x=0;x<job->upload->width;x++) {
        auto from=source.data()+y*stride+x*4; auto to=job->upload->pixels.data()+(static_cast<size_t>(y)*job->upload->width+x)*4;
        to[0]=from[format==PIXEL_FORMAT_BGRA_8888 ? 2 : 0]; to[1]=from[1]; to[2]=from[format==PIXEL_FORMAT_BGRA_8888 ? 0 : 2]; to[3]=from[3];
    }
    job->ok=job->renderer->Cache(job->upload);
}
void CacheComplete(napi_env env,napi_status,void* data) {
    auto* job=static_cast<CacheWork*>(data);
    OH_PixelmapNative_Release(job->map); napi_delete_reference(env,job->retained);
    napi_resolve_deferred(env,job->deferred,Bool(env,job->ok)); napi_delete_async_work(env,job->work); delete job;
}
napi_value Cache(napi_env env,napi_callback_info info) {
    size_t count=3; napi_value args[3]; napi_get_cb_info(env,info,&count,args,nullptr,nullptr);
    napi_deferred deferred; napi_value promise; napi_create_promise(env,&deferred,&promise);
    auto renderer=count==3 ? Find(String(env,args[0])) : nullptr;
    auto* job=new CacheWork(); job->env=env; job->deferred=deferred; job->renderer=renderer;
    if (!renderer || OH_PixelmapNative_ConvertPixelmapNativeFromNapi(env,args[2],&job->map)!=IMAGE_SUCCESS) {
        napi_resolve_deferred(env,deferred,Bool(env,false)); delete job; return promise;
    }
    job->upload->key=String(env,args[1]); napi_create_reference(env,args[2],1,&job->retained);
    napi_value name; napi_create_string_utf8(env,"curl-texture",NAPI_AUTO_LENGTH,&name);
    if (napi_create_async_work(env,nullptr,name,CacheExecute,CacheComplete,job,&job->work)!=napi_ok ||
        napi_queue_async_work(env,job->work)!=napi_ok) {
        OH_PixelmapNative_Release(job->map); napi_delete_reference(env,job->retained);
        napi_resolve_deferred(env,deferred,Bool(env,false)); if(job->work) napi_delete_async_work(env,job->work); delete job;
    }
    return promise;
}
napi_value Present(napi_env env,napi_callback_info info) {
    size_t count=10; napi_value args[10]; napi_get_cb_info(env,info,&count,args,nullptr,nullptr); uint64_t sequence=0;
    if(count==10) {
        auto renderer=Find(String(env,args[0]));
        if(renderer) {
            Frame f; f.front=String(env,args[1]); f.behind=String(env,args[2]);
            f.progress=std::clamp(Number(env,args[3]),0.0,1.0); f.corner=Number(env,args[4]); f.fingerY=Number(env,args[5]);
            f.reverse=Number(env,args[6])!=0; f.book=Number(env,args[7])!=0; f.velocity=Number(env,args[8]);
            f.margin=std::clamp(Number(env,args[9]),0.0,0.15);
            sequence=renderer->Present(f);
        }
    }
    napi_value result; napi_create_double(env,sequence,&result); return result;
}
napi_value Control(napi_env env,napi_callback_info info) {
    size_t count=2; napi_value args[2]; void* operation=nullptr; napi_get_cb_info(env,info,&count,args,nullptr,&operation);
    intptr_t op=reinterpret_cast<intptr_t>(operation);
    auto renderer=count ? Find(String(env,args[0])) : nullptr;
    if(!renderer) {
        if(op==4) { napi_value out; napi_create_string_utf8(env,"surface-unavailable",NAPI_AUTO_LENGTH,&out); return out; }
        return Bool(env,false);
    }
    if(op==1 && count==2) { renderer->Retain(String(env,args[1])); }
    if(op==2) { renderer->Clear(); }
    if(op==3) { return Bool(env,count==2 && renderer->Presented()>=Number(env,args[1])); }
    if(op==4) { napi_value out; auto value=renderer->Metrics(); napi_create_string_utf8(env,value.c_str(),value.size(),&out); return out; }
    return Bool(env,true);
}
napi_value Init(napi_env env,napi_value exports) {
    napi_property_descriptor props[]={
        {"cache",nullptr,Cache,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"present",nullptr,Present,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"retain",nullptr,Control,nullptr,nullptr,nullptr,napi_default,reinterpret_cast<void*>(1)},
        {"clear",nullptr,Control,nullptr,nullptr,nullptr,napi_default,reinterpret_cast<void*>(2)},
        {"presented",nullptr,Control,nullptr,nullptr,nullptr,napi_default,reinterpret_cast<void*>(3)},
        {"metrics",nullptr,Control,nullptr,nullptr,nullptr,napi_default,reinterpret_cast<void*>(4)}};
    napi_define_properties(env,exports,sizeof(props)/sizeof(props[0]),props);
    bool has=false; napi_has_named_property(env,exports,OH_NATIVE_XCOMPONENT_OBJ,&has);
    if(has) {
        napi_value object; napi_get_named_property(env,exports,OH_NATIVE_XCOMPONENT_OBJ,&object);
        OH_NativeXComponent* component=nullptr; napi_unwrap(env,object,reinterpret_cast<void**>(&component));
        if(component) OH_NativeXComponent_RegisterCallback(component,&callbacks);
    }
    return exports;
}
}
static napi_module module={1,0,nullptr,Init,"pagecurl",nullptr,{0}};
extern "C" __attribute__((constructor)) void RegisterPageCurl() { napi_module_register(&module); }
