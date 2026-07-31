cmake_minimum_required(VERSION 3.20)
project(libretrogd LANGUAGES CXX)

# Caminho de compilação fora do binário. Os macros de erro do godot-cpp gravam
# `__FILE__` em `.rodata`, então o caminho absoluto da máquina que compilou vai
# junto no `.so` — e no APK publicado. Não é debug info: o binário já sai
# stripado e as strings continuam lá, então `strip` não resolve.
#
# `-ffile-prefix-map` implica `-fmacro-prefix-map` (que é o que alcança
# `__FILE__`) e `-fdebug-prefix-map`. Precisa vir **antes** do
# `add_subdirectory`: `add_compile_options` só alcança alvos criados depois.
add_compile_options("-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}/=")

# godot-cpp (branch 4.5) fornece o target `godot-cpp` e os headers da API.
add_subdirectory(godot-cpp)

file(GLOB SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")

add_library(libretrogd SHARED ${SOURCES})

target_compile_features(libretrogd PRIVATE cxx_std_17)
target_link_libraries(libretrogd PRIVATE godot-cpp)
# dlopen/dlsym (libdl) — em glibc moderno já está na libc, mas ligamos por portabilidade.
target_link_libraries(libretrogd PRIVATE ${CMAKE_DL_LIBS})

# Nome de saída no padrão que o .gdextension referencia, sem prefixo "lib".
# Ex.: libretrogd.android.template_release.arm64.so
#
# **O alvo do godot-cpp entra no nome porque precisa entrar.** Uma extensão
# compilada contra `template_debug` e carregada num motor `template_release`
# passa pelo `dlopen` sem erro nenhum e mata o processo depois: SIGSEGV dentro do
# próprio motor, sem um único quadro da extensão no backtrace. Medido no Quest
# 3S — `fault addr 0x15` no primeiro `GodotLib.step` após o resume, com o APK
# debug rodando a 72 fps ao lado. Com o alvo no nome os dois binários coexistem,
# e é o `.gdextension` que escolhe pelo tipo de build.
#
# `CMAKE_BUILD_TYPE` **não** serve para isso: ele só liga otimização. Quem decide
# a variante da API é `GODOTCPP_TARGET`, cujo padrão é `template_debug` — então
# quem só passa `-DCMAKE_BUILD_TYPE=Release` leva um binário de debug com nome
# de release, que é exatamente como o crash nasceu.
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

set(LRGD_NOME "libretrogd.${LRGD_PLATFORM}.${GODOTCPP_TARGET}.${LRGD_ARCH}")

set_target_properties(libretrogd PROPERTIES
	PREFIX ""
	OUTPUT_NAME "${LRGD_NOME}"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../app/bin"
)

message(STATUS "libretrogd -> app/bin/${LRGD_NOME}.so (alvo: ${GODOTCPP_TARGET})")
