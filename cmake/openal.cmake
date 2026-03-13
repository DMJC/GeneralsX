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

    # Match the GeneralsX vcpkg openal-soft backend configuration exactly.
    # vcpkg/ports/openal-soft/portfile.cmake disables all backends except the
    # platform-required one. On Linux: ALSA only (no PulseAudio, PipeWire,
    # JACK, OSS, PortAudio, Sndio). This is the known-stable configuration.
    if(WIN32)
        set(ALSOFT_BACKEND_DSOUND   ON  CACHE BOOL "" FORCE)
        set(ALSOFT_REQUIRE_DSOUND   ON  CACHE BOOL "" FORCE)
        set(ALSOFT_BACKEND_WASAPI   ON  CACHE BOOL "" FORCE)
        set(ALSOFT_REQUIRE_WASAPI   ON  CACHE BOOL "" FORCE)
        set(ALSOFT_BACKEND_WINMM    OFF CACHE BOOL "" FORCE)
    elseif(UNIX AND NOT APPLE)
        set(ALSOFT_BACKEND_ALSA     ON  CACHE BOOL "" FORCE)
        set(ALSOFT_REQUIRE_ALSA     ON  CACHE BOOL "" FORCE)
        set(ALSOFT_BACKEND_PIPEWIRE OFF CACHE BOOL "" FORCE)
        set(ALSOFT_BACKEND_PULSEAUDIO OFF CACHE BOOL "" FORCE)
        set(ALSOFT_BACKEND_JACK     OFF CACHE BOOL "" FORCE)
        set(ALSOFT_BACKEND_OSS      OFF CACHE BOOL "" FORCE)
        set(ALSOFT_BACKEND_SNDIO    OFF CACHE BOOL "" FORCE)
        set(ALSOFT_BACKEND_PORTAUDIO OFF CACHE BOOL "" FORCE)
    elseif(APPLE)
        set(ALSOFT_BACKEND_COREAUDIO ON  CACHE BOOL "" FORCE)
        set(ALSOFT_REQUIRE_COREAUDIO ON  CACHE BOOL "" FORCE)
    endif()
    set(ALSOFT_BACKEND_SOLARIS  OFF CACHE BOOL "" FORCE)
    set(ALSOFT_BACKEND_OBOE     OFF CACHE BOOL "" FORCE)
    set(ALSOFT_BACKEND_WAVE     ON  CACHE BOOL "" FORCE)

    FetchContent_MakeAvailable(openal_soft)

    # Patch opthelpers.h: define SIMDALIGN as alignas(32) on Linux.
    #
    # Root cause of SIGSEGV in DeviceBase::DeviceBase on Linux:
    #   alcOpenDevice calls new(std::nothrow) al::Device{...}.
    #   On Linux, SIMDALIGN is defined empty (non-MinGW branch), so alignof(DeviceBase)=8.
    #   alignof(DeviceBase)=8 <= __STDCPP_DEFAULT_NEW_ALIGNMENT__=16, so C++17 uses the
    #   plain operator new(size_t,nothrow_t) path, which calls the game's custom
    #   operator new(size_t). The game's pool allocator guarantees only 8-byte alignment.
    #   The DeviceBase constructor emits SSE movaps instructions (requires 16-byte
    #   alignment) assuming the standard heap's 16-byte guarantee — SIGSEGV.
    #
    # Fix: define SIMDALIGN as alignas(32) on Linux too (matching the MinGW fix).
    #   alignof(DeviceBase)=32 > __STDCPP_DEFAULT_NEW_ALIGNMENT__=16, so C++17 routes
    #   new(nothrow) al::Device through operator new(size_t, align_val_t{32}, nothrow_t),
    #   which calls our override operator new(size_t, align_val_t) = posix_memalign(32,...),
    #   giving properly aligned memory. operator delete(p, align_val_t) calls free(p).
    #
    # Only patch once: skip if the Linux branch already contains alignas(32).
    if(UNIX)
        set(_opthelpers_path "${openal_soft_SOURCE_DIR}/common/opthelpers.h")
        if(EXISTS "${_opthelpers_path}")
            file(READ "${_opthelpers_path}" _opthelpers_content)
            string(FIND "${_opthelpers_content}" "#define SIMDALIGN alignas(32)\n#endif" _already_patched)
            if(_already_patched LESS 0)
                string(REPLACE "#else\n#define SIMDALIGN\n#endif"
                               "#else\n#define SIMDALIGN alignas(32)\n#endif"
                               _opthelpers_patched "${_opthelpers_content}")
                if(NOT "${_opthelpers_patched}" STREQUAL "${_opthelpers_content}")
                    file(WRITE "${_opthelpers_path}" "${_opthelpers_patched}")
                    message(STATUS "OpenAL opthelpers.h patched: SIMDALIGN=alignas(32) on Linux (fixes SIGSEGV from SSE movaps on 8-byte-aligned heap)")
                else()
                    message(WARNING "OpenAL opthelpers.h patch did not apply — string not found (line ending mismatch?)")
                endif()
            else()
                message(STATUS "OpenAL opthelpers.h already patched: SIMDALIGN=alignas(32)")
            endif()
        endif()
    endif()

    # openal-soft FetchContent creates the OpenAL::OpenAL imported target
    message(STATUS "OpenAL Soft configured: target OpenAL::OpenAL available")
endif()
