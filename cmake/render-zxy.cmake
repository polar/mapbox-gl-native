add_executable(mbgl-render-zxy
    bin/render-zxy.cpp
)

target_compile_options(mbgl-render-zxy
    PRIVATE -fvisibility-inlines-hidden
)

target_include_directories(mbgl-render-zxy
    PRIVATE platform/default
)

target_link_libraries(mbgl-render-zxy
    PRIVATE mbgl-core
)

target_add_mason_package(mbgl-render-zxy PRIVATE boost)
target_add_mason_package(mbgl-render-zxy PRIVATE boost_libprogram_options)

mbgl_platform_render_zxy()

create_source_groups(mbgl-render-zxy)

initialize_xcode_cxx_build_settings(mbgl-render-zxy)

xcode_create_scheme(
    TARGET mbgl-render-zxy
    OPTIONAL_ARGS
        "--style=file.json"
        "--x=0"
        "--y=0"
        "--zoom=0"
        "--bearing=0"
        "--pitch=0"
        "--width=512"
        "--height=512"
        "--ratio=1"
        "--token="
        "--debug"
        "--output=out.png"
        "--cache=cache.sqlite"
        "--assets=."
)
