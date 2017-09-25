#include <mbgl/tile/custom_tile.hpp>
#include <mbgl/tile/geometry_tile_data.hpp>
#include <mbgl/renderer/query.hpp>
#include <mbgl/renderer/tile_parameters.hpp>
#include <mbgl/style/filter_evaluator.hpp>
#include <mbgl/util/logging.hpp>
#include <mbgl/actor/scheduler.hpp>

#include <mapbox/geojsonvt.hpp>

namespace mbgl {

CustomTile::CustomTile(const OverscaledTileID& overscaledTileID,
                         std::string sourceID_,
                         const TileParameters& parameters,
                         const style::GeoJSONOptions options_)
    : GeometryTile(overscaledTileID, sourceID_, parameters),
    options(options_),
    actor(*Scheduler::GetCurrent(), std::bind(&CustomTile::setTileData, this, std::placeholders::_1, std::placeholders::_2)) {

}

void CustomTile::setTileData(const CanonicalTileID&, const style::FetchTileResult& result) {
    if (result.is<style::Error>()) {
        Log::Error(Event::Render, "FetchTile (%d, %d, %d) error: %s", id.canonical.z, id.canonical.x, id.canonical.y, result.get<style::Error>().message.c_str());
        return;
    }
    
    auto geoJSON = result.get<mapbox::geojson::geojson>();
    auto data = mapbox::geometry::feature_collection<int16_t>();
    if (geoJSON.is<FeatureCollection>() && !geoJSON.get<FeatureCollection>().empty()) {
        const double scale = util::EXTENT / options.tileSize;

        mapbox::geojsonvt::Options vtOptions;
        vtOptions.maxZoom = options.maxzoom;
        vtOptions.extent = util::EXTENT;
        vtOptions.buffer = std::round(scale * options.buffer);
        vtOptions.tolerance = scale * options.tolerance;
        auto geojsonVt = std::make_unique<mapbox::geojsonvt::GeoJSONVT>(geoJSON, vtOptions);
        data = geojsonVt->getTile(id.canonical.z, id.canonical.x, id.canonical.y).features;
    }
    setData(std::make_unique<GeoJSONTileData>(std::move(data)));
}

void CustomTile::setNecessity(Necessity) {}
    
void CustomTile::querySourceFeatures(
    std::vector<Feature>& result,
    const SourceQueryOptions& queryOptions) {
    
    // Ignore the sourceLayer, there is only one
    auto layer = getData()->getLayer({});
    
    if (layer) {
        auto featureCount = layer->featureCount();
        for (std::size_t i = 0; i < featureCount; i++) {
            auto feature = layer->getFeature(i);
            
            // Apply filter, if any
            if (queryOptions.filter && !(*queryOptions.filter)(*feature)) {
                continue;
            }
            
            result.push_back(convertFeature(*feature, id.canonical));
        }
    }
}

ActorRef<style::FetchTileCallback> CustomTile::fetchTileCallback() {
    return actor.self();
}

} // namespace mbgl
