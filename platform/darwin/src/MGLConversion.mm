#import <Foundation/Foundation.h>

#include "MGLConversion.h"

NS_ASSUME_NONNULL_BEGIN

namespace mbgl {
namespace style {
namespace conversion {

class Holder {
public:
    Holder(const id v) : value(v) {}
    const id value;
};

using MGLValue = Holder;

template<> bool ValueTraits<MGLValue>::isUndefined(const MGLValue& holder) {
    const id value = holder.value;
    return !value || value == [NSNull null];
}

template<> bool ValueTraits<MGLValue>::isArray(const MGLValue& holder) {
    const id value = holder.value;
    return [value isKindOfClass:[NSArray class]];
}

template<> bool ValueTraits<MGLValue>::isObject(const MGLValue& holder) {
    const id value = holder.value;
    return [value isKindOfClass:[NSDictionary class]];
}

template<> std::size_t ValueTraits<MGLValue>::arrayLength(const MGLValue& holder) {
    const id value = holder.value;
    NSCAssert([value isKindOfClass:[NSArray class]], @"Value must be an NSArray for getLength().");
    NSArray *array = value;
    auto length = [array count];
    NSCAssert(length <= std::numeric_limits<size_t>::max(), @"Array length out of bounds.");
    return length;
}

template<> MGLValue ValueTraits<MGLValue>::arrayMember(const MGLValue& holder, std::size_t i) {
    const id value = holder.value;
    NSCAssert([value isKindOfClass:[NSArray class]], @"Value must be an NSArray for get(int).");
    NSCAssert(i < NSUIntegerMax, @"Index must be less than NSUIntegerMax");
    return {[value objectAtIndex: i]};
}

template<> optional<MGLValue> ValueTraits<MGLValue>::objectMember(const MGLValue& holder, const char *key) {
    const id value = holder.value;
    NSCAssert([value isKindOfClass:[NSDictionary class]], @"Value must be an NSDictionary for get(string).");
    NSObject *member = [value objectForKey: @(key)];
    if (member && member != [NSNull null]) {
        return {member};
    } else {
        return {};
    }
}

template<> optional<Error> ValueTraits<MGLValue>::eachMember(const MGLValue& holder, const std::function<optional<Error> (const std::string&, const MGLValue&)>& fn) {
    // Not implemented (unneeded for MGLStyleFunction conversion).
    NSCAssert(NO, @"eachMember not implemented");
    return {};
}

inline bool _isBool(const id value) {
    if (![value isKindOfClass:[NSNumber class]]) return false;
    // char: 32-bit boolean
    // BOOL: 64-bit boolean
    NSNumber *number = value;
    return ((strcmp([number objCType], @encode(char)) == 0) ||
            (strcmp([number objCType], @encode(BOOL)) == 0));
}
    
inline bool _isNumber(const id value) {
    return [value isKindOfClass:[NSNumber class]] && !_isBool(value);
}
    
inline bool _isString(const id value) {
    return [value isKindOfClass:[NSString class]];
}

template<> optional<bool> ValueTraits<MGLValue>::toBool(const MGLValue& holder) {
    const id value = holder.value;
    if (_isBool(value)) {
        return ((NSNumber *)value).boolValue;
    } else {
        return {};
    }
}

template<> optional<float> ValueTraits<MGLValue>::toNumber(const MGLValue& holder) {
    const id value = holder.value;
    if (_isNumber(value)) {
        return ((NSNumber *)value).floatValue;
    } else {
        return {};
    }
}

template<> optional<double> ValueTraits<MGLValue>::toDouble(const MGLValue& holder) {
    const id value = holder.value;
    if (_isNumber(value)) {
        return ((NSNumber *)value).doubleValue;
    } else {
        return {};
    }
}

template<> optional<std::string> ValueTraits<MGLValue>::toString(const MGLValue& holder) {
    const id value = holder.value;
    if (_isString(value)) {
        return std::string(static_cast<const char *>([value UTF8String]));
    } else {
        return {};
    }
}

template<> optional<mbgl::Value> ValueTraits<MGLValue>::toValue(const MGLValue& holder) {
    const id value = holder.value;
    if (isUndefined(value)) {
        return {};
    } else if (_isBool(value)) {
        return { *toBool(holder) };
    } else if ( _isString(value)) {
        return { *toString(holder) };
    } else if (_isNumber(value)) {
        // Need to cast to a double here as the float is otherwise considered a bool...
       return { static_cast<double>(*toNumber(holder)) };
    } else {
        return {};
    }
}

template<> optional<GeoJSON> ValueTraits<MGLValue>::toGeoJSON(const MGLValue& holder, Error& error) {
    error = { "toGeoJSON not implemented" };
    return {};
}

Value makeValue(const id value) {
    return {Holder(value)};
}


} // namespace conversion
} // namespace style
} // namespace mbgl

NS_ASSUME_NONNULL_END

