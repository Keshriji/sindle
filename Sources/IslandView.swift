import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The icons down the right edge of the wide dashboard. Each one swaps what the right-hand column shows.
enum RailItem: CaseIterable, Identifiable {
    case weather, calendar, clock, tasks, notes, status, diary, typing, wallpapers, mini
    var id: Self { self }
    var icon: String {
        switch self {
        case .weather: return "cloud.sun.fill"; case .calendar: return "calendar"; case .clock: return "timer"
        case .tasks: return "checklist"; case .notes: return "note.text"; case .status: return "headphones"
        case .diary: return "chart.bar.fill"; case .typing: return "keyboard"; case .wallpapers: return "photo.on.rectangle"
        case .mini: return "square.grid.2x2"
        }
    }
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
    @State private var expanded = false        // false: the compact card, true: the wide dashboard
    @State private var cardPage = 0            // compact card pages: 0 music, 1 weather, 2 mirror
    @State private var tab = 0                 // dashboard tabs: 0 Now, 1 Tray
    @State private var rail = RailItem.weather
    @State private var mirrorOn = false
    @State private var scrollMonitor: Any?
    @State private var lastStep = Date.distantPast

    private var w: CGFloat {
        if open { return expanded ? 660 : 420 }
        if peek { return 310 }
        let n = IslandPanel.notchWidth                    // wings sit either side of the camera housing
        if let t = status.toast { return n + (t.battery != nil || t.level != nil ? 130 : 230) }
        return player.track == nil ? n : n + 110
    }
    private var h: CGFloat { open ? (expanded ? 226 : 152) : (peek ? 72 : 34) }
    private var radius: CGFloat { (open || peek) ? 28 : 14 }
    private var glassMaterial: Material { [Material.ultraThinMaterial, .thinMaterial, .regularMaterial, .thickMaterial][min(max(settings.glassMaterial, 0), 3)] }
    private var spring: Animation { .spring(response: 0.42 / settings.animSpeed, dampingFraction: 0.74) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Group {
                    if open {
                        // The open island is frosted glass: wallpaper shows through, with a bright rim.
                        Rectangle().fill(.ultraThinMaterial)
                            .overlay(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03), .black.opacity(0.22)],
                                                    startPoint: .top, endPoint: .bottom))
                            .environment(\.colorScheme, .dark)
                    } else if settings.glassStyle {
                        Rectangle().fill(glassMaterial).overlay(Color.black.opacity(settings.glassTint)).environment(\.colorScheme, .dark)
                    } else { Rectangle().fill(.black) }
                }
                content.padding(.horizontal, open ? 0 : 12)
            }
            .frame(width: w, height: h)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: settings.floatingIsland ? radius : 0,
                                              bottomLeadingRadius: radius, bottomTrailingRadius: radius,
                                              topTrailingRadius: settings.floatingIsland ? radius : 0))
            .overlay {
                if open {
                    UnevenRoundedRectangle(topLeadingRadius: settings.floatingIsland ? radius : 0,
                                           bottomLeadingRadius: radius, bottomTrailingRadius: radius,
                                           topTrailingRadius: settings.floatingIsland ? radius : 0)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08), .white.opacity(0.3)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
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
                if over { withAnimation(spring) { open = true; expanded = true; tab = 1 } }
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
        .onChange(of: open) { _, o in
            if o {
                expanded = settings.bigIsland; tab = 0; cardPage = 0
                watchOpenIsland()
            } else {
                mirrorOn = false                 // the camera goes off as soon as the island closes
                face.lock()
                if !peek { stopWatching() }
            }
        }
        .onChange(of: peek) { _, v in
            if v { watchOpenIsland() } else if !open { stopWatching() }
        }
        .onDisappear { stopWatching(); stopScroll() }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true }
            startScroll()
        }
        .onChange(of: player.track?.title) { _, _ in
            coverBump = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { coverBump = false }
            if let t = player.track { lyrics.load(title: t.title, artist: t.artist) }
        }
    }

    // MARK: keep the island from hanging open

    @State private var hoverWatch: Timer?

    /// Where the island currently is on screen, in the bottom-left coordinates NSEvent reports.
    private var islandOnScreen: CGRect? {
        guard let f = NSScreen.main?.frame else { return nil }
        let width = w * settings.islandScale
        let height = h * settings.islandScale
        let top = f.maxY - (settings.floatingIsland ? 10 : 0)
        return CGRect(x: f.midX - width / 2, y: top - height, width: width, height: height)
    }

    /// macOS only delivers the hover exit while this app is active, so a missed exit used to leave
    /// the island open over everything. While it is open, look at the pointer itself.
    private func watchOpenIsland() {
        guard hoverWatch == nil else { return }
        hoverWatch = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async { closeIfPointerLeft() }
        }
    }

    private func closeIfPointerLeft() {
        guard open || peek, !pinned, !dropping else { return }
        guard let box = islandOnScreen else { return }
        guard !box.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
        withAnimation(spring) { open = false; peek = false }
    }

    private func stopWatching() { hoverWatch?.invalidate(); hoverWatch = nil }

    // MARK: two-finger swipe between pages

    /// A sideways two-finger swipe steps to the next page, the way Needle moves between them. A
    /// local monitor is enough here: the island is this app's own window, so its events come to us.
    private func startScroll() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            handleScroll(e)
            return e
        }
    }

    private func stopScroll() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        scrollMonitor = nil
    }

    /// One page per gesture: a swipe arrives as a stream of small deltas, so only the first one
    /// after a short pause is allowed to move.
    private func handleScroll(_ e: NSEvent) {
        guard open, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY), abs(e.scrollingDeltaX) > 2 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastStep) > 0.35 else { return }
        lastStep = now
        step(e.scrollingDeltaX < 0 ? 1 : -1)
    }

    @ViewBuilder private func gate<V: View>(_ v: V) -> some View {
        if settings.faceLockOn && !face.unlocked { LockedPage(face: face) } else { v }
    }

    /// A swipe moves between the compact card's pages, or down the dashboard's icon rail.
    private func step(_ d: Int) {
        if expanded {
            let all = RailItem.allCases
            guard let i = all.firstIndex(of: rail) else { return }
            let n = max(0, min(all.count - 1, i + d))
            withAnimation(spring) { rail = all[n] }
        } else {
            withAnimation(spring) { cardPage = max(0, min(2, cardPage + d)) }
        }
    }

    @ViewBuilder private var content: some View {
        if open {
            let t = player.track ?? Track(title: "Nothing playing")
            if expanded { dashboard(t) } else { compactCard(t) }
        } else if peek, let t = player.track {
            peekView(t)
        } else if let toast = status.toast {
            toastView(toast)
        } else if let t = player.track {
            compact(t)
        }
    }

    // MARK: the compact card (open, not expanded)

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.14)))
        }
        .buttonStyle(PressScale())
    }

    private func cover(_ t: Track, _ size: CGFloat) -> some View {
        Group {
            if settings.turntable {
                TurntableView(url: t.artworkURL, size: size, playing: t.isPlaying)
            } else {
                AsyncImage(url: t.artworkURL) { $0.resizable().scaledToFill() }
                    placeholder: { Color.gray.opacity(0.3).overlay(reel(size * 0.5)) }
                    .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.18))
            }
        }
        .scaleEffect(coverBump ? 1.08 : 1).animation(.spring(response: 0.3, dampingFraction: 0.5), value: coverBump)
    }

    private func pauseButton(_ t: Track) -> some View {
        Button { player.send("playpause") } label: {
            Image(systemName: t.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 26)).foregroundStyle(.white)
                .frame(width: 34, height: 30)
        }
        .buttonStyle(PressScale())
    }

    private func notchTime(_ s: Double) -> String {
        let v = Int(max(0, s))
        return String(format: "%d:%02d", v / 60, v % 60)
    }

    /// Elapsed time, a bar, and the length: the bar glides because it is drawn four times a second from the last reading.
    private func progressRow(_ t: Track) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { tl in
            let since: Double = t.isPlaying ? tl.date.timeIntervalSince(t.polledAt) : 0
            let pos: Double = min(t.duration, t.position + since)
            let frac: CGFloat = CGFloat(min(1.0, pos / max(t.duration, 1)))
            HStack(spacing: 8) {
                Text(notchTime(pos)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(.white.opacity(0.92)).frame(width: g.size.width * frac)
                    }
                }
                .frame(height: 4)
                Text(notchTime(t.duration)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func eqView(_ t: Track) -> some View {
        Group {
            if settings.eqOn {
                EqualizerBars(audio: audio, playing: t.isPlaying, count: settings.eqBars, rainbow: settings.eqColorMode == 1, gain: settings.eqSensitivity)
            }
        }
    }

    private func controls(_ t: Track, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ctl("backward.fill", "previous track")
            pauseButton(t)
            ctl("forward.fill", "next track")
        }
    }

    private func compactCard(_ t: Track) -> some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(.white.opacity(cardPage == i ? 0.95 : 0.35))
                            .frame(width: cardPage == i ? 18 : 6, height: 6)
                            .onTapGesture { withAnimation(spring) { cardPage = i } }
                    }
                }
                Spacer()
                iconButton("arrow.up.left.and.arrow.down.right") { withAnimation(spring) { expanded = true } }
            }
            .padding(.horizontal, 14).padding(.top, 8).frame(height: 30)

            Group {
                switch cardPage {
                case 1:  weatherMini
                case 2:  MirrorPage()
                default: musicMini(t)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        }
    }

    private func musicMini(_ t: Track) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                cover(t, 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(t.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer()
                eqView(t)
            }
            progressRow(t)
            ZStack {
                controls(t, spacing: 36)
                HStack {
                    Spacer()
                    Button { withAnimation(spring) { expanded = true } } label: {
                        Image(systemName: "laptopcomputer").font(.system(size: 15)).foregroundStyle(.white.opacity(0.75))
                    }.buttonStyle(PressScale())
                }
            }
        }
    }

    private var weatherMini: some View {
        HStack(spacing: 14) {
            Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 42))
            VStack(alignment: .leading, spacing: 2) {
                Text(weather.now.map { "\(settings.temp($0))°" } ?? "–").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                Text(weather.now == nil ? (weather.error ?? "Loading…") : weather.rainNote)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let hi = weather.high, let lo = weather.low {
                    Text("↑\(settings.temp(hi))°  ↓\(settings.temp(lo))°").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                }
                if let place = weather.place { Text(place).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)) }
            }
        }
    }

    // MARK: the wide dashboard (open and expanded)

    private func tabPill(_ label: String, _ icon: String, _ index: Int) -> some View {
        Button { withAnimation(spring) { tab = index } } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(tab == index ? 1 : 0.6))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(tab == index ? 0.22 : 0)))
        }
        .buttonStyle(.plain)
    }

    private var columnDivider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: 1).padding(.vertical, 8)
    }

    private func dashboard(_ t: Track) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                tabPill("Now", "house.fill", 0)
                tabPill("Tray", "tray.fill", 1)
                Spacer()
                iconButton(pinned ? "pin.fill" : "pin") { settings.keepOpen.toggle() }
                iconButton("arrow.down.right.and.arrow.up.left") { withAnimation(spring) { expanded = false } }
            }
            .padding(.horizontal, 14).padding(.top, 8).frame(height: 32)

            if tab == 0 {
                HStack(spacing: 0) {
                    musicColumn(t).frame(width: 256)
                    columnDivider
                    mirrorColumn.frame(width: 150)
                    columnDivider
                    railContent
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    railBar
                }
                .padding(.horizontal, 6).padding(.bottom, 10)
            } else {
                gate(TrayPage(tray: tools.tray)).padding(.horizontal, 18).padding(.bottom, 12)
            }
        }
    }

    private func musicColumn(_ t: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                cover(t, 70)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(t.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer(minLength: 0)
                eqView(t)
            }
            HStack(spacing: 22) {
                controls(t, spacing: 24)
                LikeButton(diary: tools.diary, track: t)
            }
            .padding(.leading, 80)
            progressRow(t)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }

    /// The round Mirror button: tap it and the camera appears inside the circle; tap again to switch it off.
    private var mirrorColumn: some View {
        Button { withAnimation(spring) { mirrorOn.toggle() } } label: {
            ZStack {
                Circle().fill(.white.opacity(0.10))
                if mirrorOn {
                    MirrorCircle().clipShape(Circle()).padding(3)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "web.camera").font(.system(size: 24))
                        Text("Mirror").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
                Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1)
            }
            .frame(width: 106, height: 106)
        }
        .buttonStyle(PressScale())
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var railContent: some View {
        switch rail {
        case .weather:    weatherCard
        case .calendar:   CalendarPage()
        case .clock:      ClockPage(clock: tools.clock)
        case .tasks:      gate(TasksPage(tasks: tools.tasks))
        case .notes:      gate(NotesPage(notes: tools.notes))
        case .status:     statusPage
        case .diary:      gate(DiaryPage(diary: tools.diary))
        case .typing:     TypingPage(typing: tools.typing)
        case .wallpapers: WallpapersPage()
        case .mini:       MiniAppsPage(mini: tools.mini)
        }
    }

    private var railBar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(RailItem.allCases) { item in
                    Button { withAnimation(spring) { rail = item } } label: {
                        Image(systemName: item.icon).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(rail == item ? 1 : 0.6))
                            .frame(width: 30, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(rail == item ? 0.22 : 0)))
                    }
                    .buttonStyle(PressScale())
                }
            }
        }
        .frame(width: 38)
    }

    private var placeSuffix: String {
        guard let place = weather.place else { return "" }
        return "  ·  " + place
    }

    /// Current weather, high and low, whether rain is coming, and the next six days.
    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 34))
                Text(weather.now.map { "\(settings.temp($0))°" } ?? "–").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(weather.now == nil ? (weather.error ?? "Loading…") : weather.rainNote)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    if let hi = weather.high, let lo = weather.low {
                        Text("↑\(settings.temp(hi))°  ↓\(settings.temp(lo))°\(placeSuffix)")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(weather.daily) { d in
                    VStack(spacing: 4) {
                        Text("\(d.id)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                        Image(systemName: d.symbol).symbolRenderingMode(.multicolor).font(.system(size: 17))
                        Text("\(settings.temp(d.high))°").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Weather: MET Norway").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
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

    /// Pop-ups live on the two sides of the notch: icon on the left, value on the right.
    private func toastView(_ toast: Toast) -> some View {
        HStack(spacing: 0) {
            if let b = toast.battery { BatteryView(percent: b, charging: toast.charging) }
            else if let lv = toast.level {
                Image(systemName: toast.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .symbolEffect(.bounce, value: lv)
            }
            else if toast.icon == "alarm.fill" { ShakeIcon(name: toast.icon) }
            else { PopIcon(name: toast.icon) }
            Spacer(minLength: 8)
            if let b = toast.battery {
                Text("\(b)%").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).contentTransition(.numericText())
            } else if let lv = toast.level {
                HUDBar(level: lv)
            } else {
                Text(toast.text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private func compact(_ t: Track) -> some View {
        // Left: the cover turning like a record. Right: the equalizer. No title here, which is what
        // used to show up as stray text beside the bars.
        HStack(spacing: 0) {
            CDDisc(url: t.artworkURL, size: 26, playing: t.isPlaying)
            Spacer(minLength: 8)
            if settings.eqOn {
                EqualizerBars(audio: audio, playing: t.isPlaying, count: settings.eqBars, rainbow: settings.eqColorMode == 1, gain: settings.eqSensitivity)
            } else {
                Image(systemName: "waveform").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var statusPage: some View {
        VStack(spacing: 10) {
            if let h = status.headphones {
                HStack(spacing: 6) {
                    TurningAirPods(level: h.left ?? h.main)
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
}
