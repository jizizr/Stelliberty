cmake_minimum_required(VERSION 3.22.1)

project(clash_core_bridge)

add_library(
  clash_core_bridge
  SHARED
  clash_core_bridge.cpp
)

find_library(log-lib log)

target_link_libraries(
  clash_core_bridge
  ${log-lib}
  dl
)
