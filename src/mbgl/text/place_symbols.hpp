#pragma once

namespace mbgl {

    class SymbolBucket;
    class SymbolLayout;
    struct CollisionFadeTimes;

    void updateOpacities(SymbolBucket&, SymbolLayout&, CollisionFadeTimes&);


} // namespace mbgl
