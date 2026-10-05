import CFileReferences
import Foundation

/// File references SatimageOSAX returns: FSRefs (`fsrf`, what `list files` and `glob` return by default) and
/// aliases (`alis`). Neither can be made from a file URL by coercion, but an FSRef can be made from a path,
/// and it coerces to an alias or a file URL.
extension NSAppleEventDescriptor {
	/// An `fsrf` descriptor for an existing item, or nil if it doesn't exist.
	public static func fileReference(_ url: URL) -> NSAppleEventDescriptor? {
		var bytes = [UInt8](repeating: 0, count: Int(MTC_FSREF_SIZE))
		guard mtc_fsref_from_path(url.path, &bytes) == 0 else {
			return nil
		}
		return NSAppleEventDescriptor(descriptorType: typeFSRef, data: Data(bytes))
	}

	/// An `alis` descriptor for an existing item, or nil if it doesn't exist.
	public static func alias(_ url: URL) -> NSAppleEventDescriptor? {
		fileReference(url)?.coerce(toDescriptorType: typeAlias)
	}

	/// The POSIX path of an `fsrf` descriptor, or nil if it isn't one or its item is gone.
	public var fileReferencePath: String? {
		guard descriptorType == typeFSRef, data.count == Int(MTC_FSREF_SIZE) else {
			return nil
		}
		var path = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
		let status = data.withUnsafeBytes { mtc_path_from_fsref($0.bindMemory(to: UInt8.self).baseAddress!, &path, path.count) }
		return status == 0 ? String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
	}
}
