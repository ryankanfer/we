"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import Icon from "./Icon";
import InterlockMark from "./InterlockMark";
import { useSession } from "@/lib/session";

const ITEMS = [
  { href: "/", label: "Today", icon: "today" as const },
  { href: "/plan", label: "Plan", icon: "plan" as const },
  { href: "/home", label: "Home", icon: "home" as const },
  { href: "/profile", label: "Profile", icon: "profile" as const },
];

function useActive() {
  const pathname = usePathname();
  return (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));
}

/** Desktop: a left sidebar. Rendered only at md+ via the parent. */
export function Sidebar() {
  const isActive = useActive();
  const user = useSession((s) => s.user);
  return (
    <aside className="hidden md:flex md:w-60 lg:w-64 shrink-0 flex-col border-r border-line px-5 py-7">
      <Link href="/" className="mb-9 flex items-center gap-2.5 px-2">
        <InterlockMark size={26} overlap="interlocked" />
        <span className="font-serif text-lg tracking-[0.18em]">WE</span>
      </Link>
      <nav className="flex flex-col gap-1">
        {ITEMS.map((it) => {
          const on = isActive(it.href);
          return (
            <Link
              key={it.href}
              href={it.href}
              aria-current={on ? "page" : undefined}
              className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-[15px] transition-colors ${
                on ? "bg-ink text-cream" : "text-faint hover:bg-card hover:text-ink"
              }`}
            >
              <Icon name={it.icon} size={20} />
              {it.label}
            </Link>
          );
        })}
      </nav>
      <div className="mt-auto flex items-center gap-2 px-3 pt-6 text-sm text-faint">
        <span className="grid h-8 w-8 place-items-center rounded-full bg-burgundy-soft text-xs text-burgundy">
          {(user?.name ?? "U").slice(0, 1)}
        </span>
        <span>{user?.name}</span>
      </div>
    </aside>
  );
}

/** Mobile: a fixed bottom bar with a raised center action. Hidden at md+. */
export function BottomBar() {
  const isActive = useActive();
  return (
    <nav
      aria-label="Sections"
      className="fixed inset-x-0 bottom-0 z-30 flex items-end justify-around border-t border-line bg-cream/95 px-2 pb-safe pt-2 backdrop-blur md:hidden"
    >
      {ITEMS.slice(0, 2).map((it) => (
        <Tab key={it.href} {...it} on={isActive(it.href)} />
      ))}
      <button
        aria-label="Add"
        className="mx-1 -mt-5 grid h-14 w-14 shrink-0 place-items-center rounded-full bg-ink text-cream shadow-[0_6px_16px_rgba(39,33,26,0.25)]"
      >
        <Icon name="plus" size={24} />
      </button>
      {ITEMS.slice(2).map((it) => (
        <Tab key={it.href} {...it} on={isActive(it.href)} />
      ))}
    </nav>
  );
}

function Tab({ href, label, icon, on }: { href: string; label: string; icon: "today" | "plan" | "home" | "profile"; on: boolean }) {
  return (
    <Link
      href={href}
      aria-current={on ? "page" : undefined}
      className={`flex w-16 flex-col items-center gap-1 py-1 text-[10px] tracking-wide transition-colors ${
        on ? "text-ink" : "text-faint"
      }`}
    >
      <Icon name={icon} size={22} strokeWidth={on ? 1.9 : 1.5} />
      {label}
    </Link>
  );
}
