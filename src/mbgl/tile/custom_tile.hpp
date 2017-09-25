#pragma once

#include <mbgl/tile/geometry_tile.hpp>
#include <mbgl/util/feature.hpp>
#include <mbgl/style/sources/custom_vector_source.hpp>
#include <mbgl/style/sources/geojson_source.hpp>

namespace mbgl {

class TileParameters;

class CustomTile: public GeometryTile {
public:
    CustomTile(const OverscaledTileID&,
               std::string sourceID,
               const TileParameters&,
               const style::GeoJSONOptions);

    void setTileData(const CanonicalTileID& tileID, const style::FetchTileResult& result);

    void setNecessity(Necessity) final;
    
    void querySourceFeatures(
        std::vector<Feature>& result,
        const SourceQueryOptions&) override;
    
    ActorRef<style::FetchTileCallback> fetchTileCallback();
private:
    const style::GeoJSONOptions options;
    Actor<style::FetchTileCallback> actor;
};

} // namespace mbgl
