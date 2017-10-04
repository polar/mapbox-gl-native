#pragma once

#include <mbgl/tile/geometry_tile.hpp>
#include <mbgl/util/feature.hpp>
#include <mbgl/style/sources/custom_vector_source.hpp>
#include <mbgl/style/sources/geojson_source.hpp>

namespace mbgl {

class TileParameters;

namespace style {

class CustomTile: public GeometryTile {
public:
    CustomTile(const OverscaledTileID&,
               std::string sourceID,
               const TileParameters&,
               const style::GeoJSONOptions,
               ActorRef<style::CustomTileLoader> loader);
    ~CustomTile() override;
    void setTileData(const mapbox::geojson::geojson& data);

    void setNecessity(Necessity) final;

    void querySourceFeatures(
        std::vector<Feature>& result,
        const SourceQueryOptions&) override;

private:
    Necessity necessity;
    const style::GeoJSONOptions options;
    ActorRef<style::CustomTileLoader> loader;
    Actor<style::SetTileDataFunction> actor;
};

} // namespace style
} // namespace mbgl
