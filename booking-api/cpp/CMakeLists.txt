cmake_minimum_required(VERSION 3.14)
project(booking-api)

set(CMAKE_CXX_STANDARD 17)

include(FetchContent)

FetchContent_Declare(httplib
  GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
  GIT_TAG v0.18.3)
FetchContent_MakeAvailable(httplib)

FetchContent_Declare(json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.11.3)
FetchContent_MakeAvailable(json)

find_package(OpenSSL REQUIRED)

add_executable(booking-api main.cpp)
target_link_libraries(booking-api httplib nlohmann_json::nlohmann_json sqlite3 OpenSSL::SSL OpenSSL::Crypto)
