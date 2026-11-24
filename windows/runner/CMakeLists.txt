cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
# Auto-fetch ONNX Runtime DirectML SDK on fresh clones if not cached yet.
set(ORT_ROOT "${CMAKE_SOURCE_DIR}/third_party/onnxruntime")
if(NOT EXISTS "${ORT_ROOT}/lib/onnxruntime.lib")
  message(STATUS "Downloading ONNX Runtime DirectML 1.24.4 + DirectML 1.15.4...")
  file(MAKE_DIRECTORY "${ORT_ROOT}/include" "${ORT_ROOT}/lib" "${ORT_ROOT}/bin" "${ORT_ROOT}/tmp")
  file(DOWNLOAD
    "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime.directml/1.24.4/microsoft.ml.onnxruntime.directml.1.24.4.nupkg"
    "${ORT_ROOT}/tmp/ort_dml.zip"
    SHOW_PROGRESS
  )
  file(DOWNLOAD
    "https://api.nuget.org/v3-flatcontainer/microsoft.ai.directml/1.15.4/microsoft.ai.directml.1.15.4.nupkg"
    "${ORT_ROOT}/tmp/dml.zip"
    SHOW_PROGRESS
  )
  file(ARCHIVE_EXTRACT INPUT "${ORT_ROOT}/tmp/ort_dml.zip" DESTINATION "${ORT_ROOT}/tmp/ort_dml")
  file(ARCHIVE_EXTRACT INPUT "${ORT_ROOT}/tmp/dml.zip" DESTINATION "${ORT_ROOT}/tmp/dml")
  file(COPY "${ORT_ROOT}/tmp/ort_dml/build/native/include/" DESTINATION "${ORT_ROOT}/include")
  file(COPY "${ORT_ROOT}/tmp/dml/include/" DESTINATION "${ORT_ROOT}/include")
  file(COPY "${ORT_ROOT}/tmp/ort_dml/runtimes/win-x64/native/onnxruntime.lib" DESTINATION "${ORT_ROOT}/lib")
  file(COPY "${ORT_ROOT}/tmp/ort_dml/runtimes/win-x64/native/onnxruntime.dll" DESTINATION "${ORT_ROOT}/bin")
  file(COPY "${ORT_ROOT}/tmp/ort_dml/runtimes/win-x64/native/onnxruntime_providers_shared.dll" DESTINATION "${ORT_ROOT}/bin")
  file(COPY "${ORT_ROOT}/tmp/dml/bin/x64-win/DirectML.dll" DESTINATION "${ORT_ROOT}/bin")
  file(REMOVE_RECURSE "${ORT_ROOT}/tmp")
endif()

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "projector/projector_plugin.cpp"
  "vision/mf_camera_capture.cpp"
  "vision/onnx_pose_hand_tracker.cpp"
  "vision/vision_plugin.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE
  "dwmapi.lib"
  "Shcore.lib"
  "mf.lib"
  "mfplat.lib"
  "mfreadwrite.lib"
  "mfuuid.lib"
  "${ORT_ROOT}/lib/onnxruntime.lib"
)
target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${ORT_ROOT}/include"
)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
