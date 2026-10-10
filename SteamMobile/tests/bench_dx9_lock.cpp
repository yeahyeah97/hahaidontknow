// Steam Mobile SM-001 synthetic host microbenchmark.
// This does NOT measure iPhone FPS or DXMT's real workload; only atomic lock overhead.
#include <atomic>
#include <thread>
#include <chrono>
#include <cstdint>
#include <initializer_list>
#include <cstdio>
using Clock = std::chrono::steady_clock;
static uint32_t thread_id() {
    static std::atomic<uint32_t> next{1};
    static thread_local uint32_t id=next.fetch_add(1);
    return id;
}
struct Original {
    std::atomic<uint32_t> owner{0};
    uint32_t recursion{0};
    bool try_lock() {
        uint32_t id=thread_id(),expected=0;
        bool ok=owner.compare_exchange_weak(expected,id,std::memory_order_acquire);
        if(ok)return true;
        if(expected!=id)return false;
        ++recursion;
        return true;
    }
    void lock(){while(!try_lock())std::this_thread::yield();}
    void unlock(){if(!recursion)owner.store(0,std::memory_order_release);else --recursion;}
};
struct SM001 {
    std::atomic<uint32_t> owner{0};
    uint32_t recursion{0};
    bool try_lock() {
        uint32_t id=thread_id();
        if(owner.load(std::memory_order_relaxed)==id) {++recursion;return true;}
        uint32_t expected=0;
        bool ok=owner.compare_exchange_weak(expected,id,std::memory_order_acquire);
        if(ok)return true;
        if(expected!=id)return false;
        ++recursion; return true;
    }
    void lock(){while(!try_lock())std::this_thread::yield();}
    void unlock(){if(!recursion)owner.store(0,std::memory_order_release);else --recursion;}
};
template <typename Lock>
void bench(const char *label) {
    Lock lock;
    volatile unsigned long sink=0;
    for(int depth: {1,2,4}) {
        const int loops=3000000;
        auto start=Clock::now();
        for(int i=0;i<loops;++i) {
            for(int j=0;j<depth;++j)lock.lock();
            ++sink;
            for(int j=0;j<depth;++j)lock.unlock();
        }
        auto seconds=std::chrono::duration<double>(Clock::now()-start).count();
        std::printf("%s depth=%d ns/iteration=%.3f\n",label,depth,seconds*1e9/loops);
    }
}
int main(){bench<Original>("original");bench<SM001>("SM001");bench<SM001>("SM001");bench<Original>("original");}
