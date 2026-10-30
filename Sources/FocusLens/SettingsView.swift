import AppKit
import LensCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let hotKeys: HotKeyManager
    @State private var tab = 0
    @State private var recording: LensAction?
    @State private var recordError: String?
    @State private var resetting = false

    private var preferences: Preferences { model.preferences }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 18) {
                    LensPreview(options: preferences.options)
                        .frame(width: 232, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .accessibilityLabel("Предпросмотр формы и оформления линзы")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Детали — в фокусе.").font(.title3.weight(.semibold))
                        Text("Лупа поверх любого приложения.\nКлики проходят сквозь линзу.")
                            .font(.callout).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    Label(preferences.shortcut(for: .toggle).title, systemImage: "keyboard")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.quaternary, in: Capsule())
                    Text("Нажми, чтобы включить или скрыть лупу.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(width: 232)
                VStack(spacing: 16) {
                    Picker("Раздел", selection: $tab) {
                        Text("Линза").tag(0)
                        Text("Вид").tag(1)
                        Text("Клавиши").tag(2)
                        Text("Доступ").tag(3)
                    }.pickerStyle(.segmented).labelsHidden()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch tab {
                            case 0: lensControls
                            case 1: appearanceControls
                            case 2: shortcutControls
                            default: permissionControls
                            }
                        }.padding(.vertical, 4).padding(.horizontal, 2)
                    }.scrollIndicators(.hidden)
                }.frame(maxWidth: .infinity)
            }.padding(28)
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 16)
            }
            Divider()
            HStack {
                Label("Локально на твоём Mac", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Сбросить настройки…") { resetting = true }.buttonStyle(.plain).font(.caption)
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.2")
                    .font(.caption).foregroundStyle(.tertiary)
            }.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .frame(width: 800, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.mint)
        .onAppear {
            model.refreshPermission()
            if !model.hasPermission { tab = 3 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermission()
        }
        .sheet(item: $recording) { action in recorderSheet(action) }
        .confirmationDialog("Вернуть исходные настройки и сочетания клавиш?", isPresented: $resetting) {
            Button("Сбросить") { preferences.reset(); registerShortcuts() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "viewfinder.circle.fill")
                .font(.system(size: 38, weight: .light)).foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Focus Lens").font(.system(size: 23, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Circle().fill(model.isEnabled ? Color.mint : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(model.isCheckingPermission ? "Проверяю доступ…" : model.hasPermission ? model.status : "Доступ для этой версии не подтверждён")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                model.setEnabled(!model.isEnabled)
            } label: {
                Label(model.isEnabled ? "Выключить" : "Включить лупу", systemImage: model.isEnabled ? "pause.fill" : "play.fill")
                    .padding(.horizontal, 6).padding(.vertical, 4)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isCheckingPermission)
        }.padding(.horizontal, 28).padding(.vertical, 24)
    }

    private var lensControls: some View {
        @Bindable var prefs = preferences
        return VStack(alignment: .leading, spacing: 20) {
            controlTitle("ФОРМА")
            HStack(spacing: 8) {
                ForEach(LensShape.allCases, id: \.self) { shape in
                    Button { prefs.options.shape = shape } label: {
                        VStack(spacing: 8) {
                            Image(systemName: shape.symbol).font(.system(size: 22, weight: .light))
                            Text(shape.title).font(.system(size: 10))
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(prefs.options.shape == shape ? Color.mint.opacity(0.17) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(prefs.options.shape == shape ? Color.mint : .clear))
                    }.buttonStyle(.plain).accessibilityAddTraits(prefs.options.shape == shape ? [.isSelected] : [])
                }
            }
            valueSlider("Масштаб", value: $prefs.options.zoom, range: 1.5...10, step: 0.5,
                        valueText: String(format: "%.1f×", prefs.options.zoom))
            valueSlider(prefs.options.shape == .circle ? "Диаметр" : "Ширина", value: $prefs.options.width,
                        range: 160...800, step: 20, valueText: "\(Int(prefs.options.width)) pt")
            if prefs.options.shape == .rounded || prefs.options.shape == .rectangle {
                valueSlider("Высота", value: $prefs.options.height, range: 120...600, step: 20,
                            valueText: "\(Int(prefs.options.height)) pt")
            }
            Divider()
            Picker("Положение", selection: $prefs.options.placement) {
                ForEach(LensPlacement.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("В закреплённой линзе всё равно увеличивается область под курсором. При переходе на другой экран линза следует за тобой.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appearanceControls: some View {
        @Bindable var prefs = preferences
        return VStack(alignment: .leading, spacing: 18) {
            Toggle("Затемнять фон", isOn: $prefs.options.spotlight).toggleStyle(.switch)
            if prefs.options.spotlight {
                valueSlider("Затемнение", value: $prefs.options.dimOpacity, range: 0.1...0.8, step: 0.05,
                            valueText: "\(Int(prefs.options.dimOpacity * 100))%")
            }
            Divider()
            Toggle("Обводка линзы", isOn: $prefs.options.border)
            if prefs.options.border {
                Toggle("Мягкое свечение", isOn: $prefs.options.glow)
                valueSlider("Толщина", value: $prefs.options.borderWidth, range: 1...8, step: 1,
                            valueText: "\(Int(prefs.options.borderWidth)) pt")
            }
            Divider()
            Toggle("Показывать указатель внутри", isOn: $prefs.options.cursorVisible)
            if prefs.options.cursorVisible {
                valueSlider("Размер указателя", value: $prefs.options.cursorScale, range: 0.5...3, step: 0.25,
                            valueText: String(format: "%.2g×", prefs.options.cursorScale))
            }
            Toggle("Сглаживать увеличенные пиксели", isOn: $prefs.options.smoothPixels)
            Picker("Частота", selection: $prefs.options.frameRate) {
                Text("30 fps · экономнее").tag(30)
                Text("60 fps · плавнее").tag(60)
            }
        }
    }

    private var shortcutControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Работают во всех приложениях. Нажми на сочетание, чтобы назначить своё.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(LensAction.allCases, id: \.self) { action in
                HStack {
                    Text(action.title).font(.callout)
                    Spacer()
                    Button(preferences.shortcut(for: action).title) {
                        recordError = nil
                        hotKeys.unregister()
                        recording = action
                    }.font(.system(.callout, design: .monospaced)).frame(minWidth: 80)
                }.padding(.vertical, 3)
            }
            if let message = model.shortcutMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            Text("Названия букв соответствуют физическим клавишам английской раскладки.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var permissionControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: model.hasPermission ? "checkmark.shield.fill" : "display")
                .font(.system(size: 34, weight: .light)).foregroundStyle(.mint)
            Text(model.hasPermission ? "Доступ к экрану открыт" : "Проверим доступ к экрану")
                .font(.title3.weight(.semibold))
            Text("macOS называет это разрешение «Запись экрана». Оно нужно, чтобы увеличивать изображение под курсором.")
                .foregroundStyle(.secondary)
            Text("Focus Lens не записывает видео или звук, не сохраняет кадры и не отправляет их в сеть. При выключенной лупе захват останавливается.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Настройки macOS") { model.openPrivacySettings() }
                Button(model.isCheckingPermission ? "Проверяю…" : "Проверить доступ") { model.verifyPermission() }
                    .disabled(model.isCheckingPermission)
            }
            Divider()
            Text("Если переключатель уже включён") .font(.headline)
            Text("Разрешение могло остаться от старой сборки. В настройках macOS удали запись Focus Lens кнопкой «−», затем добавь текущее приложение через «+» и включи доступ. Если macOS попросит — перезапусти приложение.")
                .font(.callout).foregroundStyle(.secondary).lineSpacing(5)
            Button("Показать текущее приложение в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }
        }
    }

    private func recorderSheet(_ action: LensAction) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard").font(.largeTitle).foregroundStyle(.mint)
            Text(action.title).font(.headline)
            Text("Нажми сочетание с ⌃ Control, ⌥ Option или ⌘ Command.")
                .font(.callout).foregroundStyle(.secondary)
            ShortcutRecorder { shortcut in
                guard let shortcut else { recording = nil; return }
                if LensAction.allCases.contains(where: { $0 != action && preferences.shortcut(for: $0) == shortcut }) {
                    recordError = "Это сочетание уже назначено другой команде."
                    return
                }
                let previous = preferences.shortcuts
                preferences.shortcuts[action.rawValue] = shortcut
                let failures = hotKeys.register(preferences: preferences)
                if !failures.isEmpty {
                    preferences.shortcuts = previous
                    hotKeys.unregister()
                    recordError = "Сочетание занято. Попробуй другое."
                    return
                }
                recording = nil
            }.frame(height: 1)
            if let recordError { Text(recordError).foregroundStyle(.orange).font(.caption) }
            Button("Отмена (Esc)") { recording = nil }
        }.padding(32).frame(width: 450)
            .onDisappear { registerShortcuts() }
    }

    private func registerShortcuts() {
        let failures = hotKeys.register(preferences: preferences)
        model.shortcutMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        model.onStateChanged?()
    }

    private func controlTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                             step: Double, valueText: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(valueText).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
}

extension LensAction: Identifiable { var id: String { rawValue } }

struct LensPreview: View {
    var options: LensOptions
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.075, blue: 0.09)
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 5) {
                    ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.2)).frame(width: 5, height: 5) }
                }
                ForEach(0..<6) { row in
                    HStack(spacing: 7) {
                        Text(String(format: "%02d", row + 1)).font(.system(size: 8, design: .monospaced)).foregroundStyle(.white.opacity(0.25))
                        Capsule().fill(row == 2 ? Color.mint.opacity(0.45) : .white.opacity(0.12)).frame(width: CGFloat([112, 80, 138, 95, 125, 65][row]), height: 5)
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            if options.spotlight { Color.black.opacity(options.dimOpacity) }
            PreviewLensShape(shape: options.shape)
                .fill(Color(red: 0.1, green: 0.18, blue: 0.2))
                .frame(width: 148, height: options.shape == .circle || options.shape == .square ? 148 : 108)
                .overlay {
                    VStack(spacing: 8) {
                        Text(String(format: "%.1f", options.zoom)).font(.system(size: 43, weight: .light, design: .rounded))
                        Text("БЛИЖЕ К ДЕТАЛЯМ").font(.system(size: 7, weight: .medium)).tracking(1.2).foregroundStyle(.mint)
                    }.foregroundStyle(.white)
                }
                .overlay {
                    PreviewLensShape(shape: options.shape)
                        .stroke(options.border ? Color.mint.opacity(0.9) : .clear, lineWidth: options.borderWidth)
                }
                .shadow(color: options.glow && options.border ? .mint.opacity(0.23) : .clear, radius: 16)
            Text("ПРЕДПРОСМОТР").font(.system(size: 8, weight: .medium)).tracking(1.6)
                .foregroundStyle(.white.opacity(0.4)).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 15)
        }
    }
}

private struct PreviewLensShape: Shape {
    var shape: LensShape
    nonisolated func path(in rect: CGRect) -> Path {
        switch shape {
        case .circle: Path(ellipseIn: rect)
        case .rounded: Path(roundedRect: rect, cornerRadius: 20)
        case .square, .rectangle: Path(rect)
        }
    }
}
