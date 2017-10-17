#pragma once

#include <mbgl/util/optional.hpp>
#include <mbgl/util/feature.hpp>
#include <mbgl/util/geojson.hpp>

#include <string>

namespace mbgl {
namespace style {
namespace conversion {

/*
   The `conversion` namespace defines conversions from JSON structures conforming to the schema defined by
   the Mapbox Style Specification, to the various C++ types that form the C++ model of that domain:

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

   `Value` is a type that encapsulates a special form of polymorphism over various underlying types that
   can serve as input to the conversion algorithm. For instance, on macOS, we need to support
   conversion from both RapidJSON types, and a JSON structure represented with `NSArray`/`NSDictionary`/etc.
   On Qt, we need to support conversion from RapidJSON types and QVariant.

   We don't want to use traditional forms of polymorphism to accomplish this:

     * Compile time polymorphism using a template parameter for the actual value type leads to
       excessive code bloat and long compile times.
     * Runtime polymorphism using virtual methods requires extra heap allocation and ubiquitous
       use of std::unique_ptr, unsuitable for this performance-sensitive code.

   Therefore, we're using a custom implementation where we manually create and dispatch through a table
   of function pointers (vtable), while keeping the storage for any of the possible underlying types inline
   on the stack.

   For a given underlying type T, an explicit specialization of ValueTraits<T> must be provided. This
   specialization must provide the following static methods:

      * `isUndefined(v)` -- returns a boolean indication whether `v` is undefined or a JSON null

      * `isArray(v)` -- returns a boolean indicating whether `v` represents a JSON array
      * `arrayLength(v)` -- called only if `isArray(v)`; returns a size_t length
      * `arrayMember(v)` -- called only if `isArray(v)`; returns `V` or `V&`

      * `isObject(v)` -- returns a boolean indicating whether `v` represents a JSON object
      * `objectMember(v, name)` -- called only if `isObject(v)`; `name` is `const char *`; return value:
         * is true when evaluated in a boolean context iff the named member exists
         * is convertable to a `V` or `V&` when dereferenced
      * `eachMember(v, [] (const std::string&, const V&) -> optional<Error> {...})` -- called
         only if `isObject(v)`; calls the provided lambda once for each key and value of the object;
         short-circuits if any call returns an `Error`

      * `toBool(v)` -- returns `optional<bool>`, absence indicating `v` is not a JSON boolean
      * `toNumber(v)` -- returns `optional<float>`, absence indicating `v` is not a JSON number
      * `toDouble(v)` -- returns `optional<double>`, absence indicating `v` is not a JSON number
      * `toString(v)` -- returns `optional<std::string>`, absence indicating `v` is not a JSON string
      * `toValue(v)` -- returns `optional<mbgl::Value>`, a variant type, for generic conversion,
        absence indicating `v` is not a boolean, number, or string. Numbers should be converted to
        unsigned integer, signed integer, or floating point, in descending preference.

   In addition, the type T must be move-constructable. And finally, `Value::Storage`, a typedef for
   `std::aligned_storage_t`, must be large enough to satisfy the memory requirements for any of the
   possible underlying types. (A static assert will fail if this is not the case.)

   `Value` itself is movable, but not copyable. A moved-from `Value` is in an invalid state; you must
   not do anything with it except let it go out of scope.
*/

struct Error { std::string message; };

template <typename T>
class ValueTraits;

class Value {
public:
    template <typename T>
    Value(const T value) : vtable(vtableForType<T>()) {
        static_assert(sizeof(Storage) >= sizeof(T), "Storage must be large enough to hold value type");
        new (static_cast<void*>(&storage)) T(value);
   }

    Value(Value&& v)
        : vtable(v.vtable)
    {
        if (vtable) {
            vtable->move(std::move(v.storage), this->storage);
        }
    }

    ~Value() {
        if (vtable) {
            vtable->destroy(storage);
        }
    }

    Value& operator=(Value&& v) {
        if (vtable) {
            vtable->destroy(storage);
        }
        vtable = v.vtable;
        if (vtable) {
            vtable->move(std::move(v.storage), this->storage);
        }
        v.vtable = nullptr;
        return *this;
    }

    Value()                        = delete;
    Value(const Value&)            = delete;
    Value& operator=(const Value&) = delete;

    friend inline bool isUndefined(const Value& v) {
        assert(v.vtable);
        return v.vtable->isUndefined(v.storage);
    }

    friend inline bool isArray(const Value& v) {
        assert(v.vtable);
        return v.vtable->isArray(v.storage);
    }

    friend inline std::size_t arrayLength(const Value& v) {
        assert(v.vtable);
        return v.vtable->arrayLength(v.storage);
    }

    friend inline Value arrayMember(const Value& v, std::size_t i) {
        assert(v.vtable);
        return v.vtable->arrayMember(v.storage, i);
    }

    friend inline bool isObject(const Value& v) {
        assert(v.vtable);
        return v.vtable->isObject(v.storage);
    }

    friend inline optional<Value> objectMember(const Value& v, const char * name) {
        assert(v.vtable);
        return v.vtable->objectMember(v.storage, name);
    }

    friend inline optional<Error> eachMember(const Value& v, const std::function<optional<Error> (const std::string&, const Value&)>& fn) {
        assert(v.vtable);
        return v.vtable->eachMember(v.storage, fn);
    }

    friend inline optional<bool> toBool(const Value& v) {
        assert(v.vtable);
        return v.vtable->toBool(v.storage);
    }

    friend inline optional<float> toNumber(const Value& v) {
        assert(v.vtable);
        return v.vtable->toNumber(v.storage);
    }

    friend inline optional<double> toDouble(const Value& v) {
        assert(v.vtable);
        return v.vtable->toDouble(v.storage);
    }

    friend inline optional<std::string> toString(const Value& v) {
        assert(v.vtable);
        return v.vtable->toString(v.storage);
    }

    friend inline optional<mbgl::Value> toValue(const Value& v) {
        assert(v.vtable);
        return v.vtable->toValue(v.storage);
    }

    friend inline optional<GeoJSON> toGeoJSON(const Value& v, Error& error) {
        assert(v.vtable);
        return v.vtable->toGeoJSON(v.storage, error);
    }

private:
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

    template <typename T>
    static VTable* vtableForType() {
        using Traits = ValueTraits<T>;
    
        static Value::VTable vtable = {
            [] (Storage&& src, Storage& dest) {
                auto srcValue = reinterpret_cast<T&&>(src);
                new (static_cast<void*>(&dest)) T(std::move(srcValue));
                srcValue.~T();
            },
            [] (Storage& s) {
                reinterpret_cast<T&>(s).~T();
            },
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
