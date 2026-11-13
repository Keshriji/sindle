import SwiftUI
import UniformTypeIdentifiers

enum Page: Int, CaseIterable {
    case player, lyrics, weather, status, tray, notes, tasks, clock, wallpapers, typing, diary, mirror
    static let main: [Page] = [.player, .lyrics, .weather, .status]
    static let tools: [Page] = [.tray, .notes, .tasks, .clock, .wallpapers, .typing, .diary, .mirror]
    var isTool: Bool { Page.tools.contains(self) }
    var icon: String { ["music.note", "text.quote", "cloud.sun.fill", "headphones", "tray.full", "note.text", "checklist", "alarm", "photo.on.rectangle", "keyboard", "chart.bar.fill", "camera.fill"][rawValue] }
}

struct IslandView: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var weather: WeatherStore
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var status: StatusStore
    let tools: Tools
    let audio: AudioLevel      // only the equalizer observes it, so audio ticks do not re-render the island
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var face = FaceLock.shared
    private var pinned: Bool { settings.keepOpen }
    @State private var dropping = false
    @State private var open = false
    @State private var spin = false
    @State private var peek = false
    @State private var coverBump = false
    @State private var page = Page.player

    private var w: CGFloat { open ? 380 : (peek ? 310 : status.toast != nil ? 300 : (player.track == nil ? 190 : 250)) }
    private var h: CGFloat { open ? 160 : (peek ? 72 : 34) }
    private var radius: CGFloat { (open || peek) ? 28 : 14 }
    private var glassMaterial: Material { [Material.ultraThinMaterial, .thinMaterial, .regularMaterial, .thickMaterial][min(max(settings.glassMaterial, 0), 3)] }
    private var spring: Animation { .spring(response: 0.42 / settings.animSpeed, dampingFraction: 0.74) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Group {
                    if settings.glassStyle {
                        Rectangle().fill(glassMaterial).overlay(Color.black.opacity(settings.glassTint)).environment(\.colorScheme, .dark)
                    } else { Rectangle().fill(.black) }
                }
                content.padding(.horizontal, open ? 18 : 12).padding(.top, open ? 12 : 0)
            }
            .frame(width: w, height: h)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: settings.floatingIsland ? radius : 0,
                                              bottomLeadingRadius: radius, bottomTrailingRadius: radius,
                                              topTrailingRadius: settings.floatingIsland ? radius : 0))
            .offset(y: settings.floatingIsland ? 10 : 0)
            .scaleEffect(settings.islandScale, anchor: .top)
            .opacity(settings.hideWhenIdle && player.track == nil && status.toast == nil && !open ? 0.0 : 1.0)
            .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: NSURL.self) { obj, _ in
                        if let n = obj as? NSURL { DispatchQueue.main.async { tools.tray.add([n as URL]) } }
                    }
                }
                return true
            }
            .onChange(of: dropping) { _, over in
                if over { withAnimation(spring) { open = true; page = .tray } }
            }
            .onHover { hovering in
                if settings.openOnClick {
                    withAnimation(spring) {
                        if !hovering && !pinned { open = false }
                        peek = hovering && !open && player.track != nil
                    }
                    return
                }
                if !hovering && pinned { return }
                withAnimation(spring) { open = hovering }
            }
            .onTapGesture {
                if settings.openOnClick && !open { withAnimation(spring) { open = true; peek = false } }
            }
            .gesture(DragGesture(minimumDistance: 24).onEnded { v in
                guard open else { return }
                step(v.translation.width < 0 ? 1 : -1)
            })
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: status.toast)
        .onChange(of: open) { _, o in if !o { face.lock() } }
        .onAppear { withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true } }
        .onChange(of: player.track?.title) { _, _ in
            coverBump = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { coverBump = false }
            if let t = player.track { lyrics.load(title: t.title, artist: t.artist) }
        }
    }

    @ViewBuilder private func gate<V: View>(_ v: V) -> some View {
        if settings.faceLockOn && !face.unlocked { LockedPage(face: face) } else { v }
    }

    private func step(_ d: Int) {
        let n = max(0, min(Page.allCases.count - 1, page.rawValue + d))
        withAnimation(spring) { page = Page(rawValue: n)! }
    }

    @ViewBuilder private var content: some View {
        if open {
            let t = player.track ?? Track(title: "Nothing playing")
            VStack(spacing: 8) {
                ZStack {
                    switch page {
                    case .player:  playerPage(t)
                    case .lyrics:  lyricsPage(t)
                    case .weather: weatherPage
                    case .status:  statusPage
                    case .tray:    gate(TrayPage(tray: tools.tray))
                    case .notes:   gate(NotesPage(notes: tools.notes))
                    case .tasks:   gate(TasksPage(tasks: tools.tasks))
                    case .clock:   ClockPage(clock: tools.clock)
                    case .wallpapers: WallpapersPage()
                    case .typing:  TypingPage(typing: tools.typing)
                    case .diary:   gate(DiaryPage(diary: tools.diary))
                    case .mirror:  MirrorPage()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .frame(maxHeight: .infinity)
                tabs
            }.padding(.bottom, 8)
        } else if peek, let t = player.track {
            peekView(t)
        } else if let toast = status.toast {
            HStack(spacing: 8) {
                if let b = toast.battery { BatteryView(percent: b, charging: toast.charging) }
                else if toast.icon == "alarm.fill" { ShakeIcon(name: toast.icon) }
                else { PopIcon(name: toast.icon) }
                Text(toast.text).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            }
            .frame(height: 34).transition(.opacity)
        } else if let t = player.track {
            compact(t)
        }
    }

    // MARK: pages
    private func reel(_ size: CGFloat) -> some View {
        Image(systemName: "opticaldisc.fill").resizable().frame(width: size, height: size)
            .foregroundStyle(.white.opacity(0.9)).rotationEffect(.degrees(spin ? 360 : 0))
    }

    /// Album cover cut like a little record, so the left of the notch turns while the music plays.
    private func disc(_ t: Track, _ size: CGFloat) -> some View {
        ZStack {
            AsyncImage(url: t.artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
                .frame(width: size, height: size).clipShape(Circle())
            Circle().fill(.black).frame(width: size * 0.18)      // spindle hole
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 0.5))
        .clipShape(Circle())
        .rotationEffect(.degrees(spin ? 360 : 0))
    }

    private func peekView(_ t: Track) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: t.artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(coverBump ? 1.12 : 1).animation(.spring(response: 0.3, dampingFraction: 0.5), value: coverBump)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(t.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            ctl("playpause.fill", "playpause")
        }.padding(.horizontal, 14).frame(height: 72)
    }

    private func compact(_ t: Track) -> some View {
        // Left: the cover turning like a record. Right: the equalizer. No title here, which is what
        // used to show up as stray text beside the bars.
        HStack(spacing: 0) {
            disc(t, 24)
            Spacer(minLength: 8)
            if settings.eqOn {
                EqualizerBars(audio: audio, playing: true, count: settings.eqBars, rainbow: settings.eqColorMode == 1, gain: settings.eqSensitivity)
            } else {
                Image(systemName: "waveform").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private func playerPage(_ t: Track) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                AsyncImage(url: t.artworkURL) { $0.resizable().scaledToFill() }
                    placeholder: { Color.gray.opacity(0.3).overlay(reel(26)) }
                    .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 10))
                    .scaleEffect(coverBump ? 1.12 : 1).animation(.spring(response: 0.3, dampingFraction: 0.5), value: coverBump)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(t.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer()
                if settings.eqOn {
                    EqualizerBars(audio: audio, playing: true, count: settings.eqBars, rainbow: settings.eqColorMode == 1, gain: settings.eqSensitivity)
                }
            }
            ProgressView(value: min(t.position / t.duration, 1)).tint(.white)
                .animation(.linear(duration: 1), value: t.position)
            HStack(spacing: 28) {
                ctl("backward.fill", "previous track")
                ctl("playpause.fill", "playpause")
                ctl("forward.fill", "next track")
            }
        }
    }

    private func lyricsPage(_ t: Track) -> some View {
        let i = lyrics.index(at: t.position)
        let cur = i.map { lyrics.lines[$0].s } ?? (lyrics.lines.isEmpty ? "No synced lyrics found" : "…")
        let next = i.flatMap { $0 + 1 < lyrics.lines.count ? lyrics.lines[$0 + 1].s : nil } ?? ""
        return VStack(spacing: 6) {
            Text(cur.isEmpty ? "♪" : cur)
                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(2)
                .id(i ?? -1)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
            Text(next).font(.system(size: 12)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.35), value: i)
    }

    private var weatherPage: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(weather.now.map { "\(settings.temp($0))°" } ?? "–")
                    .font(.system(size: 32, weight: .semibold)).foregroundStyle(.white)
                if let place = weather.place {
                    Text(place).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                if weather.now == nil {
                    Text(weather.error ?? "Loading…").font(.system(size: 10)).foregroundStyle(.orange)
                }
            }
            HStack {
                ForEach(weather.hours) { h in
                    VStack(spacing: 2) {
                        Text("\(settings.temp(h.temp))°").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        Text(h.hour).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }.frame(maxWidth: .infinity)
                }
            }
            Text("Weather: MET Norway").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
        }
    }

    private var statusPage: some View {
        VStack(spacing: 10) {
            if let h = status.headphones {
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                    Text(h.name).lineLimit(1)
                    Spacer()
                }.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                HStack(spacing: 14) {
                    level("L", h.left ?? h.main)
                    level("R", h.right)
                    level("Case", h.caseLevel)
                }
            } else {
                Text("No headphones connected").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    BatteryView(percent: status.batteryPercent ?? 0, charging: status.charging)
                    Text(status.batteryPercent.map { "\($0)%" } ?? "–").font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(.white.opacity(0.14)))
                if let f = status.focus { chip("moon.fill", f) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func level(_ label: String, _ v: Int?) -> some View {
        if let v {
            VStack(spacing: 3) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(v < 20 ? Color.red : Color.white).frame(width: 64 * CGFloat(v) / 100)
                }.frame(width: 64, height: 6).animation(spring, value: v)
                Text("\(label) \(v)%").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.14)))
    }

    // MARK: controls
    private func ctl(_ icon: String, _ cmd: String) -> some View {
        Button { player.send(cmd) } label: { Image(systemName: icon).foregroundStyle(.white) }.buttonStyle(PressScale())
    }

    private var tabs: some View {
        HStack(spacing: 14) {
            Button { settings.keepOpen.toggle() } label: {
                Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 10))
                    .foregroundStyle(.white.opacity(pinned ? 1 : 0.35))
            }.buttonStyle(.plain)
            if page.isTool { tabButton("chevron.left", on: false) { page = .player } }
            ForEach(page.isTool ? Page.tools : Page.main, id: \.self) { p in
                tabButton(p.icon, on: page == p) { page = p }
            }
            if !page.isTool { tabButton("square.grid.2x2", on: false) { page = .tray } }   // opens the tools row
        }
    }

    private func tabButton(_ icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(spring) { action() } } label: {
            Image(systemName: icon).font(.system(size: 11))
                .foregroundStyle(.white.opacity(on ? 1 : 0.4))
                .scaleEffect(on ? 1.2 : 1)
        }.buttonStyle(.plain)
    }
}
