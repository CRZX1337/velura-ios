import Combine
import Foundation
import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

struct NowPlayingSnapshot: Equatable {
    let title: String
    let artist: String
    let isPlaying: Bool
    let artworkImage: UIImage?
}

enum DriveMediaAvailability: Equatable {
    case ready
    case authorizationRequired
    case denied
    case empty
}

@MainActor
final class DriveMediaController: ObservableObject {
    @Published private(set) var availability: DriveMediaAvailability = .empty
    @Published private(set) var nowPlaying: NowPlayingSnapshot?

    private let systemPlayer = MPMusicPlayerController.systemMusicPlayer
    private var observers: [NSObjectProtocol] = []
    private var isMonitoring = false

    func startMonitoring() {
        guard !isMonitoring else {
            refreshState()
            return
        }
        isMonitoring = true
        systemPlayer.beginGeneratingPlaybackNotifications()

        let center = NotificationCenter.default
        let playbackObserver = center.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: systemPlayer,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshState() }
        }
        let itemObserver = center.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: systemPlayer,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshState() }
        }
        observers = [playbackObserver, itemObserver]
        refreshState()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        systemPlayer.endGeneratingPlaybackNotifications()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func requestAuthorization() {
        Task { @MainActor [weak self] in
            _ = await MusicAuthorization.request()
            self?.refreshState()
        }
    }

    func refreshState() {
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
                artworkImage: artwork
            )
            availability = .ready
        @unknown default:
            availability = .empty
            nowPlaying = nil
        }
    }

    func togglePlayPause() {
        guard availability == .ready else { return }
        if systemPlayer.playbackState == .playing {
            systemPlayer.pause()
        } else {
            systemPlayer.play()
        }
        refreshState()
    }

    func skipToNext() {
        guard availability == .ready else { return }
        systemPlayer.skipToNextItem()
        refreshState()
    }

    func skipToPrevious() {
        guard availability == .ready else { return }
        systemPlayer.skipToPreviousItem()
        refreshState()
    }
}
