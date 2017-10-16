#include <mbgl/style/rapidjson_conversion.hpp>
#include <mapbox/geojson.hpp>
#include <mapbox/geojson/rapidjson.hpp>


namespace mbgl {
namespace style {
namespace conversion {

template<> bool ValueTraits<const JSValue*>::isUndefined(const JSValue* const& value) {
    return value->IsNull();
}

template<> bool ValueTraits<const JSValue*>::isArray(const JSValue* const& value) {
    return value->IsArray();
}

template<> std::size_t ValueTraits<const JSValue*>::arrayLength(const JSValue* const& value) {
    return value->Size();
}

template<> const JSValue* ValueTraits<const JSValue*>::arrayMember(const JSValue* const& value, std::size_t i) {
    return &(*value)[rapidjson::SizeType(i)];
}

template<> bool ValueTraits<const JSValue*>::isObject(const JSValue* const& value) {
    return value->IsObject();
}

template<> optional<const JSValue*> ValueTraits<const JSValue*>::objectMember(const JSValue* const& value, const char * name) {
    if (!value->HasMember(name)) {
        return optional<const JSValue*>();
    }
    const JSValue* const& member = &(*value)[name];
    return {member};
}

template<> optional<Error> ValueTraits<const JSValue*>::eachMember(const JSValue* const& value, const std::function<optional<Error> (const std::string&, const JSValue* const&)>& fn) {
    assert(value->IsObject());
    for (const auto& property : value->GetObject()) {
        optional<Error> result =
            fn({ property.name.GetString(), property.name.GetStringLength() }, &property.value);
        if (result) {
            return result;
        }
    }
    return {};
}

template<> optional<bool> ValueTraits<const JSValue*>::toBool(const JSValue* const& value) {
    if (!value->IsBool()) {
        return {};
    }
    return value->GetBool();
}

template<> optional<float> ValueTraits<const JSValue*>::toNumber(const JSValue* const& value) {
    if (!value->IsNumber()) {
        return {};
    }
    return value->GetDouble();
}

template<> optional<double> ValueTraits<const JSValue*>::toDouble(const JSValue* const& value) {
    if (!value->IsNumber()) {
        return {};
    }
    return value->GetDouble();
}

template<> optional<std::string> ValueTraits<const JSValue*>::toString(const JSValue* const& value) {
    if (!value->IsString()) {
        return {};
    }
    return {{ value->GetString(), value->GetStringLength() }};
}

template<> optional<mbgl::Value> ValueTraits<const JSValue*>::toValue(const JSValue* const& value) {
    switch (value->GetType()) {
        case rapidjson::kNullType:
        case rapidjson::kFalseType:
            return { false };

        case rapidjson::kTrueType:
            return { true };

        case rapidjson::kStringType:
            return { std::string { value->GetString(), value->GetStringLength() } };

        case rapidjson::kNumberType:
            if (value->IsUint64()) return { value->GetUint64() };
            if (value->IsInt64()) return { value->GetInt64() };
            return { value->GetDouble() };

        default:
            return {};
    }
}

template<> optional<GeoJSON> ValueTraits<const JSValue*>::toGeoJSON(const JSValue* const& value, Error& error) {
    try {
        return mapbox::geojson::convert(*value);
    } catch (const std::exception& ex) {
        error = { ex.what() };
        return {};
    }
}


} // namespace conversion
} // namespace style
} // namespace mbgl
