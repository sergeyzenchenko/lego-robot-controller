import Foundation
import JSONSchemaBuilder

// MARK: - Schema Export Helpers

enum SchemaExport {
    /// Convert a @Schemable-generated schema to [String: Any] for API request bodies.
    static func toDict<T: JSONSchemaComponent>(_ schema: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(schema.definition()),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    /// Convert a schema to OpenAI strict-mode-compatible format.
    ///
    /// OpenAI structured output with `strict: true` requires:
    /// - `anyOf` instead of `oneOf` (for enum variants)
    /// - `additionalProperties: false` on every object
    /// - All properties listed in `required`
    static func toOpenAIStrictDict<T: JSONSchemaComponent>(_ schema: T) -> [String: Any] {
        var dict = toDict(schema)
        enforceOpenAIStrict(&dict)
        return dict
    }

    /// Convert a schema to Gemini format (uppercase type names, strip unsupported keywords).
    static func toGeminiDict<T: JSONSchemaComponent>(_ schema: T) -> [String: Any] {
        var dict = toDict(schema)
        convertToGemini(&dict)
        return dict
    }

    // MARK: - OpenAI Strict Mode

    private static func enforceOpenAIStrict(_ dict: inout [String: Any]) {
        // oneOf → anyOf (OpenAI strict doesn't support oneOf)
        if let oneOf = dict.removeValue(forKey: "oneOf") {
            dict["anyOf"] = oneOf
        }

        // For objects: add additionalProperties: false, ensure all properties in required
        if dict["type"] as? String == "object" {
            dict["additionalProperties"] = false

            if let properties = dict["properties"] as? [String: Any] {
                dict["required"] = Array(properties.keys).sorted()
            }
        }

        // Recurse into all nested structures
        for key in dict.keys {
            if var nested = dict[key] as? [String: Any] {
                enforceOpenAIStrict(&nested)
                dict[key] = nested
            } else if var array = dict[key] as? [[String: Any]] {
                for i in array.indices {
                    enforceOpenAIStrict(&array[i])
                }
                dict[key] = array
            }
        }
    }

    // MARK: - Gemini Format

    private static func convertToGemini(_ dict: inout [String: Any]) {
        // Uppercase type names (string → STRING, object → OBJECT, etc.)
        if let type = dict["type"] as? String {
            dict["type"] = type.uppercased()
        }

        // Gemini supports anyOf but not oneOf — convert oneOf to anyOf
        if let oneOf = dict.removeValue(forKey: "oneOf") {
            dict["anyOf"] = oneOf
        }

        // Strip additionalProperties (Gemini ignores it but can cause 400 errors on some models)
        dict.removeValue(forKey: "additionalProperties")

        // Recurse
        for key in dict.keys {
            if var nested = dict[key] as? [String: Any] {
                convertToGemini(&nested)
                dict[key] = nested
            } else if var array = dict[key] as? [[String: Any]] {
                for i in array.indices {
                    convertToGemini(&array[i])
                }
                dict[key] = array
            }
        }
    }
}
