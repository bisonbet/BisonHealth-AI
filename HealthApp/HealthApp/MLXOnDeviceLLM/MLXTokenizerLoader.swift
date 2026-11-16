//
//  MLXTokenizerLoader.swift
//  HealthApp
//
//  Adapts swift-transformers tokenizers to mlx-swift-lm 3.x.
//

import Foundation
import MLXLMCommon
import Tokenizers

// MARK: - Tokenizer Loader

/// Loads a model folder's tokenizer with swift-transformers, the implementation mlx-swift-lm 2.x
/// used internally.
///
/// mlx-swift-lm 3.x no longer bundles a tokenizer; it takes any `TokenizerLoader`. Its
/// `MLXHuggingFace` macros generate exactly this adapter, but they pull in swift-syntax and
/// need macro trust in every `xcodebuild` invocation, CI included. Writing the dozen lines
/// out avoids both. The models are always loaded from a local directory the download manager
/// wrote, so no `Downloader` is needed.
struct MLXTokenizerLoader: MLXLMCommon.TokenizerLoader {

    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

// MARK: - Local-Only Downloader

/// The `Downloader` handed to mlx-swift-lm for loads that must never touch the network.
///
/// mlx-swift-lm 3.x only offers `loadContainer(from:using:configuration:)` with a downloader,
/// and the directory-only overload drops the configuration, which is where `extraEOSTokens`
/// lives — MediPhi runs on into invented turns without `<|end|>`. A `.directory`
/// configuration resolves locally and never calls `download`; if a future library version
/// ever did, this fails loudly instead of fetching from the Hub in the background.
struct MLXLocalOnlyDownloader: MLXLMCommon.Downloader {

    struct NetworkLoadRefused: LocalizedError {
        let id: String
        var errorDescription: String? {
            "Refused to download \(id) while loading a model; on-device models load from local files only."
        }
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        throw NetworkLoadRefused(id: id)
    }
}

// MARK: - Tokenizer Bridge

/// `MLXLMCommon.Tokenizer` over a swift-transformers tokenizer.
private struct TokenizerBridge: MLXLMCommon.Tokenizer {

    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    // swift-transformers names the argument `tokens`, not `tokenIds`.
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
