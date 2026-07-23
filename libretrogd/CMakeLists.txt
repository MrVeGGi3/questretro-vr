cmake_minimum_required(VERSION 3.20)
project(libretrogd LANGUAGES CXX)

# godot-cpp (branch 4.5) fornece o target `godot-cpp` e os headers da API.
add_subdirectory(godot-cpp)

file(GLOB SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")

add_library(libretrogd SHARED ${SOURCES})

target_compile_features(libretrogd PRIVATE cxx_std_17)
target_link_libraries(libretrogd PRIVATE godot-cpp)
# dlopen/dlsym (libdl) — em glibc moderno já está na libc, mas ligamos por portabilidade.
target_link_libraries(libretrogd PRIVATE ${CMAKE_DL_LIBS})

# Nome de saída no padrão que o .gdextension referencia, sem prefixo "lib".
# Ex.: libretrogd.linux.x86_64.so
if(ANDROID)
	set(LRGD_PLATFORM "android")
	# Normaliza a ABI para a tag que o .gdextension usa (arm64-v8a -> arm64).
	if(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
		set(LRGD_ARCH "arm64")
	elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "armeabi-v7a")
		set(LRGD_ARCH "arm32")
	else()
		set(LRGD_ARCH "${CMAKE_ANDROID_ARCH_ABI}")
	endif()
else()
	string(TOLOWER "${CMAKE_SYSTEM_NAME}" LRGD_PLATFORM)
	set(LRGD_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
endif()

set_target_properties(libretrogd PROPERTIES
	PREFIX ""
	OUTPUT_NAME "libretrogd.${LRGD_PLATFORM}.${LRGD_ARCH}"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../app/bin"
)

message(STATUS "libretrogd -> app/bin/libretrogd.${LRGD_PLATFORM}.${LRGD_ARCH}.so")
