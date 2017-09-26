#pragma once

#include <mbgl/util/optional.hpp>
#include <mbgl/util/feature.hpp>
#include <mbgl/util/geojson.hpp>

#include <string>

namespace mbgl {
namespace style {
namespace conversion {

/*
   The `conversion` namespace defines conversions from a templated type `V` representing a JSON
   object conforming to the schema defined by the Mapbox Style Specification, to the various C++
   types that form the C++ model of that domain:

       * `std::unique_ptr<Source>`
       * `std::unique_ptr<Layer>`
       * `Filter`
       * `PropertyValue<T>`

   A single template function serves as the public interface:

       template <class T>
       optional<T> convert(const Value& value, Error& error);

   Where `T` is one of the above types. If the conversion fails, the result is empty, and the
   error parameter includes diagnostic text suitable for presentation to a library user. Otherwise,
   a filled optional is returned.
*/

namespace detail {


} // namespace detail


struct Error { std::string message; };

template <typename T>
struct ValueTraits {
    static bool isUndefined(const T& value);
    static bool isArray(const T& value);
    static std::size_t arrayLength(const T& value);
    static T arrayMember(const T& value, std::size_t i);
    static bool isObject(const T& value);
    static optional<T> objectMember(const T& value, const char * name);
    static optional<Error> eachMember(const T& value, const std::function<optional<Error> (const std::string&, const T&)>& fn);
    static optional<bool> toBool(const T& value);
    static optional<float> toNumber(const T& value);
    static optional<double> toDouble(const T& value);
    static optional<std::string> toString(const T& value);
    static optional<mbgl::Value> toValue(const T& value);
    static optional<GeoJSON> toGeoJSON(const T& value, Error& error);
};

class Value {
    // Node:        JSValue* or v8::Local<v8::Value>
    // Android:     JSValue* or mbgl::android::Value
    // iOS/macOS:   JSValue* or id
    // Qt:          JSValue* or QVariant

    // TODO: use platform-specific size
    using Storage = std::aligned_storage_t<32, 8>;
    struct VTable {
        void (*move) (Storage&& src, Storage& dest);
        void (*destroy) (Storage&);

        bool (*isUndefined) (const Storage&);

        bool        (*isArray)     (const Storage&);
        std::size_t (*arrayLength) (const Storage&);
        Value       (*arrayMember) (const Storage&, std::size_t);

        bool            (*isObject)     (const Storage&);
        optional<Value> (*objectMember) (const Storage&, const char *);
        optional<Error> (*eachMember)   (const Storage&, const std::function<optional<Error> (const std::string&, const Value&)>&);

        optional<bool>        (*toBool)   (const Storage&);
        optional<float>       (*toNumber) (const Storage&);
        optional<double>      (*toDouble) (const Storage&);
        optional<std::string> (*toString) (const Storage&);
        optional<mbgl::Value> (*toValue)  (const Storage&);

        // https://github.com/mapbox/mapbox-gl-native/issues/5623
        optional<GeoJSON> (*toGeoJSON) (const Storage&, Error&);
    };

public:
    Value(VTable* vt, Storage&& s)
        : vtable(vt)
    {
        vtable->move(std::move(s), this->storage);
    }

    Value(Value&& v)
        : vtable(v.vtable)
    {
        vtable->move(std::move(v.storage), this->storage);
    }

    template <typename T>
    Value(const T value) : vtable(vtableForType<T>()) {
        static_assert(sizeof(Storage) >= sizeof(T), "Storage must be large enough to hold value type");

        new (static_cast<void*>(&storage)) const T (value);
   }

    ~Value() {
        vtable->destroy(storage);
    }

    Value& operator=(Value&& v) {
        vtable->destroy(storage);
        vtable = v.vtable;
        vtable->move(std::move(v.storage), this->storage);
        return *this;
    }

    Value()                        = delete;
    Value(const Value&)            = delete;
    Value& operator=(const Value&) = delete;

    friend inline bool isUndefined(const Value& v) {
        return v.vtable->isUndefined(v.storage);
    }

    friend inline bool isArray(const Value& v) {
        return v.vtable->isArray(v.storage);
    }

    friend inline std::size_t arrayLength(const Value& v) {
        return v.vtable->arrayLength(v.storage);
    }

    friend inline Value arrayMember(const Value& v, std::size_t i) {
        return v.vtable->arrayMember(v.storage, i);
    }

    friend inline bool isObject(const Value& v) {
        return v.vtable->isObject(v.storage);
    }

    friend inline optional<Value> objectMember(const Value& v, const char * name) {
        return v.vtable->objectMember(v.storage, name);
    }

    friend inline optional<Error> eachMember(const Value& v, const std::function<optional<Error> (const std::string&, const Value&)>& fn) {
        return v.vtable->eachMember(v.storage, fn);
    }

    friend inline optional<bool> toBool(const Value& v) {
        return v.vtable->toBool(v.storage);
    }

    friend inline optional<float> toNumber(const Value& v) {
        return v.vtable->toNumber(v.storage);
    }

    friend inline optional<double> toDouble(const Value& v) {
        return v.vtable->toDouble(v.storage);
    }

    friend inline optional<std::string> toString(const Value& v) {
        return v.vtable->toString(v.storage);
    }

    friend inline optional<mbgl::Value> toValue(const Value& v) {
        return v.vtable->toValue(v.storage);
    }

    friend inline optional<GeoJSON> toGeoJSON(const Value& v, Error& error) {
        return v.vtable->toGeoJSON(v.storage, error);
    }

private:
    template <typename T>
    static VTable* vtableForType() {
        using Traits = ValueTraits<T>;
    
        static Value::VTable vtable = {
            [] (Storage&& src, Storage& dest) {
                auto srcValue = reinterpret_cast<T&&>(src);
                new (static_cast<void*>(&dest)) const T (std::move(srcValue));
                srcValue.~T();
            },
            [] (Storage& s) { reinterpret_cast<T&>(s).~T(); },
            [] (const Storage& s) {
                return Traits::isUndefined(reinterpret_cast<const T&>(s));
            },
            [] (const Storage& s) {
                return Traits::isArray(reinterpret_cast<const T&>(s));
            },
            [] (const Storage& s) {
                return Traits::arrayLength(reinterpret_cast<const T&>(s));
            },
            [] (const Storage& s, std::size_t i) {
                return Value(Traits::arrayMember(reinterpret_cast<const T&>(s), i));
            },
            [] (const Storage& s) {
                return Traits::isObject(reinterpret_cast<const T&>(s));
            },
            [] (const Storage& s, const char * key) {
                optional<T> member = Traits::objectMember(reinterpret_cast<const T&>(s), key);
                if (member) return optional<Value>(*member);
                return optional<Value>();
            },
            [] (const Storage& s, const std::function<optional<Error> (const std::string&, const Value&)>& fn) {
                return Traits::eachMember(reinterpret_cast<const T&>(s), [&](const std::string& k, const T& v) {
                    return fn(k, Value(v));
                });
            },
            [] (const Storage& s) {
                return Traits::toBool(reinterpret_cast<const T&>(s));
            },
            [] (const Storage& s) {
                return Traits::toNumber(reinterpret_cast<const T&>(s));
            },
            [] (const Storage& s) {
                return Traits::toDouble(reinterpret_cast<const T&>(s));
            },
            [] (const Storage& s) {
                return Traits::toString(reinterpret_cast<const T&>(s));
            },
            []  (const Storage& s) {
                return Traits::toValue(reinterpret_cast<const T&>(s));
            },
            [] (const Storage& s, Error& err) {
                return Traits::toGeoJSON(reinterpret_cast<const T&>(s), err);
            }
        };
        return &vtable;
    }

    VTable* vtable;
    Storage storage;
};

template <class T, class Enable = void>
struct Converter;

template <class T, class...Args>
optional<T> convert(const Value& value, Error& error, Args&&...args) {
    return Converter<T>()(value, error, std::forward<Args>(args)...);
}

} // namespace conversion
} // namespace style
} // namespace mbgl
