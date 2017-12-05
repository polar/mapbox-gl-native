add_executable(alk-rts
    alk/TileServer.cpp
)

target_sources(alk-rts
    PRIVATE alk/RasterTileRenderer.cpp
    PRIVATE alk/RasterTileRenderer.hpp
    PRIVATE alk/Tile.cpp
    PRIVATE alk/Tile.hpp
    PRIVATE alk/TileHandler.cpp
    PRIVATE alk/TileHandler.hpp
    PRIVATE alk/TileLoader.cpp
    PRIVATE alk/TileLoader.hpp
    PRIVATE alk/TilePath.cpp
    PRIVATE alk/TilePath.hpp
    PRIVATE alk/TileServer.cpp
    PRIVATE alk/Frontend.hpp
    PRIVATE alk/Frontend.cpp
    PRIVATE alk/Map.hpp
    PRIVATE alk/Map.cpp
    PRIVATE alk/RenderCache.hpp
    PRIVATE alk/RenderCache.cpp
)

target_compile_options(alk-rts
    PRIVATE -ggdb
)
target_include_directories(alk-rts
    PRIVATE platform/default
    PRIVATE src
)

target_link_libraries(alk-rts
    PUBLIC proxygenhttpserver
    PUBLIC proxygenlib
    PUBLIC folly
    PUBLIC wangle
    PUBLIC pthread
    PUBLIC gflags
    PUBLIC glog
    PRIVATE mbgl-core
    PRIVATE mbgl-filesource
    PRIVATE mbgl-loop-uv
)

target_add_mason_package(alk-rts PRIVATE cheap-ruler)
target_add_mason_package(alk-rts PRIVATE unique_resource)
target_add_mason_package(alk-rts PRIVATE geojson)
target_add_mason_package(alk-rts PRIVATE geometry)
target_add_mason_package(alk-rts PRIVATE glfw)
target_add_mason_package(alk-rts PRIVATE rapidjson)
target_add_mason_package(alk-rts PRIVATE libuv)
target_add_mason_package(alk-rts PRIVATE variant)
target_add_mason_package(alk-rts PRIVATE boost)
target_add_mason_package(alk-rts PRIVATE boost_libprogram_options)

alk_rts()

create_source_groups(alk-rts)


