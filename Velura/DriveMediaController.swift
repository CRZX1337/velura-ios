import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

enum DriveMediaSource: String, CaseIterable, Identifiable {
    case appleMusic = "appleMusic"
    case spotify = "spotify"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }

    var symbol: String {
        switch self {
        case .appleMusic: "music.note"
        case .spotify: "dot.radiowaves.left.and.right"
        }
    }
}

struct NowPlayingSnapshot: Equatable {
    let title: String
    let artist: String
    let isPlaying: Bool
    let artworkImage: UIImage?
    let source: DriveMediaSource
}

enum DriveMediaAvailability: Equatable {
    case ready
    case authorizationRequired
    case denied
    case empty
    case spotifySetupNeeded
}

private struct SpotifyTokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}

private struct SpotifyCurrentlyPlayingResponse: Decodable {
    struct Item: Decodable {
        struct Artist: Decodable { let name: String }
        struct Album: Decodable {
            struct ImageItem: Decodable { let url: String }
            let images: [ImageItem]
        }
        let name: String
        let artists: [Artist]
        let album: Album
    }

    let is_playing: Bool
    let item: Item?
}

enum SpotifyPKCE {
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func makeCodeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

@MainActor
final class DriveMediaController: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var source: DriveMediaSource {
        didSet {
            UserDefaults.standard.set(source.rawValue, forKey: Self.sourceStorageKey)
            if isMonitoring {
                restartMonitoringForCurrentSource()
            }
        }
    }

    @Published private(set) var availability: DriveMediaAvailability = .empty
    @Published private(set) var nowPlaying: NowPlayingSnapshot?
    @Published private(set) var spotifyStatusMessage: String?
    @Published var spotifyClientID: String {
        didSet {
            let trimmed = spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: Self.spotifyClientIDKey)
        }
    }

    private static let sourceStorageKey = "speedometer.driveMode.mediaSource"
    private static let spotifyClientIDKey = "speedometer.spotify.clientID"
    private static let spotifyAccessTokenKey = "speedometer.spotify.accessToken"
    private static let spotifyRefreshTokenKey = "speedometer.spotify.refreshToken"
    private static let spotifyExpiryKey = "speedometer.spotify.tokenExpiry"
    static let spotifyRedirectURI = "velura://spotify-callback"

    private let systemPlayer = MPMusicPlayerController.systemMusicPlayer
    private var observers: [NSObjectProtocol] = []
    private var spotifyPollTask: Task<Void, Never>?
    private var authSession: ASWebAuthenticationSession?
    private var isMonitoring = false
    private var cachedArtworkURL: String?
    private var cachedArtworkImage: UIImage?

    var isSpotifyAppInstalled: Bool {
        guard let url = URL(string: "spotify://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    var isSpotifyConnected: Bool {
        !(UserDefaults.standard.string(forKey: Self.spotifyAccessTokenKey) ?? "").isEmpty
    }

    override init() {
        let savedSource = UserDefaults.standard.string(forKey: Self.sourceStorageKey)
        self.source = DriveMediaSource(rawValue: savedSource ?? "") ?? .appleMusic
        let storedClientID = UserDefaults.standard.string(forKey: Self.spotifyClientIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.spotifyClientID = storedClientID.isEmpty ? Self.bundledClientID : storedClientID
        super.init()
    }

    /// Optional Client ID baked into a private build. Public builds ship without one, so
    /// every user supplies their own via the setup sheet.
    private static var bundledClientID: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func startMonitoring() {
        guard !isMonitoring else {
            refreshState()
            return
        }
        isMonitoring = true
        restartMonitoringForCurrentSource()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        stopAppleMusicObservers()
        spotifyPollTask?.cancel()
        spotifyPollTask = nil
    }

    deinit {
        spotifyPollTask?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func restartMonitoringForCurrentSource() {
        stopAppleMusicObservers()
        spotifyPollTask?.cancel()
        spotifyPollTask = nil
        spotifyStatusMessage = nil

        switch source {
        case .appleMusic:
            startAppleMusicObservers()
            refreshAppleMusicState()
        case .spotify:
            startSpotifyPolling()
        }
    }

    private func startAppleMusicObservers() {
        systemPlayer.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        let playbackObserver = center.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: systemPlayer,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAppleMusicState() }
        }
        let itemObserver = center.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: systemPlayer,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAppleMusicState() }
        }
        observers = [playbackObserver, itemObserver]
    }

    private func stopAppleMusicObservers() {
        guard !observers.isEmpty else { return }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        systemPlayer.endGeneratingPlaybackNotifications()
    }

    func refreshState() {
        switch source {
        case .appleMusic:
            refreshAppleMusicState()
        case .spotify:
            Task { await refreshSpotifyNowPlaying() }
        }
    }

    // MARK: - Apple Music

    func requestAppleMusicAuthorization() {
        Task { @MainActor [weak self] in
            _ = await MusicAuthorization.request()
            self?.refreshAppleMusicState()
        }
    }

    private func refreshAppleMusicState() {
        let status = MusicAuthorization.currentStatus
        switch status {
        case .notDetermined:
            availability = .authorizationRequired
            nowPlaying = nil
        case .denied, .restricted:
            availability = .denied
            nowPlaying = nil
        case .authorized:
            guard let item = systemPlayer.nowPlayingItem else {
                availability = .empty
                nowPlaying = nil
                return
            }
            let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
            let artwork = item.artwork?.image(at: CGSize(width: 96, height: 96))
            let isPlaying = systemPlayer.playbackState == .playing
            nowPlaying = NowPlayingSnapshot(
                title: (title?.isEmpty == false ? title! : "Unknown Track"),
                artist: (artist?.isEmpty == false ? artist! : "Apple Music"),
                isPlaying: isPlaying,
                artworkImage: artwork,
                source: .appleMusic
            )
            availability = .ready
        @unknown default:
            availability = .empty
            nowPlaying = nil
        }
    }

    // MARK: - Spotify PKCE + Web API

    func connectSpotify() {
        let clientID = spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            availability = .spotifySetupNeeded
            spotifyStatusMessage = "Add your own Spotify Client ID to enable live controls."
            return
        }

        let verifier = SpotifyPKCE.makeCodeVerifier()
        let challenge = SpotifyPKCE.makeCodeChallenge(for: verifier)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.spotifyRedirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: "user-read-currently-playing user-read-playback-state user-modify-playback-state")
        ]
        guard let authURL = components?.url else { return }

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "velura") { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.authSession = nil
                if let error {
                    self.spotifyStatusMessage = error.localizedDescription
                    return
                }
                guard let callbackURL,
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
                      let code = items.first(where: { $0.name == "code" })?.value else {
                    self.spotifyStatusMessage = "Spotify authorization was cancelled."
                    return
                }
                await self.exchangeSpotifyCode(code, verifier: verifier, clientID: clientID)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    func disconnectSpotify() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.spotifyAccessTokenKey)
        defaults.removeObject(forKey: Self.spotifyRefreshTokenKey)
        defaults.removeObject(forKey: Self.spotifyExpiryKey)
        cachedArtworkURL = nil
        cachedArtworkImage = nil
        nowPlaying = nil
        availability = .spotifySetupNeeded
        spotifyStatusMessage = nil
    }

    func openSpotifyApp() {
        if let appURL = URL(string: "spotify://"), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = URL(string: "https://open.spotify.com") {
            UIApplication.shared.open(webURL)
        }
    }

    private func exchangeSpotifyCode(_ code: String, verifier: String, clientID: String) async {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: Self.spotifyRedirectURI),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                spotifyStatusMessage = "Spotify token exchange failed. Check Client ID and Redirect URI."
                return
            }
            let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            storeSpotifyTokens(decoded)
            spotifyStatusMessage = nil
            await refreshSpotifyNowPlaying()
        } catch {
            spotifyStatusMessage = "Could not connect to Spotify."
        }
    }

    private func refreshSpotifyTokenIfNeeded() async -> String? {
        let defaults = UserDefaults.standard
        let currentToken = defaults.string(forKey: Self.spotifyAccessTokenKey)
        let expiry = defaults.double(forKey: Self.spotifyExpiryKey)
        if let currentToken, !currentToken.isEmpty, Date().timeIntervalSince1970 < expiry - 60 {
            return currentToken
        }

        let clientID = spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty,
              let refreshToken = defaults.string(forKey: Self.spotifyRefreshTokenKey),
              !refreshToken.isEmpty,
              let url = URL(string: "https://accounts.spotify.com/api/token") else {
            return currentToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            storeSpotifyTokens(decoded)
            return decoded.access_token
        } catch {
            return nil
        }
    }

    private func storeSpotifyTokens(_ token: SpotifyTokenResponse) {
        let defaults = UserDefaults.standard
        defaults.set(token.access_token, forKey: Self.spotifyAccessTokenKey)
        if let refresh = token.refresh_token, !refresh.isEmpty {
            defaults.set(refresh, forKey: Self.spotifyRefreshTokenKey)
        }
        let expiry = Date().timeIntervalSince1970 + Double(token.expires_in)
        defaults.set(expiry, forKey: Self.spotifyExpiryKey)
    }

    private func startSpotifyPolling() {
        spotifyPollTask?.cancel()
        spotifyPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSpotifyNowPlaying()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func refreshSpotifyNowPlaying() async {
        guard isSpotifyConnected else {
            nowPlaying = nil
            availability = .spotifySetupNeeded
            return
        }
        guard let token = await refreshSpotifyTokenIfNeeded(),
              let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else {
            nowPlaying = nil
            availability = .spotifySetupNeeded
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 204 {
                nowPlaying = nil
                availability = .empty
                return
            }
            if http.statusCode == 401 {
                disconnectSpotify()
                return
            }
            guard (200...299).contains(http.statusCode) else { return }
            let payload = try JSONDecoder().decode(SpotifyCurrentlyPlayingResponse.self, from: data)
            guard let item = payload.item else {
                nowPlaying = nil
                availability = .empty
                return
            }

            let artist = item.artists.map(\.name).joined(separator: ", ")
            let artworkURL = item.album.images.last?.url ?? item.album.images.first?.url
            let artwork = await loadArtwork(urlString: artworkURL)
            nowPlaying = NowPlayingSnapshot(
                title: item.name,
                artist: artist.isEmpty ? "Spotify" : artist,
                isPlaying: payload.is_playing,
                artworkImage: artwork,
                source: .spotify
            )
            availability = .ready
        } catch {
            // Keep last valid snapshot on transient network hiccups.
        }
    }

    private func loadArtwork(urlString: String?) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        if cachedArtworkURL == urlString, let cachedArtworkImage {
            return cachedArtworkImage
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                cachedArtworkURL = urlString
                cachedArtworkImage = image
                return image
            }
        } catch { }
        return nil
    }

    private func sendSpotifyPlayerCommand(method: String, path: String) {
        Task { [weak self] in
            guard let self,
                  let token = await self.refreshSpotifyTokenIfNeeded(),
                  let url = URL(string: "https://api.spotify.com/v1/me/player/\(path)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                    self.spotifyStatusMessage = "Spotify Premium is required for remote playback control."
                } else {
                    self.spotifyStatusMessage = nil
                }
            } catch { }
            try? await Task.sleep(nanoseconds: 350_000_000)
            await self.refreshSpotifyNowPlaying()
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        switch source {
        case .appleMusic:
            guard availability == .ready else { return }
            if systemPlayer.playbackState == .playing {
                systemPlayer.pause()
            } else {
                systemPlayer.play()
            }
            refreshAppleMusicState()
        case .spotify:
            guard availability == .ready else { return }
            let playing = nowPlaying?.isPlaying == true
            sendSpotifyPlayerCommand(method: "PUT", path: playing ? "pause" : "play")
        }
    }

    func skipToNext() {
        switch source {
        case .appleMusic:
            guard availability == .ready else { return }
            systemPlayer.skipToNextItem()
            refreshAppleMusicState()
        case .spotify:
            guard availability == .ready else { return }
            sendSpotifyPlayerCommand(method: "POST", path: "next")
        }
    }

    func skipToPrevious() {
        switch source {
        case .appleMusic:
            guard availability == .ready else { return }
            systemPlayer.skipToPreviousItem()
            refreshAppleMusicState()
        case .spotify:
            guard availability == .ready else { return }
            sendSpotifyPlayerCommand(method: "POST", path: "previous")
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
                ?? ASPresentationAnchor()
        }
    }
}
