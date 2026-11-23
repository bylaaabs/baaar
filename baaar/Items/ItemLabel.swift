import Foundation

/// An item's label: the first line of the first attribute that has text.
enum ItemLabel {
    /// Reads each attribute at most once, in order. A title or description can change between two
    /// Accessibility reads, so a value is never read again to be returned.
    static func first(of attributes: [String], read: (String) -> String?) -> String? {
        for attribute in attributes {
            if let value = read(attribute), !value.isEmpty {
                return value.components(separatedBy: .newlines)[0]
            }
        }
        return nil
    }
}
