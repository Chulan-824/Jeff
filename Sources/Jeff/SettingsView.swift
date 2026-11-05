import SwiftUI

/// Settings shell with a 180pt sidebar; each page owns its content layout.
struct SettingsView: View {
    enum Page: Hashable {
        case service, translateSettings, about
    }
    @State private var page: Page = .service

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: 920, height: 640)
    }

    // MARK: - Sidebar (180pt, grey, grouped labels + icon rows)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupLabel("顾问")
            sidebarRow(icon: "gearshape", title: "使用设置", page: .translateSettings)
            sidebarRow(icon: "cube", title: "服务", page: .service)

            groupLabel("通用")
            sidebarRow(icon: "info.circle", title: "关于", page: .about)

            Spacer()
        }
        .padding(.top, 14)
        .frame(width: 180)
        .background(Color.primary.opacity(0.06))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func sidebarRow(icon: String, title: String, page p: Page) -> some View {
        let selected = page == p
        return Button {
            page = p
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor : Color.clear)
            .foregroundStyle(selected ? .white : .primary)
            .cornerRadius(5)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content pane

    @ViewBuilder
    private var content: some View {
        switch page {
        case .service: ServicePage()
        case .translateSettings: TranslateSettingsPage()
        case .about: AboutPage()
        }
    }
}

// MARK: - 关于页

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("J")
                .font(.system(size: 40, weight: .bold))
            Text("Jeff").font(.title3).bold()
            Text("1.0.0").font(.callout).foregroundStyle(.secondary)
            Text("划词 / 截图 / 剪贴板 → AI 服务 + Jeff")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
