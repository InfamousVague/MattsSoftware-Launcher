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
import vyvIcon from "../assets/appicons/vyv.png";
import dianeIcon from "../assets/appicons/diane.png";
import baseIcon from "../assets/appicons/base.png";
import stashIcon from "../assets/appicons/stash.png";
import fishbonesIcon from "../assets/appicons/fishbones.png";
import tapIcon from "../assets/appicons/tap.png";

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
  },
  {
    id: "vyv",
    name: "Vyv",
    tagline: "Your computer wants to sleep. Vyv disagrees.",
    description:
      "Keep-awake utility that prevents your computer from sleeping. Timed sessions, mouse-jiggle simulation, lid-closed override, and a panic hotkey for instant deactivation.",
    category: "Utilities",
    icon: vyvIcon,
    tags: ["Utility", "Cross-Platform", "Productivity"],
    channel: "github",
    githubRepo: "Vyv",
    bundleName: "Vyv",
    pitch: "Stay awake on your terms.",
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
