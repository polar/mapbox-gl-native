#pragma once

#include <mbgl/tile/geometry_tile.hpp>
#include <mbgl/util/feature.hpp>
#include <mbgl/style/custom_tile_loader.hpp>

namespace mbgl {

class TileParameters;

class CustomTile: public GeometryTile {
public:
    CustomTile(const OverscaledTileID&,
               std::string sourceID,
               const TileParameters&,
               const style::CustomVectorSource::TileOptions,
               ActorRef<style::CustomTileLoader> loader);
    ~CustomTile() override;
    void setTileData(const GeoJSON& data);

    void setNecessity(Necessity) final;

    void querySourceFeatures(
        std::vector<Feature>& result,
        const SourceQueryOptions&) override;

private:
    Necessity necessity;
    const style::CustomVectorSource::TileOptions options;
    ActorRef<style::CustomTileLoader> loader;
    Actor<style::SetTileDataFunction> actor;
};

} // namespace mbgl
