//
//  Created by Alex.M on 20.06.2022.
//

import SwiftUI
import Kingfisher

struct AttachmentsPage: View {

    @EnvironmentObject var mediaPagesViewModel: FullscreenMediaPagesViewModel
    @Environment(\.chatTheme) private var theme

    let attachment: Attachment

    var body: some View {
        if attachment.type == .image {
            if isGifURL(attachment.full) {
                KFAnimatedImage(attachment.full)
                    .configure { $0.contentMode = .scaleAspectFit }
                    .placeholder {
                        ActivityIndicator()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CachedAsyncImage(
                    url: attachment.full,
                    cacheKey: attachment.fullCacheKey
                ) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    default:
                        ActivityIndicator()
                    }
                }
            }
        } else if attachment.type == .video {
            VideoView(viewModel: VideoViewModel(attachment: attachment))
        } else {
            Rectangle()
                .foregroundColor(Color.gray)
                .frame(minWidth: 100, minHeight: 100)
                .frame(maxHeight: 200)
                .overlay {
                    Text("Unknown", bundle: .module)
                }
        }
    }

    private func isGifURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "gif" || url.absoluteString.lowercased().contains(".gif")
    }
}
