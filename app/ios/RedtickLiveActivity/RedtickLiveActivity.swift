//
//  RedtickLiveActivity.swift
//  RedtickLiveActivity
//
//  Created by Tomas Sykora, jr. on 25.06.2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

// The single attributes type the `live_activities` plugin drives. ContentState
// stays empty; all dynamic fields live in the App Group, keyed by prefixedKey.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState
  public struct ContentState: Codable, Hashable {}
  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String { "\(id)_\(key)" }
}

// MUST match the App Group enabled on both Runner and this extension target.
private let sharedDefault = UserDefaults(suiteName: "group.cz.syky.redtick")!
private let brandRed = Color(red: 161.0 / 255.0, green: 28.0 / 255.0, blue: 28.0 / 255.0)

private typealias Ctx = ActivityViewContext<LiveActivitiesAppAttributes>

private func laString(_ context: Ctx, _ key: String) -> String {
  sharedDefault.string(forKey: context.attributes.prefixedKey(key)) ?? ""
}
private func laStart(_ context: Ctx) -> Date {
  Date(timeIntervalSince1970: sharedDefault.double(forKey: context.attributes.prefixedKey("startedAt")))
}
private func laTitle(_ context: Ctx) -> String {
  let issue = laString(context, "issue")
  let project = laString(context, "project")
  if issue.isEmpty { return project }
  if project.isEmpty { return issue }
  return "\(issue) · \(project)"
}
private func laClock(_ context: Ctx) -> Text {
  Text(timerInterval: laStart(context)...Date.distantFuture, countsDown: false)
}

private struct HourglassBadge: View {
  var size: CGFloat = 44
  var icon: CGFloat = 20
  var body: some View {
    Image(systemName: "hourglass")
      .font(.system(size: icon, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(brandRed, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

private struct LockScreenView: View {
  let context: Ctx
  var body: some View {
    HStack(spacing: 12) {
      HourglassBadge()
      VStack(alignment: .leading, spacing: 3) {
        Text(laTitle(context))
          .font(.subheadline).fontWeight(.semibold)
          .foregroundStyle(.white).lineLimit(1)
        let desc = laString(context, "description")
        Text(desc.isEmpty ? "Tracking…" : desc)
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
      }
      Spacer(minLength: 8)
      laClock(context)
        .font(.system(.title2, design: .rounded).monospacedDigit())
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .lineLimit(1)
        .layoutPriority(1) // never squeezed by a long title
        .frame(minWidth: 96, alignment: .trailing)
    
    }
    .padding(.vertical, 14)
    .padding(.leading, 16)
    .padding(.trailing, 8)
  }
}

struct RedtickLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      LockScreenView(context: context)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HourglassBadge(size: 36, icon: 16)
        }
        DynamicIslandExpandedRegion(.trailing) {
          laClock(context)
            .font(.system(.title3, design: .rounded).monospacedDigit())
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: 96, alignment: .trailing)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 2) {
            Text(laTitle(context))
              .font(.caption).fontWeight(.semibold)
              .foregroundStyle(.white).lineLimit(1)
            let desc = laString(context, "description")
            if !desc.isEmpty {
              Text(desc)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } compactLeading: {
        Image(systemName: "hourglass").foregroundStyle(brandRed)
      } compactTrailing: {
        laClock(context).monospacedDigit().foregroundStyle(.white).frame(maxWidth: 52)
      } minimal: {
        Image(systemName: "hourglass").foregroundStyle(brandRed)
      }
    }
  }
}
