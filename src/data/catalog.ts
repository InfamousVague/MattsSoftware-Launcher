/// The MattsSoftware catalog — every app I've shipped, with the
/// metadata the launcher renders and the coordinates the backend
/// needs to detect / fetch / install each one.
///
/// Sourced from the live marketing site (mattssoftware.com Home),
/// so names / taglines / descriptions / store links are the real
/// published copy, not invented.
///
/// `channel` + its coordinates drive what the action button does:
///   - github   → look up the latest release on
///                 github.com/InfamousVague/<repo>, install its .dmg
///   - appstore → deep-link to the App Store listing (e.g. Tap, an
///                 Apple Watch app that can't be installed on a Mac)
///   - library  → not an installable app (Base is a design system);
///                 the button opens its docs/source instead
///
/// `bundleName` is the `.app` name in /Applications WITHOUT `.app`
/// (used for installed-detection + Open). Omitted for non-Mac /
/// non-installable entries.

import blipIcon from "../assets/appicons/blip.png";
import espressoIcon from "../assets/appicons/espresso.png";
import dianeIcon from "../assets/appicons/diane.png";
import baseIcon from "../assets/appicons/base.png";
import stashIcon from "../assets/appicons/stash.png";
import portIcon from "../assets/appicons/port.png";
import peepholeIcon from "../assets/appicons/peephole.png";
import quarantineIcon from "../assets/appicons/quarantine.png";
import sentryIcon from "../assets/appicons/sentry.png";
import alfredIcon from "../assets/appicons/alfred.png";
import fishbonesIcon from "../assets/appicons/fishbones.png";
import tapIcon from "../assets/appicons/tap.png";

// Screenshot strips (real captures from the marketing site). Only
// the apps with published screenshots have them; the detail panel
// hides the gallery when the array is empty.
import blipShot1 from "../assets/screenshots/blip/firewall.png";
import blipShot2 from "../assets/screenshots/blip/guard.png";
import blipShot3 from "../assets/screenshots/blip/hops.png";
import vyvShot1 from "../assets/screenshots/vyv/jiggle.png";
import vyvShot2 from "../assets/screenshots/vyv/stats.png";
import vyvShot3 from "../assets/screenshots/vyv/timer.png";
import dianeShot1 from "../assets/screenshots/diane/library.png";
import dianeShot2 from "../assets/screenshots/diane/recorder.png";
import dianeShot3 from "../assets/screenshots/diane/transcription.png";
import stashShot1 from "../assets/screenshots/stash/directory.png";
import stashShot2 from "../assets/screenshots/stash/health.png";
import stashShot3 from "../assets/screenshots/stash/pull-preview.png";

export type Channel = "github" | "appstore" | "dmg" | "library";

export type Category =
  | "Developer Tools"
  | "Privacy & Security"
  | "Utilities"
  | "Learning"
  | "Design";

export interface CatalogApp {
  id: string;
  name: string;
  tagline: string;
  description: string;
  category: Category;
  /// Bundled PNG (imported → Vite gives us a hashed URL string).
  icon: string;
  tags: string[];
  channel: Channel;
  /// `owner/repo` or bare `repo` (owner defaults to InfamousVague).
  githubRepo?: string;
  /// App Store / docs / direct-dmg URL depending on channel.
  url?: string;
  /// `.app` name in /Applications (no `.app`). Absent = not a Mac
  /// app we install (Tap is watchOS; Base is a library).
  bundleName?: string;
  /// One-liner shown on the detail panel's "why it exists" line.
  pitch?: string;
  /// Optional screenshot strip shown in the detail panel.
  screenshots?: string[];
}

export const CATALOG: readonly CatalogApp[] = [
  {
    id: "blip",
    name: "Blip",
    tagline: "Your computer has been talking behind your back.",
    description:
      "Real-time network monitoring with a 3D connection map, smart firewall, DNS blocking, submarine-cable routing, and bandwidth analytics. See exactly where your data goes.",
    category: "Privacy & Security",
    icon: blipIcon,
    tags: ["Network", "Firewall", "Privacy", "macOS"],
    channel: "github",
    githubRepo: "Blip",
    bundleName: "Blip",
    pitch: "Watch every connection your Mac makes, in real time.",
    screenshots: [blipShot1, blipShot2, blipShot3],
  },
  {
    // Vyv was renamed to Espresso (the native-Swift rewrite). The
    // GitHub repo + the installed .app bundle both moved to
    // "Espresso", so installed-detection + release lookup target
    // the new name. Screenshots are the same app's (still under the
    // legacy `screenshots/vyv/` asset dir — same captures, no need
    // to churn the files).
    id: "espresso",
    name: "Espresso",
    tagline: "Your computer wants to sleep. Espresso disagrees.",
    description:
      "Keep-awake utility that prevents your computer from sleeping. Timed sessions, mouse-jiggle simulation, lid-closed override, and a panic hotkey for instant deactivation.",
    category: "Utilities",
    icon: espressoIcon,
    tags: ["Utility", "Menu Bar", "Productivity", "macOS"],
    channel: "github",
    githubRepo: "Espresso",
    bundleName: "Espresso",
    pitch: "Stay awake on your terms.",
    screenshots: [vyvShot1, vyvShot2, vyvShot3],
  },
  {
    id: "diane",
    name: "Diane",
    tagline: "I'm holding in my hand a small tape recorder.",
    description:
      "A skeuomorphic retro voice recorder with live speech-to-text transcription, a cassette-tape library, and dictation mode. Inspired by Special Agent Dale Cooper.",
    category: "Utilities",
    icon: dianeIcon,
    tags: ["Voice", "Transcription", "macOS"],
    channel: "github",
    githubRepo: "Diane",
    bundleName: "Diane",
    pitch: "Dictate, transcribe, and keep a tape library.",
    screenshots: [dianeShot1, dianeShot2, dianeShot3],
  },
  {
    id: "stash",
    name: "Stash",
    tagline: "Your .env files deserve a bodyguard.",
    description:
      "Encrypted environment-variable vault with profiles, team sharing via public-key crypto, a CLI, health monitoring, and an API directory. Never leak a secret again.",
    category: "Developer Tools",
    icon: stashIcon,
    tags: ["Security", "Developer Tools", "macOS", "Encryption"],
    channel: "github",
    githubRepo: "Stash",
    bundleName: "Stash",
    pitch: "An encrypted vault for every project's secrets.",
    screenshots: [stashShot1, stashShot2, stashShot3],
  },
  {
    id: "port",
    name: "Port",
    tagline: "Every open port on your Mac, one click away.",
    description:
      "A native menu-bar port manager: see what's listening, kill or pause the process, forward or NAT-PMP-map it, and watch active connections on a live map — click one to inspect it in Blip.",
    category: "Developer Tools",
    icon: portIcon,
    tags: ["Menu Bar", "Network", "Developer Tools", "macOS"],
    channel: "github",
    githubRepo: "Port",
    bundleName: "Port",
    pitch: "See what's listening — and shut it down.",
  },
  {
    id: "peephole",
    name: "Peephole",
    tagline: "See who's watching.",
    description:
      "A menu-bar sentinel for your camera and microphone: which apps are using them right now, a history of access, and a notification the moment something turns them on.",
    category: "Privacy & Security",
    icon: peepholeIcon,
    tags: ["Menu Bar", "Privacy", "Camera & Mic", "macOS"],
    channel: "github",
    githubRepo: "Peephole",
    bundleName: "Peephole",
    pitch: "Know the instant your camera or mic turns on.",
  },
  {
    id: "quarantine",
    name: "Quarantine",
    tagline: "Trust, but verify every download.",
    description:
      "A menu-bar inspector for ~/Downloads: quarantine origin, Gatekeeper/codesign status, SHA-256, and an optional VirusTotal verdict for every new file, with a notification to vet it.",
    category: "Privacy & Security",
    icon: quarantineIcon,
    tags: ["Menu Bar", "Privacy", "Downloads", "macOS"],
    channel: "github",
    githubRepo: "Quarantine",
    bundleName: "Quarantine",
    pitch: "Vet every file that lands in Downloads.",
  },
  {
    id: "sentry",
    name: "Sentry",
    tagline: "Know the moment something digs in.",
    description:
      "A menu-bar auditor for macOS persistence — LaunchAgents, login items, cron, and shell startup files — with signature checks and alerts when something new or changed appears. Read-only.",
    category: "Privacy & Security",
    icon: sentryIcon,
    tags: ["Menu Bar", "Privacy", "Persistence", "macOS"],
    channel: "github",
    githubRepo: "Sentry",
    bundleName: "Sentry",
    pitch: "Catch persistence the moment it's planted.",
  },
  {
    id: "alfred",
    name: "Alfred",
    tagline: "Reclaim the disk space dev cruft is hoarding.",
    description:
      "A native menu-bar valet that finds safe-to-delete developer cruft — node_modules, Cargo target/, build & test caches, Xcode DerivedData, package-manager caches — sizes it biggest-first, and moves it to the Trash (recoverable).",
    category: "Developer Tools",
    icon: alfredIcon,
    tags: ["Menu Bar", "Disk", "Developer Tools", "macOS"],
    channel: "github",
    githubRepo: "Alfred",
    bundleName: "Alfred",
    pitch: "Take back the gigabytes node_modules forgot about.",
  },
  {
    id: "fishbones",
    name: "Libre",
    tagline: "Turn any technical book into an interactive course.",
    description:
      "Drop in a PDF or EPUB and Libre generates lessons, exercises, and hidden tests. Sixteen languages with one editor, a local AI tutor on your laptop, streak fire that survives weekends, and seventeen themes.",
    category: "Learning",
    icon: fishbonesIcon,
    tags: ["Learning", "Multi-language", "AI Tutor", "Local-first", "macOS"],
    channel: "github",
    githubRepo: "Fishbones",
    bundleName: "Libre",
    pitch: "Any technical book, turned into a real course.",
  },
  {
    id: "tap",
    name: "Tap",
    tagline: "The command remote for your infrastructure.",
    description:
      "Run pre-configured SSH commands on remote servers from your Apple Watch. Works over cellular, supports Siri, and encrypts everything end-to-end.",
    category: "Developer Tools",
    icon: tapIcon,
    tags: ["watchOS", "SSH", "Rust", "Apple Watch"],
    channel: "appstore",
    url: "https://apps.apple.com/app/tap-command-runner/id6762214314",
    pitch: "Your servers, one wrist-tap away.",
  },
  {
    id: "base",
    name: "Base",
    tagline: "Universal design toolkit — monochrome, platform-agnostic.",
    description:
      "70 primitives, 8 design-token categories, dark mode, and zero opinions about your stack. Clean, composable React components that work everywhere — including this launcher.",
    category: "Design",
    icon: baseIcon,
    tags: ["UI Kit", "React", "TypeScript", "Design System"],
    channel: "library",
    url: "https://github.com/InfamousVague",
    pitch: "The design system this launcher is built on.",
  },
];

export const CATEGORIES: readonly Category[] = [
  "Developer Tools",
  "Privacy & Security",
  "Utilities",
  "Learning",
  "Design",
];

/// The slim shape the Rust `app_statuses` / `install_app` commands
/// expect (`catalog.rs::AppRef`). Presentation fields stay on the
/// frontend; the backend only gets what it needs to act.
export interface AppRef {
  id: string;
  name: string;
  bundle_name: string | null;
  channel: Channel;
  github_repo: string | null;
  url: string | null;
}

export function toAppRef(a: CatalogApp): AppRef {
  return {
    id: a.id,
    name: a.name,
    bundle_name: a.bundleName ?? null,
    channel: a.channel,
    github_repo: a.githubRepo ?? null,
    url: a.url ?? null,
  };
}
