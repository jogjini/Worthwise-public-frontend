import SwiftUI

/// The disclosure behind the photo-analysis consent decision.
///
/// App Store Guideline 5.1.2(i), as amended 13 Nov 2025, requires that before
/// personal data is shared with third parties, including third-party AI, the
/// app **clearly discloses it** and **gets permission first**. This view is the
/// disclosure; the buttons that wrap it are the permission.
///
/// Plain language first: `summary` is the one sentence shown above everything
/// else (O3 and the "What We Send" sheet); the rows are the details.
///
/// Recipients are **named** (12 Oct run, bug 10: the photo upload to SerpApi
/// for Google Lens was not disclosed). Keep this list, the server's actual
/// providers and the Privacy Policy (collectible-proxy/public/privacy.html) in
/// sync whenever a provider is added or removed (GDPR Art. 13/15).
///
/// It is shown in two places — the first-run gate and the Settings sheet — and
/// deliberately lives in one file so the two can never say different things.
///
/// Copy rule: state only what is verifiable. Claims about a provider's
/// retention or model-training policy belong here only if they match that
/// provider's current terms for the tier this app actually uses.
struct AIConsentExplanation: View {
    /// The one-sentence summary, read before the details.
    static let summary = "We send your photo to AI and image-search services to identify it. It isn't linked to you, and we don't keep it."

    var body: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            WWInfoRow(
                icon: "photo.on.rectangle.angled",
                title: "Your photo goes to AI and image search",
                detail: "To identify an item, we send your photo to AI services from Google and OpenAI, which describe what's in it. It also goes to SerpApi, which runs a Google Lens image search, and to eBay's image search, to find matching items."
            )

            WWInfoRow(
                icon: "person.crop.circle.badge.xmark",
                title: "Nothing is attached to you",
                detail: "No name, email or account ID travels with the photo, and our server doesn't keep it once your result comes back. Each company then handles it under that company's rules for business customers."
            )

            WWInfoRow(
                icon: "tag",
                title: "Prices come from marketplaces",
                detail: "To check prices, we search marketplaces and price guides with a text description of the item, not your photo. Only the image searches above use the photo."
            )

            WWInfoRow(
                icon: "iphone.gen3",
                title: "If you say no",
                detail: "The app still opens and reads text and barcodes on this iPhone, but it can't identify items or check prices. You can turn analysis on any time in Settings."
            )
        }
    }
}

/// The "What We Send" sheet reachable from Settings, so the disclosure stays
/// available after first run: the guideline requires consent to be revocable
/// on an informed basis, not just grantable once.
///
/// Brand level None (02): neutral, no Lapis. Header in content, untitled
/// inline bar with Done (05 §2.24, §3.7).
struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WW.Space.xl) {
                    header
                    AIConsentExplanation()
                        .wwCard()
                    links
                }
                .padding(.horizontal, WW.margin(for: dynamicTypeSize))
                .padding(.top, WW.Space.xs)
                .padding(.bottom, WW.Space.xxxl)
            }
            .wwSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.wwBarTextProminent)
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(WW.text)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            WWSheetHeader(title: "What We Send")
            Text(AIConsentExplanation.summary)
                .wwFont(.body)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            Text("Our Privacy Policy lists every company we work with.")
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: WW.Space.xs) {
                Link(destination: AppConfig.privacyURL) {
                    Text("Privacy Policy")
                        .underline()
                        .foregroundStyle(WW.text)
                        .frame(minHeight: WW.Size.minTarget)
                }
                .accessibilityHint("Opens in Safari")
                Text("·")
                    .foregroundStyle(WW.tertiaryText)
                    .accessibilityHidden(true)
                Link(destination: AppConfig.termsURL) {
                    Text("Terms of Use")
                        .underline()
                        .foregroundStyle(WW.text)
                        .frame(minHeight: WW.Size.minTarget)
                }
                .accessibilityHint("Opens in Safari")
            }
            .wwFont(.subhead, weight: .semibold)
        }
    }
}
