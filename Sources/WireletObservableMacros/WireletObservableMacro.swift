import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct WireletObservableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: WireletObservableDiagnostic.notAFinalClass))
            return []
        }
        guard hasFinalModifier(classDecl) else {
            context.diagnose(Diagnostic(node: Syntax(classDecl.name), message: WireletObservableDiagnostic.notAFinalClass))
            return []
        }
        guard hasObservableAttribute(classDecl) else {
            context.diagnose(Diagnostic(node: Syntax(classDecl.name), message: WireletObservableDiagnostic.missingObservableAttribute))
            return []
        }
        let className = type.trimmed.description
        let properties = WireletObservableProperty.collect(classDecl)
            .filter { !$0.isIgnored }

        var bridges: [String] = []
        for property in properties {
            switch property.kind {
            case .primitive(let jniType, _):
                bridges.append(renderPrimitiveBridge(
                    className: className, property: property, jniType: jniType
                ))
            case .string:
                bridges.append(renderStringBridge(className: className, property: property))
            case .wireFormat, .wireFormatArray, .optionalPrimitive, .optionalString, .optionalWireFormat:
                // Task 11.
                continue
            }
        }

        let body: DeclSyntax = """
        extension \(type.trimmed) {
            #if os(Android)
            \(raw: bridges.joined(separator: "\n    "))
            #endif
        }
        """
        guard let ext = body.as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    private static func renderPrimitiveBridge(
        className: String,
        property: WireletObservableProperty,
        jniType: String
    ) -> String {
        let returnExpr: String = {
            switch property.swiftTypeText {
            case "Bool": return "jboolean(snapshot ? 1 : 0)"
            default:    return "\(jniType)(snapshot)"
            }
        }()
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
            public static func __\(property.name)_track_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
                _ self_ptr: jlong,
                _ on_change: jobject?
            ) -> \(jniType) {
                let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
                let runnable = JObject(env: env, jobject: on_change)
                let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                    runnable?.call(method: "run")
                }
                return \(returnExpr)
            }
        """
    }

    private static func renderStringBridge(
        className: String,
        property: WireletObservableProperty
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
            public static func __\(property.name)_track_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
                _ self_ptr: jlong,
                _ on_change: jobject?
            ) -> jstring? {
                guard let env, let envValue = env.pointee else { return nil }
                let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
                let runnable = JObject(env: env, jobject: on_change)
                let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                    runnable?.call(method: "run")
                }
                return snapshot.withCString { cstr in
                    envValue.pointee.NewStringUTF(env, cstr)
                }
            }
        """
    }

    private static func hasFinalModifier(_ decl: ClassDeclSyntax) -> Bool {
        decl.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
    }

    private static func hasObservableAttribute(_ decl: ClassDeclSyntax) -> Bool {
        decl.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription == "Observable"
        }
    }
}
