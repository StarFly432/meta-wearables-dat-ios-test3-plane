import SwiftUI
import MWDATDisplay

/// A simple wrapper that adapts a SwiftUI `View` to `DisplayableView`
/// so it can be sent to a `Display` capability.
public struct DisplayView<V: View>: DisplayableView {
  public let content: V

  public init(_ content: V) {
    self.content = content
  }

  // DisplayableView conformance by exposing a body as SwiftUI content
  public var body: some View {
    content
  }
}
