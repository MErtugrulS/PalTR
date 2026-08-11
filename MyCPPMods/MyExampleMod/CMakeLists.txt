cmake_minimum_required(VERSION 3.22)

set(TARGET PalTRStructureGuard)
project(${TARGET})

add_library(PalTRPolicy STATIC "src/PolicySnapshot.cpp")
target_include_directories(PalTRPolicy PUBLIC "src")
target_compile_features(PalTRPolicy PUBLIC cxx_std_20)

add_library(${TARGET} SHARED "src/dllmain.cpp")
target_include_directories(${TARGET} PRIVATE .)

target_link_libraries(${TARGET} PRIVATE UE4SS PalTRPolicy)

add_executable(PalTRPolicyTests "tests/PolicySnapshotTests.cpp")
target_link_libraries(PalTRPolicyTests PRIVATE PalTRPolicy)

enable_testing()
add_test(NAME PalTRPolicyTests COMMAND PalTRPolicyTests)
