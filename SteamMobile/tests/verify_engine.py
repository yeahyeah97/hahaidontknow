#!/usr/bin/env python3
"""SM-001 host verification: real DXMT header compiles and recursive locking works."""
import argparse
import subprocess
import tempfile
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("--dxmt", required=True, type=Path)
ap.add_argument("--madeira", required=True, type=Path)
args = ap.parse_args()

dxmt_header = args.dxmt / "src/d3d9/d3d9_multithread.hpp"
ios_bridge = args.madeira / "app/Madeira/Winios/Winios.m"
header = dxmt_header.read_text()
bridge = ios_bridge.read_text()
assert "Steam Mobile SM-001: owner recursion" in header
assert "std::memory_order_relaxed" in header
assert "std::memory_order_acquire" in header
assert "Steam Mobile SM-001: bounded FIFO drain" in bridge
assert 'getenv("MADEIRA_INPUT_TRACE")' in bridge
assert "winios_input_event_t batch[64]" in bridge

with tempfile.TemporaryDirectory() as tmp:
    d = Path(tmp)
    (d / "log").mkdir()
    (d / "windows.h").write_text("""#pragma once
#include <cstdint>
#include <atomic>
#include <thread>
inline uint32_t GetCurrentThreadId() {
  static std::atomic<uint32_t> next{1};
  static thread_local uint32_t id=next.fetch_add(1);
  return id;
}
inline void YieldProcessor() { std::this_thread::yield(); }
inline void SwitchToThread() { std::this_thread::yield(); }
""")
    (d / "log/log.hpp").write_text("""#pragma once
namespace dxmt { struct Logger { template<typename T> static void warn(T&&) {} }; }
""")
    (d / "util_env.hpp").write_text("""#pragma once
#include <string>
namespace dxmt::env { inline std::string getEnvVar(const char *) { return ""; } }
""")
    (d / "util_string.hpp").write_text("""#pragma once
#include <string>
namespace dxmt::str { template<typename... T> std::string format(T&&...) { return ""; } }
""")
    (d / "util_madeira_compat.h").write_text("#pragma once\n")
    (d / "test.cpp").write_text("""#include "d3d9_multithread.hpp"
#include <cassert>
#include <thread>
#include <vector>
#include <iostream>
int main() {
  dxmt::D9RecursiveSpinlock lock;
  int shared = 0;
  lock.lock(); assert(lock.try_lock()); lock.unlock(); lock.unlock();
  auto work=[&](){ for(int i=0;i<10000;i++) {
    lock.lock(); lock.lock(); shared++; lock.unlock(); lock.unlock();
  }};
  std::vector<std::thread> threads;
  for (int i=0;i<4;i++) threads.emplace_back(work);
  for(auto &t:threads)t.join();
  assert(shared==40000);
  std::cout<<"D3D9 recursive lock PASS: "<<shared<<"\\n";
}
""")
    cmd = ["c++", "-std=c++17", "-O2", "-pthread", "-DDXMT_MADEIRA",
           "-I",str(d),"-I",str(dxmt_header.parent),str(d/"test.cpp"),
           "-o",str(d/"d9-lock-test")]
    subprocess.run(cmd,check=True)
    subprocess.run([str(d/"d9-lock-test")],check=True,timeout=20)
print("SM-001 patched DXMT and Winios source verification PASS")
