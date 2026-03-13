# GeneralsX @build fbraz 24/02/2026
# GeneralsX @bugfix fbraz 10/03/2026 Use FetchContent for ALL platforms (macOS, Linux, Windows)
# OpenAL audio library via FetchContent (openal-soft v1.24.2)
#
# Strategy: FetchContent for ALL platforms -- no Homebrew/system detection.
# - macOS:   CoreAudio backend. Compiled natively (arm64 on Apple Silicon).
#            Apple's deprecated OpenAL.framework is avoided -- it uses <OpenAL/al.h>
#            which is incompatible with the standard <AL/al.h> used throughout the codebase.
#            Homebrew openal-soft was unreliable: Intel Homebrew (/usr/local) installs
#            x86_64-only binaries that fail to link against native arm64 builds.
# - Linux:   ALSA/PipeWire backend.
# - Windows: WASAPI backend (modern, low-latency).
#
# FetchContent_MakeAvailable is idempotent: safe to include from multiple CMakeLists.
# Callers guard with: if(NOT TARGET OpenAL::OpenAL) find_package... endif()
#
# Reference: jmarshall OpenAL implementation uses <AL/al.h> throughout.

if(SAGE_USE_OPENAL)
    message(STATUS "Configuring OpenAL Soft (v1.24.2) with FetchContent...")

    include(FetchContent)

    FetchContent_Declare(
        openal_soft
        URL "https://github.com/kcat/openal-soft/archive/refs/tags/1.24.2.tar.gz"
        URL_HASH "SHA256=7efd383d70508587fbc146e4c508771a2235a5fc8ae05bf6fe721c20a348bd7c"
    )

    # Build as a static library to match the GeneralsX vcpkg approach.
    # When OpenAL is a shared library, its ::operator new[](size_t, std::align_val_t)
    # call in FlexArray::Create resolves through the dynamic linker and interacts
    # badly with the game's custom global operator new[], causing a SIGSEGV in
    # DeviceBase::DeviceBase. Static linking uses the same allocator as the game.
    # openal-soft uses LIBTYPE (not BUILD_SHARED_LIBS) to control shared vs static.
    set(LIBTYPE                      "STATIC" CACHE STRING "Build OpenAL as static lib" FORCE)
    set(BUILD_SHARED_LIBS            OFF      CACHE BOOL   "Disable shared lib build"   FORCE)

    # Minimal build: no utilities, examples, or tests
    set(ALSOFT_INSTALL_RUNTIME_LIBS  OFF CACHE BOOL "Install runtime libs" FORCE)
    set(ALSOFT_EXAMPLES              OFF CACHE BOOL "Build examples"       FORCE)
    set(ALSOFT_TESTS                 OFF CACHE BOOL "Build tests"          FORCE)
    set(ALSOFT_UTILS                 OFF CACHE BOOL "Build utils"          FORCE)
    set(ALSOFT_NO_CONFIG_UTIL        ON  CACHE BOOL "Disable config util"  FORCE)

    if(WIN32)
        # Windows: WASAPI is the modern low-latency audio API
        set(ALSOFT_REQUIRE_WASAPI ON CACHE BOOL "Require WASAPI backend on Windows" FORCE)
    elseif(UNIX AND NOT APPLE)
        # Linux: disable PipeWire backend (known unstable on this system)
        set(ALSOFT_BACKEND_PIPEWIRE OFF CACHE BOOL "Disable PipeWire backend" FORCE)
    endif()

    FetchContent_MakeAvailable(openal_soft)

    # openal-soft FetchContent creates the OpenAL::OpenAL imported target
    message(STATUS "OpenAL Soft configured: target OpenAL::OpenAL available")
endif()
